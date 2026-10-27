import { beforeEach, describe, expect, it, vi } from 'vitest'

const { from, builder } = vi.hoisted(() => {
  const builder = {
    select: vi.fn(),
    eq: vi.fn(),
    order: vi.fn(),
  }

  builder.select.mockReturnValue(builder)
  builder.eq.mockReturnValue(builder)

  return { from: vi.fn(() => builder), builder }
})

vi.mock('@supabase/supabase-js', () => ({
  createClient: vi.fn(() => ({ from })),
}))

async function loadSupabaseModule() {
  vi.stubEnv('VITE_SUPABASE_URL', 'https://example.supabase.co')
  vi.stubEnv('VITE_SUPABASE_PUBLISHABLE_KEY', 'public-anon-key')

  vi.resetModules()

  return await import('../supabase')
}

function establishmentPayload() {
  return {
    id: 'est-barberleo',
    owner_id: 'user-1',
    name: 'BarberLeo',
    slug: 'barberleo',
    type: 'barbershop',
    document: null,
    phone: null,
    email: null,
    address: null,
    is_active: true,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  }
}

describe('getUserEstablishments', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    builder.select.mockReturnValue(builder)
    builder.eq.mockReturnValue(builder)
  })

  it('filtra os vínculos pelo usuário autenticado', async () => {
    builder.order.mockResolvedValueOnce({ data: [], error: null })

    const { getUserEstablishments } = await loadSupabaseModule()
    await getUserEstablishments('user-1')

    expect(from).toHaveBeenCalledWith('establishment_members')
    expect(builder.eq).toHaveBeenCalledWith('user_id', 'user-1')
    expect(builder.eq).toHaveBeenCalledWith('is_active', true)
  })

  it('não consulta nada sem usuário autenticado', async () => {
    const { getUserEstablishments } = await loadSupabaseModule()
    const result = await getUserEstablishments('')

    expect(result).toEqual([])
    expect(from).not.toHaveBeenCalled()
  })

  it('ignora vínculos sem estabelecimento e estabelecimentos inativos', async () => {
    builder.order.mockResolvedValueOnce({
      data: [
        { role: 'owner', establishments: establishmentPayload() },
        { role: 'owner', establishments: null },
        {
          role: 'professional',
          establishments: { ...establishmentPayload(), id: 'est-inativo', is_active: false },
        },
      ],
      error: null,
    })

    const { getUserEstablishments } = await loadSupabaseModule()
    const result = await getUserEstablishments('user-1')

    expect(result).toHaveLength(1)
    expect(result[0].id).toBe('est-barberleo')
    expect(result[0].role).toBe('owner')
  })

  it('propaga erros do banco', async () => {
    builder.order.mockResolvedValueOnce({
      data: null,
      error: new Error('permission denied for table establishment_members'),
    })

    const { getUserEstablishments } = await loadSupabaseModule()

    await expect(getUserEstablishments('user-1')).rejects.toThrow('permission denied')
  })
})
