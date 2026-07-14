\set pgpass `printf '%s' "$POSTGRES_PASSWORD"`

ALTER ROLE postgres WITH PASSWORD :'pgpass';
ALTER ROLE supabase_admin WITH PASSWORD :'pgpass';
ALTER ROLE authenticator WITH PASSWORD :'pgpass';
ALTER ROLE pgbouncer WITH PASSWORD :'pgpass';
ALTER ROLE supabase_auth_admin WITH PASSWORD :'pgpass';
ALTER ROLE supabase_functions_admin WITH PASSWORD :'pgpass';
ALTER ROLE supabase_storage_admin WITH PASSWORD :'pgpass';
