\set app_db `printf '%s' "$POSTGRES_DB"`
\set db_owner `printf '%s' "$POSTGRES_DB_OWNER"`

SELECT format('CREATE DATABASE %I WITH OWNER %I', :'app_db', :'db_owner')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'app_db')\gexec

SELECT format('CREATE DATABASE %I WITH OWNER %I', '_supabase', :'db_owner')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '_supabase')\gexec
