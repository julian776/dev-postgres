-- setup-roles.sql — Recommended PostgreSQL role setup for dev-postgres
--
-- This script creates two roles:
--   1. A read-only role for production/staging connections
--   2. A read-write role for development connections
--
-- Adjust database names, schema names, and passwords as needed.

-- =============================================================================
-- Read-only role (for prod/staging connections)
-- =============================================================================

-- Create the role
CREATE ROLE readonly_user WITH LOGIN PASSWORD 'CHANGE_ME';

-- Grant connect
GRANT CONNECT ON DATABASE myapp_prod TO readonly_user;

-- Grant schema usage
GRANT USAGE ON SCHEMA public TO readonly_user;
GRANT USAGE ON SCHEMA analytics TO readonly_user;

-- Grant SELECT on all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO readonly_user;

-- Auto-grant SELECT on future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO readonly_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics
  GRANT SELECT ON TABLES TO readonly_user;

-- Grant SELECT on sequences (needed for some queries)
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO readonly_user;

-- =============================================================================
-- Read-write role (for dev connections)
-- =============================================================================

-- Create the role
CREATE ROLE dev_user WITH LOGIN PASSWORD 'CHANGE_ME';

-- Grant connect
GRANT CONNECT ON DATABASE myapp_dev TO dev_user;

-- Grant full schema access
GRANT USAGE, CREATE ON SCHEMA public TO dev_user;

-- Grant DML on all existing tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO dev_user;

-- Auto-grant DML on future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO dev_user;

-- Grant sequence usage (needed for INSERT with serial/identity columns)
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO dev_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO dev_user;

-- =============================================================================
-- Optional: Set statement timeout at role level (additional safety)
-- =============================================================================

ALTER ROLE readonly_user SET statement_timeout = '30s';
ALTER ROLE dev_user SET statement_timeout = '60s';
