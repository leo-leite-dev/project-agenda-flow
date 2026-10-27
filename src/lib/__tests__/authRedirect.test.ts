import { describe, expect, it } from 'vitest'

import { resolvePostAuthRedirect } from '../authRedirect'

describe('resolvePostAuthRedirect', () => {
  it('returns an error when not authenticated after init', () => {
    expect(
      resolvePostAuthRedirect({
        isAuthenticated: false,
        establishmentCount: 0,
        isLoadingEstablishments: false,
      }),
    ).toEqual({ kind: 'error' })
  })

  it('waits while establishments are still loading', () => {
    expect(
      resolvePostAuthRedirect({
        isAuthenticated: true,
        establishmentCount: 0,
        isLoadingEstablishments: true,
      }),
    ).toEqual({ kind: 'wait' })
  })

  it('redirects to /welcome when the user has no establishment', () => {
    expect(
      resolvePostAuthRedirect({
        isAuthenticated: true,
        establishmentCount: 0,
        isLoadingEstablishments: false,
      }),
    ).toEqual({ kind: 'redirect', path: '/welcome' })
  })

  it('redirects to /dashboard with a single establishment', () => {
    expect(
      resolvePostAuthRedirect({
        isAuthenticated: true,
        establishmentCount: 1,
        isLoadingEstablishments: false,
      }),
    ).toEqual({ kind: 'redirect', path: '/dashboard' })
  })

  it('redirects to /select-establishment with multiple establishments', () => {
    expect(
      resolvePostAuthRedirect({
        isAuthenticated: true,
        establishmentCount: 2,
        isLoadingEstablishments: false,
      }),
    ).toEqual({ kind: 'redirect', path: '/select-establishment' })
  })
})
