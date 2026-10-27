import type { UserEstablishment } from '../contexts/AuthContext'

/**
 * Chave de armazenamento do estabelecimento ativo.
 *
 * O id é guardado POR USUÁRIO: dois usuários diferentes no mesmo navegador
 * (ex.: dono e funcionário) nunca compartilham a escolha.
 */
export const ACTIVE_ESTABLISHMENT_STORAGE_KEY = 'agenda-flow:active-establishment'

function storageKey(userId: string): string {
  return `${ACTIVE_ESTABLISHMENT_STORAGE_KEY}:${userId}`
}

/**
 * Remove vínculos repetidos do mesmo estabelecimento.
 *
 * Proteção adicional da interface: a listagem deve mostrar cada
 * estabelecimento acessível uma única vez. A causa raiz (vínculos de outras
 * pessoas no resultado) é corrigida na consulta; esta deduplicação apenas
 * evita a repetição visual caso o banco ainda possua inconsistências.
 */
export function dedupeEstablishmentsById(
  establishments: ReadonlyArray<UserEstablishment>,
): UserEstablishment[] {
  const seen = new Set<string>()
  const unique: UserEstablishment[] = []

  for (const establishment of establishments) {
    if (!establishment || seen.has(establishment.id)) continue
    seen.add(establishment.id)
    unique.push(establishment)
  }

  return unique
}

/**
 * Verdadeiro quando o estabelecimento pertence à lista autorizada do usuário.
 * Usado como barreira antes de ativar um estabelecimento ou navegar para ele.
 */
export function isEstablishmentAuthorized(
  establishments: ReadonlyArray<UserEstablishment>,
  establishmentId: string | null | undefined,
): boolean {
  if (!establishmentId) return false
  return establishments.some((establishment) => establishment.id === establishmentId)
}

/**
 * Escolhe o estabelecimento ativo.
 *
 * Regras (nunca inventa acesso):
 *   • o vínculo atual só é mantido se continuar na lista autorizada;
 *   • a escolha persistida só é restaurada se pertencer à lista autorizada;
 *   • com um único estabelecimento acessível, ele é ativado automaticamente;
 *   • com vários e sem escolha, retorna null (o usuário deve escolher).
 */
export function resolveActiveEstablishment(
  establishments: ReadonlyArray<UserEstablishment>,
  options: {
    currentId?: string | null
    persistedId?: string | null
  } = {},
): UserEstablishment | null {
  const { currentId, persistedId } = options

  if (isEstablishmentAuthorized(establishments, currentId)) {
    return establishments.find((establishment) => establishment.id === currentId) ?? null
  }

  if (isEstablishmentAuthorized(establishments, persistedId)) {
    return establishments.find((establishment) => establishment.id === persistedId) ?? null
  }

  if (establishments.length === 1) {
    return establishments[0]
  }

  return null
}

/**
 * Lê o estabelecimento ativo guardado no navegador.
 * Retorna null quando não há escolha salva (ou quando o armazenamento falha).
 */
export function readPersistedEstablishmentId(userId: string | null | undefined): string | null {
  if (!userId) return null

  try {
    const stored = window.localStorage.getItem(storageKey(userId))
    return stored && stored.length > 0 ? stored : null
  } catch {
    // Armazenamento indisponível (navegador restrito): sem escolha persistida.
    return null
  }
}

/** Guarda o estabelecimento ativo escolhido (idempotente). */
export function persistEstablishmentId(userId: string | null | undefined, establishmentId: string): void {
  if (!userId) return

  try {
    window.localStorage.setItem(storageKey(userId), establishmentId)
  } catch {
    // Armazenamento indisponível: a sessão atual segue normalmente.
  }
}

/** Apaga a escolha guardada (troca de usuário ou saída da sessão). */
export function clearPersistedEstablishmentId(userId: string | null | undefined): void {
  if (!userId) return

  try {
    window.localStorage.removeItem(storageKey(userId))
  } catch {
    // Armazenamento indisponível: nada a limpar.
  }
}
