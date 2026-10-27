import { useEffect, useState } from 'react'

import { CloseIcon } from '../dashboard/icons'
import {
  listServices,
  serviceCategoryLabel,
  type EstablishmentService,
} from '../../lib/services'
import type { EstablishmentProfessional } from '../../lib/professionals'

interface ProfessionalServicesModalProps {
  isOpen: boolean
  isBusy: boolean
  error: string | null
  professional: EstablishmentProfessional | null
  establishmentId: string
  onClose: () => void
  onAddService: (serviceId: string) => void
  onRemoveService: (serviceId: string) => void
}

/**
 * Associação de serviços a um profissional de atendimento. A lista exibe o
 * catálogo REAL do estabelecimento ativo (RLS): só entram serviços do próprio
 * tenant. Associações com serviços inativos são preservadas e visíveis, mas
 * serviços inativos não recebem novas associações. Cada alternância é salva
 * no banco por RPC — o isBusy evita salvamentos duplicados.
 */
export function ProfessionalServicesModal({
  isOpen,
  isBusy,
  error,
  professional,
  establishmentId,
  onClose,
  onAddService,
  onRemoveService,
}: ProfessionalServicesModalProps) {
  const [services, setServices] = useState<EstablishmentService[] | null>(null)
  const [servicesError, setServicesError] = useState<string | null>(null)

  useEffect(() => {
    if (!isOpen) return

    let isMounted = true

    void listServices(establishmentId)
      .then((data) => {
        if (isMounted) {
          setServices(data)
          setServicesError(null)
        }
      })
      .catch(() => {
        if (isMounted) {
          setServicesError('Não foi possível carregar os serviços. Tente novamente.')
        }
      })

    return () => {
      isMounted = false
    }
  }, [isOpen, establishmentId, professional?.id])

  useEffect(() => {
    if (!isOpen) return

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !isBusy) onClose()
    }

    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, isBusy, onClose])

  if (!isOpen || !professional) return null

  const associatedIds = new Set(professional.services.map((service) => service.id))
  const inactiveAssociated = professional.services.filter((service) => !service.is_active)

  const handleToggle = (service: EstablishmentService) => {
    if (isBusy) return

    if (associatedIds.has(service.id)) {
      onRemoveService(service.id)
    } else {
      onAddService(service.id)
    }
  }

  return (
    <div
      className="modal-backdrop"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !isBusy) onClose()
      }}
    >
      <div
        className="modal modal--professional-services"
        role="dialog"
        aria-modal="true"
        aria-labelledby="professional-services-title"
      >
        <div className="modal__header">
          <div>
            <h2 className="modal__title" id="professional-services-title">
              Serviços de {professional.full_name ?? 'profissional'}
            </h2>
            <p className="modal__subtitle">
              Marque os serviços que o profissional executa. O mesmo serviço pode ter vários
              profissionais.
            </p>
          </div>
          <button
            type="button"
            className="dash-icon-button modal__close"
            onClick={onClose}
            aria-label="Fechar lista de serviços"
            disabled={isBusy}
          >
            <CloseIcon />
          </button>
        </div>

        {error && (
          <div className="modal__alert" role="alert">
            {error}
          </div>
        )}

        {servicesError && (
          <div className="modal__alert" role="alert">
            {servicesError}
          </div>
        )}

        {services === null && !servicesError ? (
          <div className="dash-list-state" role="status">
            <div className="auth-card__spinner" aria-label="Carregando" />
            <p>Carregando os serviços...</p>
          </div>
        ) : services !== null && services.length === 0 ? (
          <div className="dash-list-state">
            <p>Nenhum serviço cadastrado ainda. Cadastre serviços para associá-los.</p>
          </div>
        ) : (
          <ul className="professional-services">
            {(services ?? []).map((service) => {
              const associated = associatedIds.has(service.id)
              const blocked = !service.is_active && !associated

              return (
                <li
                  className={`professional-services__item${service.is_active ? '' : ' professional-services__item--inactive'}`}
                  key={service.id}
                >
                  <label className="professional-services__label">
                    <input
                      type="checkbox"
                      checked={associated}
                      disabled={isBusy || blocked}
                      onChange={() => handleToggle(service)}
                      aria-label={`${associated ? 'Remover' : 'Associar'} ${service.name}`}
                      title={
                        blocked
                          ? 'Serviço inativo não pode ser associado'
                          : associated
                            ? 'Remover serviço do profissional'
                            : 'Associar serviço ao profissional'
                      }
                    />
                    <span className="professional-services__name">{service.name}</span>
                    <span className="professional-services__meta">
                      {serviceCategoryLabel(service.category as EstablishmentService['category'])}
                    </span>
                    {!service.is_active && (
                      <span className="professional-services__inactive">Inativo</span>
                    )}
                  </label>
                </li>
              )
            })}
          </ul>
        )}

        <div className="modal__actions">
          {inactiveAssociated.length > 0 && (
            <p className="modal__hint professional-services__hint">
              {inactiveAssociated.length} serviço(s) deste profissional estão inativos no catálogo —
              as associações ficam preservadas, mas o serviço não pode ser usado enquanto inativo.
            </p>
          )}
          <button
            type="button"
            className="button button--secondary"
            onClick={onClose}
            disabled={isBusy}
          >
            Fechar
          </button>
        </div>
      </div>
    </div>
  )
}
