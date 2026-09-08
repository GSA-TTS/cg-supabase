-- ---------------------------------------------------------------------------
-- db_schema_init.sql  —  Postgres schema prep for Supabase on cloud.gov
--
-- Terraform loads this SQL into local.db_schema_init_sql in supabase.tf and
-- pg-meta executes it at container startup. All statements are idempotent.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- ---------------------------------------------------------------------------
-- Roles required by Supabase services
-- (pgjwt is not available on managed RDS — GoTrue signs JWTs natively.)
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
-- GoTrue: pre-create auth.schema_migrations
--
-- Cloud Foundry RDS service-key users cannot SET search_path globally the
-- way a local Postgres superuser can, which causes GoTrue's Pop v6 migrator
-- to fail when it tries to create this table.  Pre-creating it here (in the
-- correct schema) unblocks GoTrue's startup migration run.
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
--  pre-creating the table is harmless and prevents errors if it is enabled.)
-- ---------------------------------------------------------------------------
SET search_path TO _realtime;
CREATE TABLE IF NOT EXISTS schema_migrations (
  version  BIGINT NOT NULL,
  inserted_at TIMESTAMP(0) DEFAULT NOW(),
  PRIMARY KEY (version)
);
RESET search_path;

SELECT 'DB schema init complete.' AS status;
