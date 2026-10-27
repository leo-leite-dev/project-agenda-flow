-- Recovery procedure for auth.users rows without public.profiles.
--
-- Safe properties:
--   * inserts only missing profiles;
--   * preserves auth.users IDs and existing profile rows;
--   * does not create auth accounts, memberships, establishments, or roles;
--   * is idempotent and transactional.
--
-- Review the result before committing it in a production SQL session.

BEGIN;

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
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL;

DO $$
DECLARE
  v_missing integer;
BEGIN
  SELECT count(*) INTO v_missing
  FROM auth.users u
  LEFT JOIN public.profiles p ON p.id = u.id
  WHERE p.id IS NULL;

  IF v_missing <> 0 THEN
    RAISE EXCEPTION 'Profile recovery incomplete: % auth user(s) remain without a profile', v_missing;
  END IF;

  RAISE NOTICE 'Profile recovery completed: no auth user remains without a profile.';
END $$;

COMMIT;
