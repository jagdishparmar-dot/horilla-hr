-- Control login for new Postgres volumes.
-- POSTGRES_USER is the registry login. It may create a database and a
-- login per customer. Application queries for a customer connect as
-- tenant_<slug>, not as this role.
ALTER ROLE CURRENT_USER WITH CREATEDB CREATEROLE;

-- This script runs connected to the database named by POSTGRES_DB, which is
-- the control database on a new volume. PUBLIC can CONNECT by default, and
-- every tenant role is a member of PUBLIC, so remove that grant. The control
-- login keeps CONNECT. Existing volumes are locked by lock_control_connect.
DO $$
BEGIN
  EXECUTE format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', current_database());
  EXECUTE format(
    'GRANT CONNECT ON DATABASE %I TO %I',
    current_database(),
    current_user
  );
END
$$;
