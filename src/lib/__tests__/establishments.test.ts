import { beforeEach, describe, expect, it } from 'vitest'

import {
  clearPersistedEstablishmentId,
  dedupeEstablishmentsById,
  isEstablishmentAuthorized,
  persistEstablishmentId,
  readPersistedEstablishmentId,
  resolveActiveEstablishment,
} from '../establishments'
import type { UserEstablishment } from '../../contexts/AuthContext'

function establishmentFixture(
  id: string,
  overrides: Partial<UserEstablishment> = {},
): UserEstablishment {
  return {
    id,
    owner_id: 'user-1',
    name: `Estabelecimento ${id}`,
    slug: `estabelecimento-${id}`,
    type: 'barbershop',
    document: null,
    phone: null,
    email: null,
    address: null,
    is_active: true,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    role: 'owner',
    ...overrides,
  }
}

describe('dedupeEstablishmentsById', () => {
  it('mantém cada estabelecimento uma única vez mesmo com vínculos repetidos', () => {
    const barberLeo = establishmentFixture('est-barberleo', { name: 'BarberLeo' })
    const duplicated = establishmentFixture('est-barberleo', {
      name: 'BarberLeo',
      role: 'professional',
    })
    const other = establishmentFixture('est-outro')

    const unique = dedupeEstablishmentsById([barberLeo, duplicated, other])

    expect(unique).toHaveLength(2)
    expect(unique.map((item) => item.id)).toEqual(['est-barberleo', 'est-outro'])
  })

  it('preserva a ordem original dos vínculos autorizados', () => {
    const unique = dedupeEstablishmentsById([
      establishmentFixture('est-b'),
      establishmentFixture('est-a'),
    ])

    expect(unique.map((item) => item.id)).toEqual(['est-b', 'est-a'])
  })
})

describe('isEstablishmentAuthorized', () => {
  it('aceita apenas estabelecimentos da lista do usuário', () => {
    const list = [establishmentFixture('est-1')]

    expect(isEstablishmentAuthorized(list, 'est-1')).toBe(true)
    expect(isEstablishmentAuthorized(list, 'est-2')).toBe(false)
    expect(isEstablishmentAuthorized(list, null)).toBe(false)
    expect(isEstablishmentAuthorized([], 'est-1')).toBe(false)
  })
})

describe('resolveActiveEstablishment', () => {
  it('mantém o vínculo atual quando ele continua autorizado', () => {
    const current = establishmentFixture('est-1')
    const resolved = resolveActiveEstablishment([current, establishmentFixture('est-2')], {
      currentId: 'est-1',
    })

    expect(resolved?.id).toBe('est-1')
  })

  it('descarta o vínculo atual que saiu da lista autorizada', () => {
    const resolved = resolveActiveEstablishment(
      [establishmentFixture('est-2'), establishmentFixture('est-3')],
      { currentId: 'est-1' },
    )

    expect(resolved).toBeNull()
  })

  it('restaura a escolha persistida somente quando ela é autorizada', () => {
    const list = [establishmentFixture('est-1'), establishmentFixture('est-2')]

    expect(resolveActiveEstablishment(list, { persistedId: 'est-2' })?.id).toBe('est-2')
    expect(resolveActiveEstablishment(list, { persistedId: 'est-3' })).toBeNull()
  })

  it('ativa automaticamente o único estabelecimento acessível', () => {
    const resolved = resolveActiveEstablishment([establishmentFixture('est-1')])

    expect(resolved?.id).toBe('est-1')
  })

  it('não escolhe por conta própria quando há vários estabelecimentos', () => {
    const resolved = resolveActiveEstablishment([
      establishmentFixture('est-1'),
      establishmentFixture('est-2'),
    ])

    expect(resolved).toBeNull()
  })
})

describe('persistência do estabelecimento ativo', () => {
  beforeEach(() => {
    window.localStorage.clear()
  })

  it('guarda a escolha por usuário (sem vazar entre contas)', () => {
    persistEstablishmentId('user-1', 'est-1')

    expect(readPersistedEstablishmentId('user-1')).toBe('est-1')
    expect(readPersistedEstablishmentId('user-2')).toBeNull()
  })

  it('apaga a escolha no logout', () => {
    persistEstablishmentId('user-1', 'est-1')
    clearPersistedEstablishmentId('user-1')

    expect(readPersistedEstablishmentId('user-1')).toBeNull()
  })

  it('ignora usuários desconhecidos', () => {
    persistEstablishmentId(null, 'est-1')

    expect(readPersistedEstablishmentId(null)).toBeNull()
  })
})
