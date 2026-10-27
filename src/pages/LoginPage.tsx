import { useCallback, useState } from 'react'
import { Navigate, useNavigate, useSearchParams } from 'react-router-dom'

import { useAuth } from '../hooks/useAuth'

export function LoginPage() {
  const [searchParams] = useSearchParams()
  const initialMode = searchParams.get('mode') === 'signup' ? 'signup' : 'login'

  const [mode, setMode] = useState<'login' | 'signup'>(initialMode)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [fullName, setFullName] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [localError, setLocalError] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)

  const navigate = useNavigate()
  const { isLoading, isAuthenticated, signInWithGoogle, signInWithEmail, signUpWithEmail, error, clearError } = useAuth()

  const switchMode = useCallback(
    (nextMode: 'login' | 'signup') => {
      setMode(nextMode)
      setLocalError(null)
      clearError()
    },
    [clearError],
  )

  const handleGoogleSignIn = async () => {
    setLocalError(null)
    clearError()
    try {
      await signInWithGoogle()
    } catch {
      // Error is already handled by the auth context.
    }
  }

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setLocalError(null)
    setSuccessMessage(null)
    clearError()
    setIsSubmitting(true)

    try {
      if (mode === 'login') {
        await signInWithEmail(email, password)
        navigate('/dashboard', { replace: true })
      } else {
        if (!fullName.trim()) {
          setLocalError('Informe seu nome completo.')
          setIsSubmitting(false)
          return
        }
        const { session } = await signUpWithEmail(email, password, fullName)
        if (session) {
          navigate('/dashboard', { replace: true })
        } else {
          setSuccessMessage('Conta criada. Verifique seu e-mail para confirmar o cadastro antes de entrar.')
        }
      }
    } catch (err) {
      setLocalError(err instanceof Error ? err.message : 'Ocorreu um erro. Tente novamente.')
    } finally {
      setIsSubmitting(false)
    }
  }

  if (isAuthenticated) {
    return <Navigate to="/dashboard" replace />
  }

  if (isLoading) {
    return (
      <main className="auth-page">
        <section className="auth-card">
          <div className="auth-card__spinner" aria-label="Carregando" />
          <p className="auth-card__message">Carregando...</p>
        </section>
      </main>
    )
  }

  const displayedError = localError || error

  return (
    <main className="auth-page">
      <section className="auth-card">
        <div className="auth-card__header">
          <h1 className="auth-card__title">{mode === 'login' ? 'Entrar no Agenda Flow' : 'Criar conta'}</h1>
          <p className="auth-card__subtitle">
            {mode === 'login'
              ? 'Entre com sua conta para continuar.'
              : 'Crie sua conta e comece a organizar seu negócio.'}
          </p>
        </div>

        {displayedError && (
          <div className="auth-card__alert" role="alert">
            {displayedError}
          </div>
        )}

        {successMessage && (
          <div
            className="auth-card__alert"
            style={{ background: '#f0fdf4', color: '#166534', borderColor: '#bbf7d0' }}
            role="status"
          >
            {successMessage}
          </div>
        )}

        <button
          type="button"
          className="button button--google"
          onClick={handleGoogleSignIn}
          disabled={isSubmitting}
          aria-label="Continuar com Google"
        >
          <svg className="button__icon" viewBox="0 0 24 24" aria-hidden="true">
            <path
              fill="#4285F4"
              d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
            />
            <path
              fill="#34A853"
              d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
            />
            <path
              fill="#FBBC05"
              d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
            />
            <path
              fill="#EA4335"
              d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
            />
          </svg>
          Continuar com Google
        </button>

        <div className="auth-card__divider" aria-hidden="true">
          <span>ou</span>
        </div>

        <form className="auth-form" onSubmit={handleSubmit} noValidate>
          {mode === 'signup' && (
            <div className="auth-form__field">
              <label htmlFor="fullName">Nome completo</label>
              <input
                id="fullName"
                type="text"
                value={fullName}
                onChange={(e) => setFullName(e.target.value)}
                placeholder="Seu nome"
                required
                autoComplete="name"
              />
            </div>
          )}

          <div className="auth-form__field">
            <label htmlFor="email">E-mail</label>
            <input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="seu@email.com"
              required
              autoComplete="email"
            />
          </div>

          <div className="auth-form__field">
            <label htmlFor="password">Senha</label>
            <input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Sua senha"
              required
              minLength={6}
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
            />
          </div>

          <button type="submit" className="button button--primary" disabled={isSubmitting}>
            {isSubmitting ? 'Processando...' : mode === 'login' ? 'Entrar' : 'Criar conta'}
          </button>
        </form>

        <p className="auth-card__footer">
          {mode === 'login' ? (
            <>
              Ainda não tem conta?{' '}
              <button type="button" className="link" onClick={() => switchMode('signup')}>
                Criar conta
              </button>
            </>
          ) : (
            <>
              Já tem uma conta?{' '}
              <button type="button" className="link" onClick={() => switchMode('login')}>
                Entrar
              </button>
            </>
          )}
        </p>
      </section>
    </main>
  )
}
