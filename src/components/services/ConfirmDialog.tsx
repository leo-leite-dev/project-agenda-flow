import { useEffect, useRef } from 'react'

import { CloseIcon } from '../dashboard/icons'

interface ConfirmDialogProps {
  isOpen: boolean
  title: string
  message: string
  confirmLabel: string
  cancelLabel?: string
  danger?: boolean
  onConfirm: () => void
  onCancel: () => void
  isBusy?: boolean
}

/**
 * Confirmação simples e acessível (Escape, clique no backdrop e foco no
 * botão principal). Usada, por exemplo, para desativar um serviço.
 */
export function ConfirmDialog({
  isOpen,
  title,
  message,
  confirmLabel,
  cancelLabel = 'Cancelar',
  danger = false,
  onConfirm,
  onCancel,
  isBusy = false,
}: ConfirmDialogProps) {
  const confirmRef = useRef<HTMLButtonElement | null>(null)

  useEffect(() => {
    if (!isOpen) return

    confirmRef.current?.focus()

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onCancel()
    }

    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, onCancel])

  if (!isOpen) return null

  return (
    <div
      className="modal-backdrop"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onCancel()
      }}
    >
      <div className="modal confirm-dialog" role="alertdialog" aria-modal="true" aria-labelledby="confirm-title">
        <div className="modal__header">
          <h2 className="modal__title" id="confirm-title">
            {title}
          </h2>
          <button
            type="button"
            className="dash-icon-button modal__close"
            onClick={onCancel}
            aria-label="Fechar"
            disabled={isBusy}
          >
            <CloseIcon />
          </button>
        </div>

        <p className="confirm-dialog__message">{message}</p>

        <div className="modal__actions">
          <button
            type="button"
            className="button button--secondary"
            onClick={onCancel}
            disabled={isBusy}
          >
            {cancelLabel}
          </button>
          <button
            type="button"
            ref={confirmRef}
            className={`button ${danger ? 'button--danger' : 'button--primary'}`}
            onClick={onConfirm}
            disabled={isBusy}
          >
            {isBusy ? 'Processando...' : confirmLabel}
          </button>
        </div>
      </div>
    </div>
  )
}
