-- Migration: Row Level Security policies for Agenda Flow

--------------------------------------------------------------------------------
-- profiles
--------------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select" ON public.profiles;
CREATE POLICY "profiles_select"
  ON public.profiles
  FOR SELECT
  USING (
    auth.uid() = id
    OR public.is_colleague(id)
  );

DROP POLICY IF EXISTS "profiles_update" ON public.profiles;
CREATE POLICY "profiles_update"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Profiles are created automatically by the auth trigger; direct inserts are denied by default.

--------------------------------------------------------------------------------
-- establishments
--------------------------------------------------------------------------------
ALTER TABLE public.establishments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "establishments_select" ON public.establishments;
CREATE POLICY "establishments_select"
  ON public.establishments
  FOR SELECT
  USING (
    owner_id = auth.uid()
    OR public.is_establishment_member(id)
  );

DROP POLICY IF EXISTS "establishments_insert" ON public.establishments;
CREATE POLICY "establishments_insert"
  ON public.establishments
  FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated'
    AND owner_id = auth.uid()
  );

DROP POLICY IF EXISTS "establishments_update" ON public.establishments;
CREATE POLICY "establishments_update"
  ON public.establishments
  FOR UPDATE
  USING (public.is_establishment_owner(id))
  WITH CHECK (public.is_establishment_owner(id));

DROP POLICY IF EXISTS "establishments_delete" ON public.establishments;
CREATE POLICY "establishments_delete"
  ON public.establishments
  FOR DELETE
  USING (public.is_establishment_owner(id));

--------------------------------------------------------------------------------
-- establishment_members
--------------------------------------------------------------------------------
ALTER TABLE public.establishment_members ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "establishment_members_select" ON public.establishment_members;
CREATE POLICY "establishment_members_select"
  ON public.establishment_members
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR public.is_establishment_member(establishment_id)
  );

DROP POLICY IF EXISTS "establishment_members_insert" ON public.establishment_members;
CREATE POLICY "establishment_members_insert"
  ON public.establishment_members
  FOR INSERT
  WITH CHECK (
    public.can_manage_member_role(establishment_id, role)
  );

DROP POLICY IF EXISTS "establishment_members_update" ON public.establishment_members;
CREATE POLICY "establishment_members_update"
  ON public.establishment_members
  FOR UPDATE
  USING (
    public.can_manage_member_role(establishment_id, role)
  )
  WITH CHECK (
    public.can_manage_member_role(establishment_id, role)
  );

DROP POLICY IF EXISTS "establishment_members_delete" ON public.establishment_members;
CREATE POLICY "establishment_members_delete"
  ON public.establishment_members
  FOR DELETE
  USING (
    public.can_manage_member_role(establishment_id, role)
  );

--------------------------------------------------------------------------------
-- member_permissions
--------------------------------------------------------------------------------
ALTER TABLE public.member_permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_permissions_select" ON public.member_permissions;
CREATE POLICY "member_permissions_select"
  ON public.member_permissions
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.establishment_members m
      WHERE m.id = member_permissions.member_id
        AND (
          m.user_id = auth.uid()
          OR public.is_establishment_member(m.establishment_id)
        )
    )
  );

DROP POLICY IF EXISTS "member_permissions_insert" ON public.member_permissions;
CREATE POLICY "member_permissions_insert"
  ON public.member_permissions
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.establishment_members m
      WHERE m.id = member_permissions.member_id
        AND public.is_establishment_owner_or_manager(m.establishment_id)
    )
  );

DROP POLICY IF EXISTS "member_permissions_update" ON public.member_permissions;
CREATE POLICY "member_permissions_update"
  ON public.member_permissions
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.establishment_members m
      WHERE m.id = member_permissions.member_id
        AND public.is_establishment_owner_or_manager(m.establishment_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.establishment_members m
      WHERE m.id = member_permissions.member_id
        AND public.is_establishment_owner_or_manager(m.establishment_id)
    )
  );

DROP POLICY IF EXISTS "member_permissions_delete" ON public.member_permissions;
CREATE POLICY "member_permissions_delete"
  ON public.member_permissions
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1
      FROM public.establishment_members m
      WHERE m.id = member_permissions.member_id
        AND public.is_establishment_owner_or_manager(m.establishment_id)
    )
  );

--------------------------------------------------------------------------------
-- establishment_invitations
--------------------------------------------------------------------------------
ALTER TABLE public.establishment_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "establishment_invitations_select" ON public.establishment_invitations;
CREATE POLICY "establishment_invitations_select"
  ON public.establishment_invitations
  FOR SELECT
  USING (public.is_establishment_owner_or_manager(establishment_id));

DROP POLICY IF EXISTS "establishment_invitations_insert" ON public.establishment_invitations;
CREATE POLICY "establishment_invitations_insert"
  ON public.establishment_invitations
  FOR INSERT
  WITH CHECK (public.is_establishment_owner_or_manager(establishment_id));

DROP POLICY IF EXISTS "establishment_invitations_update" ON public.establishment_invitations;
CREATE POLICY "establishment_invitations_update"
  ON public.establishment_invitations
  FOR UPDATE
  USING (
    public.is_establishment_owner_or_manager(establishment_id)
    AND accepted_at IS NULL
    AND cancelled_at IS NULL
  )
  WITH CHECK (
    public.is_establishment_owner_or_manager(establishment_id)
    AND accepted_at IS NULL
  );

DROP POLICY IF EXISTS "establishment_invitations_delete" ON public.establishment_invitations;
CREATE POLICY "establishment_invitations_delete"
  ON public.establishment_invitations
  FOR DELETE
  USING (public.is_establishment_owner_or_manager(establishment_id));
