import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'

import { getCurrentSession } from '../lib/supabase'

export function AuthCallbackPage() {
  const navigate = useNavigate()
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let isMounted = true

    getCurrentSession()
      .then((session) => {
        if (!isMounted) return

        if (!session) {
          setError('Não foi possível recuperar a sessão após o login.')
          return
        }

        navigate('/dashboard', { replace: true })
      })
      .catch((err) => {
        if (!isMounted) return
        setError(err instanceof Error ? err.message : 'Falha ao processar login.')
      })

    return () => {
      isMounted = false
    }
  }, [navigate])

  if (error) {
    return (
      <main className="auth-page">
        <section className="auth-card">
          <h1 className="auth-card__title">Erro no login</h1>
          <p className="auth-card__error">{error}</p>
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
