import { describe, expect, it } from 'vitest'

import {
  ALL_PERMISSION_KEYS,
  ASSIGNABLE_ROLES,
  INVITATION_STATUS_LABELS,
  PERMISSION_GROUPS,
  TEAM_ROLE_LABELS,
  buildMailtoLink,
  buildWhatsAppLink,
  invitationStatus,
  isSafeInternalPath,
  permissionLabel,
  teamRoleLabel,
  type TeamInvitation,
} from '../team'

function invitationFixture(overrides: Partial<TeamInvitation> = {}): TeamInvitation {
  return {
    id: 'inv-1',
    email: 'funcionario@exemplo.com',
    phone: null,
    role: 'professional',
    permissions: [],
    created_at: '2026-10-20T10:00:00Z',
    expires_at: '2099-10-27T10:00:00Z',
    accepted_at: null,
    cancelled_at: null,
    ...overrides,
  }
}

describe('cargos da equipe', () => {
  it('exibe nomes amigáveis em português', () => {
    expect(teamRoleLabel('owner')).toBe('Proprietário')
    expect(teamRoleLabel('manager')).toBe('Gerente')
    expect(teamRoleLabel('professional')).toBe('Profissional')
    expect(teamRoleLabel('receptionist')).toBe('Recepcionista')
    expect(Object.keys(TEAM_ROLE_LABELS)).toHaveLength(4)
  })

  it('não permite atribuir o cargo de proprietário (sem transferência de propriedade)', () => {
    expect(ASSIGNABLE_ROLES).not.toContain('owner')
    expect(ASSIGNABLE_ROLES).toEqual(['manager', 'professional', 'receptionist'])
  })
})

describe('permissões granulares', () => {
  it('usa apenas as chaves previstas no schema', () => {
    expect(ALL_PERMISSION_KEYS).toContain('appointments.read')
    expect(ALL_PERMISSION_KEYS).toContain('settings.write')
    expect(ALL_PERMISSION_KEYS).not.toContain('owner.transfer')
    expect(ALL_PERMISSION_KEYS.every((key) => /^[a-z]+\.(read|write|delete)$/.test(key))).toBe(true)
  })

  it('agrupa as permissões por módulo', () => {
    expect(PERMISSION_GROUPS.map((group) => group.key)).toEqual([
      'appointments',
      'clients',
      'finances',
      'services',
      'staff',
      'settings',
    ])
    expect(permissionLabel('clients.read')).toBe('Clientes — Visualizar')
  })
})

describe('situação dos convites', () => {
  it('deriva a situação real do convite', () => {
    expect(invitationStatus(invitationFixture())).toBe('pendente')
    expect(invitationStatus(invitationFixture({ accepted_at: '2026-10-21T10:00:00Z' }))).toBe('aceito')
    expect(invitationStatus(invitationFixture({ cancelled_at: '2026-10-21T10:00:00Z' }))).toBe('cancelado')
    expect(invitationStatus(invitationFixture({ expires_at: '2020-01-01T00:00:00Z' }))).toBe('expirado')
    expect(INVITATION_STATUS_LABELS.pendente).toBe('Pendente')
  })
})

describe('compartilhamento do convite', () => {
  it('monta o e-mail com link pré-preenchido', () => {
    const link = buildMailtoLink(
      'funcionario@exemplo.com',
      'Convite',
      'Acesse: https://app.test/convite/abc',
    )

    expect(link.startsWith('mailto:funcionario@exemplo.com?')).toBe(true)
    expect(link).toContain('subject=Convite')
    expect(decodeURIComponent(link)).toContain('https://app.test/convite/abc')
  })

  it('monta o link do WhatsApp com a mensagem', () => {
    const link = buildWhatsAppLink('+55 (11) 99999-9999', 'Olá! Convite: https://app.test/convite/abc')

    expect(link.startsWith('https://wa.me/5511999999999?text=')).toBe(true)
    expect(decodeURIComponent(link)).toContain('Convite')
  })
})

describe('isSafeInternalPath', () => {
  it('aceita apenas caminhos internos', () => {
    expect(isSafeInternalPath('/convite/abc')).toBe(true)
    expect(isSafeInternalPath('/dashboard')).toBe(true)
  })

  it('recusa caminhos externos ou malformados', () => {
    expect(isSafeInternalPath('//evil.example.com')).toBe(false)
    expect(isSafeInternalPath('https://evil.example.com')).toBe(false)
    expect(isSafeInternalPath('/\\evil')).toBe(false)
    expect(isSafeInternalPath(null)).toBe(false)
    expect(isSafeInternalPath('')).toBe(false)
  })
})
