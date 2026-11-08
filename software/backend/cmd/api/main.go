package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"backend/internal/auth"
	"backend/internal/bootstrap"
	"backend/internal/company"
	"backend/internal/config"
	"backend/internal/db"
	"backend/internal/httpapi"
	"backend/internal/module"
	"backend/internal/user"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	resetAdmin := flag.Bool("reset-admin", false, "Reset the system_admin password to a new temporary password and exit")
	flag.Parse()

	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))

	cfg, err := config.Load()
	if err != nil {
		logger.Error("failed to load configuration", slog.String("error", err.Error()))
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	startupCtx, cancelStartup := context.WithTimeout(ctx, 15*time.Second)
	defer cancelStartup()

	pool, err := pgxpool.New(startupCtx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("failed to create database pool", slog.String("error", err.Error()))
		os.Exit(1)
	}
	defer pool.Close()

	if err := pool.Ping(startupCtx); err != nil {
		logger.Error("failed to ping database", slog.String("error", err.Error()))
		os.Exit(1)
	}

	if err := bootstrap.RunMigrations(startupCtx, pool, logger); err != nil {
		logger.Error("failed to run database migrations", slog.String("error", err.Error()))
		os.Exit(1)
	}

	queries := db.New(pool)

	if _, err := bootstrap.EnsureSystemAdmin(startupCtx, queries, cfg.BootstrapAdminName, cfg.BootstrapAdminEmail, logger); err != nil {
		logger.Error("failed to run system_admin bootstrap", slog.String("error", err.Error()))
		os.Exit(1)
	}

	if *resetAdmin {
		if _, err := bootstrap.ResetSystemAdminPassword(startupCtx, queries, cfg.BootstrapAdminEmail, logger); err != nil {
			logger.Error("failed to reset system_admin password", slog.String("error", err.Error()))
			os.Exit(1)
		}
		return
	}

	tokens := auth.NewTokenManager(cfg.JWTSecret)

	authService := auth.NewService(pool, tokens)
	authHandler := auth.NewHandler(authService, queries, tokens)

	companyService := company.NewService(pool)
	companyHandler := company.NewHandler(companyService, queries, tokens)

	userService := user.NewService(pool)
	userHandler := user.NewHandler(userService, queries, tokens)

	moduleService := module.NewService(pool)
	moduleHandler := module.NewHandler(moduleService, queries, tokens)

	router := httpapi.NewRouter(httpapi.Dependencies{
		Pinger:         pool,
		AuthHandler:    authHandler,
		CompanyHandler: companyHandler,
		UserHandler:    userHandler,
		ModuleHandler:  moduleHandler,
	})

	srv := &http.Server{
		Addr:              ":" + cfg.APIPort,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	go func() {
		logger.Info("starting ThermoScan API server", slog.String("port", cfg.APIPort))
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("HTTP server error", slog.String("error", err.Error()))
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down ThermoScan API server")

	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancelShutdown()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", slog.String("error", err.Error()))
	}
}
