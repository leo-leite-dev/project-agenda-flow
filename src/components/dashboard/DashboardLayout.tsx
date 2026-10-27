import { useEffect, useState, type ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'

import { useAuth } from '../../hooks/useAuth'
import { usePendingInvitation } from '../../hooks/usePendingInvitation'
import { resolveOnboardingDecision } from '../../lib/onboarding'
import { DashboardHeader } from './DashboardHeader'
import { DashboardSidebar } from './DashboardSidebar'

interface DashboardLayoutProps {
  children: ReactNode
}

/**
 * Estrutura compartilhada da área administrativa: sidebar, cabeçalho e área
 * principal.
 *
 * A decisão de tela inicial considera autenticação, vínculos, convites
 * pendentes e o estado de carregamento — um funcionário convidado nunca é
 * obrigado a criar um estabelecimento.
 */
export function DashboardLayout({ children }: DashboardLayoutProps) {
  const { user, establishments, currentEstablishment, isLoadingEstablishments, isLoading, signOut } =
    useAuth()
  const {
    hasPendingInvitation,
    pendingInvitationPath,
    isLoading: isLoadingInvitations,
  } = usePendingInvitation()
  const [isSidebarOpen, setSidebarOpen] = useState(false)
  const location = useLocation()

  // Navegação por teclado entre rotas retorna o foco ao topo da área principal.
  useEffect(() => {
    document.getElementById('dash-main')?.focus()
  }, [location.pathname])

  const decision = resolveOnboardingDecision({
    isAuthenticated: Boolean(user),
    isLoading,
    isLoadingEstablishments,
    isLoadingInvitations,
    establishmentCount: establishments.length,
    hasActiveEstablishment: Boolean(currentEstablishment),
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

  if (decision.kind === 'select-establishment') {
    return <Navigate to="/select-establishment" replace />
  }

  if (decision.kind === 'invitation') {
    return <Navigate to={decision.path} replace />
  }

  if (decision.kind === 'pending-invitation' || decision.kind === 'welcome') {
    // Sem vínculos: ou há um convite para aceitar ou o usuário pode criar
    // o próprio estabelecimento. A página inicial orienta os dois caminhos.
    return <Navigate to="/welcome" replace />
  }

  const establishment = currentEstablishment ?? establishments[0]

  return (
    <div className="dash">
      <a className="dash-skip" href="#dash-main">
        Pular para o conteúdo principal
      </a>

      <DashboardSidebar
        isOpen={isSidebarOpen}
        onClose={() => setSidebarOpen(false)}
        establishmentName={establishment.name}
      />

      {isSidebarOpen && (
        <button
          type="button"
          className="dash-backdrop"
          aria-label="Fechar menu de navegação"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      <div className="dash-body">
        <DashboardHeader
          establishment={establishment}
          user={user}
          isSidebarOpen={isSidebarOpen}
          onToggleSidebar={() => setSidebarOpen((open) => !open)}
          onSignOut={signOut}
        />

        <main id="dash-main" className="dash-main" tabIndex={-1}>
          {children}
        </main>
      </div>
    </div>
  )
}
