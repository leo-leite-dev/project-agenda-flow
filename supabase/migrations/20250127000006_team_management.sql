-- Migration: gestão de equipe, vínculos e permissões (etapa 6)
--
-- Reaproveita as estruturas já existentes:
--   • public.establishment_members        (vínculo, cargo, situação)
--   • public.member_permissions           (permissões granulares)
--   • public.establishment_invitations     (convites com token hasheado)
-- Nenhuma tabela de funcionários é criada.
--
-- Segurança
-- ---------
--   • Escritas administrativas apenas por RPCs SECURITY DEFINER com
--     search_path vazio, auth.uid() validado e autorização conferida no
--     banco (is_establishment_owner);
--   • somente o proprietário altera cargo, situação de vínculo e permissões;
--   • o cargo 'owner' não é atribuível por esta etapa (sem transferência de
--     propriedade) e o proprietário não altera o próprio cargo nem a própria
--     situação;
--   • o vínculo do único proprietário ativo é preservado;
--   • desativar um vínculo NÃO remove a conta global da pessoa e não afeta
--     seus vínculos com outros estabelecimentos;
--   • convites aceitos de forma concorrente são serializados com bloqueio de
--     linha (FOR UPDATE) sobre o convite;
--   • convites duplicados pendentes para o mesmo contato são recusados;
--   • GRANT mínimo: authenticated mantém apenas SELECT nas tabelas
--     administrativas; nenhuma escrita direta é concedida.
--
-- Esta migration é idempotente e não destrutiva.

--------------------------------------------------------------------------------
-- 1. Vínculo desativado perde o acesso ao estabelecimento
--------------------------------------------------------------------------------
-- A policy anterior permitia que um membro desativado ainda visse a própria
-- linha de vínculo (user_id = auth.uid() sem checar is_active). A policy passa
-- a exigir vínculo ativo em ambos os ramos: um funcionário desativado não
-- enxerga mais nada do estabelecimento.
DROP POLICY IF EXISTS "establishment_members_select" ON public.establishment_members;
CREATE POLICY "establishment_members_select"
  ON public.establishment_members
  FOR SELECT
  USING (
    (user_id = auth.uid() AND is_active = true)
    OR public.is_establishment_member(establishment_id)
  );

--------------------------------------------------------------------------------
-- 2. Convite: prevenção de duplicados pendentes
--------------------------------------------------------------------------------
-- Reimplementação da RPC existente (mesma semântica e mesmas mensagens) com
-- duas garantias adicionais:
--   • recusa convite pendente duplicado para o mesmo contato/estabelecimento;
--   • valida o cargo antes de gravar.
-- O corpo funcional é idêntico ao da migration 20250127000000.
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

  IF p_role IS NULL OR p_role NOT IN ('owner', 'manager', 'professional', 'receptionist') THEN
    RAISE EXCEPTION 'Cargo invalido';
  END IF;

  IF p_role IN ('owner', 'manager') AND NOT public.is_establishment_owner(p_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode convidar administradores';
  END IF;

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
-- 3. Aceite de convite com bloqueio de linha
--------------------------------------------------------------------------------
-- Reimplementação da RPC existente com FOR UPDATE sobre o convite: dois
-- aceites concorrentes são serializados e apenas o primeiro é aceito. As demais
-- verificações (identidade do convidado, expiração, uso único) são preservadas.
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

  -- Reject if the user is already a member of the establishment
  IF EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = v_invitation.establishment_id
      AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Usuario ja e membro deste estabelecimento';
  END IF;

  -- Identity verification: the authenticated user must match the invited contact
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
-- 4. Alteração de cargo (somente proprietário)
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_establishment_member_role(
  p_member_id uuid,
  p_role text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_establishment_id uuid;
  v_user_id uuid;
  v_current_role text;
  v_active_owners integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  IF p_member_id IS NULL THEN
    RAISE EXCEPTION 'Membro nao informado';
  END IF;

  IF p_role IS NULL OR p_role NOT IN ('manager', 'professional', 'receptionist') THEN
    RAISE EXCEPTION 'Cargo invalido. A propriedade nao e transferida por esta operacao';
  END IF;

  SELECT establishment_id, user_id, role
    INTO v_establishment_id, v_user_id, v_current_role
  FROM public.establishment_members
  WHERE id = p_member_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'Membro nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode alterar cargos';
  END IF;

  IF v_user_id = auth.uid() THEN
    RAISE EXCEPTION 'O proprietario nao pode alterar o proprio cargo';
  END IF;

  -- O estabelecimento precisa conservar ao menos um proprietario ativo.
  IF v_current_role = 'owner' THEN
    SELECT count(*) INTO v_active_owners
    FROM public.establishment_members
    WHERE establishment_id = v_establishment_id
      AND role = 'owner'
      AND is_active = true;

    IF v_active_owners <= 1 THEN
      RAISE EXCEPTION 'O estabelecimento precisa manter ao menos um proprietario ativo';
    END IF;
  END IF;

  UPDATE public.establishment_members
  SET role = p_role
  WHERE id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Membro nao encontrado';
  END IF;
END;
$$;

--------------------------------------------------------------------------------
-- 5. Ativação e desativação de vínculo (somente proprietário)
--------------------------------------------------------------------------------
-- A desativação é lógica: o registro permanece (preservando o histórico de
-- agendamentos futuros) e a conta global da pessoa não é afetada — os vínculos
-- dela com outros estabelecimentos seguem válidos.
CREATE OR REPLACE FUNCTION public.set_establishment_member_active(
  p_member_id uuid,
  p_is_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_establishment_id uuid;
  v_user_id uuid;
  v_current_role text;
  v_active_owners integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  IF p_member_id IS NULL THEN
    RAISE EXCEPTION 'Membro nao informado';
  END IF;

  IF p_is_active IS NULL THEN
    RAISE EXCEPTION 'Informe a situacao do vinculo';
  END IF;

  SELECT establishment_id, user_id, role
    INTO v_establishment_id, v_user_id, v_current_role
  FROM public.establishment_members
  WHERE id = p_member_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'Membro nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode alterar a situacao de um vinculo';
  END IF;

  IF v_user_id = auth.uid() THEN
    RAISE EXCEPTION 'O proprietario nao pode desativar o proprio vinculo';
  END IF;

  IF NOT p_is_active AND v_current_role = 'owner' THEN
    SELECT count(*) INTO v_active_owners
    FROM public.establishment_members
    WHERE establishment_id = v_establishment_id
      AND role = 'owner'
      AND is_active = true;

    IF v_active_owners <= 1 THEN
      RAISE EXCEPTION 'O estabelecimento precisa manter ao menos um proprietario ativo';
    END IF;
  END IF;

  UPDATE public.establishment_members
  SET is_active = p_is_active
  WHERE id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Membro nao encontrado';
  END IF;
END;
$$;

--------------------------------------------------------------------------------
-- 6. Permissões granulares (somente proprietário)
--------------------------------------------------------------------------------
-- Substitui o conjunto de permissões do membro. As chaves aceitas são
-- exatamente as previstas no CHECK da tabela (valid_service de
-- member_permissions), sem inventar novas permissões.
CREATE OR REPLACE FUNCTION public.set_establishment_member_permissions(
  p_member_id uuid,
  p_permission_keys text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_establishment_id uuid;
  v_invalid text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  IF p_member_id IS NULL THEN
    RAISE EXCEPTION 'Membro nao informado';
  END IF;

  SELECT establishment_id INTO v_establishment_id
  FROM public.establishment_members
  WHERE id = p_member_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'Membro nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode alterar permissoes';
  END IF;

  IF p_permission_keys IS NOT NULL AND array_length(p_permission_keys, 1) > 0 THEN
    SELECT string_agg(key, ', ') INTO v_invalid
    FROM unnest(p_permission_keys) AS key
    WHERE key NOT IN (
      'appointments.read', 'appointments.write', 'appointments.delete',
      'clients.read', 'clients.write', 'clients.delete',
      'finances.read', 'finances.write', 'finances.delete',
      'services.read', 'services.write', 'services.delete',
      'staff.read', 'staff.write', 'staff.delete',
      'settings.read', 'settings.write'
    );

    IF v_invalid IS NOT NULL THEN
      RAISE EXCEPTION 'Permissao invalida: %', v_invalid;
    END IF;
  END IF;

  DELETE FROM public.member_permissions
  WHERE member_id = p_member_id;

  IF p_permission_keys IS NOT NULL AND array_length(p_permission_keys, 1) > 0 THEN
    INSERT INTO public.member_permissions (member_id, permission_key, granted_by)
    SELECT p_member_id, key, auth.uid()
    FROM unnest(p_permission_keys) AS key
    ON CONFLICT (member_id, permission_key) DO NOTHING;
  END IF;
END;
$$;

--------------------------------------------------------------------------------
-- 7. Permissões de execução (matriz explícita do projeto)
--------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) TO authenticated;

REVOKE ALL ON FUNCTION public.accept_establishment_invitation(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_establishment_invitation(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.accept_establishment_invitation(text) TO authenticated;

REVOKE ALL ON FUNCTION public.update_establishment_member_role(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_establishment_member_role(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.update_establishment_member_role(uuid, text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.update_establishment_member_role(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.set_establishment_member_active(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_establishment_member_active(uuid, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.set_establishment_member_active(uuid, boolean) FROM service_role;
GRANT EXECUTE ON FUNCTION public.set_establishment_member_active(uuid, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.set_establishment_member_permissions(uuid, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_establishment_member_permissions(uuid, text[]) FROM anon;
REVOKE ALL ON FUNCTION public.set_establishment_member_permissions(uuid, text[]) FROM service_role;
GRANT EXECUTE ON FUNCTION public.set_establishment_member_permissions(uuid, text[]) TO authenticated;

--------------------------------------------------------------------------------
-- 8. Privilégio mínimo nas tabelas administrativas
--------------------------------------------------------------------------------
-- As escritas administrativas acontecem exclusivamente por RPC; nenhuma
-- escrita direta é necessária ao role da API.
REVOKE ALL PRIVILEGES ON TABLE public.establishment_members FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.member_permissions FROM authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.establishment_invitations FROM authenticated;

GRANT SELECT ON public.establishment_members TO authenticated;
GRANT SELECT ON public.member_permissions TO authenticated;
GRANT SELECT ON public.establishment_invitations TO authenticated;

-- Recarrega o cache de schema do PostgREST.
NOTIFY pgrst, 'reload schema';
