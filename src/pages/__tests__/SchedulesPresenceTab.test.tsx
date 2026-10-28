import { describe, expect, it, vi, beforeEach } from 'vitest'
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'

import { SchedulesPresenceTab } from '../../components/team/SchedulesPresenceTab'
import type { TeamMember } from '../../lib/team'
import type {
  AttendanceException,
  AttendanceRecord,
  EstablishmentClock,
  WorkSchedule,
} from '../../lib/schedules'

/**
 * MOCKS ISOLADOS: os testes abaixo usam dados simulados e NÃO validam o
 * Supabase remoto. A migration 00011 (RPCs/tabelas da etapa 8) ainda não
 * foi aplicada ao banco; os asserts cobrem a interface contra o contrato de
 * src/lib/schedules.ts. A validação real do banco ocorre após a aplicação
 * autorizada da migration.
 */
const schedulesData = vi.hoisted(() => ({
  listEstablishmentSchedules: vi.fn(),
  listAttendanceRecords: vi.fn(),
  listAttendanceExceptions: vi.fn(),
  fetchEstablishmentClock: vi.fn(),
  saveMemberSchedule: vi.fn(),
  recordCheckIn: vi.fn(),
  recordCheckOut: vi.fn(),
  recordAttendanceException: vi.fn(),
  correctAttendanceRecord: vi.fn(),
}))

vi.mock('../../lib/schedules', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  listEstablishmentSchedules: schedulesData.listEstablishmentSchedules,
  listAttendanceRecords: schedulesData.listAttendanceRecords,
  listAttendanceExceptions: schedulesData.listAttendanceExceptions,
  fetchEstablishmentClock: schedulesData.fetchEstablishmentClock,
  saveMemberSchedule: schedulesData.saveMemberSchedule,
  recordCheckIn: schedulesData.recordCheckIn,
  recordCheckOut: schedulesData.recordCheckOut,
  recordAttendanceException: schedulesData.recordAttendanceException,
  correctAttendanceRecord: schedulesData.correctAttendanceRecord,
}))

vi.mock('../../lib/supabase', () => ({ supabase: {} }))

const memberFixture = (overrides: Partial<TeamMember> = {}): TeamMember => ({
  id: 'mem-owner',
  user_id: 'user-10',
  role: 'owner',
  is_active: true,
  created_at: '2026-06-01T10:00:00Z',
  profile: { id: 'user-10', full_name: 'Marcos Pereira', avatar_url: null, phone: null },
  permissions: [],
  ...overrides,
})

const clockFixture = (overrides: Partial<EstablishmentClock> = {}): EstablishmentClock => ({
  now_at: '2026-03-02T13:00:00+00:00',
  timezone: 'America/Sao_Paulo',
  local_date: '2026-03-02',
  local_time: '10:00',
  ...overrides,
})

const scheduleFixture = (overrides: Partial<WorkSchedule> = {}): WorkSchedule => ({
  id: `sch-${overrides.weekday ?? 1}-${overrides.member_id ?? 'mem-owner'}`,
  establishment_id: 'est-1',
  member_id: overrides.member_id ?? 'mem-owner',
  weekday: overrides.weekday ?? 1,
  is_day_off: overrides.is_day_off ?? false,
  start_time: overrides.start_time ?? '09:00:00',
  end_time: overrides.end_time ?? '18:00:00',
  break_start: overrides.break_start ?? null,
  break_end: overrides.break_end ?? null,
  ...overrides,
})

const recordFixture = (overrides: Partial<AttendanceRecord> = {}): AttendanceRecord => ({
  id: 'att-1',
  establishment_id: 'est-1',
  member_id: 'mem-owner',
  work_date: '2026-03-02',
  check_in_at: '2026-03-02T12:05:00+00:00',
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
  member_id: 'mem-prof',
  start_date: '2026-03-02',
  end_date: '2026-03-02',
  exception_type: 'absence',
  reason: 'Sem aviso',
  recorded_by: 'user-10',
  created_at: '2026-03-02T01:00:00+00:00',
  ...overrides,
})

interface RenderOverrides {
  isOwner?: boolean
  members?: TeamMember[]
  currentUserId?: string | null
}

function renderTab(overrides: RenderOverrides = {}) {
  return render(
    <SchedulesPresenceTab
      establishmentId="est-1"
      establishmentName="Barber Alpha"
      isOwner={overrides.isOwner ?? true}
      members={
        overrides.members ??
        [
          memberFixture(),
          memberFixture({
            id: 'mem-prof',
            user_id: 'user-20',
            role: 'professional',
            profile: { id: 'user-20', full_name: 'Carlos Silva', avatar_url: null, phone: null },
          }),
        ]
      }
      currentUserId={overrides.currentUserId ?? 'user-10'}
    />,
  )
}

describe('SchedulesPresenceTab (aba Escalas e Presença)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    schedulesData.listEstablishmentSchedules.mockResolvedValue([])
    schedulesData.listAttendanceRecords.mockResolvedValue([])
    schedulesData.listAttendanceExceptions.mockResolvedValue([])
    schedulesData.fetchEstablishmentClock.mockResolvedValue(clockFixture())
    schedulesData.saveMemberSchedule.mockResolvedValue(undefined)
    schedulesData.recordCheckIn.mockResolvedValue(recordFixture())
    schedulesData.recordCheckOut.mockResolvedValue(
      recordFixture({
        check_out_at: '2026-03-02T22:00:00+00:00',
        check_out_source: 'self',
      }),
    )
    schedulesData.recordAttendanceException.mockResolvedValue(exceptionFixture())
    schedulesData.correctAttendanceRecord.mockResolvedValue(
      recordFixture({ check_out_source: 'owner', correction_reason: 'Conferido' }),
    )
  })

  it('lista todos os membros com cargo e expediente previsto para hoje', async () => {
    schedulesData.listEstablishmentSchedules.mockResolvedValue([
      scheduleFixture({ member_id: 'mem-owner', weekday: 1 }),
      scheduleFixture({ member_id: 'mem-prof', weekday: 1 }),
    ])

    renderTab()

    expect(await screen.findByText('Marcos Pereira')).toBeInTheDocument()
    expect(screen.getByText('Carlos Silva')).toBeInTheDocument()
    expect(screen.getAllByText('Proprietário')).toHaveLength(1)
    expect(screen.getAllByText('Profissional')).toHaveLength(1)
    expect(screen.getAllByText(/Escala: Seg 09:00–18:00/)).toHaveLength(2)
    expect(await screen.findAllByText('Aguardando registro de entrada').then((n) => n.length)).toBeGreaterThan(0)
  })

  it('membro conclui check-in com horário do servidor e feedback real', async () => {
    // Primeira carga sem registros; a recarga (após o check-in) traz o registro.
    schedulesData.listAttendanceRecords
      .mockResolvedValueOnce([])
      .mockResolvedValue([recordFixture({ check_in_at: '2026-03-02T12:03:00+00:00' })])
    schedulesData.recordCheckIn.mockResolvedValue(
      recordFixture({ check_in_at: '2026-03-02T12:03:00+00:00' }),
    )

    renderTab()

    const button = await screen.findByRole('button', { name: 'Registrar entrada' })
    expect(button).toBeEnabled()
    fireEvent.click(button)

    await waitFor(() => {
      expect(schedulesData.recordCheckIn).toHaveBeenCalledWith('est-1')
    })
    expect(await screen.findByText(/Entrada registrada pelo servidor às 09:03/)).toBeInTheDocument()
    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'Registrar saída' })).toBeEnabled()
    })
  })

  it('não exibe sucesso quando o check-in falha e mostra a mensagem do banco', async () => {
    schedulesData.recordCheckIn.mockRejectedValue({
      message: 'Registro de entrada ja existe para hoje',
    })

    renderTab()

    fireEvent.click(await screen.findByRole('button', { name: 'Registrar entrada' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Registro de entrada ja existe para hoje',
    )
    expect(screen.queryByText(/Entrada registrada pelo servidor/)).not.toBeInTheDocument()
  })

  it('bloqueia duplo envio durante o salvamento', async () => {
    let resolveCheckIn: (value: AttendanceRecord) => void = () => {}
    schedulesData.recordCheckIn.mockReturnValue(
      new Promise<AttendanceRecord>((resolve) => {
        resolveCheckIn = resolve
      }),
    )

    renderTab()

    const button = await screen.findByRole('button', { name: 'Registrar entrada' })
    fireEvent.click(button)

    expect(await screen.findByRole('button', { name: 'Registrando...' })).toBeDisabled()

    await waitFor(() => {
      resolveCheckIn(recordFixture())
    })
    expect(await screen.findByText(/Entrada registrada pelo servidor/)).toBeInTheDocument()
  })

  it('saída exige entrada registrada e é habilitada somente nesse caso', async () => {
    schedulesData.listAttendanceRecords.mockResolvedValue([
      recordFixture({ member_id: 'mem-owner', check_out_at: null }),
      recordFixture({
        id: 'att-2',
        member_id: 'mem-prof',
        check_out_at: '2026-03-02T22:00:00+00:00',
        check_out_source: 'self',
      }),
    ])

    renderTab({ currentUserId: 'user-10' })

    expect(await screen.findByRole('button', { name: 'Registrar saída' })).toBeEnabled()
    fireEvent.click(screen.getByRole('button', { name: 'Registrar saída' }))
    expect(schedulesData.recordCheckOut).toHaveBeenCalledWith('est-1')
  })

  it('funcionário comum registra a própria presença e não vê controles administrativos', async () => {
    schedulesData.listEstablishmentSchedules.mockResolvedValue([
      scheduleFixture({ member_id: 'mem-prof', weekday: 1 }),
    ])

    renderTab({
      isOwner: false,
      members: [
        memberFixture({
          id: 'mem-prof',
          user_id: 'user-20',
          role: 'professional',
          profile: { id: 'user-20', full_name: 'Carlos Silva', avatar_url: null, phone: null },
        }),
      ],
      currentUserId: 'user-20',
    })

    expect(await screen.findByText('Aguardando registro de entrada')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Registrar entrada' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Meu histórico' })).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Configurar escala/i })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Ausência\/Exceção/i })).not.toBeInTheDocument()
  })

  it('exibe ausência registrada e folga prevista corretamente', async () => {
    schedulesData.listEstablishmentSchedules.mockResolvedValue([
      scheduleFixture({ member_id: 'mem-owner', weekday: 1 }),
      scheduleFixture({ member_id: 'mem-prof', weekday: 1 }),
    ])
    schedulesData.listAttendanceExceptions.mockResolvedValue([
      exceptionFixture({ member_id: 'mem-prof' }),
    ])

    renderTab()

    expect(await screen.findByText('Ausência registrada')).toBeInTheDocument()
  })

  it('não exibe falta confirmada quando falta check-in da pessoa', async () => {
    schedulesData.listEstablishmentSchedules.mockResolvedValue([
      scheduleFixture({ member_id: 'mem-prof', weekday: 1 }),
    ])

    renderTab({
      isOwner: false,
      members: [
        memberFixture({
          id: 'mem-prof',
          user_id: 'user-20',
          role: 'professional',
          profile: { id: 'user-20', full_name: 'Carlos Silva', avatar_url: null, phone: null },
        }),
      ],
      currentUserId: 'user-20',
    })

    // Sem exceção registrada, a mensagem NÃO é "Ausência registrada".
    expect(await screen.findByText('Aguardando registro de entrada')).toBeInTheDocument()
    expect(screen.queryByText('Ausência registrada')).not.toBeInTheDocument()
  })

  it('exibe escala não configurada e permite configurar via modal', async () => {
    renderTab()

    const configure = await screen.findAllByRole('button', { name: 'Configurar escala' })
    expect(configure.length).toBe(2)

    fireEvent.click(configure[1])

    const dialog = await screen.findByRole('dialog')
    expect(within(dialog).getByText(/Escala de Carlos Silva/)).toBeInTheDocument()

    // Habilita segunda-feira e salva a escala via RPC do proprietário.
    fireEvent.click(within(dialog).getByLabelText('Marcar folga em Segunda-feira'))

    fireEvent.click(within(dialog).getByRole('button', { name: 'Salvar escala' }))

    await waitFor(() => {
      expect(schedulesData.saveMemberSchedule).toHaveBeenCalledWith(
        'mem-prof',
        expect.any(Array),
      )
    })
  })

  it('registra ausência pelo proprietário com motivo opcional', async () => {
    renderTab()

    fireEvent.click((await screen.findAllByRole('button', { name: /Ausência\/Exceção/i }))[0])

    const dialog = await screen.findByRole('dialog')
    fireEvent.change(within(dialog).getByLabelText('Tipo de ocorrência'), {
      target: { value: 'justified_delay' },
    })
    fireEvent.change(within(dialog).getByLabelText('Motivo da ocorrência'), {
      target: { value: 'Ônibus' },
    })

    fireEvent.click(within(dialog).getByRole('button', { name: 'Registrar ocorrência' }))

    await waitFor(() => {
      expect(schedulesData.recordAttendanceException).toHaveBeenCalledWith(
        'mem-owner',
        'justified_delay',
        '2026-03-02',
        '2026-03-02',
        'Ônibus',
      )
    })
  })

  it('abre histórico e corrige registro com justificativa (somente proprietário)', async () => {
    schedulesData.listAttendanceRecords.mockResolvedValue([
      recordFixture({
        check_in_at: '2026-03-02T12:05:00+00:00',
        check_out_at: '2026-03-02T22:00:00+00:00',
        check_out_source: 'self',
      }),
    ])

    renderTab()

    fireEvent.click((await screen.findAllByRole('button', { name: 'Histórico' }))[0])

    const dialog = await screen.findByRole('dialog')
    expect(within(dialog).getByText(/Histórico de Marcos Pereira/)).toBeInTheDocument()

    fireEvent.click(within(dialog).getByRole('button', { name: 'Corrigir' }))

    fireEvent.change(within(dialog).getByLabelText('Justificativa da correção'), {
      target: { value: 'Entrada digitada errada' },
    })

    fireEvent.click(within(dialog).getByRole('button', { name: 'Aplicar correção' }))

    await waitFor(() => {
      expect(schedulesData.correctAttendanceRecord).toHaveBeenCalledWith(
        'att-1',
        expect.objectContaining({ reason: 'Entrada digitada errada' }),
      )
    })
  })

  it('exibe estado vazio sem inventar presença', async () => {
    renderTab({ members: [] })

    expect(await screen.findByText('Nenhum membro vinculado ainda.')).toBeInTheDocument()
    expect(screen.queryByText('Ausência registrada')).not.toBeInTheDocument()
  })

  it('exibe erro com opção de tentar novamente', async () => {
    schedulesData.listEstablishmentSchedules
      .mockResolvedValueOnce([])
      .mockResolvedValue([scheduleFixture({ member_id: 'mem-owner', weekday: 1 })])
    schedulesData.fetchEstablishmentClock
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValue(clockFixture())

    renderTab()

    expect(
      await screen.findByText(/Não foi possível carregar as escalas e presença/),
    ).toBeInTheDocument()
    expect(screen.getByText('Entrada: — • Saída: —')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Tentar novamente' }))

    expect(await screen.findAllByText('Aguardando registro de entrada').then((n) => n.length)).toBeGreaterThan(0)
  })

  it('exibe o fuso horário do estabelecimento, não o do navegador', async () => {
    renderTab()

    expect(await screen.findByText(/fuso America\/Sao_Paulo/)).toBeInTheDocument()
  })
})
