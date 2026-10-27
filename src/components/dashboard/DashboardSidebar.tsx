import { useEffect } from 'react'
import { NavLink, useLocation } from 'react-router-dom'

import { dashboardNav } from './navigation'
import { CloseIcon } from './icons'

interface DashboardSidebarProps {
  isOpen: boolean
  onClose: () => void
  establishmentName: string
}

export function DashboardSidebar({ isOpen, onClose, establishmentName }: DashboardSidebarProps) {
  const location = useLocation()

  // Fecha o drawer em telas menores sempre que a rota muda.
  useEffect(() => {
    onClose()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [location.pathname])

  // Fecha o drawer com a tecla Escape.
  useEffect(() => {
    if (!isOpen) return

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, onClose])

  return (
    <aside
      id="dash-sidebar"
      className={`dash-sidebar${isOpen ? ' dash-sidebar--open' : ''}`}
      aria-label="Navegação do estabelecimento"
    >
      <div className="dash-sidebar__head">
        <span className="dash-brand">
          <span className="home__badge-dot" aria-hidden="true" />
          Agenda Flow
        </span>
        <button
          type="button"
          className="dash-icon-button dash-sidebar__close"
          onClick={onClose}
          aria-label="Fechar menu de navegação"
        >
          <CloseIcon />
        </button>
      </div>

      <p className="dash-sidebar__establishment" title={establishmentName}>
        {establishmentName}
      </p>

      <nav className="dash-sidebar__nav">
        <ul>
          {dashboardNav.map((item) => {
            const Icon = item.icon

            return (
              <li key={item.path}>
                <NavLink
                  to={item.path}
                  end={item.path === '/dashboard'}
                  className={({ isActive }) =>
                    `dash-nav-item${isActive ? ' dash-nav-item--active' : ''}`
                  }
                  aria-current={item.path === location.pathname ? 'page' : undefined}
                >
                  <Icon className="dash-nav-item__icon" />
                  <span>{item.label}</span>
                  {!item.implemented && (
                    <span className="dash-nav-item__badge">
                      Em breve
                    </span>
                  )}
                </NavLink>
              </li>
            )
          })}
        </ul>
      </nav>

      <p className="dash-sidebar__footer">Agenda Flow • Etapa 4</p>
    </aside>
  )
}
