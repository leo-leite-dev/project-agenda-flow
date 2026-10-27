import { useCallback, useState } from 'react'
import { Navigate, useNavigate } from 'react-router-dom'

import { useAuth } from '../hooks/useAuth'
import { generateSlug } from '../lib/utils'
import type { Establishment } from '../lib/supabase'

const ESTABLISHMENT_TYPES: { value: Establishment['type']; label: string }[] = [
  { value: 'barbershop', label: 'Barbearia' },
  { value: 'salon', label: 'Salão de beleza' },
]

const BRAZILIAN_STATES = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG',
  'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
]

export function CreateEstablishmentPage() {
  const navigate = useNavigate()
  const { user, isLoading, isAuthenticated, establishments, createEstablishment, error, clearError } = useAuth()

  const [name, setName] = useState('')
  const [type, setType] = useState<Establishment['type']>('barbershop')
  const [phone, setPhone] = useState('')
  const [city, setCity] = useState('')
  const [state, setState] = useState('')
  const [address, setAddress] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [localError, setLocalError] = useState<string | null>(null)

  const handleSubmit = useCallback(
    async (event: React.FormEvent<HTMLFormElement>) => {
      event.preventDefault()
      setLocalError(null)
      clearError()

      if (!name.trim()) {
        setLocalError('Informe o nome do estabelecimento.')
        return
      }

      setIsSubmitting(true)

      try {
        const slug = generateSlug(name)
        await createEstablishment({
          name: name.trim(),
          type,
          slug,
          phone: phone.trim() || null,
          email: user?.email ?? null,
          city: city.trim() || null,
          state: state.trim() || null,
          address: address.trim() || null,
        })
        navigate('/dashboard', { replace: true })
      } catch (err) {
        setLocalError(err instanceof Error ? err.message : 'Falha ao cadastrar estabelecimento.')
      } finally {
        setIsSubmitting(false)
      }
    },
    [name, type, phone, city, state, address, user, createEstablishment, navigate, clearError],
  )

  if (!isAuthenticated && !isLoading) {
    return <Navigate to="/login" replace />
  }

  if (establishments.length > 0) {
    return <Navigate to="/dashboard" replace />
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

  const displayedError = localError || error

  return (
    <main className="auth-page">
      <section className="auth-card" style={{ maxWidth: '520px' }}>
        <div className="auth-card__header">
          <h1 className="auth-card__title">Cadastrar estabelecimento</h1>
          <p className="auth-card__subtitle">Preencha os dados principais da sua barbearia ou salão.</p>
        </div>

        {displayedError && (
          <div className="auth-card__alert" role="alert">
            {displayedError}
          </div>
        )}

        <form className="auth-form" onSubmit={handleSubmit} noValidate>
          <div className="auth-form__field">
            <label htmlFor="name">Nome do estabelecimento *</label>
            <input
              id="name"
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Ex: Barbearia Alpha"
              required
              autoComplete="organization"
              disabled={isSubmitting}
            />
          </div>

          <div className="auth-form__field">
            <label>Tipo *</label>
            <div className="radio-group">
              {ESTABLISHMENT_TYPES.map((option) => (
                <label key={option.value} className="radio-option">
                  <input
                    type="radio"
                    name="type"
                    value={option.value}
                    checked={type === option.value}
                    onChange={() => setType(option.value)}
                    disabled={isSubmitting}
                  />
                  <span>{option.label}</span>
                </label>
              ))}
            </div>
          </div>

          <div className="auth-form__field">
            <label htmlFor="phone">Telefone / WhatsApp</label>
            <input
              id="phone"
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="(11) 99999-9999"
              autoComplete="tel"
              disabled={isSubmitting}
            />
          </div>

          <div className="auth-form__row">
            <div className="auth-form__field">
              <label htmlFor="city">Cidade</label>
              <input
                id="city"
                type="text"
                value={city}
                onChange={(e) => setCity(e.target.value)}
                placeholder="São Paulo"
                autoComplete="address-level2"
                disabled={isSubmitting}
              />
            </div>

            <div className="auth-form__field">
              <label htmlFor="state">Estado</label>
              <select id="state" value={state} onChange={(e) => setState(e.target.value)} disabled={isSubmitting}>
                <option value="">UF</option>
                {BRAZILIAN_STATES.map((uf) => (
                  <option key={uf} value={uf}>
                    {uf}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="auth-form__field">
            <label htmlFor="address">Endereço</label>
            <input
              id="address"
              type="text"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="Rua, número, bairro"
              autoComplete="street-address"
              disabled={isSubmitting}
            />
          </div>

          <button type="submit" className="button button--primary" disabled={isSubmitting}>
            {isSubmitting ? 'Cadastrando...' : 'Cadastrar estabelecimento'}
          </button>
        </form>
      </section>
    </main>
  )
}
