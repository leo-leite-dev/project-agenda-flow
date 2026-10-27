import { Navigate, useNavigate } from 'react-router-dom'

import { useAuth } from '../hooks/useAuth'

export function WelcomePage() {
  const navigate = useNavigate()
  const { user, isLoading, isAuthenticated } = useAuth()

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

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />
  }

  return (
    <main className="auth-page">
      <section className="auth-card" style={{ textAlign: 'center' }}>
        <div className="home__badge" style={{ margin: '0 auto 20px' }}>
          <span className="home__badge-dot" />
          <span>Bem-vindo</span>
        </div>
        <h1 className="auth-card__title">Olá, {user?.user_metadata?.full_name ?? user?.email ?? 'usuário'}!</h1>
        <p className="auth-card__subtitle">
          Você ainda não possui um estabelecimento vinculado. Cadastre sua barbearia ou salão de beleza para começar.
        </p>
        <button
          type="button"
          className="button button--primary"
          style={{ width: '100%', marginTop: '8px' }}
          onClick={() => navigate('/establishment/new')}
        >
          Cadastrar estabelecimento
        </button>
      </section>
    </main>
  )
}
