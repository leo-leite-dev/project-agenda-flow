import { useCallback, useEffect, useMemo, useState } from 'react'

import { TeamIcon } from '../dashboard/icons'
import { TEAM_ROLE_LABELS, type TeamMember } from '../../lib/team'
import {
  correctAttendanceRecord,
  fetchEstablishmentClock,
  listAttendanceExceptions,
  listAttendanceRecords,
  listEstablishmentSchedules,
  recordCheckIn,
  recordCheckOut,
  recordAttendanceException,
  resolvePresenceStatus,
  saveMemberSchedule,
  scheduleSummary,
  type AttendanceException,
  type AttendanceRecord,
  type EstablishmentClock,
  type ScheduleDraft,
  type WorkSchedule,
} from '../../lib/schedules'
import { WorkScheduleModal } from './WorkScheduleModal'
import { AttendanceExceptionModal } from './AttendanceExceptionModal'
import { AttendanceHistoryModal } from './AttendanceHistoryModal'

interface SchedulesPresenceTabProps {
  establishmentId: string | null
  establishmentName: string | null
  isOwner: boolean
  members: TeamMember[]
  currentUserId: string | null
}

interface MemberPresence {
  member: TeamMember
  schedules: WorkSchedule[]
  attendance: AttendanceRecord | null
  status: {
    key: string
    label: string
    offScheduleCheckIn: boolean
  }
  lastCheckIn: string | null
  lastCheckOut: string | null
}

function formatStamp(iso: string | null, clock: EstablishmentClock | null): string {
  if (!iso) return '—'
  const formatted = new Intl.DateTimeFormat('pt-BR', {
    timeZone: clock?.timezone ?? undefined,
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso))
  return formatted
}

/** Supabase/PostgREST devolvem objetos {message}; não são Error. */
function errorMessage(error: unknown, fallback: string): string {
  const message =
    typeof error === 'object' && error !== null && 'message' in error
      ? (error as { message?: unknown }).message
      : undefined
  return typeof message === 'string' && message.trim() ? message : fallback
}

const memberName = (member: TeamMember): string =>
  member.profile?.full_name ?? 'Membro da equipe'

export function SchedulesPresenceTab({
  establishmentId,
  establishmentName,
  isOwner,
  members,
  currentUserId,
}: SchedulesPresenceTabProps) {
  const [isLoading, setIsLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [schedules, setSchedules] = useState<WorkSchedule[]>([])
  const [records, setRecords] = useState<AttendanceRecord[]>([])
  const [exceptions, setExceptions] = useState<AttendanceException[]>([])
  const [clock, setClock] = useState<EstablishmentClock | null>(null)

  const [isCheckInBusy, setCheckInBusy] = useState(false)
  const [isCheckOutBusy, setCheckOutBusy] = useState(false)

  const [schedulingMember, setSchedulingMember] = useState<TeamMember | null>(null)
  const [scheduleBusy, setScheduleBusy] = useState(false)
  const [scheduleError, setScheduleError] = useState<string | null>(null)

  const [exceptionMember, setExceptionMember] = useState<TeamMember | null>(null)
  const [exceptionBusy, setExceptionBusy] = useState(false)
  const [exceptionError, setExceptionError] = useState<string | null>(null)

  const [historyMember, setHistoryMember] = useState<TeamMember | null>(null)
  const [correctionBusy, setCorrectionBusy] = useState(false)
  const [correctionError, setCorrectionError] = useState<string | null>(null)

  const [feedback, setFeedback] = useState<string | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)

  const loadTab = useCallback(async () => {
    if (!establishmentId) {
      setIsLoading(false)
      return
    }

    setIsLoading(true)
    setLoadError(null)

    try {
      const [scheduleData, recordData, exceptionData, clockData] = await Promise.all([
        listEstablishmentSchedules(establishmentId),
        listAttendanceRecords(establishmentId, { limit: 120 }),
        listAttendanceExceptions(establishmentId, { limit: 120 }),
        fetchEstablishmentClock(establishmentId),
      ])

      setSchedules(scheduleData)
      setRecords(recordData)
      setExceptions(exceptionData)
      setClock(clockData)
    } catch {
      setSchedules([])
      setRecords([])
      setExceptions([])
      setClock(null)
      setLoadError('Não foi possível carregar as escalas e presença. Tente novamente.')
    } finally {
      setIsLoading(false)
    }
  }, [establishmentId])

  useEffect(() => {
    void loadTab()
  }, [loadTab])

  const schedulesByMember = useMemo(() => {
    const map = new Map<string, WorkSchedule[]>()
    for (const schedule of schedules) {
      const current = map.get(schedule.member_id) ?? []
      current.push(schedule)
      map.set(schedule.member_id, current)
    }
    return map
  }, [schedules])

  const recordsByMember = useMemo(() => {
    const map = new Map<string, AttendanceRecord>()
    if (!clock?.local_date) return map
    for (const record of records) {
      if (record.work_date === clock?.local_date) {
        map.set(record.member_id, record)
      }
    }
    return map
  }, [records, clock])

  const exceptionsByMember = useMemo(() => {
    const map = new Map<string, AttendanceException[]>()
    const today = clock?.local_date
    if (!today) return map
    for (const exception of exceptions) {
      if (exception.start_date <= today && today <= exception.end_date) {
        const current = map.get(exception.member_id) ?? []
        current.push(exception)
        map.set(exception.member_id, current)
      }
    }
    return map
  }, [exceptions, clock?.local_date])

  const presenceList = useMemo<MemberPresence[]>(
    () =>
      members.map((member) => {
        const memberSchedules = schedulesByMember.get(member.id) ?? []
        const attendance = recordsByMember.get(member.id) ?? null
        const offSchedule = resolvePresenceStatus({
          schedules: memberSchedules,
          attendance,
          exceptions: exceptionsByMember.get(member.id) ?? [],
          clock,
        })

        return {
          member,
          schedules: memberSchedules,
          attendance,
          status: offSchedule,
          lastCheckIn: attendance?.check_in_at ?? null,
          lastCheckOut: attendance?.check_out_at ?? null,
        }
      }),
    [members, schedulesByMember, recordsByMember, exceptionsByMember, clock],
  )

  const selfMember = members.find((member) => member.user_id === currentUserId) ?? null
  const selfPresence = useMemo<MemberPresence | null>(() => {
    if (!selfMember) return null
    return presenceList.find((item) => item.member.id === selfMember.id) ?? null
  }, [selfMember, presenceList])

  const selfCanCheckIn = Boolean(
    establishmentId &&
      !loadError &&
      selfMember?.is_active !== false &&
      selfPresence?.attendance?.check_in_at == null,
  )
  const selfCanCheckOut = Boolean(
    establishmentId &&
      !loadError &&
      selfPresence?.attendance?.check_in_at &&
      selfPresence?.attendance?.check_out_at == null,
  )

  const handleCheckIn = async () => {
    if (!establishmentId || !selfCanCheckIn || isCheckInBusy) return

    setCheckInBusy(true)
    setActionError(null)

    try {
      const record = await recordCheckIn(establishmentId)
      setFeedback(
        `Entrada registrada pelo servidor às ${formatStamp(record.check_in_at, clock)}.`,
      )
      await loadTab()
    } catch (error) {
      setActionError(
        errorMessage(error, 'Não foi possível registrar a entrada. Tente novamente.'),
      )
    } finally {
      setCheckInBusy(false)
    }
  }

  const handleCheckOut = async () => {
    if (!establishmentId || !selfCanCheckOut || isCheckOutBusy) return

    setCheckOutBusy(true)
    setActionError(null)

    try {
      const record = await recordCheckOut(establishmentId)
      setFeedback(`Saída registrada pelo servidor às ${formatStamp(record.check_out_at, clock)}.`)
      await loadTab()
    } catch (error) {
      setActionError(
        errorMessage(error, 'Não foi possível registrar a saída. Tente novamente.'),
      )
    } finally {
      setCheckOutBusy(false)
    }
  }

  const handleSaveSchedule = async (drafts: ScheduleDraft[]) => {
    if (!schedulingMember) return

    setScheduleBusy(true)
    setScheduleError(null)

    try {
      await saveMemberSchedule(schedulingMember.id, drafts)
      setFeedback(`Escala de ${memberName(schedulingMember)} salva.`)
      setSchedulingMember(null)
      await loadTab()
    } catch (error) {
      setScheduleError(errorMessage(error, 'Não foi possível salvar a escala. Tente novamente.'))
    } finally {
      setScheduleBusy(false)
    }
  }

  const handleExceptionSubmit = async (input: {
    exceptionType: Parameters<typeof recordAttendanceException>[1]
    startDate: string
    endDate: string
    reason: string | null
  }) => {
    if (!exceptionMember) return

    setExceptionBusy(true)
    setExceptionError(null)

    try {
      await recordAttendanceException(
        exceptionMember.id,
        input.exceptionType,
        input.startDate,
        input.endDate,
        input.reason,
      )
      setFeedback(`Ocorrência registrada para ${memberName(exceptionMember)}.`)
      setExceptionMember(null)
      await loadTab()
    } catch (error) {
      setExceptionError(
        errorMessage(error, 'Não foi possível registrar a ocorrência. Tente novamente.'),
      )
    } finally {
      setExceptionBusy(false)
    }
  }

  const handleCorrectionSubmit = async (input: {
    attendanceId: string
    checkInAt?: string
    checkOutAt?: string
    reason: string
  }) => {
    if (!historyMember) return

    setCorrectionBusy(true)
    setCorrectionError(null)

    try {
      await correctAttendanceRecord(input.attendanceId, {
        checkInAt: input.checkInAt ?? null,
        checkOutAt: input.checkOutAt ?? null,
        reason: input.reason,
      })
      setFeedback('Registro corrigido com justificativa e auditoria no banco.')
      setHistoryMember(null)
      await loadTab()
    } catch (error) {
      setCorrectionError(
        errorMessage(error, 'Não foi possível corrigir o registro. Tente novamente.'),
      )
    } finally {
      setCorrectionBusy(false)
    }
  }

  if (!establishmentId) return null

  return (
    <>
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

      {loadError && (
        <div className="dash-alert dash-alert--error" role="alert">
          {loadError}
          <button type="button" className="button button--secondary" onClick={() => void loadTab()}>
            Tentar novamente
          </button>
        </div>
      )}

      {selfMember && (
      <section className="dash-card presence-self" aria-label="Meu expediente">
        <header className="dash-checklist__head">
          <div>
            <h2 className="dash-card__title">Meu expediente</h2>
            <p className="dash-card__subtitle">
              Horário oficial do servidor (fuso {clock?.timezone ?? 'não disponível'}). Um
              registro de check-in não é prova de localização — é a declaração de quem registra.
            </p>
          </div>
        </header>

        {isLoading && !selfPresence ? (
          <div className="dash-list-state" role="status">
            <div className="auth-card__spinner" aria-label="Carregando" />
            <p>Carregando meu expediente...</p>
          </div>
        ) : selfPresence ? (
          <>
            <div className="presence-self__status">
              <span
                className={
                  selfPresence.status.key === 'checked_in' || selfPresence.status.key === 'on_break'
                    ? 'service-item__status service-item__status--active'
                    : 'service-item__status service-item__status--inactive'
                }
              >
                {selfPresence.status.label}
              </span>
              <span className="presence-self__times">
                Entrada: {formatStamp(selfPresence.lastCheckIn, clock)} • Saída:{' '}
                {formatStamp(selfPresence.lastCheckOut, clock)}
              </span>
              {selfPresence.status.offScheduleCheckIn && (
                <span className="presence-self__warning">
                  Entrada fora do expediente previsto — ocorrência em conferência.
                </span>
              )}
            </div>

            {actionError && (
              <div className="modal__alert" role="alert">
                {actionError}
              </div>
            )}

            <div className="presence-self__actions">
              <button
                type="button"
                className="button button--primary"
                onClick={() => void handleCheckIn()}
                disabled={isCheckInBusy || !selfCanCheckIn}
              >
                {isCheckInBusy ? 'Registrando...' : 'Registrar entrada'}
              </button>
              <button
                type="button"
                className="button button--secondary"
                onClick={() => void handleCheckOut()}
                disabled={isCheckOutBusy || !selfCanCheckOut}
              >
                {isCheckOutBusy ? 'Registrando...' : 'Registrar saída'}
              </button>
              <button
                type="button"
                className="button button--secondary"
                onClick={() => {
                  setCorrectionError(null)
                  setHistoryMember(selfMember)
                }}
              >
                Meu histórico
              </button>
            </div>
          </>
        ) : null}
      </section>
      )}

      {!loadError && isOwner && (
        <section className="dash-card" aria-label="Escalas e presença da equipe">
          <header className="dash-list-head">
            <p className="dash-list-head__summary">
              {establishmentName ?? 'Estabelecimento'} • {presenceList.length} membro(s) • fuso:{' '}
              {clock?.timezone ?? 'não disponível'}
            </p>
          </header>

          {isLoading ? (
            <div className="dash-list-state" role="status">
              <div className="auth-card__spinner" aria-label="Carregando" />
              <p>Carregando escalas e presença...</p>
            </div>
          ) : presenceList.length === 0 ? (
            <div className="dash-list-state">
              <TeamIcon width={28} height={28} />
              <p>Nenhum membro vinculado ainda.</p>
            </div>
          ) : (
            <ul className="service-list">
              {presenceList.map((item) => {
                const name = memberName(item.member)
                const summary = scheduleSummary(item.schedules)

                return (
                  <li className="service-item" key={item.member.id}>
                    <div className="service-item__main">
                      <div className="service-item__title-row">
                        <h2 className="service-item__name">{name}</h2>
                        <span className="service-item__badge">
                          {TEAM_ROLE_LABELS[item.member.role]}
                        </span>
                        {!item.member.is_active && (
                          <span className="service-item__status service-item__status--inactive">
                            Vínculo inativo
                          </span>
                        )}
                        <span
                          className={`service-item__status ${
                            item.status.key === 'checked_in' || item.status.key === 'on_break'
                              ? 'service-item__status--active'
                              : 'service-item__status--inactive'
                          }`}
                        >
                          {item.status.label}
                        </span>
                      </div>

                      <div className="service-item__meta">
                        <span className="service-item__meta-item">
                          Escala: {summary.text}
                        </span>
                        <span className="service-item__meta-item">
                          Entrada: {formatStamp(item.lastCheckIn, clock)} • Saída:{' '}
                          {formatStamp(item.lastCheckOut, clock)}
                        </span>
                        {item.status.offScheduleCheckIn && (
                          <span className="service-item__meta-item">
                            Entrada fora do expediente previsto
                          </span>
                        )}
                      </div>
                    </div>

                    <div className="service-item__side">
                      <div className="service-item__actions">
                        <button
                          type="button"
                          className="button button--secondary service-item__action"
                          onClick={() => {
                            setScheduleError(null)
                            setSchedulingMember(item.member)
                          }}
                        >
                          {item.schedules.length === 0 ? 'Configurar escala' : 'Editar escala'}
                        </button>
                        <button
                          type="button"
                          className="button button--secondary service-item__action"
                          onClick={() => {
                            setExceptionError(null)
                            setExceptionMember(item.member)
                          }}
                        >
                          Ausência/Exceção
                        </button>
                        <button
                          type="button"
                          className="button button--secondary service-item__action"
                          onClick={() => {
                            setCorrectionError(null)
                            setHistoryMember(item.member)
                          }}
                        >
                          Histórico
                        </button>
                      </div>
                      {item.member.user_id === currentUserId && (
                        <span className="team-self">Você</span>
                      )}
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </section>
      )}

      <WorkScheduleModal
        key={schedulingMember?.id ?? 'schedule-none'}
        isOpen={schedulingMember !== null}
        isBusy={scheduleBusy}
        error={scheduleError}
        member={schedulingMember ? { id: schedulingMember.id, name: memberName(schedulingMember) } : null}
        schedules={
          schedulingMember ? schedulesByMember.get(schedulingMember.id) ?? [] : []
        }
        timezone={clock?.timezone ?? null}
        onClose={() => {
          setSchedulingMember(null)
          setScheduleError(null)
        }}
        onSubmit={(drafts) => void handleSaveSchedule(drafts)}
      />

      <AttendanceExceptionModal
        key={exceptionMember?.id ?? 'exception-none'}
        isOpen={exceptionMember !== null}
        isBusy={exceptionBusy}
        error={exceptionError}
        member={exceptionMember ? { id: exceptionMember.id, name: memberName(exceptionMember) } : null}
        today={clock?.local_date ?? null}
        onClose={() => {
          setExceptionMember(null)
          setExceptionError(null)
        }}
        onSubmit={(input) => void handleExceptionSubmit(input)}
      />

      <AttendanceHistoryModal
        key={historyMember?.id ?? 'history-none'}
        isOpen={historyMember !== null}
        member={historyMember ? { id: historyMember.id, name: memberName(historyMember) } : null}
        records={
          historyMember ? records.filter((record) => record.member_id === historyMember.id) : []
        }
        canCorrect={isOwner}
        clock={clock}
        isCorrecting={correctionBusy}
        correctionError={correctionError}
        onClose={() => {
          setHistoryMember(null)
          setCorrectionError(null)
        }}
        onCorrect={(input) => void handleCorrectionSubmit(input)}
      />
    </>
  )
}
