export type PostAuthRedirectInput = {
  isAuthenticated: boolean
  establishmentCount: number
  isLoadingEstablishments: boolean
  /** Caminho interno de retorno (ex.: aceite de convite). */
  nextPath?: string | null
}

export type PostAuthRedirectResult =
  | { kind: 'redirect'; path: string }
  | { kind: 'wait' }
  | { kind: 'error' }

/**
 * Valida um caminho interno de retorno. Barreira contra open redirect:
 * apenas caminhos relativos internos são aceitos.
 */
export function isSafeInternalPath(path: string | null | undefined): boolean {
  if (!path) return false

  return path.startsWith('/') && !path.startsWith('//') && !path.includes('\\')
}

/**
 * Decides what the OAuth callback should do once authentication has settled.
 *
 * - Not authenticated after initialization => error.
 * - Authenticated but establishments still loading => wait.
 * - Authenticated with a safe internal next path => that path (ex.: invite).
 * - Authenticated with no establishment => /welcome.
 * - Authenticated with exactly one establishment => /dashboard.
 * - Authenticated with multiple establishments => /select-establishment.
 */
export function resolvePostAuthRedirect(input: PostAuthRedirectInput): PostAuthRedirectResult {
  const { isAuthenticated, establishmentCount, isLoadingEstablishments, nextPath } = input

  if (!isAuthenticated) {
    return { kind: 'error' }
  }

  if (isLoadingEstablishments) {
    return { kind: 'wait' }
  }

  if (isSafeInternalPath(nextPath)) {
    return { kind: 'redirect', path: nextPath as string }
  }

  if (establishmentCount === 0) {
    return { kind: 'redirect', path: '/welcome' }
  }

  if (establishmentCount === 1) {
    return { kind: 'redirect', path: '/dashboard' }
  }

  return { kind: 'redirect', path: '/select-establishment' }
}
