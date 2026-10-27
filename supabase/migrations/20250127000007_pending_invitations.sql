-- Migration: convites pendentes do usuário autenticado (correção do onboarding)
--
-- O frontend precisa saber se a identidade autenticada possui um convite
-- pendente para decidir a tela inicial — sem isso, um funcionário convidado
-- que ainda não aceitou o convite é levado a "criar um estabelecimento",
-- o que é incorreto: ele foi convidado para uma empresa que já existe.
--
-- Esta RPC é de LEITURA e devolve apenas os convites endereçados ao e-mail
-- VERIFICADO do próprio chamador. Nenhum token (nem hash) é exposto: o token
-- bruto só existe no link enviado ao funcionário e não pode ser recuperado.
--
-- A aceitação continua exigindo o token do link e sendo validada pela RPC
-- accept_establishment_invitation (identidade, expiração e uso único).
--
-- Esta migration é idempotente e não destrutiva.

CREATE OR REPLACE FUNCTION public.get_my_pending_invitations()
RETURNS TABLE (
  establishment_id uuid,
  establishment_name text,
  role text,
  expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_email text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  -- Identidade confiável: o e-mail confirmado no Supabase Auth.
  SELECT u.email INTO v_email
  FROM auth.users u
  WHERE u.id = auth.uid()
    AND u.email_confirmed_at IS NOT NULL;

  IF v_email IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT i.establishment_id, e.name, i.role, i.expires_at
  FROM public.establishment_invitations i
  JOIN public.establishments e ON e.id = i.establishment_id
  WHERE i.email = lower(v_email)
    AND i.accepted_at IS NULL
    AND i.cancelled_at IS NULL
    AND i.expires_at > now()
  ORDER BY i.expires_at;
END;
$$;

COMMENT ON FUNCTION public.get_my_pending_invitations() IS
  'Convites pendentes endereçados ao e-mail confirmado do usuário autenticado (sem expor tokens).';

REVOKE ALL ON FUNCTION public.get_my_pending_invitations() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_pending_invitations() FROM anon;
REVOKE ALL ON FUNCTION public.get_my_pending_invitations() FROM service_role;
GRANT EXECUTE ON FUNCTION public.get_my_pending_invitations() TO authenticated;

-- Recarrega o cache de schema do PostgREST.
NOTIFY pgrst, 'reload schema';
