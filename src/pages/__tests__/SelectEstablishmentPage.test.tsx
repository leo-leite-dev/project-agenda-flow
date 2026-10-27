import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import type { AuthResponse } from '@supabase/supabase-js'

import { AuthContext, type AuthContextValue, type UserEstablishment } from '../../contexts/AuthContext'
import { SelectEstablishmentPage } from '../SelectEstablishmentPage'

function establishmentFixture(
  id: string,
  overrides: Partial<UserEstablishment> = {},
): UserEstablishment {
  return {
    id,
    owner_id: 'user-1',
    name: `Estabelecimento ${id}`,
    slug: `estabelecimento-${id}`,
    type: 'barbershop',
    document: null,
    phone: null,
    email: null,
    address: { city: 'São Paulo', state: 'SP' },
    is_active: true,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    role: 'owner',
    ...overrides,
  }
}

function baseValue(overrides: Partial<AuthContextValue> = {}): AuthContextValue {
  return {
    user: { id: 'user-1', email: 'user@agenda.flow.test' } as AuthContextValue['user'],
    isLoading: false,
    isAuthenticated: true,
    establishments: [],
    currentEstablishment: null,
    isLoadingEstablishments: false,
    signInWithGoogle: async () => {},
    signInWithEmail: async () => {},
    signUpWithEmail: async () => ({}) as AuthResponse['data'],
    signOut: vi.fn(async () => {}),
    refreshEstablishments: async () => {},
    selectEstablishment: vi.fn(),
    createEstablishment: async () => 'id',
    error: null,
    clearError: () => {},
    ...overrides,
  }
}

function renderSelection(value: AuthContextValue) {
  return render(
    <MemoryRouter initialEntries={['/select-establishment']}>
      <AuthContext.Provider value={value}>
        <Routes>
          <Route path="/select-establishment" element={<SelectEstablishmentPage />} />
          <Route path="/dashboard" element={<div>DASHBOARD</div>} />
          <Route path="/welcome" element={<div>WELCOME</div>} />
          <Route path="/login" element={<div>LOGIN</div>} />
        </Routes>
      </AuthContext.Provider>
    </MemoryRouter>,
  )
}

describe('SelectEstablishmentPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('mostra cada estabelecimento acessível uma única vez', () => {
    const barberLeo = establishmentFixture('est-barberleo', { name: 'BarberLeo' })

    renderSelection(
      baseValue({
        establishments: [
          barberLeo,
          establishmentFixture('est-barberleo', { name: 'BarberLeo', role: 'professional' }),
          establishmentFixture('est-salao', { name: 'Salão Aurora' }),
        ],
      }),
    )

    expect(screen.getAllByText('BarberLeo')).toHaveLength(1)
    expect(screen.getAllByText('Salão Aurora')).toHaveLength(1)
  })

  it('redireciona para o dashboard ao escolher o estabelecimento', async () => {
    const selectEstablishment = vi.fn()
    const barberLeo = establishmentFixture('est-barberleo', { name: 'BarberLeo' })

    renderSelection(
      baseValue({
        establishments: [barberLeo, establishmentFixture('est-outro', { name: 'Salão Aurora' })],
        selectEstablishment,
      }),
    )

    fireEvent.click(screen.getByText('BarberLeo'))

    await waitFor(() => {
      expect(selectEstablishment).toHaveBeenCalledWith(barberLeo)
    })
    expect(await screen.findByText('DASHBOARD')).toBeInTheDocument()
  })

  it('entra direto no dashboard quando há um único estabelecimento', async () => {
    const selectEstablishment = vi.fn()

    renderSelection(
      baseValue({
        establishments: [establishmentFixture('est-barberleo', { name: 'BarberLeo' })],
        selectEstablishment,
      }),
    )

    await waitFor(() => {
      expect(selectEstablishment).toHaveBeenCalledTimes(1)
    })
    expect(await screen.findByText('DASHBOARD')).toBeInTheDocument()
  })

  it('permite escolher entre dois estabelecimentos distintos', async () => {
    const selectEstablishment = vi.fn()

    renderSelection(
      baseValue({
        establishments: [
          establishmentFixture('est-barberleo', { name: 'BarberLeo' }),
          establishmentFixture('est-salao', { name: 'Salão Aurora' }),
        ],
        selectEstablishment,
      }),
    )

    fireEvent.click(screen.getByText('Salão Aurora'))

    await waitFor(() => {
      expect(selectEstablishment).toHaveBeenCalledWith(
        expect.objectContaining({ id: 'est-salao' }),
      )
    })
    expect(await screen.findByText('DASHBOARD')).toBeInTheDocument()
  })

  it('leva ao onboarding quando o usuário não tem vínculo ativo', () => {
    renderSelection(baseValue({ establishments: [] }))

    expect(screen.getByText('WELCOME')).toBeInTheDocument()
  })

  it('leva ao login quando não há sessão', () => {
    renderSelection(baseValue({ isAuthenticated: false, user: null }))

    expect(screen.getByText('LOGIN')).toBeInTheDocument()
  })
})
