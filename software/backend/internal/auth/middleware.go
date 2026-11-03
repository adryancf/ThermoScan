package auth

import (
	"context"
	"net/http"
	"strings"
	"time"

	"backend/internal/db"
	"backend/internal/httpjson"

	"github.com/jackc/pgx/v5/pgtype"
)

type contextKey string

const principalContextKey contextKey = "auth_principal"

type Principal struct {
	ID                 pgtype.UUID
	CompanyID          pgtype.UUID
	Name               string
	Email              string
	Role               string
	IsActive           bool
	IsDefaultManager   bool
	MustChangePassword bool
	CreatedAt          time.Time
	UpdatedAt          time.Time
}

func (p Principal) ToDTO() UserDTO {
	return mapUserRowToDTO(
		p.ID,
		p.CompanyID,
		p.Name,
		p.Email,
		p.Role,
		p.IsActive,
		p.IsDefaultManager,
		p.MustChangePassword,
		p.CreatedAt,
		p.UpdatedAt,
	)
}

func PrincipalFromContext(ctx context.Context) (Principal, bool) {
	p, ok := ctx.Value(principalContextKey).(Principal)
	return p, ok
}

func Authenticate(queries *db.Queries, tokens *TokenManager) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
			if authHeader == "" {
				httpjson.WriteError(w, http.StatusUnauthorized, "missing authorization header", "UNAUTHORIZED")
				return
			}

			scheme, tokenStr, ok := strings.Cut(authHeader, " ")
			if !ok || !strings.EqualFold(scheme, "Bearer") || strings.TrimSpace(tokenStr) == "" {
				httpjson.WriteError(w, http.StatusUnauthorized, "invalid authorization header format", "UNAUTHORIZED")
				return
			}

			rawToken := strings.TrimSpace(tokenStr)
			if strings.HasPrefix(rawToken, "dev_sec_") {
				mod, err := queries.GetModuleByDeviceToken(r.Context(), pgtype.Text{String: rawToken, Valid: true})
				if err != nil || !mod.IsActive {
					httpjson.WriteError(w, http.StatusUnauthorized, "invalid or inactive device token", "UNAUTHORIZED")
					return
				}
				principal := Principal{
					ID:                 mod.ID,
					CompanyID:          mod.CompanyID,
					Name:               mod.Name,
					Email:              "device@" + mod.MacAddress.String(),
					Role:               RoleTechnician,
					IsActive:           mod.IsActive,
					IsDefaultManager:   false,
					MustChangePassword: false,
					CreatedAt:          mod.CreatedAt,
					UpdatedAt:          mod.UpdatedAt,
				}
				ctx := context.WithValue(r.Context(), principalContextKey, principal)
				next.ServeHTTP(w, r.WithContext(ctx))
				return
			}

			_, userID, sessionID, err := tokens.ParseAccessToken(rawToken)
			if err != nil {
				httpjson.WriteError(w, http.StatusUnauthorized, "invalid or expired access token", "UNAUTHORIZED")
				return
			}

			u, err := queries.GetActiveAuthSessionWithUserByID(r.Context(), db.GetActiveAuthSessionWithUserByIDParams{
				ID:     sessionID,
				UserID: userID,
			})
			if err != nil || !u.IsActive || !u.CompanyIsActive {
				httpjson.WriteError(w, http.StatusUnauthorized, "session is revoked, expired, or account is inactive", "UNAUTHORIZED")
				return
			}

			principal := Principal{
				ID:                 u.ID,
				CompanyID:          u.CompanyID,
				Name:               u.Name,
				Email:              u.Email,
				Role:               u.Role,
				IsActive:           u.IsActive,
				IsDefaultManager:   u.IsDefaultManager,
				MustChangePassword: u.MustChangePassword,
				CreatedAt:          u.CreatedAt,
				UpdatedAt:          u.UpdatedAt,
			}

			ctx := context.WithValue(r.Context(), principalContextKey, principal)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func RequirePasswordChanged(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		principal, ok := PrincipalFromContext(r.Context())
		if !ok {
			httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
			return
		}

		if principal.MustChangePassword {
			httpjson.WriteError(w, http.StatusForbidden, "password change is required before accessing this resource", "PASSWORD_CHANGE_REQUIRED")
			return
		}

		next.ServeHTTP(w, r)
	})
}

func RequireRoles(allowedRoles ...string) func(http.Handler) http.Handler {
	allowed := make(map[string]struct{}, len(allowedRoles))
	for _, role := range allowedRoles {
		allowed[role] = struct{}{}
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			principal, ok := PrincipalFromContext(r.Context())
			if !ok {
				httpjson.WriteError(w, http.StatusUnauthorized, "authentication required", "UNAUTHORIZED")
				return
			}

			if _, ok := allowed[principal.Role]; !ok {
				httpjson.WriteError(w, http.StatusForbidden, "insufficient permissions", "FORBIDDEN")
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}
