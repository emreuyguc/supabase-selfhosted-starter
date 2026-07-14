\set app_db `printf '%s' "$POSTGRES_DB"`
\set jwt_secret `printf '%s' "$JWT_SECRET"`
\set jwt_exp `printf '%s' "$JWT_EXP"`

ALTER DATABASE :app_db SET "app.settings.jwt_secret" TO :'jwt_secret';
ALTER DATABASE :app_db SET "app.settings.jwt_exp" TO :'jwt_exp';
