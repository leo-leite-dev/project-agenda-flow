import { describe, expect, it, vi } from 'vitest'

const { rpc } = vi.hoisted(() => ({
  rpc: vi.fn(),
}))

vi.mock('@supabase/supabase-js', () => ({
  createClient: vi.fn(() => ({ rpc })),
}))

async function loadSupabaseModule() {
  vi.stubEnv('VITE_SUPABASE_URL', 'https://example.supabase.co')
  vi.stubEnv('VITE_SUPABASE_PUBLISHABLE_KEY', 'public-anon-key')

  vi.resetModules()

  return await import('../supabase')
}

describe('ensureProfile', () => {
  it('calls the ensure_profile RPC and returns the profile id', async () => {
    rpc.mockResolvedValueOnce({ data: '11111111-1111-1111-1111-111111111111', error: null })

    const { ensureProfile } = await loadSupabaseModule()
    const profileId = await ensureProfile()

    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc).toHaveBeenCalledWith('ensure_profile')
    expect(profileId).toBe('11111111-1111-1111-1111-111111111111')
  })

  it('propagates database errors instead of silently ignoring them', async () => {
    rpc.mockResolvedValueOnce({ data: null, error: new Error('permission denied for function ensure_profile') })

    const { ensureProfile } = await loadSupabaseModule()

    await expect(ensureProfile()).rejects.toThrow('permission denied for function ensure_profile')
  })
})
