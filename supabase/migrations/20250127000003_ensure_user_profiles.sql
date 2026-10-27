-- Migration: garante a criação de public.profiles para todo usuário autenticado
--
-- Contexto
-- --------
-- A foreign key "establishments_owner_id_fkey" referencia public.profiles(id).
-- Usuários autenticados (Google ou e-mail/senha) que não possuem linha em
-- public.profiles não conseguem vincular um estabelecimento como proprietário,
-- pois a função public.create_establishment insere owner_id = auth.uid().
--
-- Esta migration é idempotente e não destrutiva:
--   * não altera credenciais em auth.users;
--   * não remove nem sobrescreve perfis existentes;
--   * não concede papéis administrativos;
--   * não desabilita RLS.
--
-- Organização das funções (superfície de exposição)
-- -----------------------------------------------
--   schema agenda_flow_private (NÃO exposto ao PostgREST)
--     • funções de trigger e helper interno de provisionamento de perfil.
--       Nenhum papel da API possui USAGE no schema, portanto elas não podem
--       ser chamadas nem mesmo se o EXECUTE for concedido por engano.
--
--   schema public (superfície da API)
--     • RPCs chamadas pelo frontend: create_establishment, ensure_profile,
--       create_establishment_invitation, accept_establishment_invitation,
--       cancel_establishment_invitation;
--     • auxiliares de leitura usadas pelas políticas RLS (que são avaliadas
--       no contexto do role que consulta): has_permission,
--       get_user_establishment_role, is_establishment_member,
--       is_establishment_owner, is_establishment_owner_or_manager,
--       can_manage_member_role, is_colleague, normalize_phone.
--
-- Segurança
-- ---------
-- Todas as funções SECURITY DEFINER são criadas com search_path vazio e
-- referências totalmente qualificadas (schema.objeto), eliminando o risco de
-- resolução de objetos por um search_path manipulável. Exceção deliberada:
-- as funções de convite precisam do pgcrypto e usam
-- "SET search_path = public, extensions".
--
-- Cada função é bloqueada (REVOKE ALL ... FROM PUBLIC) no mesmo ponto em que
-- é criada, de modo que NENHUMA função nova fica exposta a PUBLIC/anon entre
-- esta migration e a 20250127000004. O trigger continua funcionando porque
-- o PostgreSQL verifica o privilégio EXECUTE da função de trigger apenas no
-- momento da criação do trigger, e a execução ocorre com os privilégios do
-- dono (SECURITY DEFINER) — comportamento verificado em PostgreSQL real.

--------------------------------------------------------------------------------
-- 1. Schema privado e extensão pgcrypto
--------------------------------------------------------------------------------
-- Schema sem exposição: o PostgREST do projeto só publica "public" e
-- "graphql_public", portanto nada deste schema é alcançável por RPC.
CREATE SCHEMA IF NOT EXISTS agenda_flow_private;

REVOKE ALL ON SCHEMA agenda_flow_private FROM PUBLIC;
REVOKE ALL ON SCHEMA agenda_flow_private FROM anon;
REVOKE ALL ON SCHEMA agenda_flow_private FROM authenticated;
REVOKE ALL ON SCHEMA agenda_flow_private FROM service_role;

COMMENT ON SCHEMA agenda_flow_private IS
  'Funções internas do Agenda Flow (triggers e provisionamento de perfil). Não exposto à API.';

-- Garante a existência do pgcrypto em um schema conhecido. Se a extensão já
-- estiver instalada (em "extensions" ou em "public"), o comando é apenas um
-- aviso e nada muda.
CREATE SCHEMA IF NOT EXISTS extensions;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

--------------------------------------------------------------------------------
-- 2. Helper interno: cria o perfil a partir de um auth.users existente
--------------------------------------------------------------------------------
-- SECURITY DEFINER para escrever em public.profiles (RLS não permite INSERT
-- direto pelo role authenticated). Vive no schema privado e, portanto, não é
-- alcançável pela API.
CREATE OR REPLACE FUNCTION agenda_flow_private.upsert_profile_from_auth_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user auth.users%ROWTYPE;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_user FROM auth.users WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  INSERT INTO public.profiles (id, full_name, phone, avatar_url)
  VALUES (
    v_user.id,
    COALESCE(
      NULLIF(btrim(v_user.raw_user_meta_data ->> 'full_name'), ''),
      NULLIF(btrim(v_user.raw_user_meta_data ->> 'name'), ''),
      NULLIF(split_part(COALESCE(v_user.email, ''), '@', 1), ''),
      'Usuario'
    ),
    v_user.phone,
    COALESCE(
      v_user.raw_user_meta_data ->> 'avatar_url',
      v_user.raw_user_meta_data ->> 'picture'
    )
  )
  ON CONFLICT (id) DO NOTHING;
END;
$$;

COMMENT ON FUNCTION agenda_flow_private.upsert_profile_from_auth_user(uuid) IS
  'Cria o perfil público a partir do registro em auth.users. Função interna (SECURITY DEFINER).';

REVOKE ALL ON FUNCTION agenda_flow_private.upsert_profile_from_auth_user(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION agenda_flow_private.upsert_profile_from_auth_user(uuid) FROM anon;
REVOKE ALL ON FUNCTION agenda_flow_private.upsert_profile_from_auth_user(uuid) FROM authenticated;
REVOKE ALL ON FUNCTION agenda_flow_private.upsert_profile_from_auth_user(uuid) FROM service_role;

--------------------------------------------------------------------------------
-- 3. Trigger de auth.users: criação automática do perfil
--------------------------------------------------------------------------------
-- A lógica é lida diretamente de NEW (sem consultar auth.users), garantindo
-- que o cadastro do usuário nunca dependa de permissões de leitura extras.
-- Falhas são convertidas em WARNING para não impedir a autenticação: a
-- integridade é garantida pelas funções ensure_profile/create_establishment.
CREATE OR REPLACE FUNCTION agenda_flow_private.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  BEGIN
    INSERT INTO public.profiles (id, full_name, phone, avatar_url)
    VALUES (
      NEW.id,
      COALESCE(
        NULLIF(btrim(NEW.raw_user_meta_data ->> 'full_name'), ''),
        NULLIF(btrim(NEW.raw_user_meta_data ->> 'name'), ''),
        NULLIF(split_part(COALESCE(NEW.email, ''), '@', 1), ''),
        'Usuario'
      ),
      NEW.phone,
      COALESCE(
        NEW.raw_user_meta_data ->> 'avatar_url',
        NEW.raw_user_meta_data ->> 'picture'
      )
    )
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN others THEN
    RAISE WARNING 'Agenda Flow: nao foi possivel criar o perfil do usuario %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

-- Trigger recriado de forma idempotente (garante que exista e esteja ativo).
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION agenda_flow_private.handle_new_user();

REVOKE ALL ON FUNCTION agenda_flow_private.handle_new_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION agenda_flow_private.handle_new_user() FROM anon;
REVOKE ALL ON FUNCTION agenda_flow_private.handle_new_user() FROM authenticated;
REVOKE ALL ON FUNCTION agenda_flow_private.handle_new_user() FROM service_role;

--------------------------------------------------------------------------------
-- 4. Triggers auxiliares (updated_at e vínculo de proprietário)
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION agenda_flow_private.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION agenda_flow_private.handle_new_establishment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.establishment_members (establishment_id, user_id, role)
  VALUES (NEW.id, NEW.owner_id, 'owner')
  ON CONFLICT (establishment_id, user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION agenda_flow_private.set_updated_at() FROM PUBLIC;
REVOKE ALL ON FUNCTION agenda_flow_private.set_updated_at() FROM anon;
REVOKE ALL ON FUNCTION agenda_flow_private.set_updated_at() FROM authenticated;
REVOKE ALL ON FUNCTION agenda_flow_private.set_updated_at() FROM service_role;

REVOKE ALL ON FUNCTION agenda_flow_private.handle_new_establishment() FROM PUBLIC;
REVOKE ALL ON FUNCTION agenda_flow_private.handle_new_establishment() FROM anon;
REVOKE ALL ON FUNCTION agenda_flow_private.handle_new_establishment() FROM authenticated;
REVOKE ALL ON FUNCTION agenda_flow_private.handle_new_establishment() FROM service_role;

-- Triggers recriados apontando para o schema privado (o corpo é idêntico ao
-- da migration 20250127000000).
DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION agenda_flow_private.set_updated_at();

DROP TRIGGER IF EXISTS establishments_updated_at ON public.establishments;
CREATE TRIGGER establishments_updated_at
  BEFORE UPDATE ON public.establishments
  FOR EACH ROW EXECUTE FUNCTION agenda_flow_private.set_updated_at();

DROP TRIGGER IF EXISTS establishment_members_updated_at ON public.establishment_members;
CREATE TRIGGER establishment_members_updated_at
  BEFORE UPDATE ON public.establishment_members
  FOR EACH ROW EXECUTE FUNCTION agenda_flow_private.set_updated_at();

DROP TRIGGER IF EXISTS on_establishment_created ON public.establishments;
CREATE TRIGGER on_establishment_created
  AFTER INSERT ON public.establishments
  FOR EACH ROW EXECUTE FUNCTION agenda_flow_private.handle_new_establishment();

-- As funções internas deixam de existir no schema exposto à API (as cópias
-- remanescentes da migration 20250127000000 são removidas depois que os
-- triggers passaram a apontar para o schema privado).
--
-- Antes de remover, confirma que nenhum outro objeto do banco ainda depende
-- dessas funções (trigger, view, função ou regra). Os triggers desta mesma
-- migration já foram recriados para o schema privado e, portanto, não geram
-- dependência. O DROP abaixo é RESTRICT: se surgisse alguma dependência
-- inesperada, a migration aborta sem deixar o banco inconsistente.
DO $$
DECLARE
  v_dependentes text;
BEGIN
  SELECT string_agg(DISTINCT dependent.proname, ', ') INTO v_dependentes
  FROM pg_depend d
  JOIN pg_proc target ON target.oid = d.objid
  JOIN pg_proc dependent ON dependent.oid = d.refobjid
  WHERE d.classid = 'pg_proc'::regclass
    AND d.refclassid = 'pg_proc'::regclass
    AND d.deptype IN ('n', 'a')
    AND target.pronamespace = 'public'::regnamespace
    AND target.proname IN (
      'set_updated_at',
      'handle_new_establishment',
      'handle_new_user'
    )
    AND NOT EXISTS (
      SELECT 1 FROM pg_trigger t
      WHERE t.tgfoid = target.oid
        AND t.tgname IN (
          'on_auth_user_created',
          'on_establishment_created',
          'profiles_updated_at',
          'establishments_updated_at',
          'establishment_members_updated_at'
        )
    );

  IF v_dependentes IS NOT NULL THEN
    RAISE EXCEPTION
      'FALHA: outros objetos ainda dependem das funcoes internas que serao movidas: %', v_dependentes;
  END IF;

  RAISE NOTICE 'Agenda Flow: nenhuma dependencia externa nas funcoes internas moveidas.';
END;
$$;

DROP FUNCTION IF EXISTS public.set_updated_at();
DROP FUNCTION IF EXISTS public.handle_new_establishment();
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.upsert_profile_from_auth_user(uuid);

--------------------------------------------------------------------------------
-- 5. Função ensure_profile: autocorreção sob demanda (RPC do frontend)
--------------------------------------------------------------------------------
-- Cria o perfil do usuário autenticado caso ainda não exista. Idempotente,
-- preserva dados existentes e nunca cria perfis para outros usuários.
CREATE OR REPLACE FUNCTION public.ensure_profile()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  BEGIN
    PERFORM agenda_flow_private.upsert_profile_from_auth_user(v_user_id);
  EXCEPTION WHEN others THEN
    -- Fallback: perfil mínimo ainda é criado abaixo, garantindo a integridade
    -- da FK establishments_owner_id_fkey mesmo sem leitura de auth.users.
    RAISE WARNING 'Agenda Flow: leitura de auth.users indisponivel para o usuario %: %', v_user_id, SQLERRM;
  END;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_id) THEN
    INSERT INTO public.profiles (id, full_name)
    VALUES (v_user_id, 'Usuario')
    ON CONFLICT (id) DO NOTHING;
  END IF;

  RETURN v_user_id;
END;
$$;

COMMENT ON FUNCTION public.ensure_profile() IS
  'Garante a existencia do perfil do usuario autenticado atual. Idempotente.';

-- Fechado no mesmo momento em que é criado: sem janela de exposição.
REVOKE ALL ON FUNCTION public.ensure_profile() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_profile() FROM anon;
GRANT EXECUTE ON FUNCTION public.ensure_profile() TO authenticated;

--------------------------------------------------------------------------------
-- 6. Backfill dos perfis ausentes (idempotente)
--------------------------------------------------------------------------------
-- Cria SOMENTE os registros faltantes. Perfis existentes são preservados
-- (ON CONFLICT DO NOTHING) e nenhuma credencial de auth.users é tocada.
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
  COALESCE(
    u.raw_user_meta_data ->> 'avatar_url',
    u.raw_user_meta_data ->> 'picture'
  )
FROM auth.users u
ON CONFLICT (id) DO NOTHING;

--------------------------------------------------------------------------------
-- 7. create_establishment: autocorreção do vínculo de propriedade
--------------------------------------------------------------------------------
-- Garante o perfil antes de inserir o estabelecimento, eliminando a possibilidade
-- de erro 23503 (FK establishments_owner_id_fkey) mesmo que o trigger de
-- auth.users não tenha disparado (ex.: usuário criado antes da migration).
CREATE OR REPLACE FUNCTION public.create_establishment(
  p_name text,
  p_slug text,
  p_type text DEFAULT 'salon',
  p_document text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_address jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_establishment_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  IF p_type IS NULL OR p_type NOT IN ('barbershop', 'salon') THEN
    RAISE EXCEPTION 'Tipo de estabelecimento invalido';
  END IF;

  -- Garante o perfil do proprietario (integridade da FK owner_id).
  PERFORM public.ensure_profile();

  INSERT INTO public.establishments (owner_id, name, slug, type, document, phone, email, address)
  VALUES (auth.uid(), p_name, p_slug, p_type, p_document, p_phone, p_email, p_address)
  RETURNING id INTO v_establishment_id;

  INSERT INTO public.establishment_members (establishment_id, user_id, role)
  VALUES (v_establishment_id, auth.uid(), 'owner')
  ON CONFLICT (establishment_id, user_id) DO NOTHING;

  RETURN v_establishment_id;
END;
$$;

-- Remove a sobrecarga obsoleta criada pela migration 20250127000000, que
-- mantinha a assinatura antiga (sem p_type) e podia gerar ambiguidade.
DROP FUNCTION IF EXISTS public.create_establishment(text, text, text, text, text, jsonb);

REVOKE ALL ON FUNCTION public.create_establishment(text, text, text, text, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_establishment(text, text, text, text, text, text, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_establishment(text, text, text, text, text, text, jsonb) TO authenticated;

--------------------------------------------------------------------------------
-- 8. Funções auxiliares usadas pelas políticas RLS
--------------------------------------------------------------------------------
-- Recriadas com search_path vazio e referências qualificadas. O conteúdo
-- funcional é idêntico ao da migration 20250127000000: apenas o isolamento
-- do search_path e as permissões de execução são endurecidos.
-- Permaneecem em "public" porque são avaliadas dentro das políticas RLS, no
-- contexto do role que consulta — exigem USAGE no schema e EXECUTE concedidos
-- de forma explícita, e são somente leitura e escopadas ao próprio tenant.

-- True if current user is an active member of the establishment
CREATE OR REPLACE FUNCTION public.is_establishment_member(p_establishment_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = p_establishment_id
      AND user_id = auth.uid()
      AND is_active = true
  );
$$;

-- True if current user is owner of the establishment
CREATE OR REPLACE FUNCTION public.is_establishment_owner(p_establishment_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = p_establishment_id
      AND user_id = auth.uid()
      AND is_active = true
      AND role = 'owner'
  );
$$;

-- True if current user is owner or manager
CREATE OR REPLACE FUNCTION public.is_establishment_owner_or_manager(p_establishment_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.establishment_members
    WHERE establishment_id = p_establishment_id
      AND user_id = auth.uid()
      AND is_active = true
      AND role IN ('owner', 'manager')
  );
$$;

-- Returns the current user's role in a given establishment
CREATE OR REPLACE FUNCTION public.get_user_establishment_role(p_establishment_id uuid)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT role FROM public.establishment_members
  WHERE establishment_id = p_establishment_id
    AND user_id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;

-- Permission check for managing a member role (prevents privilege escalation)
CREATE OR REPLACE FUNCTION public.can_manage_member_role(
  p_establishment_id uuid,
  p_target_role text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_my_role text;
BEGIN
  v_my_role := public.get_user_establishment_role(p_establishment_id);

  IF v_my_role IS NULL THEN
    RETURN false;
  END IF;

  -- Only owners can assign or manage owner/manager roles
  IF p_target_role IN ('owner', 'manager') THEN
    RETURN v_my_role = 'owner';
  END IF;

  -- Owners and managers can manage professional/receptionist roles
  RETURN v_my_role IN ('owner', 'manager');
END;
$$;

-- True if current user belongs to any establishment that the target profile also belongs to
CREATE OR REPLACE FUNCTION public.is_colleague(p_profile_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.establishment_members my_members
    JOIN public.establishment_members their_members
      ON my_members.establishment_id = their_members.establishment_id
    WHERE my_members.user_id = auth.uid()
      AND my_members.is_active = true
      AND their_members.user_id = p_profile_id
      AND their_members.is_active = true
  );
$$;

-- Normalizes a phone number by keeping only digits (E.164 comparison helper)
CREATE OR REPLACE FUNCTION public.normalize_phone(p_phone text)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT regexp_replace(p_phone, '[^0-9]', '', 'g');
$$;

-- Permission helper: check if current user has a granular permission
CREATE OR REPLACE FUNCTION public.has_permission(
  p_establishment_id uuid,
  p_permission_key text
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.establishment_members m
    JOIN public.member_permissions mp ON mp.member_id = m.id
    WHERE m.establishment_id = p_establishment_id
      AND m.user_id = auth.uid()
      AND m.is_active = true
      AND mp.permission_key = p_permission_key
  )
  OR public.is_establishment_owner_or_manager(p_establishment_id);
$$;

-- Permissões de execução: as auxiliares de leitura alimentam as políticas
-- RLS. Precisam ser executáveis pelo role que consulta (authenticated) e
-- também por anon, para que uma consulta anônima seja avaliada como "sem
-- linhas visíveis" em vez de falhar com "permission denied for function".
REVOKE ALL ON FUNCTION public.is_establishment_member(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_establishment_member(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.is_establishment_member(uuid) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.is_establishment_owner(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_establishment_owner(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.is_establishment_owner(uuid) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.is_establishment_owner_or_manager(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_establishment_owner_or_manager(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.is_establishment_owner_or_manager(uuid) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.get_user_establishment_role(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_establishment_role(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.get_user_establishment_role(uuid) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.can_manage_member_role(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_manage_member_role(uuid, text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_member_role(uuid, text) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.is_colleague(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_colleague(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.is_colleague(uuid) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.normalize_phone(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.normalize_phone(text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.normalize_phone(text) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.has_permission(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.has_permission(uuid, text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.has_permission(uuid, text) TO anon, authenticated;

--------------------------------------------------------------------------------
-- 9. Funções de negócio de convites (convites de acesso)
--------------------------------------------------------------------------------
-- Recriadas por dois motivos:
--   1) hardening do search_path e das referências;
--   2) CORREÇÃO DE UM BUG LATENTE: as funções originais declaravam
--      "SET search_path = public" e chamavam gen_random_bytes()/digest(),
--      que pertencem ao pgcrypto. No Supabase o pgcrypto é instalado no schema
--      "extensions" (que faz parte do search_path padrão do banco, mas NÃO de
--      um search_path restrito a "public"). Com a definição original, a
--      criação de convites falhava em runtime com
--      "function gen_random_bytes(integer) does not exist".
--      "SET search_path = public, extensions" resolve o pgcrypto tanto quando
--      ele está em "extensions" (Supabase) quanto quando está em "public"
--      (instalação local da extensão).
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

  IF p_role IN ('owner', 'manager') AND NOT public.is_establishment_owner(p_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode convidar administradores';
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
    AND accepted_at IS NULL
    AND cancelled_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
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

CREATE OR REPLACE FUNCTION public.cancel_establishment_invitation(p_invitation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.establishment_invitations
  SET cancelled_at = now()
  WHERE id = p_invitation_id
    AND public.is_establishment_owner_or_manager(establishment_id)
    AND accepted_at IS NULL
    AND cancelled_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Convite nao encontrado, ja utilizado ou sem permissao';
  END IF;
END;
$$;

-- Permissões de execução: RPCs de negócio, apenas para `authenticated`.
REVOKE ALL ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) FROM anon;
REVOKE ALL ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) FROM service_role;
GRANT EXECUTE ON FUNCTION public.create_establishment_invitation(uuid, text, text, text, text[], interval) TO authenticated;

REVOKE ALL ON FUNCTION public.accept_establishment_invitation(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_establishment_invitation(text) FROM anon;
REVOKE ALL ON FUNCTION public.accept_establishment_invitation(text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.accept_establishment_invitation(text) TO authenticated;

REVOKE ALL ON FUNCTION public.cancel_establishment_invitation(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_establishment_invitation(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.cancel_establishment_invitation(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.cancel_establishment_invitation(uuid) TO authenticated;

--------------------------------------------------------------------------------
-- 10. Verificação da resolução do pgcrypto com o search_path das RPCs
--------------------------------------------------------------------------------
-- Garante, no momento da aplicação, que as funções de convite conseguirão
-- resolver gen_random_bytes()/digest() (falha aqui evita o erro em runtime).
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
      'FALHA: pgcrypto nao resolvivel com "search_path = public, extensions" (%). Verifique a instalacao da extensao.', SQLERRM;
  END;

  PERFORM set_config('search_path', v_previous_search_path, true);

  RAISE NOTICE 'Agenda Flow: resolucao do pgcrypto validada.';
END;
$$;

--------------------------------------------------------------------------------
-- 11. Estado da migration 20250127000002_add_establishment_type
--------------------------------------------------------------------------------
-- Garante a existencia da coluna e do CHECK constraint, cobrindo o caso em que
-- a coluna foi criada manualmente (ADD COLUMN IF NOT EXISTS nao recria o
-- constraint quando a coluna ja existe).
ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS type text NOT NULL DEFAULT 'salon';

DO $$
DECLARE
  v_invalid integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'valid_establishment_type'
      AND conrelid = 'public.establishments'::regclass
  ) THEN
    SELECT count(*) INTO v_invalid
    FROM public.establishments
    WHERE type IS NULL OR type NOT IN ('barbershop', 'salon');

    IF v_invalid > 0 THEN
      ALTER TABLE public.establishments
        ADD CONSTRAINT valid_establishment_type
        CHECK (type IN ('barbershop', 'salon')) NOT VALID;
      RAISE NOTICE 'Agenda Flow: constraint valid_establishment_type adicionada como NOT VALID (ha dados invalidos).';
    ELSE
      ALTER TABLE public.establishments
        ADD CONSTRAINT valid_establishment_type
        CHECK (type IN ('barbershop', 'salon'));
    END IF;
  END IF;
END;
$$;

-- Recarrega o cache de schema do PostgREST (disponibiliza ensure_profile).
NOTIFY pgrst, 'reload schema';
