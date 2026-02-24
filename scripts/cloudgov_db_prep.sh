#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cloudgov_db_prep.sh  —  One-time Postgres schema prep for Supabase on cloud.gov
#
# Run this AFTER terraform apply (services will be deployed but apps may be
# crash-looping until the schema exists). Once this script completes,
# restart the affected apps:
#   cf restart supabase-auth
#   cf restart supabase-storage
#
# Prerequisites:
#   - cf CLI logged in and targeting gsa-tts-oros-sorndashboard / supabase
#       cf login -a https://api.fr.cloud.gov --sso
#       cf target -o gsa-tts-oros-sorndashboard -s supabase
#   - cf connect-to-service plugin installed:
#       cf install-plugin -r CF-Community "connect-to-service"
#   - psql in PATH
# ---------------------------------------------------------------------------
set -euo pipefail

DB_SERVICE="supabase-db"
KEY_NAME="meta"

echo "==> Fetching credentials for service: ${DB_SERVICE} (key: ${KEY_NAME})"

KEY_JSON=$(cf service-key "${DB_SERVICE}" "${KEY_NAME}" 2>/dev/null | tail -n +3)
DB_HOST=$(echo "$KEY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host'])")
DB_PORT=$(echo "$KEY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['port'])")
DB_NAME=$(echo "$KEY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['db_name'])")
DB_USER=$(echo "$KEY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['username'])")
DB_PASS=$(echo "$KEY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['password'])")

export PGPASSWORD="$DB_PASS"
PSQL="psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"

echo "==> Connecting to ${DB_HOST}:${DB_PORT}/${DB_NAME} as ${DB_USER}"

$PSQL <<'EOSQL'
-- ---------------------------------------------------------------------------
-- Extensions (install as many as the managed RDS allows)
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- ---------------------------------------------------------------------------
-- Roles needed by Supabase
-- pgjwt is not available on managed RDS — GoTrue signs JWTs directly instead.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    CREATE ROLE supabase_admin NOLOGIN;
  END IF;
END
$$;

-- Grant roles to the RDS app user so PostgREST can SET ROLE
DO $$
DECLARE
  app_user text := current_user;
BEGIN
  EXECUTE format('GRANT anon TO %I', app_user);
  EXECUTE format('GRANT authenticated TO %I', app_user);
  EXECUTE format('GRANT service_role TO %I', app_user);
  EXECUTE format('GRANT supabase_admin TO %I', app_user);
END
$$;

-- ---------------------------------------------------------------------------
-- Schemas
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS _realtime;
CREATE SCHEMA IF NOT EXISTS extensions;

-- Permissions on public
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- Permissions on auth
GRANT USAGE ON SCHEMA auth TO service_role;

-- Permissions on storage
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- GoTrue: pre-create auth.schema_migrations (Pop v6 / pgx v4 workaround)
-- Required because Cloud Foundry RDS users cannot SET search_path during
-- the CREATE TABLE statement the way local Postgres superusers can.
-- ---------------------------------------------------------------------------
SET search_path TO auth;
CREATE TABLE IF NOT EXISTS schema_migrations (
  version VARCHAR(14) NOT NULL,
  PRIMARY KEY (version)
);
CREATE UNIQUE INDEX IF NOT EXISTS schema_migrations_version_idx ON schema_migrations (version);
RESET search_path;

-- ---------------------------------------------------------------------------
-- Realtime: pre-create _realtime.schema_migrations
-- (Realtime is disabled on cloud.gov due to IPv6 incompatibility, but
--  pre-creating the table prevents errors if it is ever enabled.)
-- ---------------------------------------------------------------------------
SET search_path TO _realtime;
CREATE TABLE IF NOT EXISTS schema_migrations (
  version  BIGINT NOT NULL,
  inserted_at TIMESTAMP(0) DEFAULT NOW(),
  PRIMARY KEY (version)
);
RESET search_path;

SELECT 'DB prep complete. Restart Supabase apps now.' AS status;
EOSQL

echo ""
echo "==> Done. Now restart apps:"
echo "    cf restart supabase-auth"
echo "    cf restart supabase-storage"
