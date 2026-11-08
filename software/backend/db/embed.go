package db

import "embed"

// MigrationsFS embeds all SQL migration files located in software/backend/db/migrations.
//
//go:embed migrations/*.sql
var MigrationsFS embed.FS
