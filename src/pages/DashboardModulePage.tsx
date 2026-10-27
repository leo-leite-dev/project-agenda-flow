import { Navigate, useLocation } from 'react-router-dom'

import { DashboardLayout } from '../components/dashboard/DashboardLayout'
import { ModulePlaceholder } from '../components/dashboard/ModulePlaceholder'
import { resolveNavItem } from '../components/dashboard/navigation'

/**
 * Página de "Em breve" para os módulos ainda não implementados. O conteúdo é
 * resolvido a partir da rota atual — nada é simulado. Rotas desconhecidas
 * retornam à Visão geral.
 */
export function DashboardModulePage() {
  const location = useLocation()
  const module = resolveNavItem(location.pathname)

  if (!module) {
    return <Navigate to="/dashboard" replace />
  }

  return (
    <DashboardLayout>
      <ModulePlaceholder module={module} />
    </DashboardLayout>
  )
}
