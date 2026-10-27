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

function Consumer() {
  const auth = useAuth()

  return (
    <div>
      <span data-testid="establishment-count">{auth.establishments.length}</span>
      <span data-testid="is-authenticated">{String(auth.isAuthenticated)}</span>
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
