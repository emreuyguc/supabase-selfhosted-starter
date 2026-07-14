\connect _supabase

CREATE SCHEMA IF NOT EXISTS _analytics AUTHORIZATION supabase_admin;
ALTER SCHEMA _analytics OWNER TO supabase_admin;

CREATE SCHEMA IF NOT EXISTS _supavisor AUTHORIZATION supabase_admin;
ALTER SCHEMA _supavisor OWNER TO supabase_admin;
