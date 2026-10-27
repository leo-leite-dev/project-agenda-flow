import { useEffect, useState } from 'react'

import {
  ASSIGNABLE_ROLES,
  PERMISSION_GROUPS,
  TEAM_ROLE_LABELS,
  type TeamMember,
  type TeamRole,
} from '../../lib/team'
import { permissionActionLabel, permissionLabel } from '../../lib/labels'
import { CloseIcon } from '../dashboard/icons'

interface MemberPermissionsModalProps {
  isOpen: boolean
  member: TeamMember | null
  isSaving: boolean
  error: string | null
  onClose: () => void
  onSubmit: (input: { role: TeamRole; permissions: string[] }) => void
}

/**
 * Edição de cargo e permissões granulares de um membro. As opções de cargo
 * excluem 'owner' (a propriedade não é transferida por esta etapa) e a
 * autorização real é sempre conferida pelo PostgreSQL.
 */
export function MemberPermissionsModal({
  isOpen,
  member,
  isSaving,
  error,
  onClose,
  onSubmit,
}: MemberPermissionsModalProps) {
  const [role, setRole] = useState<TeamRole>(() =>
    member && member.role !== 'owner' ? member.role : 'professional',
  )
  const [permissions, setPermissions] = useState<string[]>(() => member?.permissions ?? [])

  useEffect(() => {
    if (!isOpen || !member) return

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !isSaving) onClose()
    }

    document.addEventListener('keydown', handleKeyDown)
    return () => document.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, member, isSaving, onClose])

  if (!isOpen || !member) return null

  const togglePermission = (permission: string) => {
    setPermissions((current) =>
      current.includes(permission)
        ? current.filter((item) => item !== permission)
        : [...current, permission],
    )
  }

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (isSaving) return

    onSubmit({ role, permissions })
  }

  return (
    <div
      className="modal-backdrop"
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && !isSaving) onClose()
      }}
    >
      <div className="modal" role="dialog" aria-modal="true" aria-labelledby="member-permissions-title">
        <div className="modal__header">
          <div>
            <h2 className="modal__title" id="member-permissions-title">
              {member.profile?.full_name ?? 'Membro'}
            </h2>
            <p className="modal__subtitle">Cargo e permissões refinadas do membro.</p>
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
            <label htmlFor="member-role">Cargo do membro</label>
            <select
              id="member-role"
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
            <legend>Permissões adicionais</legend>
            <div className="permission-grid">
              {PERMISSION_GROUPS.map((group) => (
                <div className="permission-grid__group" key={group.key}>
                  <span className="permission-grid__label">{group.label}</span>
                  {group.permissions.map((permission) => (
                    <label className="permission-grid__item" key={permission}>
                      <input
                        type="checkbox"
                        aria-label={permissionLabel(permission)}
                        checked={permissions.includes(permission)}
                        onChange={() => togglePermission(permission)}
                        disabled={isSaving}
                        title={permissionLabel(permission)}
                      />
                      <span>{permissionActionLabel(permission)}</span>
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
              {isSaving ? 'Salvando...' : 'Salvar alterações'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
