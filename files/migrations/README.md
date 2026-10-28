# Manual database migrations

These scripts are operator-run migrations for existing deployments. They are
not executed by startup commands. `external-db-existing` skips the Realtime/Supavisor
migration and seed entrypoints.
Auth, Storage and Analytics can still run their own startup migrations; prepare
a compatible database and backups before starting them. Fresh `internal-db` and bootstrapped
`external-db-bootstrap` installations receive these settings from their initialization
scripts and do not need this migration.

## Self-hosted v0.8.3

`20261028-v0.8.3.sql` removes the application database's persisted
`app.settings.jwt_secret` setting and grants the standard API/admin roles, including `supabase_functions_admin`,
USAGE on `extensions`. The JWT expiration setting remains. JWT verification continues to
use the service configuration's JWT secret; the SQL GUC is no longer its storage
location. Upstream: [secret removal](https://github.com/supabase/supabase/pull/45003)
and [webhook grant](https://github.com/supabase/supabase/pull/46526).

Before applying to an existing database, back it up and review custom SQL that
uses `current_setting('app.settings.jwt_secret')`. This query lists candidate
function/procedure names without printing function bodies or secret values:

```sql
SELECT n.nspname AS schema_name, p.proname AS routine_name, p.oid
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE p.prosrc ILIKE '%current_setting%'
  AND p.prosrc ILIKE '%app.settings.jwt_secret%'
ORDER BY 1, 2, 3;
```

Also search application SQL, migration files, jobs and dynamically assembled SQL;
the catalog query cannot find every dependency. Migrate any required secret
lookup to an access-controlled store such as Supabase Vault before removing the
GUC. Do not print or commit secret values while investigating.

Connect explicitly to the intended **application database**, not `_supabase` or
an assumed default. The migration uses `current_database()` with identifier-safe
formatting. Supply the actual provider endpoint, database name and administrative
role; let `psql` prompt for the password or use a protected password file:

```sh
psql --host=YOUR_DB_HOST --port=5432 --username=YOUR_ADMIN_ROLE \
  --dbname=YOUR_APP_DATABASE --password -v ON_ERROR_STOP=1 \
  --file=files/migrations/20261028-v0.8.3.sql
```

The connected role needs authority to alter the application database's settings
(normally database owner or superuser) and to grant USAGE on `extensions`
(normally schema owner, superuser, or a role holding the relevant grant option).
The `supabase_functions_admin` role and `extensions` schema must already exist.
For a managed provider, arrange the equivalent provider-authorized execution if
your administrative login lacks those privileges. The transaction rolls back
both changes on failure; repeated successful execution is safe.

Remove `PGRST_APP_SETTINGS_JWT_SECRET` from the PostgREST service configuration as
part of the same upgrade, and recreate the affected services. Existing database
sessions can retain old settings until they reconnect. After reconnecting, the
following checks report booleans only:

```sql
SELECT EXISTS (
  SELECT 1
  FROM pg_db_role_setting AS s
  CROSS JOIN LATERAL unnest(s.setconfig) AS c(setting)
  WHERE s.setdatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND split_part(c.setting, '=', 1) = 'app.settings.jwt_secret'
) AS database_or_database_role_secret_setting_present;

SELECT nullif(current_setting('app.settings.jwt_secret', true), '') IS NOT NULL
  AS effective_secret_setting_present;

SELECT has_schema_privilege('supabase_functions_admin', 'extensions', 'USAGE')
  AS webhook_extensions_usage;
```

Expect `false`, `false`, `true`. If a secret setting remains, investigate
role-level, database-role-level, connection or service overrides; the migration
intentionally resets only the target database's setting. Do not display the
setting's contents to diagnose it. This manual migration does not run component schema migrations or replace
component-specific upgrade preparation.
