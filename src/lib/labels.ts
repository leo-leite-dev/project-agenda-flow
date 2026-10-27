import type { TeamRole } from './team'

/**
 * Rótulos de apresentação (pt-BR) centralizados.
 *
 * Este módulo NÃO participa da autorização: as chaves de permissão e os
 * valores técnicos de cargo continuam sendo os mesmos gravados no banco
 * (migrations 00000–00009). Aqui vive APENAS o que o usuário vê na interface.
 */

/** Cargos exibidos na interface (os valores técnicos permanecem no banco). */
export const ROLE_LABELS: Record<TeamRole, string> = {
  owner: 'Proprietário',
  manager: 'Gerente',
  professional: 'Profissional',
  receptionist: 'Recepcionista',
}

export function roleLabel(role: string): string {
  return ROLE_LABELS[role as TeamRole] ?? role
}

/**
 * Descrições em português de cada permissão do schema (17 chaves previstas
 * pelo CHECK de public.member_permissions). Nenhuma chave é inventada.
 */
export const PERMISSION_LABELS: Record<string, string> = {
  'appointments.read': 'Visualizar agendamentos',
  'appointments.write': 'Criar e editar agendamentos',
  'appointments.delete': 'Excluir agendamentos',
  'clients.read': 'Visualizar clientes',
  'clients.write': 'Cadastrar e editar clientes',
  'clients.delete': 'Excluir clientes',
  'finances.read': 'Visualizar informações financeiras',
  'finances.write': 'Gerenciar informações financeiras',
  'finances.delete': 'Excluir registros financeiros',
  'services.read': 'Visualizar serviços',
  'services.write': 'Gerenciar serviços',
  'services.delete': 'Excluir serviços',
  'staff.read': 'Visualizar equipe',
  'staff.write': 'Gerenciar equipe',
  'staff.delete': 'Remover funcionários',
  'settings.read': 'Visualizar configurações',
  'settings.write': 'Alterar configurações',
}

export function permissionLabel(key: string): string {
  return PERMISSION_LABELS[key] ?? key
}

/**
 * Palavras curtas da grade compacta de permissões (grupo + ação). As caixas
 * usam aria-label com a descrição completa (permissionLabel).
 */
export const PERMISSION_ACTION_LABELS: Record<string, string> = {
  read: 'Visualizar',
  write: 'Editar',
  delete: 'Excluir',
}

export function permissionActionLabel(key: string): string {
  const action = key.split('.')[1] ?? ''
  return PERMISSION_ACTION_LABELS[action] ?? action
}
