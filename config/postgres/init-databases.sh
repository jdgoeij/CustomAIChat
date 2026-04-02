#!/bin/bash
# =============================================================================
# Initialize additional PostgreSQL databases on first run
# This script runs automatically when the postgres container starts fresh.
# =============================================================================
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE langfuse'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'langfuse')\gexec
EOSQL

echo "Additional databases initialized."
