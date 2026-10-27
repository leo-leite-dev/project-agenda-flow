-- Migration: protect tenant data when a public profile is deleted
--
-- This migration is prepared locally only. It must not be applied remotely
-- without a separate authorization and a review of affected accounts.
--
-- Deleting an auth.users row may still remove its profile through the
-- profiles_auth_user_id_fkey cascade. The relationships below deliberately
-- refuse deletion while the profile owns an establishment, belongs to a
-- membership, or is recorded as the inviter of an invitation. Account and
-- establishment deletion therefore remain explicit administrative operations.

ALTER TABLE public.establishments
  DROP CONSTRAINT IF EXISTS establishments_owner_id_fkey;

ALTER TABLE public.establishments
  ADD CONSTRAINT establishments_owner_id_fkey
    FOREIGN KEY (owner_id)
    REFERENCES public.profiles(id)
    ON DELETE RESTRICT;

ALTER TABLE public.establishment_members
  DROP CONSTRAINT IF EXISTS establishment_members_user_id_fkey;

ALTER TABLE public.establishment_members
  ADD CONSTRAINT establishment_members_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES public.profiles(id)
    ON DELETE RESTRICT;

ALTER TABLE public.establishment_invitations
  DROP CONSTRAINT IF EXISTS establishment_invitations_invited_by_fkey;

ALTER TABLE public.establishment_invitations
  ADD CONSTRAINT establishment_invitations_invited_by_fkey
    FOREIGN KEY (invited_by)
    REFERENCES public.profiles(id)
    ON DELETE RESTRICT;
