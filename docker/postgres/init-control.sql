-- Control login for new Postgres volumes.
-- POSTGRES_USER is the registry login. It may create a database and a
-- login per customer. Application queries for a customer connect as
-- tenant_<slug>, not as this role.
ALTER ROLE CURRENT_USER WITH CREATEDB CREATEROLE;
