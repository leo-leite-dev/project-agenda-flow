import { Navigate } from 'react-router-dom'

import { useAuth } from '../hooks/useAuth'

export function SelectEstablishmentPage() {
  const { user, isLoading, isAuthenticated, establishments, selectEstablishment } = useAuth()

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

  if (establishments.length === 0) {
    return <Navigate to="/welcome" replace />
  }

  if (establishments.length === 1) {
    selectEstablishment(establishments[0])
    return <Navigate to="/dashboard" replace />
  }

  return (
    <main className="auth-page">
      <section className="auth-card" style={{ maxWidth: '520px' }}>
        <div className="auth-card__header">
          <h1 className="auth-card__title">Escolha um estabelecimento</h1>
          <p className="auth-card__subtitle">
            Olá, {user?.user_metadata?.full_name ?? user?.email ?? 'usuário'}. Você está vinculado a mais de um
            estabelecimento.
          </p>
        </div>

        <div className="establishment-list">
          {establishments.map((establishment) => (
            <button
              key={establishment.id}
              type="button"
              className="establishment-card"
              onClick={() => selectEstablishment(establishment)}
            >
              <span className="establishment-card__name">{establishment.name}</span>
              <span className="establishment-card__type">
                {establishment.type === 'barbershop' ? 'Barbearia' : 'Salão de beleza'}
              </span>
              {establishment.address?.city && establishment.address?.state && (
                <span className="establishment-card__location">
                  {establishment.address.city}, {establishment.address.state}
                </span>
              )}
            </button>
          ))}
        </div>
      </section>
    </main>
  )
}
