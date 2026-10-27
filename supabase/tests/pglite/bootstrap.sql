-- Bootstrap para o ambiente de testes local (PGlite / PostgreSQL real).
--
-- Emula o ambiente Supabase que as migrations pressupõem:
--   * schema `auth` com a tabela `auth.users` e as funções `auth.uid()`/`auth.role()`;
--   * roles `anon`, `authenticated` e `service_role`;
--   * as funções da extensão `pgcrypto` usadas pelo schema (o build do PGlite
--     não embarca o arquivo de controle da extensão; no Supabase a extensão é
--     criada pela migration 20250127000000).
--
-- Este arquivo NÃO faz parte das migrations do projeto: é usado apenas pelo
-- runner de testes `supabase/tests/pglite/run.mjs`.

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS extensions;

-- Funções equivalentes ao pgcrypto (usadas por auth.users e pelo seed).
-- No Supabase, o pgcrypto é instalado no schema `extensions` (que faz parte
-- do search_path padrão do banco). O runner reproduz esse layout para
-- detectar funções que dependem de pgcrypto com search_path restrito.
CREATE OR REPLACE FUNCTION extensions.gen_random_bytes(p_bytes integer)
RETURNS bytea
LANGUAGE sql
VOLATILE
AS $$
  SELECT substr(
    (
      md5(random()::text) || md5(random()::text) ||
      md5(random()::text) || md5(random()::text)
    )::bytea,
    1,
    p_bytes
  );
$$;

CREATE OR REPLACE FUNCTION extensions.digest(p_data text, p_type text)
RETURNS bytea
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT sha256(convert_to(p_data, 'utf8'));
$$;

CREATE OR REPLACE FUNCTION extensions.crypt(p_password text, p_salt text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 'pbkdf2$' || p_salt || '$' || md5(p_password);
$$;

CREATE OR REPLACE FUNCTION extensions.gen_salt(p_type text)
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
  SELECT md5(random()::text);
$$;

-- Search_path padrão do Supabase: "$user", public, extensions.
SET search_path TO "$user", public, extensions;

-- Tabela mínima compatível com o schema de auth.users do Supabase.
CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  instance_id uuid,
  email text,
  phone text,
  encrypted_password text,
  email_confirmed_at timestamptz,
  phone_confirmed_at timestamptz,
  raw_app_meta_data jsonb,
  raw_user_meta_data jsonb,
  is_super_admin boolean,
  role text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- auth.uid() e auth.role(): mesma semântica do GoTrue do Supabase.
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.sub', true), ''),
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.role', true), ''),
    (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text;
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
END $$;

-- Concessões padrão criadas pela plataforma Supabase no provisionamento do
-- projeto. Elas existem no catálogo (pg_default_acl) e valem para TODA tabela
-- nova criada no schema public. O runner reproduz esse estado para provar que
-- a migration 20250127000004 as neutraliza.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

-- Papel interno da plataforma Supabase. O role postgres NAO tem permissao
-- para alterar os default privileges do supabase_admin (documentacao oficial:
-- https://supabase.com/kb/troubleshooting/cant-change-the-default-privileges-of-supabase-admin-in-the-public-schema).
-- O runner reproduz esse estado para provar que a migration 00004 preserva
-- essas entradas (apenas reportando-as) e normaliza apenas as do postgres.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    CREATE ROLE supabase_admin NOLOGIN NOINHERIT CREATEROLE CREATEDB;
  END IF;
END $$;

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public
  GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
