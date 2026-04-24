-- sql/doc_examples.sql
-- Regression tests for SQL examples in user documentation.
-- Generated and maintained by the doc-example-tester skill.
-- Every -- Example: block in README.md and doc/*.md must have a test here.

\pset format unaligned
\set ON_ERROR_STOP on

CREATE EXTENSION IF NOT EXISTS myextension;

-- ============================================================================
-- README.md: Quick Start (~line 30)
-- ============================================================================
SELECT myext_example('hello world');

DROP EXTENSION myextension;
