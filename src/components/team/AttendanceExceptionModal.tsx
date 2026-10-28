import { useEffect, useState } from 'react'

import { CloseIcon } from '../dashboard/icons'
import {
  ATTENDANCE_EXCEPTION_LABELS,
  type AttendanceExceptionType,
} from '../../lib/schedules'

interface AttendanceExceptionModalProps {
  isOpen: boolean
  isBusy: boolean
  error: string | null
  member: { id: string; name: string } | null
  today: string | null
  onClose: () => void
  onSubmit: (input: {
    exceptionType: AttendanceExceptionType
    startDate: string
    endDate: string
    reason: string | null
  }) => void
}

/**
 * Registro de ocorrências pelo proprietário (RPC record_attendance_exception):
 * falta, atraso justificado, saída antecipada, folga, férias ou ajuste. A
 * exceção NÃO substitui a escala habitual — é um registro adicional auditável.
 */
export function AttendanceExceptionModal({
  isOpen,
  isBusy,
  error,
  member,
  today,
  onClose,
  onSubmit,
}: AttendanceExceptionModalProps) {
  const [exceptionType, setExceptionType] = useState<AttendanceExceptionType>('absence')
  const [startDate, setStartDate] = useState(today ?? '')
  const [endDate, setEndDate] = useState(today ?? '')
  const [reason, setReason] = useState('')

  useEffect(() => {
    if (!isOpen) return
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !isBusy) onClose()
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, isBusy, onClose])

  if (!isOpen || !member) return null

  const handleSubmit = () => {
    if (isBusy || !startDate || !endDate) return
    onSubmit({ exceptionType, startDate, endDate, reason: reason.trim() ? reason.trim() : null })
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
        className="modal modal--exception"
        role="dialog"
        aria-modal="true"
        aria-labelledby="exception-modal-title"
      >
        <div className="modal__header">
          <div>
            <h2 className="modal__title" id="exception-modal-title">
              Exceção para {member.name}
            </h2>
            <p className="modal__subtitle">
              Ocorrência registrada pelo proprietário; a escala habitual não é alterada.
            </p>
          </div>
          <button
            type="button"
            className="dash-icon-button modal__close"
            onClick={onClose}
            aria-label="Fechar registro de exceção"
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

        <div className="modal__form">
          <label className="modal__field">
            <span>Ocorrência</span>
            <select
              value={exceptionType}
              disabled={isBusy}
              onChange={(event) => setExceptionType(event.target.value as AttendanceExceptionType)}
              aria-label="Tipo de ocorrência"
            >
              {Object.entries(ATTENDANCE_EXCEPTION_LABELS).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>

          <label className="modal__field">
            <span>Início</span>
            <input
              type="date"
              value={startDate}
              disabled={isBusy}
              onChange={(event) => setStartDate(event.target.value)}
              aria-label="Data de início da ocorrência"
            />
          </label>

          <label className="modal__field">
            <span>Fim</span>
            <input
              type="date"
              value={endDate}
              disabled={isBusy}
              onChange={(event) => setEndDate(event.target.value)}
              aria-label="Data de fim da ocorrência"
            />
          </label>

          <label className="modal__field">
            <span>Motivo (opcional)</span>
            <textarea
              value={reason}
              disabled={isBusy}
              rows={3}
              onChange={(event) => setReason(event.target.value)}
              aria-label="Motivo da ocorrência"
              placeholder="Ex.: faltou sem aviso."
            />
          </label>
        </div>

        <div className="modal__actions">
          <button type="button" className="button button--secondary" onClick={onClose} disabled={isBusy}>
            Cancelar
          </button>
          <button
            type="button"
            className="button button--primary"
            onClick={handleSubmit}
            disabled={isBusy || !startDate || !endDate}
          >
            {isBusy ? 'Registrando...' : 'Registrar ocorrência'}
          </button>
        </div>
      </div>
    </div>
  )
}
