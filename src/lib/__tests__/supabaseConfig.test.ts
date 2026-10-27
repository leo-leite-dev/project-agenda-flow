import { describe, expect, it, vi } from 'vitest'

vi.mock('@supabase/supabase-js', () => ({
  createClient: vi.fn(() => ({})),
}))

import { createClient } from '@supabase/supabase-js'

describe('supabase client configuration', () => {
  it('uses the implicit OAuth flow and detects the session in the URL', async () => {
    vi.stubEnv('VITE_SUPABASE_URL', 'https://example.supabase.co')
    vi.stubEnv('VITE_SUPABASE_PUBLISHABLE_KEY', 'public-anon-key')

    vi.resetModules()
    await import('../supabase')

    expect(createClient).toHaveBeenCalledTimes(1)

    const [, , options] = (createClient as unknown as ReturnType<typeof vi.fn>).mock.calls[0]

    expect(options.auth.flowType).toBe('implicit')
    expect(options.auth.detectSessionInUrl).toBe(true)
    expect(options.auth.persistSession).toBe(true)
    expect(options.auth.autoRefreshToken).toBe(true)

    vi.unstubAllEnvs()
  })
})
