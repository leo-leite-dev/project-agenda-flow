import { useCallback, useEffect, useMemo } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'

import { useAuth } from '../hooks/useAuth'
import { dedupeEstablishmentsById, isEstablishmentAuthorized } from '../lib/establishments'

export function SelectEstablishmentPage() {
  const navigate = useNavigate()
  const { user, isLoading, isAuthenticated, establishments, selectEstablishment } = useAuth()

  // Proteção adicional da interface: cada estabelecimento aparece uma única
  // vez, mesmo que o banco ainda possua vínculos inconsistentes.
  const options = useMemo(() => dedupeEstablishmentsById(establishments), [establishments])

  const handleSelect = useCallback(
    (establishmentId: string) => {
      // Só estabelecimentos da lista autorizada do usuário autenticado podem
      // ser ativados.
      const establishment = options.find((item) => item.id === establishmentId)

      if (!establishment || !isEstablishmentAuthorized(options, establishmentId)) {
        return
      }

      selectEstablishment(establishment)
      navigate('/dashboard', { replace: true })
    },
    [navigate, options, selectEstablishment],
  )

  // Usuário com um único estabelecimento: a seleção é automática.
  useEffect(() => {
    if (isLoading || !isAuthenticated) return
    if (options.length !== 1) return

    selectEstablishment(options[0])
    navigate('/dashboard', { replace: true })
  }, [isAuthenticated, isLoading, navigate, options, selectEstablishment])

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

  if (options.length === 0) {
    return <Navigate to="/welcome" replace />
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
          {options.map((establishment) => (
            <button
              key={establishment.id}
              type="button"
              className="establishment-card"
              onClick={() => handleSelect(establishment.id)}
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
