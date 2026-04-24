-- sql/extension_lifecycle.sql
-- Regression tests for CREATE / ALTER EXTENSION UPDATE / DROP EXTENSION cycles.
-- Every version pair must be tested here.

\pset format unaligned
\set ON_ERROR_STOP on

-- ============================================================================
-- Fresh install
-- ============================================================================
DROP EXTENSION IF EXISTS myextension;
CREATE EXTENSION myextension;

SELECT extname, extversion
  FROM pg_extension
 WHERE extname = 'myextension';

-- Verify the extension's objects are accessible
SELECT myext_example('hello') = 'hello' AS example_works;

-- ============================================================================
-- DROP and re-install (idempotency check)
-- ============================================================================
DROP EXTENSION myextension;

SELECT count(*) = 0 AS objects_cleaned_up
  FROM pg_proc
 WHERE proname LIKE 'myext_%';

CREATE EXTENSION myextension;
SELECT myext_example('world') = 'world' AS reinstall_works;

-- ============================================================================
-- Final cleanup
-- ============================================================================
DROP EXTENSION myextension;
