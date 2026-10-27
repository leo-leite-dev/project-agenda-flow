import type { ServiceCategory } from './database.types'
import type { TeamRole } from './team'
import { supabase } from './supabase'

/** Serviço associado a um profissional (visão de apresentação). */
export interface ProfessionalServiceLink {
  id: string
  name: string
  category: ServiceCategory | string
  is_active: boolean
}

export interface EstablishmentProfessional {
  id: string
  member_id: string
  user_id: string
  role: TeamRole
  /** Situação do vínculo de funcionário (independe da habilitação). */
  is_active: boolean
  accepts_appointments: boolean
  created_at: string
  full_name: string | null
  avatar_url: string | null
  services: ProfessionalServiceLink[]
}

interface ProfessionalRow {
  id: string
  member_id: string
  accepts_appointments: boolean
  created_at: string
  member: {
    id: string
    user_id: string
    role: TeamRole
    is_active: boolean
    profiles: {
      id: string
      full_name: string
      avatar_url: string | null
    } | null
  } | null
  services: Array<{
    id: string
    establishment_services: {
      id: string
      name: string
      category: ServiceCategory | string
      is_active: boolean
    } | null
  }> | null
}

/**
 * Lista os profissionais habilitados do estabelecimento ativo, com os
 * serviços associados. O filtro por estabelecimento é defesa em profundidade:
 * a RLS limita o resultado ao tenant do usuário.
 */
export async function listEstablishmentProfessionals(
  establishmentId: string,
): Promise<EstablishmentProfessional[]> {
  const { data, error } = await supabase
    .from('establishment_professionals')
    .select(
      'id, member_id, accepts_appointments, created_at, member:member_id(id, user_id, role, is_active, profiles:user_id(id, full_name, avatar_url)), services:establishment_professional_services(id, establishment_services(id, name, category, is_active))',
    )
    .eq('establishment_id', establishmentId)
    .order('created_at', { ascending: true })

  if (error) {
    throw error
  }

  return ((data ?? []) as unknown as ProfessionalRow[]).map((row) => ({
    id: row.id,
    member_id: row.member_id,
    user_id: row.member?.user_id ?? '',
    role: row.member?.role ?? 'professional',
    is_active: row.member?.is_active ?? false,
    accepts_appointments: row.accepts_appointments,
    created_at: row.created_at,
    full_name: row.member?.profiles?.full_name ?? null,
    avatar_url: row.member?.profiles?.avatar_url ?? null,
    services: (row.services ?? []).map((link) => ({
      id: link.establishment_services?.id ?? '',
      name: link.establishment_services?.name ?? '',
      category: link.establishment_services?.category ?? 'outros',
      is_active: link.establishment_services?.is_active ?? true,
    })),
  }))
}

/**
 * Habilita (ou pausa) um membro como profissional de atendimento.
 * A RPC valida no banco o proprietário, o vínculo ativo e a unicidade.
 */
export async function setProfessionalEnabled(
  memberId: string,
  acceptsAppointments: boolean,
): Promise<void> {
  const { error } = await supabase.rpc('set_establishment_professional', {
    p_member_id: memberId,
    p_accepts_appointments: acceptsAppointments,
  })

  if (error) {
    throw error
  }
}

/** Associa um serviço (ativo, do mesmo estabelecimento) ao profissional. */
export async function addProfessionalService(
  professionalId: string,
  serviceId: string,
): Promise<void> {
  const { error } = await supabase.rpc('add_establishment_professional_service', {
    p_professional_id: professionalId,
    p_service_id: serviceId,
  })

  if (error) {
    throw error
  }
}

/** Remove a associação do serviço com o profissional. */
export async function removeProfessionalService(
  professionalId: string,
  serviceId: string,
): Promise<void> {
  const { error } = await supabase.rpc('remove_establishment_professional_service', {
    p_professional_id: professionalId,
    p_service_id: serviceId,
  })

  if (error) {
    throw error
  }
}
