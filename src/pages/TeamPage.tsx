import { useCallback, useEffect, useMemo, useState } from 'react'

import { DashboardLayout } from '../components/dashboard/DashboardLayout'
import { InviteMemberModal } from '../components/team/InviteMemberModal'
import { MemberPermissionsModal } from '../components/team/MemberPermissionsModal'
import { ProfessionalServicesModal } from '../components/team/ProfessionalServicesModal'
import { ConfirmDialog } from '../components/services/ConfirmDialog'
import { SparkIcon, TeamIcon } from '../components/dashboard/icons'
import { useAuth } from '../hooks/useAuth'
import { useActiveEstablishment } from '../hooks/useActiveEstablishment'
import {
  ASSIGNABLE_ROLES,
  INVITATION_STATUS_LABELS,
  TEAM_ROLE_LABELS,
  cancelTeamInvitation,
  createTeamInvitation,
  invitationStatus,
  listEstablishmentInvitations,
  listTeamMembers,
  setMemberActive,
  setMemberPermissions,
  updateMemberRole,
  type InvitationStatus,
  type TeamInvitation,
  type TeamMember,
  type TeamRole,
} from '../lib/team'
import {
  addProfessionalService,
  listEstablishmentProfessionals,
  removeProfessionalService,
  setProfessionalEnabled,
  type EstablishmentProfessional,
} from '../lib/professionals'

type RoleFilter = 'todos' | TeamRole
type StatusFilter = 'todos' | 'ativos' | 'inativos'
type InvitationFilter = 'todas' | InvitationStatus
type TeamTab = 'equipe' | 'profissionais'

function formatDate(value: string): string {
  try {
    return new Intl.DateTimeFormat('pt-BR', { dateStyle: 'medium' }).format(new Date(value))
  } catch {
    return value
  }
}

function initials(name: string): string {
  return name
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part.charAt(0).toUpperCase())
    .join('')
}

export function TeamPage() {
  const { user, refreshEstablishments } = useAuth()
  const establishment = useActiveEstablishment()
  const isOwner = establishment?.role === 'owner'

  const [tab, setTab] = useState<TeamTab>('equipe')

  const [members, setMembers] = useState<TeamMember[]>([])
  const [professionals, setProfessionals] = useState<EstablishmentProfessional[]>([])
  const [invitations, setInvitations] = useState<TeamInvitation[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)

  const [searchTerm, setSearchTerm] = useState('')
  const [roleFilter, setRoleFilter] = useState<RoleFilter>('todos')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('todos')
  const [invitationFilter, setInvitationFilter] = useState<InvitationFilter>('todas')

  const [enableMemberId, setEnableMemberId] = useState('')

  const [isInviteOpen, setInviteOpen] = useState(false)
  const [isSaving, setSaving] = useState(false)
  const [modalError, setModalError] = useState<string | null>(null)
  const [generatedLink, setGeneratedLink] = useState<string | null>(null)

  const [editingMember, setEditingMember] = useState<TeamMember | null>(null)
  const [deactivatingMember, setDeactivatingMember] = useState<TeamMember | null>(null)
  const [cancellingInvitation, setCancellingInvitation] = useState<TeamInvitation | null>(null)
  const [servicesProfessional, setServicesProfessional] = useState<EstablishmentProfessional | null>(null)
  const [isProfessionalBusy, setIsProfessionalBusy] = useState(false)

  const [isMutating, setIsMutating] = useState(false)

  const [feedback, setFeedback] = useState<string | null>(null)
  const [pageError, setPageError] = useState<string | null>(null)

  const loadTeam = useCallback(async () => {
    if (!establishment) return

    setIsLoading(true)
    setLoadError(null)
    setPageError(null)

    const [teamResult, professionalResult, invitationResult] = await Promise.allSettled([
      listTeamMembers(establishment.id),
      listEstablishmentProfessionals(establishment.id),
      isOwner ? listEstablishmentInvitations(establishment.id) : Promise.resolve([]),
    ])

    if (teamResult.status === 'fulfilled') {
      setMembers(teamResult.value)
    } else {
      setMembers([])
      setLoadError('Não foi possível carregar a equipe. Tente novamente.')
    }

    if (professionalResult.status === 'fulfilled') {
      setProfessionals(professionalResult.value)
    } else {
      setProfessionals([])
      setPageError('Não foi possível carregar os profissionais. Tente novamente.')
    }

    if (invitationResult.status === 'fulfilled') {
      setInvitations(invitationResult.value)
    } else {
      setInvitations([])
      setPageError('Não foi possível carregar os convites. Tente novamente.')
    }

    setIsLoading(false)
  }, [establishment, isOwner])

  useEffect(() => {
    // Carregamento assíncrono: os setState ocorrem após o await.
    // eslint-disable-next-line react-hooks/exhaustive-deps -- carga intencional na montagem/troca de estabelecimento
    void loadTeam()
  }, [loadTeam])

  const enabledMemberIds = useMemo(
    () => new Set(professionals.map((professional) => professional.member_id)),
    [professionals],
  )

  const enableCandidates = useMemo(
    () => members.filter((member) => member.is_active && !enabledMemberIds.has(member.id)),
    [members, enabledMemberIds],
  )

  const professionalsWithoutServices = useMemo(
    () => professionals.filter((professional) => professional.services.length === 0).length,
    [professionals],
  )

  const filteredMembers = useMemo(() => {
    const term = searchTerm.trim().toLowerCase()

    return members.filter((member) => {
      const name = member.profile?.full_name ?? ''
      if (term && !name.toLowerCase().includes(term)) return false
      if (roleFilter !== 'todos' && member.role !== roleFilter) return false
      if (statusFilter === 'ativos' && !member.is_active) return false
      if (statusFilter === 'inativos' && member.is_active) return false
      return true
    })
  }, [members, searchTerm, roleFilter, statusFilter])

  const filteredInvitations = useMemo(
    () =>
      invitations.filter((invitation) => {
        if (invitationFilter === 'todas') return true
        return invitationStatus(invitation) === invitationFilter
      }),
    [invitations, invitationFilter],
  )

  /** Habilita um membro como profissional de atendimento (RPC do banco). */
  const handleEnableProfessional = async () => {
    if (!establishment || !enableMemberId) return

    const member = members.find((item) => item.id === enableMemberId)

    if (!member) return

    setIsProfessionalBusy(true)
    setPageError(null)

    try {
      await setProfessionalEnabled(member.id, true)
      setEnableMemberId('')
      setFeedback(`${member.profile?.full_name ?? 'Membro'} agora é profissional de atendimento.`)
      await loadTeam()
    } catch (error) {
      setPageError(
        error instanceof Error && error.message
          ? error.message
          : 'Não foi possível habilitar o profissional. Tente novamente.',
      )
    } finally {
      setIsProfessionalBusy(false)
    }
  }

  /** Pausa ou retoma os atendimentos sem alterar o vínculo de funcionário. */
  const handleToggleAccepts = async (professional: EstablishmentProfessional) => {
    setIsProfessionalBusy(true)
    setPageError(null)

    try {
      await setProfessionalEnabled(professional.member_id, !professional.accepts_appointments)
      setFeedback(
        professional.accepts_appointments
          ? `Atendimentos pausados para ${professional.full_name ?? 'profissional'}. O vínculo e o cargo permanecem inalterados.`
          : `${professional.full_name ?? 'Profissional'} volta a receber atendimentos.`,
      )
      await loadTeam()
    } catch (error) {
      setPageError(
        error instanceof Error && error.message
          ? error.message
          : 'Não foi possível alterar a habilitação. Tente novamente.',
      )
    } finally {
      setIsProfessionalBusy(false)
    }
  }

  const handleAddService = async (serviceId: string) => {
    if (!servicesProfessional) return

    setIsProfessionalBusy(true)
    setModalError(null)

    try {
      await addProfessionalService(servicesProfessional.id, serviceId)
      setFeedback(`Serviço associado a ${servicesProfessional.full_name ?? 'profissional'}.`)
      await loadTeam()
    } catch (error) {
      setModalError(
        error instanceof Error && error.message
          ? error.message
          : 'Não foi possível associar o serviço. Tente novamente.',
      )
    } finally {
      setIsProfessionalBusy(false)
    }
  }

  const handleRemoveService = async (serviceId: string) => {
    if (!servicesProfessional) return

    setIsProfessionalBusy(true)
    setModalError(null)

    try {
      await removeProfessionalService(servicesProfessional.id, serviceId)
      setFeedback(`Serviço removido de ${servicesProfessional.full_name ?? 'profissional'}.`)
      await loadTeam()
    } catch (error) {
      setModalError(
        error instanceof Error && error.message
          ? error.message
          : 'Não foi possível remover a associação. Tente novamente.',
      )
    } finally {
      setIsProfessionalBusy(false)
    }
  }

  const handleInvite = async (input: { email: string; role: TeamRole; permissions: string[] }) => {
    if (!establishment) return

    setSaving(true)
    setModalError(null)

    try {
      const token = await createTeamInvitation(establishment.id, input)
      setGeneratedLink(`${window.location.origin}/convite/${token}`)
      setFeedback('Convite criado. Compartilhe o link com o funcionário.')
      await loadTeam()
    } catch (error) {
      setModalError(
        error instanceof Error && error.message
          ? error.message
          : 'Não foi possível criar o convite. Tente novamente.',
      )
    } finally {
      setSaving(false)
    }
  }

  const handleSaveMember = async (input: { role: TeamRole; permissions: string[] }) => {
    if (!editingMember) return

    setIsMutating(true)
    setModalError(null)

    try {
      await updateMemberRole(editingMember.id, input.role)
      await setMemberPermissions(editingMember.id, input.permissions)
      setFeedback('Membro atualizado com sucesso.')
      setEditingMember(null)
      await loadTeam()
      await refreshEstablishments()
    } catch (error) {
      setModalError(
        error instanceof Error && error.message
          ? error.message
          : 'Não foi possível atualizar o membro. Tente novamente.',
      )
    } finally {
      setIsMutating(false)
    }
  }

  const handleToggleMember = async () => {
    if (!deactivatingMember) return

    setIsMutating(true)
    setPageError(null)

    try {
      const nextStatus = !deactivatingMember.is_active
      await setMemberActive(deactivatingMember.id, nextStatus)
      setFeedback(
        nextStatus
          ? `Vínculo de ${deactivatingMember.profile?.full_name ?? 'membro'} reativado.`
          : `Vínculo de ${deactivatingMember.profile?.full_name ?? 'membro'} desativado.`,
      )
      setDeactivatingMember(null)
      await loadTeam()
      await refreshEstablishments()
    } catch (error) {
      setPageError(
        error instanceof Error && error.message
          ? error.message
          : 'Não foi possível alterar a situação do vínculo. Tente novamente.',
      )
    } finally {
      setIsMutating(false)
    }
  }

  const handleCancelInvitation = async () => {
    if (!cancellingInvitation) return

    setIsMutating(true)
    setPageError(null)

    try {
      await cancelTeamInvitation(cancellingInvitation.id)
      setFeedback('Convite cancelado.')
      setCancellingInvitation(null)
      await loadTeam()
    } catch (error) {
      setPageError(
        error instanceof Error && error.message
          ? error.message
          : 'Não foi possível cancelar o convite. Tente novamente.',
      )
    } finally {
      setIsMutating(false)
    }
  }

  const handleResendInvitation = async (invitation: TeamInvitation) => {
    if (!establishment || !invitation.email) return

    setIsMutating(true)
    setPageError(null)

    try {
      await cancelTeamInvitation(invitation.id)
      const token = await createTeamInvitation(establishment.id, {
        email: invitation.email,
        role: invitation.role,
        permissions: invitation.permissions,
      })
      setGeneratedLink(`${window.location.origin}/convite/${token}`)
      setInviteOpen(true)
      setFeedback('Novo link de convite gerado.')
      await loadTeam()
    } catch (error) {
      setPageError(
        error instanceof Error && error.message
          ? error.message
          : 'Não foi possível gerar um novo convite. Tente novamente.',
      )
    } finally {
      setIsMutating(false)
    }
  }

  return (
    <DashboardLayout>
      <section className="dash-welcome">
        <p className="dash-welcome__eyebrow">
          <SparkIcon className="dash-welcome__eyebrow-icon" />
          {establishment?.name ?? 'Estabelecimento'}
        </p>
        <h1 className="dash-welcome__title">Equipe</h1>
        <p className="dash-welcome__subtitle">
          {isOwner
            ? 'Gerencie os vínculos da equipe, os cargos, as permissões refinadas e os profissionais.'
            : 'Acompanha a equipe e os profissionais do estabelecimento. Apenas o proprietário administra.'}
        </p>
      </section>

      <div className="dash-tabs" role="tablist" aria-label="Seções da equipe">
        <button
          type="button"
          role="tab"
          aria-selected={tab === 'equipe'}
          className={`dash-tabs__tab${tab === 'equipe' ? ' dash-tabs__tab--active' : ''}`}
          onClick={() => setTab('equipe')}
        >
          Equipe
        </button>
        <button
          type="button"
          role="tab"
          aria-selected={tab === 'profissionais'}
          className={`dash-tabs__tab${tab === 'profissionais' ? ' dash-tabs__tab--active' : ''}`}
          onClick={() => setTab('profissionais')}
        >
          Profissionais
        </button>
      </div>

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

      {!isOwner && (
        <div className="dash-alert dash-alert--info" role="status">
          Sua permissão permite visualizar a equipe e os profissionais. Convites, cargos, permissões
          e habilitação de profissionais são exclusivos do proprietário.
        </div>
      )}

      {tab === 'profissionais' ? (
        <>
          <section className="dash-card dash-toolbar" aria-label="Ferramentas dos profissionais">
            <div className="dash-toolbar__filters">
              {isOwner && (
                <div className="dash-toolbar__field">
                  <label htmlFor="professional-member-enable">Habilitar profissional</label>
                  <select
                    id="professional-member-enable"
                    value={enableMemberId}
                    onChange={(event) => setEnableMemberId(event.target.value)}
                    disabled={isProfessionalBusy || enableCandidates.length === 0}
                  >
                    <option value="">
                      {enableCandidates.length === 0 ? 'Nenhum membro disponível' : 'Selecione um membro...'}
                    </option>
                    {enableCandidates.map((member) => (
                      <option key={member.id} value={member.id}>
                        {member.profile?.full_name ?? 'Membro da equipe'}
                        {' — '}
                        {TEAM_ROLE_LABELS[member.role]}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              <p className="dash-toolbar__summary" aria-live="polite">
                {professionals.length} profissional(is) habilitado(s) • {professionalsWithoutServices}
                {' '}sem serviços
              </p>
            </div>

            {isOwner && enableCandidates.length > 0 && (
              <button
                type="button"
                className="button button--primary"
                onClick={() => void handleEnableProfessional()}
                disabled={isProfessionalBusy || !enableMemberId}
              >
                Habilitar profissional
              </button>
            )}
          </section>

          <section className="dash-card" aria-label="Lista de profissionais">
            <header className="dash-list-head">
              <p className="dash-list-head__summary">
                {professionals.length === 0
                  ? 'Nenhum profissional habilitado ainda.'
                  : `${professionals.filter((professional) => professional.accepts_appointments).length} habilitado(s) para atendimentos • ${professionals.filter((professional) => !professional.accepts_appointments).length} em pausa`}
              </p>
            </header>

            {isLoading ? (
              <div className="dash-list-state" role="status">
                <div className="auth-card__spinner" aria-label="Carregando" />
                <p>Carregando os profissionais...</p>
              </div>
            ) : loadError ? (
              <div className="dash-list-state" role="alert">
                <p>{loadError}</p>
                <button
                  type="button"
                  className="button button--secondary"
                  onClick={() => {
                    setIsLoading(true)
                    void loadTeam()
                  }}
                >
                  Tentar novamente
                </button>
              </div>
            ) : professionals.length === 0 ? (
              <div className="dash-list-state">
                <TeamIcon width={28} height={28} />
                <p>Habilite membros da equipe como profissionais para associar serviços.</p>
              </div>
            ) : (
              <ul className="service-list">
                {professionals.map((professional) => {
                  const name = professional.full_name ?? 'Profissional'

                  return (
                    <li className="service-item" key={professional.id}>
                      <div className="service-item__main">
                        <div className="service-item__title-row">
                          <span className="team-avatar" aria-hidden="true">
                            {professional.avatar_url ? (
                              <img src={professional.avatar_url} alt="" />
                            ) : (
                              initials(name)
                            )}
                          </span>
                          <h2 className="service-item__name">{name}</h2>
                          <span className="service-item__badge">
                            {TEAM_ROLE_LABELS[professional.role]}
                          </span>
                          {!professional.is_active ? (
                            <span className="service-item__status service-item__status--inactive">
                              Vínculo inativo
                            </span>
                          ) : (
                            <span
                              className={`service-item__status ${
                                professional.accepts_appointments
                                  ? 'service-item__status--active'
                                  : 'service-item__status--inactive'
                              }`}
                            >
                              {professional.accepts_appointments ? 'Recebe atendimentos' : 'Em pausa'}
                            </span>
                          )}
                        </div>

                        <div className="service-item__meta">
                          <span className="service-item__meta-item">
                            {professional.services.length} serviço(s) associado(s)
                          </span>
                          {!professional.is_active && (
                            <span className="service-item__meta-item">
                              Nova associação é recusada enquanto o vínculo estiver desativado
                            </span>
                          )}
                        </div>
                      </div>

                      <div className="service-item__side">
                        {isOwner && professional.is_active && (
                          <div className="service-item__actions">
                            <button
                              type="button"
                              className="button button--secondary service-item__action"
                              onClick={() => {
                                setModalError(null)
                                setServicesProfessional(professional)
                              }}
                            >
                              Gerenciar serviços
                            </button>
                            <button
                              type="button"
                              className="button button--secondary service-item__action"
                              onClick={() => void handleToggleAccepts(professional)}
                              disabled={isProfessionalBusy}
                            >
                              {professional.accepts_appointments
                                ? 'Pausar atendimentos'
                                : 'Retomar atendimentos'}
                            </button>
                          </div>
                        )}
                      </div>
                    </li>
                  )
                })}
              </ul>
            )}
          </section>
        </>
      ) : (
        <>
          <section className="dash-card dash-toolbar" aria-label="Ferramentas da lista de equipe">
            <div className="dash-toolbar__filters">
              <div className="dash-toolbar__field">
                <label htmlFor="team-search">Buscar</label>
                <input
                  id="team-search"
                  type="search"
                  value={searchTerm}
                  onChange={(event) => setSearchTerm(event.target.value)}
                  placeholder="Buscar por nome..."
                />
              </div>

              <div className="dash-toolbar__field">
                <label htmlFor="team-role-filter">Cargo</label>
                <select
                  id="team-role-filter"
                  value={roleFilter}
                  onChange={(event) => setRoleFilter(event.target.value as RoleFilter)}
                >
                  <option value="todos">Todos</option>
                  {(['owner', ...ASSIGNABLE_ROLES] as TeamRole[]).map((role) => (
                    <option key={role} value={role}>
                      {TEAM_ROLE_LABELS[role]}
                    </option>
                  ))}
                </select>
              </div>

              <div className="dash-toolbar__field">
                <label htmlFor="team-status-filter">Situação</label>
                <select
                  id="team-status-filter"
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
              <button type="button" className="button button--primary" onClick={() => setInviteOpen(true)}>
                Convidar funcionário
              </button>
            )}
          </section>

          <section className="dash-card" aria-label="Lista de funcionários">
            <header className="dash-list-head">
              {!isLoading && !loadError && (
                <p className="dash-list-head__summary">
                  {members.length === 0
                    ? 'Nenhum membro vinculado ainda.'
                    : `${members.length} membro(s) • ${members.filter((member) => member.is_active).length} ativo(s)`}
                </p>
              )}
            </header>

            {isLoading ? (
              <div className="dash-list-state" role="status">
                <div className="auth-card__spinner" aria-label="Carregando" />
                <p>Carregando a equipe...</p>
              </div>
            ) : loadError ? (
              <div className="dash-list-state" role="alert">
                <p>{loadError}</p>
                <button
                  type="button"
                  className="button button--secondary"
                  onClick={() => {
                    setIsLoading(true)
                    void loadTeam()
                  }}
                >
                  Tentar novamente
                </button>
              </div>
            ) : filteredMembers.length === 0 ? (
              <div className="dash-list-state">
                <TeamIcon width={28} height={28} />
                <p>
                  {members.length === 0
                    ? 'Nenhum membro vinculado ainda. Convide sua equipe para começar.'
                    : 'Nenhum membro corresponde aos filtros selecionados.'}
                </p>
                {isOwner && members.length === 0 && (
                  <button
                    type="button"
                    className="button button--primary"
                    onClick={() => setInviteOpen(true)}
                  >
                    Convidar funcionário
                  </button>
                )}
              </div>
            ) : (
              <ul className="service-list">
                {filteredMembers.map((member) => {
                  const name = member.profile?.full_name ?? 'Membro da equipe'
                  const isSelf = member.user_id === user?.id

                  return (
                    <li className="service-item" key={member.id}>
                      <div className="service-item__main">
                        <div className="service-item__title-row">
                          <span className="team-avatar" aria-hidden="true">
                            {member.profile?.avatar_url ? (
                              <img src={member.profile.avatar_url} alt="" />
                            ) : (
                              initials(name)
                            )}
                          </span>
                          <h2 className="service-item__name">{name}</h2>
                          <span className="service-item__badge">{TEAM_ROLE_LABELS[member.role]}</span>
                          <span
                            className={`service-item__status ${
                              member.is_active
                                ? 'service-item__status--active'
                                : 'service-item__status--inactive'
                            }`}
                          >
                            {member.is_active ? 'Ativo' : 'Inativo'}
                          </span>
                        </div>

                        <div className="service-item__meta">
                          <span className="service-item__meta-item">
                            Entrou em {formatDate(member.created_at)}
                          </span>
                          {member.permissions.length > 0 && (
                            <span className="service-item__meta-item">
                              {member.permissions.length} permissão(ões) adicional(is)
                            </span>
                          )}
                        </div>
                      </div>

                      <div className="service-item__side">
                        {isOwner && !isSelf && (
                          <div className="service-item__actions">
                            <button
                              type="button"
                              className="button button--secondary service-item__action"
                              onClick={() => {
                                setModalError(null)
                                setEditingMember(member)
                              }}
                            >
                              Cargo e permissões
                            </button>
                            <button
                              type="button"
                              className="button button--secondary service-item__action"
                              onClick={() => {
                                setPageError(null)
                                setDeactivatingMember(member)
                              }}
                            >
                              {member.is_active ? 'Desativar' : 'Reativar'}
                            </button>
                          </div>
                        )}
                        {isSelf && <span className="team-self">Você</span>}
                      </div>
                    </li>
                  )
                })}
              </ul>
            )}
          </section>

          {isOwner && (
            <section className="dash-card" aria-label="Convites pendentes">
              <header className="dash-checklist__head">
                <div>
                  <h2 className="dash-card__title">Convites</h2>
                  <p className="dash-card__subtitle">
                    O link do convite não pode ser recuperado — apenas o hash é guardado. Gere um novo
                    link quando necessário.
                  </p>
                </div>
                <div className="dash-toolbar__field">
                  <label htmlFor="invitation-filter">Status</label>
                  <select
                    id="invitation-filter"
                    value={invitationFilter}
                    onChange={(event) => setInvitationFilter(event.target.value as InvitationFilter)}
                  >
                    <option value="todas">Todos</option>
                    <option value="pendente">Pendentes</option>
                    <option value="aceito">Aceitos</option>
                    <option value="cancelado">Cancelados</option>
                    <option value="expirado">Expirados</option>
                  </select>
                </div>
              </header>

              {filteredInvitations.length === 0 ? (
                <div className="dash-list-state">
                  <p>Nenhum convite nesta situação.</p>
                </div>
              ) : (
                <ul className="service-list">
                  {filteredInvitations.map((invitation) => {
                    const status = invitationStatus(invitation)

                    return (
                      <li className="service-item" key={invitation.id}>
                        <div className="service-item__main">
                          <div className="service-item__title-row">
                            <h2 className="service-item__name">
                              {invitation.email ?? invitation.phone ?? 'Convite'}
                            </h2>
                            <span className="service-item__badge">
                              {TEAM_ROLE_LABELS[invitation.role]}
                            </span>
                            <span
                              className={`service-item__status ${
                                status === 'pendente'
                                  ? 'service-item__status--active'
                                  : 'service-item__status--inactive'
                              }`}
                            >
                              {INVITATION_STATUS_LABELS[status]}
                            </span>
                          </div>
                          <div className="service-item__meta">
                            <span className="service-item__meta-item">
                              Criado em {formatDate(invitation.created_at)}
                            </span>
                            <span className="service-item__meta-item">
                              Expira em {formatDate(invitation.expires_at)}
                            </span>
                          </div>
                        </div>

                        <div className="service-item__side">
                          {status === 'pendente' && (
                            <div className="service-item__actions">
                              <button
                                type="button"
                                className="button button--secondary service-item__action"
                                onClick={() => void handleResendInvitation(invitation)}
                                disabled={isMutating}
                              >
                                Gerar novo link
                              </button>
                              <button
                                type="button"
                                className="button button--secondary service-item__action"
                                onClick={() => setCancellingInvitation(invitation)}
                                disabled={isMutating}
                              >
                                Cancelar
                              </button>
                            </div>
                          )}
                        </div>
                      </li>
                    )
                  })}
                </ul>
              )}
            </section>
          )}
        </>
      )}

      <InviteMemberModal
        isOpen={isInviteOpen}
        isSaving={isSaving}
        error={modalError}
        generatedLink={generatedLink}
        onClose={() => {
          setInviteOpen(false)
          setGeneratedLink(null)
          setModalError(null)
        }}
        onSubmit={(input) => void handleInvite(input)}
        onResetGeneratedLink={() => {
          setGeneratedLink(null)
          setModalError(null)
        }}
      />

      <MemberPermissionsModal
        key={editingMember?.id ?? 'sem-membro'}
        isOpen={editingMember !== null}
        member={editingMember}
        isSaving={isMutating}
        error={modalError}
        onClose={() => {
          setEditingMember(null)
          setModalError(null)
        }}
        onSubmit={(input) => void handleSaveMember(input)}
      />

      <ProfessionalServicesModal
        isOpen={servicesProfessional !== null}
        isBusy={isProfessionalBusy}
        error={modalError}
        professional={servicesProfessional}
        establishmentId={establishment?.id ?? ''}
        onClose={() => {
          setServicesProfessional(null)
          setModalError(null)
        }}
        onAddService={(serviceId) => void handleAddService(serviceId)}
        onRemoveService={(serviceId) => void handleRemoveService(serviceId)}
      />

      <ConfirmDialog
        isOpen={deactivatingMember !== null}
        title={deactivatingMember?.is_active ? 'Desativar vínculo' : 'Reativar vínculo'}
        message={
          deactivatingMember?.is_active
            ? `Desativar o vínculo de ${deactivatingMember?.profile?.full_name ?? 'membro'}? A conta continua existindo e os vínculos com outros estabelecimentos não são afetados.`
            : `Reativar o vínculo de ${deactivatingMember?.profile?.full_name ?? 'membro'}?`
        }
        confirmLabel={deactivatingMember?.is_active ? 'Desativar' : 'Reativar'}
        danger={Boolean(deactivatingMember?.is_active)}
        isBusy={isMutating}
        onConfirm={() => void handleToggleMember()}
        onCancel={() => setDeactivatingMember(null)}
      />

      <ConfirmDialog
        isOpen={cancellingInvitation !== null}
        title="Cancelar convite"
        message={`Cancelar o convite de ${cancellingInvitation?.email ?? 'contato'}? O link deixa de funcionar.`}
        confirmLabel="Cancelar convite"
        danger
        isBusy={isMutating}
        onConfirm={() => void handleCancelInvitation()}
        onCancel={() => setCancellingInvitation(null)}
      />
    </DashboardLayout>
  )
}
