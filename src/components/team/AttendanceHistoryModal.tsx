import { useEffect, useState } from 'react'

import { CloseIcon } from '../dashboard/icons'
import { formatTime, type AttendanceRecord } from '../../lib/schedules'
import type { EstablishmentClock } from '../../lib/schedules'

interface AttendanceHistoryModalProps {
  isOpen: boolean
  member: { id: string; name: string } | null
  records: AttendanceRecord[]
  canCorrect: boolean
  clock: EstablishmentClock | null
  isCorrecting: boolean
  correctionError: string | null
  onClose: () => void
  onCorrect: (input: {
    attendanceId: string
    checkInAt?: string
    checkOutAt?: string
    reason: string
  }) => void
}

/** ISO UTC → 'YYYY-MM-DDTHH:mm' no fuso do estabelecimento (p/ datetime-local). */
function toLocalInput(iso: string | null, timezone: string | null): string {
  if (!iso || !timezone) return ''
  const formatted = new Intl.DateTimeFormat('sv-SE', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso))
  return formatted.replace(' ', 'T')
}

/** 'YYYY-MM-DDTHH:mm' (fuso do tenant) → ISO UTC, sempre que corrigível. */
function localInputToIso(value: string, timezone: string): string | undefined {
  if (!value) return undefined
  const [datePart, timePart = '00:00'] = value.split('T')
  const [year, month, day] = datePart.split('-').map(Number)
  const [hour = 0, minute = 0] = timePart.split(':').map(Number)
  const assumedUtc = Date.UTC(year, month - 1, day, hour, minute)
  const atTz = new Intl.DateTimeFormat('sv-SE', {
    timeZone: timezone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(new Date(assumedUtc))
  const observed = Date.parse(`${atTz.replace(' ', 'T')}Z`)
  const offsetMs = observed - assumedUtc
  return new Date(assumedUtc - offsetMs).toISOString()
}

function formatFull(iso: string | null, timezone: string | null): string {
  if (!iso || !timezone) return '—'
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: timezone,
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(iso))
}

/**
 * Histórico de presença do membro. Somente o proprietário corrige registros —
 * com justificativa obrigatória e trilha de auditoria no banco
 * (correct_attendance_record corrige no servidor e registra
 * attendance_corrections). Funcionário comum acompanha a própria lista
 * sem botões administrativos.
 */
export function AttendanceHistoryModal({
  isOpen,
  member,
  records,
  canCorrect,
  clock,
  isCorrecting,
  correctionError,
  onClose,
  onCorrect,
}: AttendanceHistoryModalProps) {
  const [correctingId, setCorrectingId] = useState<string | null>(null)
  const [checkInAt, setCheckInAt] = useState('')
  const [checkOutAt, setCheckOutAt] = useState('')
  const [reason, setReason] = useState('')

  useEffect(() => {
    if (!isOpen) return
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !isCorrecting) onClose()
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, isCorrecting, onClose])

  if (!isOpen || !member) return null

  const startCorrection = (record: AttendanceRecord) => {
    setCorrectingId(record.id)
    setCheckInAt(toLocalInput(record.check_in_at, clock?.timezone ?? null))
    setCheckOutAt(toLocalInput(record.check_out_at, clock?.timezone ?? null))
    setReason('')
  }

  const handleSubmitCorrection = () => {
    if (isCorrecting || !correctingId) return
    if (!reason.trim()) return
    onCorrect({
      attendanceId: correctingId,
      checkInAt: checkInAt ? localInputToIso(checkInAt, clock?.timezone ?? 'UTC') ?? undefined : undefined,
      checkOutAt: checkOutAt ? localInputToIso(checkOutAt, clock?.timezone ?? 'UTC') ?? undefined : undefined,
      reason: reason.trim(),
    })
  }

  return (
    <div
      className="modal-backdrop"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !isCorrecting) onClose()
      }}
    >
      <div
        className="modal modal--history"
        role="dialog"
        aria-modal="true"
        aria-labelledby="history-modal-title"
      >
        <div className="modal__header">
          <div>
            <h2 className="modal__title" id="history-modal-title">
              Histórico de {member.name}
            </h2>
            <p className="modal__subtitle">
              Registros reais do Supabase (horário oficial do servidor, fuso{' '}
              {clock?.timezone ?? 'não disponível'}).
            </p>
          </div>
          <button
            type="button"
            className="dash-icon-button modal__close"
            onClick={onClose}
            aria-label="Fechar histórico de presença"
            disabled={isCorrecting}
          >
            <CloseIcon />
          </button>
        </div>

        {correctionError && (
          <div className="modal__alert" role="alert">
            {correctionError}
          </div>
        )}

        {records.length === 0 ? (
          <div className="dash-list-state">
            <p>Nenhum registro de presença ainda.</p>
          </div>
        ) : (
          <ul className="attendance-history">
            {records.map((record) => {
              const isCorrectingThis = canCorrect && record.id === correctingId

              return (
                <li className="attendance-history__item" key={record.id}>
                  <div className="attendance-history__main">
                    <span className="attendance-history__date">{formatFull(record.check_in_at ?? null, clock?.timezone ?? null).slice(0, 5)}</span>
                    <span className="attendance-history__detail">
                      Entrada {formatFull(record.check_in_at, clock?.timezone ?? null)} • Saída{' '}
                      {formatFull(record.check_out_at, clock?.timezone ?? null)}
                      {record.correction_reason && (
                        <> • corrigido: {record.correction_reason}</>
                      )}
                    </span>
                  </div>
                  <span className={`attendance-history__state${record.check_out_at ? ' is-done' : ''}`}>
                    {record.check_out_at ? 'Completo' : record.check_in_at ? 'Em aberto' : 'Sem entrada'}
                  </span>
                  {canCorrect && !isCorrectingThis && (
                    <button
                      type="button"
                      className="button button--secondary"
                      onClick={() => startCorrection(record)}
                      disabled={isCorrecting}
                    >
                      Corrigir
                    </button>
                  )}
                  {isCorrectingThis && (
                    <div className="attendance-correction">
                      <label>
                        Nova entrada
                        <input
                          type="datetime-local"
                          value={checkInAt}
                          disabled={isCorrecting}
                          onChange={(event) => setCheckInAt(event.target.value)}
                          aria-label="Nova entrada"
                        />
                      </label>
                      <label>
                        Nova saída
                        <input
                          type="datetime-local"
                          value={checkOutAt}
                          disabled={isCorrecting}
                          onChange={(event) => setCheckOutAt(event.target.value)}
                          aria-label="Nova saída"
                        />
                      </label>
                      <label>
                        Justificativa (obrigatória)
                        <textarea
                          rows={2}
                          value={reason}
                          disabled={isCorrecting}
                          onChange={(event) => setReason(event.target.value)}
                          aria-label="Justificativa da correção"
                        />
                      </label>
                      <div className="attendance-correction__actions">
                        <button
                          type="button"
                          className="button button--secondary"
                          onClick={() => setCorrectingId(null)}
                          disabled={isCorrecting}
                        >
                          Cancelar
                        </button>
                        <button
                          type="button"
                          className="button button--primary"
                          onClick={handleSubmitCorrection}
                          disabled={isCorrecting || !reason.trim()}
                        >
                          {isCorrecting ? 'Corrigindo...' : 'Aplicar correção'}
                        </button>
                      </div>
                    </div>
                  )}
                </li>
              )
            })}
          </ul>
        )}

        <div className="modal__actions">
          <p className="modal__hint">
            Horários em HH:MM; turnos completos exibem saída {formatTime('00:00')} quando o turno
            cruza a meia-noite.
          </p>
          <button type="button" className="button button--secondary" onClick={onClose} disabled={isCorrecting}>
            Fechar
          </button>
        </div>
      </div>
    </div>
  )
}
