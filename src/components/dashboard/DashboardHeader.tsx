import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'

import type { User } from '@supabase/supabase-js'

import type { UserEstablishment } from '../../contexts/AuthContext'
import { BellIcon, MenuIcon, SignOutIcon, SwapIcon } from './icons'

interface DashboardHeaderProps {
  establishment: UserEstablishment
  user: User | null
  isSidebarOpen: boolean
  onToggleSidebar: () => void
  onSignOut: () => Promise<void>
}

function userTypeLabel(establishment: UserEstablishment): string {
  return establishment.type === 'barbershop' ? 'Barbearia' : 'Salão de beleza'
}

function userDisplayName(user: User | null): string {
  const metadata = user?.user_metadata as Record<string, unknown> | undefined
  const name =
    (metadata?.full_name as string | undefined) ??
    (metadata?.name as string | undefined) ??
    user?.email ??
    user?.phone

  return name ?? 'Usuário'
}

export function DashboardHeader({
  establishment,
  user,
  isSidebarOpen,
  onToggleSidebar,
  onSignOut,
}: DashboardHeaderProps) {
  const navigate = useNavigate()
  const [isProfileOpen, setProfileOpen] = useState(false)
  const profileRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    if (!isProfileOpen) return

    const handleClickOutside = (event: MouseEvent) => {
      if (profileRef.current && !profileRef.current.contains(event.target as Node)) {
        setProfileOpen(false)
      }
    }

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setProfileOpen(false)
    }

    document.addEventListener('mousedown', handleClickOutside)
    document.addEventListener('keydown', handleKeyDown)

    return () => {
      document.removeEventListener('mousedown', handleClickOutside)
      document.removeEventListener('keydown', handleKeyDown)
    }
  }, [isProfileOpen])

  const handleSignOut = async () => {
    setProfileOpen(false)
    await onSignOut()
    navigate('/login', { replace: true })
  }

  return (
    <header className="dash-header">
      <div className="dash-header__left">
        <button
          type="button"
          className="dash-icon-button dash-header__menu"
          onClick={onToggleSidebar}
          aria-label={isSidebarOpen ? 'Fechar menu de navegação' : 'Abrir menu de navegação'}
          aria-controls="dash-sidebar"
          aria-expanded={isSidebarOpen}
        >
          <MenuIcon />
        </button>

        <div className="dash-header__establishment">
          <span className="dash-header__establishment-name" title={establishment.name}>
            {establishment.name}
          </span>
          <span className="dash-header__establishment-type">{userTypeLabel(establishment)}</span>
        </div>
      </div>

      <div className="dash-header__actions">
        <button
          type="button"
          className="dash-icon-button"
          disabled
          aria-label="Notificações — disponível em breve"
          title="Notificações — disponível em breve"
        >
          <BellIcon />
        </button>

        <Link to="/select-establishment" className="dash-header__switch">
          <SwapIcon className="dash-header__switch-icon" />
          <span>Trocar estabelecimento</span>
        </Link>

        <div className="dash-profile" ref={profileRef}>
          <button
            type="button"
            className="dash-profile__trigger"
            onClick={() => setProfileOpen((open) => !open)}
            aria-haspopup="menu"
            aria-expanded={isProfileOpen}
          >
            <span className="dash-profile__avatar" aria-hidden="true">
              {userDisplayName(user).charAt(0).toUpperCase()}
            </span>
            <span className="dash-profile__name">{userDisplayName(user)}</span>
          </button>

          {isProfileOpen && (
            <div className="dash-profile__menu" role="menu" aria-label="Menu do perfil">
              <div className="dash-profile__info">
                <span className="dash-profile__info-name">{userDisplayName(user)}</span>
                <span className="dash-profile__info-email">
                  {user?.email ?? user?.phone ?? 'Conta Agenda Flow'}
                </span>
              </div>
              <button
                type="button"
                role="menuitem"
                className="dash-profile__signout"
                onClick={() => void handleSignOut()}
              >
                <SignOutIcon className="dash-profile__signout-icon" />
                Sair da conta
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  )
}
