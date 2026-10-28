import { describe, expect, it, vi, beforeEach } from 'vitest'

import {
  addProfessionalService,
  listEstablishmentProfessionals,
  removeProfessionalService,
  setProfessionalEnabled,
} from '../professionals'

const fromMock = vi.hoisted(() => vi.fn())
const rpcMock = vi.hoisted(() => vi.fn())

vi.mock('../supabase', () => ({
  supabase: {
    from: (...args: unknown[]) => fromMock(...args),
    rpc: (...args: unknown[]) => rpcMock(...args),
  },
}))

const professionalRow = {
  id: 'pro-1',
  member_id: 'mem-1',
  accepts_appointments: true,
  created_at: '2026-02-01T10:00:00Z',
  member: {
    id: 'mem-1',
    user_id: 'user-2',
    role: 'professional',
    is_active: true,
    profiles: { id: 'user-2', full_name: 'Carlos Silva', avatar_url: null },
  },
  services: [
    {
      id: 'link-1',
      establishment_services: {
        id: 'svc-1',
        name: 'Corte Masculino',
        category: 'cabelo',
        is_active: true,
      },
    },
    {
      id: 'link-2',
      establishment_services: {
        id: 'svc-2',
        name: 'Barba',
        category: 'barba',
        is_active: false,
      },
    },
  ],
}

function expectChainedQuery() {
  const builder = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    order: vi.fn(async () => ({ data: [professionalRow], error: null })),
  }

  fromMock.mockReturnValue(builder)
  return builder
}

describe('listEstablishmentProfessionals', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('consulta a tabela com filtro pelo estabelecimento ativo e mapeia a leitura', async () => {
    const builder = expectChainedQuery()

    const professionals = await listEstablishmentProfessionals('est-1')

    expect(fromMock).toHaveBeenCalledWith('establishment_professionals')
    expect(builder.select).toHaveBeenCalledWith(
      'id, member_id, accepts_appointments, created_at, member:establishment_members!establishment_professionals_member_establishment_fkey(id, user_id, role, is_active, profiles:user_id(id, full_name, avatar_url)), services:establishment_professional_services!establishment_professional_services_professional_establishment_fkey(id, establishment_services:establishment_professional_services_service_establishment_fkey(id, name, category, is_active))',
    )
    expect(builder.eq).toHaveBeenCalledWith('establishment_id', 'est-1')

    expect(professionals).toHaveLength(1)
    expect(professionals[0]).toMatchObject({
      id: 'pro-1',
      member_id: 'mem-1',
      user_id: 'user-2',
      role: 'professional',
      is_active: true,
      accepts_appointments: true,
      full_name: 'Carlos Silva',
      services: [
        { id: 'svc-1', name: 'Corte Masculino', is_active: true },
        { id: 'svc-2', name: 'Barba', is_active: false },
      ],
    })
  })

  it('propaga o erro do Supabase', async () => {
    const builder = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      order: vi.fn(async () => ({ data: null, error: { message: 'rls' } })),
    }

    fromMock.mockReturnValue(builder)

    await expect(listEstablishmentProfessionals('est-1')).rejects.toEqual({ message: 'rls' })
  })
})

describe('RPCs de profissionais', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it('setProfessionalEnabled chama set_establishment_professional com o membro', async () => {
    rpcMock.mockResolvedValue({ error: null })

    await setProfessionalEnabled('mem-1', true)

    expect(rpcMock).toHaveBeenCalledWith('set_establishment_professional', {
      p_member_id: 'mem-1',
      p_accepts_appointments: true,
    })
  })

  it('addProfessionalService chama add_establishment_professional_service', async () => {
    rpcMock.mockResolvedValue({ error: null })

    await addProfessionalService('pro-1', 'svc-1')

    expect(rpcMock).toHaveBeenCalledWith('add_establishment_professional_service', {
      p_professional_id: 'pro-1',
      p_service_id: 'svc-1',
    })
  })

  it('removeProfessionalService chama remove_establishment_professional_service', async () => {
    rpcMock.mockResolvedValue({ error: null })

    await removeProfessionalService('pro-1', 'svc-1')

    expect(rpcMock).toHaveBeenCalledWith('remove_establishment_professional_service', {
      p_professional_id: 'pro-1',
      p_service_id: 'svc-1',
    })
  })

  it('propaga o erro de RPC (mensagem do PostgreSQL)', async () => {
    rpcMock.mockResolvedValue({ error: { message: 'Servico inativo nao pode ser associado' } })

    await expect(addProfessionalService('pro-1', 'svc-2')).rejects.toEqual({
      message: 'Servico inativo nao pode ser associado',
    })
  })
})
