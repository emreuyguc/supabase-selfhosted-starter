-- Enable Supabase GraphQL endpoint support.
-- This is intentionally idempotent for fresh database initialization.
CREATE SCHEMA IF NOT EXISTS graphql;
CREATE SCHEMA IF NOT EXISTS graphql_public;

CREATE EXTENSION IF NOT EXISTS pg_graphql WITH SCHEMA graphql;

GRANT USAGE ON SCHEMA graphql TO postgres, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA graphql_public TO postgres, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION graphql_public.graphql(
  "operationName" text DEFAULT NULL,
  query text DEFAULT NULL,
  variables jsonb DEFAULT NULL,
  extensions jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $$
  SELECT graphql.resolve(query, variables, "operationName", extensions);
$$;

GRANT EXECUTE ON FUNCTION graphql_public.graphql(text, text, jsonb, jsonb) TO anon, authenticated, service_role;
