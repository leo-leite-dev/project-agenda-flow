import { describe, expect, it } from 'vitest'

import {
  PERMISSION_ACTION_LABELS,
  PERMISSION_LABELS,
  ROLE_LABELS,
  permissionActionLabel,
  permissionLabel,
  roleLabel,
} from '../labels'

const EXPECTED_PERMISSION_KEYS = [
  'appointments.read',
  'appointments.write',
  'appointments.delete',
  'clients.read',
  'clients.write',
  'clients.delete',
  'finances.read',
  'finances.write',
  'finances.delete',
  'services.read',
  'services.write',
  'services.delete',
  'staff.read',
  'staff.write',
  'staff.delete',
  'settings.read',
  'settings.write',
]

describe('tradução de cargos (labels de apresentação)', () => {
  it('traduz os quatro cargos do schema para português', () => {
    expect(roleLabel('owner')).toBe('Proprietário')
    expect(roleLabel('manager')).toBe('Gerente')
    expect(roleLabel('professional')).toBe('Profissional')
    expect(roleLabel('receptionist')).toBe('Recepcionista')
    expect(Object.keys(ROLE_LABELS)).toHaveLength(4)
  })

  it('preserva o valor técnico em cargo desconhecido', () => {
    expect(roleLabel('cargo-inexistente')).toBe('cargo-inexistente')
  })
})

describe('tradução de permissões (labels de apresentação)', () => {
  it('cobre EXATAMENTE as 17 chaves previstas pelo CHECK do banco', () => {
    expect(Object.keys(PERMISSION_LABELS).sort()).toEqual([...EXPECTED_PERMISSION_KEYS].sort())
  })

  it('descreve cada operação efetivamente autorizada', () => {
    expect(permissionLabel('appointments.read')).toBe('Visualizar agendamentos')
    expect(permissionLabel('appointments.write')).toBe('Criar e editar agendamentos')
    expect(permissionLabel('appointments.delete')).toBe('Excluir agendamentos')
    expect(permissionLabel('clients.write')).toBe('Cadastrar e editar clientes')
    expect(permissionLabel('finances.read')).toBe('Visualizar informações financeiras')
    expect(permissionLabel('finances.write')).toBe('Gerenciar informações financeiras')
    expect(permissionLabel('finances.delete')).toBe('Excluir registros financeiros')
    expect(permissionLabel('services.write')).toBe('Gerenciar serviços')
    expect(permissionLabel('staff.read')).toBe('Visualizar equipe')
    expect(permissionLabel('staff.write')).toBe('Gerenciar equipe')
    expect(permissionLabel('staff.delete')).toBe('Remover funcionários')
    expect(permissionLabel('settings.read')).toBe('Visualizar configurações')
    expect(permissionLabel('settings.write')).toBe('Alterar configurações')
  })

  it('devolve a chave técnica para chaves desconhecidas (sem inventar rótulos)', () => {
    expect(permissionLabel('permissions.inventadas')).toBe('permissions.inventadas')
  })

  it('traduz as ações curtas da grade compacta (read/write/delete)', () => {
    expect(Object.keys(PERMISSION_ACTION_LABELS).sort()).toEqual(['delete', 'read', 'write'])
    expect(permissionActionLabel('staff.write')).toBe('Editar')
    expect(permissionActionLabel('staff.delete')).toBe('Excluir')
    expect(permissionActionLabel('staff.read')).toBe('Visualizar')
  })
})
