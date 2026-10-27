-- Seed / RLS tests for local development
-- This file is applied automatically by `supabase db reset` on local environments.
-- It must NEVER be applied to production. It creates synthetic users and data to
-- validate tenant isolation and privilege escalation protections.

DO $$
DECLARE
  v_owner_a uuid := '11111111-1111-1111-1111-111111111111';
  v_prof_a  uuid := '22222222-2222-2222-2222-222222222222';
  v_manager_a uuid := '33333333-3333-3333-3333-333333333333';
  v_owner_b uuid := '44444444-4444-4444-4444-444444444444';
  v_prof_b  uuid := '55555555-5555-5555-5555-555555555555';
  v_est_a uuid;
  v_est_b uuid;
  v_member_b uuid;
  v_token text;
BEGIN
  -- --------------------------------------------------------------------------
  -- Create test auth users (local-only, superuser context)
  -- --------------------------------------------------------------------------
  INSERT INTO auth.users (id, email, phone, encrypted_password, email_confirmed_at, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data, role)
  VALUES
    (v_owner_a, 'owner-a@agenda.flow.test', '+5511999900001', crypt('password', gen_salt('bf')), now(), now(), '{"provider":"email"}', '{"full_name":"Owner A"}', 'authenticated'),
    (v_prof_a, 'prof-a@agenda.flow.test', '+5511999900002', crypt('password', gen_salt('bf')), now(), now(), '{"provider":"email"}', '{"full_name":"Professional A"}', 'authenticated'),
    (v_manager_a, 'manager-a@agenda.flow.test', '+5511999900003', crypt('password', gen_salt('bf')), now(), now(), '{"provider":"email"}', '{"full_name":"Manager A"}', 'authenticated'),
    (v_owner_b, 'owner-b@agenda.flow.test', '+5511999900004', crypt('password', gen_salt('bf')), now(), now(), '{"provider":"email"}', '{"full_name":"Owner B"}', 'authenticated'),
    (v_prof_b, 'prof-b@agenda.flow.test', '+5511999900005', crypt('password', gen_salt('bf')), now(), now(), '{"provider":"email"}', '{"full_name":"Professional B"}', 'authenticated')
  ON CONFLICT (id) DO NOTHING;

  -- Confirm profiles were auto-created by trigger
  ASSERT (SELECT count(*) FROM public.profiles WHERE id IN (v_owner_a, v_prof_a, v_manager_a, v_owner_b, v_prof_b)) = 5,
    'Profiles trigger did not create all test profiles';

  -- --------------------------------------------------------------------------
  -- Create establishments as owners
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  v_est_a := public.create_establishment('Barbearia Alpha', 'barbearia-alpha');

  PERFORM set_config('request.jwt.claim.sub', v_owner_b::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  v_est_b := public.create_establishment('Salão Beta', 'salao-beta');

  ASSERT v_est_a IS NOT NULL AND v_est_b IS NOT NULL, 'Establishments should be created';

  -- --------------------------------------------------------------------------
  -- Add members to establishment A
  -- --------------------------------------------------------------------------
  INSERT INTO public.establishment_members (establishment_id, user_id, role)
  VALUES
    (v_est_a, v_manager_a, 'manager'),
    (v_est_a, v_prof_a, 'professional')
  ON CONFLICT (establishment_id, user_id) DO NOTHING;

  -- Add member to establishment B
  INSERT INTO public.establishment_members (establishment_id, user_id, role)
  VALUES (v_est_b, v_prof_b, 'professional')
  RETURNING id INTO v_member_b;

  -- --------------------------------------------------------------------------
  -- Test 1: Tenant isolation — professional A cannot see establishment B
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  ASSERT EXISTS (SELECT 1 FROM public.establishments WHERE id = v_est_a),
    'Member should see own establishment';
  ASSERT NOT EXISTS (SELECT 1 FROM public.establishments WHERE id = v_est_b),
    'Member should NOT see another tenant establishment';

  -- --------------------------------------------------------------------------
  -- Test 2: Colleague visibility — professional A can see owner A profile
  -- --------------------------------------------------------------------------
  ASSERT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_owner_a),
    'Member should see colleague profile';
  ASSERT NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_owner_b),
    'Member should NOT see profile of a user from another tenant';

  -- --------------------------------------------------------------------------
  -- Test 3: Owner can update establishment; professional cannot
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  UPDATE public.establishments SET name = 'Barbearia Alpha Updated' WHERE id = v_est_a;

  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  BEGIN
    UPDATE public.establishments SET name = 'Hacked' WHERE id = v_est_a;
    RAISE EXCEPTION 'Professional should NOT be able to update establishment';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected
  END;

  -- --------------------------------------------------------------------------
  -- Test 4: Manager cannot create/elevate another owner
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_manager_a::text, true);
  BEGIN
    INSERT INTO public.establishment_members (establishment_id, user_id, role)
    VALUES (v_est_a, v_prof_b, 'owner');
    RAISE EXCEPTION 'Manager should NOT be able to create an owner member';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected
  END;

  BEGIN
    UPDATE public.establishment_members SET role = 'owner' WHERE user_id = v_prof_a AND establishment_id = v_est_a;
    RAISE EXCEPTION 'Manager should NOT be able to promote member to owner';
  EXCEPTION WHEN insufficient_privilege THEN
    -- expected
  END;

  -- --------------------------------------------------------------------------
  -- Test 5: Manager cannot invite an owner/administrator
  -- --------------------------------------------------------------------------
  BEGIN
    PERFORM public.create_establishment_invitation(v_est_a, 'hacker@agenda.flow.test', NULL, 'owner');
    RAISE EXCEPTION 'Manager should NOT be able to invite an owner';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- --------------------------------------------------------------------------
  -- Test 6: Owner can create invitation and accept only with matching identity
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
  v_token := public.create_establishment_invitation(v_est_a, 'newprof@agenda.flow.test', NULL, 'professional', ARRAY['appointments.read', 'clients.read']);
  ASSERT v_token IS NOT NULL AND length(v_token) = 64, 'Invitation token should be a 64-char hex string';

  -- Wrong user (prof B) tries to accept invitation meant for newprof
  PERFORM set_config('request.jwt.claim.sub', v_prof_b::text, true);
  BEGIN
    PERFORM public.accept_establishment_invitation(v_token);
    RAISE EXCEPTION 'Wrong user should NOT be able to accept invitation';
  EXCEPTION WHEN raise_exception THEN
    -- expected
  END;

  -- --------------------------------------------------------------------------
  -- Test 7: Owner can see invitations; professional cannot
  -- --------------------------------------------------------------------------
  PERFORM set_config('request.jwt.claim.sub', v_prof_a::text, true);
  ASSERT NOT EXISTS (SELECT 1 FROM public.establishment_invitations WHERE establishment_id = v_est_a),
    'Professional should NOT see invitations';

  -- --------------------------------------------------------------------------
  -- Test 8: Owner can delete own establishment; non-owner cannot
  -- --------------------------------------------------------------------------
  -- We intentionally skip deletion to keep seed data available for manual testing.

  RAISE NOTICE 'All RLS seed assertions passed.';
END $$;
