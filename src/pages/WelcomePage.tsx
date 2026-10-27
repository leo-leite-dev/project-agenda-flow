import { Navigate, useNavigate } from 'react-router-dom'

import { useAuth } from '../hooks/useAuth'
import { usePendingInvitation } from '../hooks/usePendingInvitation'
import { resolveOnboardingDecision } from '../lib/onboarding'
import { TEAM_ROLE_LABELS } from '../lib/team'

export function WelcomePage() {
  const navigate = useNavigate()
  const { user, isLoading, isAuthenticated, isLoadingEstablishments } = useAuth()
  const { invitations, hasPendingInvitation, pendingInvitationPath, isLoading: isLoadingInvitations } =
    usePendingInvitation()

  const decision = resolveOnboardingDecision({
    isAuthenticated,
    isLoading,
    isLoadingEstablishments,
    isLoadingInvitations,
    establishmentCount: 0,
    hasPendingInvitation,
    pendingInvitationPath,
  })

  if (decision.kind === 'loading') {
    return (
      <main className="auth-page">
        <section className="auth-card">
          <div className="auth-card__spinner" aria-label="Carregando" />
          <p className="auth-card__message">Carregando...</p>
        </section>
      </main>
    )
  }

  if (decision.kind === 'login') {
    return <Navigate to="/login" replace />
  }

  const firstName = user?.user_metadata?.full_name ?? user?.email ?? 'usuário'

  return (
    <main className="auth-page">
      <section className="auth-card" style={{ textAlign: 'center' }}>
        <div className="home__badge" style={{ margin: '0 auto 20px' }}>
          <span className="home__badge-dot" />
          <span>Bem-vindo</span>
        </div>

        {hasPendingInvitation ? (
          <>
            <h1 className="auth-card__title">Olá, {firstName}!</h1>
            <p className="auth-card__subtitle">
              Você recebeu um convite para integrar uma equipe. Aceite o convite para acessar o
              estabelecimento — não é necessário criar uma empresa nova.
            </p>

            <ul className="pending-invitations">
              {invitations.map((invitation) => (
                <li className="pending-invitations__item" key={invitation.establishment_id}>
                  <span className="pending-invitations__name">
                    {invitation.establishment_name}
                  </span>
                  <span className="pending-invitations__role">
                    {TEAM_ROLE_LABELS[invitation.role] ?? invitation.role}
                  </span>
                </li>
              ))}
            </ul>

            {decision.kind === 'invitation' ? (
              <button
                type="button"
                className="button button--primary"
                style={{ width: '100%', marginTop: '8px' }}
                onClick={() => navigate(decision.path)}
              >
                Aceitar convite
              </button>
            ) : (
              <p className="auth-card__message">
                Abra o link de convite enviado pelo proprietário para aceitar. Se o link expirou,
                peça um novo convite ao proprietário.
              </p>
            )}

            <p className="auth-card__footer">
              Também quer gerenciar o próprio estabelecimento?{' '}
              <button
                type="button"
                className="link"
                onClick={() => navigate('/establishment/new')}
              >
                Cadastrar estabelecimento
              </button>
            </p>
          </>
        ) : (
          <>
            <h1 className="auth-card__title">Olá, {firstName}!</h1>
            <p className="auth-card__subtitle">
              Você ainda não possui um estabelecimento vinculado. Cadastre sua barbearia ou salão
              de beleza para começar.
            </p>
            <button
              type="button"
              className="button button--primary"
              style={{ width: '100%', marginTop: '8px' }}
              onClick={() => navigate('/establishment/new')}
            >
              Cadastrar estabelecimento
            </button>
          </>
        )}
      </section>
    </main>
  )
}
