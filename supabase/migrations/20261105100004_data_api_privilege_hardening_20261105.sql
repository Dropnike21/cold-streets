-- Cold Streets uses Supabase Auth for identity but keeps gameplay data
-- server-authoritative behind the Node API/direct PostgreSQL connection.
-- Direct Data API access to public gameplay objects is opt-in, not default.

REVOKE ALL ON ALL TABLES IN SCHEMA public
  FROM anon, authenticated;

REVOKE ALL ON ALL SEQUENCES IN SCHEMA public
  FROM anon, authenticated, PUBLIC;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public
  FROM anon, authenticated, PUBLIC;

-- Prevent future postgres-owned objects from inheriting legacy Supabase
-- auto-exposure defaults. service_role remains available as an explicit
-- server/admin capability; Flutter must never receive it.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
  ON TABLES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE USAGE, SELECT, UPDATE
  ON SEQUENCES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE
  ON FUNCTIONS FROM anon, authenticated, PUBLIC;

-- supabase_admin's platform-owned default ACL cannot be altered by the postgres
-- role available to project migrations. Cold Streets public gameplay objects
-- must therefore continue to be created/owned by postgres (the current state).
