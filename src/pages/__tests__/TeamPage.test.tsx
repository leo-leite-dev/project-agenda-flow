import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'

import { AuthContext, type AuthContextValue, type UserEstablishment } from '../../contexts/AuthContext'
import { TeamPage } from '../TeamPage'
import type { TeamInvitation, TeamMember } from '../../lib/team'

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
    teamMock.listTeamMembers.mockRejectedValue(new Error('offline'))

    renderTeam(baseValue())

    expect(await screen.findByText(/Não foi possível carregar a equipe/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Tentar novamente/i })).toBeInTheDocument()
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
    fireEvent.click(within(dialog).getByRole('checkbox', { name: 'finances.read' }))

    fireEvent.click(within(dialog).getByRole('button', { name: /Salvar alterações/i }))

    await waitFor(() => {
      expect(teamMock.updateMemberRole).toHaveBeenCalledWith('mem-1', 'manager')
      expect(teamMock.setMemberPermissions).toHaveBeenCalledWith('mem-1', ['clients.read', 'finances.read'])
    })

    expect(await screen.findByText(/Membro atualizado com sucesso/i)).toBeInTheDocument()
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
    expect(screen.getByText(/Apenas o proprietário administra/i)).toBeInTheDocument()
  })
})
