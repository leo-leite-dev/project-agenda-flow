import { supabase } from './supabase'
import { ROLE_LABELS, permissionLabel as presentationPermissionLabel } from './labels'

export type TeamRole = 'owner' | 'manager' | 'professional' | 'receptionist'

/** Cargos que podem ser atribuídos por esta etapa (sem transferência de propriedade). */
export const ASSIGNABLE_ROLES: TeamRole[] = ['manager', 'professional', 'receptionist']

/** Rótulos de apresentação centralizados em src/lib/labels.ts. */
export const TEAM_ROLE_LABELS = ROLE_LABELS

export function teamRoleLabel(role: string): string {
  return TEAM_ROLE_LABELS[role as TeamRole] ?? role
}

/**
 * Permissões granulares já previstas no schema (member_permissions).
 * Nenhuma permissão nova é inventada aqui — as chaves são exatamente as
 * aceitas pelo CHECK da tabela.
 */
export const PERMISSION_GROUPS: ReadonlyArray<{ key: string; label: string; permissions: string[] }> = [
  {
    key: 'appointments',
    label: 'Agenda',
    permissions: ['appointments.read', 'appointments.write', 'appointments.delete'],
  },
  {
    key: 'clients',
    label: 'Clientes',
    permissions: ['clients.read', 'clients.write', 'clients.delete'],
  },
  {
    key: 'finances',
    label: 'Financeiro',
    permissions: ['finances.read', 'finances.write', 'finances.delete'],
  },
  {
    key: 'services',
    label: 'Serviços',
    permissions: ['services.read', 'services.write', 'services.delete'],
  },
  {
    key: 'staff',
    label: 'Equipe',
    permissions: ['staff.read', 'staff.write', 'staff.delete'],
  },
  {
    key: 'settings',
    label: 'Configurações',
    permissions: ['settings.read', 'settings.write'],
  },
]

export const ALL_PERMISSION_KEYS: string[] = PERMISSION_GROUPS.flatMap((group) => group.permissions)

/** Descrição completa da permissão em português (rótulo centralizado). */
export function permissionLabel(key: string): string {
  return presentationPermissionLabel(key)
}

export interface TeamMemberProfile {
  id: string
  full_name: string
  avatar_url: string | null
  phone: string | null
}

export interface TeamMember {
  id: string
  user_id: string
  role: TeamRole
  is_active: boolean
  created_at: string
  profile: TeamMemberProfile | null
  permissions: string[]
}

export interface TeamInvitation {
  id: string
  email: string | null
  phone: string | null
  role: TeamRole
  permissions: string[]
  created_at: string
  expires_at: string
  accepted_at: string | null
  cancelled_at: string | null
}

export type InvitationStatus = 'pendente' | 'aceito' | 'cancelado' | 'expirado'

export function invitationStatus(invitation: TeamInvitation): InvitationStatus {
  if (invitation.accepted_at) return 'aceito'
  if (invitation.cancelled_at) return 'cancelado'
  if (new Date(invitation.expires_at).getTime() <= Date.now()) return 'expirado'
  return 'pendente'
}

export const INVITATION_STATUS_LABELS: Record<InvitationStatus, string> = {
  pendente: 'Pendente',
  aceito: 'Aceito',
  cancelado: 'Cancelado',
  expirado: 'Expirado',
}

/** Link de aceitação do convite (o token viaja apenas na URL, nunca em logs). */
export function buildInvitationLink(token: string): string {
  const origin = typeof window === 'undefined' ? '' : window.location.origin
  return `${origin}/convite/${token}`
}

export function buildMailtoLink(email: string, subject: string, body: string): string {
  return `mailto:${email}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`
}

export function buildWhatsAppLink(phone: string | null, message: string): string {
  const digits = (phone ?? '').replace(/\D/g, '')
  const base = digits ? `https://wa.me/${digits}?text=` : 'https://wa.me/?text='

  return `${base}${encodeURIComponent(message)}`
}

/**
 * Valida um caminho interno de redirecionamento (uso restrito: evita
 * open redirect após login).
 */
export function isSafeInternalPath(path: string | null | undefined): boolean {
  if (!path) return false
  return path.startsWith('/') && !path.startsWith('//') && !path.includes('\\')
}

interface TeamMemberRow {
  id: string
  user_id: string
  role: TeamRole
  is_active: boolean
  created_at: string
  profiles: TeamMemberProfile | null
  member_permissions: Array<{ permission_key: string }> | null
}

/**
 * Lista os membros do estabelecimento ativo. O filtro por estabelecimento é
 * defesa em profundidade: a RLS limita o resultado ao tenant do usuário.
 */
export async function listTeamMembers(establishmentId: string): Promise<TeamMember[]> {
  const { data, error } = await supabase
    .from('establishment_members')
    .select(
      'id, user_id, role, is_active, created_at, profiles:user_id(id, full_name, avatar_url, phone), member_permissions(permission_key)',
    )
    .eq('establishment_id', establishmentId)
    .order('created_at', { ascending: true })

  if (error) {
    throw error
  }

  return ((data ?? []) as unknown as TeamMemberRow[]).map((row) => ({
    id: row.id,
    user_id: row.user_id,
    role: row.role,
    is_active: row.is_active,
    created_at: row.created_at,
    profile: row.profiles ?? null,
    permissions: (row.member_permissions ?? []).map((permission) => permission.permission_key),
  }))
}

/** Lista os convites do estabelecimento ativo (sem expor o hash do token). */
export async function listEstablishmentInvitations(
  establishmentId: string,
): Promise<TeamInvitation[]> {
  const { data, error } = await supabase
    .from('establishment_invitations')
    .select('id, email, phone, role, permissions, created_at, expires_at, accepted_at, cancelled_at')
    .eq('establishment_id', establishmentId)
    .order('created_at', { ascending: false })

  if (error) {
    throw error
  }

  return (data ?? []) as unknown as TeamInvitation[]
}

/** Cria o convite e devolve o token bruto (exibido uma única vez ao dono). */
export async function createTeamInvitation(
  establishmentId: string,
  input: { email: string; role: TeamRole; permissions: string[] },
): Promise<string> {
  const { data, error } = await supabase.rpc('create_establishment_invitation', {
    p_establishment_id: establishmentId,
    p_email: input.email,
    p_role: input.role,
    p_permissions: input.permissions,
  })

  if (error) {
    throw error
  }

  return data as string
}

export interface PendingInvitation {
  establishment_id: string
  establishment_name: string
  role: TeamRole
  expires_at: string
}

/** Convites pendentes endereçados ao e-mail confirmado do usuário autenticado. */
export async function getMyPendingInvitations(): Promise<PendingInvitation[]> {
  const { data, error } = await supabase.rpc('get_my_pending_invitations')

  if (error) {
    throw error
  }

  return (data ?? []) as unknown as PendingInvitation[]
}

export async function cancelTeamInvitation(invitationId: string): Promise<void> {
  const { error } = await supabase.rpc('cancel_establishment_invitation', {
    p_invitation_id: invitationId,
  })

  if (error) {
    throw error
  }
}

export async function acceptTeamInvitation(token: string): Promise<string> {
  const { data, error } = await supabase.rpc('accept_establishment_invitation', {
    p_token: token,
  })

  if (error) {
    throw error
  }

  return data as string
}

export async function updateMemberRole(memberId: string, role: TeamRole): Promise<void> {
  const { error } = await supabase.rpc('update_establishment_member_role', {
    p_member_id: memberId,
    p_role: role,
  })

  if (error) {
    throw error
  }
}

export async function setMemberActive(memberId: string, isActive: boolean): Promise<void> {
  const { error } = await supabase.rpc('set_establishment_member_active', {
    p_member_id: memberId,
    p_is_active: isActive,
  })

  if (error) {
    throw error
  }
}

export async function setMemberPermissions(
  memberId: string,
  permissionKeys: string[],
): Promise<void> {
  const { error } = await supabase.rpc('set_establishment_member_permissions', {
    p_member_id: memberId,
    p_permission_keys: permissionKeys,
  })

  if (error) {
    throw error
  }
}
