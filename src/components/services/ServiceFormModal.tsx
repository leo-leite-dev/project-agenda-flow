import { useEffect, useRef, useState } from 'react'

import type { EstablishmentService, ServiceCategory } from '../../lib/services'
import {
  SERVICE_CATEGORIES,
  buildBRLMask,
  parseBRLToCents,
} from '../../lib/services'
import { CloseIcon } from '../dashboard/icons'

export interface ServiceFormValues {
  name: string
  description: string | null
  category: ServiceCategory
  duration_minutes: number
  price_cents: number
  is_active: boolean
}

interface ServiceFormModalProps {
  isOpen: boolean
  /** Serviço em edição; null quando é um cadastro novo. */
  service: EstablishmentService | null
  isSaving: boolean
  error: string | null
  onClose: () => void
  onSubmit: (values: ServiceFormValues) => void
}

interface FormState {
  name: string
  description: string
  category: ServiceCategory
  duration: string
  price: string
  isActive: boolean
}

function emptyForm(): FormState {
  return {
    name: '',
    description: '',
    category: 'cabelo',
    duration: '30',
    price: '',
    isActive: true,
  }
}

function formFromService(service: EstablishmentService): FormState {
  return {
    name: service.name,
    description: service.description ?? '',
    category: service.category,
    duration: String(service.duration_minutes),
    price: (service.price_cents / 100).toFixed(2).replace('.', ','),
    isActive: service.is_active,
  }
}

/** Validação client-side; o banco valida novamente nas RPCs. */
function validate(state: FormState): Partial<Record<keyof FormState, string>> {
  const errors: Partial<Record<keyof FormState, string>> = {}

  if (state.name.trim().length === 0) {
    errors.name = 'Informe o nome do serviço.'
  } else if (state.name.trim().length > 120) {
    errors.name = 'O nome deve ter até 120 caracteres.'
  }

  if (state.description.trim().length > 500) {
    errors.description = 'A descrição deve ter até 500 caracteres.'
  }

  const duration = Number(state.duration)

  if (state.duration.trim().length === 0 || Number.isNaN(duration) || duration <= 0) {
    errors.duration = 'A duração deve ser maior que zero.'
  } else if (duration > 1440) {
    errors.duration = 'A duração não pode exceder 1440 minutos (24h).'
  } else if (!Number.isInteger(duration)) {
    errors.duration = 'Informe a duração em minutos inteiros.'
  }

  const priceCents = parseBRLToCents(state.price)

  if (state.price.trim().length === 0 || priceCents === null) {
    errors.price = 'Informe o preço do serviço.'
  } else if (priceCents < 0) {
    errors.price = 'O preço não pode ser negativo.'
  }

  return errors
}

export function ServiceFormModal({
  isOpen,
  service,
  isSaving,
  error,
  onClose,
  onSubmit,
}: ServiceFormModalProps) {
  // O estado inicial é derivado de `service` na montagem. O componente é
  // remontado (via key no pai) a cada mudança de alvo de edição.
  const [form, setForm] = useState<FormState>(() =>
    service ? formFromService(service) : emptyForm(),
  )
  const [fieldErrors, setFieldErrors] = useState<Partial<Record<keyof FormState, string>>>({})
  const nameRef = useRef<HTMLInputElement | null>(null)

  const isEditing = service !== null

  useEffect(() => {
    if (!isOpen) return

    nameRef.current?.focus()

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !isSaving) onClose()
    }

    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, isSaving, onClose])

  if (!isOpen) return null

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (isSaving) return

    const errors = validate(form)

    if (Object.keys(errors).length > 0) {
      setFieldErrors(errors)
      return
    }

    setFieldErrors({})
    onSubmit({
      name: form.name.trim(),
      description: form.description.trim() || null,
      category: form.category,
      duration_minutes: Number(form.duration),
      price_cents: parseBRLToCents(form.price) ?? 0,
      is_active: form.isActive,
    })
  }

  return (
    <div
      className="modal-backdrop"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !isSaving) onClose()
      }}
    >
      <div className="modal" role="dialog" aria-modal="true" aria-labelledby="service-form-title">
        <div className="modal__header">
          <div>
            <h2 className="modal__title" id="service-form-title">
              {isEditing ? 'Editar serviço' : 'Novo serviço'}
            </h2>
            <p className="modal__subtitle">
              {isEditing
                ? 'Atualize as informações do serviço.'
                : 'Cadastre um serviço do catálogo do estabelecimento.'}
            </p>
          </div>
          <button
            type="button"
            className="dash-icon-button modal__close"
            onClick={onClose}
            aria-label="Fechar formulário"
            disabled={isSaving}
          >
            <CloseIcon />
          </button>
        </div>

        {error && (
          <div className="modal__alert" role="alert">
            {error}
          </div>
        )}

        <form className="modal__form" onSubmit={handleSubmit} noValidate>
          <div className="modal__field">
            <label htmlFor="service-name">
              Nome do serviço <span aria-hidden="true">*</span>
            </label>
            <input
              id="service-name"
              ref={nameRef}
              type="text"
              value={form.name}
              onChange={(event) => setForm((state) => ({ ...state, name: event.target.value }))}
              placeholder="Ex.: Corte Masculino"
              maxLength={120}
              required
              disabled={isSaving}
              aria-invalid={Boolean(fieldErrors.name)}
              aria-describedby={fieldErrors.name ? 'service-name-error' : undefined}
            />
            {fieldErrors.name && (
              <p className="modal__field-error" id="service-name-error">
                {fieldErrors.name}
              </p>
            )}
          </div>

          <div className="modal__field">
            <label htmlFor="service-description">Descrição (opcional)</label>
            <textarea
              id="service-description"
              value={form.description}
              onChange={(event) =>
                setForm((state) => ({ ...state, description: event.target.value }))
              }
              placeholder="Explique o que está incluído no serviço."
              rows={3}
              maxLength={500}
              disabled={isSaving}
              aria-invalid={Boolean(fieldErrors.description)}
              aria-describedby={fieldErrors.description ? 'service-description-error' : undefined}
            />
            {fieldErrors.description && (
              <p className="modal__field-error" id="service-description-error">
                {fieldErrors.description}
              </p>
            )}
          </div>

          <div className="modal__row">
            <div className="modal__field">
              <label htmlFor="service-category">Categoria</label>
              <select
                id="service-category"
                value={form.category}
                onChange={(event) =>
                  setForm((state) => ({ ...state, category: event.target.value as ServiceCategory }))
                }
                disabled={isSaving}
              >
                {SERVICE_CATEGORIES.map((category) => (
                  <option key={category.value} value={category.value}>
                    {category.label}
                  </option>
                ))}
              </select>
            </div>

            <div className="modal__field">
              <label htmlFor="service-duration">
                Duração (minutos) <span aria-hidden="true">*</span>
              </label>
              <input
                id="service-duration"
                type="number"
                inputMode="numeric"
                min={1}
                max={1440}
                step={5}
                value={form.duration}
                onChange={(event) =>
                  setForm((state) => ({ ...state, duration: event.target.value }))
                }
                placeholder="30"
                required
                disabled={isSaving}
                aria-invalid={Boolean(fieldErrors.duration)}
                aria-describedby={fieldErrors.duration ? 'service-duration-error' : undefined}
              />
              {fieldErrors.duration && (
                <p className="modal__field-error" id="service-duration-error">
                  {fieldErrors.duration}
                </p>
              )}
            </div>
          </div>

          <div className="modal__row">
            <div className="modal__field">
              <label htmlFor="service-price">
                Preço <span aria-hidden="true">*</span>
              </label>
              <input
                id="service-price"
                type="text"
                inputMode="decimal"
                value={form.price}
                onChange={(event) =>
                  setForm((state) => ({ ...state, price: buildBRLMask(event.target.value) }))
                }
                placeholder="R$ 0,00"
                required
                disabled={isSaving}
                aria-invalid={Boolean(fieldErrors.price)}
                aria-describedby={fieldErrors.price ? 'service-price-error' : undefined}
              />
              {fieldErrors.price && (
                <p className="modal__field-error" id="service-price-error">
                  {fieldErrors.price}
                </p>
              )}
            </div>

            <div className="modal__field">
              <span className="modal__field-label" id="service-status-label">
                Status
              </span>
              <label className="modal__switch" htmlFor="service-active">
                <input
                  id="service-active"
                  type="checkbox"
                  checked={form.isActive}
                  onChange={(event) =>
                    setForm((state) => ({ ...state, isActive: event.target.checked }))
                  }
                  disabled={isSaving}
                  aria-labelledby="service-status-label"
                />
                <span>{form.isActive ? 'Ativo' : 'Inativo'}</span>
              </label>
            </div>
          </div>

          <div className="modal__actions">
            <button
              type="button"
              className="button button--secondary"
              onClick={onClose}
              disabled={isSaving}
            >
              Cancelar
            </button>
            <button type="submit" className="button button--primary" disabled={isSaving}>
              {isSaving
                ? 'Salvando...'
                : isEditing
                  ? 'Salvar alterações'
                  : 'Cadastrar serviço'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
