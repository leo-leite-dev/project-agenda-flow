import { describe, expect, it, vi, beforeEach } from 'vitest'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'

const mocks = vi.hoisted(() => ({
  ensureProfile: vi.fn(async () => 'profile-id'),
  getCurrentSession: vi.fn(),
  getUserEstablishments: vi.fn(async () => [] as unknown[]),
  onAuthStateChange: vi.fn(() => ({ unsubscribe: vi.fn() })),
  createEstablishment: vi.fn(async () => 'establishment-id'),
  signInWithGoogle: vi.fn(async () => ({})),
  signInWithEmail: vi.fn(async () => ({ user: { id: 'user-1' } })),
  signUpWithEmail: vi.fn(async () => ({ user: { id: 'user-1' } })),
  signOut: vi.fn(async () => undefined),
}))

vi.mock('../../lib/supabase', () => mocks)

import { AuthProvider } from '../AuthProvider'
import { useAuth } from '../../hooks/useAuth'

const FAKE_USER = { id: 'user-1', email: 'user@agenda.flow.test' }

function establishmentFixture(id: string, overrides: Record<string, unknown> = {}) {
  return {
    id,
    owner_id: 'user-1',
    name: `Estabelecimento ${id}`,
    slug: `estabelecimento-${id}`,
    type: 'barbershop',
    document: null,
    phone: null,
    email: null,
    address: null,
    is_active: true,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    role: 'owner',
    ...overrides,
  }
}

function Consumer() {
  const auth = useAuth()

  return (
    <div>
      <span data-testid="establishment-count">{auth.establishments.length}</span>
      <span data-testid="is-authenticated">{String(auth.isAuthenticated)}</span>
      <span data-testid="active-establishment">{auth.currentEstablishment?.id ?? 'nenhum'}</span>
      <button
        type="button"
        onClick={() =>
          auth.createEstablishment({
            name: 'Barbearia Teste',
            type: 'barbershop',
            slug: 'barbearia-teste',
          })
        }
      >
        criar
      </button>
      <button
        type="button"
        onClick={() => auth.selectEstablishment(auth.establishments[1] ?? null)}
      >
        escolher o segundo
      </button>
    </div>
  )
}

function renderProvider() {
  return render(
    <AuthProvider>
      <Consumer />
    </AuthProvider>,
  )
}

describe('AuthProvider profile provisioning', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    window.localStorage.clear()
    mocks.getCurrentSession.mockResolvedValue({ user: FAKE_USER })
    mocks.getUserEstablishments.mockResolvedValue([])
    mocks.ensureProfile.mockResolvedValue('profile-id')
  })

  it('ensures the profile exists before loading the establishments', async () => {
    renderProvider()

    await waitFor(() => {
      expect(mocks.ensureProfile).toHaveBeenCalledTimes(1)
      expect(mocks.getUserEstablishments).toHaveBeenCalledTimes(1)
    })

    expect(mocks.ensureProfile.mock.invocationCallOrder[0]).toBeLessThan(
      mocks.getUserEstablishments.mock.invocationCallOrder[0],
    )
  })

  it('keeps the session working when the profile RPC fails', async () => {
    mocks.ensureProfile.mockRejectedValue(new Error('ensure_profile unavailable'))

    renderProvider()

    await waitFor(() => {
      expect(mocks.getUserEstablishments).toHaveBeenCalledTimes(1)
    })

    expect(await screen.findByTestId('is-authenticated')).toHaveTextContent('true')
  })

  it('calls ensure_profile only once per session', async () => {
    renderProvider()

    await waitFor(() => {
      expect(mocks.ensureProfile).toHaveBeenCalledTimes(1)
    })

    await new Promise((resolve) => setTimeout(resolve, 20))
    expect(mocks.ensureProfile).toHaveBeenCalledTimes(1)
  })

  it('creates establishments with the type informed by the user', async () => {
    renderProvider()

    await waitFor(() => {
      expect(mocks.getUserEstablishments).toHaveBeenCalled()
    })

    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'criar' }))
    })

    await waitFor(() => {
      expect(mocks.createEstablishment).toHaveBeenCalledWith({
        name: 'Barbearia Teste',
        type: 'barbershop',
        slug: 'barbearia-teste',
      })
    })
  })
})

describe('AuthProvider vínculos do usuário autenticado', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    window.localStorage.clear()
    mocks.getCurrentSession.mockResolvedValue({ user: FAKE_USER })
    mocks.ensureProfile.mockResolvedValue('profile-id')
  })

  it('consulta os vínculos do usuário autenticado (não os de outras pessoas)', async () => {
    mocks.getUserEstablishments.mockResolvedValue([establishmentFixture('est-1')])

    renderProvider()

    await waitFor(() => {
      expect(mocks.getUserEstablishments).toHaveBeenCalledWith('user-1')
    })
  })

  it('exibe cada estabelecimento uma única vez, mesmo com vínculos repetidos', async () => {
    mocks.getUserEstablishments.mockResolvedValue([
      establishmentFixture('est-barberleo', { name: 'BarberLeo', role: 'owner' }),
      establishmentFixture('est-barberleo', { name: 'BarberLeo', role: 'professional' }),
      establishmentFixture('est-salao', { name: 'Salão Aurora' }),
    ])

    renderProvider()

    await waitFor(() => {
      expect(screen.getByTestId('establishment-count')).toHaveTextContent('2')
    })
  })

  it('ativa o único estabelecimento do usuário', async () => {
    mocks.getUserEstablishments.mockResolvedValue([
      establishmentFixture('est-barberleo', { role: 'owner' }),
    ])

    renderProvider()

    await waitFor(() => {
      expect(screen.getByTestId('active-establishment')).toHaveTextContent('est-barberleo')
    })
  })

  it('mantém a escolha persistida entre atualizações da página', async () => {
    window.localStorage.setItem('agenda-flow:active-establishment:user-1', 'est-salao')
    mocks.getUserEstablishments.mockResolvedValue([
      establishmentFixture('est-barberleo'),
      establishmentFixture('est-salao'),
    ])

    renderProvider()

    await waitFor(() => {
      expect(screen.getByTestId('active-establishment')).toHaveTextContent('est-salao')
    })
  })

  it('ignora escolha persistida que não pertence ao usuário', async () => {
    window.localStorage.setItem('agenda-flow:active-establishment:user-1', 'est-de-outro')
    mocks.getUserEstablishments.mockResolvedValue([
      establishmentFixture('est-barberleo'),
      establishmentFixture('est-salao'),
    ])

    renderProvider()

    await waitFor(() => {
      expect(mocks.getUserEstablishments).toHaveBeenCalled()
    })

    expect(screen.getByTestId('active-establishment')).toHaveTextContent('nenhum')
  })

  it('guarda o estabelecimento escolhido para a próxima atualização', async () => {
    mocks.getUserEstablishments.mockResolvedValue([
      establishmentFixture('est-barberleo'),
      establishmentFixture('est-salao'),
    ])

    renderProvider()

    await waitFor(() => {
      expect(screen.getByTestId('establishment-count')).toHaveTextContent('2')
    })

    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'escolher o segundo' }))
    })

    await waitFor(() => {
      expect(screen.getByTestId('active-establishment')).toHaveTextContent('est-salao')
    })
    expect(window.localStorage.getItem('agenda-flow:active-establishment:user-1')).toBe('est-salao')
  })
})
