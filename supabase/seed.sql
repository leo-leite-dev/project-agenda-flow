-- Seed / RLS tests for local development
-- This file is applied automatically by `supabase db reset` on local environments.
-- It must NEVER be applied to production. It creates synthetic users and data to
-- validate tenant isolation, privilege escalation protections and the integrity
-- of the profile provisioning.
--
-- Execution model
-- ---------------
-- 1. Users are created with the owner role (auth.users is not writable by
--    `authenticated`).
-- 2. All application scenarios run with `SET LOCAL ROLE authenticated` and the
--    JWT claims of the simulated user, so the policies are really evaluated
--    (the table owner bypasses RLS, therefore testing as the owner would
--    prove nothing).
-- 3. A probe role (`agenda_flow_probe`) inherits `authenticated` and receives
--    the membership write grants that the production role does NOT have. It is
--    used only to prove that the RLS POLICIES (and not only the GRANT layer)
--    block privilege escalation. Its extra grants are revoked at the end.
--
-- The seed keeps its data committed for manual testing.

BEGIN;

--------------------------------------------------------------------------------
-- 0. Test users (created with the owner role)
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_owner_a uuid := '11111111-1111-1111-1111-111111111111';
  v_prof_a  uuid := '22222222-2222-2222-2222-222222222222';
  v_manager_a uuid := '33333333-3333-3333-3333-333333333333';
  v_owner_b uuid := '44444444-4444-4444-4444-444444444444';
  v_prof_b  uuid := '55555555-5555-5555-5555-555555555555';
  v_google_user uuid := '66666666-6666-6666-6666-666666666666';
  v_email_user  uuid := '77777777-7777-7777-7777-777777777777';
  v_legacy_user uuid := '88888888-8888-8888-8888-888888888888';
  v_legacy_user2 uuid := '99999999-9999-9999-9999-999999999999';
BEGIN
  INSERT INTO auth.users (id, email, phone, encrypted_password, email_confirmed_at, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data, role)
  VALUES
    (v_owner_a, 'owner-a@agenda.flow.test', '+5511999900001', crypt('password', gen_salt('bf')), now(), now(), '{"provider":"email"}', '{"full_name":"Owner A"}', 'authenticated'),
    (v_prof_a, 'prof-a@agenda.flow.test', '+5511999900002', crypt('password', gen_salt('bf')), now(), now(), '{"provider":"email"}', '{"full_name":"Professional A"}', 'authenticated'),
    (v_manager_a, 'manager-a@agenda.flow.test', '+5511999900003', crypt('password', gen_salt('bf')), now(), now(), '{"provider":"email"}', '{"full_name":"Manager A"}', 'authenticated'),
    (v_owner_b, 'owner-b@agenda.flow.test', '+5511999900004', crypt('password', gen_salt('bf')), now(), now(), '{"provider":"email"}', '{"full_name":"Owner B"}', 'authenticated'),
    (v_prof_b, 'prof-b@agenda.flow.test', '+5511999900005', crypt('password', gen_salt('bf')), now(), now(), '{"provider":"email"}', '{"full_name":"Professional B"}', 'authenticated')
  ON CONFLICT (id) DO NOTHING;

  -- Google-style account: metadata uses "name"/"picture" and has no phone.
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, role)
  VALUES (
    v_google_user,
    'google-user@agenda.flow.test',
    crypt('password', gen_salt('bf')),
    now(),
    '{"provider":"google","providers":["google"]}',
    '{"name":"Google User","picture":"https://example.test/google-avatar.png"}',
    'authenticated'
  )
  ON CONFLICT (id) DO NOTHING;

  -- E-mail/senha account: metadata uses "full_name".
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, role)
  VALUES (
    v_email_user,
    'email-user@agenda.flow.test',
    crypt('password', gen_salt('bf')),
    now(),
    '{"provider":"email"}',
    '{"full_name":"Email User"}',
    'authenticated'
  )
  ON CONFLICT (id) DO NOTHING;

  -- Shared user: member of two establishments (tests the isolation of links).
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, role)
  VALUES (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'shared@agenda.flow.test',
    crypt('password', gen_salt('bf')),
    now(),
    '{"provider":"email"}',
    '{"full_name":"Shared Professional"}',
    'authenticated'
  )
  ON CONFLICT (id) DO NOTHING;

  -- Legacy accounts: simulate users created before the profile trigger existed.
  INSERT INTO auth.users (id, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, role)
  VALUES
    (
      v_legacy_user,
      'legacy-user@agenda.flow.test',
      crypt('password', gen_salt('bf')),
      now(),
      '{"provider":"google","providers":["google"]}',
      '{"name":"Legacy User"}',
      'authenticated'
    ),
    (
      v_legacy_user2,
      'legacy-user-2@agenda.flow.test',
      crypt('password', gen_salt('bf')),
      now(),
      '{"provider":"email"}',
      '{"full_name":"Legacy User Two"}',
      'authenticated'
    )
  ON CONFLICT (id) DO NOTHING;

  RAISE NOTICE 'Test users created.';
END $$;

--------------------------------------------------------------------------------
-- 1. Profile integrity (owner role): trigger, backfill and idempotency
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_google_user uuid := '66666666-6666-6666-6666-666666666666';
  v_email_user  uuid := '77777777-7777-7777-7777-777777777777';
  v_legacy_user uuid := '88888888-8888-8888-8888-888888888888';
BEGIN
  -- Test 1: the trigger creates a profile for every new auth user.
  ASSERT (SELECT count(*) FROM public.profiles) >= 9,
    'Profiles trigger did not create the profiles of the test users';

  -- Test 2: Google account uses "name"/"picture" metadata.
  ASSERT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_google_user),
    'Trigger did not create the profile of the Google user';
  ASSERT (SELECT full_name FROM public.profiles WHERE id = v_google_user) = 'Google User',
    'Google profile should use the "name" metadata';
  ASSERT (SELECT avatar_url FROM public.profiles WHERE id = v_google_user) = 'https://example.test/google-avatar.png',
    'Google profile should use the "picture" metadata';

  -- Test 3: E-mail/senha account uses "full_name" metadata.
  ASSERT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_email_user),
    'Trigger did not create the profile of the e-mail user';
  ASSERT (SELECT full_name FROM public.profiles WHERE id = v_email_user) = 'Email User',
    'E-mail profile should use the "full_name" metadata';

  -- Test 4: no duplicated profile.
  ASSERT (SELECT count(*) FROM public.profiles WHERE id = v_google_user) = 1,
    'Profile must not be duplicated';

  -- Test 5: recovery of a user without profile (legacy account).
  DELETE FROM public.profiles WHERE id = v_legacy_user;
  ASSERT NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_legacy_user),
    'Legacy user should start without a profile';

  -- Backfill (same statement used by the migration) recreates the missing row.
  INSERT INTO public.profiles (id, full_name, phone, avatar_url)
  SELECT
    u.id,
    COALESCE(
      NULLIF(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
      NULLIF(btrim(u.raw_user_meta_data ->> 'name'), ''),
      NULLIF(split_part(COALESCE(u.email, ''), '@', 1), ''),
      'Usuario'
    ),
    u.phone,
    COALESCE(u.raw_user_meta_data ->> 'avatar_url', u.raw_user_meta_data ->> 'picture')
  FROM auth.users u
  ON CONFLICT (id) DO NOTHING;

  ASSERT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_legacy_user),
    'Backfill did not recover the missing profile';

  -- Test 6: the backfill is idempotent and preserves existing data.
  UPDATE public.profiles SET full_name = 'Nome Preservado' WHERE id = v_legacy_user;

  INSERT INTO public.profiles (id, full_name, phone, avatar_url)
  SELECT
    u.id,
    COALESCE(
      NULLIF(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
      NULLIF(btrim(u.raw_user_meta_data ->> 'name'), ''),
      NULLIF(split_part(COALESCE(u.email, ''), '@', 1), ''),
      'Usuario'
    ),
    u.phone,
    COALESCE(u.raw_user_meta_data ->> 'avatar_url', u.raw_user_meta_data ->> 'picture')
  FROM auth.users u
  ON CONFLICT (id) DO NOTHING;

  ASSERT (SELECT count(*) FROM public.profiles) = (SELECT count(*) FROM auth.users),
    'Every auth user must have exactly one profile';
  ASSERT (SELECT full_name FROM public.profiles WHERE id = v_legacy_user) = 'Nome Preservado',
    'Backfill must not overwrite existing profile data';

  RAISE NOTICE 'Profile integrity assertions passed.';
END $$;

--------------------------------------------------------------------------------
-- 2. Least privilege, grants and RLS state (owner role)
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_leaked text[];
  v_message text;
BEGIN
  -- authenticated: leitura apenas, nenhuma escrita direta.
  ASSERT has_table_privilege('authenticated', 'public.profiles', 'SELECT'),
    'authenticated must have SELECT on public.profiles';
  ASSERT has_table_privilege('authenticated', 'public.establishments', 'SELECT'),
    'authenticated must have SELECT on public.establishments';
  ASSERT has_table_privilege('authenticated', 'public.establishment_members', 'SELECT'),
    'authenticated must have SELECT on public.establishment_members';

  ASSERT NOT has_table_privilege('authenticated', 'public.profiles', 'INSERT,UPDATE,DELETE'),
    'authenticated must NOT have write privileges on public.profiles';
  ASSERT NOT has_table_privilege('authenticated', 'public.establishments', 'INSERT,UPDATE,DELETE'),
    'authenticated must NOT have write privileges on public.establishments';
  ASSERT NOT has_table_privilege('authenticated', 'public.establishment_members', 'INSERT,UPDATE,DELETE'),
    'authenticated must NOT have write privileges on public.establishment_members';
  ASSERT NOT has_table_privilege('authenticated', 'public.member_permissions', 'INSERT,UPDATE,DELETE'),
    'authenticated must NOT have write privileges on public.member_permissions';
  ASSERT NOT has_table_privilege('authenticated', 'public.establishment_invitations', 'INSERT,UPDATE,DELETE'),
    'authenticated must NOT have write privileges on public.establishment_invitations';

  -- anon: nenhum acesso aos dados do projeto.
  ASSERT NOT has_table_privilege('anon', 'public.profiles', 'SELECT'),
    'anon must NOT have access to public.profiles';
  ASSERT NOT has_table_privilege('anon', 'public.establishments', 'SELECT'),
    'anon must NOT have access to public.establishments';
  ASSERT NOT has_table_privilege('anon', 'public.establishment_members', 'SELECT'),
    'anon must NOT have access to public.establishment_members';

  -- Funções internas vivem em schema privado, sem USAGE para os papéis da API.
  ASSERT NOT has_function_privilege('anon', 'agenda_flow_private.upsert_profile_from_auth_user(uuid)', 'EXECUTE'),
    'anon must NOT execute the internal profile helper';
  ASSERT NOT has_function_privilege('authenticated', 'agenda_flow_private.upsert_profile_from_auth_user(uuid)', 'EXECUTE'),
    'authenticated must NOT execute the internal profile helper';
  ASSERT NOT has_function_privilege('authenticated', 'agenda_flow_private.handle_new_user()', 'EXECUTE'),
    'authenticated must NOT execute the profile trigger function';
  ASSERT NOT has_function_privilege('anon', 'agenda_flow_private.handle_new_establishment()', 'EXECUTE'),
    'anon must NOT execute the membership trigger function';

  ASSERT NOT has_schema_privilege('anon', 'agenda_flow_private', 'USAGE'),
    'anon must NOT have USAGE on the private schema';
  ASSERT NOT has_schema_privilege('authenticated', 'agenda_flow_private', 'USAGE'),
    'authenticated must NOT have USAGE on the private schema';

  -- Nenhuma função interna pode permanecer no schema exposto à API.
  ASSERT NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'upsert_profile_from_auth_user',
        'handle_new_user',
        'handle_new_establishment',
        'set_updated_at'
      )
  ), 'Internal functions must not exist in the public schema';

  --------------------------------------------------------------------------
  -- Serviços (etapa 5): leitura para membros, escrita somente por RPC e
  -- apenas para o proprietário.
  --------------------------------------------------------------------------
  ASSERT has_table_privilege('authenticated', 'public.establishment_services', 'SELECT'),
    'authenticated must have SELECT on public.establishment_services';
  ASSERT NOT has_table_privilege('authenticated', 'public.establishment_services', 'INSERT,UPDATE,DELETE'),
    'authenticated must NOT have write privileges on public.establishment_services';
  ASSERT NOT has_table_privilege('anon', 'public.establishment_services', 'SELECT'),
    'anon must NOT have access to public.establishment_services';

  ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.establishment_services'::regclass),
    'RLS must be enabled on public.establishment_services';

  ASSERT has_function_privilege('authenticated', 'public.create_establishment_service(uuid, text, text, text, integer, integer, boolean)', 'EXECUTE'),
    'authenticated must be able to execute create_establishment_service';
  ASSERT has_function_privilege('authenticated', 'public.update_establishment_service(uuid, text, text, text, integer, integer, boolean)', 'EXECUTE'),
    'authenticated must be able to execute update_establishment_service';
  ASSERT has_function_privilege('authenticated', 'public.set_establishment_service_active(uuid, boolean)', 'EXECUTE'),
    'authenticated must be able to execute set_establishment_service_active';

  ASSERT NOT has_function_privilege('anon', 'public.create_establishment_service(uuid, text, text, text, integer, integer, boolean)', 'EXECUTE'),
    'anon must NOT execute create_establishment_service';
  ASSERT NOT has_function_privilege('anon', 'public.set_establishment_service_active(uuid, boolean)', 'EXECUTE'),
    'anon must NOT execute set_establishment_service_active';

  --------------------------------------------------------------------------
  -- Gestão de equipe (etapa 6): escrita apenas por RPCs do proprietário.
  --------------------------------------------------------------------------
  ASSERT has_function_privilege('authenticated', 'public.update_establishment_member_role(uuid, text)', 'EXECUTE'),
    'authenticated must be able to execute update_establishment_member_role';
  ASSERT has_function_privilege('authenticated', 'public.set_establishment_member_active(uuid, boolean)', 'EXECUTE'),
    'authenticated must be able to execute set_establishment_member_active';
  ASSERT has_function_privilege('authenticated', 'public.set_establishment_member_permissions(uuid, text[])', 'EXECUTE'),
    'authenticated must be able to execute set_establishment_member_permissions';

  ASSERT NOT has_function_privilege('anon', 'public.update_establishment_member_role(uuid, text)', 'EXECUTE'),
    'anon must NOT execute update_establishment_member_role';
  ASSERT NOT has_function_privilege('anon', 'public.set_establishment_member_active(uuid, boolean)', 'EXECUTE'),
    'anon must NOT execute set_establishment_member_active';
  ASSERT NOT has_function_privilege('anon', 'public.set_establishment_member_permissions(uuid, text[])', 'EXECUTE'),
    'anon must NOT execute set_establishment_member_permissions';

  ASSERT NOT has_table_privilege('authenticated', 'public.establishment_members', 'INSERT,UPDATE,DELETE'),
    'authenticated must NOT have write privileges on public.establishment_members';
  ASSERT NOT has_table_privilege('authenticated', 'public.member_permissions', 'INSERT,UPDATE,DELETE'),
    'authenticated must NOT have write privileges on public.member_permissions';
  ASSERT NOT has_table_privilege('authenticated', 'public.establishment_invitations', 'INSERT,UPDATE,DELETE'),
    'authenticated must NOT have write privileges on public.establishment_invitations';


  -- RPCs de negócio: apenas authenticated.
  ASSERT has_function_privilege('authenticated', 'public.ensure_profile()', 'EXECUTE'),
    'authenticated must be able to execute public.ensure_profile()';
  ASSERT has_function_privilege('authenticated', 'public.create_establishment(text, text, text, text, text, text, jsonb)', 'EXECUTE'),
    'authenticated must be able to execute public.create_establishment()';
  ASSERT NOT has_function_privilege('anon', 'public.ensure_profile()', 'EXECUTE'),
    'anon must NOT execute public.ensure_profile()';
  ASSERT NOT has_function_privilege('anon', 'public.create_establishment(text, text, text, text, text, text, jsonb)', 'EXECUTE'),
    'anon must NOT execute public.create_establishment()';

  -- RLS deve permanecer habilitado em todas as tabelas de dados.
  ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.profiles'::regclass),
    'RLS must be enabled on public.profiles';
  ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.establishments'::regclass),
    'RLS must be enabled on public.establishments';
  ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.establishment_members'::regclass),
    'RLS must be enabled on public.establishment_members';
  ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.member_permissions'::regclass),
    'RLS must be enabled on public.member_permissions';
  ASSERT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.establishment_invitations'::regclass),
    'RLS must be enabled on public.establishment_invitations';

  -- O trigger de criação de perfis deve existir, estar habilitado e apontar
  -- para a função interna no schema privado.
  ASSERT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'auth.users'::regclass
      AND tgname = 'on_auth_user_created'
      AND NOT tgisinternal
      AND tgenabled = 'O'
  ), 'Trigger on_auth_user_created must exist and be enabled on auth.users';

  ASSERT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE t.tgrelid = 'auth.users'::regclass
      AND t.tgname = 'on_auth_user_created'
      AND n.nspname = 'agenda_flow_private'
  ), 'Trigger on_auth_user_created must call the private schema function';

  -- Os triggers de updated_at também devem usar a função privada.
  ASSERT NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE t.tgname IN (
        'profiles_updated_at',
        'establishments_updated_at',
        'establishment_members_updated_at',
        'on_establishment_created'
      )
      AND n.nspname <> 'agenda_flow_private'
  ), 'Auxiliary triggers must call the private schema functions';

  -- As políticas de isolamento devem existir.
  ASSERT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'establishments' AND policyname = 'establishments_select'
  ), 'Policy establishments_select must exist';
  ASSERT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'establishment_members' AND policyname = 'establishment_members_update'
  ), 'Policy establishment_members_update must exist';
  ASSERT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'member_permissions' AND policyname = 'member_permissions_update'
  ), 'Policy member_permissions_update must exist';

  --------------------------------------------------------------------------
  -- Default de privilégios: uma função nova NÃO pode ser executável por
  -- PUBLIC. O EXECUTE para PUBLIC é o default global do PostgreSQL e só é
  -- removido por "ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM
  -- PUBLIC" (sem IN SCHEMA) — um REVOKE per-schema é um no-op silencioso.
  --------------------------------------------------------------------------
  CREATE FUNCTION public.af_default_privileges_probe()
  RETURNS integer LANGUAGE sql AS 'SELECT 1';

  ASSERT NOT has_function_privilege('anon', 'public.af_default_privileges_probe()', 'EXECUTE'),
    'A new function must NOT be executable by PUBLIC (global default privileges not revoked)';
  ASSERT NOT has_function_privilege('authenticated', 'public.af_default_privileges_probe()', 'EXECUTE'),
    'A new function must NOT be executable by authenticated (global default privileges not revoked)';

  DROP FUNCTION public.af_default_privileges_probe();

  -- Nenhum privilégio padrão per-schema para o schema public concedendo
  -- acesso automático aos papéis da API nos objetos criados pelo projeto.
  -- (Os default privileges de papéis internos da plataforma — supabase_admin —
  -- são preservados e verificados separadamente.)
  ASSERT NOT EXISTS (
    SELECT 1
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
  ), 'No automatic table/sequence privileges may exist for PUBLIC/anon/authenticated in project-owned objects';

  --------------------------------------------------------------------------
  -- Regressão da auditoria: função de event trigger (caso real do Supabase,
  -- public.rls_auto_enable) NÃO deve ser apontada como RPC exposta — mas uma
  -- RPC comum insegura DEVE ser apontada.
  --------------------------------------------------------------------------
  BEGIN
    EXECUTE 'CREATE FUNCTION public.af_event_trigger_probe() RETURNS event_trigger LANGUAGE plpgsql AS $fn$
    BEGIN
      RAISE NOTICE ''Agenda Flow: event trigger de teste disparado'';
    END;
    $fn$';

    EXECUTE 'CREATE EVENT TRIGGER af_event_trigger_probe ON ddl_command_end EXECUTE FUNCTION public.af_event_trigger_probe()';

    -- Reproduz o cenário real do Supabase (public.rls_auto_enable): função de
    -- event trigger com EXECUTE para PUBLIC (proacl NULL ou GRANT explícito).
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.af_event_trigger_probe() TO PUBLIC';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Teste de event trigger ignorado: sem privilégio para criar event trigger.';
    DROP FUNCTION IF EXISTS public.af_event_trigger_probe();
    RAISE NOTICE 'Least privilege, grants and RLS assertions passed.';
    RETURN;
  END;

  -- (a) Uma função de event trigger não pode ser chamada diretamente por SQL.
  BEGIN
    PERFORM public.af_event_trigger_probe();
  EXCEPTION WHEN others THEN
    v_message := SQLERRM;
  END;

  ASSERT v_message IS NOT NULL AND v_message ILIKE '%trigger functions can only be called as triggers%',
    'Event trigger functions must not be directly callable (got: %', COALESCE(v_message, 'no error');

  -- (b) E, ainda assim, não deve ser apontada pela auditoria de funções
  --     expostas do schema public.
  v_leaked := agenda_flow_private.publicly_exposed_functions();

  ASSERT NOT ('af_event_trigger_probe' = ANY(v_leaked)),
    'Event trigger functions must NOT be reported as publicly exposed RPCs';

  -- (c) Uma RPC comum e insegura DEVE ser apontada pela auditoria. Como o
  --     default global já foi revogado, o cenário inseguro é reproduzido com
  --     um GRANT explícito de EXECUTE a PUBLIC.
  EXECUTE 'CREATE FUNCTION public.af_insecure_rpc_probe() RETURNS integer LANGUAGE sql AS $fn$ SELECT 1 $fn$';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.af_insecure_rpc_probe() TO PUBLIC';

  v_leaked := agenda_flow_private.publicly_exposed_functions();

  ASSERT ('af_insecure_rpc_probe' = ANY(v_leaked)),
    'Insecure public RPCs MUST be reported by the audit';

  EXECUTE 'REVOKE ALL ON FUNCTION public.af_insecure_rpc_probe() FROM PUBLIC';
  EXECUTE 'DROP EVENT TRIGGER af_event_trigger_probe';
  EXECUTE 'DROP FUNCTION public.af_event_trigger_probe()';
  EXECUTE 'DROP FUNCTION public.af_insecure_rpc_probe()';

  --------------------------------------------------------------------------
  -- Default privileges: papéis do projeto x infraestrutura da plataforma.
  --------------------------------------------------------------------------
  -- (d) Os default privileges do supabase_admin (papel interno da plataforma,
  --     não alterável pelo role postgres) DEVEM SER PRESERVADOS e não podem
  --     bloquear a auditoria.
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') THEN
    ASSERT EXISTS (
      SELECT 1
      FROM pg_default_acl d
      JOIN pg_namespace n ON n.oid = d.defaclnamespace
      CROSS JOIN LATERAL aclexplode(d.defaclacl) g
      WHERE n.nspname = 'public'
        AND d.defaclrole = (SELECT oid FROM pg_roles WHERE rolname = 'supabase_admin')
        AND d.defaclobjtype IN ('r', 'S')
    ), 'Platform (supabase_admin) default privileges must be preserved';
  END IF;

  -- (e) Os default privileges do role postgres para PUBLIC/anon/
  --     authenticated DEVEM TER SIDO REMOVIDOS.
  ASSERT agenda_flow_private.unexpected_default_privileges() = ARRAY[]::text[],
    'Project role default privileges for PUBLIC/anon/authenticated must be revoked';

  -- (f) Uma concessão insegura criada pelo PAPEL DA APLICAÇÃO deve continuar
  --     provocando falha na auditoria.
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon';

  v_leaked := agenda_flow_private.unexpected_default_privileges();

  ASSERT array_length(v_leaked, 1) > 0,
    'An insecure default privilege created by the application role MUST be reported';

  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon';

  ASSERT agenda_flow_private.unexpected_default_privileges() = ARRAY[]::text[],
    'Default privileges must be clean again after the revocation';

  --------------------------------------------------------------------------
  -- Integridade dos vínculos: unicidade (establishment_id, user_id).
  --
  -- Regra de negócio: um usuário possui no máximo um vínculo efetivo por
  -- estabelecimento (com um cargo definido nesse vínculo). O mesmo usuário
  -- pode ter vínculos em empresas diferentes.
  --------------------------------------------------------------------------
  ASSERT (
    SELECT count(*) > 0
    FROM (
      SELECT c.oid
      FROM pg_constraint c
      WHERE c.conrelid = 'public.establishment_members'::regclass
        AND c.contype = 'u'
        AND (
          SELECT array_agg(a.attname::text ORDER BY a.attname::text)
          FROM unnest(c.conkey) AS k(attnum)
          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
        ) = ARRAY['establishment_id', 'user_id']
      UNION ALL
      SELECT i.indexrelid
      FROM pg_index i
      WHERE i.indrelid = 'public.establishment_members'::regclass
        AND i.indisunique
        AND i.indisvalid
        AND i.indpred IS NULL
        AND (
          SELECT array_agg(a.attname::text ORDER BY a.attname::text)
          FROM unnest(i.indkey::smallint[]) AS k(attnum)
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
        ) = ARRAY['establishment_id', 'user_id']
    ) AS uniques
  ), 'public.establishment_members must guarantee one link per (establishment_id, user_id)';

  -- Nenhum vínculo duplicado existe nos dados de teste.
  ASSERT NOT EXISTS (
    SELECT 1
    FROM public.establishment_members
    GROUP BY establishment_id, user_id
    HAVING count(*) > 1
  ), 'No establishment may have duplicated links for the same user';

  RAISE NOTICE 'Least privilege, grants and RLS assertions passed.';
END $$;

--------------------------------------------------------------------------------
-- 2.1 Legacy accounts without profile (owner role)
--------------------------------------------------------------------------------
-- Simulates accounts created before the profile trigger existed.
DO $$
BEGIN
  DELETE FROM public.profiles
  WHERE id IN (
    '88888888-8888-8888-8888-888888888888',
    '99999999-9999-9999-9999-999999999999'
  );

  ASSERT NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = '88888888-8888-8888-8888-888888888888'),
    'Legacy user should be without a profile';
  ASSERT NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = '99999999-9999-9999-9999-999999999999'),
    'Second legacy user should be without a profile';

  RAISE NOTICE 'Legacy accounts prepared.';
END $$;

--------------------------------------------------------------------------------
-- 3. Application behaviour (role authenticated, real identities)
--------------------------------------------------------------------------------
-- Requer que o role atual possa assumir `authenticated` (superusuário ou
-- membro do role). Em ambiente local o role postgres é superusuário.
DO $$
BEGIN
  IF NOT pg_has_role(current_user, 'authenticated', 'MEMBER') THEN
    BEGIN
      EXECUTE format('GRANT authenticated TO %I', current_user);
      RAISE NOTICE 'Role authenticated liberado para % na execução do seed.', current_user;
    EXCEPTION WHEN insufficient_privilege THEN
      RAISE NOTICE 'AVISO: o role atual não pode assumir authenticated. Os cenários de RLS exigem esse acesso.';
    END;
  END IF;
END $$;

SET LOCAL ROLE authenticated;

-- Simulated session of Owner A.
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

DO $$
DECLARE
  v_owner_a uuid := '11111111-1111-1111-1111-111111111111';
  v_prof_a  uuid := '22222222-2222-2222-2222-222222222222';
  v_manager_a uuid := '33333333-3333-3333-3333-333333333333';
  v_owner_b uuid := '44444444-4444-4444-4444-444444444444';
  v_prof_b  uuid := '55555555-5555-5555-5555-555555555555';
  v_legacy_user uuid := '88888888-8888-8888-8888-888888888888';
  v_legacy_user2 uuid := '99999999-9999-9999-9999-999999999999';
  v_est_a uuid;
  v_est_b uuid;
  v_est_legacy uuid;
  v_est_frontend uuid;
  v_service_a uuid;
  v_service_b uuid;
  v_shared_user uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_token_shared text;
  v_token_shared_b text;
  v_token_expired text;
  v_token_cancelled text;
  v_token_reused text;
  v_token_identity text;
  v_token_email text;
  v_email_user uuid := '77777777-7777-7777-7777-777777777777';
  v_token_manager text;
  v_token_prof text;
  v_token_prof_b text;
  v_token_owner_self text;
  v_token_prof_again text;
  v_token_manager2 text;
  v_token_delegated text;
  v_token_owner_permissions text;
BEGIN
  -- Garante que o cenário roda com o papel da API, e não como dono das
  -- tabelas (o dono ignora RLS e tornaria as asserções vazias).
  ASSERT current_user = 'authenticated',
    'The RLS scenarios must run as the authenticated role, not as the table owner';

  --------------------------------------------------------------------------
  -- Test 7: establishment creation keeps working (RPC, owner identity)
  --------------------------------------------------------------------------
  v_est_a := public.create_establishment(
    p_name => 'Barbearia Alpha',
    p_slug => 'barbearia-alpha',
    p_type => 'barbershop'
  );

  ASSERT v_est_a IS NOT NULL, 'Establishments should be created';
  ASSERT EXISTS (SELECT 1 FROM public.establishments WHERE id = v_est_a AND owner_id = v_owner_a),
    'Establishment must be owned by its creator';
  ASSERT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_owner_a AND role = 'owner'
  ), 'Owner membership must be created atomically';

  -- Owner B creates its own establishment (second, independent tenant).
  PERFORM set_config('request.jwt.claim.sub', v_owner_b::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);

  v_est_b := public.create_establishment(
    p_name => 'Salao Beta',
    p_slug => 'salao-beta',
    p_type => 'salon'
  );

  ASSERT v_est_b IS NOT NULL, 'Second establishment should be created';
  ASSERT (SELECT owner_id FROM public.establishments WHERE id = v_est_b) = v_owner_b,
    'Second establishment must belong to its own owner';

  --------------------------------------------------------------------------
  -- Test 8: real invitation flow (RPC) creates the memberships
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  v_token_manager := public.create_establishment_invitation(
    v_est_a, 'manager-a@agenda.flow.test', NULL, 'manager', ARRAY['appointments.read', 'clients.read']
  );
  v_token_prof := public.create_establishment_invitation(
    v_est_a, 'prof-a@agenda.flow.test', NULL, 'professional', ARRAY['appointments.read', 'clients.read']
  );
  ASSERT v_token_manager IS NOT NULL AND length(v_token_manager) = 64,
    'Invitation token should be a 64-char hex string';

  -- The invited employee accepts the invitation (real identity).
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);
  PERFORM public.accept_establishment_invitation(v_token_manager);

  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);
  PERFORM public.accept_establishment_invitation(v_token_prof);

  ASSERT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_manager_a AND role = 'manager'
  ), 'Manager membership should be created by the invitation flow';
  ASSERT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_prof_a AND role = 'professional'
  ), 'Professional membership should be created by the invitation flow';

  -- Second tenant: owner B invites professional B.
  PERFORM set_config('request.jwt.claim.sub', v_owner_b::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);
  v_token_prof_b := public.create_establishment_invitation(
    v_est_b, 'prof-b@agenda.flow.test', NULL, 'professional', ARRAY['appointments.read']
  );

  PERFORM set_config('request.jwt.claim.sub', v_prof_b::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","aud":"authenticated","email":"prof-b@agenda.flow.test"}', true);
  PERFORM public.accept_establishment_invitation(v_token_prof_b);

  --------------------------------------------------------------------------
  -- Test 9: tenant isolation — professional A cannot see establishment B
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);

  ASSERT EXISTS (SELECT 1 FROM public.establishments WHERE id = v_est_a),
    'Member should see own establishment';
  ASSERT NOT EXISTS (SELECT 1 FROM public.establishments WHERE id = v_est_b),
    'Member should NOT see another tenant establishment';
  ASSERT NOT EXISTS (SELECT 1 FROM public.establishment_members WHERE establishment_id = v_est_b),
    'Member should NOT see the members of another tenant';
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.member_permissions mp
    JOIN public.establishment_members m ON m.id = mp.member_id
    WHERE m.establishment_id = v_est_b
  ), 'Member should NOT see the permissions of another tenant';

  --------------------------------------------------------------------------
  -- Test 10: colleague visibility inside the own tenant
  --------------------------------------------------------------------------
  ASSERT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_owner_a),
    'Member should see colleague profile';
  ASSERT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_manager_a),
    'Member should see the profile of a colleague of the same tenant';
  ASSERT NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_owner_b),
    'Member should NOT see profile of a user from another tenant';
  ASSERT NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_prof_b),
    'Member should NOT see profile of an employee from another tenant';

  --------------------------------------------------------------------------
  -- Test 11: professional cannot read the invitations of the tenant
  --------------------------------------------------------------------------
  ASSERT NOT EXISTS (SELECT 1 FROM public.establishment_invitations WHERE establishment_id = v_est_a),
    'Professional should NOT see invitations';

  -- Owner and manager can see the invitations of their own tenant.
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);
  ASSERT EXISTS (SELECT 1 FROM public.establishment_invitations WHERE establishment_id = v_est_a),
    'Manager should see the invitations of the own tenant';

  --------------------------------------------------------------------------
  -- Test 12: unauthorized writes are refused by PostgreSQL (grant layer)
  --------------------------------------------------------------------------
  -- The production role has no write privilege on the data tables at all.
  BEGIN
    UPDATE public.establishments SET name = 'Hacked' WHERE id = v_est_a;
    RAISE EXCEPTION 'Professional should NOT be able to update establishment';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: refused by PostgreSQL
  END;

  BEGIN
    INSERT INTO public.establishment_members (establishment_id, user_id, role)
    VALUES (v_est_a, v_prof_b, 'owner');
    RAISE EXCEPTION 'Authenticated role should NOT be able to insert memberships';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: refused by PostgreSQL
  END;

  BEGIN
    INSERT INTO public.profiles (id, full_name)
    VALUES (gen_random_uuid(), 'Perfil Invasor');
    RAISE EXCEPTION 'Authenticated role should NOT be able to insert profiles';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: refused by PostgreSQL
  END;

  BEGIN
    UPDATE public.profiles SET full_name = 'Perfil Alterado' WHERE id = v_owner_b;
    RAISE EXCEPTION 'Authenticated role should NOT be able to update another profile';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: refused by PostgreSQL
  END;

  BEGIN
    UPDATE public.member_permissions SET permission_key = 'finances.delete';
    RAISE EXCEPTION 'Authenticated role should NOT be able to change permissions';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: refused by PostgreSQL
  END;

  --------------------------------------------------------------------------
  -- Test 13: the authorization logic itself denies the escalation
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

  ASSERT public.can_manage_member_role(v_est_a, 'owner') = false,
    'Manager must NOT be able to manage owner/manager roles';
  ASSERT public.can_manage_member_role(v_est_a, 'professional') = true,
    'Manager must be able to manage professional roles';
  ASSERT public.is_establishment_owner_or_manager(v_est_a) = true,
    'Manager must be recognized as owner_or_manager';
  ASSERT public.is_establishment_owner(v_est_a) = false,
    'Manager must NOT be recognized as owner';

  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);

  ASSERT public.can_manage_member_role(v_est_a, 'professional') = false,
    'Professional must NOT be able to manage any role';
  ASSERT public.has_permission(v_est_a, 'appointments.read') = true,
    'Professional should have the granted granular permission';
  ASSERT public.has_permission(v_est_a, 'finances.delete') = false,
    'Professional must NOT have a permission that was not granted';

  --------------------------------------------------------------------------
  -- Test 14: manager cannot invite an owner/administrator
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.create_establishment_invitation(v_est_a, 'hacker@agenda.flow.test', NULL, 'owner');
    RAISE EXCEPTION 'Manager should NOT be able to invite an owner';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  --------------------------------------------------------------------------
  -- Test 15: only the invited identity can accept an invitation
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_prof_b::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","aud":"authenticated","email":"prof-b@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_prof);
    RAISE EXCEPTION 'Wrong user should NOT be able to accept invitation';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  --------------------------------------------------------------------------
  -- Test 16: ensure_profile recovers a missing profile (idempotent)
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_legacy_user::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated","aud":"authenticated","email":"legacy-user@agenda.flow.test"}', true);

  ASSERT NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_legacy_user),
    'Legacy user should be without a profile at this point';

  ASSERT public.ensure_profile() = v_legacy_user,
    'ensure_profile should return the id of the authenticated user';
  ASSERT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_legacy_user),
    'ensure_profile should recover the missing profile';
  ASSERT (SELECT full_name FROM public.profiles WHERE id = v_legacy_user) = 'Legacy User',
    'ensure_profile should use the user metadata for the name';

  PERFORM public.ensure_profile();
  PERFORM public.ensure_profile();
  ASSERT (SELECT count(*) FROM public.profiles WHERE id = v_legacy_user) = 1,
    'ensure_profile must not duplicate profiles';

  --------------------------------------------------------------------------
  -- Test 17: create_establishment works even without a pre-existing profile
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_legacy_user2::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated","aud":"authenticated","email":"legacy-user-2@agenda.flow.test"}', true);

  ASSERT NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_legacy_user2),
    'Second legacy user should be without a profile before creating the establishment';

  v_est_legacy := public.create_establishment(
    p_name => 'Barbearia Recuperada',
    p_slug => 'barbearia-recuperada',
    p_type => 'barbershop'
  );

  ASSERT v_est_legacy IS NOT NULL,
    'create_establishment must succeed even without a pre-existing profile (FK 23503)';
  ASSERT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_legacy_user2),
    'create_establishment must recreate the missing profile';
  ASSERT EXISTS (SELECT 1 FROM public.establishments WHERE id = v_est_legacy AND owner_id = v_legacy_user2),
    'Recovered establishment must be owned by its creator';
  ASSERT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_est_legacy AND user_id = v_legacy_user2 AND role = 'owner'
  ), 'Recovered establishment must have an owner membership';

  --------------------------------------------------------------------------
  -- Test 18: the exact contract used by the frontend keeps working
  --------------------------------------------------------------------------
  -- src/lib/supabase.ts chama create_establishment com p_name, p_slug,
  -- p_type, p_phone, p_email e p_address.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  v_est_frontend := public.create_establishment(
    p_name => 'Barbearia Contrato Frontend',
    p_slug => 'barbearia-contrato-frontend',
    p_type => 'barbershop',
    p_phone => '(11) 99999-9999',
    p_email => 'owner-a@agenda.flow.test',
    p_address => '{"city":"Sao Paulo","state":"SP","address":"Rua Teste, 123"}'::jsonb
  );

  ASSERT v_est_frontend IS NOT NULL,
    'create_establishment must accept the payload used by the frontend';
  ASSERT (SELECT type FROM public.establishments WHERE id = v_est_frontend) = 'barbershop',
    'Establishment type must be persisted';
  ASSERT (SELECT email FROM public.establishments WHERE id = v_est_frontend) = 'owner-a@agenda.flow.test',
    'Establishment email must be persisted';

  --------------------------------------------------------------------------
  -- Test 19: duplicated establishment slug is rejected (no duplicate tenants)
  --------------------------------------------------------------------------
  BEGIN
    PERFORM public.create_establishment(
      p_name => 'Barbearia Alpha Repetida',
      p_slug => 'barbearia-alpha',
      p_type => 'barbershop'
    );
    RAISE EXCEPTION 'Duplicated slug should be rejected';
  EXCEPTION WHEN unique_violation THEN
    -- expected
  END;

  --------------------------------------------------------------------------
  -- Services (etapa 5)
  --------------------------------------------------------------------------
  -- Test 20: the owner creates a service for the active establishment.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  v_service_a := public.create_establishment_service(
    p_establishment_id => v_est_a,
    p_name => '  Corte Masculino  ',
    p_description => 'Corte completo com finalização',
    p_category => 'cabelo',
    p_duration_minutes => 30,
    p_price_cents => 3500,
    p_is_active => true
  );

  ASSERT v_service_a IS NOT NULL, 'Service should be created by the owner';
  ASSERT EXISTS (
    SELECT 1 FROM public.establishment_services s
    WHERE s.id = v_service_a
      AND s.establishment_id = v_est_a
      AND s.name = 'Corte Masculino'
      AND s.category = 'cabelo'
      AND s.duration_minutes = 30
      AND s.price_cents = 3500
      AND s.is_active = true
  ), 'Service must be persisted with trimmed name and correct data';

  -- Test 21: duplicated name (case/trim-insensitive) is rejected.
  BEGIN
    PERFORM public.create_establishment_service(
      p_establishment_id => v_est_a,
      p_name => 'corte masculino',
      p_category => 'cabelo',
      p_duration_minutes => 30,
      p_price_cents => 4000
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Duplicated service name should be rejected';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 22: invalid values are rejected by the RPC.
  BEGIN
    PERFORM public.create_establishment_service(
      p_establishment_id => v_est_a,
      p_name => 'Servico Invalido',
      p_category => 'cabelo',
      p_duration_minutes => 0,
      p_price_cents => 3500
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Zero duration should be rejected';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  BEGIN
    PERFORM public.create_establishment_service(
      p_establishment_id => v_est_a,
      p_name => 'Servico Invalido',
      p_category => 'cabelo',
      p_duration_minutes => 30,
      p_price_cents => -100
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Negative price should be rejected';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  BEGIN
    PERFORM public.create_establishment_service(
      p_establishment_id => v_est_a,
      p_name => 'Servico Invalido',
      p_category => 'teletransporte',
      p_duration_minutes => 30,
      p_price_cents => 3500
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Invalid category should be rejected';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 23: only the owner can manage services (manager and professional cannot).
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.create_establishment_service(
      p_establishment_id => v_est_a,
      p_name => 'Servico do Gestor',
      p_category => 'outros',
      p_duration_minutes => 30,
      p_price_cents => 1000
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Manager should NOT be able to create services';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.update_establishment_service(
      p_service_id => v_service_a,
      p_name => 'Hackeado',
      p_duration_minutes => 30,
      p_price_cents => 1
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Professional should NOT be able to update services';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 24: the owner edits and toggles the service (logical deactivation).
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  PERFORM public.update_establishment_service(
    p_service_id => v_service_a,
    p_name => 'Corte Premium',
    p_description => NULL,
    p_category => 'cabelo',
    p_duration_minutes => 40,
    p_price_cents => 5000,
    p_is_active => NULL
  );

  ASSERT EXISTS (
    SELECT 1 FROM public.establishment_services s
    WHERE s.id = v_service_a
      AND s.name = 'Corte Premium'
      AND s.duration_minutes = 40
      AND s.price_cents = 5000
      AND s.is_active = true
  ), 'Service edit must be persisted';

  PERFORM public.set_establishment_service_active(v_service_a, false);
  ASSERT (
    SELECT is_active FROM public.establishment_services WHERE id = v_service_a
  ) = false, 'Service deactivation must be persisted (logical, no delete)';

  PERFORM public.set_establishment_service_active(v_service_a, true);
  ASSERT (
    SELECT is_active FROM public.establishment_services WHERE id = v_service_a
  ) = true, 'Service reactivation must be persisted';

  -- Test 25: another establishment has its own catalog (data isolation).
  -- Owner A first confirms the data of its own service.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  ASSERT (
    SELECT price_cents FROM public.establishment_services WHERE id = v_service_a
  ) = 5000, 'Service A data must be readable by its own owner';

  PERFORM set_config('request.jwt.claim.sub', v_owner_b::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);

  v_service_b := public.create_establishment_service(
    p_establishment_id => v_est_b,
    p_name => 'Corte Masculino',
    p_category => 'cabelo',
    p_duration_minutes => 25,
    p_price_cents => 5000
  );

  ASSERT v_service_b IS NOT NULL, 'The other tenant must have its own catalog';
  ASSERT v_service_a <> v_service_b, 'The two tenants must have independent services';
  ASSERT (
    SELECT price_cents FROM public.establishment_services WHERE id = v_service_b
  ) = 5000, 'Service B data must be readable by its own owner';
  ASSERT (
    SELECT establishment_id FROM public.establishment_services WHERE id = v_service_b
  ) = v_est_b, 'Service B must belong to establishment B';

  -- Test 26: tenant isolation — professional A sees only the services of
  -- establishment A.
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);

  ASSERT EXISTS (
    SELECT 1 FROM public.establishment_services s WHERE s.id = v_service_a
  ), 'Member should see the services of the own establishment';
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_services s WHERE s.id = v_service_b
  ), 'Member should NOT see the services of another tenant';

  -- Test 27: the owner of another establishment cannot update services that
  -- are not his.
  PERFORM set_config('request.jwt.claim.sub', v_owner_b::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.update_establishment_service(
      p_service_id => v_service_a,
      p_name => 'Sequestrado',
      p_duration_minutes => 30,
      p_price_cents => 1
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Owner of another tenant should NOT update foreign services';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 28: a user without an establishment cannot create services.
  PERFORM set_config('request.jwt.claim.sub', v_legacy_user::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated","aud":"authenticated","email":"legacy-user@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.create_establishment_service(
      p_establishment_id => v_est_a,
      p_name => 'Intruso',
      p_category => 'outros',
      p_duration_minutes => 30,
      p_price_cents => 1000
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'User without ownership should NOT create services';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 29: direct writes without privileges are refused by PostgreSQL.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  BEGIN
    INSERT INTO public.establishment_services (
      establishment_id, name, category, duration_minutes, price_cents
    )
    VALUES (v_est_a, 'Insercao Direta', 'outros', 30, 1000);
    RAISE EXCEPTION 'Authenticated role should NOT insert services directly';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected
  END;

  BEGIN
    UPDATE public.establishment_services SET price_cents = 1 WHERE id = v_service_a;
    RAISE EXCEPTION 'Authenticated role should NOT update services directly';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected
  END;

  --------------------------------------------------------------------------
  -- Team management (etapa 6)
  --------------------------------------------------------------------------
  -- Test 30: the owner changes a member's role (manager -> professional).
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  PERFORM public.update_establishment_member_role(
    (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_manager_a),
    'professional'
  );

  ASSERT (
    SELECT role FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_manager_a
  ) = 'professional', 'Role change must be persisted';

  -- Test 31: the owner restores the role.
  PERFORM public.update_establishment_member_role(
    (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_manager_a),
    'manager'
  );

  -- Test 32: a manager cannot change roles.
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.update_establishment_member_role(
      (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_prof_a),
      'manager'
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Manager should NOT change roles';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 33: a professional cannot change roles (nor promote itself).
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.update_establishment_member_role(
      (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_prof_a),
      'manager'
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Professional should NOT change roles';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  BEGIN
    PERFORM public.set_establishment_member_active(
      (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_prof_a),
      false
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Professional should NOT deactivate links';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 34: the owner cannot change their own role nor deactivate themselves
  -- (the only owner of the establishment keeps the access).
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.update_establishment_member_role(
      (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_owner_a),
      'manager'
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Owner should NOT change the own role';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  BEGIN
    PERFORM public.set_establishment_member_active(
      (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_owner_a),
      false
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Owner should NOT deactivate the own link';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 35: the owner of A cannot manage members of B.
  BEGIN
    PERFORM public.update_establishment_member_role(
      (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_b AND user_id = v_prof_b),
      'professional'
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Owner of A should NOT manage members of B';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  BEGIN
    PERFORM public.set_establishment_member_active(
      (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_b AND user_id = v_prof_b),
      false
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Owner of A should NOT deactivate members of B';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 36: the owner manages granular permissions (and invalid keys are
  -- refused).
  PERFORM public.set_establishment_member_permissions(
    (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_prof_a),
    ARRAY['appointments.read', 'clients.read']
  );

  ASSERT (
    SELECT count(*) FROM public.member_permissions mp
    JOIN public.establishment_members em ON em.id = mp.member_id
    WHERE em.establishment_id = v_est_a AND em.user_id = v_prof_a
  ) = 2, 'Owner must be able to grant granular permissions';

  BEGIN
    PERFORM public.set_establishment_member_permissions(
      (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_prof_a),
      ARRAY['permissions.inventadas']
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Invalid permission should be rejected';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 37: a manager cannot grant permissions.
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.set_establishment_member_permissions(
      (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_prof_a),
      ARRAY['finances.delete']
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Manager should NOT grant permissions';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 38: invitation flow — a user joins establishment A and keeps the
  -- existing link in another establishment.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  v_token_shared := public.create_establishment_invitation(
    v_est_a,
    'shared@agenda.flow.test',
    NULL,
    'professional',
    ARRAY['appointments.read'],
    '7 days'::interval
  );

  PERFORM set_config('request.jwt.claim.sub', v_shared_user::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated","aud":"authenticated","email":"shared@agenda.flow.test"}', true);

  PERFORM public.accept_establishment_invitation(v_token_shared);

  ASSERT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_shared_user AND role = 'professional'
  ), 'Accepted invitation must create the membership';

  -- The same user also belongs to establishment B (created by owner B).
  PERFORM set_config('request.jwt.claim.sub', v_owner_b::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);

  v_token_shared_b := public.create_establishment_invitation(
    v_est_b,
    'shared@agenda.flow.test',
    NULL,
    'professional',
    ARRAY['clients.read'],
    '7 days'::interval
  );

  PERFORM set_config('request.jwt.claim.sub', v_shared_user::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated","aud":"authenticated","email":"shared@agenda.flow.test"}', true);

  PERFORM public.accept_establishment_invitation(v_token_shared_b);

  -- Test 39: deactivating the link in A removes the access to A but keeps B.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  PERFORM public.set_establishment_member_active(
    (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_shared_user),
    false
  );

  PERFORM set_config('request.jwt.claim.sub', v_shared_user::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated","aud":"authenticated","email":"shared@agenda.flow.test"}', true);

  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishments WHERE id = v_est_a
  ), 'Deactivated member must NOT read the establishment data';

  ASSERT EXISTS (
    SELECT 1 FROM public.establishments WHERE id = v_est_b
  ), 'Deactivation in A must NOT remove the link with B';

  ASSERT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_est_b AND user_id = v_shared_user
  ), 'Deactivation in A must NOT remove the membership in B';

  -- Test 40: expired, cancelled and already used invitations are refused.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  v_token_expired := public.create_establishment_invitation(
    v_est_a, 'expirado@agenda.flow.test', NULL, 'professional', '{}', '0 seconds'::interval
  );

  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_expired);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Expired invitation should NOT be accepted';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  v_token_cancelled := public.create_establishment_invitation(
    v_est_a, 'cancelado@agenda.flow.test', NULL, 'professional', '{}', '7 days'::interval
  );

  PERFORM public.cancel_establishment_invitation(
    (SELECT id FROM public.establishment_invitations
     WHERE establishment_id = v_est_a AND email = 'cancelado@agenda.flow.test')
  );

  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_cancelled);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Cancelled invitation should NOT be accepted';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  v_token_reused := public.create_establishment_invitation(
    v_est_a, 'legacy-user@agenda.flow.test', NULL, 'professional', '{}', '7 days'::interval
  );

  PERFORM set_config('request.jwt.claim.sub', v_legacy_user::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"88888888-8888-8888-8888-888888888888","role":"authenticated","aud":"authenticated","email":"legacy-user@agenda.flow.test"}', true);

  PERFORM public.accept_establishment_invitation(v_token_reused);

  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_reused);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Used invitation should NOT be accepted twice';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 41: an invitation of A cannot be accepted by a different identity.
  -- O contato convidado ainda NÃO é membro de A (pertence a outro
  -- estabelecimento), de modo que a recusa venha da verificação de identidade
  -- e não da regra de vínculo já existente.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  v_token_identity := public.create_establishment_invitation(
    v_est_a, 'legacy-user-2@agenda.flow.test', NULL, 'professional', '{}', '7 days'::interval
  );

  PERFORM set_config('request.jwt.claim.sub', v_prof_b::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","aud":"authenticated","email":"prof-b@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_identity);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Invitation should NOT be accepted by another identity';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 42: duplicated pending invitation for the same contact is refused.
  BEGIN
    PERFORM public.create_establishment_invitation(
      v_est_a, 'prof-a@agenda.flow.test', NULL, 'professional', '{}', '7 days'::interval
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Duplicated pending invitation should be rejected';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Test 43: an invitation of A grants access only to A.
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_est_b AND user_id = v_legacy_user
  ), 'Invitation of A must NOT create a link with B';

  --------------------------------------------------------------------------
  -- Test 44: convites pendentes por identidade autenticada (onboarding).
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  v_token_email := public.create_establishment_invitation(
    v_est_a, 'email-user@agenda.flow.test', NULL, 'professional', '{}', '7 days'::interval
  );

  -- O convidado (sem vínculo) enxerga o próprio convite pendente.
  PERFORM set_config('request.jwt.claim.sub', v_email_user::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated","email":"email-user@agenda.flow.test"}', true);

  ASSERT (SELECT count(*) FROM public.get_my_pending_invitations()) = 1,
    'The RPC must list the pending invitation addressed to the caller';

  ASSERT (
    SELECT establishment_name FROM public.get_my_pending_invitations() LIMIT 1
  ) IS NOT NULL, 'The RPC must expose the establishment name of the invitation';

  -- Nenhum convite de outra identidade é exposto.
  PERFORM set_config('request.jwt.claim.sub', v_prof_b::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","email":"prof-b@agenda.flow.test"}', true);

  ASSERT (SELECT count(*) FROM public.get_my_pending_invitations()) = 0,
    'The RPC must NOT expose invitations addressed to other identities';

  --------------------------------------------------------------------------
  -- Test 45: o proprietário não pode ser convidado para a própria empresa.
  --
  -- O convite é recusado NA ORIGEM (create_establishment_invitation) e, se
  -- ainda assim existir um convite pendente, o aceite é recusado sem criar
  -- vínculo e sem alterar o cargo de proprietário.
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.create_establishment_invitation(
      v_est_a, 'owner-a@agenda.flow.test', NULL, 'professional', '{}', '7 days'::interval
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Owner should NOT be invited to the own establishment';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- O convite recusado não deixou nenhum registro pendente para o dono.
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_invitations
    WHERE establishment_id = v_est_a
      AND email = 'owner-a@agenda.flow.test'
      AND accepted_at IS NULL
      AND cancelled_at IS NULL
  ), 'A refused invitation to the owner must NOT be persisted';

  -- O vínculo de proprietário continua único e com o cargo intacto.
  ASSERT (
    SELECT count(*) FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_owner_a
  ) = 1, 'The owner must keep exactly one link in the establishment';

  ASSERT (
    SELECT role FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_owner_a
  ) = 'owner', 'The owner role must be preserved';

  ASSERT public.is_establishment_owner(v_est_a) = true,
    'The owner must keep the owner privileges';

  --------------------------------------------------------------------------
  -- Test 46: quem já pertence ao estabelecimento não cria um segundo vínculo.
  --
  -- Um convite forçado (criado fora do fluxo normal) é recusado no aceite:
  -- nenhum vínculo é criado, nenhum cargo é trocado ou rebaixado. O cenário
  -- completo está na seção 3.2 (o convite forjado é inserido pelo dono do
  -- banco, porque o role da API não tem escrita direta).
  --------------------------------------------------------------------------

  --------------------------------------------------------------------------
  -- Test 50: o fluxo comum de convites nunca cria outro PROPRIETÁRIO.
  --
  -- A transferência de propriedade não faz parte desta etapa: o cargo
  -- 'owner' não é concedível por convite, nem pelo proprietário, nem pelo
  -- gerente. O proprietário atual e establishments.owner_id são preservados.
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.create_establishment_invitation(
      v_est_a, 'segundo-owner@agenda.flow.test', NULL, 'owner', '{}', '7 days'::interval
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Invitation should NOT create another owner';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Um gerente também não pode criar um proprietário.
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.create_establishment_invitation(
      v_est_a, 'segundo-owner@agenda.flow.test', NULL, 'owner', '{}', '7 days'::interval
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Manager should NOT create an owner';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Nenhum convite pendente carrega o cargo de proprietário.
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_invitations
    WHERE establishment_id = v_est_a AND role = 'owner'
  ), 'No invitation may carry the owner role';

  -- O vínculo e o cargo do proprietário seguem intactos.
  ASSERT (
    SELECT count(*) FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_owner_a
  ) = 1, 'The owner must keep exactly one link in the establishment';

  ASSERT (
    SELECT role FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_owner_a
  ) = 'owner', 'The owner role must be preserved';

  ASSERT (
    SELECT owner_id FROM public.establishments WHERE id = v_est_a
  ) = v_owner_a, 'establishments.owner_id must be preserved';

  --------------------------------------------------------------------------
  -- Test 51: um gerente não cria outros administradores.
  --------------------------------------------------------------------------
  BEGIN
    PERFORM public.create_establishment_invitation(
      v_est_a, 'gerente-novo@agenda.flow.test', NULL, 'manager', '{}', '7 days'::interval
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Manager should NOT invite another manager';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- O proprietário pode convidar um gerente (carga de administrador).
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  v_token_manager2 := public.create_establishment_invitation(
    v_est_a, 'gerente-novo@agenda.flow.test', NULL, 'manager', ARRAY['appointments.read'], '7 days'::interval
  );

  ASSERT v_token_manager2 IS NOT NULL,
    'The owner must be able to invite a manager with valid permissions';

  --------------------------------------------------------------------------
  -- Test 52: permissões inválidas ou não autorizadas são recusadas NO BANCO.
  --
  -- O parâmetro p_permissions é validado pelo PostgreSQL: apenas chaves
  -- previstas no schema do projeto são aceitas e o gerente concede somente
  -- as permissões que possui.
  --------------------------------------------------------------------------
  BEGIN
    PERFORM public.create_establishment_invitation(
      v_est_a, 'permissao-invalida@agenda.flow.test', NULL, 'professional',
      ARRAY['permissions.inventadas'], '7 days'::interval
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Invalid permission should be rejected';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- O gerente tenta conceder uma permissão que não possui (acima das suas).
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.create_establishment_invitation(
      v_est_a, 'escalonamento@agenda.flow.test', NULL, 'professional',
      ARRAY['finances.delete'], '7 days'::interval
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Manager should NOT grant permissions that it does not hold';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- O gerente pode delegar uma permissão que possui (appointments.read).
  v_token_delegated := public.create_establishment_invitation(
    v_est_a, 'delegado@agenda.flow.test', NULL, 'professional',
    ARRAY['appointments.read'], '7 days'::interval
  );

  ASSERT v_token_delegated IS NOT NULL,
    'A manager must be able to delegate a permission that it holds';

  -- O proprietário pode conceder qualquer chave válida da matriz.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  v_token_owner_permissions := public.create_establishment_invitation(
    v_est_a, 'permissao-valida@agenda.flow.test', NULL, 'professional',
    ARRAY['finances.delete', 'settings.write'], '7 days'::interval
  );

  ASSERT v_token_owner_permissions IS NOT NULL,
    'The owner must be able to grant any valid permission of the project matrix';

  --------------------------------------------------------------------------
  -- Test 53: isolamento entre estabelecimentos no fluxo de convites.
  --
  -- Um gerente de A não convida em B e nenhum convite de A cria vínculo em B.
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.create_establishment_invitation(
      v_est_b, 'intruso-b@agenda.flow.test', NULL, 'professional', '{}', '7 days'::interval
    );
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Manager of A should NOT invite into B';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_est_b AND user_id = v_manager_a
  ), 'A manager of A must NOT gain a link in B through an invitation';

  RAISE NOTICE 'All application assertions passed.';
END $$;

RESET ROLE;

--------------------------------------------------------------------------------
-- 3.2 Convites forjados (dono do banco)
--------------------------------------------------------------------------------
-- Simula convites que chegaram FORA do fluxo normal (e-mail antigo, banco
-- restaurado, convite criado por outra ferramenta) endereçados a pessoas que
-- JÁ pertencem ao estabelecimento. O fluxo normal (create_establishment_
-- invitation) recusa esse tipo de convite; aqui o registro é inserido pelo
-- dono do banco para provar que o ACEITE também é seguro.
--
-- Os tokens ficam disponíveis para a seção seguinte via set_config.
DO $$
DECLARE
  v_est_a uuid;
  v_owner_a uuid := '11111111-1111-1111-1111-111111111111';
  v_prof_a  uuid := '22222222-2222-2222-2222-222222222222';
  v_manager_a uuid := '33333333-3333-3333-3333-333333333333';
  v_email_user uuid := '77777777-7777-7777-7777-777777777777';
  v_token_owner_self text;
  v_token_prof_again text;
  v_token_escalation_owner text;
  v_token_escalation_permissions text;
  v_token_escalation_invalid text;
  v_token_escalation_manager text;
BEGIN
  SELECT id INTO v_est_a FROM public.establishments WHERE slug = 'barbearia-alpha';

  v_token_owner_self := encode(
    sha256(convert_to(
      'agenda-flow-owner-self-' || v_est_a::text || '-' || v_owner_a::text,
      'utf8'
    )),
    'hex'
  );

  v_token_prof_again := encode(
    sha256(convert_to(
      'agenda-flow-prof-again-' || v_est_a::text || '-' || v_prof_a::text,
      'utf8'
    )),
    'hex'
  );

  -- Convite antigo que tentaria transferir a propriedade.
  v_token_escalation_owner := encode(
    sha256(convert_to(
      'agenda-flow-escalation-owner-' || v_est_a::text || '-' || v_email_user::text,
      'utf8'
    )),
    'hex'
  );

  -- Convite antigo com permissões acima das do concedente (gerente).
  v_token_escalation_permissions := encode(
    sha256(convert_to(
      'agenda-flow-escalation-permissions-' || v_est_a::text || '-' || v_email_user::text,
      'utf8'
    )),
    'hex'
  );

  -- Convite antigo com chave de permissão inexistente.
  v_token_escalation_invalid := encode(
    sha256(convert_to(
      'agenda-flow-escalation-invalid-' || v_est_a::text || '-' || v_email_user::text,
      'utf8'
    )),
    'hex'
  );

  -- Convite antigo de gerente criado por um gerente (carga de administrador).
  v_token_escalation_manager := encode(
    sha256(convert_to(
      'agenda-flow-escalation-manager-' || v_est_a::text || '-' || v_email_user::text,
      'utf8'
    )),
    'hex'
  );

  INSERT INTO public.establishment_invitations (
    establishment_id, email, token_hash, role, permissions, invited_by, expires_at
  ) VALUES (
    v_est_a, 'owner-a@agenda.flow.test', v_token_owner_self, 'professional', '{}',
    v_owner_a, now() + interval '7 days'
  );

  INSERT INTO public.establishment_invitations (
    establishment_id, email, token_hash, role, permissions, invited_by, expires_at
  ) VALUES (
    v_est_a, 'prof-a@agenda.flow.test', v_token_prof_again, 'manager', '{}',
    v_owner_a, now() + interval '7 days'
  );

  INSERT INTO public.establishment_invitations (
    establishment_id, email, token_hash, role, permissions, invited_by, expires_at
  ) VALUES (
    v_est_a, 'email-user@agenda.flow.test', v_token_escalation_owner, 'owner', '{}',
    v_owner_a, now() + interval '7 days'
  );

  INSERT INTO public.establishment_invitations (
    establishment_id, email, token_hash, role, permissions, invited_by, expires_at
  ) VALUES (
    v_est_a, 'email-user@agenda.flow.test', v_token_escalation_permissions, 'professional',
    ARRAY['finances.delete'], v_manager_a, now() + interval '7 days'
  );

  INSERT INTO public.establishment_invitations (
    establishment_id, email, token_hash, role, permissions, invited_by, expires_at
  ) VALUES (
    v_est_a, 'email-user@agenda.flow.test', v_token_escalation_invalid, 'professional',
    ARRAY['permissions.inventadas'], v_owner_a, now() + interval '7 days'
  );

  INSERT INTO public.establishment_invitations (
    establishment_id, email, token_hash, role, permissions, invited_by, expires_at
  ) VALUES (
    v_est_a, 'email-user@agenda.flow.test', v_token_escalation_manager, 'manager', '{}',
    v_manager_a, now() + interval '7 days'
  );

  PERFORM set_config('agenda_flow.token_owner_self', v_token_owner_self, true);
  PERFORM set_config('agenda_flow.token_prof_again', v_token_prof_again, true);
  PERFORM set_config('agenda_flow.token_escalation_owner', v_token_escalation_owner, true);
  PERFORM set_config('agenda_flow.token_escalation_permissions', v_token_escalation_permissions, true);
  PERFORM set_config('agenda_flow.token_escalation_invalid', v_token_escalation_invalid, true);
  PERFORM set_config('agenda_flow.token_escalation_manager', v_token_escalation_manager, true);

  RAISE NOTICE 'Forced invitations created for the membership integrity scenarios.';
END $$;

SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_est_a uuid;
  v_est_b uuid;
  v_owner_a uuid := '11111111-1111-1111-1111-111111111111';
  v_prof_a  uuid := '22222222-2222-2222-2222-222222222222';
  v_shared_user uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_email_user uuid := '77777777-7777-7777-7777-777777777777';
  v_token_owner_self text;
  v_token_prof_again text;
  v_token_escalation_owner text;
  v_token_escalation_permissions text;
  v_token_escalation_invalid text;
  v_token_escalation_manager text;
BEGIN
  -- A sessão herda as claims do bloco anterior: fixamos a identidade do
  -- proprietário para ler o estabelecimento A (a RLS só revela o próprio
  -- tenant).
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  SELECT id INTO v_est_a FROM public.establishments WHERE slug = 'barbearia-alpha';

  v_token_owner_self := current_setting('agenda_flow.token_owner_self');
  v_token_prof_again := current_setting('agenda_flow.token_prof_again');
  v_token_escalation_owner := current_setting('agenda_flow.token_escalation_owner');
  v_token_escalation_permissions := current_setting('agenda_flow.token_escalation_permissions');
  v_token_escalation_invalid := current_setting('agenda_flow.token_escalation_invalid');
  v_token_escalation_manager := current_setting('agenda_flow.token_escalation_manager');

  --------------------------------------------------------------------------
  -- Test 46: o proprietário não aceita convite para a própria empresa.
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_owner_self);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Invitation should NOT create a second link';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  ASSERT (
    SELECT count(*) FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_owner_a
  ) = 1, 'Accepting an invitation must NOT create a duplicated link';

  ASSERT (
    SELECT role FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_owner_a
  ) = 'owner', 'The owner must NOT be demoted by an invitation';

  ASSERT public.is_establishment_owner(v_est_a) = true,
    'The owner must keep the owner privileges after the refused invitation';

  --------------------------------------------------------------------------
  -- Test 47: o convidado que já é da equipe não cria vínculo duplicado.
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_prof_again);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Invitation should NOT create a second link';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  ASSERT (
    SELECT count(*) FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_prof_a
  ) = 1, 'The employee must keep exactly one link in the establishment';

  ASSERT (
    SELECT role FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_prof_a
  ) = 'professional',
    'The employee role must NOT be silently replaced by an invitation';

  --------------------------------------------------------------------------
  -- Test 54: convites já existentes não provocam escalonamento de privilégios.
  --
  -- Convites forjados (criados fora do fluxo normal) são REVALIDADOS no
  -- aceite: cargo de proprietário, permissões acima das do concedente e
  -- chaves inexistentes são recusados — sem criar vínculo e sem conceder
  -- qualquer privilégio.
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_email_user::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated","aud":"authenticated","email":"email-user@agenda.flow.test"}', true);

  -- (a) Convite antigo com cargo de proprietário (transferência de propriedade).
  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_escalation_owner);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'An old invitation must NOT transfer the ownership';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- (b) Convite antigo com permissões acima das do concedente (gerente).
  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_escalation_permissions);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'An old invitation must NOT grant permissions above the granter';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- (c) Convite antigo com chave de permissão inexistente.
  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_escalation_invalid);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'An old invitation must NOT grant an unknown permission';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- (d) Convite antigo de gerente criado por um gerente.
  BEGIN
    PERFORM public.accept_establishment_invitation(v_token_escalation_manager);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'An old invitation must NOT create another administrator';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Nenhum vínculo foi criado e nenhuma permissão foi concedida.
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_email_user
  ), 'A refused escalation must NOT create a link';

  ASSERT NOT EXISTS (
    SELECT 1
    FROM public.member_permissions mp
    JOIN public.establishment_members m ON m.id = mp.member_id
    WHERE m.establishment_id = v_est_a
      AND m.user_id = v_email_user
  ), 'A refused escalation must NOT grant permissions';

  -- O recusado não ganhou acesso a nenhum estabelecimento.
  ASSERT (SELECT count(*) FROM public.establishments) = 0,
    'A refused invitation must NOT grant access to any establishment';

  -- O proprietário e o cargo de proprietário seguem intactos.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  ASSERT (
    SELECT count(*) FROM public.establishment_members
    WHERE establishment_id = v_est_a AND user_id = v_owner_a AND role = 'owner'
  ) = 1, 'The owner link must be preserved after the refused escalations';

  ASSERT (
    SELECT owner_id FROM public.establishments WHERE id = v_est_a
  ) = v_owner_a, 'establishments.owner_id must be preserved';

  --------------------------------------------------------------------------
  -- Test 55: isolamento entre estabelecimentos após as recusas.
  --
  -- O profissional de A enxerga apenas o próprio tenant: nem o estabelecimento
  -- nem os vínculos de B são visíveis.
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);

  ASSERT (SELECT count(*) FROM public.establishments) = 1,
    'A member of A must see only its own establishment';

  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishments WHERE slug = 'salao-beta'
  ), 'A member of A must NOT read the establishment of another tenant';

  ASSERT (
    SELECT count(*) FROM public.establishment_members
    WHERE user_id = v_prof_a
  ) = 1, 'A member of A must NOT have a link in another tenant';

  --------------------------------------------------------------------------
  -- Test 48: a listagem do frontend (vínculos do usuário autenticado) retorna
  -- UMA linha por estabelecimento — é o que evita a empresa duplicada.
  --
  -- A RLS permite que um membro leia os vínculos dos colegas do tenant (necessário
  -- para a tela de equipe). A consulta do frontend filtra por user_id: por isso
  -- o profissional de A enxerga apenas o PRÓPRIO vínculo, mesmo com outros
  -- membros no mesmo estabelecimento.
  --------------------------------------------------------------------------
  ASSERT (
    SELECT count(*) FROM public.establishment_members
    WHERE user_id = v_prof_a AND is_active = true
  ) = 1, 'The listing of the authenticated user must return a single link';

  ASSERT (
    SELECT count(DISTINCT establishment_id) FROM public.establishment_members
    WHERE user_id = v_prof_a AND is_active = true
  ) = 1, 'The listing of the authenticated user must not repeat establishments';

  -- O cargo visto pelo frontend é o do PRÓPRIO vínculo (nunca o do colega).
  ASSERT (
    SELECT role FROM public.establishment_members
    WHERE user_id = v_prof_a AND is_active = true
  ) = 'professional',
    'The role exposed to the frontend must be the role of the own link';

  -- Isolamento multi-tenant: o profissional de A não enxerga vínculos de B.
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE user_id = v_prof_a AND establishment_id <> v_est_a
  ), 'The user must NOT have links to another tenant';

  --------------------------------------------------------------------------
  -- Test 49: vínculo desativado não aparece na listagem e não dá acesso.
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_shared_user::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated","aud":"authenticated","email":"shared@agenda.flow.test"}', true);

  ASSERT (
    SELECT count(*) FROM public.establishment_members
    WHERE user_id = v_shared_user AND is_active = true
  ) = 1, 'A deactivated link must NOT appear in the listing of the user';

  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishments WHERE id = v_est_a
  ), 'A deactivated link must NOT grant access to the establishment';

  RAISE NOTICE 'Membership integrity assertions passed.';
END $$;

RESET ROLE;

--------------------------------------------------------------------------------
-- 3.2 Gestão de profissionais e associação de serviços (etapa 7)
--
-- Conceitos independentes: o CARGO (permissões administrativas) e a
-- HABILITAÇÃO para receber atendimentos. Qualquer membro ativo pode ser
-- habilitado; o gerenciamento é exclusivo do proprietário; a integridade
-- entre estabelecimentos é garantida por FKs compostas.
--------------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- Contexto: dono do estabelecimento A.
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

DO $$
DECLARE
  v_owner_a uuid := '11111111-1111-1111-1111-111111111111';
  v_prof_a uuid := '22222222-2222-2222-2222-222222222222';
  v_manager_a uuid := '33333333-3333-3333-3333-333333333333';
  v_prof_b uuid := '55555555-5555-5555-5555-555555555555';
  v_shared_user uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_est_a uuid;
  v_est_b uuid;
  v_member_owner uuid;
  v_member_prof_a uuid;
  v_member_manager uuid;
  v_member_shared uuid;
  v_service_a uuid;
  v_service_barba uuid;
  v_service_sobrancelha uuid;
  v_service_infantil uuid;
  v_professional_owner uuid;
  v_professional_prof_a uuid;
  v_professional_manager uuid;
  v_permissions_before integer;
  v_debug_total integer;
BEGIN
  ASSERT current_user = 'authenticated',
    'The professionals scenarios must run as the authenticated role, not as the table owner';

  SELECT id INTO v_est_a FROM public.establishments WHERE slug = 'barbearia-alpha';
  -- v_est_b é selecionado sob as claims do DONO DE B (a RLS oculta o
  -- estabelecimento alheio; sob as claims de A a seleção devolveria NULL
  -- e as asserções cross-tenant seriam vazias).
  PERFORM set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);

  SELECT id INTO v_est_b FROM public.establishments WHERE slug = 'salao-beta';

  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  SELECT id INTO v_member_owner FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_owner_a;
  SELECT id INTO v_member_prof_a FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_prof_a;
  SELECT id INTO v_member_manager FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_manager_a;
  SELECT id INTO v_member_shared FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = v_shared_user;
  SELECT id INTO v_service_a FROM public.establishment_services WHERE establishment_id = v_est_a;

  SELECT count(*) INTO v_permissions_before
  FROM public.member_permissions mp
  JOIN public.establishment_members em ON em.id = mp.member_id
  WHERE em.establishment_id = v_est_a AND em.user_id = v_prof_a;

  --------------------------------------------------------------------------
  -- Test 55: o proprietário habilita membros com cargos DIFERENTES
  -- (owner, manager e professional) como profissionais de atendimento.
  --------------------------------------------------------------------------
  PERFORM public.set_establishment_professional(v_member_owner, true);
  PERFORM public.set_establishment_professional(v_member_prof_a, true);
  PERFORM public.set_establishment_professional(v_member_manager, true);

  ASSERT (
    SELECT count(*) FROM public.establishment_professionals
    WHERE establishment_id = v_est_a
  ) = 3, 'Three members must be enabled as professionals';

  ASSERT (
    SELECT ep.accepts_appointments
    FROM public.establishment_professionals ep
    JOIN public.establishment_members em ON em.id = ep.member_id
    WHERE ep.establishment_id = v_est_a AND em.user_id = v_owner_a
  ) = true, 'The owner member can be enabled as a professional';

  -- A habilitação NÃO altera cargo, permissões nem o vínculo.
  ASSERT (
    SELECT em.role FROM public.establishment_members em
    JOIN public.establishment_professionals ep ON ep.member_id = em.id
    WHERE ep.establishment_id = v_est_a AND em.user_id = v_prof_a
  ) = 'professional', 'Enabling a professional must NOT change the member role';

  ASSERT (
    SELECT count(*) FROM public.member_permissions mp
    JOIN public.establishment_members em ON em.id = mp.member_id
    WHERE em.establishment_id = v_est_a AND em.user_id = v_prof_a
  ) = v_permissions_before, 'Enabling a professional must NOT change administrative permissions';

  ASSERT (
    SELECT em.is_active FROM public.establishment_members em
    JOIN public.establishment_professionals ep ON ep.member_id = em.id
    WHERE ep.establishment_id = v_est_a AND em.user_id = v_prof_a
  ) = true, 'Enabling a professional must NOT deactivate the membership';

  --------------------------------------------------------------------------
  -- Test 56: re-habilitação é idempotente (um único registro por membro)
  -- e a pausa (false) preserva o registro sem desativar o vínculo.
  --------------------------------------------------------------------------
  PERFORM public.set_establishment_professional(v_member_prof_a, true);

  ASSERT (
    SELECT count(*) FROM public.establishment_professionals
    WHERE establishment_id = v_est_a AND member_id = v_member_prof_a
  ) = 1, 'Re-enabling a professional must NOT duplicate the record';

  PERFORM public.set_establishment_professional(v_member_prof_a, false);

  ASSERT (
    SELECT accepts_appointments FROM public.establishment_professionals
    WHERE establishment_id = v_est_a AND member_id = v_member_prof_a
  ) = false, 'Pausing a professional must be persisted';

  ASSERT (
    SELECT em.is_active FROM public.establishment_members em
    WHERE em.id = v_member_prof_a
  ) = true, 'Pausing a professional must NOT deactivate the membership';

  ASSERT (
    SELECT em.role FROM public.establishment_members em
    WHERE em.id = v_member_prof_a
  ) = 'professional', 'Pausing a professional must NOT change the role';

  PERFORM public.set_establishment_professional(v_member_prof_a, true);

  ASSERT (
    SELECT accepts_appointments FROM public.establishment_professionals
    WHERE establishment_id = v_est_a AND member_id = v_member_prof_a
  ) = true, 'Re-enabling after the pause restores acceptance';

  --------------------------------------------------------------------------
  -- Test 57: apenas o proprietário habilita profissionais — gerente e
  -- profissional não podem habilitar (nem a si mesmos).
  --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.set_establishment_professional(v_member_prof_a, true);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Manager should NOT enable professionals';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.set_establishment_professional(v_member_prof_a, true);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Professional should NOT enable itself as a professional';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- O proprietário de OUTRO estabelecimento não habilita membros de A.
  PERFORM set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.set_establishment_professional(v_member_prof_a, true);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Owner of B should NOT enable members of A';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Volta ao dono de A.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  --------------------------------------------------------------------------
  -- Test 58: membro com vínculo DESATIVADO não pode ser habilitado.
  -- (O vínculo de shared_user em A foi desativado no Test 39 e segue assim.)
  --------------------------------------------------------------------------
  BEGIN
    PERFORM public.set_establishment_professional(v_member_shared, true);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Deactivated link should NOT be enabled as a professional';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  --------------------------------------------------------------------------
  -- Test 59: associações de serviços — o proprietário associa o MESMO
  -- serviço a vários profissionais e vários serviços a um profissional.
  --------------------------------------------------------------------------
  SELECT ep.id INTO v_professional_prof_a
  FROM public.establishment_professionals ep
  WHERE ep.establishment_id = v_est_a AND ep.member_id = v_member_prof_a;

  SELECT ep.id INTO v_professional_owner
  FROM public.establishment_professionals ep
  WHERE ep.establishment_id = v_est_a AND ep.member_id = v_member_owner;

  SELECT ep.id INTO v_professional_manager
  FROM public.establishment_professionals ep
  WHERE ep.establishment_id = v_est_a AND ep.member_id = v_member_manager;

  -- Segundo serviço de A (ativo), criado pelo próprio dono.
  v_service_barba := public.create_establishment_service(
    p_establishment_id => v_est_a,
    p_name => 'Barba',
    p_category => 'barba',
    p_duration_minutes => 20,
    p_price_cents => 2500,
    p_is_active => true
  );

  -- Mesmo serviço para dois profissionais.
  PERFORM public.add_establishment_professional_service(v_professional_prof_a, v_service_a);
  PERFORM public.add_establishment_professional_service(v_professional_manager, v_service_a);

  -- Vários serviços para o mesmo profissional.
  PERFORM public.add_establishment_professional_service(v_professional_prof_a, v_service_barba);

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE establishment_id = v_est_a
  ) = 3, 'The associations must be persisted';

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE professional_id = v_professional_prof_a
  ) = 2, 'A professional may hold multiple services';

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE service_id = v_service_a
  ) = 2, 'A service may be associated to multiple professionals';

  --------------------------------------------------------------------------
  -- Test 60: associação DUPLICADA é recusada (nenhuma linha extra).
  --------------------------------------------------------------------------
  BEGIN
    PERFORM public.add_establishment_professional_service(v_professional_prof_a, v_service_a);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Duplicated association should be rejected';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE professional_id = v_professional_prof_a AND service_id = v_service_a
  ) = 1, 'A duplicated association must NOT be persisted';

  --------------------------------------------------------------------------
  -- Test 61: isolamento entre estabelecimentos — tentativa de associar um
  -- serviço de B a um profissional de A é recusada pela RPC E pela FK
  -- composta (teste de FK bloqueio direto na seção do papel sonda).
  --------------------------------------------------------------------------
  -- Identidade REAL do serviço de B (selecionado sob as claims do dono de
  -- B; sob as claims de A o catálogo alheio é invisível e o teste seria
  -- vago — a RPC recusaria um NULL por outro motivo).
  PERFORM set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);

  DECLARE
    v_service_b uuid;
  BEGIN
    SELECT id INTO v_service_b FROM public.establishment_services WHERE establishment_id = v_est_b;
    ASSERT v_service_b IS NOT NULL, 'Service B must exist and be selectable by its own owner';

    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
    PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

    BEGIN
      PERFORM public.add_establishment_professional_service(v_professional_prof_a, v_service_b);
      RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Cross-tenant association should be rejected';
    EXCEPTION WHEN raise_exception THEN
      -- expected (Servico nao encontrado neste estabelecimento)
    END;
  END;

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE service_id IN (SELECT id FROM public.establishment_services WHERE establishment_id = v_est_b)
  ) = 0, 'No association may cross establishments';

  -- O dono de B não pode gerenciar os profissionais de A. A adição usa o
  -- profissional-proprietário com o serviço "Barba" (par ainda INÉDITO) e a
  -- remoção usa o par (profª, acesso Servico A) que JÁ EXISTE: se a
  -- autorização falhasse, a contagem total e a contagem do profissional
  -- mudariam — assertivas abaixo não são vagas.
  PERFORM set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.add_establishment_professional_service(v_professional_owner, v_service_barba);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Owner of B should NOT manage professionals of A';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  BEGIN
    PERFORM public.remove_establishment_professional_service(v_professional_prof_a, v_service_a);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Owner of B should NOT remove associations of A';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Volta ao dono de A: as contagens abaixo são lidas sob identity com
  -- acesso ao estabelecimento (a RLS filtra as linhas de outra pessoa).
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  SELECT count(*) INTO v_debug_total FROM public.establishment_professional_services WHERE establishment_id = v_est_a;
  IF v_debug_total <> 3 THEN
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = format(
      'Associations must be unchanged after the foreign owner attempts (atual=%s; prof_a=%s; owner_barba=%s; svc_a=%s)',
      v_debug_total,
      (SELECT count(*) FROM public.establishment_professional_services WHERE professional_id = v_professional_prof_a),
      (SELECT count(*) FROM public.establishment_professional_services WHERE professional_id = v_professional_owner AND service_id = v_service_barba),
      (SELECT count(*) FROM public.establishment_professional_services WHERE service_id = v_service_a));
  END IF;

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE professional_id = v_professional_prof_a
  ) = 2, 'The foreign owner must not remove existing associations';

  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  --------------------------------------------------------------------------
  -- Test 62: nenhum membro que não seja o proprietário associa serviços.
  -- Um serviço NOVO (par ainda inédito) torna a tentativa discriminante:
  -- quebra da autorização gravaria a associação e a contagem mudaria.
  --------------------------------------------------------------------------
  v_service_sobrancelha := public.create_establishment_service(
    p_establishment_id => v_est_a,
    p_name => 'Sombrancelha',
    p_category => 'estetica',
    p_duration_minutes => 15,
    p_price_cents => 1800,
    p_is_active => true
  );

  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.add_establishment_professional_service(v_professional_prof_a, v_service_sobrancelha);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Manager should NOT associate services';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE professional_id = v_professional_prof_a
  ) = 2, 'The manager must not add associations';

  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);

  BEGIN
    PERFORM public.add_establishment_professional_service(v_professional_prof_a, v_service_sobrancelha);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Professional should NOT associate services to itself';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE professional_id = v_professional_prof_a
  ) = 2, 'The professional must not add associations to itself';

  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);

  --------------------------------------------------------------------------
  -- Test 63: serviço INATIVO não recebe NOVA associação; a associação que
  -- já existia é PRESERVADA (sem exclusão histórica).
  --------------------------------------------------------------------------
  PERFORM public.set_establishment_service_active(v_service_barba, false);

  -- A associação preexistente continua lá.
  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE professional_id = v_professional_prof_a AND service_id = v_service_barba
  ) = 1, 'Deactivating a service must preserve existing associations';

  -- Nova associação com o serviço inativo é recusada.
  BEGIN
    PERFORM public.add_establishment_professional_service(v_professional_manager, v_service_barba);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Inactive service should NOT receive new associations';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- Nenhuma associação com o serviço inativo pode ter sido criada.
  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE establishment_id = v_est_a
  ) = 3, 'An inactive service must NOT receive associations';

  -- Reativar permite novas associações novamente.
  PERFORM public.set_establishment_service_active(v_service_barba, true);
  PERFORM public.add_establishment_professional_service(v_professional_manager, v_service_barba);

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE establishment_id = v_est_a
  ) = 4, 'Reactivated service must accept associations again';

  --------------------------------------------------------------------------
  -- Test 64: remover associação é exclusivo do dono, com feedback correto.
  --------------------------------------------------------------------------
  PERFORM public.remove_establishment_professional_service(v_professional_prof_a, v_service_barba);

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE professional_id = v_professional_prof_a AND service_id = v_service_barba
  ) = 0, 'The association must be removed';

  BEGIN
    PERFORM public.remove_establishment_professional_service(v_professional_prof_a, v_service_barba);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Removing a missing association should be rejected';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  --------------------------------------------------------------------------
  -- Test 65: pausa do profissional preserva cargo, permissões, vínculo e
  -- as associações de serviços existentes.
  --------------------------------------------------------------------------
  PERFORM public.set_establishment_service_active(v_service_barba, false);

  PERFORM public.set_establishment_professional(v_member_prof_a, false);

  ASSERT (
    SELECT em.is_active FROM public.establishment_members em
    WHERE em.id = v_member_prof_a
  ) = true, 'Pausing must NOT deactivate the membership';

  ASSERT (
    SELECT em.role FROM public.establishment_members em
    WHERE em.id = v_member_prof_a
  ) = 'professional', 'Pausing must NOT change the role';

  ASSERT (
    SELECT count(*) FROM public.member_permissions mp
    JOIN public.establishment_members em ON em.id = mp.member_id
    WHERE em.establishment_id = v_est_a AND em.user_id = v_prof_a
  ) = v_permissions_before, 'Pausing must NOT change administrative permissions';

  ASSERT EXISTS (
    SELECT 1 FROM public.establishment_professional_services
    WHERE professional_id = v_professional_prof_a
  ), 'Pausing must preserve the existing service associations';

  --------------------------------------------------------------------------
  -- Test 66: vínculo DESATIVADO não recebe novas associações nem nova
  -- habilitação; associações antigas são preservadas (nada é excluído) e o
  -- estado profissional permanece o anterior às tentativas.
  --------------------------------------------------------------------------
  -- Serviço novo e ATIVO (par ainda inédito): se a validação de vínculo
  -- falhasse, a associação seria gravada e a contagem mudaria.
  v_service_infantil := public.create_establishment_service(
    p_establishment_id => v_est_a,
    p_name => 'Corte Infantil',
    p_category => 'cabelo',
    p_duration_minutes => 25,
    p_price_cents => 2200,
    p_is_active => true
  );

  PERFORM public.set_establishment_member_active(v_member_prof_a, false);

  -- Tentativa de re-habilitar o vínculo desativado.
  BEGIN
    PERFORM public.set_establishment_professional(v_member_prof_a, true);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Deactivated link should NOT be re-enabled';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- A pausa anterior (Test 65) permanece: a tentativa não alterou o estado.
  ASSERT (
    SELECT ep.accepts_appointments FROM public.establishment_professionals ep
    WHERE ep.id = v_professional_prof_a
  ) = false, 'A refused attempt must NOT re-enable the paused professional';

  -- Tentativa de nova associação para o vínculo desativado.
  BEGIN
    PERFORM public.add_establishment_professional_service(v_professional_prof_a, v_service_infantil);
    RAISE EXCEPTION USING ERRCODE = 'P0004', MESSAGE = 'Deactivated link should NOT receive new services';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- A associação antiga permanece e NENHUMA nova foi criada.
  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE professional_id = v_professional_prof_a
  ) = 1, 'Deactivation must preserve history and refuse new associations';

  -- Reativação do vínculo restaura a elegibilidade (a pausa é revertida).
  PERFORM public.set_establishment_member_active(v_member_prof_a, true);

  PERFORM public.set_establishment_professional(v_member_prof_a, true);

  --------------------------------------------------------------------------
  -- Test 67: escrita DIRETA nas tabelas novas é recusada (somente leitura
  -- para o role da API).
  --------------------------------------------------------------------------
  BEGIN
    INSERT INTO public.establishment_professionals (establishment_id, member_id)
    VALUES (v_est_a, v_member_shared);
    RAISE EXCEPTION 'Authenticated role should NOT insert professionals directly';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected
  END;

  BEGIN
    UPDATE public.establishment_professionals SET accepts_appointments = false;
    RAISE EXCEPTION 'Authenticated role should NOT update professionals directly';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected
  END;

  BEGIN
    DELETE FROM public.establishment_professional_services;
    RAISE EXCEPTION 'Authenticated role should NOT delete associations directly';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected
  END;

  --------------------------------------------------------------------------
  -- Test 68: RLS — o profissional de A lê os profissionais DELE
  -- estabelecimento e não os de B.
  --------------------------------------------------------------------------
  -- O estabelecimento B também tem um profissional habilitado, para que a
  -- asserção de isolamento seja de fato discriminante (uma fuga de RLS
  -- traria a linha de B para a leitura de A).
  PERFORM set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444', true);
  PERFORM set_config('request.jwt.claims', '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);

  PERFORM public.set_establishment_professional(
    (SELECT id FROM public.establishment_members
      WHERE establishment_id = v_est_b AND user_id = v_prof_b),
    true
  );

  ASSERT (
    SELECT count(*) FROM public.establishment_professionals
    WHERE establishment_id = v_est_b
  ) = 1, 'Establishment B must have its own enabled professional';

  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);

  ASSERT (
    SELECT count(*) FROM public.establishment_professionals
    WHERE establishment_id = v_est_a
  ) = 3, 'The member must read the professionals of the own establishment';

  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_professionals
    WHERE establishment_id = v_est_b
  ), 'The member must NOT read the professionals of another tenant';

  ASSERT (
    SELECT count(*) FROM public.establishment_professional_services
    WHERE establishment_id = v_est_a
  ) = 3, 'The member must read the associations of the own establishment';

  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_professional_services
    WHERE establishment_id = v_est_b
  ), 'The member must NOT read the associations of another tenant';

  RAISE NOTICE 'Professional management assertions passed.';
END $$;

RESET ROLE;

--------------------------------------------------------------------------------
-- 3.1 Usuário não autenticado (anon) não lê serviços nem executa RPCs
--------------------------------------------------------------------------------
SET LOCAL ROLE anon;

DO $$
BEGIN
  ASSERT current_user = 'anon', 'This scenario must run as the anon role';

  BEGIN
    PERFORM 1 FROM public.establishment_services;
    RAISE EXCEPTION 'anon should NOT read services';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: recusado pelo PostgreSQL
  END;

  BEGIN
    PERFORM public.create_establishment_service(
      p_establishment_id => '00000000-0000-0000-0000-000000000000'::uuid,
      p_name => 'Anonimo',
      p_category => 'outros',
      p_duration_minutes => 30,
      p_price_cents => 1000
    );
    RAISE EXCEPTION 'anon should NOT execute the service RPC';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: EXECUTE não concedido ao anon
  END;

  -- Etapa 7: anon não lê profissionais nem executa as RPCs de profissionais.
  BEGIN
    PERFORM 1 FROM public.establishment_professionals;
    RAISE EXCEPTION 'anon should NOT read professionals';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: recusado pelo PostgreSQL
  END;

  BEGIN
    PERFORM 1 FROM public.establishment_professional_services;
    RAISE EXCEPTION 'anon should NOT read professional services';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: recusado pelo PostgreSQL
  END;

  BEGIN
    PERFORM public.set_establishment_professional(
      '00000000-0000-0000-0000-000000000000'::uuid, true
    );
    RAISE EXCEPTION 'anon should NOT execute the professional RPC';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: EXECUTE não concedido ao anon
  END;

  BEGIN
    PERFORM public.add_establishment_professional_service(
      '00000000-0000-0000-0000-000000000000'::uuid,
      '00000000-0000-0000-0000-000000000000'::uuid
    );
    RAISE EXCEPTION 'anon should NOT execute the professional service RPC';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: EXECUTE não concedido ao anon
  END;

  RAISE NOTICE 'Unauthenticated assertions passed.';
END $$;

RESET ROLE;
--------------------------------------------------------------------------------
-- O papel de produção não possui escrita direta; para provar que as POLÍTICAS
-- RLS (e não apenas o GRANT) bloqueiam o escalonamento, um papel sonda recebe
-- temporariamente as permissões de escrita e repete as tentativas.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'agenda_flow_probe') THEN
    CREATE ROLE agenda_flow_probe NOLOGIN INHERIT;
  END IF;

  EXECUTE 'GRANT authenticated TO agenda_flow_probe';
  EXECUTE 'GRANT INSERT, UPDATE, DELETE ON public.establishment_members TO agenda_flow_probe';
  EXECUTE 'GRANT INSERT, UPDATE, DELETE ON public.member_permissions TO agenda_flow_probe';
  EXECUTE 'GRANT UPDATE ON public.profiles TO agenda_flow_probe';
  EXECUTE 'GRANT INSERT, UPDATE, DELETE ON public.establishments TO agenda_flow_probe';
  EXECUTE 'GRANT INSERT, UPDATE, DELETE ON public.establishment_professionals TO agenda_flow_probe';
  EXECUTE 'GRANT INSERT, UPDATE, DELETE ON public.establishment_professional_services TO agenda_flow_probe';
END $$;

SET LOCAL ROLE agenda_flow_probe;

-- Identity of the manager of establishment A.
SELECT set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);

DO $$
DECLARE
  v_est_a uuid;
  v_est_b uuid;
  v_prof_a uuid := '22222222-2222-2222-2222-222222222222';
  v_prof_b uuid := '55555555-5555-5555-5555-555555555555';
  v_manager_a uuid := '33333333-3333-3333-3333-333333333333';
BEGIN
  SELECT id INTO v_est_a FROM public.establishments WHERE slug = 'barbearia-alpha';
  SELECT id INTO v_est_b FROM public.establishments WHERE slug = 'salao-beta';

  ASSERT current_user = 'agenda_flow_probe',
    'The policy scenarios must run as the probe role, not as the table owner';

  --------------------------------------------------------------------------
  -- Test 20: manager cannot promote a professional to owner (RLS policy)
  --------------------------------------------------------------------------
  BEGIN
    UPDATE public.establishment_members SET role = 'owner'
    WHERE user_id = v_prof_a AND establishment_id = v_est_a;
    RAISE EXCEPTION 'Manager should NOT be able to promote a member to owner';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: refused by the RLS policy
  END;

  --------------------------------------------------------------------------
  -- Test 21: manager cannot create another owner (RLS policy)
  --------------------------------------------------------------------------
  BEGIN
    INSERT INTO public.establishment_members (establishment_id, user_id, role)
    VALUES (v_est_a, v_prof_b, 'owner');
    RAISE EXCEPTION 'Manager should NOT be able to create an owner member';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected: refused by the RLS policy
  END;

  --------------------------------------------------------------------------
  -- Test 22: manager cannot change the permissions of another tenant
  --------------------------------------------------------------------------
  -- A RLS filtra as linhas de origem: o INSERT não encontra o membro do
  -- outro tenant e, portanto, não cria nenhuma permissão indevida.
  INSERT INTO public.member_permissions (member_id, permission_key, granted_by)
  SELECT em.id, 'finances.delete', v_manager_a
  FROM public.establishment_members em
  WHERE em.establishment_id = v_est_b
    AND em.user_id = v_prof_b;

  ASSERT NOT EXISTS (
    SELECT 1
    FROM public.member_permissions mp
    JOIN public.establishment_members em ON em.id = mp.member_id
    WHERE em.establishment_id = v_est_b
      AND mp.permission_key = 'finances.delete'
  ), 'Manager must NOT grant permissions in another tenant';

  -- No próprio tenant o gestor pode conceder permissões (comportamento
  -- previsto pela policy member_permissions_insert).
  INSERT INTO public.member_permissions (member_id, permission_key, granted_by)
  SELECT em.id, 'finances.read', v_manager_a
  FROM public.establishment_members em
  WHERE em.establishment_id = v_est_a
    AND em.user_id = v_prof_a;

  ASSERT EXISTS (
    SELECT 1
    FROM public.member_permissions mp
    JOIN public.establishment_members em ON em.id = mp.member_id
    WHERE em.establishment_id = v_est_a
      AND mp.permission_key = 'finances.read'
  ), 'Manager should be able to grant permissions inside the own tenant';

  --------------------------------------------------------------------------
  -- Test 23: manager cannot update the establishment of the tenant
  --------------------------------------------------------------------------
  -- A policy establishments_update exige is_establishment_owner: a linha que
  -- não satisfaz o USING é simplesmente filtrada (nenhuma linha é alterada).
  UPDATE public.establishments SET name = 'Hacked' WHERE id = v_est_a;

  ASSERT (SELECT name FROM public.establishments WHERE id = v_est_a) <> 'Hacked',
    'Manager must NOT be able to update the establishment of the tenant';

  RAISE NOTICE 'All RLS policy assertions passed.';
END $$;

RESET ROLE;

--------------------------------------------------------------------------------
-- 4.1 Integridade das FKs compostas (etapa 7)
--
-- Mesmo como dono das tabelas (ignorando RLS, portanto contornando toda a
-- aplicação), o banco recusa:
--   • habilitar um cliente/membro de OUTRO estabelecimento;
--   • associar um serviço de OUTRO estabelecimento a um profissional.
-- A integridade entre estabelecimentos não depende apenas dos filtros do
-- frontend nem das verificações das RPCs.
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_est_a uuid;
  v_est_b uuid;
BEGIN
  SELECT id INTO v_est_a FROM public.establishments WHERE slug = 'barbearia-alpha';
  SELECT id INTO v_est_b FROM public.establishments WHERE slug = 'salao-beta';

  -- Membro de B habilitado como profissional com establishment_id de A.
  BEGIN
    INSERT INTO public.establishment_professionals (establishment_id, member_id)
    VALUES (
      v_est_a,
      (SELECT id FROM public.establishment_members
        WHERE establishment_id = v_est_b
        LIMIT 1)
    );
    RAISE EXCEPTION 'Composite FK should refuse a member of another tenant';
  EXCEPTION WHEN foreign_key_violation THEN
    -- expected: establishment_professionals_member_establishment_fkey
  END;

  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_professionals
    WHERE establishment_id = v_est_a
      AND member_id IN (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_b)
  ), 'No professional may be enabled with a member of another tenant';

  -- Profissional de A associado a um serviço de B (FK composta do serviço).
  BEGIN
    INSERT INTO public.establishment_professional_services
      (establishment_id, professional_id, service_id)
    VALUES (
      v_est_a,
      (SELECT ep.id FROM public.establishment_professionals ep
        WHERE ep.establishment_id = v_est_a
        LIMIT 1),
      (SELECT id FROM public.establishment_services WHERE establishment_id = v_est_b)
    );
    RAISE EXCEPTION 'Composite FK should refuse a service of another tenant';
  EXCEPTION WHEN foreign_key_violation THEN
    -- expected: establishment_professional_services_service_establishment_fkey
  END;

  -- Incompatível também na ponta do profissional (FK composta do profissional).
  BEGIN
    INSERT INTO public.establishment_professional_services
      (establishment_id, professional_id, service_id)
    VALUES (
      v_est_b,
      (SELECT ep.id FROM public.establishment_professionals ep
        WHERE ep.establishment_id = v_est_a
        LIMIT 1),
      (SELECT id FROM public.establishment_services WHERE establishment_id = v_est_b)
    );
    RAISE EXCEPTION 'Composite FK should refuse a professional of another tenant';
  EXCEPTION WHEN foreign_key_violation THEN
    -- expected: establishment_professional_services_professional_establishment_fkey
  END;

  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_professional_services
    WHERE establishment_id <> (SELECT ep.establishment_id FROM public.establishment_professionals ep WHERE ep.id = professional_id)
       OR establishment_id <> (SELECT s.establishment_id FROM public.establishment_services s WHERE s.id = service_id)
  ), 'No association may reference rows of another tenant';

  RAISE NOTICE 'Composite foreign key assertions passed.';
END $$;

--------------------------------------------------------------------------------
-- 5. Cleanup of the probe role grants
--------------------------------------------------------------------------------
-- 4.1 Profile deletion safety (migration 00010, local preparation only).
-- A profile deletion must never cascade into an establishment or membership.
DO $$
DECLARE
  v_owner_id uuid := '11111111-1111-1111-1111-111111111111';
  v_establishment_id uuid;
  v_member_count integer;
BEGIN
  SELECT id INTO v_establishment_id
  FROM public.establishments
  WHERE owner_id = v_owner_id
  LIMIT 1;

  SELECT count(*) INTO v_member_count
  FROM public.establishment_members
  WHERE user_id = v_owner_id;

  BEGIN
    DELETE FROM public.profiles WHERE id = v_owner_id;
    RAISE EXCEPTION 'Deleting an owner profile must be rejected';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  ASSERT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_owner_id),
    'Owner profile must remain after rejected deletion';
  ASSERT EXISTS (SELECT 1 FROM public.establishments WHERE id = v_establishment_id),
    'Owner establishment must remain after rejected profile deletion';
  ASSERT (SELECT count(*) FROM public.establishment_members WHERE user_id = v_owner_id) = v_member_count,
    'Owner memberships must remain after rejected profile deletion';
END $$;

--------------------------------------------------------------------------------
-- 4.2 Escalas, presença e exceções (etapa 8)
--------------------------------------------------------------------------------
-- Proprietário define escalas (inclusive a própria e turnos noturnos);
-- não-proprietário é recusado; RPCs de check-in/out usam a identidade
-- autenticada e o horário do servidor; duplicidade diária e correções
-- auditadas. Fuso por estabelecimento; isolamento multi-tenant.
DO $$
DECLARE
  v_owner_a uuid := '11111111-1111-1111-1111-111111111111';
  v_prof_a  uuid := '22222222-2222-2222-2222-222222222222';
  v_prof_b  uuid := '55555555-5555-5555-5555-555555555555';
  v_est_a uuid;
  v_est_b uuid;
  v_member_owner uuid;
  v_member_prof uuid;
  v_clock jsonb;
  v_record_id uuid;
  v_corrections integer;
BEGIN
  SELECT id INTO v_est_a FROM public.establishments WHERE slug = 'barbearia-alpha';
  SELECT id INTO v_est_b FROM public.establishments WHERE slug = 'salao-beta';

  SELECT id INTO v_member_owner FROM public.establishment_members
  WHERE establishment_id = v_est_a AND user_id = v_owner_a;
  SELECT id INTO v_member_prof FROM public.establishment_members
  WHERE establishment_id = v_est_a AND user_id = v_prof_a;

  -- (1) Proprietário define a escala do profissional da própria empresa.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);
  PERFORM public.set_establishment_schedule(v_member_prof, '[
    {"weekday":0,"is_day_off":true},
    {"weekday":1,"start_time":"09:00","end_time":"18:00","break_start":"12:00","break_end":"13:00"},
    {"weekday":2,"start_time":"09:00","end_time":"18:00","break_start":"12:00","break_end":"13:00"},
    {"weekday":3,"start_time":"09:00","end_time":"18:00","break_start":"12:00","break_end":"13:00"},
    {"weekday":4,"start_time":"09:00","end_time":"18:00","break_start":"12:00","break_end":"13:00"},
    {"weekday":5,"start_time":"09:00","end_time":"18:00","break_start":"12:00","break_end":"13:00"},
    {"weekday":6,"start_time":"22:00","end_time":"02:00"}
  ]'::jsonb);
  ASSERT (SELECT count(*) FROM public.establishment_schedules WHERE member_id = v_member_prof) = 7,
    'Professional weekly schedule must have seven day rows';
  ASSERT (SELECT is_day_off FROM public.establishment_schedules WHERE member_id = v_member_prof AND weekday = 0),
    'Sunday must be a day off';
  ASSERT (SELECT start_time FROM public.establishment_schedules WHERE member_id = v_member_prof AND weekday = 6)
           = '22:00:00'::time,
    'Overnight shift (22:00 -> 02:00) must be accepted';

  -- (1a) Proprietário define a própria escala (owner também tem controle de presença).
  PERFORM public.set_establishment_schedule(v_member_owner,
    '[{"weekday":1,"start_time":"08:00","end_time":"17:00"},{"weekday":2,"start_time":"08:00","end_time":"17:00"}]'::jsonb);
  ASSERT (SELECT count(*) FROM public.establishment_schedules WHERE member_id = v_member_owner) = 2,
    'Own schedule must replace the previous rows entirely';

  -- (2) Gerente/profissional NÃO configura escalas (somente proprietário).
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);
  BEGIN
    PERFORM public.set_establishment_schedule(v_member_prof, '[{"weekday":1,"start_time":"01:00","end_time":"02:00"}]'::jsonb);
    RAISE EXCEPTION 'Non-owner must not configure schedules';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Apenas o proprietario configura escalas%' THEN
      RAISE EXCEPTION 'Unexpected error while a non-owner set a schedule: %', SQLERRM;
    END IF;
  END;

  -- (3) Proprietário de OUTRA empresa não configura escala do membro alheio.
  PERFORM set_config('request.jwt.claim.sub', '44444444-4444-4444-4444-444444444444'::uuid::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"44444444-4444-4444-4444-444444444444","role":"authenticated","aud":"authenticated","email":"owner-b@agenda.flow.test"}', true);
  BEGIN
    PERFORM public.set_establishment_schedule(v_member_prof, '[{"weekday":1,"start_time":"01:00","end_time":"02:00"}]'::jsonb);
    RAISE EXCEPTION 'Foreign owner must not configure schedules of another tenant';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Apenas o proprietario configura escalas%' THEN
      RAISE EXCEPTION 'Unexpected error for foreign owner: %', SQLERRM;
    END IF;
  END;

  -- (4) Membro desativado não recebe escala; escalas existentes são preservadas.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);
  PERFORM public.set_establishment_member_active(v_member_prof, false);
  BEGIN
    PERFORM public.set_establishment_schedule(v_member_prof, '[{"weekday":1,"start_time":"01:00","end_time":"02:00"}]'::jsonb);
    RAISE EXCEPTION 'Inactive member must not receive a new schedule';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Vinculo inativo%' THEN
      RAISE EXCEPTION 'Unexpected error for inactive member: %', SQLERRM;
    END IF;
  END;
  PERFORM public.set_establishment_member_active(v_member_prof, true);
  ASSERT (SELECT count(*) FROM public.establishment_schedules WHERE member_id = v_member_prof) = 7,
    'Existing schedule rows must be preserved';

  -- (5) Relógio oficial do servidor no fuso do estabelecimento.
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);
  v_clock := public.get_establishment_clock(v_est_a);
  ASSERT v_clock->>'timezone' = 'America/Sao_Paulo', 'Establishment timezone must be returned';
  ASSERT v_clock->>'local_date' ~ '^\d{4}-\d{2}-\d{2}$' AND v_clock->>'local_time' ~ '^\d{2}:\d{2}$',
    'Clock must expose local_date/local_time from the server';
  v_clock := NULL;

  -- (6) Check-in do próprio usuário (horário do servidor, sem duplicidade).
  v_record_id := (public.record_attendance_check_in(v_est_a)).id;
  ASSERT v_record_id IS NOT NULL, 'Check-in must create the daily record';
  ASSERT (SELECT check_out_at IS NULL FROM public.attendance_records WHERE id = v_record_id), 'No check-out at check-in time';
  BEGIN
    PERFORM public.record_attendance_check_in(v_est_a);
    RAISE EXCEPTION 'Duplicate check-in must be refused';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Registro de entrada ja existe para hoje%'
       AND SQLERRM NOT LIKE 'Existe um registro de entrada em aberto%' THEN
      RAISE EXCEPTION 'Unexpected duplicate check-in error: %', SQLERRM;
    END IF;
  END;

  -- (6a) Usuário de outra empresa não registra presença no estabelecimento alheio.
  PERFORM set_config('request.jwt.claim.sub', v_prof_b::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","aud":"authenticated","email":"prof-b@agenda.flow.test"}', true);
  BEGIN
    PERFORM public.record_attendance_check_in(v_est_a);
    RAISE EXCEPTION 'Non-member must not check-in in another establishment';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Vinculo inexistente ou inativo%' THEN
      RAISE EXCEPTION 'Unexpected foreign check-in error: %', SQLERRM;
    END IF;
  END;

  -- (6b) Escrita direta exige o papel autenticado: assumimos o role para a
  -- tentativa (o seed roda como superusuário, que ignora GRANTs).
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    INSERT INTO public.establishment_schedules (establishment_id, member_id, weekday, is_day_off, start_time, end_time)
    VALUES (v_est_a, v_member_prof, 3, false, '01:00', '02:00');
    RAISE EXCEPTION 'Authenticated must not write schedules directly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  -- (7) Check-out exige entrada aberta; duplicidade recusada.
  v_record_id := (public.record_attendance_check_out(v_est_a)).id;
  ASSERT v_record_id IS NOT NULL, 'Check-out must complete the daily record';
  ASSERT (SELECT check_out_at IS NOT NULL FROM public.attendance_records WHERE id = v_record_id),
    'Check-out must be persisted by the server';
  BEGIN
    PERFORM public.record_attendance_check_out(v_est_a);
    RAISE EXCEPTION 'Duplicate check-out must be refused';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Saida ja registrada para hoje%' THEN
      RAISE EXCEPTION 'Unexpected duplicate check-out error: %', SQLERRM;
    END IF;
  END;

  -- Perde o registro: manager sem entrada não pode registrar saída.
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333'::uuid::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);
  BEGIN
    PERFORM public.record_attendance_check_out(v_est_a);
    RAISE EXCEPTION 'Check-out without check-in must be refused';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Nenhum registro de entrada para hoje%' THEN
      RAISE EXCEPTION 'Unexpected check-out error: %', SQLERRM;
    END IF;
  END;

  -- (8) Exceções: somente proprietário, período validado.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);
  BEGIN
    PERFORM public.record_attendance_exception(v_member_prof, 'absence',
      (SELECT now()::date), (SELECT now()::date - 1), NULL);
    RAISE EXCEPTION 'Invalid exception dates must be refused';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Periodo de datas invalido%' THEN
      RAISE EXCEPTION 'Unexpected invalid-dates error: %', SQLERRM;
    END IF;
  END;
  PERFORM public.record_attendance_exception(v_member_prof, 'absence',
    (SELECT now()::date), (SELECT now()::date), 'Aviso attendance test');
  ASSERT EXISTS (
    SELECT 1 FROM public.attendance_exceptions e
    JOIN public.establishment_members m ON m.id = e.member_id
    WHERE e.member_id = v_member_prof AND e.exception_type = 'absence'
  ), 'Absence must be recorded by the owner';

  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);
  BEGIN
    PERFORM public.record_attendance_exception(v_member_prof, 'absence',
      (SELECT now()::date), (SELECT now()::date), NULL);
    RAISE EXCEPTION 'Non-owner must not record exceptions';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Apenas o proprietario registra exceções%' THEN
      RAISE EXCEPTION 'Unexpected exception-permission error: %', SQLERRM;
    END IF;
  END;

  -- (9) Correção administrativa com auditoria (somente proprietário).
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);
  PERFORM public.correct_attendance_record(
    v_record_id,
    (SELECT now() AT TIME ZONE 'America/Sao_Paulo')::timestamptz,
    (SELECT now() AT TIME ZONE 'America/Sao_Paulo')::timestamptz,
    'Correção de teste')
  ;
  SELECT count(*) INTO v_corrections
  FROM public.attendance_corrections WHERE attendance_id = v_record_id;
  ASSERT v_corrections = 1, 'Correction audit row must exist exactly once';
  ASSERT (SELECT check_out_source FROM public.attendance_records WHERE id = v_record_id) = 'owner',
    'Corrected check-out must be audited as owner action';

  -- (10) Isolamento: profissional de B não lê presença de A (RLS).
  PERFORM set_config('request.jwt.claim.sub', v_prof_b::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"55555555-5555-5555-5555-555555555555","role":"authenticated","aud":"authenticated","email":"prof-b@agenda.flow.test"}', true);
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.attendance_records WHERE establishment_id = v_est_a
  ), 'Attendance of tenant A must be invisible to a professional of tenant B';
  ASSERT NOT EXISTS (
    SELECT 1 FROM public.establishment_schedules WHERE establishment_id = v_est_a
  ), 'Schedules of tenant A must be invisible to a professional of tenant B';

  -- (11) RLS self-or-owner: mantém o papel `authenticated` (ativo desde 6b).
  -- Profissional vê SOMENTE os próprios registros (não os do colega).
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);
  ASSERT (SELECT count(*) FROM public.attendance_records WHERE establishment_id = v_est_a) = 1,
    'Professional must see only the own attendance record';
  ASSERT (SELECT count(*) FROM public.attendance_exceptions WHERE establishment_id = v_est_a) = 1,
    'Professional must see only the own exceptions';

  -- Colega (manager) não vê presença alheia.
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333'::uuid::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);
  ASSERT (SELECT count(*) FROM public.attendance_records WHERE establishment_id = v_est_a) = 0,
    'Colleague must not read attendance of teammates';
  ASSERT (SELECT count(*) FROM public.attendance_exceptions WHERE establishment_id = v_est_a) = 0,
    'Colleague must not read exceptions of teammates';

  -- Proprietário vê a equipe inteira.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);
  ASSERT (SELECT count(*) FROM public.attendance_records WHERE establishment_id = v_est_a) >= 1,
    'Owner must read the team attendance';
  ASSERT (SELECT count(*) FROM public.attendance_corrections WHERE establishment_id = v_est_a) = 1,
    'Owner must read the team correction history';

  -- (12) Fuso inválido é recusado pelo relógio (validação IANA real).
  PERFORM set_config('role', 'none', true);
  UPDATE public.establishments SET timezone = 'Marte/Phobos' WHERE id = v_est_a;
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","aud":"authenticated","email":"prof-a@agenda.flow.test"}', true);
  BEGIN
    PERFORM public.get_establishment_clock(v_est_a);
    RAISE EXCEPTION 'Invalid IANA timezone must be refused';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Fuso horario invalido%' THEN
      RAISE EXCEPTION 'Unexpected invalid-timezone error: %', SQLERRM;
    END IF;
  END;
  PERFORM set_config('role', 'none', true);
  UPDATE public.establishments SET timezone = 'America/Sao_Paulo' WHERE id = v_est_a;
  ASSERT (public.get_establishment_clock(v_est_a)->>'timezone') = 'America/Sao_Paulo',
    'Valid timezone must work again after restore';

  -- (13) Turno noturno: check-out fecha o registro EM ABERTO do dia anterior.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);
  PERFORM public.set_establishment_schedule(
    (SELECT id FROM public.establishment_members WHERE establishment_id = v_est_a AND user_id = '33333333-3333-3333-3333-333333333333'::uuid),
    '[{"weekday":0,"start_time":"22:00","end_time":"02:00"},{"weekday":1,"start_time":"22:00","end_time":"02:00"},{"weekday":2,"start_time":"22:00","end_time":"02:00"},{"weekday":3,"start_time":"22:00","end_time":"02:00"},{"weekday":4,"start_time":"22:00","end_time":"02:00"},{"weekday":5,"start_time":"22:00","end_time":"02:00"},{"weekday":6,"start_time":"22:00","end_time":"02:00"}]'::jsonb
  );

  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333'::uuid::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated","aud":"authenticated","email":"manager-a@agenda.flow.test"}', true);
  DECLARE
    v_night_id uuid;
  BEGIN
    v_night_id := (public.record_attendance_check_in(v_est_a)).id;
    -- Meia-noite passa: o registro passa a pertencer ao dia anterior.
    PERFORM set_config('role', 'none', true);
    UPDATE public.attendance_records SET work_date = work_date - 1 WHERE id = v_night_id;
    v_night_id := (public.record_attendance_check_out(v_est_a)).id;
    ASSERT (
      SELECT check_out_at IS NOT NULL
             AND work_date = (SELECT (now() AT TIME ZONE (SELECT timezone FROM public.establishments WHERE id = v_est_a))::date - 1)
      FROM public.attendance_records WHERE id = v_night_id
    ), 'Overnight check-out must close the open record of the previous local day';
  END;

  -- (13a) Sem registro em aberto nem registro HOJE: recusa sem mentir.
  BEGIN
    PERFORM public.record_attendance_check_out(v_est_a);
    RAISE EXCEPTION 'Second check-out without open record must be refused';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Nenhum registro de entrada para hoje%' THEN
      RAISE EXCEPTION 'Unexpected second check-out error: %', SQLERRM;
    END IF;
  END;

  -- (13b) Check-in não abre segundo registro com entrada em aberto.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);
  DECLARE
    v_owner_record uuid;
  BEGIN
    v_owner_record := (public.record_attendance_check_in(v_est_a)).id;
    PERFORM set_config('role', 'none', true);
    UPDATE public.attendance_records SET work_date = work_date - 1 WHERE id = v_owner_record;
    BEGIN
      PERFORM public.record_attendance_check_in(v_est_a);
      RAISE EXCEPTION 'Check-in with an open record must be refused';
    EXCEPTION WHEN others THEN
      IF SQLERRM NOT LIKE 'Existe um registro de entrada em aberto%' THEN
        RAISE EXCEPTION 'Unexpected open-record error: %', SQLERRM;
      END IF;
    END;
  END;

  -- (14) FK COMPOSTA na auditoria: correção não cruza tenants.
  PERFORM set_config('role', 'none', true);
  BEGIN
    INSERT INTO public.attendance_corrections (establishment_id, attendance_id, reason, corrected_by)
    VALUES (v_est_b, v_record_id, 'Cross-tenant correction', v_owner_a);
    RAISE EXCEPTION 'Correction with foreign establishment must be refused';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;

  -- (14a) HISTÓRICO PRESERVADO: registro com correção não é apagado (RESTRICT).
  BEGIN
    DELETE FROM public.attendance_records WHERE id = v_record_id;
    RAISE EXCEPTION 'Deleting an audited attendance record must be restricted';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
  ASSERT EXISTS (SELECT 1 FROM public.attendance_records WHERE id = v_record_id),
    'Audited record must remain after restricted delete';

  -- (14b) Cronologia: entrada corrigida deve preceder a saída.
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);
  BEGIN
    PERFORM public.correct_attendance_record(
      v_record_id,
      (SELECT now() + interval '2 hours'),
      (SELECT now()),
      'Teste de cronologia'
    );
    RAISE EXCEPTION 'Inverted correction times must be refused';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Horarios inconsistentes%' THEN
      RAISE EXCEPTION 'Unexpected chronology error: %', SQLERRM;
    END IF;
  END;

  -- (15) GARANTIA FÍSICA: o índice único parcial impede duas entradas em
  -- aberto para o mesmo membro, mesmo em dias diferentes (virada de
  -- meia-noite) e mesmo escrevendo direto na tabela.
  PERFORM set_config('role', 'none', true);
  BEGIN
    INSERT INTO public.attendance_records
      (establishment_id, member_id, work_date, check_in_at, check_in_source)
    VALUES
      (v_est_a, v_member_owner, (SELECT (now() AT TIME ZONE 'America/Sao_Paulo')::date), now(), 'self');
    RAISE EXCEPTION 'A second open attendance record must be refused by the partial index';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
  ASSERT (
    SELECT count(*) FROM public.attendance_records
    WHERE member_id = v_member_owner AND check_out_at IS NULL
  ) = 1, 'Exactly one open record may exist per member';

  -- (16) HISTÓRICO PRESERVADO: excluir vínculo não apaga presença nem ausência.
  BEGIN
    DELETE FROM public.establishment_members WHERE id = v_member_prof;
    RAISE EXCEPTION 'Deleting a member with attendance history must be restricted';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
  ASSERT EXISTS (SELECT 1 FROM public.establishment_members WHERE id = v_member_prof),
    'Member with history must survive a restricted delete';
  ASSERT EXISTS (
    SELECT 1 FROM public.attendance_records WHERE member_id = v_member_prof
  ), 'Attendance history must survive a member delete attempt';
  ASSERT EXISTS (
    SELECT 1 FROM public.attendance_exceptions WHERE member_id = v_member_prof
  ), 'Exception history must survive a member delete attempt';

  -- (16a) Exclusão definitiva do estabelecimento também não apaga histórico.
  BEGIN
    DELETE FROM public.establishments WHERE id = v_est_a;
    RAISE EXCEPTION 'Deleting an establishment with attendance history must be restricted';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
  ASSERT EXISTS (SELECT 1 FROM public.establishments WHERE id = v_est_a),
    'Establishment with history must survive a restricted delete';

  -- (17) INTERVALO NOTURNO: aceito pelo banco (mesma regra da interface).
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);
  PERFORM public.set_establishment_schedule(
    v_member_prof,
    '[{"weekday":0,"is_day_off":true},
      {"weekday":1,"start_time":"22:00","end_time":"02:00","break_start":"23:00","break_end":"01:00"},
      {"weekday":2,"start_time":"22:00","end_time":"02:00","break_start":"23:00","break_end":"01:00"},
      {"weekday":3,"start_time":"22:00","end_time":"02:00","break_start":"23:00","break_end":"01:00"},
      {"weekday":4,"start_time":"22:00","end_time":"02:00","break_start":"23:00","break_end":"01:00"},
      {"weekday":5,"start_time":"22:00","end_time":"02:00","break_start":"23:00","break_end":"01:00"},
      {"weekday":6,"start_time":"22:00","end_time":"02:00","break_start":"23:00","break_end":"01:00"}]'::jsonb
  );
  ASSERT (
    SELECT break_start = '23:00' AND break_end = '01:00'
    FROM public.establishment_schedules
    WHERE member_id = v_member_prof AND weekday = 1
  ), 'Overnight break (23:00->01:00) must be accepted';

  -- (17a) Intervalo vazio continua proibido (validação não foi removida).
  BEGIN
    PERFORM public.set_establishment_schedule(
      v_member_prof,
      '[{"weekday":1,"start_time":"22:00","end_time":"02:00","break_start":"23:00","break_end":"23:00"}]'::jsonb
    );
    RAISE EXCEPTION 'Zero-length break must be refused';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- (18) SAÍDA ESQUECIDA: entrada antiga em aberto bloqueia nova entrada e só
  -- é liberada pela correção administrativa auditável do proprietário.
  PERFORM set_config('role', 'none', true);
  UPDATE public.attendance_records
  SET work_date = (SELECT (now() AT TIME ZONE 'America/Sao_Paulo')::date - 3)
  WHERE member_id = v_member_owner AND check_out_at IS NULL;

  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claims',
    '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","aud":"authenticated","email":"owner-a@agenda.flow.test"}', true);
  BEGIN
    PERFORM public.record_attendance_check_in(v_est_a);
    RAISE EXCEPTION 'A forgotten open record must block a new check-in';
  EXCEPTION WHEN others THEN
    IF SQLERRM NOT LIKE 'Existe um registro de entrada em aberto%' THEN
      RAISE EXCEPTION 'Unexpected forgotten-open-record error: %', SQLERRM;
    END IF;
  END;

  SELECT id INTO v_record_id FROM public.attendance_records
  WHERE member_id = v_member_owner AND check_out_at IS NULL;

  PERFORM public.correct_attendance_record(
    v_record_id,
    NULL,
    (SELECT now()),
    'Correcao de saida esquecida'
  );
  ASSERT (
    SELECT check_out_at IS NOT NULL AND corrected_at IS NOT NULL
    FROM public.attendance_records WHERE id = v_record_id
  ), 'Owner correction must close the forgotten open record with audit metadata';

  PERFORM public.record_attendance_check_in(v_est_a);
  ASSERT (
    SELECT count(*) FROM public.attendance_records
    WHERE member_id = v_member_owner
      AND check_out_at IS NULL
      AND work_date = (SELECT (now() AT TIME ZONE 'America/Sao_Paulo')::date)
  ) = 1, 'After the auditable correction the user may check in again';

  PERFORM public.record_attendance_check_out(v_est_a);

  -- Restaura o papel da sessão (o fim do bloco devolve o contexto ao seed).
  PERFORM set_config('role', 'none', true);

  RAISE NOTICE 'Schedule and presence assertions passed.';
END $$;


--------------------------------------------------------------------------------
-- 5. Cleanup of the probe role grants
--------------------------------------------------------------------------------
DO $$
BEGIN
  EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON public.establishment_members FROM agenda_flow_probe';
  EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON public.member_permissions FROM agenda_flow_probe';
  EXECUTE 'REVOKE UPDATE ON public.profiles FROM agenda_flow_probe';
  EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON public.establishments FROM agenda_flow_probe';
  EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON public.establishment_professionals FROM agenda_flow_probe';
  EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON public.establishment_professional_services FROM agenda_flow_probe';
  EXECUTE 'REVOKE authenticated FROM agenda_flow_probe';
END $$;

COMMIT;
