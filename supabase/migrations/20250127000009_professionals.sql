-- Migration: gestão de profissionais de atendimento (etapa 7)
--
-- Cada membro de uma equipe pode ser habilitado como PROFISSIONAL DE ATEN-
-- DIMENTO e receber a associação com os serviços que executa. São conceitos
-- independentes:
--
--   • cargo (public.establishment_members.role): permissões administrativas;
--   • habilitação (public.establishment_professionals): elegibilidade para
--     receber atendimentos e ter serviços associados.
--
-- Qualquer membro (owner, manager, professional ou receptionist) pode ser
-- habilitado; o cargo determina as permissões administrativas, e a habilitação
-- determina se a pessoa executa serviços. O mesmo usuário continua podendo
-- participar de vários estabelecimentos, com configurações profissionais
-- independentes em cada empresa.
--
-- Segurança
-- ---------
--   * RLS habilitado nas duas tabelas novas;
--   * leitura para membros ativos do estabelecimento (policy SELECT);
--   * NENHUMA policy de INSERT/UPDATE/DELETE para a API: as escritas ocorrem
--     por RPCs SECURITY DEFINER que validam a identidade (auth.uid()) e a
--     autorização (apenas o proprietário do estabelecimento, nesta etapa);
--   * integridade entre tenants garantida também por chaves estrangeiras
--     COMPOSTAS: um serviço não pode ser associado a um profissional de
--     outro estabelecimento, mesmo contornando a aplicação;
--   * EXECUTE das RPCs concedido apenas ao role authenticated;
--   * a tabela não recebe nenhum privilégio automático: o GRANT explícito é
--     apenas SELECT para authenticated (a tabela é criada depois que a
--     migration 20250127000004 revogou os default privileges do projeto).
--
-- Esta migration é idempotente: pode ser reaplicada sem duplicar objetos.
-- NELHUM registro é excluído nem modificado: apenas objetos novo são criados.

--------------------------------------------------------------------------------
-- 1. Unicidade de referência para as FKs compostas
--------------------------------------------------------------------------------
-- As FKs compostas (id, establishment_id) exigem unicidade nas tabelas de
-- origem. A PK de establishment_members/establishment_services é `id`; os
-- índices abaixo são adicionais e não alteram nenhum registro existente.
CREATE UNIQUE INDEX IF NOT EXISTS uq_establishment_members_id_establishment
  ON public.establishment_members (id, establishment_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_establishment_services_id_establishment
  ON public.establishment_services (id, establishment_id);

--------------------------------------------------------------------------------
-- 2. Tabela establishment_professionals
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.establishment_professionals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.establishment_members(id) ON DELETE CASCADE,
  accepts_appointments boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Um membro é habilitado (ou não) exatamente uma vez por estabelecimento —
  -- o membro pertence a um único estabelecimento (UNIQUE establishment_id,
  -- user_id), portanto a unicidade por membro também protege o tenant.
  UNIQUE (member_id),

  -- Referência para as FKs compostas da tabela de associações.
  UNIQUE (id, establishment_id)
);

COMMENT ON TABLE public.establishment_professionals IS
  'Habilitação de um membro da equipe como profissional de atendimento, por estabelecimento.';

COMMENT ON COLUMN public.establishment_professionals.accepts_appointments IS
  'Habilitação para receber atendimentos. Desabilitar NÃO desativa o vínculo de funcionário, o cargo nem as permissões.';

CREATE INDEX IF NOT EXISTS idx_establishment_professionals_establishment_id
  ON public.establishment_professionals (establishment_id);

-- Integridade referencial entre tenants: o membro habilitado deve pertencer
-- ao MESMO estabelecimento da linha (FK composta, mesmo contornando a API).
ALTER TABLE public.establishment_professionals
  DROP CONSTRAINT IF EXISTS establishment_professionals_member_establishment_fkey;

ALTER TABLE public.establishment_professionals
  ADD CONSTRAINT establishment_professionals_member_establishment_fkey
    FOREIGN KEY (member_id, establishment_id)
    REFERENCES public.establishment_members (id, establishment_id)
    ON DELETE CASCADE;

--------------------------------------------------------------------------------
-- 3. Tabela establishment_professional_services (muitos-para-muitos)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.establishment_professional_services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE CASCADE,
  professional_id uuid NOT NULL REFERENCES public.establishment_professionals(id) ON DELETE CASCADE,
  service_id uuid NOT NULL REFERENCES public.establishment_services(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),

  -- Cada associação profissional↔serviço é única (sem duplicidade).
  UNIQUE (professional_id, service_id),

  -- Referências para as FKs compostas das tabelas de origem.
  UNIQUE (id, establishment_id)
);

COMMENT ON TABLE public.establishment_professional_services IS
  'Associação de serviços a um profissional de atendimento do estabelecimento.';

CREATE INDEX IF NOT EXISTS idx_establishment_professional_services_establishment_id
  ON public.establishment_professional_services (establishment_id);

CREATE INDEX IF NOT EXISTS idx_establishment_professional_services_service_id
  ON public.establishment_professional_services (service_id);

CREATE INDEX IF NOT EXISTS idx_establishment_professional_services_professional_id
  ON public.establishment_professional_services (professional_id);

-- Integridade entre tenants no nível do BANCO (não apenas no frontend/RPC):
--   * o profissional deve pertencer ao MESMO estabelecimento da linha;
--   * o serviço deve pertencer ao MESMO estabelecimento da linha.
ALTER TABLE public.establishment_professional_services
  DROP CONSTRAINT IF EXISTS establishment_professional_services_professional_establishment_fkey;

ALTER TABLE public.establishment_professional_services
  ADD CONSTRAINT establishment_professional_services_professional_establishment_fkey
    FOREIGN KEY (professional_id, establishment_id)
    REFERENCES public.establishment_professionals (id, establishment_id)
    ON DELETE CASCADE;

ALTER TABLE public.establishment_professional_services
  DROP CONSTRAINT IF EXISTS establishment_professional_services_service_establishment_fkey;

ALTER TABLE public.establishment_professional_services
  ADD CONSTRAINT establishment_professional_services_service_establishment_fkey
    FOREIGN KEY (service_id, establishment_id)
    REFERENCES public.establishment_services (id, establishment_id)
    ON DELETE CASCADE;

--------------------------------------------------------------------------------
-- 4. RLS e permissões
--------------------------------------------------------------------------------
ALTER TABLE public.establishment_professionals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "establishment_professionals_select" ON public.establishment_professionals;
CREATE POLICY "establishment_professionals_select"
  ON public.establishment_professionals
  FOR SELECT
  USING (public.is_establishment_member(establishment_id));

-- Não há policies de INSERT/UPDATE/DELETE: as escritas são feitas pelas RPCs
-- SECURITY DEFINER, que validam auth.uid() e o papel de proprietário no banco.

ALTER TABLE public.establishment_professional_services ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "establishment_professional_services_select" ON public.establishment_professional_services;
CREATE POLICY "establishment_professional_services_select"
  ON public.establishment_professional_services
  FOR SELECT
  USING (public.is_establishment_member(establishment_id));

-- Privilégio mínimo: apenas leitura para o role da API.
REVOKE ALL PRIVILEGES ON TABLE public.establishment_professionals FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.establishment_professionals FROM authenticated;
GRANT SELECT ON public.establishment_professionals TO authenticated;

REVOKE ALL PRIVILEGES ON TABLE public.establishment_professional_services FROM anon;
REVOKE ALL PRIVILEGES ON TABLE public.establishment_professional_services FROM authenticated;
GRANT SELECT ON public.establishment_professional_services TO authenticated;

--------------------------------------------------------------------------------
-- 5. Trigger de updated_at
--------------------------------------------------------------------------------
DROP TRIGGER IF EXISTS establishment_professionals_updated_at ON public.establishment_professionals;
CREATE TRIGGER establishment_professionals_updated_at
  BEFORE UPDATE ON public.establishment_professionals
  FOR EACH ROW EXECUTE FUNCTION agenda_flow_private.set_updated_at();

-- (establishment_professional_services não tem updated_at: as associações são
-- imutáveis — recriar/remove, nunca edita.)

--------------------------------------------------------------------------------
-- 6. RPCs de escrita (apenas o proprietário do estabelecimento)
--------------------------------------------------------------------------------
-- Todas seguem o padrão das RPCs do projeto: SECURITY DEFINER, search_path
-- restrito, autenticação obrigatória (auth.uid()), verificação de
-- autorização no banco e validações explícitas de entrada.

CREATE OR REPLACE FUNCTION public.set_establishment_professional(
  p_member_id uuid,
  p_accepts_appointments boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_establishment_id uuid;
  v_member_is_active boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  IF p_accepts_appointments IS NULL THEN
    RAISE EXCEPTION 'Informe a habilitação para atendimentos';
  END IF;

  IF p_member_id IS NULL THEN
    RAISE EXCEPTION 'Membro nao informado';
  END IF;

  SELECT em.establishment_id, em.is_active
    INTO v_establishment_id, v_member_is_active
  FROM public.establishment_members em
  WHERE em.id = p_member_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'Membro nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode gerenciar os profissionais';
  END IF;

  -- Vínculos desativados não podem ser usados para receber atendimentos:
  -- a habilitação (crescente ou de pausa) é recusada nesse estado.
  IF NOT v_member_is_active THEN
    RAISE EXCEPTION 'Vinculo desativado nao pode receber habilitacao de profissional';
  END IF;

  INSERT INTO public.establishment_professionals (establishment_id, member_id, accepts_appointments)
  VALUES (v_establishment_id, p_member_id, p_accepts_appointments)
  ON CONFLICT (member_id) DO UPDATE
    SET accepts_appointments = EXCLUDED.accepts_appointments;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_establishment_professional_service(
  p_professional_id uuid,
  p_service_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_establishment_id uuid;
  v_member_is_active boolean;
  v_service_establishment_id uuid;
  v_service_is_active boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  IF p_professional_id IS NULL THEN
    RAISE EXCEPTION 'Profissional nao informado';
  END IF;

  IF p_service_id IS NULL THEN
    RAISE EXCEPTION 'Servico nao informado';
  END IF;

  SELECT ep.establishment_id, em.is_active
    INTO v_establishment_id, v_member_is_active
  FROM public.establishment_professionals ep
  JOIN public.establishment_members em ON em.id = ep.member_id
  WHERE ep.id = p_professional_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'Profissional nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode gerenciar os servicos dos profissionais';
  END IF;

  -- Vínculo desativado: associações antigas são preservadas, mas NENHUMA
  -- nova associação recebe esse membro (ele deixa de ser elegível).
  IF NOT v_member_is_active THEN
    RAISE EXCEPTION 'Vinculo desativado nao pode receber novos servicos';
  END IF;

  SELECT s.establishment_id, s.is_active
    INTO v_service_establishment_id, v_service_is_active
  FROM public.establishment_services s
  WHERE s.id = p_service_id;

  IF v_service_establishment_id IS NULL THEN
    RAISE EXCEPTION 'Servico nao encontrado';
  END IF;

  -- O serviço deve pertencer AO MESMO estabelecimento do profissional
  -- (a FK composta também garante isso no nível do banco).
  IF v_service_establishment_id <> v_establishment_id THEN
    RAISE EXCEPTION 'Servico nao encontrado neste estabelecimento';
  END IF;

  -- Serviços inativos não recebem NOVAS associações (associações que já
  -- existam são preservadas e continuam visíveis, mas inutilizadas).
  IF NOT v_service_is_active THEN
    RAISE EXCEPTION 'Servico inativo nao pode ser associado';
  END IF;

  INSERT INTO public.establishment_professional_services (establishment_id, professional_id, service_id)
  VALUES (v_establishment_id, p_professional_id, p_service_id)
  ON CONFLICT (professional_id, service_id)
  DO NOTHING;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Associacao ja existe para este profissional e servico';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_establishment_professional_service(
  p_professional_id uuid,
  p_service_id uuid
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

  IF p_professional_id IS NULL THEN
    RAISE EXCEPTION 'Profissional nao informado';
  END IF;

  IF p_service_id IS NULL THEN
    RAISE EXCEPTION 'Servico nao informado';
  END IF;

  SELECT ep.establishment_id
    INTO v_establishment_id
  FROM public.establishment_professionals ep
  WHERE ep.id = p_professional_id;

  IF v_establishment_id IS NULL THEN
    RAISE EXCEPTION 'Profissional nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario pode gerenciar os servicos dos profissionais';
  END IF;

  DELETE
  FROM public.establishment_professional_services
  WHERE professional_id = p_professional_id
    AND service_id = p_service_id
    AND establishment_id = v_establishment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Associacao nao encontrada';
  END IF;
END;
$$;

-- As permissões administrativas do membro NUNCA são alteradas por estas RPCs:
-- cargos e permissões continuam sendo gerenciados exclusivamente pelas RPCs
-- da etapa 6 (update_establishment_member_role / set_establishment_member_...),
-- de modo que um profissional não consegue alterar as próprias permissões
-- administrativas através do fluxo de profissionais.

--------------------------------------------------------------------------------
-- 7. Permissões de execução (matriz explícita do projeto)
--------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.set_establishment_professional(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_establishment_professional(uuid, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.set_establishment_professional(uuid, boolean) FROM service_role;
GRANT EXECUTE ON FUNCTION public.set_establishment_professional(uuid, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.add_establishment_professional_service(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_establishment_professional_service(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.add_establishment_professional_service(uuid, uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.add_establishment_professional_service(uuid, uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.remove_establishment_professional_service(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_establishment_professional_service(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.remove_establishment_professional_service(uuid, uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.remove_establishment_professional_service(uuid, uuid) TO authenticated;

--------------------------------------------------------------------------------
-- 8. Recarrega o cache de schema do PostgREST
--------------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';
