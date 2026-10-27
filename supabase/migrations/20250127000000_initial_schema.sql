-- Migration: initial schema for Agenda Flow multi-tenant SaaS
-- Tables: profiles, establishments, establishment_members, member_permissions, establishment_invitations

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

--------------------------------------------------------------------------------
-- 1. profiles: extends auth.users with public app-level information
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  phone text,
  avatar_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.profiles IS 'Public profile information for authenticated users.';

--------------------------------------------------------------------------------
-- 2. establishments: each tenant (barbershop/salon)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.establishments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  document text,
  phone text,
  email text,
  address jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT slug_format CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

COMMENT ON TABLE public.establishments IS 'Multi-tenant establishments (barbershops/salons).';

--------------------------------------------------------------------------------
-- 3. establishment_members: membership of a user in an establishment
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.establishment_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'professional',
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (establishment_id, user_id),
  CONSTRAINT valid_role CHECK (role IN ('owner', 'manager', 'professional', 'receptionist'))
);

COMMENT ON TABLE public.establishment_members IS 'Links users to establishments with a tenant role.';

--------------------------------------------------------------------------------
-- 4. member_permissions: optional granular permissions per membership
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.member_permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id uuid NOT NULL REFERENCES public.establishment_members(id) ON DELETE CASCADE,
  permission_key text NOT NULL,
  granted_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (member_id, permission_key),
  CONSTRAINT valid_permission_key CHECK (
    permission_key IN (
      'appointments.read', 'appointments.write', 'appointments.delete',
      'clients.read', 'clients.write', 'clients.delete',
      'finances.read', 'finances.write', 'finances.delete',
      'services.read', 'services.write', 'services.delete',
      'staff.read', 'staff.write', 'staff.delete',
      'settings.read', 'settings.write'
    )
  )
);

COMMENT ON TABLE public.member_permissions IS 'Granular permissions assigned to an establishment member.';

--------------------------------------------------------------------------------
-- 5. establishment_invitations: single-use invitations to join a tenant
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.establishment_invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE CASCADE,
  email text,
  phone text,
  token_hash text NOT NULL UNIQUE,
  role text NOT NULL DEFAULT 'professional',
  permissions text[] DEFAULT '{}',
  invited_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT valid_invitation_role CHECK (role IN ('owner', 'manager', 'professional', 'receptionist')),
  CONSTRAINT contact_required CHECK (email IS NOT NULL OR phone IS NOT NULL),
  CONSTRAINT valid_contact CHECK (
    (email IS NOT NULL AND length(trim(email)) > 0)
    OR (phone IS NOT NULL AND length(regexp_replace(phone, '[^0-9]', '', 'g')) > 0)
  )
);

COMMENT ON TABLE public.establishment_invitations IS 'Single-use invitations for users to join an establishment.';

--------------------------------------------------------------------------------
-- Indexes for performance and integrity
--------------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_profiles_phone ON public.profiles(phone);

CREATE INDEX IF NOT EXISTS idx_establishments_owner_id ON public.establishments(owner_id);
CREATE INDEX IF NOT EXISTS idx_establishments_slug ON public.establishments(slug);

CREATE INDEX IF NOT EXISTS idx_establishment_members_establishment_id ON public.establishment_members(establishment_id);
CREATE INDEX IF NOT EXISTS idx_establishment_members_user_id ON public.establishment_members(user_id);

CREATE INDEX IF NOT EXISTS idx_member_permissions_member_id ON public.member_permissions(member_id);

CREATE INDEX IF NOT EXISTS idx_establishment_invitations_establishment_id ON public.establishment_invitations(establishment_id);
CREATE INDEX IF NOT EXISTS idx_establishment_invitations_token_hash ON public.establishment_invitations(token_hash);
CREATE INDEX IF NOT EXISTS idx_establishment_invitations_email ON public.establishment_invitations(email);
CREATE INDEX IF NOT EXISTS idx_establishment_invitations_phone ON public.establishment_invitations(phone);

--------------------------------------------------------------------------------
-- Updated-at trigger helper
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER establishments_updated_at
  BEFORE UPDATE ON public.establishments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

--------------------------------------------------------------------------------
-- Auto-create owner membership when an establishment is inserted directly
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_establishment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.establishment_members (establishment_id, user_id, role)
  VALUES (NEW.id, NEW.owner_id, 'owner')
  ON CONFLICT (establishment_id, user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_establishment_created ON public.establishments;
CREATE TRIGGER on_establishment_created
  AFTER INSERT ON public.establishments
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_establishment();

CREATE TRIGGER establishment_members_updated_at
  BEFORE UPDATE ON public.establishment_members
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

--------------------------------------------------------------------------------
-- Auto-create profile on auth.user creation
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, phone, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      split_part(NEW.email, '@', 1),
      'Usuario'
    ),
    NEW.phone,
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', NEW.raw_user_meta_data->>'picture')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Backfill profiles for users that already existed before this migration
INSERT INTO public.profiles (id, full_name, phone, avatar_url)
SELECT
  id,
  COALESCE(
    raw_user_meta_data->>'full_name',
    raw_user_meta_data->>'name',
    split_part(email, '@', 1),
    'Usuario'
  ),
  phone,
  COALESCE(raw_user_meta_data->>'avatar_url', raw_user_meta_data->>'picture')
FROM auth.users
ON CONFLICT (id) DO NOTHING;

--------------------------------------------------------------------------------
-- Authorization helper functions (SECURITY DEFINER to avoid RLS recursion)
--------------------------------------------------------------------------------

-- Returns the current user's role in a given establishment
CREATE OR REPLACE FUNCTION public.get_user_establishment_role(p_establishment_id uuid)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT role FROM public.establishment_members
  WHERE establishment_id = p_establishment_id
    AND user_id = auth.uid()
    AND is_active = true
  LIMIT 1;
$$;

-- True if current user is an active member of the establishment
CREATE OR REPLACE FUNCTION public.is_establishment_member(p_establishment_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
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
SET search_path = public
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
SET search_path = public
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

-- Permission check for managing a member role (prevents privilege escalation)
CREATE OR REPLACE FUNCTION public.can_manage_member_role(
  p_establishment_id uuid,
  p_target_role text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
SET search_path = public
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
SET search_path = public
STABLE
AS $$
  SELECT regexp_replace(p_phone, '[^0-9]', '', 'g');
$$;

--------------------------------------------------------------------------------
-- Atomic establishment creation with owner membership
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_establishment(
  p_name text,
  p_slug text,
  p_document text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_address jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_establishment_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  INSERT INTO public.establishments (owner_id, name, slug, document, phone, email, address)
  VALUES (auth.uid(), p_name, p_slug, p_document, p_phone, p_email, p_address)
  RETURNING id INTO v_establishment_id;

  INSERT INTO public.establishment_members (establishment_id, user_id, role)
  VALUES (v_establishment_id, auth.uid(), 'owner')
  ON CONFLICT (establishment_id, user_id) DO NOTHING;

  RETURN v_establishment_id;
END;
$$;

--------------------------------------------------------------------------------
-- Invitation management functions
--------------------------------------------------------------------------------

-- Creates an invitation and returns the RAW token (must be shared securely)
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
SET search_path = public
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

-- Accepts an invitation, verifying the authenticated user's identity
CREATE OR REPLACE FUNCTION public.accept_establishment_invitation(p_token text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- Cancels an open invitation
CREATE OR REPLACE FUNCTION public.cancel_establishment_invitation(p_invitation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

--------------------------------------------------------------------------------
-- Permission helper: check if current user has a granular permission
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_permission(
  p_establishment_id uuid,
  p_permission_key text
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
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
