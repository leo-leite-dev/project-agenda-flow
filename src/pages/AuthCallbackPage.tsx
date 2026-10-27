import { useCallback, useEffect, useMemo, useRef } from 'react'
import { useNavigate } from 'react-router-dom'

import { useAuth } from '../hooks/useAuth'
import { resolvePostAuthRedirect } from '../lib/authRedirect'

export function AuthCallbackPage() {
  const navigate = useNavigate()
  const { isAuthenticated, isLoading, isLoadingEstablishments, establishments } = useAuth()
  const didRedirect = useRef(false)

  const redirect = useCallback(
    (path: string) => {
      if (didRedirect.current) return
      didRedirect.current = true
      navigate(path, { replace: true })
    },
    [navigate],
  )

  // Derive the post-login decision during render (pure, no side effects). The
  // library processes the OAuth return URL hash asynchronously during client
  // initialization, so we wait for the AuthProvider bootstrap (isLoading ===
  // false) before acting. We never read the URL tokens manually.
  const decision = useMemo(
    () =>
      resolvePostAuthRedirect({
        isAuthenticated,
        establishmentCount: establishments.length,
        isLoadingEstablishments,
      }),
    [isAuthenticated, establishments, isLoadingEstablishments],
  )

  useEffect(() => {
    if (isLoading) return
    if (decision.kind === 'redirect') {
      redirect(decision.path)
    }
  }, [isLoading, decision, redirect])

  if (!isLoading && decision.kind === 'error') {
    return (
      <main className="auth-page">
        <section className="auth-card">
          <h1 className="auth-card__title">Erro no login</h1>
          <p className="auth-card__error">Não foi possível recuperar a sessão após o login.</p>
          <a href="/login" className="button button--primary">
            Voltar para o login
          </a>
        </section>
      </main>
    )
  }

  return (
    <main className="auth-page">
      <section className="auth-card">
        <div className="auth-card__spinner" aria-label="Processando login" />
        <p className="auth-card__message">Processando seu login...</p>
      </section>
    </main>
  )
}
