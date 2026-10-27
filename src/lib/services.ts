import type { ServiceCategory } from './database.types'
import { supabase } from './supabase'

export type { ServiceCategory }

export interface EstablishmentService {
  id: string
  establishment_id: string
  name: string
  description: string | null
  category: ServiceCategory
  duration_minutes: number
  price_cents: number
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface ServiceInput {
  name: string
  description: string | null
  category: ServiceCategory
  duration_minutes: number
  price_cents: number
  is_active: boolean
}

/** Categorias simples da primeira versão do catálogo (fixas e documentadas). */
export const SERVICE_CATEGORIES: ReadonlyArray<{ value: ServiceCategory; label: string }> = [
  { value: 'cabelo', label: 'Cabelo' },
  { value: 'barba', label: 'Barba' },
  { value: 'estetica', label: 'Estética' },
  { value: 'unhas', label: 'Unhas' },
  { value: 'outros', label: 'Outros' },
]

export const SERVICE_CATEGORY_VALUES: ReadonlyArray<ServiceCategory> =
  SERVICE_CATEGORIES.map((category) => category.value)

export function serviceCategoryLabel(category: ServiceCategory): string {
  return SERVICE_CATEGORIES.find((item) => item.value === category)?.label ?? 'Outros'
}

/**
 * Formata um valor em centavos como moeda brasileira (R$ 1.234,56).
 * O armazenamento é sempre em centavos inteiros.
 */
export function formatBRL(cents: number): string {
  return (cents / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: 2,
  })
}

/**
 * Converte o texto digitado em centavos inteiros.
 * Aceita "35", "35,50", "R$ 1.234,56" e variações com pontos ou espaços.
 * Retorna null quando não há nenhum dígito (campo vazio).
 */
export function parseBRLToCents(input: string): number | null {
  const digits = input.replace(/\D/g, '')

  if (digits.length === 0) {
    return null
  }

  return Number.parseInt(digits, 10)
}

/** Máscara de digitação: reconstrói a moeda a partir dos dígitos. */
export function buildBRLMask(input: string): string {
  const cents = parseBRLToCents(input)

  if (cents === null) {
    return ''
  }

  return formatBRL(cents)
}

/**
 * Lista os serviços do estabelecimento ativo.
 * O establishment_id é sempre o do estabelecimento ativo da sessão; o filtro
 * adicional é defesa em profundidade — o isolamento é garantido pelas
 * políticas RLS.
 */
export async function listServices(establishmentId: string): Promise<EstablishmentService[]> {
  const { data, error } = await supabase
    .from('establishment_services')
    .select(
      'id, establishment_id, name, description, category, duration_minutes, price_cents, is_active, created_at, updated_at',
    )
    .eq('establishment_id', establishmentId)
    .order('name', { ascending: true })

  if (error) {
    throw error
  }

  return (data ?? []) as unknown as EstablishmentService[]
}

export async function createService(
  establishmentId: string,
  input: ServiceInput,
): Promise<string> {
  const { data, error } = await supabase.rpc('create_establishment_service', {
    p_establishment_id: establishmentId,
    p_name: input.name,
    p_description: input.description ?? undefined,
    p_category: input.category,
    p_duration_minutes: input.duration_minutes,
    p_price_cents: input.price_cents,
    p_is_active: input.is_active,
  })

  if (error) {
    throw error
  }

  return data as string
}

export async function updateService(
  serviceId: string,
  input: ServiceInput,
): Promise<void> {
  const { error } = await supabase.rpc('update_establishment_service', {
    p_service_id: serviceId,
    p_name: input.name,
    p_description: input.description ?? undefined,
    p_category: input.category,
    p_duration_minutes: input.duration_minutes,
    p_price_cents: input.price_cents,
    p_is_active: input.is_active,
  })

  if (error) {
    throw error
  }
}

export async function setServiceActive(serviceId: string, isActive: boolean): Promise<void> {
  const { error } = await supabase.rpc('set_establishment_service_active', {
    p_service_id: serviceId,
    p_is_active: isActive,
  })

  if (error) {
    throw error
  }
}
