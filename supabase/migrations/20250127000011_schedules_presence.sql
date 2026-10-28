-- Migration: escalas de trabalho, presença (check-in/check-out) e exceções (etapa 8)
--
-- Conceitos separados (a escala NÃO prova presença; presença NÃO é atendimento):
--   • public.establishment_schedules      — escala semanal esperada por membro;
--   • public.attendance_records           — entrada/saída efetivamente registradas;
--   • public.attendance_exceptions        — ausências, folgas e ajustes excepcionais;
--   • public.attendance_corrections       — auditoria das correções administrativas.
--
-- Regras de negócio
-- -----------------
--   * o horário oficial vem do SERVIDOR (now()); nada é aceito do navegador;
--   * cada estabelecimento possui um fuso horário IANA próprio ('America/Sao_Paulo'
--     como compatível com os dados existentes, alterável por operação futura);
--   * um registro por membro por dia (chaves compostas impedem duplicidade e
--     cruzar tenants, mesmo contornando a API);
--   * no máximo UMA entrada em aberto por membro, garantida pelo PostgreSQL com
--     índice único parcial (não depende de checagem prévia da RPC). Entradas
--     antigas esquecidas não são apagadas: o proprietário corrige a saída pela
--     operação administrativa auditável;
--   * histórico de presença e de ausências é PRESERVADO: excluir vínculo (ou o
--     estabelecimento) não apaga registros; exige correção/expurgo explícito;
--   * funcionário só registra ENTRADA/SAÍDA para a própria identidade (RPC usa
--     auth.uid()); owner-only: escalas, exceções e correções;
--   * vínculo desativado não recebe novos registros; históricos são preservados;
--   * nenhuma rotina em segundo plano: o status atual é calculado pela
--     aplicação a partir da escala, dos registros e do relógio do servidor;
--   * um check-in é um REGISTRO do usuário, não prova de localização física.
--
-- Esta migration é idempotente e não destrutiva; não toca em migrations anteriores.

--------------------------------------------------------------------------------
-- 1. Fuso horário do estabelecimento
--------------------------------------------------------------------------------
ALTER TABLE public.establishments
  ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'America/Sao_Paulo';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'establishments_timezone_format'
      AND conrelid = 'public.establishments'::regclass
  ) THEN
    ALTER TABLE public.establishments
      ADD CONSTRAINT establishments_timezone_format
      CHECK (timezone ~ '^[A-Za-z][A-Za-z0-9_+\-]*/[A-Za-z0-9_+\-]+$');
  END IF;
END $$;

COMMENT ON COLUMN public.establishments.timezone IS
  'Fuso horário IANA usado para datas de expediente, presença e ausências.';

--------------------------------------------------------------------------------
-- 2. establishment_schedules: escala semanal esperada (por membro e dia)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.establishment_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE CASCADE,
  member_id uuid NOT NULL REFERENCES public.establishment_members(id) ON DELETE CASCADE,
  weekday smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  is_day_off boolean NOT NULL DEFAULT false,
  start_time time,
  end_time time,
  break_start time,
  break_end time,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Um dia por semana por membro (reaplicações substituem tudo).
  UNIQUE (member_id, weekday),

  -- Turnos noturnos são permitidos: NÃO exigimos start_time < end_time.
  CONSTRAINT schedule_time_window CHECK (
    is_day_off = true OR (start_time IS NOT NULL AND end_time IS NOT NULL)
  ),
  CONSTRAINT schedule_break_pair CHECK (
    (break_start IS NULL AND break_end IS NULL)
    OR (break_start IS NOT NULL AND break_end IS NOT NULL)
  ),
  -- Intervalos: o turno pode cruzar a meia-noite (22:00→02:00), portanto o
  -- intervalo também pode (23:00→01:00). O que se exige é um intervalo real:
  -- início diferente do fim. A duração circular é calculada pela aplicação
  -- (isWithinWindow), que já trata janelas que atravessam a meia-noite.
  CONSTRAINT schedule_break_order CHECK (
    break_start IS NULL OR break_end IS NULL OR break_start <> break_end
  )
);

-- Integridade entre tenants: a escala deve apontar para vínculo do MESMO tenant.
ALTER TABLE public.establishment_schedules
  DROP CONSTRAINT IF EXISTS establishment_schedules_member_establishment_fkey;

ALTER TABLE public.establishment_schedules
  ADD CONSTRAINT establishment_schedules_member_establishment_fkey
    FOREIGN KEY (member_id, establishment_id)
    REFERENCES public.establishment_members (id, establishment_id)
    ON DELETE CASCADE;

-- Reaplicação: garante a versão atual da regra de intervalo (aceita virada de
-- meia-noite) mesmo quando a tabela já existia com a regra antiga (início < fim).
ALTER TABLE public.establishment_schedules
  DROP CONSTRAINT IF EXISTS schedule_break_order;

ALTER TABLE public.establishment_schedules
  ADD CONSTRAINT schedule_break_order CHECK (
    break_start IS NULL OR break_end IS NULL OR break_start <> break_end
  );

COMMENT ON TABLE public.establishment_schedules IS
  'Escala semanal esperada por membro (expediente previsto; não registra presença).';

CREATE INDEX IF NOT EXISTS idx_establishment_schedules_establishment_id
  ON public.establishment_schedules (establishment_id);
CREATE INDEX IF NOT EXISTS idx_establishment_schedules_member_id
  ON public.establishment_schedules (member_id);

--------------------------------------------------------------------------------
-- 3. attendance_records: entrada e saída registradas (horário do servidor)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE RESTRICT,
  member_id uuid NOT NULL REFERENCES public.establishment_members(id) ON DELETE RESTRICT,
  work_date date NOT NULL,
  check_in_at timestamptz,
  check_out_at timestamptz,
  check_in_source text,
  check_out_source text,
  corrected_by uuid REFERENCES public.profiles(id) ON DELETE RESTRICT,
  corrected_at timestamptz,
  correction_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  -- Um registro por membro por dia (turno completo, sem check-ins duplicados).
  UNIQUE (member_id, work_date),

  -- Alvo das FKs compostas das correções (integridade de histórico).
  UNIQUE (id, establishment_id),

  CONSTRAINT attendance_source_valid CHECK (
    (check_in_source IS NULL OR check_in_source IN ('self', 'owner'))
    AND (check_out_source IS NULL OR check_out_source IN ('self', 'owner'))
  ),
  CONSTRAINT attendance_checkout_requires_checkin CHECK (
    check_out_at IS NULL OR check_in_at IS NOT NULL
  ),
  CONSTRAINT attendance_correction_metadata CHECK (
    (corrected_at IS NULL) = (corrected_by IS NULL)
  )
);

-- Integridade entre tenants: o registro deve pertencer ao MESMO tenant do vínculo.
ALTER TABLE public.attendance_records
  DROP CONSTRAINT IF EXISTS attendance_records_member_establishment_fkey;

-- HISTÓRICO PRESERVADO: desativar/desligar um vínculo é uma operação de
-- administração; apagar o vínculo NÃO pode apagar presença. A exclusão fica
-- bloqueada enquanto existir histórico (o desligamento comum deve usar
-- set_establishment_member_active, que preserva as linhas).
ALTER TABLE public.attendance_records
  ADD CONSTRAINT attendance_records_member_establishment_fkey
    FOREIGN KEY (member_id, establishment_id)
    REFERENCES public.establishment_members (id, establishment_id)
    ON DELETE RESTRICT;

ALTER TABLE public.attendance_records
  DROP CONSTRAINT IF EXISTS attendance_records_establishment_id_fkey;

ALTER TABLE public.attendance_records
  ADD CONSTRAINT attendance_records_establishment_id_fkey
    FOREIGN KEY (establishment_id)
    REFERENCES public.establishments (id)
    ON DELETE RESTRICT;

-- UMA entrada aberta por membro, garantida pelo PostgreSQL. Uma checagem
-- prévia dentro da RPC pode sofrer corrida; o índice único parcial é a
-- garantia definitiva, inclusive quando os registros abertos atravessam a
-- meia-noite (work_date diferentes, mesmo membro).
DO $$
DECLARE
  v_duplicate_members integer;
BEGIN
  SELECT count(*) INTO v_duplicate_members
  FROM (
    SELECT member_id
    FROM public.attendance_records
    WHERE check_out_at IS NULL
    GROUP BY member_id
    HAVING count(*) > 1
  ) AS duplicates;

  IF v_duplicate_members > 0 THEN
    RAISE EXCEPTION
      'Existem % membro(s) com mais de um registro de presenca aberto. Corrija a saida desses registros pela operacao administrativa auditavel (correct_attendance_record) antes de aplicar esta migration.',
      v_duplicate_members;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS attendance_records_one_open_per_member
  ON public.attendance_records (member_id)
  WHERE check_out_at IS NULL;

COMMENT ON TABLE public.attendance_records IS
  'Registro de entrada e saída por membro/dia, sempre com horário do servidor.';

CREATE INDEX IF NOT EXISTS idx_attendance_records_establishment_date
  ON public.attendance_records (establishment_id, work_date DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_records_member_date
  ON public.attendance_records (member_id, work_date DESC);

--------------------------------------------------------------------------------
-- 4. attendance_exceptions: ausências, folgas e ajustes excepcionais
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance_exceptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE RESTRICT,
  member_id uuid NOT NULL REFERENCES public.establishment_members(id) ON DELETE RESTRICT,
  start_date date NOT NULL,
  end_date date NOT NULL,
  exception_type text NOT NULL CHECK (
    exception_type IN (
      'absence', 'justified_delay', 'early_leave',
      'exceptional_day_off', 'vacation', 'schedule_adjustment'
    )
  ),
  reason text,
  recorded_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT attendance_exception_dates CHECK (end_date >= start_date)
);

-- Integridade entre tenants: exceção aponta para vínculo do mesmo tenant.
ALTER TABLE public.attendance_exceptions
  DROP CONSTRAINT IF EXISTS attendance_exceptions_member_establishment_fkey;

-- HISTÓRICO PRESERVADO: ausências/férias não são apagadas por exclusão de vínculo.
ALTER TABLE public.attendance_exceptions
  ADD CONSTRAINT attendance_exceptions_member_establishment_fkey
    FOREIGN KEY (member_id, establishment_id)
    REFERENCES public.establishment_members (id, establishment_id)
    ON DELETE RESTRICT;

ALTER TABLE public.attendance_exceptions
  DROP CONSTRAINT IF EXISTS attendance_exceptions_establishment_id_fkey;

ALTER TABLE public.attendance_exceptions
  ADD CONSTRAINT attendance_exceptions_establishment_id_fkey
    FOREIGN KEY (establishment_id)
    REFERENCES public.establishments (id)
    ON DELETE RESTRICT;

COMMENT ON TABLE public.attendance_exceptions IS
  'Ocorrências especiais registradas pelo proprietário; não substituem a escala habitual.';

CREATE INDEX IF NOT EXISTS idx_attendance_exceptions_establishment_id
  ON public.attendance_exceptions (establishment_id);
CREATE INDEX IF NOT EXISTS idx_attendance_exceptions_member_dates
  ON public.attendance_exceptions (member_id, start_date, end_date);

--------------------------------------------------------------------------------
-- 5. attendance_corrections: trilha de auditoria das correções administrativas
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  establishment_id uuid NOT NULL REFERENCES public.establishments(id) ON DELETE RESTRICT,
  attendance_id uuid NOT NULL,
  previous_check_in_at timestamptz,
  previous_check_out_at timestamptz,
  check_in_at timestamptz,
  check_out_at timestamptz,
  reason text NOT NULL,
  corrected_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),

  -- FK COMPOSTA: a correção pertence ao MESMO tenant do registro corrigido.
  CONSTRAINT attendance_corrections_attendance_establishment_fkey
    FOREIGN KEY (attendance_id, establishment_id)
    REFERENCES public.attendance_records (id, establishment_id)
    -- HISTÓRICO PRESERVADO: o registro não é apagado enquanto existir
    -- correção auditável (exclusões definitivas são operações próprias).
    ON DELETE RESTRICT
);

-- Reaplicação: auditoria também sobrevive a tentativas de exclusão do tenant.
ALTER TABLE public.attendance_corrections
  DROP CONSTRAINT IF EXISTS attendance_corrections_establishment_id_fkey;

ALTER TABLE public.attendance_corrections
  ADD CONSTRAINT attendance_corrections_establishment_id_fkey
    FOREIGN KEY (establishment_id)
    REFERENCES public.establishments (id)
    ON DELETE RESTRICT;

COMMENT ON TABLE public.attendance_corrections IS
  'Histórico imutável das correções de presença feitas pelo proprietário.';

CREATE INDEX IF NOT EXISTS idx_attendance_corrections_attendance_id
  ON public.attendance_corrections (attendance_id);
CREATE INDEX IF NOT EXISTS idx_attendance_corrections_establishment_id
  ON public.attendance_corrections (establishment_id);

--------------------------------------------------------------------------------
-- 6. Triggers de updated_at
--------------------------------------------------------------------------------
DROP TRIGGER IF EXISTS establishment_schedules_updated_at ON public.establishment_schedules;
CREATE TRIGGER establishment_schedules_updated_at
  BEFORE UPDATE ON public.establishment_schedules
  FOR EACH ROW EXECUTE FUNCTION agenda_flow_private.set_updated_at();

DROP TRIGGER IF EXISTS attendance_records_updated_at ON public.attendance_records;
CREATE TRIGGER attendance_records_updated_at
  BEFORE UPDATE ON public.attendance_records
  FOR EACH ROW EXECUTE FUNCTION agenda_flow_private.set_updated_at();

--------------------------------------------------------------------------------
-- 7. RLS e privilégio mínimo (leitura self-or-owner; escritas apenas por RPC)
--------------------------------------------------------------------------------
-- PRIVACIDADE DA PRESENÇA: um funcionário consulta SOMENTE os próprios
-- registros/escalas/exceções; o proprietário consulta a equipe inteira do
-- tenant. Colegas não leem presença de colegas.
ALTER TABLE public.establishment_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_exceptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_corrections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "establishment_schedules_select" ON public.establishment_schedules;
CREATE POLICY "establishment_schedules_select"
  ON public.establishment_schedules
  FOR SELECT
  USING (
    public.is_establishment_owner(establishment_id)
    OR EXISTS (
      SELECT 1 FROM public.establishment_members m
      WHERE m.id = establishment_schedules.member_id AND m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "attendance_records_select" ON public.attendance_records;
CREATE POLICY "attendance_records_select"
  ON public.attendance_records
  FOR SELECT
  USING (
    public.is_establishment_owner(establishment_id)
    OR EXISTS (
      SELECT 1 FROM public.establishment_members m
      WHERE m.id = attendance_records.member_id AND m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "attendance_exceptions_select" ON public.attendance_exceptions;
CREATE POLICY "attendance_exceptions_select"
  ON public.attendance_exceptions
  FOR SELECT
  USING (
    public.is_establishment_owner(establishment_id)
    OR EXISTS (
      SELECT 1 FROM public.establishment_members m
      WHERE m.id = attendance_exceptions.member_id AND m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "attendance_corrections_select" ON public.attendance_corrections;
CREATE POLICY "attendance_corrections_select"
  ON public.attendance_corrections
  FOR SELECT
  USING (
    public.is_establishment_owner(establishment_id)
    OR EXISTS (
      SELECT 1
      FROM public.attendance_records r
      JOIN public.establishment_members m ON m.id = r.member_id
      WHERE r.id = attendance_corrections.attendance_id AND m.user_id = auth.uid()
    )
  );

REVOKE ALL PRIVILEGES ON TABLE public.establishment_schedules FROM anon, authenticated, PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.attendance_records FROM anon, authenticated, PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.attendance_exceptions FROM anon, authenticated, PUBLIC;
REVOKE ALL PRIVILEGES ON TABLE public.attendance_corrections FROM anon, authenticated, PUBLIC;

GRANT SELECT ON public.establishment_schedules TO authenticated;
GRANT SELECT ON public.attendance_records TO authenticated;
GRANT SELECT ON public.attendance_exceptions TO authenticated;
GRANT SELECT ON public.attendance_corrections TO authenticated;

--------------------------------------------------------------------------------
-- 8. RPCs (SECURITY DEFINER, search_path vazio, auth.uid() validado)
--------------------------------------------------------------------------------

-- Relógio oficial do estabelecimento (hora do SERVIDOR no fuso do tenant).
CREATE OR REPLACE FUNCTION public.get_establishment_clock(p_establishment_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_timezone text;
  v_local timestamp; -- now() AT TIME ZONE devolve timestamp SEM fuso
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  IF NOT public.is_establishment_member(p_establishment_id) THEN
    RAISE EXCEPTION 'Sem permissao para consultar este estabelecimento';
  END IF;

  SELECT timezone INTO v_timezone
  FROM public.establishments WHERE id = p_establishment_id;

  IF v_timezone IS NULL OR v_timezone !~ '^[A-Za-z][A-Za-z0-9_+\-]*/[A-Za-z0-9_+\-]+$' THEN
    RAISE EXCEPTION 'Fuso horario invalido do estabelecimento';
  END IF;

  BEGIN
    v_local := (now() AT TIME ZONE v_timezone);
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'Fuso horario invalido do estabelecimento (%)', v_timezone;
  END;

  RETURN jsonb_build_object(
    'now_at', now(),
    'timezone', v_timezone,
    'local_date', to_char(v_local, 'YYYY-MM-DD'),
    'local_time', to_char(v_local, 'HH24:MI')
  );
END;
$$;

COMMENT ON FUNCTION public.get_establishment_clock(uuid) IS
  'Relógio oficial do estabelecimento: now() do servidor no fuso IANA do tenant.';

-- Substitui a escala semanal de um membro (apenas proprietário).
CREATE OR REPLACE FUNCTION public.set_establishment_schedule(p_member_id uuid, p_schedules jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_establishment_id uuid;
  v_member_active boolean;
  v_rows integer;
  v_distinct_weekdays integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  SELECT m.establishment_id, m.is_active
    INTO v_establishment_id, v_member_active
  FROM public.establishment_members m
  WHERE m.id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Membro nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario configura escalas';
  END IF;

  IF NOT v_member_active THEN
    RAISE EXCEPTION 'Vinculo inativo: reative o membro antes de definir a escala';
  END IF;

  IF jsonb_typeof(p_schedules) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_schedules) = 0 THEN
    RAISE EXCEPTION 'Escala invalida: informe os dias da semana do membro';
  END IF;

  SELECT count(*) INTO v_rows FROM jsonb_array_elements(p_schedules);
  SELECT count(DISTINCT (e.value->>'weekday')) INTO v_distinct_weekdays
  FROM jsonb_array_elements(p_schedules) AS e(value);

  IF v_rows <> v_distinct_weekdays THEN
    RAISE EXCEPTION 'Escala invalida: cada dia da semana deve aparecer uma unica vez';
  END IF;

  DELETE FROM public.establishment_schedules WHERE member_id = p_member_id;

  INSERT INTO public.establishment_schedules (
    establishment_id, member_id, weekday, is_day_off,
    start_time, end_time, break_start, break_end
  )
  SELECT
    v_establishment_id,
    p_member_id,
    (e.value->>'weekday')::int,
    COALESCE((e.value->>'is_day_off')::boolean, false),
    NULLIF(e.value->>'start_time', '')::time,
    NULLIF(e.value->>'end_time', '')::time,
    NULLIF(e.value->>'break_start', '')::time,
    NULLIF(e.value->>'break_end', '')::time
  FROM jsonb_array_elements(p_schedules) AS e(value);
END;
$$;

COMMENT ON FUNCTION public.set_establishment_schedule(uuid, jsonb) IS
  'Define a escala semanal do membro (somente proprietário); turnos noturnos permitidos.';

-- Entrada (check-in): identidade = auth.uid(); horário = now() do servidor.
CREATE OR REPLACE FUNCTION public.record_attendance_check_in(p_establishment_id uuid)
RETURNS public.attendance_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_member_id uuid;
  v_today date;
  v_timezone text;
  v_record public.attendance_records%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  SELECT timezone INTO v_timezone
  FROM public.establishments WHERE id = p_establishment_id;

  SELECT m.id INTO v_member_id
  FROM public.establishment_members m
  WHERE m.establishment_id = p_establishment_id
    AND m.user_id = auth.uid()
    AND m.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vinculo inexistente ou inativo neste estabelecimento';
  END IF;

  v_today := (now() AT TIME ZONE v_timezone)::date;

  -- Sem duas entradas em aberto: qualquer saída pendente (inclusive de dias
  -- anteriores ou de turno que cruzou a meia-noite) bloqueia nova entrada.
  -- Saídas esquecidas NÃO são contornadas criando outro registro: o
  -- proprietário corrige o registro aberto pela operação administrativa
  -- auditável (correct_attendance_record). O índice único parcial
  -- attendance_records_one_open_per_member é a garantia definitiva contra
  -- corridas; a checagem abaixo apenas devolve uma mensagem amigável.
  IF EXISTS (
    SELECT 1 FROM public.attendance_records r
    WHERE r.member_id = v_member_id
      AND r.check_out_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Existe um registro de entrada em aberto: o proprietario deve corrigir a saida antes de uma nova entrada';
  END IF;

  BEGIN
    INSERT INTO public.attendance_records
      (establishment_id, member_id, work_date, check_in_at, check_in_source)
    VALUES
      (p_establishment_id, v_member_id, v_today, now(), 'self')
    ON CONFLICT (member_id, work_date) DO NOTHING
    RETURNING * INTO v_record;
  EXCEPTION WHEN unique_violation THEN
    -- Corrida entre check-ins em dias diferentes (ex.: virada de meia-noite):
    -- o índice parcial impediu a segunda entrada aberta.
    RAISE EXCEPTION 'Existe um registro de entrada em aberto: o proprietario deve corrigir a saida antes de uma nova entrada';
  END;

  IF v_record.id IS NULL THEN
    RAISE EXCEPTION 'Registro de entrada ja existe para hoje';
  END IF;

  RETURN v_record;
END;
$$;

COMMENT ON FUNCTION public.record_attendance_check_in(uuid) IS
  'Registra a entrada do USUÁRIO AUTENTICADO com now() do servidor; não aceita duplicidade diária.';

-- Saída (check-out): exige registro de entrada aberto no dia (fuso do tenant).
CREATE OR REPLACE FUNCTION public.record_attendance_check_out(p_establishment_id uuid)
RETURNS public.attendance_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_member_id uuid;
  v_today date;
  v_timezone text;
  v_record public.attendance_records%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  SELECT timezone INTO v_timezone
  FROM public.establishments WHERE id = p_establishment_id;

  SELECT m.id INTO v_member_id
  FROM public.establishment_members m
  WHERE m.establishment_id = p_establishment_id
    AND m.user_id = auth.uid()
    AND m.is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Vinculo inexistente ou inativo neste estabelecimento';
  END IF;

  v_today := (now() AT TIME ZONE v_timezone)::date;

  -- Turno noturno: a entrada pode ter ocorrido no dia anterior (22h→02h) —
  -- procura o registro EM ABERTO mais recente (últimas 24h) e fecha com
  -- guarda atômica (check_out_at IS NULL), impedindo check-outs simultâneos
  -- de sobrescreverem o horário já registrado.
  UPDATE public.attendance_records
  SET check_out_at = now(), check_out_source = 'self'
  WHERE id = (
    SELECT r.id FROM public.attendance_records r
    WHERE r.member_id = v_member_id
      AND r.check_in_at IS NOT NULL
      AND r.check_out_at IS NULL
      AND r.work_date >= v_today - 1
    ORDER BY r.work_date DESC, r.check_in_at DESC
    LIMIT 1
    FOR UPDATE
  )
  AND check_out_at IS NULL
  RETURNING * INTO v_record;

  IF v_record.id IS NOT NULL THEN
    RETURN v_record;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.attendance_records r
    WHERE r.member_id = v_member_id AND r.work_date = v_today
  ) THEN
    RAISE EXCEPTION 'Saida ja registrada para hoje';
  END IF;

  RAISE EXCEPTION 'Nenhum registro de entrada para hoje';
END;
$$;

COMMENT ON FUNCTION public.record_attendance_check_out(uuid) IS
  'Registra a saída do USUÁRIO AUTENTICADO com now() do servidor; exige entrada aberta no dia.';

-- Exceções e ausências (apenas proprietário; não altera a escala habitual).
CREATE OR REPLACE FUNCTION public.record_attendance_exception(
  p_member_id uuid,
  p_exception_type text,
  p_start_date date,
  p_end_date date,
  p_reason text DEFAULT NULL
)
RETURNS public.attendance_exceptions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_establishment_id uuid;
  v_record public.attendance_exceptions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  SELECT m.establishment_id INTO v_establishment_id
  FROM public.establishment_members m
  WHERE m.id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Membro nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario registra exceções e ausências';
  END IF;

  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RAISE EXCEPTION 'Periodo de datas invalido';
  END IF;

  INSERT INTO public.attendance_exceptions
    (establishment_id, member_id, start_date, end_date, exception_type, reason, recorded_by)
  VALUES
    (v_establishment_id, p_member_id, p_start_date, p_end_date, p_exception_type, p_reason, auth.uid())
  RETURNING * INTO v_record;

  RETURN v_record;
END;
$$;

COMMENT ON FUNCTION public.record_attendance_exception(uuid, text, date, date, text) IS
  'Registra falta, atraso justificado, saída antecipada, folga, férias ou ajuste (somente proprietário).';

-- Correção administrativa de presença com trilha de auditoria (somente proprietário).
CREATE OR REPLACE FUNCTION public.correct_attendance_record(
  p_attendance_id uuid,
  p_check_in timestamptz DEFAULT NULL,
  p_check_out timestamptz DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS public.attendance_records
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_record public.attendance_records%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Autenticacao requerida';
  END IF;

  SELECT r.* INTO v_record FROM public.attendance_records r WHERE r.id = p_attendance_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Registro de presença nao encontrado';
  END IF;

  IF NOT public.is_establishment_owner(v_record.establishment_id) THEN
    RAISE EXCEPTION 'Apenas o proprietario corrige registros de presença';
  END IF;

  IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'Justificativa obrigatoria para corrigir o registro';
  END IF;

  IF p_check_in IS NULL AND p_check_out IS NULL THEN
    RAISE EXCEPTION 'Informe ao menos um horario para corrigir';
  END IF;

  -- Cronologia: a entrada corrigida deve preceder a saída corrigida.
  IF COALESCE(p_check_in, v_record.check_in_at) IS NOT NULL
     AND COALESCE(p_check_out, v_record.check_out_at) IS NOT NULL
     AND COALESCE(p_check_in, v_record.check_in_at) > COALESCE(p_check_out, v_record.check_out_at) THEN
    RAISE EXCEPTION 'Horarios inconsistentes: a entrada deve preceder a saida';
  END IF;

  INSERT INTO public.attendance_corrections
    (establishment_id, attendance_id, previous_check_in_at, previous_check_out_at,
     check_in_at, check_out_at, reason, corrected_by)
  VALUES
    (v_record.establishment_id, v_record.id,
     v_record.check_in_at, v_record.check_out_at,
     COALESCE(p_check_in, v_record.check_in_at),
     COALESCE(p_check_out, v_record.check_out_at),
     p_reason, auth.uid());

  UPDATE public.attendance_records
  SET check_in_at = COALESCE(p_check_in, check_in_at),
      check_out_at = COALESCE(p_check_out, check_out_at),
      check_out_source = CASE WHEN p_check_out IS NOT NULL THEN 'owner' ELSE check_out_source END,
      corrected_by = auth.uid(),
      corrected_at = now(),
      correction_reason = p_reason
  WHERE id = v_record.id
  RETURNING * INTO v_record;

  RETURN v_record;
END;
$$;

COMMENT ON FUNCTION public.correct_attendance_record(uuid, timestamptz, timestamptz, text) IS
  'Corrige entrada/saída com justificativa e registra auditoria integral (somente proprietário).';

-- Matriz de EXECUTE: apenas `authenticated` chama as RPCs.
REVOKE ALL ON FUNCTION public.get_establishment_clock(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_establishment_clock(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_establishment_clock(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.get_establishment_clock(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.set_establishment_schedule(uuid, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_establishment_schedule(uuid, jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.set_establishment_schedule(uuid, jsonb) FROM service_role;
GRANT EXECUTE ON FUNCTION public.set_establishment_schedule(uuid, jsonb) TO authenticated;

REVOKE ALL ON FUNCTION public.record_attendance_check_in(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_attendance_check_in(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.record_attendance_check_in(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.record_attendance_check_in(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.record_attendance_check_out(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_attendance_check_out(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.record_attendance_check_out(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.record_attendance_check_out(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.record_attendance_exception(uuid, text, date, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_attendance_exception(uuid, text, date, date, text) FROM anon;
REVOKE ALL ON FUNCTION public.record_attendance_exception(uuid, text, date, date, text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.record_attendance_exception(uuid, text, date, date, text) TO authenticated;

REVOKE ALL ON FUNCTION public.correct_attendance_record(uuid, timestamptz, timestamptz, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.correct_attendance_record(uuid, timestamptz, timestamptz, text) FROM anon;
REVOKE ALL ON FUNCTION public.correct_attendance_record(uuid, timestamptz, timestamptz, text) FROM service_role;
GRANT EXECUTE ON FUNCTION public.correct_attendance_record(uuid, timestamptz, timestamptz, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
