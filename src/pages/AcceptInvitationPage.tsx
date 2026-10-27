import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'

import { useAuth } from '../hooks/useAuth'
import { acceptTeamInvitation } from '../lib/team'
import { clearPendingInvitationPath, storePendingInvitationPath } from '../lib/onboarding'
import { TeamIcon } from '../components/dashboard/icons'

const TOKEN_PATTERN = /^[a-f0-9]{64}$/i

export function AcceptInvitationPage() {
  const { token = '' } = useParams()
  const navigate = useNavigate()
  const { user, isAuthenticated, isLoading, refreshEstablishments } = useAuth()

  const [isAccepting, setIsAccepting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [accepted, setAccepted] = useState(false)

  const isValidToken = TOKEN_PATTERN.test(token)

  useEffect(() => {
    // Novo token invalida o estado da tentativa anterior.
    // eslint-disable-next-line react-hooks/exhaustive-deps -- reset intencional ao trocar o token
    setError(null)
    setAccepted(false)
  }, [token])

  // Preserva o convite durante o login/cadastro e a atualização da página.
  useEffect(() => {
    if (isValidToken) {
      storePendingInvitationPath(`/convite/${token}`)
    }
  }, [isValidToken, token])

  const handleAccept = useCallback(async () => {
    if (!isValidToken) return

    setIsAccepting(true)
    setError(null)

    try {
      await acceptTeamInvitation(token)
      await refreshEstablishments()
      clearPendingInvitationPath()
      setAccepted(true)
    } catch (err) {
      setError(
        err instanceof Error && err.message
          ? err.message
          : 'Não foi possível aceitar o convite. Verifique o link e sua conta.',
      )
    } finally {
      setIsAccepting(false)
    }
  }, [isValidToken, token, refreshEstablishments])

  const invitePath = `/convite/${token}`

  if (!isValidToken) {
    return (
      <main className="auth-page">
        <section className="auth-card">
          <h1 className="auth-card__title">Convite inválido</h1>
          <p className="auth-card__message">
            O link de convite não é válido. Peça um novo link ao proprietário do estabelecimento.
          </p>
          <div className="auth-card__footer">
            <Link to="/login" className="button button--primary">
              Ir para o login
            </Link>
          </div>
        </section>
      </main>
    )
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

  if (!isAuthenticated) {
    return (
      <main className="auth-page">
        <section className="auth-card">
          <span className="auth-card__icon" aria-hidden="true">
            <TeamIcon width={28} height={28} />
          </span>
          <h1 className="auth-card__title">Você foi convidado(a)</h1>
          <p className="auth-card__message">
            Entre ou crie sua conta com o e-mail convidado para aceitar o convite e fazer parte da
            equipe.
          </p>
          <div className="auth-card__footer">
            <Link to={`/login?next=${encodeURIComponent(invitePath)}`} className="button button--primary">
              Entrar para aceitar
            </Link>
          </div>
          <p className="auth-card__footer">
            <Link to={`/login?mode=signup&next=${encodeURIComponent(invitePath)}`} className="link">
              Ainda não tenho conta — criar agora
            </Link>
          </p>
        </section>
      </main>
    )
  }

  if (accepted) {
    return (
      <main className="auth-page">
        <section className="auth-card">
          <h1 className="auth-card__title">Convite aceito</h1>
          <p className="auth-card__message">
            Você agora faz parte da equipe. Continue no establishment pelo painel.
          </p>
          <div className="auth-card__footer">
            <button
              type="button"
              className="button button--primary"
              onClick={() => navigate('/dashboard', { replace: true })}
            >
              Ir para o dashboard
            </button>
          </div>
        </section>
      </main>
    )
  }

  return (
    <main className="auth-page">
      <section className="auth-card">
        <span className="auth-card__icon" aria-hidden="true">
          <TeamIcon width={28} height={28} />
        </span>
        <h1 className="auth-card__title">Aceitar convite</h1>
        <p className="auth-card__message">
          Você está autenticado como <strong>{user?.email ?? user?.phone ?? 'usuário'}</strong>. Ao
          aceitar, você fará parte da equipe do estabelecimento que convidou você.
        </p>

        {error && (
          <div className="auth-card__alert" role="alert">
            {error}
          </div>
        )}

        <div className="auth-card__footer">
          <button
            type="button"
            className="button button--primary"
            onClick={() => void handleAccept()}
            disabled={isAccepting}
          >
            {isAccepting ? 'Aceitando...' : 'Aceitar convite'}
          </button>
        </div>
      </section>
    </main>
  )
}
