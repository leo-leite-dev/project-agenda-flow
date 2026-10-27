-- Migration: catálogo de serviços do estabelecimento (etapa 5)
--
-- Cada estabelecimento possui seu próprio catálogo de serviços, isolado por
-- Row Level Security. O preço é armazenado em CENTAVOS inteiros para evitar
-- erros de ponto flutuante.
--
-- Segurança
-- ---------
--   * RLS habilitado na tabela;
--   * leitura para membros ativos do estabelecimento (policy SELECT);
--   * NENHUMA policy de INSERT/UPDATE/DELETE para a API: todas as escritas
--     ocorrem por RPCs SECURITY DEFINER que validam a identidade (auth.uid())
--     e a autorização (apenas o proprietário do estabelecimento, nesta etapa);
--   * EXECUTE das RPCs concedido apenas ao role authenticated;
--   * a tabela não recebe nenhum privilégio automático: o GRANT explícito é
--     apenas SELECT para authenticated (a tabela é criada depois que a
--     migration 20250127000004 revogou os default privileges do projeto).
--
-- Esta migration é idempotente e não destrutiva.

--------------------------------------------------------------------------------
-- 1. Tabela establishment_services
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.establishment_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  category text NOT NULL DEFAULT 'outros',
  duration_minutes integer NOT NULL,
  price_cents integer NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT service_name_not_empty CHECK (length(btrim(name)) > 0),
  CONSTRAINT service_name_max_length CHECK (length(btrim(name)) <= 120),
  CONSTRAINT valid_service_category CHECK (category IN ('cabelo', 'barba', 'estetica', 'unhas', 'outros')),
  CONSTRAINT service_duration_positive CHECK (duration_minutes > 0),
  CONSTRAINT service_duration_limit CHECK (duration_minutes <= 1440),
  CONSTRAINT service_price_non_negative CHECK (price_cents >= 0),
  CONSTRAINT service_description_limit CHECK (description IS NULL OR length(description) <= 500)
);

COMMENT ON TABLE public.establishment_services IS
  'Catálogo de serviços de cada estabelecimento. Preço em centavos inteiros.';

COMMENT ON COLUMN public.establishment_services.category IS
  'Categoria simples do serviço: cabelo, barba, estetica, unhas ou outros.';

COMMENT ON COLUMN public.establishment_services.price_cents IS
  'Preço em centavos inteiros (R$ 35,00 = 3500).';

--------------------------------------------------------------------------------
-- 2. Índices
--------------------------------------------------------------------------------
-- Nome único dentro de cada estabelecimento (sem sensibilidade a maiúsculas
-- e espaços), evitando cadastros duplicados no mesmo tenant.
CREATE UNIQUE INDEX IF NOT EXISTS uq_establishment_services_name
  ON public.establishment_services (establishment_id, lower(btrim(name)));

CREATE INDEX IF NOT EXISTS idx_establishment_services_establishment_id
  ON public.establishment_services (establishment_id);

CREATE INDEX IF NOT EXISTS idx_establishment_services_active
  ON public.establishment_services (establishment_id, is_active);

CREATE INDEX IF NOT EXISTS idx_establishment_services_category
  ON public.establishment_services (establishment_id, category);

--------------------------------------------------------------------------------
-- 3. RLS e permissões
--------------------------------------------------------------------------------
ALTER TABLE public.establishment_services ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "establishment_services_select" ON public.establishment_services;
CREATE POLICY "establishment_services_select"
  ON public.establishment_services
  FOR SELECT
  USING (public.is_establishment_member(establishment_id));

-- Não há policies de INSERT/UPDATE/DELETE: as escritas são feitas pelas RPCs
-- SECURITY DEFINER (create/update/set_active), que validam auth.uid() e o
-- papel de proprietário no banco.

-- Privilégio mínimo: apenas leitura para o role da API.
REVOKE ALL PRIVILEGES ON TABLE public.establishment_services FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.establishment_services FROM authenticated;
GRANT SELECT ON public.establishment_services TO authenticated;

--------------------------------------------------------------------------------
-- 4. Trigger de updated_at
--------------------------------------------------------------------------------
DROP TRIGGER IF EXISTS establishment_services_updated_at ON public.establishment_services;
CREATE TRIGGER establishment_services_updated_at
  BEFORE UPDATE ON public.establishment_services
  FOR EACH ROW EXECUTE FUNCTION agenda_flow_private.set_updated_at();

--------------------------------------------------------------------------------
-- 5. RPCs de escrita (apenas o proprietário do estabelecimento)
--------------------------------------------------------------------------------
-- Todas seguem o padrão das RPCs do projeto: SECURITY DEFINER, search_path
-- restrito, autenticação obrigatória (auth.uid()), verificação de
-- autorização no banco (is_establishment_owner) e validações explícitas.

CREATE OR REPLACE FUNCTION public.create_establishment_service(
  p_establishment_id uuid,
  p_name text,
  p_description text DEFAULT NULL,
  p_category text DEFAULT 'outros',
  p_duration_minutes integer DEFAULT NULL,
  p_price_cents integer DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_service_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  IF NOT public.is_establishment_owner(p_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode gerenciar servicos';
  END IF;

  IF p_name IS NULL OR length(btrim(p_name)) = 0 THEN
    RAISE EXCEPTION 'O nome do servico e obrigatorio';
  END IF;

  IF p_category IS NOT NULL AND p_category NOT IN ('cabelo', 'barba', 'estetica', 'unhas', 'outros') THEN
    RAISE EXCEPTION 'Categoria invalida';
  END IF;

  IF p_duration_minutes IS NULL OR p_duration_minutes <= 0 THEN
    RAISE EXCEPTION 'A duracao deve ser maior que zero';
  END IF;

  IF p_duration_minutes > 1440 THEN
    RAISE EXCEPTION 'A duracao nao pode exceder 1440 minutos';
  END IF;

  IF p_price_cents IS NULL OR p_price_cents < 0 THEN
    RAISE EXCEPTION 'O preco nao pode ser negativo';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.establishment_services s
    WHERE s.establishment_id = p_establishment_id
      AND lower(btrim(s.name)) = lower(btrim(p_name))
  ) THEN
    RAISE EXCEPTION 'Ja existe um servico com esse nome neste estabelecimento';
  END IF;

  INSERT INTO public.establishment_services (
    establishment_id, name, description, category, duration_minutes, price_cents, is_active
  )
  VALUES (
    p_establishment_id,
    btrim(p_name),
    NULLIF(btrim(COALESCE(p_description, '')), ''),
    COALESCE(p_category, 'outros'),
    p_duration_minutes,
    p_price_cents,
    COALESCE(p_is_active, true)
  )
  RETURNING id INTO v_service_id;

  RETURN v_service_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_establishment_service(
  p_service_id uuid,
  p_name text,
  p_description text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_duration_minutes integer DEFAULT NULL,
  p_price_cents integer DEFAULT NULL,
  p_is_active boolean DEFAULT NULL
)
RETURNS void
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

  IF p_service_id IS NULL THEN
    RAISE EXCEPTION 'Servico nao informado';
  END IF;

  SELECT establishment_id INTO v_establishment_id
  FROM public.establishment_services
  WHERE id = p_service_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'Servico nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode gerenciar servicos';
  END IF;

  IF p_name IS NULL OR length(btrim(p_name)) = 0 THEN
    RAISE EXCEPTION 'O nome do servico e obrigatorio';
  END IF;

  IF p_category IS NOT NULL AND p_category NOT IN ('cabelo', 'barba', 'estetica', 'unhas', 'outros') THEN
    RAISE EXCEPTION 'Categoria invalida';
  END IF;

  IF p_duration_minutes IS NOT NULL AND p_duration_minutes <= 0 THEN
    RAISE EXCEPTION 'A duracao deve ser maior que zero';
  END IF;

  IF p_duration_minutes IS NOT NULL AND p_duration_minutes > 1440 THEN
    RAISE EXCEPTION 'A duracao nao pode exceder 1440 minutos';
  END IF;

  IF p_price_cents IS NOT NULL AND p_price_cents < 0 THEN
    RAISE EXCEPTION 'O preco nao pode ser negativo';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.establishment_services s
    WHERE s.establishment_id = v_establishment_id
      AND lower(btrim(s.name)) = lower(btrim(p_name))
      AND s.id <> p_service_id
  ) THEN
    RAISE EXCEPTION 'Ja existe um servico com esse nome neste estabelecimento';
  END IF;

  UPDATE public.establishment_services
  SET
    name = btrim(p_name),
    description = NULLIF(btrim(COALESCE(p_description, '')), ''),
    category = COALESCE(p_category, category),
    duration_minutes = COALESCE(p_duration_minutes, duration_minutes),
    price_cents = COALESCE(p_price_cents, price_cents),
    is_active = COALESCE(p_is_active, is_active)
  WHERE id = p_service_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Servico nao encontrado';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_establishment_service_active(
  p_service_id uuid,
  p_is_active boolean
)
RETURNS void
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

  IF p_is_active IS NULL THEN
    RAISE EXCEPTION 'Informe o novo status do servico';
  END IF;

  IF p_service_id IS NULL THEN
    RAISE EXCEPTION 'Servico nao informado';
  END IF;

  SELECT establishment_id INTO v_establishment_id
  FROM public.establishment_services
  WHERE id = p_service_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'Servico nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode gerenciar servicos';
  END IF;

  UPDATE public.establishment_services
  SET is_active = p_is_active
  WHERE id = p_service_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Servico nao encontrado';
  END IF;
END;
$$;

--------------------------------------------------------------------------------
-- 6. Permissões de execução (matriz explícita do projeto)
--------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.create_establishment_service(uuid, text, text, text, integer, integer, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_establishment_service(uuid, text, text, text, integer, integer, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.create_establishment_service(uuid, text, text, text, integer, integer, boolean) FROM service_role;
GRANT EXECUTE ON FUNCTION public.create_establishment_service(uuid, text, text, text, integer, integer, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.update_establishment_service(uuid, text, text, text, integer, integer, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_establishment_service(uuid, text, text, text, integer, integer, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.update_establishment_service(uuid, text, text, text, integer, integer, boolean) FROM service_role;
GRANT EXECUTE ON FUNCTION public.update_establishment_service(uuid, text, text, text, integer, integer, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.set_establishment_service_active(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_establishment_service_active(uuid, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.set_establishment_service_active(uuid, boolean) FROM service_role;
GRANT EXECUTE ON FUNCTION public.set_establishment_service_active(uuid, boolean) TO authenticated;

--------------------------------------------------------------------------------
-- 7. Recarrega o cache de schema do PostgREST
--------------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
