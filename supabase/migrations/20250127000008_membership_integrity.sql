-- Migration: integridade dos vínculos e proteção do proprietário (correção do
-- estabelecimento duplicado)
--
-- Contexto
-- --------
-- A tela "Escolha um estabelecimento" exibia a mesma empresa duas vezes e o
-- clique não avançava para o dashboard. A causa raiz NÃO era um vínculo
-- duplicado no banco, e sim a consulta do frontend: ela lia
-- public.establishment_members sem filtrar por user_id e, como a política RLS
-- permite que um membro leia os vínculos dos colegas do mesmo tenant (necessário
-- para a tela de equipe), o resultado trazia o vínculo do proprietário E o do
-- profissional — dois usuários diferentes.
--
-- Esta migration trata a ORIGEM do problema no banco:
--
--   1. Garante a constraint UNIQUE (establishment_id, user_id) em
--      public.establishment_members: um usuário tem no máximo um vínculo
--      efetivo por estabelecimento, com um cargo definido nesse vínculo. O
--      mesmo usuário pode ter vínculos em empresas diferentes.
--      • A constraint só é adicionada se ainda não existir (idempotente).
--      • Se existirem vínculos duplicados históricos, a migration ABORTA com
--        um relatório — NENHUM registro é excluído ou alterado
--        automaticamente. A limpeza é uma decisão do administrador.
--
--   2. create_establishment_invitation recusa convidar um contato que já
--      possui vínculo ativo no mesmo estabelecimento. Isso protege o
--      proprietário: um convite para a própria empresa é recusado na origem,
--      com a informação de que a pessoa já pertence ao estabelecimento, e
--      jamais cria um segundo vínculo nem substitui o cargo.
--
--   3. O fluxo comum de convites NUNCA concede o cargo de proprietário: a
--      transferência de propriedade não faz parte desta etapa. Apenas cargos
--      de funcionário são aceitáveis (manager, professional, receptionist) e
--      somente o proprietário pode conceder administradores.
--
--   4. As permissões concedidas por um convite são validadas NO BANCO: só
--      chaves previstas no schema do projeto são aceitas e um gerente
--      concede apenas as permissões que possui (delegação). Convites já
--      existentes são revalidados no aceite, de modo que um convite antigo
--      não possa conceder cargo de proprietário nem permissões superiores.
--
--   5. accept_establishment_invitation verifica a IDENTIDADE do convidado
--      antes da existência do vínculo e jamais cria/rebaixa um vínculo
--      existente: quem já pertence ao estabelecimento é informado, e o cargo
--      atual (inclusive o de proprietário) é preservado. A alteração de cargo
--      continua sendo exclusiva do fluxo administrativo
--      (update_establishment_member_role).
--
-- Segurança
-- ---------
--   * Nenhuma policy RLS é afrouxada; nenhuma tabela ganha privilégio de
--     escrita para o role da API;
--   * o vínculo com public.establishments.owner_id é preservado: o
--     proprietário continua sendo reconhecido por
--     is_establishment_owner/has_permission;
--   * a matriz de permissões do projeto é preservada: nenhuma chave nova é
--     inventada e nenhum papel administrativo é concedido pelo frontend;
--   * as RPCs mantêm a mesma assinatura e a mesma matriz de EXECUTE
--     (apenas authenticated).
--
-- Esta migration é idempotente e não destrutiva.

--------------------------------------------------------------------------------
-- 1. Constraint UNIQUE (establishment_id, user_id)
--------------------------------------------------------------------------------
-- Verifica se já existe uma constraint (ou índice único) que garanta a
-- unicidade do vínculo. A busca usa as colunas efetivamente indexadas, sem
-- depender do nome do objeto (as tabelas do projeto foram criadas também pelo
-- SQL Editor do Supabase).
--
-- O comentário da unicidade é aplicado ao OBJETO REALMENTE existente
-- (constraint ou índice), e não a um nome fixo: assim a migration não falha
-- quando a unicidade já está garantida por um objeto com outro nome.
DO $$
DECLARE
  v_unique_constraint text;
  v_unique_index_schema text;
  v_unique_index_name text;
  v_duplicate_groups integer;
  v_duplicate_rows integer;
  v_duplicate_detail text;
  v_comment text := 'Um usuario possui no maximo um vinculo por estabelecimento (o mesmo usuario pode ter vinculos em empresas diferentes).';
BEGIN
  -- (a) Constraint única sobre (establishment_id, user_id)?
  SELECT c.conname INTO v_unique_constraint
  FROM pg_constraint c
  WHERE c.conrelid = 'public.establishment_members'::regclass
    AND c.contype = 'u'
    AND (
      SELECT array_agg(a.attname::text ORDER BY a.attname::text)
      FROM unnest(c.conkey) AS k(attnum)
      JOIN pg_attribute a
        ON a.attrelid = c.conrelid
       AND a.attnum = k.attnum
    ) = ARRAY['establishment_id', 'user_id']
  LIMIT 1;

  IF v_unique_constraint IS NOT NULL THEN
    EXECUTE format(
      'COMMENT ON CONSTRAINT %I ON public.establishment_members IS %L',
      v_unique_constraint,
      v_comment
    );
    RAISE NOTICE 'Agenda Flow: unicidade de vinculo ja garantida pela constraint %.', v_unique_constraint;
    RETURN;
  END IF;

  -- (b) Índice único (sem constraint) sobre (establishment_id, user_id)?
  SELECT n.nspname, c.relname INTO v_unique_index_schema, v_unique_index_name
  FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE i.indrelid = 'public.establishment_members'::regclass
    AND i.indisunique
    AND i.indisvalid
    AND i.indpred IS NULL
    AND (
      SELECT array_agg(a.attname::text ORDER BY a.attname::text)
      FROM unnest(i.indkey::smallint[]) AS k(attnum)
      JOIN pg_attribute a
        ON a.attrelid = i.indrelid
       AND a.attnum = k.attnum
    ) = ARRAY['establishment_id', 'user_id']
  LIMIT 1;

  IF v_unique_index_name IS NOT NULL THEN
    EXECUTE format(
      'COMMENT ON INDEX %I.%I IS %L',
      v_unique_index_schema,
      v_unique_index_name,
      v_comment
    );
    RAISE NOTICE 'Agenda Flow: unicidade de vinculo ja garantida pelo indice %.%.',
      v_unique_index_schema, v_unique_index_name;
    RETURN;
  END IF;

  -- (c) Diagnóstico dos dados históricos (somente leitura).
  SELECT count(*), coalesce(sum(d.total), 0)
  INTO v_duplicate_groups, v_duplicate_rows
  FROM (
    SELECT count(*) AS total
    FROM public.establishment_members
    GROUP BY establishment_id, user_id
    HAVING count(*) > 1
  ) AS d;

  IF v_duplicate_groups > 0 THEN
    SELECT string_agg(d.detail, E'\n')
    INTO v_duplicate_detail
    FROM (
      SELECT format(
        'establishment_id=%s user_id=%s ocorrencias=%s (ids: %s)',
        m.establishment_id,
        m.user_id,
        count(*),
        string_agg(m.id::text, ', ' ORDER BY m.created_at, m.id)
      ) AS detail
      FROM public.establishment_members m
      GROUP BY m.establishment_id, m.user_id
      HAVING count(*) > 1
    ) AS d;

    RAISE EXCEPTION
      E'FALHA: %s grupo(s) de vinculos duplicados em public.establishment_members (%s registro(s) afetado(s)).\nNenhum registro foi alterado.\nRevise os dados abaixo e remova os vinculos redundantes (preservando o vinculo de proprietario) antes de aplicar esta migration:\n%s',
      v_duplicate_groups,
      v_duplicate_rows,
      v_duplicate_detail;
  END IF;

  -- (d) Nenhum objeto garante a unicidade: a constraint é criada.
  ALTER TABLE public.establishment_members
    ADD CONSTRAINT establishment_members_establishment_id_user_id_key
    UNIQUE (establishment_id, user_id);

  EXECUTE format(
    'COMMENT ON CONSTRAINT %I ON public.establishment_members IS %L',
    'establishment_members_establishment_id_user_id_key',
    v_comment
  );

  RAISE NOTICE 'Agenda Flow: constraint UNIQUE (establishment_id, user_id) adicionada.';
END;
$$;

--------------------------------------------------------------------------------
-- 2. Helper interno: validação de cargo e permissões concedidas
--------------------------------------------------------------------------------
-- Função INTERNA (schema privado, sem USAGE para os papéis da API): valida,
-- NO POSTGRESQL, o cargo e as permissões que um convite pode conceder.
--
-- Matriz do projeto (preservada, sem chaves novas):
--   * cargos de funcionário: manager, professional e receptionist.
--     A transferência de propriedade NÃO faz parte desta etapa — o cargo
--     'owner' nunca é concedido por convite. O proprietário é definido em
--     public.establishments.owner_id e pelo trigger de criação do
--     estabelecimento;
--   * somente o proprietário pode conceder o cargo de administrador
--     ('manager'); um gerente não cria outros administradores;
--   * as permissões só podem ser chaves previstas no schema do projeto;
--   * um gerente concede apenas as permissões que possui (delegação); o
--     proprietário pode conceder qualquer chave válida;
--   * quem concede precisa ser o proprietário ou um gerente ativo do
--     estabelecimento.
--
-- A mesma função é usada na criação do convite e no aceite: um convite já
-- existente (criado antes desta migration) é revalidado no aceite e não
-- pode conceder cargo de proprietário nem permissões superiores.
CREATE OR REPLACE FUNCTION agenda_flow_private.validate_team_grants(
  p_establishment_id uuid,
  p_role text,
  p_permissions text[],
  p_granted_by uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_allowed_keys text[] := ARRAY[
    'appointments.read', 'appointments.write', 'appointments.delete',
    'clients.read', 'clients.write', 'clients.delete',
    'finances.read', 'finances.write', 'finances.delete',
    'services.read', 'services.write', 'services.delete',
    'staff.read', 'staff.write', 'staff.delete',
    'settings.read', 'settings.write'
  ];
  v_invalid text;
  v_granted_by_is_owner boolean;
  v_granted_by_is_manager boolean;
  v_granted_keys text[];
BEGIN
  IF p_establishment_id IS NULL THEN
    RAISE EXCEPTION 'Estabelecimento nao informado';
  END IF;

  IF p_granted_by IS NULL THEN
    RAISE EXCEPTION 'Concedente nao informado';
  END IF;

  -- (1) Cargo: apenas cargos de funcionario. A propriedade nao e transferida
  --     por convite (o cargo 'owner' nao existe no fluxo de convites).
  IF p_role IS NULL OR p_role NOT IN ('manager', 'professional', 'receptionist') THEN
    RAISE EXCEPTION
      'Cargo invalido para convite: apenas manager, professional e receptionist podem ser concedidos por convite';
  END IF;

  -- (2) Quem concede precisa ser o proprietario ou um gerente ativo.
  SELECT EXISTS (
    SELECT 1
    FROM public.establishments e
    WHERE e.id = p_establishment_id
      AND e.owner_id = p_granted_by
  ) INTO v_granted_by_is_owner;

  SELECT EXISTS (
    SELECT 1
    FROM public.establishment_members m
    WHERE m.establishment_id = p_establishment_id
      AND m.user_id = p_granted_by
      AND m.is_active = true
      AND m.role = 'manager'
  ) INTO v_granted_by_is_manager;

  IF NOT (v_granted_by_is_owner OR v_granted_by_is_manager) THEN
    RAISE EXCEPTION
      'Somente o proprietario ou um gerente ativo do estabelecimento pode conceder vinculos e permissoes';
  END IF;

  -- (3) Somente o proprietario concede administradores.
  IF p_role = 'manager' AND NOT v_granted_by_is_owner THEN
    RAISE EXCEPTION 'Apenas o proprietario pode convidar administradores';
  END IF;

  -- (4) Permissoes: apenas chaves conhecidas do projeto.
  IF p_permissions IS NOT NULL AND array_length(p_permissions, 1) > 0 THEN
    SELECT string_agg(k, ', ')
    INTO v_invalid
    FROM unnest(p_permissions) AS k
    WHERE NOT (k = ANY(v_allowed_keys));

    IF v_invalid IS NOT NULL THEN
      RAISE EXCEPTION 'Permissao invalida: %', v_invalid;
    END IF;
  END IF;

  -- (5) Um gerente concede apenas o que possui (delegacao). O proprietario
  --     pode conceder qualquer chave valida.
  IF NOT v_granted_by_is_owner
     AND p_permissions IS NOT NULL
     AND array_length(p_permissions, 1) > 0 THEN
    SELECT coalesce(array_agg(mp.permission_key), ARRAY[]::text[])
    INTO v_granted_keys
    FROM public.member_permissions mp
    JOIN public.establishment_members m ON m.id = mp.member_id
    WHERE m.establishment_id = p_establishment_id
      AND m.user_id = p_granted_by
      AND m.is_active = true;

    IF EXISTS (
      SELECT 1
      FROM unnest(p_permissions) AS k
      WHERE NOT (k = ANY(v_granted_keys))
    ) THEN
      RAISE EXCEPTION
        'Permissao nao autorizada: o gerente nao pode conceder permissoes que nao possui';
    END IF;
  END IF;
END;
$$;

COMMENT ON FUNCTION agenda_flow_private.validate_team_grants(uuid, text, text[], uuid) IS
  'Valida cargo e permissoes concedidos por convite (uso interno, schema privado).';

REVOKE ALL ON FUNCTION agenda_flow_private.validate_team_grants(uuid, text, text[], uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION agenda_flow_private.validate_team_grants(uuid, text, text[], uuid) FROM anon;
REVOKE ALL ON FUNCTION agenda_flow_private.validate_team_grants(uuid, text, text[], uuid) FROM authenticated;
REVOKE ALL ON FUNCTION agenda_flow_private.validate_team_grants(uuid, text, text[], uuid) FROM service_role;

--------------------------------------------------------------------------------
-- 3. Convite: cargo de funcionario, permissões validadas e recusa de quem já
--    pertence ao estabelecimento
--------------------------------------------------------------------------------
-- Reimplementação da RPC existente (mesma semântica, mesma assinatura) com as
-- garantias de que um convite nunca vira um segundo vínculo nem um escalonamento
-- de privilégios:
--   • cargo: apenas manager, professional e receptionist (o cargo 'owner' não
--     existe no fluxo de convites — a propriedade não é transferida aqui);
--   • 'manager' somente quando quem convida é o proprietário;
--   • permissões: apenas chaves do projeto e, para o gerente, apenas as que
--     ele próprio possui;
--   • contato com vínculo ATIVO no mesmo estabelecimento → recusado com a
--     informação de que a pessoa já pertence ao estabelecimento (o
--     proprietário está incluído nessa regra);
--   • convites para contatos de OUTROS estabelecimentos são permitidos (o
--     mesmo usuário pode trabalhar em empresas diferentes).
CREATE OR REPLACE FUNCTION public.create_establishment_invitation(
  p_establishment_id uuid,
  p_email text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_role text DEFAULT 'professional',
  p_permissions text[] DEFAULT '{}',
  p_expires_in interval DEFAULT '7 days'::interval
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_raw_token text;
  v_token_hash text;
BEGIN
  IF NOT public.is_establishment_owner_or_manager(p_establishment_id) THEN
    RAISE EXCEPTION 'Sem permissao para convidar membros';
  END IF;

  IF p_email IS NULL AND p_phone IS NULL THEN
    RAISE EXCEPTION 'E-mail ou telefone sao obrigatorios';
  END IF;

  IF p_email IS NOT NULL AND length(trim(p_email)) = 0 THEN
    RAISE EXCEPTION 'E-mail invalido';
  END IF;

  IF p_phone IS NOT NULL AND length(public.normalize_phone(p_phone)) = 0 THEN
    RAISE EXCEPTION 'Telefone invalido';
  END IF;

  -- Cargo e permissões são validados NO BANCO (helper interno). O cargo
  -- 'owner' é recusado: a transferência de propriedade não faz parte desta
  -- etapa e o proprietário atual é preservado.
  PERFORM agenda_flow_private.validate_team_grants(
    p_establishment_id,
    p_role,
    p_permissions,
    auth.uid()
  );

  -- Prevenção de convites duplicados indevidos para o mesmo contato.
  IF p_email IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.establishment_invitations i
    WHERE i.establishment_id = p_establishment_id
      AND i.email = lower(trim(p_email))
      AND i.accepted_at IS NULL
      AND i.cancelled_at IS NULL
      AND i.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'Ja existe um convite pendente para este contato';
  END IF;

  -- O contato já pertence ao estabelecimento (o proprietário também pertence):
  -- o convite é recusado na origem. A alteração de cargo de um funcionário
  -- existente é feita pelo fluxo administrativo (update_establishment_member_role).
  IF EXISTS (
    SELECT 1
    FROM auth.users u
    JOIN public.establishment_members m ON m.user_id = u.id
    WHERE m.establishment_id = p_establishment_id
      AND m.is_active = true
      AND (
        (p_email IS NOT NULL AND lower(u.email) = lower(trim(p_email)))
        OR (
          p_phone IS NOT NULL
          AND u.phone IS NOT NULL
          AND public.normalize_phone(u.phone) = public.normalize_phone(p_phone)
        )
      )
  ) THEN
    RAISE EXCEPTION 'Esta pessoa ja pertence a este estabelecimento; o vinculo e o cargo atuais foram preservados';
  END IF;

  v_raw_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');

  INSERT INTO public.establishment_invitations (
    establishment_id,
    email,
    phone,
    token_hash,
    role,
    permissions,
    invited_by,
    expires_at
  ) VALUES (
    p_establishment_id,
    lower(p_email),
    public.normalize_phone(p_phone),
    v_token_hash,
    p_role,
    p_permissions,
    auth.uid(),
    now() + p_expires_in
  );

  RETURN v_raw_token;
END;
$$;

--------------------------------------------------------------------------------
-- 4. Aceite de convite: identidade verificada antes do vínculo
--------------------------------------------------------------------------------
-- Reimplementação da RPC existente com a mesma garantia de bloqueio de linha
-- (FOR UPDATE) e as seguintes garantias adicionais:
--   • a identidade do convidado é verificada ANTES da verificação de vínculo,
--     de modo que um convite nunca é recusado pelo motivo errado;
--   • o convite é REVALIDADO no aceite (cargo de funcionário e permissões
--     dentro da matriz do projeto): um convite antigo — criado antes desta
--     migration — não pode conceder cargo de proprietário nem permissões
--     superiores às do concedente;
--   • se a pessoa já pertence ao estabelecimento (inclusive o proprietário),
--     nada é criado, nenhum cargo é trocado ou rebaixado e a pessoa é
--     informada de que já pertence ao estabelecimento;
--   • o vínculo desativado não é reativado pelo convite: a reativação é do
--     fluxo administrativo (set_establishment_member_active).
CREATE OR REPLACE FUNCTION public.accept_establishment_invitation(p_token text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_invitation public.establishment_invitations%ROWTYPE;
  v_user_email text;
  v_user_email_confirmed_at timestamptz;
  v_user_phone text;
  v_user_phone_confirmed_at timestamptz;
  v_member_id uuid;
  v_is_owner boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  SELECT email, email_confirmed_at, phone, phone_confirmed_at
    INTO v_user_email, v_user_email_confirmed_at, v_user_phone, v_user_phone_confirmed_at
  FROM auth.users
  WHERE id = auth.uid();

  SELECT * INTO v_invitation
  FROM public.establishment_invitations
  WHERE token_hash = encode(digest(p_token, 'sha256'), 'hex')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Convite invalido, expirado ou ja utilizado';
  END IF;

  IF v_invitation.accepted_at IS NOT NULL
     OR v_invitation.cancelled_at IS NOT NULL
     OR v_invitation.expires_at <= now() THEN
    RAISE EXCEPTION 'Convite invalido, expirado ou ja utilizado';
  END IF;

  -- Identity verification: the authenticated user must match the invited contact.
  IF v_invitation.email IS NOT NULL THEN
    IF lower(v_invitation.email) != lower(v_user_email) THEN
      RAISE EXCEPTION 'E-mail do convite nao corresponde a conta autenticada';
    END IF;
    IF v_user_email_confirmed_at IS NULL THEN
      RAISE EXCEPTION 'E-mail ainda nao foi confirmado';
    END IF;
  END IF;

  IF v_invitation.phone IS NOT NULL THEN
    IF v_invitation.phone != public.normalize_phone(v_user_phone) THEN
      RAISE EXCEPTION 'Telefone do convite nao corresponde a conta autenticada';
    END IF;
    IF v_user_phone_confirmed_at IS NULL THEN
      RAISE EXCEPTION 'Telefone ainda nao foi confirmado';
    END IF;
  END IF;

  -- Revalidação do convite no aceite: cargo de funcionário e permissões dentro
  -- da matriz do projeto, concedidas por quem criou o convite. Um convite já
  -- existente não pode conceder cargo de proprietário nem permissões
  -- superiores — o proprietário atual e establishments.owner_id são preservados.
  PERFORM agenda_flow_private.validate_team_grants(
    v_invitation.establishment_id,
    v_invitation.role,
    v_invitation.permissions,
    v_invitation.invited_by
  );

  -- O convite nunca cria um segundo vínculo: se a pessoa já pertence ao
  -- estabelecimento, ela é informada e o vínculo/cargo atual é preservado
  -- (inclusive o cargo de proprietário).
  IF EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_invitation.establishment_id
      AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Voce ja pertence a este estabelecimento; o vinculo e o cargo atuais foram preservados';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.establishments
    WHERE id = v_invitation.establishment_id
      AND owner_id = auth.uid()
  ) INTO v_is_owner;

  IF v_is_owner THEN
    RAISE EXCEPTION 'Voce e o proprietario deste estabelecimento; o convite foi recusado e seus privilegios foram preservados';
  END IF;

  INSERT INTO public.establishment_members (establishment_id, user_id, role)
  VALUES (v_invitation.establishment_id, auth.uid(), v_invitation.role)
  RETURNING id INTO v_member_id;

  IF v_invitation.permissions IS NOT NULL AND array_length(v_invitation.permissions, 1) > 0 THEN
    INSERT INTO public.member_permissions (member_id, permission_key, granted_by)
    SELECT v_member_id, unnest(v_invitation.permissions), v_invitation.invited_by
    ON CONFLICT (member_id, permission_key) DO NOTHING;
  END IF;

  UPDATE public.establishment_invitations
  SET accepted_at = now()
  WHERE id = v_invitation.id;

  RETURN v_member_id;
END;
$$;

--------------------------------------------------------------------------------
-- 5. Permissões de execução (matriz explícita do projeto)
--------------------------------------------------------------------------------
-- As assinaturas não mudam: as concessões são reemitidas para que a matriz
-- continue explícita e verificável.
REVOKE ALL ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) FROM anon;
REVOKE ALL ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) FROM service_role;
GRANT EXECUTE ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) TO authenticated;

REVOKE ALL ON FUNCTION public.accept_establishment_invitation(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_establishment_invitation(text) FROM anon;
REVOKE ALL ON FUNCTION public.accept_establishment_invitation(text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.accept_establishment_invitation(text) TO authenticated;

-- Nenhuma escrita direta é concedida: as regras de negócio continuam
-- exclusivamente nas RPCs.
REVOKE ALL PRIVILEGES ON TABLE public.establishment_members FROM authenticated;
GRANT SELECT ON public.establishment_members TO authenticated;

-- Recarrega o cache de schema do PostgREST.
NOTIFY pgrst, 'reload schema';
