import { useAuth } from '../hooks/useAuth'

export function DashboardPage() {
  const { user, signOut, isLoading } = useAuth()

  const handleSignOut = async () => {
    await signOut()
  }

  return (
    <main className="dashboard">
      <header className="dashboard__header">
        <div className="dashboard__brand">
          <span className="home__badge-dot" />
          <span className="dashboard__title">Agenda Flow</span>
        </div>
        <button type="button" className="button button--secondary" onClick={handleSignOut} disabled={isLoading}>
          {isLoading ? 'Saindo...' : 'Sair'}
        </button>
      </header>

      <section className="dashboard__content">
        <div className="auth-card" style={{ maxWidth: '640px' }}>
          <h1 className="auth-card__title">Painel inicial</h1>
          <p className="auth-card__subtitle">
            Você está autenticado como <strong>{user?.email ?? user?.phone ?? 'usuário'}</strong>.
          </p>
          <p className="auth-card__message">
            Este é um painel provisório. Os módulos de agenda, clientes e finanças serão implementados nas próximas
            etapas.
          </p>
        </div>
      </section>
    </main>
  )
}
