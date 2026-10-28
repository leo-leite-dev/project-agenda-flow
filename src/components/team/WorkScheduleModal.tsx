import { useEffect, useState } from 'react'

import { CloseIcon } from '../dashboard/icons'
import { WEEKDAY_LABELS, type ScheduleDraft, type WorkSchedule } from '../../lib/schedules'

interface WorkScheduleModalProps {
  isOpen: boolean
  isBusy: boolean
  error: string | null
  member: { id: string; name: string } | null
  schedules: WorkSchedule[]
  timezone: string | null
  onClose: () => void
  onSubmit: (drafts: ScheduleDraft[]) => void
}

type ScheduleRowState = ScheduleDraft

const emptyRows = (): ScheduleRowState[] =>
  WEEKDAY_LABELS.map((_, weekday) => ({
    weekday,
    is_day_off: true,
    start_time: null,
    end_time: null,
    break_start: null,
    break_end: null,
  }))

function fromExisting(schedules: WorkSchedule[]): ScheduleRowState[] {
  const rows = emptyRows()
  for (const schedule of schedules) {
    if (schedule.weekday >= 0 && schedule.weekday <= 6) {
      rows[schedule.weekday] = {
        weekday: schedule.weekday,
        is_day_off: schedule.is_day_off,
        start_time: schedule.start_time,
        end_time: schedule.end_time,
        break_start: schedule.break_start,
        break_end: schedule.break_end,
      }
    }
  }
  return rows
}

/** Editor da escala semanal (um membro). Turnos noturnos permitidos (22→02). */
export function WorkScheduleModal({
  isOpen,
  isBusy,
  error,
  member,
  schedules,
  timezone,
  onClose,
  onSubmit,
}: WorkScheduleModalProps) {
  const [rows, setRows] = useState<ScheduleRowState[]>(() => fromExisting(schedules))

  useEffect(() => {
    if (!isOpen) return
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !isBusy) onClose()
    }
    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, isBusy, onClose])

  if (!isOpen || !member) return null

  const updateRow = (weekday: number, patch: Partial<ScheduleRowState>) => {
    setRows((current) =>
      current.map((row, index) => (index === weekday ? { ...row, ...patch } : row)),
    )
  }

  const handleSubmit = () => {
    if (isBusy) return
    onSubmit(rows)
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
        className="modal modal--schedule"
        role="dialog"
        aria-modal="true"
        aria-labelledby="schedule-modal-title"
      >
        <div className="modal__header">
          <div>
            <h2 className="modal__title" id="schedule-modal-title">
              Escala de {member.name}
            </h2>
            <p className="modal__subtitle">
              Expediente previsto. Fuso do estabelecimento:{' '}
              {timezone ?? 'não disponível'}. Turnos que cruzam a meia-noite são permitidos
              (ex.: 22:00 às 02:00).
            </p>
          </div>
          <button
            type="button"
            className="dash-icon-button modal__close"
            onClick={onClose}
            aria-label="Fechar configuração da escala"
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

        <div className="schedule-modal__rows">
          {rows.map((row, weekday) => {
            const working = !row.is_day_off

            return (
              <div className="schedule-modal__row" key={row.weekday}>
                <label className="schedule-modal__day">
                  <input
                    type="checkbox"
                    checked={working}
                    disabled={isBusy}
                    onChange={(event) =>
                      updateRow(row.weekday, event.target.checked
                        ? { is_day_off: false, start_time: row.start_time ?? '09:00', end_time: row.end_time ?? '18:00' }
                        : { is_day_off: true, start_time: null, end_time: null, break_start: null, break_end: null })
                    }
                    aria-label={`${working ? 'Desmarcar' : 'Marcar'} folga em ${WEEKDAY_LABELS[weekday]}`}
                  />
                  {WEEKDAY_LABELS[weekday]}
                </label>

                {working && (
                  <>
                    <label className="schedule-modal__field">
                      <span className="visually-hidden">{`Início em ${WEEKDAY_LABELS[weekday]}`}</span>
                      <input
                        type="time"
                        value={row.start_time ?? ''}
                        disabled={isBusy}
                        onChange={(event) => updateRow(row.weekday, { start_time: event.target.value || null })}
                        aria-label={`Início em ${WEEKDAY_LABELS[weekday]}`}
                      />
                    </label>
                    <label className="schedule-modal__field">
                      <input
                        type="time"
                        value={row.end_time ?? ''}
                        disabled={isBusy}
                        onChange={(event) => updateRow(row.weekday, { end_time: event.target.value || null })}
                        aria-label={`Término em ${WEEKDAY_LABELS[weekday]}`}
                      />
                    </label>
                    <label className="schedule-modal__field">
                      <input
                        type="time"
                        value={row.break_start ?? ''}
                        disabled={isBusy}
                        onChange={(event) => updateRow(row.weekday, { break_start: event.target.value || null })}
                        aria-label={`Início do intervalo em ${WEEKDAY_LABELS[weekday]}`}
                      />
                    </label>
                    <label className="schedule-modal__field">
                      <input
                        type="time"
                        value={row.break_end ?? ''}
                        disabled={isBusy}
                        onChange={(event) => updateRow(row.weekday, { break_end: event.target.value || null })}
                        aria-label={`Fim do intervalo em ${WEEKDAY_LABELS[weekday]}`}
                      />
                    </label>
                  </>
                )}
              </div>
            )
          })}
        </div>

        <div className="modal__actions">
          <p className="modal__hint">
            Escala prevista não registra presença: o check-in é individual e usa o horário do
            servidor.
          </p>
          <button type="button" className="button button--secondary" onClick={onClose} disabled={isBusy}>
            Cancelar
          </button>
          <button
            type="button"
            className="button button--primary"
            onClick={handleSubmit}
            disabled={isBusy}
          >
            {isBusy ? 'Salvando...' : 'Salvar escala'}
          </button>
        </div>
      </div>
    </div>
  )
}
