-- Migration: add establishment type and update creation function

--------------------------------------------------------------------------------
-- 1. Add type column to establishments
--------------------------------------------------------------------------------
ALTER TABLE public.establishments
ADD COLUMN IF NOT EXISTS type text NOT NULL DEFAULT 'salon'
CONSTRAINT valid_establishment_type CHECK (type IN ('barbershop', 'salon'));

COMMENT ON COLUMN public.establishments.type IS 'Tipo do estabelecimento: barbearia ou salão de beleza.';

--------------------------------------------------------------------------------
-- 2. Update atomic establishment creation function to include type
--------------------------------------------------------------------------------
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
SET search_path = public
AS $$
DECLARE
  v_establishment_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  IF p_type NOT IN ('barbershop', 'salon') THEN
    RAISE EXCEPTION 'Tipo de estabelecimento invalido';
  END IF;

  INSERT INTO public.establishments (owner_id, name, slug, type, document, phone, email, address)
  VALUES (auth.uid(), p_name, p_slug, p_type, p_document, p_phone, p_email, p_address)
  RETURNING id INTO v_establishment_id;

  INSERT INTO public.establishment_members (establishment_id, user_id, role)
  VALUES (v_establishment_id, auth.uid(), 'owner')
  ON CONFLICT (establishment_id, user_id) DO NOTHING;

  RETURN v_establishment_id;
END;
$$;
