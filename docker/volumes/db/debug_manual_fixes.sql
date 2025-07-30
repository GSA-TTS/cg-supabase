-- Debug and Manual Fixes for Supabase Docker Setup
-- This file contains all the manual SQL commands that were needed to fix issues
-- during the Docker Compose setup process. These should be run if the automatic
-- initialization fails.

\set pguser `echo "$POSTGRES_USER"`

-- ============================================================================
-- 1. CREATE MISSING DATABASES
-- ============================================================================

-- Create _supabase database (if not exists)
SELECT 'CREATE DATABASE _supabase'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '_supabase')\gexec

-- ============================================================================
-- 2. CREATE MISSING SCHEMAS  
-- ============================================================================

-- Create auth schema with proper permissions
DROP SCHEMA IF EXISTS auth CASCADE;
CREATE SCHEMA auth;
GRANT USAGE ON SCHEMA auth TO postgres, anon, authenticated, service_role, supabase_auth_admin;
GRANT CREATE ON SCHEMA auth TO supabase_auth_admin;

-- Create realtime schema with proper permissions
CREATE SCHEMA IF NOT EXISTS realtime;
GRANT USAGE ON SCHEMA realtime TO postgres, anon, authenticated, service_role;

-- Create _realtime schema (required by realtime service)
CREATE SCHEMA IF NOT EXISTS _realtime;
GRANT USAGE ON SCHEMA _realtime TO postgres, anon, authenticated, service_role;

-- Create _analytics schema in _supabase database
\c _supabase
CREATE SCHEMA IF NOT EXISTS _analytics;
GRANT USAGE ON SCHEMA _analytics TO postgres, anon, authenticated, service_role;

-- Switch back to main database
\c postgres

-- ============================================================================
-- 3. FIX USER PASSWORDS (for authentication issues)
-- ============================================================================

-- Reset passwords for Supabase service users
-- Note: These should match your .env file values
ALTER USER supabase_auth_admin PASSWORD 'your-super-secret-and-long-postgres-password';
ALTER USER supabase_storage_admin PASSWORD 'your-super-secret-and-long-postgres-password';
ALTER USER supabase_read_only_user PASSWORD 'your-super-secret-and-long-postgres-password';
ALTER USER postgres PASSWORD 'your-super-secret-and-long-postgres-password';

-- ============================================================================
-- 4. CREATE ANALYTICS TABLES (for Logflare/Analytics)
-- ============================================================================

\c _supabase

-- Create basic analytics tables if they don't exist
CREATE TABLE IF NOT EXISTS _analytics.logs (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    level TEXT,
    message TEXT,
    metadata JSONB
);

-- Grant permissions on analytics tables
GRANT ALL ON SCHEMA _analytics TO postgres;
GRANT ALL ON ALL TABLES IN SCHEMA _analytics TO postgres;
GRANT ALL ON ALL SEQUENCES IN SCHEMA _analytics TO postgres;

-- Switch back to main database
\c postgres

-- ============================================================================
-- 5. VERIFY SETUP
-- ============================================================================

-- Show databases
\l

-- Show schemas in main database
\dn

-- Show users and their attributes
\du

-- ============================================================================
-- NOTES:
-- ============================================================================
-- 1. Run this file manually if containers fail to start
-- 2. Update passwords to match your .env file
-- 3. This file consolidates all manual fixes that were needed
-- 4. Regular initialization should handle most of this automatically
