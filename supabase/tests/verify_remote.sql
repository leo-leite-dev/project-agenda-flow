-- Verificação (somente leitura) do estado do banco após aplicar as migrations.
--
-- Este script NÃO altera dados: ele apenas inspeciona o catálogo e reporta
-- inconsistências. Pode ser executado com segurança no SQL Editor do Supabase
-- (projeto remoto) ou no banco local.
--
-- Uso: cole o conteúdo no SQL Editor e execute. O resultado aparece na aba
-- "Result" e os avisos na aba "Messages".

--------------------------------------------------------------------------------
-- 1. Integridade dos perfis
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_missing integer;
  v_duplicated integer;
  v_orphan_profiles integer;
BEGIN
  -- Usuários autenticados sem perfil correspondente.
  SELECT count(*) INTO v_missing
  FROM auth.users u
  WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id);

  IF v_missing > 0 THEN
    RAISE EXCEPTION 'FALHA: % usuário(s) autenticado(s) sem perfil em public.profiles.', v_missing;
  END IF;

  RAISE NOTICE 'OK: todos os usuários autenticados possuem perfil.';

  -- Perfis duplicados (impossível pela PK, mantido como defesa).
  SELECT count(*) INTO v_duplicated
  FROM (
    SELECT id FROM public.profiles GROUP BY id HAVING count(*) > 1
  ) d;

  IF v_duplicated > 0 THEN
    RAISE EXCEPTION 'FALHA: % perfil(is) duplicado(s).', v_duplicated;
  END IF;

  RAISE NOTICE 'OK: não há perfis duplicados.';

  -- Perfis órfãos (perfil sem usuário correspondente).
  SELECT count(*) INTO v_orphan_profiles
  FROM public.profiles p
  WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.id);

  IF v_orphan_profiles > 0 THEN
    RAISE EXCEPTION 'FALHA: % perfil(is) órfão(s) (sem auth.users correspondente).', v_orphan_profiles;
  END IF;

  RAISE NOTICE 'OK: não há perfis órfãos.';
END $$;

--------------------------------------------------------------------------------
-- 1.1 Proteção contra exclusão acidental de dados de tenant
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_unsafe integer;
BEGIN
  SELECT count(*) INTO v_unsafe
  FROM pg_constraint c
  JOIN pg_class source_table ON source_table.oid = c.conrelid
  JOIN pg_namespace source_ns ON source_ns.oid = source_table.relnamespace
  WHERE c.contype = 'f'
    AND source_ns.nspname = 'public'
    AND (
      (source_table.relname = 'establishments' AND c.conname = 'establishments_owner_id_fkey')
      OR (source_table.relname = 'establishment_members' AND c.conname = 'establishment_members_user_id_fkey')
      OR (source_table.relname = 'establishment_invitations' AND c.conname = 'establishment_invitations_invited_by_fkey')
    )
    AND c.confdeltype = 'c';

  IF v_unsafe > 0 THEN
    RAISE EXCEPTION 'FALHA: % relação(ões) de perfil ainda usam ON DELETE CASCADE em dados de tenant.', v_unsafe;
  END IF;

  RAISE NOTICE 'OK: exclusão de perfil não usa cascata em proprietário, vínculo ou auditoria de convite.';
END $$;

--------------------------------------------------------------------------------
-- 1.2 Integridade histórica de presença (migration 00011)
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_cascades integer;
  v_restricts integer;
  v_open_index integer;
BEGIN
  SELECT count(*) INTO v_open_index
  FROM pg_indexes
  WHERE schemaname = 'public'
    AND tablename = 'attendance_records'
    AND indexname = 'attendance_records_one_open_per_member'
    AND indexdef ILIKE '%unique%'
    AND indexdef ILIKE '%check_out_at is null%';

  IF v_open_index <> 1 THEN
    RAISE EXCEPTION 'FALHA: índice único parcial attendance_records_one_open_per_member ausente ou inválido.';
  END IF;

  RAISE NOTICE 'OK: no máximo uma entrada em aberto por membro é garantida pelo índice parcial.';

  SELECT count(*) INTO v_cascades
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE c.contype = 'f'
    AND n.nspname = 'public'
    AND t.relname IN ('attendance_records', 'attendance_exceptions', 'attendance_corrections')
    AND c.confdeltype = 'c';

  IF v_cascades > 0 THEN
    RAISE EXCEPTION 'FALHA: % FK(s) de histórico de presença ainda usam ON DELETE CASCADE.', v_cascades;
  END IF;

  SELECT count(*) INTO v_restricts
  FROM pg_constraint c
  WHERE c.contype = 'f'
    AND c.conname IN (
      'attendance_records_member_establishment_fkey',
      'attendance_records_establishment_id_fkey',
      'attendance_exceptions_member_establishment_fkey',
      'attendance_exceptions_establishment_id_fkey',
      'attendance_corrections_attendance_establishment_fkey',
      'attendance_corrections_establishment_id_fkey'
    )
    AND c.confdeltype = 'r';

  IF v_restricts <> 6 THEN
    RAISE EXCEPTION 'FALHA: esperadas 6 FKs RESTRICT no histórico de presença, encontradas %.', v_restricts;
  END IF;

  RAISE NOTICE 'OK: vínculo/estabelecimento com histórico não é apagado em cascata.';
END $$;

--------------------------------------------------------------------------------
-- 2. Trigger de criação automática de perfis
--------------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'auth.users'::regclass
      AND tgname = 'on_auth_user_created'
      AND NOT tgisinternal
      AND tgenabled = 'O'
  ) THEN
    RAISE EXCEPTION 'FALHA: trigger on_auth_user_created não existe ou está desabilitado em auth.users.';
  END IF;

  -- O trigger deve chamar a função interna no schema privado.
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE t.tgrelid = 'auth.users'::regclass
      AND t.tgname = 'on_auth_user_created'
      AND n.nspname = 'agenda_flow_private'
  ) THEN
    RAISE EXCEPTION 'FALHA: o trigger on_auth_user_created não aponta para o schema privado.';
  END IF;

  RAISE NOTICE 'OK: trigger on_auth_user_created existe, está habilitado e usa a função privada.';
END $$;

--------------------------------------------------------------------------------
-- 3. Funções públicas esperadas
--------------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'create_establishment'
      AND pg_get_function_identity_arguments(p.oid) = 'p_name text, p_slug text, p_type text, p_document text, p_phone text, p_email text, p_address jsonb'
  ) THEN
    RAISE EXCEPTION 'FALHA: public.create_establishment não possui a assinatura com p_type.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'ensure_profile'
  ) THEN
    RAISE EXCEPTION 'FALHA: public.ensure_profile não existe.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'create_establishment'
      AND pg_get_function_identity_arguments(p.oid) = 'p_name text, p_slug text, p_document text, p_phone text, p_email text, p_address jsonb'
  ) THEN
    RAISE EXCEPTION 'FALHA: a sobrecarga obsoleta de public.create_establishment (sem p_type) ainda existe.';
  END IF;

  RAISE NOTICE 'OK: funções públicas esperadas presentes (sem sobrecargas obsoletas).';
END $$;

--------------------------------------------------------------------------------
-- 4. Estado da coluna/constraint de tipo do estabelecimento
--------------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'establishments' AND column_name = 'type'
  ) THEN
    RAISE EXCEPTION 'FALHA: public.establishments.type não existe.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'valid_establishment_type'
      AND conrelid = 'public.establishments'::regclass
  ) THEN
    RAISE EXCEPTION 'FALHA: constraint valid_establishment_type ausente em public.establishments.';
  END IF;

  RAISE NOTICE 'OK: coluna type e constraint valid_establishment_type presentes.';
END $$;

--------------------------------------------------------------------------------
-- 4.1 Integridade dos vínculos (somente leitura)
--------------------------------------------------------------------------------
-- Verifica a regra de negócio "um usuário possui no máximo um vínculo efetivo
-- por estabelecimento" e lista (sem alterar nada) os vínculos duplicados,
-- os vínculos sem proprietário e os vínculos órfãos.
DO $$
DECLARE
  v_unique_exists integer;
  v_duplicate_groups integer;
  v_duplicate_rows integer;
  v_missing_owner integer;
  v_detail text;
BEGIN
  -- (a) Existe constraint/índice único para (establishment_id, user_id)?
  SELECT count(*) INTO v_unique_exists
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
  ) AS uniques;

  IF v_unique_exists = 0 THEN
    RAISE NOTICE 'AVISO: não há constraint UNIQUE (establishment_id, user_id) em public.establishment_members. Aplique a migration 20250127000008_membership_integrity.sql depois de revisar os dados.';
  ELSE
    RAISE NOTICE 'OK: unicidade de vínculo garantida em public.establishment_members.';
  END IF;

  -- (b) Vínculos duplicados (mesmo estabelecimento e mesmo usuário).
  SELECT count(*), coalesce(sum(d.total), 0)
  INTO v_duplicate_groups, v_duplicate_rows
  FROM (
    SELECT count(*) AS total
    FROM public.establishment_members
    GROUP BY establishment_id, user_id
    HAVING count(*) > 1
  ) AS d;

  IF v_duplicate_groups > 0 THEN
    SELECT string_agg(d.detail, E'\n') INTO v_detail
    FROM (
      SELECT format(
        'establishment_id=%s user_id=%s ocorrencias=%s (ids: %s)',
        m.establishment_id, m.user_id, count(*),
        string_agg(m.id::text, ', ' ORDER BY m.created_at, m.id)
      ) AS detail
      FROM public.establishment_members m
      GROUP BY m.establishment_id, m.user_id
      HAVING count(*) > 1
    ) AS d;

    RAISE NOTICE 'FALHA: %s grupo(s) de vínculos duplicados (%s registro(s) afetado(s)):%s',
      v_duplicate_groups, v_duplicate_rows, E'\n' || v_detail;
  ELSE
    RAISE NOTICE 'OK: nenhum vínculo duplicado em public.establishment_members.';
  END IF;

  -- (c) Todo estabelecimento precisa de um vínculo de proprietário ativo.
  SELECT count(*) INTO v_missing_owner
  FROM public.establishments e
  WHERE NOT EXISTS (
    SELECT 1 FROM public.establishment_members m
    WHERE m.establishment_id = e.id
      AND m.role = 'owner'
      AND m.is_active = true
  );

  IF v_missing_owner > 0 THEN
    RAISE NOTICE 'AVISO: %s estabelecimento(s) sem vínculo de proprietário ativo.', v_missing_owner;
  ELSE
    RAISE NOTICE 'OK: todo estabelecimento possui um proprietário ativo.';
  END IF;
END $$;

--------------------------------------------------------------------------------
-- 4.2 Integridade dos profissionais (somente leitura, etapa 7)
--------------------------------------------------------------------------------
-- Verifica (sem alterar nada):
--   * as tabelas da etapa 7 existem com RLS habilitado;
--   * nenhuma associação cruza estabelecimentos (FKs compostas);
--   * nenhum profissional habilitado aponta para um membro de OUTRO tenant;
--   * profissionais afetados pela desativação do próprio vínculo são
--     listados (associações preservadas, elegibilidade suspensa).
DO $$
DECLARE
  v_cross_professionals integer;
  v_cross_associations integer;
  v_inactive_professionals integer;
BEGIN
  IF to_regclass('public.establishment_professionals') IS NULL
     OR to_regclass('public.establishment_professional_services') IS NULL THEN
    RAISE NOTICE 'AVISO: tabelas da etapa 7 (profissionais) não estão presentes. Aplique a migration 20250127000009_professionals.sql.';
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid = 'public.establishment_professionals'::regclass AND relrowsecurity
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_class
    WHERE oid = 'public.establishment_professional_services'::regclass AND relrowsecurity
  ) THEN
    RAISE EXCEPTION 'FALHA: RLS desabilitado nas tabelas de profissionais da etapa 7.';
  END IF;

  -- Nenhum profissional pode ocupar linha de estabelecimento distinto do
  -- próprio vínculo de membro.
  SELECT count(*) INTO v_cross_professionals
  FROM public.establishment_professionals ep
  JOIN public.establishment_members m ON m.id = ep.member_id
  WHERE m.establishment_id <> ep.establishment_id;

  IF v_cross_professionals > 0 THEN
    RAISE EXCEPTION 'FALHA: %s profissional(is) com estabelecimento incompatível com o vínculo de membro.', v_cross_professionals;
  END IF;

  -- Nenhuma associação pode cruzar estabelecimentos.
  SELECT count(*) INTO v_cross_associations
  FROM public.establishment_professional_services ps
  WHERE ps.establishment_id <> (
        SELECT ep.establishment_id FROM public.establishment_professionals ep WHERE ep.id = ps.professional_id)
     OR ps.establishment_id <> (
        SELECT s.establishment_id FROM public.establishment_services s WHERE s.id = ps.service_id);

  IF v_cross_associations > 0 THEN
    RAISE EXCEPTION 'FALHA: %s associação(ões) cruzando estabelecimentos (FK composta violada).', v_cross_associations;
  END IF;

  RAISE NOTICE 'OK: nenhum profissional ou associação cruza estabelecimentos.';

  SELECT count(*) INTO v_inactive_professionals
  FROM public.establishment_professionals ep
  JOIN public.establishment_members m ON m.id = ep.member_id
  WHERE m.is_active = false;

  IF v_inactive_professionals > 0 THEN
    RAISE NOTICE 'AVISO: %s profissional(is) com vínculo de membro desativado (associações preservadas; nenhuma nova associação é aceita).', v_inactive_professionals;
  ELSE
    RAISE NOTICE 'OK: todo profissional habilitado possui vínculo ativo.';
  END IF;
END $$;

-- (d) Detalhamento legível dos vínculos do tenant BarberLeo (somente leitura).
--     Cole e execute separadamente no SQL Editor para inspecionar as linhas:
--
--     SELECT
--       m.id,
--       m.establishment_id,
--       e.name            AS estabelecimento,
--       m.user_id,
--       u.email           AS usuario,
--       m.role            AS cargo,
--       m.is_active,
--       m.created_at
--     FROM public.establishment_members m
--     JOIN public.establishments e ON e.id = m.establishment_id
--     JOIN auth.users u ON u.id = m.user_id
--     WHERE e.slug = 'barberleo'
--     ORDER BY m.role, m.created_at;
--
-- (e) Vínculos duplicados de um mesmo usuário no mesmo estabelecimento
--     (somente leitura):
--
--     SELECT establishment_id, user_id, count(*) AS ocorrencias
--     FROM public.establishment_members
--     GROUP BY establishment_id, user_id
--     HAVING count(*) > 1;

--------------------------------------------------------------------------------
-- 5. Permissões de tabela: anon sem nada, authenticated somente leitura
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_table text;
  v_tables text[] := ARRAY[
    'public.profiles',
    'public.establishments',
    'public.establishment_members',
    'public.member_permissions',
    'public.establishment_invitations',
    'public.establishment_services',
    'public.establishment_professionals',
    'public.establishment_professional_services',
    'public.establishment_schedules',
    'public.attendance_records',
    'public.attendance_exceptions',
    'public.attendance_corrections'
  ];
  v_privilege text;
  v_privileges text[] := ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'];
BEGIN
  FOREACH v_table IN ARRAY v_tables LOOP
    FOREACH v_privilege IN ARRAY v_privileges LOOP
      IF has_table_privilege('anon', v_table, v_privilege) THEN
        RAISE EXCEPTION 'FALHA: anon possui % em %', v_privilege, v_table;
      END IF;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'OK: anon não possui SELECT/INSERT/UPDATE/DELETE em nenhuma tabela de dados.';

  FOREACH v_table IN ARRAY v_tables LOOP
    IF NOT has_table_privilege('authenticated', v_table, 'SELECT') THEN
      RAISE EXCEPTION 'FALHA: authenticated não possui SELECT em %', v_table;
    END IF;

    FOREACH v_privilege IN ARRAY v_privileges LOOP
      IF v_privilege <> 'SELECT'
         AND has_table_privilege('authenticated', v_table, v_privilege) THEN
        RAISE EXCEPTION 'FALHA: authenticated possui % em % (escrita direta não autorizada)', v_privilege, v_table;
      END IF;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'OK: authenticated possui somente SELECT nas tabelas de dados.';
END $$;

--------------------------------------------------------------------------------
-- 6. Privilégios herdados de PUBLIC (segunda camada de proteção)
--------------------------------------------------------------------------------
-- Nenhuma função COMUM do schema public pode manter o EXECUTE implícito
-- herdado de PUBLIC: cada função tem sua matriz de EXECUTE explicitamente
-- definida.
--
-- EXCEÇÃO ESPECÍFICA: funções RETURNS event_trigger vinculadas a
-- pg_event_trigger (caso real do projeto: public.rls_auto_enable, usada para
-- habilitar RLS automaticamente). Elas só executam como event trigger — o
-- PostgreSQL recusa a chamada direta ("trigger functions can only be called
-- as triggers") — e não são expostas pelo PostgREST. A exceção exige o tipo
-- event_trigger E o vínculo real com pg_event_trigger: uma RPC comum ou uma
-- event trigger sem vínculo continua sendo apontada.
DO $$
DECLARE
  v_leaked text;
BEGIN
  IF to_regprocedure('agenda_flow_private.publicly_exposed_functions()') IS NOT NULL THEN
    SELECT array_to_string(leaked, ', ')
      INTO v_leaked
    FROM agenda_flow_private.publicly_exposed_functions() AS leaked;
  ELSE    SELECT string_agg(p.proname, ', ')
      INTO v_leaked
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) g
    WHERE n.nspname = 'public'
      AND g.grantee = 0
      AND g.privilege_type = 'EXECUTE'
      AND NOT (
        p.prorettype = 'event_trigger'::regtype
        AND EXISTS (SELECT 1 FROM pg_event_trigger et WHERE et.evtfoid = p.oid)
      );
  END IF;

  IF v_leaked IS NOT NULL AND length(v_leaked) > 0 THEN
    RAISE EXCEPTION 'FALHA: funcoes do schema public com EXECUTE herdado de PUBLIC: %', v_leaked;
  END IF;

  RAISE NOTICE 'OK: nenhuma funcao comum do schema public herda EXECUTE de PUBLIC.';
END $$;

-- As funções de event trigger vinculadas permanecem intactas e registradas.
DO $$
DECLARE
  v_detached text;
BEGIN
  SELECT string_agg(p.proname, ', ')
    INTO v_detached
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prorettype = 'event_trigger'::regtype
    AND NOT EXISTS (SELECT 1 FROM pg_event_trigger et WHERE et.evtfoid = p.oid);

  IF v_detached IS NOT NULL THEN
    RAISE EXCEPTION
      'FALHA: funcoes event_trigger no schema public sem vinculo em pg_event_trigger: %', v_detached;
  END IF;

  RAISE NOTICE 'OK: funcoes event_trigger do schema public estao vinculadas a pg_event_trigger.';
END $$;

-- Nenhuma tabela de dados pode ter privilégio concedido a PUBLIC.
DO $$
DECLARE
  v_leaked text;
BEGIN
  SELECT string_agg(c.relname, ', ')
    INTO v_leaked
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) g
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
    AND g.grantee = 0;

  IF v_leaked IS NOT NULL THEN
    RAISE EXCEPTION 'FALHA: tabelas do schema public com privilegio herdado de PUBLIC: %', v_leaked;
  END IF;

  RAISE NOTICE 'OK: nenhuma tabela do schema public tem privilegio herdado de PUBLIC.';
END $$;

--------------------------------------------------------------------------------
-- 7. Privilégios padrão herdados (pg_default_acl)
--------------------------------------------------------------------------------
-- TABELAS E SEQUENCES — BLOQUEANTE apenas para os PAPÉIS DO PROJETO (o role
-- que executa a auditoria e o role postgres). Concessões automáticas desses
-- papéis para PUBLIC, anon ou authenticated são um problema, em QUALQUER tipo
-- de privilégio (SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES,
-- TRIGGER e MAINTAIN).
--
-- Os default privileges de papéis INTERNOS DA PLATAFORMA (supabase_admin e
-- afins) são PRESERVADOS — o role postgres não tem permissão para alterá-los
-- (https://supabase.com/kb/troubleshooting/cant-change-the-default-privileges-of-supabase-admin-in-the-public-schema)
-- — e por isso são apenas REPORTADOS, sem bloquear a auditoria.
DO $$
DECLARE
  v_leaked text;
BEGIN
  IF to_regprocedure('agenda_flow_private.unexpected_default_privileges()') IS NOT NULL THEN
    SELECT array_to_string(leaked, '; ')
      INTO v_leaked
    FROM agenda_flow_private.unexpected_default_privileges() AS leaked;
  ELSE
    SELECT string_agg(DISTINCT format(
             '%s %s para %s (schema %s, owner %s)',
             d.defaclobjtype::text,
             g.privilege_type,
             CASE WHEN g.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(g.grantee) END,
             n.nspname,
             d.defaclrole::regrole::text
           ), '; ')
      INTO v_leaked
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
      );
  END IF;

  IF v_leaked IS NOT NULL AND length(v_leaked) > 0 THEN
    RAISE EXCEPTION
      'FALHA: pg_default_acl concede acesso automatico a PUBLIC/anon/authenticated para tabelas ou sequences criadas pelos papeis do projeto: %',
      v_leaked;
  END IF;

  RAISE NOTICE 'OK: sem concessões automáticas de tabelas/sequences para PUBLIC/anon/authenticated nos papéis do projeto.';
END $$;

-- Default privileges de papéis internos da plataforma: visíveis, não bloqueantes.
DO $$
DECLARE
  v_leaked text;
BEGIN
  IF to_regprocedure('agenda_flow_private.platform_default_privileges()') IS NOT NULL THEN
    SELECT array_to_string(leaked, '; ')
      INTO v_leaked
    FROM agenda_flow_private.platform_default_privileges() AS leaked;
  ELSE
    SELECT string_agg(DISTINCT d.defaclrole::regrole::text, ', ')
      INTO v_leaked
    FROM pg_default_acl d
    JOIN pg_namespace n ON n.oid = d.defaclnamespace
    WHERE n.nspname = 'public'
      AND d.defaclobjtype IN ('r', 'S')
      AND d.defaclrole NOT IN (
        SELECT oid FROM pg_roles WHERE rolname IN (current_user, 'postgres')
      );
  END IF;

  IF v_leaked IS NOT NULL AND length(v_leaked) > 0 THEN
    RAISE NOTICE
      'AVISO: privilegios padrao da infraestrutura da plataforma (nao alteraveis pelo role postgres), preservados: %',
      v_leaked;
  END IF;
END $$;

-- FUNÇÕES: o EXECUTE para PUBLIC é o DEFAULT GLOBAL DO SISTEMA, não uma
-- entrada de pg_default_acl. Um REVOKE per-schema é um no-op silencioso; só a
-- forma global (sem IN SCHEMA) o remove. A verificação exige uma entrada
-- global (defaclnamespace = 0) que retire o EXECUTE de PUBLIC.
DO $$
DECLARE
  v_role text;
  v_leaked text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY[current_user::regrole::text, 'postgres'] LOOP
    SELECT string_agg(g.privilege_type, ', ')
      INTO v_leaked
    FROM aclexplode(
      coalesce(
        (
          SELECT d.defaclacl
          FROM pg_default_acl d
          WHERE d.defaclrole = v_role::regrole
            AND d.defaclobjtype = 'f'
            AND d.defaclnamespace = 0
        ),
        acldefault('f', v_role::regrole)
      )
    ) g
    WHERE g.grantee = 0
      AND g.privilege_type = 'EXECUTE';

    IF v_leaked IS NOT NULL THEN
      RAISE EXCEPTION
        'FALHA: o default global de funcoes do role % ainda concede EXECUTE a PUBLIC. Aplique "ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC" (sem IN SCHEMA).',
        v_role;
    END IF;
  END LOOP;

  RAISE NOTICE 'OK: default global de funcoes sem EXECUTE para PUBLIC (papeis do projeto).';
END $$;

-- Nenhuma entrada per-schema de FUNCOes pode reintroduzir o EXECUTE para
-- PUBLIC no schema public.
DO $$
DECLARE
  v_leaked text;
BEGIN
  SELECT string_agg(DISTINCT d.defaclrole::regrole::text, ', ')
    INTO v_leaked
  FROM pg_default_acl d
  JOIN pg_namespace n ON n.oid = d.defaclnamespace
  CROSS JOIN LATERAL aclexplode(d.defaclacl) g
  WHERE n.nspname = 'public'
    AND d.defaclobjtype = 'f'
    AND g.grantee = 0
    AND g.privilege_type = 'EXECUTE';

  IF v_leaked IS NOT NULL THEN
    RAISE EXCEPTION
      'FALHA: entrada per-schema de funcoes concede EXECUTE a PUBLIC no schema public (roles: %).',
      v_leaked;
  END IF;

  RAISE NOTICE 'OK: nenhuma entrada per-schema de funcoes concede EXECUTE a PUBLIC.';
END $$;

--------------------------------------------------------------------------------
-- 8. Superfície de exposição das funções
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_leaked text;
BEGIN
  -- 8.1 Funções internas: schema privado, sem USAGE para os papéis da API.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'agenda_flow_private'
      AND p.proname IN (
        'upsert_profile_from_auth_user',
        'handle_new_user',
        'handle_new_establishment',
        'set_updated_at',
        'validate_team_grants'
      )
  ) THEN
    RAISE EXCEPTION 'FALHA: funções internas ausentes no schema agenda_flow_private.';
  END IF;

  -- 8.1.0 O validador interno de cargo/permissões (migration 00008) é interno:
  --        nenhum papel da API pode chamá-lo diretamente.
  IF has_function_privilege('anon', 'agenda_flow_private.validate_team_grants(uuid, text, text[], uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'agenda_flow_private.validate_team_grants(uuid, text, text[], uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'agenda_flow_private.validate_team_grants(uuid, text, text[], uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FALHA: o validador interno de concessões é executável por um papel da API.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'upsert_profile_from_auth_user',
        'handle_new_user',
        'handle_new_establishment',
        'set_updated_at',
        'validate_team_grants'
      )
  ) THEN
    RAISE EXCEPTION 'FALHA: funções internas ainda existem no schema public.';
  END IF;

  -- 8.1.1 Nenhum outro objeto pode depender das funções internas removidas:
  --       as cópias antigas do schema public foram substituídas pelas
  --       equivalentes no schema privado, e nada mais pode referenciá-las.
  IF EXISTS (
    SELECT 1
    FROM pg_depend d
    JOIN pg_proc target ON target.oid = d.objid
    JOIN pg_proc dependent ON dependent.oid = d.refobjid
    WHERE d.classid = 'pg_proc'::regclass
      AND d.refclassid = 'pg_proc'::regclass
      AND d.deptype IN ('n', 'a')
      AND target.pronamespace = 'public'::regnamespace
      AND target.proname IN (
        'upsert_profile_from_auth_user',
        'handle_new_user',
        'handle_new_establishment',
        'set_updated_at'
      )
  ) THEN
    RAISE EXCEPTION
      'FALHA: existem objetos dependendo das funções internas removidas do schema public.';
  END IF;

  IF has_schema_privilege('anon', 'agenda_flow_private', 'USAGE')
     OR has_schema_privilege('authenticated', 'agenda_flow_private', 'USAGE') THEN
    RAISE EXCEPTION 'FALHA: os papéis da API possuem USAGE no schema agenda_flow_private.';
  END IF;

  RAISE NOTICE 'OK: funções internas confinadas ao schema privado.';

  -- 8.2 Matriz de EXECUTE das RPCs de negócio: apenas authenticated.
  SELECT string_agg(p.proname, ', ')
    INTO v_leaked
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'create_establishment',
      'ensure_profile',
      'create_establishment_invitation',
      'accept_establishment_invitation',
      'cancel_establishment_invitation',
      'create_establishment_service',
      'update_establishment_service',
      'set_establishment_service_active',
      'update_establishment_member_role',
      'set_establishment_member_active',
      'set_establishment_member_permissions',
      'get_my_pending_invitations',
      'set_establishment_professional',
      'add_establishment_professional_service',
      'remove_establishment_professional_service',
      'get_establishment_clock',
      'set_establishment_schedule',
      'record_attendance_check_in',
      'record_attendance_check_out',
      'record_attendance_exception',
      'correct_attendance_record'
    )
    AND (
      has_function_privilege('anon', p.oid, 'EXECUTE')
      OR NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
    );

  IF v_leaked IS NOT NULL THEN
    RAISE EXCEPTION 'FALHA: matriz de EXECUTE incorreta nas RPCs de negócio: %', v_leaked;
  END IF;

  RAISE NOTICE 'OK: RPCs de negócio executáveis apenas por authenticated.';

  -- 8.3 Auxiliares de leitura usadas pelas políticas RLS: anon e authenticated.
  SELECT string_agg(p.proname, ', ')
    INTO v_leaked
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'has_permission',
      'get_user_establishment_role',
      'is_establishment_member',
      'is_establishment_owner',
      'is_establishment_owner_or_manager',
      'can_manage_member_role',
      'is_colleague',
      'normalize_phone'
    )
    AND (
      NOT has_function_privilege('anon', p.oid, 'EXECUTE')
      OR NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
    );

  IF v_leaked IS NOT NULL THEN
    RAISE EXCEPTION 'FALHA: auxiliares de leitura com EXECUTE incorreto: %', v_leaked;
  END IF;

  RAISE NOTICE 'OK: auxiliares de leitura executáveis por anon e authenticated.';
END $$;

--------------------------------------------------------------------------------
-- 9. RLS habilitado nas tabelas do projeto
--------------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND c.relname IN (
        'profiles',
        'establishments',
        'establishment_members',
        'member_permissions',
        'establishment_invitations',
        'establishment_services',
        'establishment_professionals',
        'establishment_professional_services',
        'establishment_schedules',
        'attendance_records',
        'attendance_exceptions',
        'attendance_corrections'
      )
      AND NOT c.relrowsecurity
  LOOP
    RAISE EXCEPTION 'FALHA: RLS desabilitado na tabela public.%', r.relname;
  END LOOP;

  RAISE NOTICE 'OK: RLS habilitado em todas as tabelas do projeto.';

  -- Tabelas fora do escopo do projeto são reportadas, sem bloquear a
  -- auditoria.
  FOR r IN
    SELECT c.relname
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
        'establishment_invitations',
        'establishment_services',
        'establishment_professionals',
        'establishment_professional_services',
        'establishment_schedules',
        'attendance_records',
        'attendance_exceptions',
        'attendance_corrections'
      )
  LOOP
    RAISE NOTICE 'AVISO: tabela publica fora do escopo do projeto sem RLS: %', r.relname;
  END LOOP;
END $$;

--------------------------------------------------------------------------------
-- 10. Resolução do pgcrypto (usada pelas RPCs de convites)
--------------------------------------------------------------------------------
DO $$
DECLARE
  v_previous_search_path text;
BEGIN
  v_previous_search_path := current_setting('search_path');

  PERFORM set_config('search_path', 'public, extensions', true);

  BEGIN
    PERFORM encode(gen_random_bytes(4), 'hex');
    PERFORM encode(digest('agenda-flow', 'sha256'), 'hex');
  EXCEPTION WHEN others THEN
    PERFORM set_config('search_path', v_previous_search_path, true);
    RAISE EXCEPTION
      'FALHA: pgcrypto não é resolvível com "search_path = public, extensions" (%).', SQLERRM;
  END;

  PERFORM set_config('search_path', v_previous_search_path, true);

  RAISE NOTICE 'OK: pgcrypto resolvível com o search_path usado pelas RPCs de convites.';
END $$;

--------------------------------------------------------------------------------
-- 11. Resumo
--------------------------------------------------------------------------------
SELECT
  (SELECT count(*) FROM auth.users) AS auth_users,
  (SELECT count(*) FROM public.profiles) AS profiles,
  (SELECT count(*) FROM public.establishments) AS establishments,
  (SELECT count(*) FROM public.establishment_members) AS memberships;
