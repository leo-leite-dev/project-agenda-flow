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

interface ProfessionalBaseRow {
  id: string
  member_id: string
  accepts_appointments: boolean
  created_at: string
}

interface ProfessionalMemberRow {
  id: string
  user_id: string
  role: TeamRole
  is_active: boolean
  profiles: {
    id: string
    full_name: string
    avatar_url: string | null
  } | null
}

interface ProfessionalServiceLinkRow {
  id: string
  professional_id: string
  service_id: string
}

interface ProfessionalServiceRow {
  id: string
  name: string
  category: ServiceCategory | string
  is_active: boolean
}

/**
 * Lista os profissionais habilitados do estabelecimento ativo, com os
 * serviços associados. O filtro por estabelecimento é defesa em profundidade:
 * a RLS limita o resultado ao tenant do usuário.
 */
export async function listEstablishmentProfessionals(
  establishmentId: string,
): Promise<EstablishmentProfessional[]> {
  const { data: professionalData, error: professionalError } = await supabase
    .from('establishment_professionals')
    .select('id, member_id, accepts_appointments, created_at')
    .eq('establishment_id', establishmentId)
    .order('created_at', { ascending: true })

  if (professionalError) {
    throw professionalError
  }

  const professionals = (professionalData ?? []) as unknown as ProfessionalBaseRow[]
  if (professionals.length === 0) return []

  const memberIds = professionals.map((professional) => professional.member_id)
  const [memberResult, linkResult] = await Promise.all([
    supabase
      .from('establishment_members')
      .select('id, user_id, role, is_active, profiles:user_id(id, full_name, avatar_url)')
      .eq('establishment_id', establishmentId)
      .in('id', memberIds),
    supabase
      .from('establishment_professional_services')
      .select('id, professional_id, service_id')
      .eq('establishment_id', establishmentId)
      .in(
        'professional_id',
        professionals.map((professional) => professional.id),
      ),
  ])

  if (memberResult.error) throw memberResult.error
  if (linkResult.error) throw linkResult.error

  const members = new Map(
    ((memberResult.data ?? []) as unknown as ProfessionalMemberRow[]).map((member) => [member.id, member]),
  )
  const links = (linkResult.data ?? []) as unknown as ProfessionalServiceLinkRow[]
  const serviceIds = [...new Set(links.map((link) => link.service_id))]
  const serviceResult = serviceIds.length
    ? await supabase
        .from('establishment_services')
        .select('id, name, category, is_active')
        .eq('establishment_id', establishmentId)
        .in('id', serviceIds)
    : { data: [], error: null }

  if (serviceResult.error) throw serviceResult.error

  const services = new Map(
    ((serviceResult.data ?? []) as unknown as ProfessionalServiceRow[]).map((service) => [service.id, service]),
  )
  const servicesByProfessional = new Map<string, ProfessionalServiceLink[]>()

  for (const link of links) {
    const service = services.get(link.service_id)
    if (!service) continue

    const current = servicesByProfessional.get(link.professional_id) ?? []
    current.push(service)
    servicesByProfessional.set(link.professional_id, current)
  }

  return professionals.map((professional) => {
    const member = members.get(professional.member_id)

    return {
      id: professional.id,
      member_id: professional.member_id,
      user_id: member?.user_id ?? '',
      role: member?.role ?? 'professional',
      is_active: member?.is_active ?? false,
      accepts_appointments: professional.accepts_appointments,
      created_at: professional.created_at,
      full_name: member?.profiles?.full_name ?? null,
      avatar_url: member?.profiles?.avatar_url ?? null,
      services: servicesByProfessional.get(professional.id) ?? [],
    }
  })
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
