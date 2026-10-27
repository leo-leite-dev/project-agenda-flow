export type PostAuthRedirectInput = {
  isAuthenticated: boolean
  establishmentCount: number
  isLoadingEstablishments: boolean
}

export type PostAuthRedirectResult =
  | { kind: 'redirect'; path: string }
  | { kind: 'wait' }
  | { kind: 'error' }

/**
 * Decides what the OAuth callback should do once authentication has settled.
 *
 * - Not authenticated after initialization => error.
 * - Authenticated but establishments still loading => wait.
 * - Authenticated with no establishment => /welcome.
 * - Authenticated with exactly one establishment => /dashboard.
 * - Authenticated with multiple establishments => /select-establishment.
 */
export function resolvePostAuthRedirect(input: PostAuthRedirectInput): PostAuthRedirectResult {
  const { isAuthenticated, establishmentCount, isLoadingEstablishments } = input

  if (!isAuthenticated) {
    return { kind: 'error' }
  }

  if (isLoadingEstablishments) {
    return { kind: 'wait' }
  }

  if (establishmentCount === 0) {
    return { kind: 'redirect', path: '/welcome' }
  }

  if (establishmentCount === 1) {
    return { kind: 'redirect', path: '/dashboard' }
  }

  return { kind: 'redirect', path: '/select-establishment' }
}
