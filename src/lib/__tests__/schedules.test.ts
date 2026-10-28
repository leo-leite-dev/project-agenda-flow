import { describe, expect, it, vi, beforeEach } from 'vitest'

import {
  ATTENDANCE_EXCEPTION_LABELS,
  PRESENCE_STATUS_LABELS,
  correctAttendanceRecord,
  fetchEstablishmentClock,
  formatTime,
  groupSchedulesByMember,
  isCheckInOffSchedule,
  isWithinWindow,
  listAttendanceExceptions,
  listAttendanceRecords,
  listEstablishmentSchedules,
  minutesFromTime,
  recordAttendanceException,
  recordCheckIn,
  recordCheckOut,
  resolvePresenceStatus,
  saveMemberSchedule,
  scheduleSummary,
  validateScheduleDrafts,
  weekdayOfDate,
  type AttendanceRecord,
  type AttendanceException,
  type EstablishmentClock,
  type ScheduleDraft,
  type WorkSchedule,
} from '../schedules'

const fromMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())

vi.mock('../supabase', () => ({
  supabase: {
    from: (...args: unknown[]) => fromMock(...args),
    rpc: (...args: unknown[]) => rpcMock(...args),
  },
}))

/**
 * Builder thenable: encadeia select/eq/order/limit e, ao ser aguardado
 * (await em qualquer ponto da cadeia), resolve o resultado configurado —
 * assim validamos o comportamento real do cliente supabase-js.
 */
function thenableBuilder(result: { data: unknown; error: unknown }) {
  const calls = new Map<string, unknown[]>()
  const proxy: unknown = new Proxy(function () {}, {
    get(_target, prop) {
      if (prop === 'then') {
        return (resolve: (value: unknown) => unknown) => resolve(result)
      }
      return (...args: unknown[]) => {
        const existing = calls.get(prop as string) ?? []
        existing.push(args)
        calls.set(prop as string, existing)
        return proxy
      }
    },
    apply() {
      return proxy
    },
  })
  return { proxy, calls }
}

export const scheduleFixture = (overrides: Partial<WorkSchedule> = {}): WorkSchedule => ({
  id: 'sch-1',
  establishment_id: 'est-1',
  member_id: 'mem-1',
  weekday: 1,
  is_day_off: false,
  start_time: '09:00:00',
  end_time: '18:00:00',
  break_start: null,
  break_end: null,
  ...overrides,
})

const attendanceFixture = (overrides: Partial<AttendanceRecord> = {}): AttendanceRecord => ({
  id: 'att-1',
  establishment_id: 'est-1',
  member_id: 'mem-1',
  work_date: '2026-03-02',
  check_in_at: '2026-03-02T12:00:00+00:00',
  check_out_at: null,
  check_in_source: 'self',
  check_out_source: null,
  corrected_at: null,
  correction_reason: null,
  ...overrides,
})

const exceptionFixture = (overrides: Partial<AttendanceException> = {}): AttendanceException => ({
  id: 'exc-1',
  establishment_id: 'est-1',
  member_id: 'mem-1',
  start_date: '2026-03-02',
  end_date: '2026-03-02',
  exception_type: 'absence',
  reason: null,
  recorded_by: 'user-1',
  created_at: '2026-03-02T01:00:00+00:00',
  ...overrides,
})

const clockFixture = (overrides: Partial<EstablishmentClock> = {}): EstablishmentClock => ({
  now_at: '2026-03-02T13:00:00+00:00',
  timezone: 'America/Sao_Paulo',
  local_date: '2026-03-02',
  local_time: '10:00',
  ...overrides,
})

describe('consultas de escalas e presença', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('lista as escalas do estabelecimento ativo ordenadas por membro e dia', async () => {
    const builder = thenableBuilder({
      data: [scheduleFixture()],
      error: null,
    })
    fromMock.mockReturnValue(builder.proxy)

    const schedules = await listEstablishmentSchedules('est-1')

    expect(fromMock).toHaveBeenCalledWith('establishment_schedules')
    expect(builder.calls.get('select')).toEqual([
      ['id, establishment_id, member_id, weekday, is_day_off, start_time, end_time, break_start, break_end'],
    ])
    expect(builder.calls.get('eq')).toEqual([['establishment_id', 'est-1']])
    expect(builder.calls.get('order')).toEqual([
      ['member_id'],
      ['weekday'],
    ])
    expect(schedules).toHaveLength(1)
    expect(schedules[0]).toMatchObject({ member_id: 'mem-1', weekday: 1 })
  })

  it('lista presença do estabelecimento com filtro opcional por membro e limite', async () => {
    const builder = thenableBuilder({ data: [attendanceFixture()], error: null })
    fromMock.mockReturnValue(builder.proxy)

    const records = await listAttendanceRecords('est-1', { memberId: 'mem-1', limit: 30 })

    expect(fromMock).toHaveBeenCalledWith('attendance_records')
    expect(builder.calls.get('eq')).toEqual([
      ['establishment_id', 'est-1'],
      ['member_id', 'mem-1'],
    ])
    expect(builder.calls.get('order')).toEqual([['work_date', { ascending: false }]])
    expect(builder.calls.get('limit')).toEqual([[30]])
    expect(records[0]).toMatchObject({ work_date: '2026-03-02', check_in_source: 'self' })
  })

  it('usa o limite padrão quando nenhum membro é informado na presença', async () => {
    const builder = thenableBuilder({ data: [], error: null })
    fromMock.mockReturnValue(builder.proxy)

    await listAttendanceRecords('est-1')

    expect(builder.calls.get('eq')).toEqual([['establishment_id', 'est-1']])
    expect(builder.calls.get('limit')).toEqual([[60]])
  })

  it('lista as exceções do estabelecimento ativo', async () => {
    const builder = thenableBuilder({ data: [exceptionFixture()], error: null })
    fromMock.mockReturnValue(builder.proxy)

    const exceptions = await listAttendanceExceptions('est-1', { memberId: 'mem-1' })

    expect(fromMock).toHaveBeenCalledWith('attendance_exceptions')
    expect(builder.calls.get('select')).toEqual([
      ['id, establishment_id, member_id, start_date, end_date, exception_type, reason, recorded_by, created_at'],
    ])
    expect(builder.calls.get('order')).toEqual([['start_date', { ascending: false }]])
    expect(exceptions[0]).toMatchObject({ exception_type: 'absence' })
  })

  it('propaga o erro do Supabase sem tratar falha como sucesso', async () => {
    fromMock.mockReturnValue(
      thenableBuilder({ data: null, error: { message: 'rls' } }).proxy,
    )

    await expect(listEstablishmentSchedules('est-1')).rejects.toEqual({ message: 'rls' })
  })
})

describe('RPCs da etapa 8', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('consulta o relógio oficial do servidor no fuso do estabelecimento', async () => {
    const clock = clockFixture()
    rpcMock.mockResolvedValue({ data: clock, error: null })

    const result = await fetchEstablishmentClock('est-1')

    expect(rpcMock).toHaveBeenCalledWith('get_establishment_clock', { p_establishment_id: 'est-1' })
    expect(result).toEqual(clock)
  })

  it('salva a escala semanal do membro via set_establishment_schedule', async () => {
    rpcMock.mockResolvedValue({ data: null, error: null })
    const drafts = [
      {
        weekday: 1,
        is_day_off: false,
        start_time: '09:00',
        end_time: '18:00',
        break_start: '12:00',
        break_end: '13:00',
      },
      {
        weekday: 6,
        is_day_off: true,
        start_time: null,
        end_time: null,
        break_start: null,
        break_end: null,
      },
    ]

    await saveMemberSchedule('mem-1', drafts)

    expect(rpcMock).toHaveBeenCalledWith('set_establishment_schedule', {
      p_member_id: 'mem-1',
      p_schedules: drafts,
    })
  })

  it('registra entrada com horário do servidor e propaga duplicidade real', async () => {
    const record = attendanceFixture()
    rpcMock.mockResolvedValueOnce({ data: record, error: null })

    const result = await recordCheckIn('est-1')
    expect(rpcMock).toHaveBeenCalledWith('record_attendance_check_in', {
      p_establishment_id: 'est-1',
    })
    expect(result.check_in_at).toBe(record.check_in_at)

    rpcMock.mockResolvedValueOnce({
      data: null,
      error: { message: 'Registro de entrada ja existe para hoje' },
    })
    await expect(recordCheckIn('est-1')).rejects.toEqual({
      message: 'Registro de entrada ja existe para hoje',
    })
  })

  it('registra saída exigindo entrada aberta e propaga erros do banco', async () => {
    const record = attendanceFixture({ check_out_at: '2026-03-02T22:00:00+00:00', check_out_source: 'self' })
    rpcMock.mockResolvedValueOnce({ data: record, error: null })

    const result = await recordCheckOut('est-1')
    expect(rpcMock).toHaveBeenCalledWith('record_attendance_check_out', {
      p_establishment_id: 'est-1',
    })
    expect(result.check_out_source).toBe('self')

    rpcMock.mockResolvedValueOnce({
      data: null,
      error: { message: 'Nenhum registro de entrada para hoje' },
    })
    await expect(recordCheckOut('est-1')).rejects.toEqual({
      message: 'Nenhum registro de entrada para hoje',
    })
  })

  it('registra exceção/ausência via RPC exclusiva do proprietário', async () => {
    const exception = exceptionFixture()
    rpcMock.mockResolvedValue({ data: exception, error: null })

    const result = await recordAttendanceException('mem-1', 'absence', '2026-03-02', '2026-03-02', 'Aviso')

    expect(rpcMock).toHaveBeenCalledWith('record_attendance_exception', {
      p_member_id: 'mem-1',
      p_exception_type: 'absence',
      p_start_date: '2026-03-02',
      p_end_date: '2026-03-02',
      p_reason: 'Aviso',
    })
    expect(result.exception_type).toBe('absence')
  })

  it('corrige registro administrativamente com justificativa obrigatória', async () => {
    const record = attendanceFixture({ check_in_source: 'self', check_out_source: 'owner' })
    rpcMock.mockResolvedValue({ data: record, error: null })

    await correctAttendanceRecord('att-1', {
      checkInAt: '2026-03-02T09:10:00+00:00',
      checkOutAt: '2026-03-02T18:00:00+00:00',
      reason: 'Correção conferida',
    })

    expect(rpcMock).toHaveBeenCalledWith('correct_attendance_record', {
      p_attendance_id: 'att-1',
      p_check_in: '2026-03-02T09:10:00+00:00',
      p_check_out: '2026-03-02T18:00:00+00:00',
      p_reason: 'Correção conferida',
    })
  })

  it('expõe os rótulos das exceções sem afetar as chaves técnicas', () => {
    expect(Object.keys(ATTENDANCE_EXCEPTION_LABELS)).toEqual([
      'absence',
      'justified_delay',
      'early_leave',
      'exceptional_day_off',
      'vacation',
      'schedule_adjustment',
    ])
    expect(ATTENDANCE_EXCEPTION_LABELS.absence).toBe('Falta')
  })
})

describe('resolvePresenceStatus', () => {
  it('indica escala não configurada', () => {
    const status = resolvePresenceStatus({
      schedules: [],
      attendance: null,
      exceptions: [],
      clock: clockFixture(),
    })
    expect(status.key).toBe('not_configured')
  })

  it('indica folga prevista (sem ausência registrada e sem presença)', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture({ weekday: 0, is_day_off: true, start_time: null, end_time: null })],
      attendance: null,
      exceptions: [],
      clock: clockFixture({ local_date: '2026-03-01' }),
    })
    expect(status.key).toBe('day_off')
    expect(status.label).toBe('Folga prevista')
  })

  it('aguarda registro de entrada dentro do expediente previsto', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture()],
      attendance: null,
      exceptions: [],
      clock: clockFixture({ local_time: '10:00' }),
    })
    expect(status.key).toBe('awaiting_check_in')
  })

  it('solicita entrada, não falta, quando dentro do expediente', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture()],
      attendance: null,
      exceptions: [],
      clock: clockFixture({ local_time: '10:00' }),
    })
    expect(status.key).not.toBe('absence')
    expect(status.label).toBe('Aguardando registro de entrada')
  })

  it('exibe ausência registrada quando há exceção confirmada', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture()],
      attendance: null,
      exceptions: [exceptionFixture()],
      clock: clockFixture({ local_time: '10:00' }),
    })
    expect(status.key).toBe('absence')
    expect(status.label).toBe('Ausência registrada')
  })

  it('prioriza férias/afastamento como exceção', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture()],
      attendance: null,
      exceptions: [exceptionFixture({ exception_type: 'vacation', start_date: '2026-03-01', end_date: '2026-03-08' })],
      clock: clockFixture(),
    })
    expect(status.key).toBe('exception')
    expect(status.label).toBe('Exceção registrada')
  })

  it('sinaliza intervalo quando a entrada está aberta dentro da janela', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture({ break_start: '12:00:00', break_end: '13:00:00' })],
      attendance: attendanceFixture(),
      exceptions: [],
      clock: clockFixture({ local_time: '12:30' }),
    })
    expect(status.key).toBe('on_break')
    expect(status.label).toBe('Em intervalo')
  })

  it('sinaliza entrada registrada quando fora do intervalo', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture({ break_start: '12:00:00', break_end: '13:00:00' })],
      attendance: attendanceFixture(),
      exceptions: [],
      clock: clockFixture({ local_time: '14:00' }),
    })
    expect(status.key).toBe('checked_in')
    expect(status.label).toBe('Entrada registrada')
  })

  it('sinaliza saída registrada', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture()],
      attendance: attendanceFixture({ check_out_at: '2026-03-02T21:00:00+00:00', check_out_source: 'self' }),
      exceptions: [],
      clock: clockFixture({ local_time: '21:30' }),
    })
    expect(status.key).toBe('checked_out')
    expect(status.label).toBe('Saída registrada')
  })

  it('sinaliza fora do expediente quando fora da janela', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture()],
      attendance: null,
      exceptions: [],
      clock: clockFixture({ local_time: '20:30' }),
    })
    expect(status.key).toBe('outside_hours')
    expect(status.label).toBe('Fora do expediente')
  })

  it('suporta turno noturno que cruza a meia-noite', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture({ weekday: 1, start_time: '22:00:00', end_time: '02:00:00' })],
      attendance: null,
      exceptions: [],
      clock: clockFixture({ local_time: '23:30' }),
    })
    expect(status.key).toBe('awaiting_check_in')
  })

  it('sem relógio do servidor mostra a presença efetiva quando registrada', () => {
    const status = resolvePresenceStatus({
      schedules: [scheduleFixture()],
      attendance: attendanceFixture(),
      exceptions: [],
      clock: null,
    })
    expect(status.key).toBe('checked_in')

    const semRegistro = resolvePresenceStatus({
      schedules: [scheduleFixture()],
      attendance: null,
      exceptions: [],
      clock: null,
    })
    expect(semRegistro.key).toBe('no_clock')
    expect(semRegistro.label).toBe('Horário do servidor indisponível')
  })
})

describe('auxiliares de presença e escala', () => {
  it('detecta entrada fora do expediente previsto para conferência', () => {
    expect(
      isCheckInOffSchedule(scheduleFixture(), attendanceFixture(), clockFixture({ local_time: '20:00' })),
    ).toBe(true)
    expect(
      isCheckInOffSchedule(scheduleFixture(), attendanceFixture(), clockFixture({ local_time: '10:00' })),
    ).toBe(false)
    expect(isCheckInOffSchedule(null, attendanceFixture(), clockFixture({ local_time: '20:00' }))).toBe(false)
    expect(
      isCheckInOffSchedule(scheduleFixture(), attendanceFixture({ check_in_at: null }), clockFixture({
        local_time: '20:00',
      })),
    ).toBe(false)
  })

  it('detecta turnos noturnos nas janelas metade-abertas', () => {
    const start = minutesFromTime('22:00')
    const end = minutesFromTime('02:00')
    expect(start).toBe(22 * 60)
    expect(end).toBe(2 * 60)
    expect(isWithinWindow(23 * 60, start as number, end as number)).toBe(true)
    expect(isWithinWindow(1 * 60, start as number, end as number)).toBe(true)
    expect(isWithinWindow(9 * 60, start as number, end as number)).toBe(false)
    expect(isWithinWindow(13 * 60, 9 * 60, 18 * 60)).toBe(true)
  })

  it('deriva o dia da semana da data local e formata horários', () => {
    expect(weekdayOfDate('2026-03-01')).toBe(0)
    expect(weekdayOfDate('2026-03-02')).toBe(1)
    expect(formatTime('09:00:00')).toBe('09:00')
    expect(formatTime(null)).toBe('—')
  })

  it('resume a escala e marca quando não configurada', () => {
    const summary = scheduleSummary([
      scheduleFixture({ weekday: 0, is_day_off: true, start_time: null, end_time: null }),
      scheduleFixture({ weekday: 6, start_time: '22:00:00', end_time: '02:00:00' }),
      scheduleFixture({ weekday: 1, break_start: '12:00:00', break_end: '13:00:00' }),
    ])
    expect(summary.configured).toBe(true)
    expect(summary.text).toBe('Seg 09:00–18:00 (intervalo 12:00–13:00) • Sáb 22:00–02:00')

    expect(scheduleSummary([])).toEqual({ text: 'Sem escala configurada', configured: false })
  })

  it('agrupa escalas por membro', () => {
    const grouped = groupSchedulesByMember([
      scheduleFixture({ member_id: 'mem-1', weekday: 1 }),
      scheduleFixture({ member_id: 'mem-1', weekday: 2 }),
      scheduleFixture({ member_id: 'mem-2', weekday: 1 }),
    ])
    expect(grouped.get('mem-1')).toHaveLength(2)
    expect(grouped.get('mem-2')).toHaveLength(1)
  })

  it('exibe rótulos de status sem inventar atendimento', () => {
    expect(PRESENCE_STATUS_LABELS.checked_in).toBe('Entrada registrada')
    expect(Object.keys(PRESENCE_STATUS_LABELS)).not.toContain('in_service')
  })
})

describe('validateScheduleDrafts', () => {
  const draft = (overrides: Partial<ScheduleDraft> = {}): ScheduleDraft => ({
    weekday: 1,
    is_day_off: false,
    start_time: '22:00',
    end_time: '02:00',
    break_start: '23:00',
    break_end: '01:00',
    ...overrides,
  })

  it('aceita turno e intervalo que atravessam a meia-noite', () => {
    expect(() => validateScheduleDrafts([draft()])).not.toThrow()
    expect(() => validateScheduleDrafts([draft({ weekday: 2, is_day_off: true, start_time: null, end_time: null, break_start: null, break_end: null })])).not.toThrow()
  })

  it('recusa intervalo com início igual ao fim (mesma regra do banco)', () => {
    expect(() => validateScheduleDrafts([draft({ break_start: '23:00', break_end: '23:00' })])).toThrow(
      'Escala invalida: o intervalo precisa ter duracao maior que zero',
    )
  })

  it('recusa intervalo incompleto', () => {
    expect(() => validateScheduleDrafts([draft({ break_end: null })])).toThrow(
      'Escala invalida: informe inicio e fim do intervalo',
    )
  })

  it('recusa dia repetido e expediente sem início/término', () => {
    expect(() => validateScheduleDrafts([draft(), draft({ weekday: 1 })])).toThrow(
      'Escala invalida: cada dia da semana deve aparecer uma unica vez',
    )
    expect(() => validateScheduleDrafts([draft({ end_time: null })])).toThrow(
      'Escala invalida: informe inicio e termino do expediente',
    )
    expect(() => validateScheduleDrafts([])).toThrow(
      'Escala invalida: informe os dias da semana do membro',
    )
  })

  it('saveMemberSchedule não chama o servidor quando a escala é inválida', async () => {
    rpcMock.mockClear()
    await expect(saveMemberSchedule('mem-1', [draft({ break_start: '12:00', break_end: '12:00' })])).rejects.toThrow(
      'Escala invalida: o intervalo precisa ter duracao maior que zero',
    )
    expect(rpcMock).not.toHaveBeenCalled()
  })
})
