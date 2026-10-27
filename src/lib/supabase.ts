import { createClient } from '@supabase/supabase-js'

import type { Session } from '@supabase/supabase-js'
import type { Database } from './database.types'

export type Establishment = Database['public']['Tables']['establishments']['Row']
export type EstablishmentType = Database['public']['Tables']['establishments']['Row']['type']

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!supabaseUrl || !supabaseKey) {
  throw new Error(
    'Missing Supabase environment variables. ' +
      'Make sure VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY are set in your .env.local file.',
  )
}

export const supabase = createClient<Database>(supabaseUrl, supabaseKey, {
  auth: {
    // The Google OAuth return URL uses the implicit grant (#access_token=...),
    // so we keep the implicit flow and let the library process the URL hash.
    // We deliberately do NOT use PKCE (exchangeCodeForSession) here.
    flowType: 'implicit',
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
})

/**
 * Returns the currently authenticated user, or null if not signed in.
 */
export async function getCurrentUser() {
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser()

  if (error) {
    throw error
  }

  return user
}

/**
 * Returns the current session, or null if not signed in.
 */
export async function getCurrentSession() {
  const {
    data: { session },
    error,
  } = await supabase.auth.getSession()

  if (error) {
    throw error
  }

  return session
}

/**
 * Starts the OAuth sign-in flow with Google.
 * When `nextPath` is a safe internal path (e.g. an invitation link), it is
 * preserved through the OAuth round trip.
 */
export async function signInWithGoogle(nextPath?: string | null) {
  const callbackUrl = nextPath
    ? `${window.location.origin}/auth/callback?next=${encodeURIComponent(nextPath)}`
    : `${window.location.origin}/auth/callback`

  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: {
      redirectTo: callbackUrl,
      queryParams: {
        access_type: 'offline',
        prompt: 'select_account',
      },
    },
  })

  if (error) {
    throw error
  }

  return data
}

/**
 * Signs in with email and password.
 */
export async function signInWithEmail(email: string, password: string) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  })

  if (error) {
    throw error
  }

  return data
}

/**
 * Signs up with email and password.
 * The user may need to confirm their email depending on Supabase settings.
 */
export async function signUpWithEmail(email: string, password: string, fullName: string) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        full_name: fullName,
      },
    },
  })

  if (error) {
    throw error
  }

  return data
}

/**
 * Signs out the current user.
 */
export async function signOut() {
  const { error } = await supabase.auth.signOut()

  if (error) {
    throw error
  }
}

/**
 * Subscribes to authentication state changes.
 */
export function onAuthStateChange(callback: (event: string, session: Session | null) => void) {
  const { data } = supabase.auth.onAuthStateChange((event, session) => {
    callback(event, session)
  })

  return data.subscription
}

/**
 * Fetches all establishments the current user belongs to.
 */
export async function getUserEstablishments() {
  const { data, error } = await supabase
    .from('establishment_members')
    .select(
      `
      role,
      establishments:establishment_id (
        id,
        owner_id,
        name,
        slug,
        type,
        document,
        phone,
        email,
        address,
        is_active,
        created_at,
        updated_at
      )
    `,
    )
    .eq('is_active', true)
    .order('created_at', { ascending: false })

  if (error) {
    throw error
  }

  return (
    data
      ?.map((item) => {
        const establishment = Array.isArray(item.establishments)
          ? item.establishments[0]
          : item.establishments

        if (!establishment) return null

        return {
          ...establishment,
          role: item.role,
        }
      })
      .filter((item): item is NonNullable<typeof item> => item !== null) ?? []
  )
}

export interface CreateEstablishmentInput {
  name: string
  type: EstablishmentType
  slug: string
  phone?: string | null
  email?: string | null
  city?: string | null
  state?: string | null
  address?: string | null
}

/**
 * Ensures the authenticated user has a matching row in `public.profiles`.
 *
 * The database creates the profile automatically (trigger on `auth.users`) and
 * the `create_establishment` RPC self-heals the relationship, so this call is a
 * safety net: it is idempotent, never duplicates a profile and never grants
 * any extra privilege.
 */
export async function ensureProfile() {
  const { data, error } = await supabase.rpc('ensure_profile')

  if (error) {
    throw error
  }

  return data as string
}

/**
 * Creates a new establishment and binds the current user as owner.
 * The operation is atomic and enforced by the database function.
 */
export async function createEstablishment(input: CreateEstablishmentInput) {
  const { name, type, slug, phone, email, city, state, address } = input

  const addressPayload = city || state || address
    ? { city: city ?? null, state: state ?? null, address: address ?? null }
    : null

  const { data, error } = await supabase.rpc('create_establishment', {
    p_name: name,
    p_slug: slug,
    p_type: type,
    p_phone: phone ?? undefined,
    p_email: email ?? undefined,
    p_address: addressPayload ?? undefined,
  })

  if (error) {
    throw error
  }

  return data as string
}
