-- Migration: registra as permissões (GRANTs) do role authenticated e revisa o RLS
--
-- Contexto
-- --------
-- As tabelas e funções do Agenda Flow foram criadas manualmente no SQL Editor
-- do Supabase, o que não aplica automaticamente os GRANTs padrão do projeto
-- para o role `authenticated`. Sem GRANT de SELECT em public.establishments e
-- public.establishment_members, a API PostgREST respondia com
-- "permission denied for table establishments" mesmo com RLS ativo.
--
-- Princípio do menor privilégio adotado
-- -------------------------------------
-- O role `authenticated` fica com ACESSO SOMENTE LEITURA às tabelas de dados:
--   * SELECT é limitado pelas políticas RLS (o usuário só enxerga o próprio
--     tenant);
--   * NENHUMA escrita direta (INSERT/UPDATE/DELETE) é concedida, mesmo
--     existindo políticas para elas. As políticas de escrita continuam no
--     banco como segunda camada de defesa, mas o acesso real às regras de
--     negócio acontece exclusivamente por RPC SECURITY DEFINER, que aplicam
--     as invariantes de forma atômica (vínculo de proprietário, gestão de
--     papéis, hash do token de convite).
--   * O role `anon` não recebe nenhum privilégio sobre as tabelas do projeto.
--
-- Concessões automáticas (ALTER DEFAULT PRIVILEGES) NÃO são usadas: cada nova
-- tabela deve receber, em uma migration própria, apenas as permissões
-- necessárias à funcionalidade correspondente.
--
-- A matriz de EXECUTE das funções foi definida na migration
-- 20250127000003, no mesmo ponto em que cada função é criada (sem janela de
-- exposição). Aqui ela é apenas VERIFICADA.
--
-- Esta migration é idempotente, não destrutiva e não desabilita RLS.

--------------------------------------------------------------------------------
-- 1. Schema public: ninguém cria objetos, todos podem usar o schema
--------------------------------------------------------------------------------
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM anon;
REVOKE CREATE ON SCHEMA public FROM authenticated;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

--------------------------------------------------------------------------------
-- 2. RLS ativo em todas as tabelas de dados (revisão do isolamento multi-tenant)
--------------------------------------------------------------------------------
-- Habilitar RLS é idempotente e não remove nenhuma política existente.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.establishments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.establishment_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.establishment_invitations ENABLE ROW LEVEL SECURITY;

--------------------------------------------------------------------------------
-- 3. Tabelas: normaliza o estado e concede o mínimo para `authenticated`
--------------------------------------------------------------------------------
-- Normaliza primeiro: remove (eventuais) concessões amplas herdadas de
-- execuções manuais no SQL Editor ou de GRANTs padrão do projeto.
REVOKE ALL PRIVILEGES ON TABLE public.profiles FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.profiles FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.establishments FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.establishments FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.establishment_members FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.establishment_members FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.member_permissions FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.member_permissions FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.establishment_invitations FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.establishment_invitations FROM authenticated;

-- Acesso de leitura (limitado pelo RLS):
--   profiles               → o próprio perfil e o de colegas do mesmo tenant
--   establishments         → os estabelecimentos em que o usuário é membro
--   establishment_members  → o próprio vínculo e o dos colegas do tenant
--   member_permissions     → as permissões dos membros do próprio tenant
--   establishment_invitations → apenas convites de establishments que o
--                            usuário administra (policy owner_or_manager)
GRANT SELECT ON public.profiles TO authenticated;
GRANT SELECT ON public.establishments TO authenticated;
GRANT SELECT ON public.establishment_members TO authenticated;
GRANT SELECT ON public.member_permissions TO authenticated;
GRANT SELECT ON public.establishment_invitations TO authenticated;

--------------------------------------------------------------------------------
-- 4. Privilégios padrão já existentes (pg_default_acl)
--------------------------------------------------------------------------------
-- 4. Privilégios padrão já existentes (pg_default_acl)
--------------------------------------------------------------------------------
-- Remover os ALTER DEFAULT PRIVILEGES desta migration NÃO elimina as
-- concessões automáticas que já existem no catálogo (pg_default_acl), como as
-- criadas pela plataforma Supabase ao provisionar o projeto. Elas continuam
-- valendo para TODA tabela nova criada no schema public.
--
-- A política adotada é: nenhuma concessão automática para o role da API.
-- Cada nova tabela deve receber, em uma migration própria, apenas as
-- permissões necessárias à funcionalidade correspondente.
--
-- DISTINÇÃO IMPORTANTE (comportamento verificado em PostgreSQL real)
--
--   Tabelas e sequences: as concessões padrão da plataforma Supabase estão no
--   catálogo como entradas PER-SCHEMA (defaclnamespace = public) e existem
--   para DOIS proprietários: supabase_admin (papel interno da plataforma) e
--   postgres (papel que cria os objetos do Agenda Flow).
--
--   O role postgres NÃO TEM PERMISSÃO para alterar os default privileges do
--   supabase_admin (documentação oficial do Supabase:
--   https://supabase.com/kb/troubleshooting/cant-change-the-default-privileges-of-supabase_admin-in-the-public-schema).
--   Portanto estas entradas são PRESERVADAS e apenas REPORTADAS.
--
--   Já as entradas de postgres são de responsabilidade do projeto e são
--   removidas integralmente (anon, authenticated e PUBLIC) — incluindo
--   TRUNCATE, REFERENCES, TRIGGER e MAINTAIN, que vêm no ALL da plataforma.
--
--   Funções: o EXECUTE para PUBLIC NÃO é uma entrada de pg_default_acl, e
--   sim o DEFAULT GLOBAL DO SISTEMA (implícito, materializado por
--   acldefault('f', owner)). Um REVOKE per-schema é um NO-OP silencioso:
--   não remove o privilégio e nem chega a gravar entrada no catálogo.
--   A única forma de alterá-lo é a forma GLOBAL:
--
--       ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
--
--   Esse REVOKE global é aplicado somente ao role dono dos objetos do
--   projeto (o role que executa a migration e o role postgres). Os
--   privilégios padrão dos roles gerenciados pela plataforma Supabase
--   (supabase_admin, supabase_auth_admin, supabase_storage_admin,
--   authenticator, ...) NÃO são alterados — sem necessidade comprovada.
--
--   Consequência aceita e documentada: funções criadas futuramente pelo role
--   postgres, em qualquer schema, passam a exigir GRANT explícito de EXECUTE
--   (o que já era o caso na prática, pois o PostgREST sempre exige GRANT
--   para o role authenticated). As extensões não são afetadas: os objetos de
--   uma extensão recebem seus próprios privilégios, não os default do role.
--
--   As default privileges do role service_role são preservadas (o papel
--   ignora RLS e é usado pela plataforma), assim como as de schemas privados.
DO $$
DECLARE
  v_previous_search_path text;
BEGIN
  --------------------------------------------------------------------------
  -- 4.1 Tabelas e sequences: as entradas per-schema do schema public são
  --     removidas para PUBLIC, anon e authenticated — SOMENTE para o role que
  --     executa a migration (e para o postgres, quando aplicável). As
  --     entradas de supabase_admin não são tocadas.
  --------------------------------------------------------------------------
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC';
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon';
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM authenticated';
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC';
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon';
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM authenticated';

  -- O role postgres é o dono habitual dos objetos do projeto (é quem cria as
  -- tabelas e funções). Só ele recebe a alteração; nenhum role da
  -- plataforma Supabase é tocado.
  IF current_user <> 'postgres'::regrole::text
     AND pg_has_role(current_user, 'postgres', 'MEMBER') THEN
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC';
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon';
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM authenticated';
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC';
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon';
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM authenticated';
  END IF;

  --------------------------------------------------------------------------
  -- 4.2 Funções: o default global (EXECUTE para PUBLIC) só é removido pela
  --     forma global. Per-schema não tem efeito sobre o default do sistema.
  --------------------------------------------------------------------------
  EXECUTE 'ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC';

  IF current_user <> 'postgres'::regrole::text
     AND pg_has_role(current_user, 'postgres', 'MEMBER') THEN
    EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC';
  END IF;

  --------------------------------------------------------------------------
  -- 4.3 Verificação imediata do default efetivo de funções.
  --------------------------------------------------------------------------
  v_previous_search_path := current_setting('search_path');

  PERFORM set_config('search_path', 'public, extensions', true);

  BEGIN
    EXECUTE 'CREATE FUNCTION public.af_default_privileges_probe() RETURNS integer LANGUAGE sql AS $probe$ SELECT 1 $probe$';
  EXCEPTION WHEN others THEN
    PERFORM set_config('search_path', v_previous_search_path, true);
    RAISE EXCEPTION 'FALHA: nao foi possivel criar a funcao de teste do default de privilegios: %', SQLERRM;
  END;

  IF has_function_privilege('anon', 'public.af_default_privileges_probe()', 'EXECUTE') THEN
    EXECUTE 'DROP FUNCTION public.af_default_privileges_probe()';
    PERFORM set_config('search_path', v_previous_search_path, true);
    RAISE EXCEPTION
      'FALHA: o default global do PostgreSQL ainda concede EXECUTE a PUBLIC para novas funções. Use "ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC" (sem IN SCHEMA).';
  END IF;

  EXECUTE 'DROP FUNCTION public.af_default_privileges_probe()';

  --------------------------------------------------------------------------
  -- 4.4 Verificação imediata das concessões automáticas de tabelas e
  --     sequences: uma tabela sonda é criada e os papéis da API são
  --     verificados em TODOS os privilégios (SELECT, INSERT, UPDATE, DELETE,
  --     TRUNCATE, REFERENCES, TRIGGER e MAINTAIN). É a prova real de que a
  --     remoção das default privileges do projeto funcionou.
  --------------------------------------------------------------------------
  BEGIN
    EXECUTE 'CREATE TABLE public.af_default_privileges_probe (id integer)';
  EXCEPTION WHEN others THEN
    PERFORM set_config('search_path', v_previous_search_path, true);
    RAISE EXCEPTION 'FALHA: nao foi possivel criar a tabela de teste do default de privilegios: %', SQLERRM;
  END;

  IF has_table_privilege(
       'anon',
       'public.af_default_privileges_probe',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
     )
     OR has_table_privilege(
       'authenticated',
       'public.af_default_privileges_probe',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN'
     ) THEN
    EXECUTE 'DROP TABLE public.af_default_privileges_probe';
    PERFORM set_config('search_path', v_previous_search_path, true);
    RAISE EXCEPTION
      'FALHA: ainda existem privilegios automaticos para anon/authenticated nas novas tabelas do schema public.';
  END IF;

  EXECUTE 'DROP TABLE public.af_default_privileges_probe';

  PERFORM set_config('search_path', v_previous_search_path, true);

  RAISE NOTICE 'Agenda Flow: privilegios padrao do schema public normalizados.';
END;
$$;

--------------------------------------------------------------------------------
-- 5. Regras de auditoria (fonte única, no schema privado)
--------------------------------------------------------------------------------
-- Duas regras, ambas no schema privado (sem USAGE para os papéis da API):
--
--   unexpected_default_privileges()
--     Concessões automáticas (pg_default_acl) que são de responsabilidade do
--     PROJETO, ou seja, dos papéis que criam os objetos do Agenda Flow: o
--     role que executa esta migration e o role postgres. Qualquer concessão
--     a PUBLIC, anon ou authenticated é um problema BLOQUEANTE.
--
--   platform_default_privileges()
--     Concessões automáticas de outros papéis (supabase_admin e demais papéis
--     internos da plataforma Supabase). O role postgres não tem permissão
--     para alterar os default privileges do supabase_admin
--     (https://supabase.com/kb/troubleshooting/cant-change-the-default-privileges-of-supabase_admin-in-the-public-schema),
--     logo elas são PRESERVADAS e apenas reportadas como infraestrutura da
--     plataforma — visíveis na auditoria, sem bloquear a migration.
--
--   As funções de PUBLIC expostas no schema public são tratadas pela regra
--   já existente em publicly_exposed_functions() (exceção específica para
--   funções de event trigger vinculadas a pg_event_trigger).
CREATE OR REPLACE FUNCTION agenda_flow_private.unexpected_default_privileges()
RETURNS text[]
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    (
      SELECT array_agg(DISTINCT format(
        '%s %s para %s (schema %s, owner %s)',
        d.defaclobjtype::text,
        g.privilege_type,
        CASE WHEN g.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(g.grantee) END,
        n.nspname,
        d.defaclrole::regrole::text
      ))
      FROM pg_default_acl d
      JOIN pg_namespace n ON n.oid = d.defaclnamespace
      CROSS JOIN LATERAL aclexplode(d.defaclacl) g
      WHERE n.nspname = 'public'
        AND d.defaclobjtype IN ('r', 'S')
        AND d.defaclrole IN (
          SELECT oid FROM pg_roles WHERE rolname IN (current_user, 'postgres')
        )
        AND g.grantee IN (
          0,
          (SELECT oid FROM pg_roles WHERE rolname = 'anon'),
          (SELECT oid FROM pg_roles WHERE rolname = 'authenticated')
        )
    ),
    ARRAY[]::text[]
  );
$$;

COMMENT ON FUNCTION agenda_flow_private.unexpected_default_privileges() IS
  'Concessões automáticas (pg_default_acl) indevidas nos objetos criados pelos papéis do projeto.';

CREATE OR REPLACE FUNCTION agenda_flow_private.platform_default_privileges()
RETURNS text[]
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    (
      SELECT array_agg(DISTINCT format(
        '%s %s para %s (schema %s, owner %s)',
        d.defaclobjtype::text,
        g.privilege_type,
        CASE WHEN g.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(g.grantee) END,
        n.nspname,
        d.defaclrole::regrole::text
      ))
      FROM pg_default_acl d
      JOIN pg_namespace n ON n.oid = d.defaclnamespace
      CROSS JOIN LATERAL aclexplode(d.defaclacl) g
      WHERE n.nspname = 'public'
        AND d.defaclobjtype IN ('r', 'S')
        AND d.defaclrole NOT IN (
          SELECT oid FROM pg_roles WHERE rolname IN (current_user, 'postgres')
        )
    ),
    ARRAY[]::text[]
  );
$$;

COMMENT ON FUNCTION agenda_flow_private.platform_default_privileges() IS
  'Concessões automáticas de papéis internos da plataforma Supabase (não alteráveis pelo role postgres).';

REVOKE ALL ON FUNCTION agenda_flow_private.unexpected_default_privileges() FROM PUBLIC;
REVOKE ALL ON FUNCTION agenda_flow_private.unexpected_default_privileges() FROM anon;
REVOKE ALL ON FUNCTION agenda_flow_private.unexpected_default_privileges() FROM authenticated;
REVOKE ALL ON FUNCTION agenda_flow_private.unexpected_default_privileges() FROM service_role;

REVOKE ALL ON FUNCTION agenda_flow_private.platform_default_privileges() FROM PUBLIC;
REVOKE ALL ON FUNCTION agenda_flow_private.platform_default_privileges() FROM anon;
REVOKE ALL ON FUNCTION agenda_flow_private.platform_default_privileges() FROM authenticated;
REVOKE ALL ON FUNCTION agenda_flow_private.platform_default_privileges() FROM service_role;

CREATE OR REPLACE FUNCTION agenda_flow_private.publicly_exposed_functions()
RETURNS text[]
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT COALESCE(
    (
      SELECT array_agg(DISTINCT p.proname ORDER BY p.proname)
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) g
      WHERE n.nspname = 'public'
        AND g.grantee = 0
        AND g.privilege_type = 'EXECUTE'
        AND NOT (
          p.prorettype = 'event_trigger'::regtype
          AND EXISTS (SELECT 1 FROM pg_event_trigger et WHERE et.evtfoid = p.oid)
        )
    ),
    ARRAY[]::text[]
  );
$$;

COMMENT ON FUNCTION agenda_flow_private.publicly_exposed_functions() IS
  'Lista as funções do schema public com EXECUTE para PUBLIC, excluindo funções de event trigger vinculadas (não chamáveis por SQL).';

REVOKE ALL ON FUNCTION agenda_flow_private.publicly_exposed_functions() FROM PUBLIC;
REVOKE ALL ON FUNCTION agenda_flow_private.publicly_exposed_functions() FROM anon;
REVOKE ALL ON FUNCTION agenda_flow_private.publicly_exposed_functions() FROM authenticated;
REVOKE ALL ON FUNCTION agenda_flow_private.publicly_exposed_functions() FROM service_role;

--------------------------------------------------------------------------------
-- 6. Verificação explícita do estado final de privilégios
--------------------------------------------------------------------------------
-- Falha de forma explícita se o estado divergir do esperado, evitando que a
-- migration seja aplicada de forma parcial e silenciosa.
DO $$
DECLARE
  v_internal text[] := ARRAY[
    'agenda_flow_private.upsert_profile_from_auth_user(uuid)',
    'agenda_flow_private.handle_new_user()',
    'agenda_flow_private.handle_new_establishment()',
    'agenda_flow_private.set_updated_at()'
  ];
  v_business text[] := ARRAY[
    'public.create_establishment(text, text, text, text, text, text, jsonb)',
    'public.ensure_profile()',
    'public.create_establishment_invitation(uuid, text, text, text, text[], interval)',
    'public.accept_establishment_invitation(text)',
    'public.cancel_establishment_invitation(uuid)'
  ];
  v_readers text[] := ARRAY[
    'public.has_permission(uuid, text)',
    'public.get_user_establishment_role(uuid)',
    'public.is_establishment_member(uuid)',
    'public.is_establishment_owner(uuid)',
    'public.is_establishment_owner_or_manager(uuid)',
    'public.can_manage_member_role(uuid, text)',
    'public.is_colleague(uuid)',
    'public.normalize_phone(text)'
  ];
  v_item text;
  v_leaked text;
  v_project_roles text[] := ARRAY[current_user::regrole::text];
BEGIN
  -- Papéis responsáveis pelos objetos do Agenda Flow: o role que executa a
  -- migration e o role postgres. Papéis internos da plataforma Supabase
  -- (supabase_admin e afins) ficam fora — seus default privileges não são
  -- alteráveis pelo postgres e não devem bloquear esta migration.
  IF NOT ('postgres'::regrole::text = ANY(v_project_roles)) THEN
    v_project_roles := v_project_roles || 'postgres'::regrole::text;
  END IF;

  -- 4.1 Nenhuma função interna pode ser executada por anon/authenticated.
  FOREACH v_item IN ARRAY v_internal LOOP
    IF has_function_privilege('anon', v_item, 'EXECUTE') THEN
      RAISE EXCEPTION 'FALHA: anon pode executar a função interna %', v_item;
    END IF;
    IF has_function_privilege('authenticated', v_item, 'EXECUTE') THEN
      RAISE EXCEPTION 'FALHA: authenticated pode executar a função interna %', v_item;
    END IF;
  END LOOP;

  -- 4.1.1 As funções internas vivem em schema privado, sem USAGE para os
  --       papéis da API: mesmo que um GRANT indevido fosse concedido, a
  --       chamada seria impossível.
  IF has_schema_privilege('anon', 'agenda_flow_private', 'USAGE')
     OR has_schema_privilege('authenticated', 'agenda_flow_private', 'USAGE') THEN
    RAISE EXCEPTION 'FALHA: os papéis da API possuem USAGE no schema agenda_flow_private.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'agenda_flow_private'
      AND p.proname IN (
        'upsert_profile_from_auth_user',
        'handle_new_user',
        'handle_new_establishment',
        'set_updated_at'
      )
  ) THEN
    RAISE EXCEPTION 'FALHA: funcoes internas ausentes no schema agenda_flow_private.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'upsert_profile_from_auth_user',
        'handle_new_user',
        'handle_new_establishment',
        'set_updated_at'
      )
  ) THEN
    RAISE EXCEPTION 'FALHA: funcoes internas ainda existem no schema public.';
  END IF;

  -- 4.2 As RPCs de negócio são executáveis apenas por authenticated.
  FOREACH v_item IN ARRAY v_business LOOP
    IF has_function_privilege('anon', v_item, 'EXECUTE') THEN
      RAISE EXCEPTION 'FALHA: anon pode executar a RPC %', v_item;
    END IF;
    IF NOT has_function_privilege('authenticated', v_item, 'EXECUTE') THEN
      RAISE EXCEPTION 'FALHA: authenticated nao pode executar a RPC %', v_item;
    END IF;
  END LOOP;

  -- 4.3 As auxiliares de leitura (usadas pelas políticas RLS) atendem aos dois
  --     papéis da API, e nenhuma delas pode ser executada por PUBLIC.
  FOREACH v_item IN ARRAY v_readers LOOP
    IF NOT has_function_privilege('authenticated', v_item, 'EXECUTE') THEN
      RAISE EXCEPTION 'FALHA: authenticated nao pode executar a auxiliar %', v_item;
    END IF;
    IF NOT has_function_privilege('anon', v_item, 'EXECUTE') THEN
      RAISE EXCEPTION 'FALHA: anon nao pode avaliar a auxiliar % (policy quebrada)', v_item;
    END IF;
  END LOOP;

  -- 4.4 Nenhuma função COMUM do schema public pode herdar EXECUTE de PUBLIC.
  --
  --     Exceção específica e justificada: funções RETURNS event_trigger
  --     vinculadas a pg_event_trigger (caso real: public.rls_auto_enable).
  --     Elas só executam como event trigger — o PostgreSQL recusa a chamada
  --     direta ("trigger functions can only be called as triggers") — e não
  --     são expostas pelo PostgREST. A regra está centralizada em
  --     agenda_flow_private.publicly_exposed_functions().
  SELECT array_to_string(leaked, ', ')
    INTO v_leaked
  FROM agenda_flow_private.publicly_exposed_functions() AS leaked;

  IF v_leaked IS NOT NULL AND length(v_leaked) > 0 THEN
    RAISE EXCEPTION 'FALHA: funcoes do schema public com EXECUTE herdado de PUBLIC: %', v_leaked;
  END IF;

  -- 4.5 authenticated somente leitura nas tabelas de dados.
  IF has_table_privilege('authenticated', 'public.profiles', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'FALHA: authenticated possui escrita direta em public.profiles.';
  END IF;
  IF has_table_privilege('authenticated', 'public.establishments', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'FALHA: authenticated possui escrita direta em public.establishments.';
  END IF;
  IF has_table_privilege('authenticated', 'public.establishment_members', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'FALHA: authenticated possui escrita direta em public.establishment_members.';
  END IF;
  IF has_table_privilege('authenticated', 'public.member_permissions', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'FALHA: authenticated possui escrita direta em public.member_permissions.';
  END IF;
  IF has_table_privilege('authenticated', 'public.establishment_invitations', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'FALHA: authenticated possui escrita direta em public.establishment_invitations.';
  END IF;

  -- 4.6 O role anon não enxerga dados do tenant.
  IF has_table_privilege('anon', 'public.profiles', 'SELECT')
     OR has_table_privilege('anon', 'public.establishments', 'SELECT')
     OR has_table_privilege('anon', 'public.establishment_members', 'SELECT')
     OR has_table_privilege('anon', 'public.member_permissions', 'SELECT')
     OR has_table_privilege('anon', 'public.establishment_invitations', 'SELECT') THEN
    RAISE EXCEPTION 'FALHA: anon possui leitura sobre tabelas de dados do projeto.';
  END IF;

  -- 4.7 Toda tabela do PROJETO possui RLS habilitado (falha bloqueante) e
  --     qualquer outra tabela pública sem RLS é reportada como aviso — a
  --     migration não deve ser bloqueada por objetos fora do escopo do
  --     projeto, mas a condição não fica silenciosa.
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relname IN (
        'profiles',
        'establishments',
        'establishment_members',
        'member_permissions',
        'establishment_invitations'
      )
      AND NOT c.relrowsecurity
  ) THEN
    RAISE EXCEPTION 'FALHA: existe tabela do projeto sem RLS habilitado.';
  END IF;

  SELECT string_agg(c.relname, ', ')
    INTO v_leaked
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND NOT c.relrowsecurity
    AND c.relname NOT IN (
      'profiles',
      'establishments',
      'establishment_members',
      'member_permissions',
      'establishment_invitations'
    );

  IF v_leaked IS NOT NULL THEN
    RAISE NOTICE
      'AVISO: tabelas publicas fora do escopo do projeto sem RLS: % (revise com verify_remote.sql).', v_leaked;
  END IF;

  -- 4.8 Privilégios padrão (pg_default_acl).
  --
  -- 4.8.1 BLOQUEANTE: nenhuma concessão automática para PUBLIC, anon ou
  --       authenticated nos objetos criados pelos PAPÉIS DO PROJETO (o role
  --       que executa a migration e o role postgres). A regra cobre TODOS os
  --       tipos de privilégio (SELECT, INSERT, UPDATE, DELETE, TRUNCATE,
  --       REFERENCES, TRIGGER e MAINTAIN) — não apenas os principais.
  --       Os default privileges do supabase_admin (e de outros papéis internos
  --       da plataforma) NÃO são bloqueantes: o role postgres não pode
  --       alterá-los (documentação oficial do Supabase) e eles são
  --       preservados por esta migration.
  SELECT array_to_string(leaked, '; ')
    INTO v_leaked
  FROM agenda_flow_private.unexpected_default_privileges() AS leaked;

  IF v_leaked IS NOT NULL AND length(v_leaked) > 0 THEN
    RAISE EXCEPTION
      'FALHA: existem privilegios padrao (pg_default_acl) concedendo acesso automatico a PUBLIC/anon/authenticated para tabelas ou sequences criadas pelos papeis do projeto: %',
      v_leaked;
  END IF;

  -- 4.8.2 VISIBILIDADE (não bloqueante): default privileges de papéis
  --       internos da plataforma. Permanecem visíveis na auditoria, mas são
  --       infraestrutura da plataforma e não bloqueiam o Agenda Flow.
  SELECT array_to_string(leaked, '; ')
    INTO v_leaked
  FROM agenda_flow_private.platform_default_privileges() AS leaked;

  IF v_leaked IS NOT NULL AND length(v_leaked) > 0 THEN
    RAISE NOTICE
      'AVISO: privilegios padrao da infraestrutura da plataforma (nao alteraveis pelo role postgres): %', v_leaked;
  END IF;

  -- 4.8.3 Funções: o default efetivo é o global (defaclnamespace = 0) do
  --       role dono dos objetos, combinado com a entrada per-schema quando
  --       ela existe. Como o default global do sistema concede EXECUTE a
  --       PUBLIC, a verificação exige que exista uma entrada global que o
  --       remova. Aplica-se aos papéis do projeto.
  FOREACH v_item IN ARRAY v_project_roles LOOP
    IF EXISTS (
      SELECT 1
      FROM aclexplode(
        coalesce(
          (
            SELECT d.defaclacl
            FROM pg_default_acl d
            WHERE d.defaclrole = v_item::regrole
              AND d.defaclobjtype = 'f'
              AND d.defaclnamespace = 0
          ),
          acldefault('f', v_item::regrole)
        )
      ) g
      WHERE g.grantee = 0
        AND g.privilege_type = 'EXECUTE'
    ) THEN
      RAISE EXCEPTION
        'FALHA: o default global de funcoes do role % ainda concede EXECUTE a PUBLIC. Aplique "ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC" (sem IN SCHEMA).',
        v_item;
    END IF;
  END LOOP;

  RAISE NOTICE 'Agenda Flow: verificacao de privilegios concluida com sucesso.';
END;
$$;

-- Recarrega o cache de schema do PostgREST após a alteração de permissões.
NOTIFY pgrst, 'reload schema';
