import { useEffect, useRef, useState } from 'react'

import {
  ASSIGNABLE_ROLES,
  PERMISSION_GROUPS,
  TEAM_ROLE_LABELS,
  buildMailtoLink,
  buildWhatsAppLink,
  type TeamRole,
} from '../../lib/team'
import { CloseIcon } from '../dashboard/icons'

interface InviteMemberModalProps {
  isOpen: boolean
  isSaving: boolean
  error: string | null
  /** Token bruto devolvido pela RPC (exibido uma única vez). */
  generatedLink: string | null
  onClose: () => void
  onSubmit: (input: { email: string; role: TeamRole; permissions: string[] }) => void
  onResetGeneratedLink: () => void
}

/**
 * Convite de funcionário. O sistema NÃO envia e-mails: o link é exibido ao
 * proprietário, que decide como compartilhar (e-mail ou WhatsApp). O token
 * existe apenas no navegador do dono — no banco fica somente o hash.
 */
export function InviteMemberModal({
  isOpen,
  isSaving,
  error,
  generatedLink,
  onClose,
  onSubmit,
  onResetGeneratedLink,
}: InviteMemberModalProps) {
  const [email, setEmail] = useState('')
  const [role, setRole] = useState<TeamRole>('professional')
  const [permissions, setPermissions] = useState<string[]>([])
  const [copied, setCopied] = useState(false)
  const emailRef = useRef<HTMLInputElement | null>(null)

  useEffect(() => {
    if (!isOpen) return

    emailRef.current?.focus()

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

    const normalizedEmail = email.trim().toLowerCase()

    if (!normalizedEmail || !normalizedEmail.includes('@')) {
      return
    }

    onSubmit({ email: normalizedEmail, role, permissions })
  }

  const togglePermission = (permission: string) => {
    setPermissions((current) =>
      current.includes(permission)
        ? current.filter((item) => item !== permission)
        : [...current, permission],
    )
  }

  const handleCopy = async () => {
    if (!generatedLink) return

    try {
      await navigator.clipboard.writeText(generatedLink)
      setCopied(true)
    } catch {
      setCopied(false)
    }
  }

  const shareMessage = generatedLink
    ? `Olá! Você foi convidado(a) para a equipe no Agenda Flow. Acesse o link para aceitar o convite: ${generatedLink}`
    : ''

  return (
    <div
      className="modal-backdrop"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !isSaving) onClose()
      }}
    >
      <div className="modal" role="dialog" aria-modal="true" aria-labelledby="invite-title">
        <div className="modal__header">
          <div>
            <h2 className="modal__title" id="invite-title">
              Convidar funcionário
            </h2>
            <p className="modal__subtitle">
              O convite é vinculado ao e-mail do funcionário e vale por 7 dias.
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

        {generatedLink ? (
          <div className="invite-share">
            <p className="invite-share__title">Convite criado</p>
            <p className="invite-share__hint">
              O Agenda Flow não envia e-mails por conta própria. Compartilhe o link abaixo com o
              funcionário por e-mail ou WhatsApp — o convite só funciona para o e-mail informado.
            </p>

            <input
              className="invite-share__link"
              type="text"
              readOnly
              value={generatedLink}
              aria-label="Link do convite"
              onFocus={(event) => event.currentTarget.select()}
            />

            <div className="invite-share__actions">
              <button type="button" className="button button--primary" onClick={() => void handleCopy()}>
                {copied ? 'Link copiado' : 'Copiar link'}
              </button>
              <a
                className="button button--secondary"
                href={buildMailtoLink(
                  email.trim().toLowerCase(),
                  'Convite para a equipe no Agenda Flow',
                  shareMessage,
                )}
              >
                Abrir e-mail
              </a>
              <a
                className="button button--secondary"
                href={buildWhatsAppLink(null, shareMessage)}
                target="_blank"
                rel="noreferrer"
              >
                Abrir WhatsApp
              </a>
            </div>

            <button
              type="button"
              className="button button--secondary invite-share__new"
              onClick={onResetGeneratedLink}
            >
              Convidar outro funcionário
            </button>
          </div>
        ) : (
          <form className="modal__form" onSubmit={handleSubmit} noValidate>
            <div className="modal__field">
              <label htmlFor="invite-email">
                E-mail do funcionário <span aria-hidden="true">*</span>
              </label>
              <input
                id="invite-email"
                ref={emailRef}
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                placeholder="funcionario@exemplo.com"
                required
                autoComplete="off"
                disabled={isSaving}
              />
              <p className="modal__hint">
                O funcionário precisa ter conta com este e-mail confirmado para aceitar o convite.
              </p>
            </div>

            <div className="modal__field">
              <label htmlFor="invite-role">Cargo</label>
              <select
                id="invite-role"
                value={role}
                onChange={(event) => setRole(event.target.value as TeamRole)}
                disabled={isSaving}
              >
                {ASSIGNABLE_ROLES.map((option) => (
                  <option key={option} value={option}>
                    {TEAM_ROLE_LABELS[option]}
                  </option>
                ))}
              </select>
            </div>

            <fieldset className="modal__fieldset">
              <legend>Permissões adicionais (opcional)</legend>
              <p className="modal__hint">
                Permissões refinadas por módulo. O cargo já define o acesso básico.
              </p>
              <div className="permission-grid">
                {PERMISSION_GROUPS.map((group) => (
                  <div className="permission-grid__group" key={group.key}>
                    <span className="permission-grid__label">{group.label}</span>
                    {group.permissions.map((permission) => (
                      <label className="permission-grid__item" key={permission}>
                        <input
                          type="checkbox"
                          aria-label={permission}
                          checked={permissions.includes(permission)}
                          onChange={() => togglePermission(permission)}
                          disabled={isSaving}
                        />
                        <span>{permission.split('.')[1]}</span>
                      </label>
                    ))}
                  </div>
                ))}
              </div>
            </fieldset>

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
                {isSaving ? 'Criando...' : 'Gerar convite'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  )
}
