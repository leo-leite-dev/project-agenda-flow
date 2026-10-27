import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'

import { AuthContext, type AuthContextValue } from '../../contexts/AuthContext'
import { AuthCallbackPage } from '../AuthCallbackPage'

function baseValue(overrides: Partial<AuthContextValue> = {}): AuthContextValue {
  return {
    user: null,
    isLoading: true,
    isAuthenticated: false,
    establishments: [],
    currentEstablishment: null,
    isLoadingEstablishments: false,
    signInWithGoogle: async () => {},
    signInWithEmail: async () => {},
    signUpWithEmail: async () => {},
    signOut: async () => {},
    refreshEstablishments: async () => {},
    selectEstablishment: () => {},
    createEstablishment: async () => '',
    error: null,
    clearError: () => {},
    ...overrides,
  }
}

function Harness({ value }: { value: AuthContextValue }) {
  return (
    <MemoryRouter initialEntries={['/auth/callback']}>
      <AuthContext.Provider value={value}>
        <Routes>
          <Route path="/auth/callback" element={<AuthCallbackPage />} />
          <Route path="/welcome" element={<div>WELCOME</div>} />
          <Route path="/dashboard" element={<div>DASHBOARD</div>} />
          <Route path="/select-establishment" element={<div>SELECT</div>} />
          <Route path="/login" element={<div>LOGIN</div>} />
        </Routes>
      </AuthContext.Provider>
    </MemoryRouter>
  )
}

describe('AuthCallbackPage', () => {
  it('shows the processing state while the auth bootstrap is loading', () => {
    render(<Harness value={baseValue({ isLoading: true })} />)
    expect(screen.getByText(/Processando seu login/i)).toBeInTheDocument()
    expect(screen.queryByText('WELCOME')).not.toBeInTheDocument()
  })

  it('redirects to /welcome when the user has no establishment', () => {
    render(
      <Harness
        value={baseValue({
          isLoading: false,
          isAuthenticated: true,
          establishments: [],
          isLoadingEstablishments: false,
        })}
      />,
    )
    expect(screen.getByText('WELCOME')).toBeInTheDocument()
  })

  it('redirects to /dashboard with a single establishment', () => {
    const one = { id: '1' } as unknown as AuthContextValue['establishments'][number]
    render(
      <Harness
        value={baseValue({
          isLoading: false,
          isAuthenticated: true,
          establishments: [one],
          isLoadingEstablishments: false,
        })}
      />,
    )
    expect(screen.getByText('DASHBOARD')).toBeInTheDocument()
  })

  it('redirects to /select-establishment with multiple establishments', () => {
    const one = { id: '1' } as unknown as AuthContextValue['establishments'][number]
    const two = { id: '2' } as unknown as AuthContextValue['establishments'][number]
    render(
      <Harness
        value={baseValue({
          isLoading: false,
          isAuthenticated: true,
          establishments: [one, two],
          isLoadingEstablishments: false,
        })}
      />,
    )
    expect(screen.getByText('SELECT')).toBeInTheDocument()
  })

  it('waits while establishments are still loading before redirecting', () => {
    render(
      <Harness
        value={baseValue({
          isLoading: false,
          isAuthenticated: true,
          establishments: [],
          isLoadingEstablishments: true,
        })}
      />,
    )
    expect(screen.getByText(/Processando seu login/i)).toBeInTheDocument()
    expect(screen.queryByText('WELCOME')).not.toBeInTheDocument()
  })

  it('shows an error when initialization finishes without a session', () => {
    render(
      <Harness
        value={baseValue({
          isLoading: false,
          isAuthenticated: false,
          establishments: [],
          isLoadingEstablishments: false,
        })}
      />,
    )
    expect(screen.getByText(/N.o foi poss.vel recuperar a sess.o ap.s o login/i)).toBeInTheDocument()
    expect(screen.queryByText('WELCOME')).not.toBeInTheDocument()
  })

  it('handles the asynchronous session initialization (implicit return)', () => {
    const { rerender } = render(<Harness value={baseValue({ isLoading: true })} />)
    expect(screen.getByText(/Processando seu login/i)).toBeInTheDocument()

    rerender(
      <Harness
        value={baseValue({
          isLoading: false,
          isAuthenticated: true,
          establishments: [],
          isLoadingEstablishments: false,
        })}
      />,
    )

    expect(screen.getByText('WELCOME')).toBeInTheDocument()
  })
})
