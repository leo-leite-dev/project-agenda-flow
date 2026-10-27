import { useEffect, useState, type ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'

import { useAuth } from '../../hooks/useAuth'
import { DashboardHeader } from './DashboardHeader'
import { DashboardSidebar } from './DashboardSidebar'

interface DashboardLayoutProps {
  children: ReactNode
}

/**
 * Estrutura compartilhada da área administrativa: sidebar, cabeçalho e área
 * principal. Garante que o estabelecimento ativo esteja definido pelos dados
 * reais da sessão (vínculos autorizados via RLS) antes de renderizar
 * qualquer conteúdo.
 */
export function DashboardLayout({ children }: DashboardLayoutProps) {
  const { user, establishments, currentEstablishment, isLoadingEstablishments, isLoading, signOut } =
    useAuth()
  const [isSidebarOpen, setSidebarOpen] = useState(false)
  const location = useLocation()

  // Navegação por teclado entre rotas retorna o foco ao topo da área principal.
  useEffect(() => {
    document.getElementById('dash-main')?.focus()
  }, [location.pathname])

  if (isLoading || isLoadingEstablishments) {
    return (
      <main className="auth-page">
        <section className="auth-card">
          <div className="auth-card__spinner" aria-label="Carregando" />
          <p className="auth-card__message">Carregando...</p>
        </section>
      </main>
    )
  }

  if (establishments.length === 0) {
    return <Navigate to="/welcome" replace />
  }

  if (!currentEstablishment && establishments.length > 1) {
    return <Navigate to="/select-establishment" replace />
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
