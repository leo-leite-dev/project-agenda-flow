import { useCallback, useEffect, useMemo, useState } from 'react'

import { DashboardLayout } from '../components/dashboard/DashboardLayout'
import { ConfirmDialog } from '../components/services/ConfirmDialog'
import { ServiceFormModal, type ServiceFormValues } from '../components/services/ServiceFormModal'
import { ClockIcon, SparkIcon } from '../components/dashboard/icons'
import { useActiveEstablishment } from '../hooks/useActiveEstablishment'
import {
  SERVICE_CATEGORIES,
  formatBRL,
  listServices,
  serviceCategoryLabel,
  setServiceActive,
  createService,
  updateService,
  type EstablishmentService,
  type ServiceCategory,
} from '../lib/services'

type StatusFilter = 'todos' | 'ativos' | 'inativos'

function statusLabel(isActive: boolean): string {
  return isActive ? 'Ativo' : 'Inativo'
}

export function ServicesPage() {
  const establishment = useActiveEstablishment()

  // Somente o proprietário administra o catálogo. A garantia real está no
  // banco (as RPCs recusam não-proprietários), mas a interface não deve
  // expor controles administrativos a quem não pode usá-los.
  const isOwner = establishment?.role === 'owner'

  const [services, setServices] = useState<EstablishmentService[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [searchTerm, setSearchTerm] = useState('')
  const [categoryFilter, setCategoryFilter] = useState<'todas' | ServiceCategory>('todas')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('todos')

  const [isFormOpen, setFormOpen] = useState(false)
  const [editingService, setEditingService] = useState<EstablishmentService | null>(null)
  const [isSaving, setSaving] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)

  const [confirmTarget, setConfirmTarget] = useState<EstablishmentService | null>(null)
  const [isToggling, setIsToggling] = useState(false)

  const [feedback, setFeedback] = useState<string | null>(null)
  const [pageError, setPageError] = useState<string | null>(null)

  const loadServices = useCallback(async () => {
    if (!establishment) return

    try {
      const data = await listServices(establishment.id)
      setServices(data)
      setLoadError(null)
    } catch {
      setLoadError('Não foi possível carregar os serviços. Tente novamente.')
    } finally {
      setIsLoading(false)
    }
  }, [establishment])

  useEffect(() => {
    // Padrão de carregamento assíncrono: os setState acontecem após o await,
    // nunca sincronamente no corpo do efeito.
    // eslint-disable-next-line react-hooks/exhaustive-deps -- chamada intencional na montagem/troca de estabelecimento
    void loadServices()
  }, [loadServices])

  const filteredServices = useMemo(() => {
    const term = searchTerm.trim().toLowerCase()

    return services.filter((service) => {
      if (term && !service.name.toLowerCase().includes(term)) return false
      if (categoryFilter !== 'todas' && service.category !== categoryFilter) return false
      if (statusFilter === 'ativos' && !service.is_active) return false
      if (statusFilter === 'inativos' && service.is_active) return false
      return true
    })
  }, [services, searchTerm, categoryFilter, statusFilter])

  const activeCount = services.filter((service) => service.is_active).length

  const handleOpenCreate = () => {
    setEditingService(null)
    setFormError(null)
    setFormOpen(true)
  }

  const handleOpenEdit = (service: EstablishmentService) => {
    setEditingService(service)
    setFormError(null)
    setFormOpen(true)
  }

  const closeForm = () => {
    setFormOpen(false)
    setEditingService(null)
    setFormError(null)
  }

  const handleSubmit = async (values: ServiceFormValues) => {
    if (!establishment) return

    setSaving(true)
    setFormError(null)

    try {
      if (editingService) {
        await updateService(editingService.id, values)
        setFeedback('Serviço atualizado com sucesso.')
      } else {
        await createService(establishment.id, values)
        setFeedback('Serviço cadastrado com sucesso.')
      }

      closeForm()
      await loadServices()
    } catch (error) {
      setFormError(
        error instanceof Error && error.message
          ? error.message
          : 'Não foi possível salvar o serviço. Tente novamente.',
      )
    } finally {
      setSaving(false)
    }
  }

  const handleToggleActive = async () => {
    if (!confirmTarget) return

    setIsToggling(true)
    setPageError(null)

    try {
      const nextStatus = !confirmTarget.is_active
      await setServiceActive(confirmTarget.id, nextStatus)
      setFeedback(
        nextStatus
          ? `Serviço "${confirmTarget.name}" ativado.`
          : `Serviço "${confirmTarget.name}" desativado.`,
      )
      setConfirmTarget(null)
      await loadServices()
    } catch {
      setPageError('Não foi possível atualizar o status do serviço. Tente novamente.')
    } finally {
      setIsToggling(false)
    }
  }

  return (
    <DashboardLayout>
      <section className="dash-welcome">
        <p className="dash-welcome__eyebrow">
          <SparkIcon className="dash-welcome__eyebrow-icon" />
          {establishment?.name ?? 'Estabelecimento'}
        </p>
        <h1 className="dash-welcome__title">Serviços</h1>
        <p className="dash-welcome__subtitle">
          Catálogo de serviços oferecidos pelo estabelecimento. Apenas o proprietário pode
          cadastrar e editar.
        </p>
      </section>

      {feedback && (
        <div className="dash-alert dash-alert--success" role="status">
          {feedback}
          <button
            type="button"
            className="dash-alert__dismiss"
            onClick={() => setFeedback(null)}
            aria-label="Dispensar mensagem"
          >
            Fechar
          </button>
        </div>
      )}

      {pageError && (
        <div className="dash-alert dash-alert--error" role="alert">
          {pageError}
        </div>
      )}

      <section className="dash-card dash-toolbar" aria-label="Ferramentas da lista de serviços">
        <div className="dash-toolbar__filters">
          <div className="dash-toolbar__field">
            <label htmlFor="service-search">Buscar</label>
            <input
              id="service-search"
              type="search"
              value={searchTerm}
              onChange={(event) => setSearchTerm(event.target.value)}
              placeholder="Buscar por nome..."
            />
          </div>

          <div className="dash-toolbar__field">
            <label htmlFor="service-category-filter">Categoria</label>
            <select
              id="service-category-filter"
              value={categoryFilter}
              onChange={(event) =>
                setCategoryFilter(event.target.value as 'todas' | ServiceCategory)
              }
            >
              <option value="todas">Todas</option>
              {SERVICE_CATEGORIES.map((category) => (
                <option key={category.value} value={category.value}>
                  {category.label}
                </option>
              ))}
            </select>
          </div>

          <div className="dash-toolbar__field">
            <label htmlFor="service-status-filter">Status</label>
            <select
              id="service-status-filter"
              value={statusFilter}
              onChange={(event) => setStatusFilter(event.target.value as StatusFilter)}
            >
              <option value="todos">Todos</option>
              <option value="ativos">Ativos</option>
              <option value="inativos">Inativos</option>
            </select>
          </div>
        </div>

        {isOwner && (
          <button type="button" className="button button--primary" onClick={handleOpenCreate}>
            Novo serviço
          </button>
        )}
      </section>

      <section className="dash-card" aria-label="Lista de serviços">
        <header className="dash-list-head">
          <p className="dash-list-head__summary">
            {services.length === 0
              ? 'Nenhum serviço cadastrado.'
              : `${services.length} serviço(s) • ${activeCount} ativo(s)`}
          </p>
        </header>

        {isLoading ? (
          <div className="dash-list-state" role="status">
            <div className="auth-card__spinner" aria-label="Carregando" />
            <p>Carregando serviços...</p>
          </div>
        ) : loadError ? (
          <div className="dash-list-state" role="alert">
            <p>{loadError}</p>
            <button
              type="button"
              className="button button--secondary"
              onClick={() => {
                setIsLoading(true)
                void loadServices()
              }}
            >
              Tentar novamente
            </button>
          </div>
        ) : services.length === 0 ? (
          <div className="dash-list-state">
            <p>
              Nenhum serviço cadastrado ainda. Cadastre o primeiro serviço para preparar a agenda
              de atendimentos.
            </p>
            {isOwner && (
              <button type="button" className="button button--primary" onClick={handleOpenCreate}>
                Cadastrar o primeiro serviço
              </button>
            )}
          </div>
        ) : filteredServices.length === 0 ? (
          <div className="dash-list-state">
            <p>Nenhum serviço corresponde aos filtros selecionados.</p>
          </div>
        ) : (
          <ul className="service-list">
            {filteredServices.map((service) => (
              <li
                key={service.id}
                className={`service-item${service.is_active ? '' : ' service-item--inactive'}`}
              >
                <div className="service-item__main">
                  <div className="service-item__title-row">
                    <h2 className="service-item__name">{service.name}</h2>
                    <span
                      className={`service-item__status ${
                        service.is_active
                          ? 'service-item__status--active'
                          : 'service-item__status--inactive'
                      }`}
                    >
                      {statusLabel(service.is_active)}
                    </span>
                  </div>

                  {service.description && (
                    <p className="service-item__description">{service.description}</p>
                  )}

                  <div className="service-item__meta">
                    <span className="service-item__badge">
                      {serviceCategoryLabel(service.category)}
                    </span>
                    <span className="service-item__meta-item">
                      <ClockIcon width={14} height={14} />
                      {service.duration_minutes} min
                    </span>
                  </div>
                </div>

                <div className="service-item__side">
                  <span className="service-item__price">{formatBRL(service.price_cents)}</span>

                  <div className="service-item__actions">
                    {isOwner && (
                      <>
                        <button
                          type="button"
                          className="button button--secondary service-item__action"
                          onClick={() => handleOpenEdit(service)}
                        >
                          Editar
                        </button>
                        <button
                          type="button"
                          className={`button ${
                            service.is_active ? 'button--secondary' : 'button--primary'
                          } service-item__action`}
                          onClick={() => {
                            setPageError(null)
                            setConfirmTarget(service)
                          }}
                        >
                          {service.is_active ? 'Desativar' : 'Ativar'}
                        </button>
                      </>
                    )}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      <ServiceFormModal
        key={editingService?.id ?? 'novo-servico'}
        isOpen={isFormOpen}
        service={editingService}
        isSaving={isSaving}
        error={formError}
        onClose={closeForm}
        onSubmit={(values) => void handleSubmit(values)}
      />

      <ConfirmDialog
        isOpen={confirmTarget !== null}
        title={confirmTarget?.is_active ? 'Desativar serviço' : 'Ativar serviço'}
        message={
          confirmTarget?.is_active
            ? `Desativar o serviço "${confirmTarget?.name}"? Ele continuará no catálogo, mas não poderá ser agendado.`
            : `Ativar o serviço "${confirmTarget?.name}"?`
        }
        confirmLabel={confirmTarget?.is_active ? 'Desativar' : 'Ativar'}
        danger={Boolean(confirmTarget?.is_active)}
        isBusy={isToggling}
        onConfirm={() => void handleToggleActive()}
        onCancel={() => setConfirmTarget(null)}
      />
    </DashboardLayout>
  )
}
