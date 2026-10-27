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
  v_token_manager text;
  v_token_prof text;
  v_token_prof_b text;
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

  RAISE NOTICE 'All application assertions passed.';
END $$;

RESET ROLE;

--------------------------------------------------------------------------------
-- 4. RLS policy layer (probe role with write grants)
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
-- 5. Cleanup of the probe role grants
--------------------------------------------------------------------------------
DO $$
BEGIN
  EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON public.establishment_members FROM agenda_flow_probe';
  EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON public.member_permissions FROM agenda_flow_probe';
  EXECUTE 'REVOKE UPDATE ON public.profiles FROM agenda_flow_probe';
  EXECUTE 'REVOKE INSERT, UPDATE, DELETE ON public.establishments FROM agenda_flow_probe';
  EXECUTE 'REVOKE authenticated FROM agenda_flow_probe';
END $$;

COMMIT;
