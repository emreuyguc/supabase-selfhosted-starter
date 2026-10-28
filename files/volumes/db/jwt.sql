\set jwt_exp `echo "$JWT_EXP"`
\set db_name `echo "${POSTGRES_DB:-postgres}"`

ALTER DATABASE :db_name SET "app.settings.jwt_exp" TO :'jwt_exp';
