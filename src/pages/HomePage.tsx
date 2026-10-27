import { Link } from 'react-router-dom'

export function HomePage() {
  return (
    <main className="home">
      <section className="home__hero">
        <div className="home__badge">
          <span className="home__badge-dot" />
          <span>Agenda Flow</span>
        </div>
        <h1 className="home__title">Bem-vindo ao Agenda Flow!</h1>
        <p className="home__subtitle">
          Estamos construindo uma nova maneira de organizar seus agendamentos, clientes e finanças.
        </p>
        <div className="home__actions">
          <Link to="/login" className="button button--primary">
            Entrar
          </Link>
          <Link to="/login?mode=signup" className="button button--secondary">
            Criar conta
          </Link>
        </div>
        <p className="home__coming-soon">Em breve, novidades!</p>
      </section>
    </main>
  )
}
