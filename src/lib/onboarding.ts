import { isSafeInternalPath } from './authRedirect'

export const PENDING_INVITATION_STORAGE_KEY = 'agenda-flow:pending-invitation'
export const PENDING_INVITATION_CHANGED_EVENT = 'agenda-flow:pending-invitation-changed'

/** Um caminho de convite é sempre interno e começa com /convite/. */
export function isInvitationPath(path: string | null | undefined): boolean {
  return Boolean(path && isSafeInternalPath(path) && path.startsWith('/convite/'))
}

/**
 * Guarda o caminho do convite em andamento para que ele sobreviva ao
 * cadastro, à confirmação de e-mail, ao login e à atualização da página.
 *
 * O valor guardado é apenas um CAMINHO de navegação — nunca uma prova de
 * autorização. O aceite continua validado pelo banco (identidade verificada,
 * expiração e uso único).
 */
export function storePendingInvitationPath(path: string | null): void {
  try {
    if (isInvitationPath(path)) {
      window.sessionStorage.setItem(PENDING_INVITATION_STORAGE_KEY, path as string)
    } else {
      window.sessionStorage.removeItem(PENDING_INVITATION_STORAGE_KEY)
    }
  } catch {
    // Armazenamento indisponível (navegador restrito): o fluxo segue pelo link.
  }

  if (typeof window !== 'undefined') {
    window.dispatchEvent(new Event(PENDING_INVITATION_CHANGED_EVENT))
  }
}

export function readPendingInvitationPath(): string | null {
  try {
    const stored = window.sessionStorage.getItem(PENDING_INVITATION_STORAGE_KEY)
    return isInvitationPath(stored) ? stored : null
  } catch {
    return null
  }
}

export function clearPendingInvitationPath(): void {
  storePendingInvitationPath(null)
}

export interface OnboardingInput {
  isAuthenticated: boolean
  isLoading: boolean
  isLoadingEstablishments: boolean
  isLoadingInvitations: boolean
  establishmentCount: number
  /** Existe um estabelecimento ativo já escolhido pelo usuário. */
  hasActiveEstablishment?: boolean
  /** Existe convite pendente para a identidade autenticada. */
  hasPendingInvitation: boolean
  /** Caminho do convite em andamento, quando conhecido. */
  pendingInvitationPath: string | null
}

export type OnboardingDecision =
  /** Ainda estamos carregando: não decidir nada (evita falso "sem vínculos"). */
  | { kind: 'loading' }
  /** Deve autenticar-se. */
  | { kind: 'login' }
  /** Deve aceitar o convite em andamento. */
  | { kind: 'invitation'; path: string }
  /** Tem convite pendente, mas sem o link: orientar a solicitar o link. */
  | { kind: 'pending-invitation' }
  /** Escolher entre vários estabelecimentos. */
  | { kind: 'select-establishment' }
  /** Entrar direto no estabelecimento. */
  | { kind: 'dashboard' }
  /** Pode criar o próprio estabelecimento. */
  | { kind: 'welcome' }

/**
 * Decide a tela inicial do usuário.
 *
 * Regras:
 *  • carregamento em andamento → 'loading' (nunca tratar lista vazia como
 *    ausência definitiva de vínculos);
 *  • com convite pendente → priorizar o aceite do convite, nunca exigir a
 *    criação de um estabelecimento;
 *  • com um estabelecimento já escolhido → dashboard (o usuário com vários
 *    vínculos precisa poder acessar o estabelecimento escolhido);
 *  • com vários vínculos e sem escolha → seleção;
 *  • com um vínculo → dashboard;
 *  • sem vínculos e sem convite → criação do próprio estabelecimento.
 */
export function resolveOnboardingDecision(input: OnboardingInput): OnboardingDecision {
  const {
    isAuthenticated,
    isLoading,
    isLoadingEstablishments,
    isLoadingInvitations,
    establishmentCount,
    hasActiveEstablishment,
    hasPendingInvitation,
    pendingInvitationPath,
  } = input

  if (isLoading || isLoadingEstablishments || isLoadingInvitations) {
    return { kind: 'loading' }
  }

  if (!isAuthenticated) {
    return { kind: 'login' }
  }

  if (hasActiveEstablishment && establishmentCount > 0) {
    return { kind: 'dashboard' }
  }

  if (establishmentCount > 1) {
    return { kind: 'select-establishment' }
  }

  if (establishmentCount === 1) {
    return { kind: 'dashboard' }
  }

  if (hasPendingInvitation) {
    return isInvitationPath(pendingInvitationPath)
      ? { kind: 'invitation', path: pendingInvitationPath as string }
      : { kind: 'pending-invitation' }
  }

  return { kind: 'welcome' }
}
