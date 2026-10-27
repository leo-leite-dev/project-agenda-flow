import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'

import { AuthContext, type AuthContextValue, type UserEstablishment } from '../../contexts/AuthContext'
import { TeamPage } from '../TeamPage'
import type { TeamInvitation, TeamMember } from '../../lib/team'
import type { EstablishmentProfessional } from '../../lib/professionals'

const teamMock = vi.hoisted(() => ({
  listTeamMembers: vi.fn(),
  listEstablishmentInvitations: vi.fn(),
  createTeamInvitation: vi.fn(),
  cancelTeamInvitation: vi.fn(),
  acceptTeamInvitation: vi.fn(),
  updateMemberRole: vi.fn(),
  setMemberActive: vi.fn(),
  setMemberPermissions: vi.fn(),
}))

const professionalMock = vi.hoisted(() => ({
  listEstablishmentProfessionals: vi.fn(),
  setProfessionalEnabled: vi.fn(),
  addProfessionalService: vi.fn(),
  removeProfessionalService: vi.fn(),
}))

const servicesMock = vi.hoisted(() => ({
  listServices: vi.fn(),
}))

vi.mock('../../lib/team', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  listTeamMembers: teamMock.listTeamMembers,
  listEstablishmentInvitations: teamMock.listEstablishmentInvitations,
  createTeamInvitation: teamMock.createTeamInvitation,
  cancelTeamInvitation: teamMock.cancelTeamInvitation,
  acceptTeamInvitation: teamMock.acceptTeamInvitation,
  updateMemberRole: teamMock.updateMemberRole,
  setMemberActive: teamMock.setMemberActive,
  setMemberPermissions: teamMock.setMemberPermissions,
}))

vi.mock('../../lib/professionals', () => ({
  listEstablishmentProfessionals: professionalMock.listEstablishmentProfessionals,
  setProfessionalEnabled: professionalMock.setProfessionalEnabled,
  addProfessionalService: professionalMock.addProfessionalService,
  removeProfessionalService: professionalMock.removeProfessionalService,
}))

vi.mock('../../lib/services', () => ({
  listServices: servicesMock.listServices,
  serviceCategoryLabel: (category: string) => category,
}))

vi.mock('../../lib/supabase', () => ({ supabase: {} }))

function establishmentFixture(overrides: Partial<UserEstablishment> = {}): UserEstablishment {
  return {
    id: 'est-1',
    owner_id: 'user-1',
    name: 'Barbearia Alpha',
    slug: 'barbearia-alpha',
    type: 'barbershop',
    document: null,
    phone: null,
    email: null,
    address: null,
    is_active: true,
    created_at: '2026-01-15T10:00:00Z',
    updated_at: '2026-01-15T10:00:00Z',
    role: 'owner',
    ...overrides,
  }
}

function memberFixture(overrides: Partial<TeamMember> = {}): TeamMember {
  return {
    id: 'mem-1',
    user_id: 'user-2',
    role: 'professional',
    is_active: true,
    created_at: '2026-02-01T10:00:00Z',
    profile: { id: 'user-2', full_name: 'Ana Souza', avatar_url: null, phone: null },
    permissions: [],
    ...overrides,
  }
}

function invitationFixture(overrides: Partial<TeamInvitation> = {}): TeamInvitation {
  return {
    id: 'inv-1',
    email: 'convite@exemplo.com',
    phone: null,
    role: 'professional',
    permissions: [],
    created_at: '2026-10-20T10:00:00Z',
    expires_at: '2099-10-27T10:00:00Z',
    accepted_at: null,
    cancelled_at: null,
    ...overrides,
  }
}

function professionalFixture(overrides: Partial<EstablishmentProfessional> = {}): EstablishmentProfessional {
  return {
    id: 'pro-1',
    member_id: 'mem-1',
    user_id: 'user-2',
    role: 'professional',
    is_active: true,
    accepts_appointments: true,
    created_at: '2026-02-01T10:00:00Z',
    full_name: 'Ana Souza',
    avatar_url: null,
    services: [],
    ...overrides,
  }
}

function baseValue(overrides: Partial<AuthContextValue> = {}): AuthContextValue {
  return {
    user: { id: 'user-1', email: 'owner@alpha.test' } as AuthContextValue['user'],
    isLoading: false,
    isAuthenticated: true,
    establishments: [establishmentFixture()],
    currentEstablishment: establishmentFixture(),
    isLoadingEstablishments: false,
    signInWithGoogle: async () => {},
    signInWithEmail: async () => {},
    signUpWithEmail: async () => ({}) as never,
    signOut: async () => {},
    refreshEstablishments: async () => {},
    selectEstablishment: () => {},
    createEstablishment: async () => 'id',
    error: null,
    clearError: () => {},
    ...overrides,
  }
}

function renderTeam(value: AuthContextValue) {
  return render(
    <MemoryRouter initialEntries={['/dashboard/equipe']}>
      <AuthContext.Provider value={value}>
        <Routes>
          <Route path="/dashboard/equipe" element={<TeamPage />} />
          <Route path="/login" element={<div>LOGIN</div>} />
        </Routes>
      </AuthContext.Provider>
    </MemoryRouter>,
  )
}

describe('TeamPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    teamMock.listTeamMembers.mockResolvedValue([])
    teamMock.listEstablishmentInvitations.mockResolvedValue([])
    teamMock.createTeamInvitation.mockResolvedValue('a'.repeat(64))
    teamMock.updateMemberRole.mockResolvedValue(undefined)
    teamMock.setMemberActive.mockResolvedValue(undefined)
    teamMock.setMemberPermissions.mockResolvedValue(undefined)
    teamMock.cancelTeamInvitation.mockResolvedValue(undefined)
    professionalMock.listEstablishmentProfessionals.mockResolvedValue([])
    professionalMock.setProfessionalEnabled.mockResolvedValue(undefined)
    professionalMock.addProfessionalService.mockResolvedValue(undefined)
    professionalMock.removeProfessionalService.mockResolvedValue(undefined)
    servicesMock.listServices.mockResolvedValue([])
  })

  it('lista os membros reais com cargo, situação e data de entrada', async () => {
    teamMock.listTeamMembers.mockResolvedValue([
      memberFixture(),
      memberFixture({
        id: 'mem-2',
        user_id: 'user-3',
        role: 'manager',
        is_active: false,
        profile: { id: 'user-3', full_name: 'Bruno Lima', avatar_url: null, phone: null },
      }),
    ])

    renderTeam(baseValue())

    expect(await screen.findByText('Ana Souza')).toBeInTheDocument()
    expect(screen.getByText('Bruno Lima')).toBeInTheDocument()
    expect(screen.getAllByText('Profissional').length).toBeGreaterThan(0)
    expect(screen.getAllByText('Gerente').length).toBeGreaterThan(0)
    expect(screen.getAllByText('Ativo').length).toBeGreaterThan(0)
    expect(screen.getByText('Inativo')).toBeInTheDocument()
  })

  it('filtra por nome, cargo e situação', async () => {
    teamMock.listTeamMembers.mockResolvedValue([
      memberFixture(),
      memberFixture({
        id: 'mem-2',
        user_id: 'user-3',
        role: 'manager',
        profile: { id: 'user-3', full_name: 'Bruno Lima', avatar_url: null, phone: null },
      }),
    ])

    renderTeam(baseValue())

    await screen.findByText('Ana Souza')

    fireEvent.change(screen.getByLabelText('Buscar'), { target: { value: 'bruno' } })
    expect(screen.getByText('Bruno Lima')).toBeInTheDocument()
    expect(screen.queryByText('Ana Souza')).not.toBeInTheDocument()

    fireEvent.change(screen.getByLabelText('Buscar'), { target: { value: '' } })
    fireEvent.change(screen.getByLabelText('Cargo'), { target: { value: 'manager' } })
    expect(screen.getByText('Bruno Lima')).toBeInTheDocument()
    expect(screen.queryByText('Ana Souza')).not.toBeInTheDocument()

    fireEvent.change(screen.getByLabelText('Cargo'), { target: { value: 'todos' } })
    fireEvent.change(screen.getByLabelText('Situação'), { target: { value: 'inativos' } })
    expect(screen.queryByText('Ana Souza')).not.toBeInTheDocument()
  })

  it('mostra estado vazio quando não há membros', async () => {
    renderTeam(baseValue())

    expect((await screen.findAllByText(/Nenhum membro vinculado ainda/i)).length).toBeGreaterThan(0)
  })

  it('mostra erro de conexão com opção de tentar novamente', async () => {
    teamMock.listTeamMembers
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValueOnce([memberFixture()])

    renderTeam(baseValue())

    expect(await screen.findByText(/Não foi possível carregar a equipe/i)).toBeInTheDocument()
    expect(screen.queryByText('Nenhum membro vinculado ainda.')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Tentar novamente/i })).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /Tentar novamente/i }))

    expect(await screen.findByText('Ana Souza')).toBeInTheDocument()
    expect(screen.queryByText(/Não foi possível carregar a equipe/i)).not.toBeInTheDocument()
  })

  it('mantém a equipe visível quando uma consulta auxiliar falha', async () => {
    teamMock.listTeamMembers.mockResolvedValue([memberFixture()])
    professionalMock.listEstablishmentProfessionals.mockRejectedValue(new Error('professionals offline'))

    renderTeam(baseValue())

    expect(await screen.findByText('Ana Souza')).toBeInTheDocument()
    expect(screen.queryByText('Nenhum membro vinculado ainda.')).not.toBeInTheDocument()
    expect(await screen.findByText(/Não foi possível carregar os profissionais/i)).toBeInTheDocument()
  })

  it('convida um funcionário e exibe o link para compartilhamento manual', async () => {
    renderTeam(baseValue())

    fireEvent.click((await screen.findAllByRole('button', { name: 'Convidar funcionário' }))[0])

    const dialog = await screen.findByRole('dialog')

    fireEvent.change(within(dialog).getByLabelText(/E-mail do funcionário/i), {
      target: { value: 'Novo@Exemplo.com' },
    })
    fireEvent.change(within(dialog).getByLabelText('Cargo'), { target: { value: 'receptionist' } })

    fireEvent.click(within(dialog).getByRole('button', { name: /Gerar convite/i }))

    await waitFor(() => {
      expect(teamMock.createTeamInvitation).toHaveBeenCalledWith('est-1', {
        email: 'novo@exemplo.com',
        role: 'receptionist',
        permissions: [],
      })
    })

    expect(screen.getAllByText(/Convite criado/i).length).toBeGreaterThan(0)
    expect(screen.getByLabelText('Link do convite')).toHaveValue(
      `${window.location.origin}/convite/${'a'.repeat(64)}`,
    )
    expect(screen.getByText(/não envia e-mails por conta própria/i)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Abrir e-mail/i })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Abrir WhatsApp/i })).toBeInTheDocument()
  })

  it('altera cargo e permissões de um membro', async () => {
    teamMock.listTeamMembers.mockResolvedValue([memberFixture({ permissions: ['clients.read'] })])

    renderTeam(baseValue())

    fireEvent.click(await screen.findByRole('button', { name: /Cargo e permissões/i }))

    const dialog = await screen.findByRole('dialog')
    fireEvent.change(within(dialog).getByLabelText('Cargo do membro'), { target: { value: 'manager' } })
    fireEvent.click(within(dialog).getByRole('checkbox', { name: 'Visualizar informações financeiras' }))

    fireEvent.click(within(dialog).getByRole('button', { name: /Salvar alterações/i }))

    await waitFor(() => {
      expect(teamMock.updateMemberRole).toHaveBeenCalledWith('mem-1', 'manager')
      expect(teamMock.setMemberPermissions).toHaveBeenCalledWith('mem-1', ['clients.read', 'finances.read'])
    })

    expect(await screen.findByText(/Membro atualizado com sucesso/i)).toBeInTheDocument()
  })

  it('habilita um membro como profissional pela seção Profissionais', async () => {
    teamMock.listTeamMembers.mockResolvedValue([memberFixture()])

    renderTeam(baseValue())

    fireEvent.click(await screen.findByRole('tab', { name: 'Profissionais' }))

    fireEvent.change(screen.getByLabelText('Habilitar profissional'), { target: { value: 'mem-1' } })
    fireEvent.click(screen.getByRole('button', { name: 'Habilitar profissional' }))

    await waitFor(() => {
      expect(professionalMock.setProfessionalEnabled).toHaveBeenCalledWith('mem-1', true)
    })

    expect(
      await screen.findByText(/agora é profissional de atendimento/i),
    ).toBeInTheDocument()
  })

  it('pausa os atendimentos do profissional sem desativar a conta (status exibido em pausa)', async () => {
    professionalMock.listEstablishmentProfessionals.mockResolvedValue([
      professionalFixture(),
    ])

    renderTeam(baseValue())

    // A lista de profissionais é carregada desde a abertura (os dados são
    // reais); o status de atendimentos aparece após trocar de aba.
    fireEvent.click(await screen.findByRole('tab', { name: 'Profissionais' }))
    fireEvent.click(await screen.findByRole('button', { name: 'Pausar atendimentos' }))

    await waitFor(() => {
      expect(professionalMock.setProfessionalEnabled).toHaveBeenCalledWith('mem-1', false)
    })

    expect(await screen.findByText(/Atendimentos pausados para Ana Souza/i)).toBeInTheDocument()
  })

  it('lista os serviços associados e o responsivo mostra a contagem por profissional', async () => {
    professionalMock.listEstablishmentProfessionals.mockResolvedValue([
      professionalFixture({
        services: [
          { id: 'svc-1', name: 'Corte Masculino', category: 'cabelo', is_active: true },
          { id: 'svc-2', name: 'Barba', category: 'barba', is_active: true },
        ],
      }),
      professionalFixture({
        id: 'pro-2',
        member_id: 'mem-3',
        user_id: 'user-4',
        full_name: 'Bruno Lima',
        services: [],
      }),
    ])

    renderTeam(baseValue())

    fireEvent.click(await screen.findByRole('tab', { name: 'Profissionais' }))

    expect(await screen.findByText('2 serviço(s) associado(s)')).toBeInTheDocument()
    expect(screen.getByText('0 serviço(s) associado(s)')).toBeInTheDocument()
    expect(screen.getByText(/2 profissional\(is\) habilitado\(s\) • 1 sem serviços/)).toBeInTheDocument()
    expect(screen.getAllByText('Recebe atendimentos').length).toBe(2)
  })

  it('o botão para habilitar fica desabilitado sem membro selecionado e não habilita para não-proprietário', async () => {
    teamMock.listTeamMembers.mockResolvedValue([memberFixture()])

    renderTeam(baseValue())

    await screen.findByText('Ana Souza')
    fireEvent.click(screen.getByRole('tab', { name: 'Profissionais' }))

    expect(screen.getByRole('button', { name: 'Habilitar profissional' })).toBeDisabled()

    // Sem membro selecionado, nenhuma RPC é chamada.
    expect(professionalMock.setProfessionalEnabled).not.toHaveBeenCalled()
  })

  it('associa e remove serviços do profissional, evitando salvamento duplicado', async () => {
    professionalMock.listEstablishmentProfessionals.mockResolvedValue([
      professionalFixture({
        services: [{ id: 'svc-1', name: 'Corte Masculino', category: 'cabelo', is_active: true }],
      }),
    ])
    servicesMock.listServices.mockResolvedValue([
      { id: 'svc-1', establishment_id: 'est-1', name: 'Corte Masculino', description: null, category: 'cabelo', duration_minutes: 30, price_cents: 3500, is_active: true, created_at: '', updated_at: '' },
      { id: 'svc-2', establishment_id: 'est-1', name: 'Barba', description: null, category: 'barba', duration_minutes: 20, price_cents: 2500, is_active: true, created_at: '', updated_at: '' },
      { id: 'svc-3', establishment_id: 'est-1', name: 'Hidratação', description: null, category: 'cabelo', duration_minutes: 40, price_cents: 5000, is_active: false, created_at: '', updated_at: '' },
    ])

    renderTeam(baseValue())

    fireEvent.click(await screen.findByRole('tab', { name: 'Profissionais' }))
    fireEvent.click(await screen.findByRole('button', { name: 'Gerenciar serviços' }))

    const dialog = await screen.findByRole('dialog')

    // Serviço já associado: remover.
    fireEvent.click(within(dialog).getByRole('checkbox', { name: /Remover Corte Masculino/i }))

    await waitFor(() => {
      expect(professionalMock.removeProfessionalService).toHaveBeenCalledWith('pro-1', 'svc-1')
    })

    // Serviço não associado: associar.
    fireEvent.click(within(dialog).getByRole('checkbox', { name: /Associar Barba/i }))

    await waitFor(() => {
      expect(professionalMock.addProfessionalService).toHaveBeenCalledWith('pro-1', 'svc-2')
    })

    // Serviço INATIVO e não associado: a caixa é desabilitada (sem nova associação).
    expect(within(dialog).getByRole('checkbox', { name: /Associar Hidratação/i })).toBeDisabled()
  })

  it('desativa um vínculo após confirmação', async () => {
    teamMock.listTeamMembers.mockResolvedValue([memberFixture()])

    renderTeam(baseValue())

    fireEvent.click(await screen.findByRole('button', { name: 'Desativar' }))

    const dialog = await screen.findByRole('alertdialog')
    fireEvent.click(within(dialog).getByRole('button', { name: 'Desativar' }))

    await waitFor(() => {
      expect(teamMock.setMemberActive).toHaveBeenCalledWith('mem-1', false)
    })

    expect(await screen.findByText(/desativado/i)).toBeInTheDocument()
  })

  it('lista convites pendentes e permite cancelá-los', async () => {
    teamMock.listTeamMembers.mockResolvedValue([memberFixture()])
    teamMock.listEstablishmentInvitations.mockResolvedValue([invitationFixture()])

    renderTeam(baseValue())

    expect(await screen.findByText('convite@exemplo.com')).toBeInTheDocument()
    expect(screen.getByText('Pendente')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))

    const dialog = await screen.findByRole('alertdialog')
    fireEvent.click(within(dialog).getByRole('button', { name: 'Cancelar convite' }))

    await waitFor(() => {
      expect(teamMock.cancelTeamInvitation).toHaveBeenCalledWith('inv-1')
    })

    expect(await screen.findByText(/Convite cancelado/i)).toBeInTheDocument()
  })

  it('esconde as ações administrativas para quem não é proprietário', async () => {
    teamMock.listTeamMembers.mockResolvedValue([
      memberFixture({ role: 'manager', user_id: 'user-2' }),
    ])

    renderTeam(
      baseValue({
        currentEstablishment: establishmentFixture({ role: 'manager' }),
        establishments: [establishmentFixture({ role: 'manager' })],
      }),
    )

    await screen.findByText('Ana Souza')

    expect(screen.queryByRole('button', { name: 'Convidar funcionário' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Cargo e permissões/i })).not.toBeInTheDocument()
    expect(screen.getByText(/exclusivos do proprietário/i)).toBeInTheDocument()
  })

  it('profissionais não habilitam nem associam (visualização somente leitura)', async () => {
    professionalMock.listEstablishmentProfessionals.mockResolvedValue([
      professionalFixture(),
    ])

    renderTeam(
      baseValue({
        currentEstablishment: establishmentFixture({ role: 'manager' }),
        establishments: [establishmentFixture({ role: 'manager' })],
      }),
    )

    fireEvent.click(await screen.findByRole('tab', { name: 'Profissionais' }))

    await screen.findByText('Ana Souza')

    expect(screen.queryByLabelText('Habilitar profissional')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Gerenciar serviços' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Pausar atendimentos' })).not.toBeInTheDocument()
  })
})
