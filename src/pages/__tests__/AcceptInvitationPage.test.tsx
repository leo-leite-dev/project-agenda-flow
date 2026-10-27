import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'

import { AuthContext, type AuthContextValue } from '../../contexts/AuthContext'
import { AcceptInvitationPage } from '../AcceptInvitationPage'

const teamMock = vi.hoisted(() => ({
  acceptTeamInvitation: vi.fn(),
  listTeamMembers: vi.fn(),
  listEstablishmentInvitations: vi.fn(),
}))

vi.mock('../../lib/team', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  acceptTeamInvitation: teamMock.acceptTeamInvitation,
  listTeamMembers: teamMock.listTeamMembers,
  listEstablishmentInvitations: teamMock.listEstablishmentInvitations,
}))

vi.mock('../../lib/supabase', () => ({ supabase: {} }))

const TOKEN = 'a'.repeat(64)

function baseValue(overrides: Partial<AuthContextValue> = {}): AuthContextValue {
  return {
    user: { id: 'user-2', email: 'funcionario@exemplo.com' } as AuthContextValue['user'],
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

function renderPage(token: string, value: AuthContextValue) {
  return render(
    <MemoryRouter initialEntries={[`/convite/${token}`]}>
      <AuthContext.Provider value={value}>
        <Routes>
          <Route path="/convite/:token" element={<AcceptInvitationPage />} />
          <Route path="/login" element={<div>LOGIN</div>} />
          <Route path="/dashboard" element={<div>DASHBOARD</div>} />
        </Routes>
      </AuthContext.Provider>
    </MemoryRouter>,
  )
}

describe('AcceptInvitationPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    teamMock.acceptTeamInvitation.mockResolvedValue('mem-1')
  })

  it('recusa um token com formato inválido', () => {
    renderPage('token-invalido', baseValue())

    expect(screen.getByText(/Convite inválido/i)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Aceitar convite/i })).not.toBeInTheDocument()
  })

  it('exige autenticação para aceitar o convite', () => {
    renderPage(TOKEN, baseValue({ isAuthenticated: false, user: null }))

    expect(screen.getByText(/Você foi convidado\(a\)/i)).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Entrar para aceitar/i })).toHaveAttribute(
      'href',
      `/login?next=${encodeURIComponent(`/convite/${TOKEN}`)}`,
    )
  })

  it('aceita o convite quando o usuário está autenticado', async () => {
    renderPage(TOKEN, baseValue())

    expect(screen.getByRole('heading', { name: /Aceitar convite/i })).toBeInTheDocument()
    expect(screen.getByText(/funcionario@exemplo.com/i)).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /Aceitar convite/i }))

    await waitFor(() => {
      expect(teamMock.acceptTeamInvitation).toHaveBeenCalledWith(TOKEN)
    })

    expect(await screen.findByText(/Convite aceito/i)).toBeInTheDocument()
  })

  it('exibe o erro devolvido pelo banco (convite expirado, cancelado ou identidade diferente)', async () => {
    teamMock.acceptTeamInvitation.mockRejectedValue(
      new Error('Convite invalido, expirado ou ja utilizado'),
    )

    renderPage(TOKEN, baseValue())

    fireEvent.click(screen.getByRole('button', { name: /Aceitar convite/i }))

    expect(
      await screen.findByText(/Convite invalido, expirado ou ja utilizado/i),
    ).toBeInTheDocument()
  })
})
