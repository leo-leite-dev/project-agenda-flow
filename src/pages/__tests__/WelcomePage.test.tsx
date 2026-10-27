import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'

import { AuthContext, type AuthContextValue } from '../../contexts/AuthContext'
import { WelcomePage } from '../WelcomePage'
import type { PendingInvitation } from '../../lib/team'

const onboardingMock = vi.hoisted(() => ({
  getMyPendingInvitations: vi.fn(),
  listTeamMembers: vi.fn(),
  listEstablishmentInvitations: vi.fn(),
  acceptTeamInvitation: vi.fn(),
}))

vi.mock('../../lib/team', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  getMyPendingInvitations: onboardingMock.getMyPendingInvitations,
  listTeamMembers: onboardingMock.listTeamMembers,
  listEstablishmentInvitations: onboardingMock.listEstablishmentInvitations,
  acceptTeamInvitation: onboardingMock.acceptTeamInvitation,
}))

vi.mock('../../lib/supabase', () => ({ supabase: {} }))

function baseValue(overrides: Partial<AuthContextValue> = {}): AuthContextValue {
  return {
    user: { id: 'user-2', email: 'carlos@exemplo.com' } as AuthContextValue['user'],
    isLoading: false,
    isAuthenticated: true,
    establishments: [],
    currentEstablishment: null,
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

function renderWelcome(value: AuthContextValue) {
  return render(
    <MemoryRouter initialEntries={['/welcome']}>
      <AuthContext.Provider value={value}>
        <Routes>
          <Route path="/welcome" element={<WelcomePage />} />
          <Route path="/establishment/new" element={<div>NOVO ESTABELECIMENTO</div>} />
          <Route path="/convite/abc" element={<div>CONVITE</div>} />
          <Route path="/login" element={<div>LOGIN</div>} />
        </Routes>
      </AuthContext.Provider>
    </MemoryRouter>,
  )
}

describe('WelcomePage (onboarding)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    onboardingMock.getMyPendingInvitations.mockResolvedValue([])
    window.sessionStorage.clear()
  })

  it('convida a criar o estabelecimento quando não há vínculo nem convite', async () => {
    renderWelcome(baseValue())

    expect(
      await screen.findByRole('button', { name: /Cadastrar estabelecimento/i }),
    ).toBeInTheDocument()
    expect(screen.queryByText(/Aceitar convite/i)).not.toBeInTheDocument()
  })

  it('NÃO exige criar estabelecimento quando há convite pendente', async () => {
    const invitation: PendingInvitation = {
      establishment_id: 'est-9',
      establishment_name: 'BarbaLeo',
      role: 'professional',
      expires_at: '2099-01-01T00:00:00Z',
    }
    onboardingMock.getMyPendingInvitations.mockResolvedValue([invitation])
    window.sessionStorage.setItem('agenda-flow:pending-invitation', '/convite/abc')

    renderWelcome(baseValue())

    expect(await screen.findByText('BarbaLeo')).toBeInTheDocument()
    expect(screen.getByText('Profissional')).toBeInTheDocument()
    expect(screen.getByText(/não é necessário criar uma empresa nova/i)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Aceitar convite/i })).toBeInTheDocument()
    // A criação continua disponível como opção secundária.
    expect(screen.getByRole('button', { name: /Cadastrar estabelecimento/i })).toBeInTheDocument()
  })

  it('orienta a buscar o link quando há convite pendente sem caminho preservado', async () => {
    onboardingMock.getMyPendingInvitations.mockResolvedValue([
      {
        establishment_id: 'est-9',
        establishment_name: 'BarbaLeo',
        role: 'professional',
        expires_at: '2099-01-01T00:00:00Z',
      },
    ])

    renderWelcome(baseValue())

    expect(await screen.findByText(/Abra o link de convite enviado pelo proprietário/i)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Aceitar convite/i })).not.toBeInTheDocument()
  })
})
