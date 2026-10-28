import type { Json } from './database.types'
import { supabase } from './supabase'

/**
 * Etapa 8 — Escalas de trabalho, presença (check-in/check-out), exceções e
 * correções administrativas.
 *
 * Conceitos separados:
 *   • ESCALA (establishment_schedules)      — expediente PREVISTO;
 *   • PRESENÇA (attendance_records)         — entrada/saída REGISTRADAS;
 *   • FALTA — só existe quando registrada por alguém autorizado; a ausência
 *     de check-in NÃO é falta confirmada;
 *   • "Em atendimento" — NÃO é derivado aqui (depende da futura agenda).
 *
 * O horário oficial vem do servidor (RPC get_establishment_clock, no fuso
 * IANA do estabelecimento); nada é confiado ao relógio do navegador.
 */

export type AttendanceExceptionType =
  | 'absence'
  | 'justified_delay'
  | 'early_leave'
  | 'exceptional_day_off'
  | 'vacation'
  | 'schedule_adjustment'

export const ATTENDANCE_EXCEPTION_LABELS: Record<AttendanceExceptionType, string> = {
  absence: 'Falta',
  justified_delay: 'Atraso justificado',
  early_leave: 'Saída antecipada',
  exceptional_day_off: 'Folga excepcional',
  vacation: 'Férias ou afastamento',
  schedule_adjustment: 'Ajuste de expediente',
}

/** 0 = domingo … 6 = sábado (mesmo mapeamento do banco). */
export const WEEKDAY_LABELS = [
  'Domingo',
  'Segunda-feira',
  'Terça-feira',
  'Quarta-feira',
  'Quinta-feira',
  'Sexta-feira',
  'Sábado',
] as const

const WEEKDAY_SHORT = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'] as const

export interface WorkSchedule {
  id: string
  establishment_id: string
  member_id: string
  weekday: number
  is_day_off: boolean
  start_time: string | null
  end_time: string | null
  break_start: string | null
  break_end: string | null
}

/** Dia de escala enviado na configuração (RPC set_establishment_schedule). */
export type ScheduleDraft = {
  weekday: number
  is_day_off: boolean
  start_time: string | null
  end_time: string | null
  break_start: string | null
  break_end: string | null
}

export interface AttendanceRecord {
  id: string
  establishment_id: string
  member_id: string
  work_date: string
  check_in_at: string | null
  check_out_at: string | null
  check_in_source: string | null
  check_out_source: string | null
  corrected_at: string | null
  correction_reason: string | null
}

export interface AttendanceException {
  id: string
  establishment_id: string
  member_id: string
  start_date: string
  end_date: string
  exception_type: AttendanceExceptionType
  reason: string | null
  recorded_by: string
  created_at: string
}

/** Relógio oficial do estabelecimento (hora do servidor, fuso do tenant). */
export interface EstablishmentClock {
  now_at: string
  timezone: string
  local_date: string
  local_time: string
}

const SCHEDULE_COLUMNS =
  'id, establishment_id, member_id, weekday, is_day_off, start_time, end_time, break_start, break_end'
const ATTENDANCE_COLUMNS =
  'id, establishment_id, member_id, work_date, check_in_at, check_out_at, check_in_source, check_out_source, corrected_at, correction_reason'
const EXCEPTION_COLUMNS =
  'id, establishment_id, member_id, start_date, end_date, exception_type, reason, recorded_by, created_at'

function throwIfError<TErrorLike extends Error>(error: TErrorLike | null): void {
  if (error) throw error
}

/** Lista a escala semanal de todos os membros do estabelecimento ativo. */
export async function listEstablishmentSchedules(
  establishmentId: string,
): Promise<WorkSchedule[]> {
  const { data, error } = await supabase
    .from('establishment_schedules')
    .select(SCHEDULE_COLUMNS)
    .eq('establishment_id', establishmentId)
    .order('member_id')
    .order('weekday')

  throwIfError(error)
  return (data ?? []) as unknown as WorkSchedule[]
}

interface RecordFilter {
  memberId?: string
  limit?: number
}

/** Consulta o histórico de presença do estabelecimento (opcional: por membro). */
export async function listAttendanceRecords(
  establishmentId: string,
  options: RecordFilter = {},
): Promise<AttendanceRecord[]> {
  let query = supabase
    .from('attendance_records')
    .select(ATTENDANCE_COLUMNS)
    .eq('establishment_id', establishmentId)

  if (options.memberId) {
    query = query.eq('member_id', options.memberId)
  }

  const { data, error } = await query
    .order('work_date', { ascending: false })
    .limit(options.limit ?? 60)

  throwIfError(error)
  return (data ?? []) as unknown as AttendanceRecord[]
}

/** Consulta as exceções/ausências do estabelecimento (opcional: por membro). */
export async function listAttendanceExceptions(
  establishmentId: string,
  options: RecordFilter = {},
): Promise<AttendanceException[]> {
  let query = supabase
    .from('attendance_exceptions')
    .select(EXCEPTION_COLUMNS)
    .eq('establishment_id', establishmentId)

  if (options.memberId) {
    query = query.eq('member_id', options.memberId)
  }

  const { data, error } = await query.order('start_date', { ascending: false }).limit(
    options.limit ?? 60,
  )

  throwIfError(error)
  return (data ?? []) as unknown as AttendanceException[]
}

/** Hora oficial do SERVIDOR no fuso do estabelecimento (não usa o navegador). */
export async function fetchEstablishmentClock(establishmentId: string): Promise<EstablishmentClock> {
  const { data, error } = await supabase.rpc('get_establishment_clock', {
    p_establishment_id: establishmentId,
  })

  throwIfError(error)
  return data as unknown as EstablishmentClock
}

/**
 * Validação espelhada da migration 00011 (schedule_time_window / break_pair /
 * break_order). Intervalos podem atravessar a meia-noite (23:00→01:00); o que
 * não se aceita é intervalo vazio ou par incompleto. Falhar aqui evita uma
 * ida ao servidor apenas para receber o mesmo erro do banco.
 */
export function validateScheduleDrafts(schedules: ScheduleDraft[]): void {
  if (schedules.length === 0) {
    throw new Error('Escala invalida: informe os dias da semana do membro')
  }

  const weekdays = new Set<number>()

  for (const draft of schedules) {
    if (!Number.isInteger(draft.weekday) || draft.weekday < 0 || draft.weekday > 6) {
      throw new Error('Escala invalida: dia da semana fora do intervalo permitido')
    }

    if (weekdays.has(draft.weekday)) {
      throw new Error('Escala invalida: cada dia da semana deve aparecer uma unica vez')
    }
    weekdays.add(draft.weekday)

    if (draft.is_day_off) continue

    if (!draft.start_time || !draft.end_time) {
      throw new Error('Escala invalida: informe inicio e termino do expediente')
    }

    if ((draft.break_start === null) !== (draft.break_end === null)) {
      throw new Error('Escala invalida: informe inicio e fim do intervalo')
    }

    if (draft.break_start && draft.break_end && draft.break_start === draft.break_end) {
      throw new Error('Escala invalida: o intervalo precisa ter duracao maior que zero')
    }
  }
}

/** Substitui a escala semanal do membro (apenas proprietário, no banco). */
export async function saveMemberSchedule(
  memberId: string,
  schedules: ScheduleDraft[],
): Promise<void> {
  validateScheduleDrafts(schedules)

  const { error } = await supabase.rpc('set_establishment_schedule', {
    p_member_id: memberId,
    p_schedules: schedules as unknown as Json,
  })

  throwIfError(error)
}

/** Registrar entrada do USUÁRIO AUTENTICADO (horário = now() do servidor). */
export async function recordCheckIn(establishmentId: string): Promise<AttendanceRecord> {
  const { data, error } = await supabase.rpc('record_attendance_check_in', {
    p_establishment_id: establishmentId,
  })

  throwIfError(error)
  return data as unknown as AttendanceRecord
}

/** Registrar saída do USUÁRIO AUTENTICADO (exige entrada aberta no dia). */
export async function recordCheckOut(establishmentId: string): Promise<AttendanceRecord> {
  const { data, error } = await supabase.rpc('record_attendance_check_out', {
    p_establishment_id: establishmentId,
  })

  throwIfError(error)
  return data as unknown as AttendanceRecord
}

/** Exceção/ausência registrada pelo proprietário (não altera a escala habitual). */
export async function recordAttendanceException(
  memberId: string,
  exceptionType: AttendanceExceptionType,
  startDate: string,
  endDate: string,
  reason: string | null = null,
): Promise<AttendanceException> {
  const { data, error } = await supabase.rpc('record_attendance_exception', {
    p_member_id: memberId,
    p_exception_type: exceptionType,
    p_start_date: startDate,
    p_end_date: endDate,
    p_reason: reason,
  })

  throwIfError(error)
  return data as unknown as AttendanceException
}

/** Correção administrativa com justificativa (auditoria no banco). */
export async function correctAttendanceRecord(
  attendanceId: string,
  input: { checkInAt?: string | null; checkOutAt?: string | null; reason: string },
): Promise<AttendanceRecord> {
  const { data, error } = await supabase.rpc('correct_attendance_record', {
    p_attendance_id: attendanceId,
    p_check_in: input.checkInAt,
    p_check_out: input.checkOutAt,
    p_reason: input.reason,
  })

  throwIfError(error)
  return data as unknown as AttendanceRecord
}

// ---------------------------------------------------------------------------
// Cálculo de status de presença (sem rotinas em segundo plano)
// ---------------------------------------------------------------------------

export type PresenceStatusKey =
  | 'no_clock'
  | 'not_configured'
  | 'day_off'
  | 'exception'
  | 'absence'
  | 'outside_hours'
  | 'awaiting_check_in'
  | 'checked_in'
  | 'on_break'
  | 'checked_out'

export const PRESENCE_STATUS_LABELS: Record<PresenceStatusKey, string> = {
  no_clock: 'Horário do servidor indisponível',
  not_configured: 'Escala não configurada',
  day_off: 'Folga prevista',
  exception: 'Exceção registrada',
  absence: 'Ausência registrada',
  outside_hours: 'Fora do expediente',
  awaiting_check_in: 'Aguardando registro de entrada',
  checked_in: 'Entrada registrada',
  on_break: 'Em intervalo',
  checked_out: 'Saída registrada',
}

/** 'YYYY-MM-DD' → 0 (domingo) … 6 (sábado). */
export function weekdayOfDate(localDate: string): number {
  return new Date(`${localDate}T12:00:00Z`).getUTCDay()
}

/** 'HH:MM[:SS]' → minutos do dia (null quando ausente). */
export function minutesFromTime(value: string | null): number | null {
  if (!value) return null
  const [h = '0', m = '0'] = value.split(':')
  const hours = Number(h)
  const minutes = Number(m)
  if (!Number.isFinite(hours) || !Number.isFinite(minutes)) return null
  return hours * 60 + minutes
}

/** Formata 'HH:MM[:SS]' para 'HH:MM'. */
export function formatTime(value: string | null): string {
  if (!value) return '—'
  const [h = '', m = ''] = value.split(':')
  return `${h}:${m}`
}

/** Janela half-open [start, end), com suporte a turnos que cruzam a meia-noite. */
export function isWithinWindow(minutes: number, start: number, end: number): boolean {
  if (end === start) return false
  return end <= start ? minutes >= start || minutes < end : minutes >= start && minutes < end
}

interface PresenceInput {
  schedules: WorkSchedule[]
  attendance: AttendanceRecord | null
  exceptions: AttendanceException[]
  clock: EstablishmentClock | null
}

interface PresenceStatus {
  key: PresenceStatusKey
  label: string
  /** Entrada registrada fora do expediente previsto (para conferência). */
  offScheduleCheckIn: boolean
}

const BLOCKING_EXCEPTION_TYPES: AttendanceExceptionType[] = [
  'vacation',
  'exceptional_day_off',
  'absence',
]

/**
 * Status atual: calculado sempre a partir da ESCALA + REGISTROS + horário do
 * servidor. Pausa de atendimentos e habilitação de serviço NÃO influenciam o
 * controle de presença; nada aqui é "em atendimento".
 */
export function resolvePresenceStatus(input: PresenceInput): PresenceStatus {
  const defaults: PresenceStatus = { key: 'no_clock', label: PRESENCE_STATUS_LABELS.no_clock, offScheduleCheckIn: false }
  const { clock, schedules, attendance, exceptions } = input

  // Exceções que bloqueiam o expediente prevalecem sobre a folga/ausência não
  // registrada, mas um registro de presença (entrada/saída) tem prioridade.
  const today = clock?.local_date ?? null
  const activeExceptions = today
    ? exceptions.filter((e) => e.start_date <= today && today <= e.end_date)
    : []
  const blockingException = activeExceptions.find(
    (e) => BLOCKING_EXCEPTION_TYPES.includes(e.exception_type),
  )

  const checkedState: PresenceStatus | null = attendance
    ? attendance.check_out_at
      ? { key: 'checked_out', label: PRESENCE_STATUS_LABELS.checked_out, offScheduleCheckIn: false }
      : { key: 'checked_in', label: PRESENCE_STATUS_LABELS.checked_in, offScheduleCheckIn: false }
    : null

  if (!clock || today === null) {
    return checkedState ?? defaults
  }

  if (schedules.length === 0) {
    return { ...defaults, key: 'not_configured', label: PRESENCE_STATUS_LABELS.not_configured }
  }

  const schedulesForWeekday = schedules.filter((s) => s.weekday === weekdayOfDate(today))
  if (schedulesForWeekday.length === 0) {
    return { ...defaults, key: 'not_configured', label: PRESENCE_STATUS_LABELS.not_configured }
  }

  const row = schedulesForWeekday[0]

  if (checkedState) {
    // Intervalo apenas com entrada aberta e dentro da janela configurada.
    if (
      !attendance?.check_out_at &&
      attendance?.check_in_at &&
      row.start_time &&
      row.end_time &&
      row.break_start &&
      row.break_end
    ) {
      const startMins = minutesFromTime(row.start_time)
      const endMins = minutesFromTime(row.end_time)
      const breakStart = minutesFromTime(row.break_start)
      const breakEnd = minutesFromTime(row.break_end)
      const nowMins = minutesFromTime(`${clock.local_time}:00`)

      if (
        startMins !== null &&
        endMins !== null &&
        breakStart !== null &&
        breakEnd !== null &&
        nowMins !== null &&
        isWithinWindow(nowMins, startMins, endMins) &&
        isWithinWindow(nowMins, breakStart, breakEnd)
      ) {
        return { key: 'on_break', label: PRESENCE_STATUS_LABELS.on_break, offScheduleCheckIn: false }
      }
    }
    return checkedState
  }

  if (blockingException) {
    const key: PresenceStatusKey =
      blockingException.exception_type === 'absence' ? 'absence' : 'exception'
    return { key, label: PRESENCE_STATUS_LABELS[key], offScheduleCheckIn: false }
  }

  if (row.is_day_off) {
    return { key: 'day_off', label: PRESENCE_STATUS_LABELS.day_off, offScheduleCheckIn: false }
  }

  const startMins = minutesFromTime(row.start_time)
  const endMins = minutesFromTime(row.end_time)
  const nowMins = minutesFromTime(`${clock.local_time}:00`)

  if (startMins !== null && endMins !== null && nowMins !== null && isWithinWindow(nowMins, startMins, endMins)) {
    return {
      key: 'awaiting_check_in',
      label: PRESENCE_STATUS_LABELS.awaiting_check_in,
      offScheduleCheckIn: false,
    }
  }

  return {
    key: 'outside_hours',
    label: PRESENCE_STATUS_LABELS.outside_hours,
    offScheduleCheckIn: false,
  }
}

/** Entrada registrada fora do expediente previsto (não é falta automática). */
export function isCheckInOffSchedule(
  schedule: WorkSchedule | null,
  attendance: AttendanceRecord | null,
  clock: EstablishmentClock | null,
): boolean {
  if (!schedule || schedule.is_day_off || !attendance?.check_in_at || !clock) return false
  const startMins = minutesFromTime(schedule.start_time)
  const inAt = minutesFromTime(clock.local_time)
  if (startMins === null || inAt === null) return false
  const endMins = minutesFromTime(schedule.end_time)
  const inShift =
    startMins !== null && endMins !== null
      ? isWithinWindow(inAt, startMins, endMins)
      : false
  return !inShift
}

interface ScheduleSummary {
  text: string
  configured: boolean
}

/** Resumo legível da escala do membro, ex.: 'Seg 09:00–18:00 • Sáb 09:00–13:00'. */
export function scheduleSummary(schedules: WorkSchedule[]): ScheduleSummary {
  const working = schedules
    .filter((s) => !s.is_day_off)
    .sort((a, b) => a.weekday - b.weekday)

  if (working.length === 0) {
    return { text: 'Sem escala configurada', configured: false }
  }

  return {
    text: working
      .map((s) => {
        const breakPart = s.break_start && s.break_end
          ? ` (intervalo ${formatTime(s.break_start)}–${formatTime(s.break_end)})`
          : ''
        return `${WEEKDAY_SHORT[s.weekday]} ${formatTime(s.start_time)}–${formatTime(s.end_time)}${breakPart}`
      })
      .join(' • '),
    configured: true,
  }
}

/** Agrupa as escalas por membro (consultas retornam a lista do tenant). */
export function groupSchedulesByMember(schedules: WorkSchedule[]): Map<string, WorkSchedule[]> {
  return schedules.reduce((map, schedule) => {
    const current = map.get(schedule.member_id) ?? []
    current.push(schedule)
    map.set(schedule.member_id, current)
    return map
  }, new Map<string, WorkSchedule[]>())
}
