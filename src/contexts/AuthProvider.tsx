import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'

import { AuthContext, type AuthContextValue, type UserEstablishment } from './AuthContext'
import {
  createEstablishment as createEstablishmentRpc,
  ensureProfile as ensureProfileRpc,
  getCurrentSession,
  getUserEstablishments,
  onAuthStateChange,
  signInWithEmail,
  signInWithGoogle,
  signOut,
  signUpWithEmail,
} from '../lib/supabase'
import type { Establishment } from '../lib/supabase'

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthContextValue['user']>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [establishments, setEstablishments] = useState<UserEstablishment[]>([])
  const [currentEstablishment, setCurrentEstablishment] = useState<UserEstablishment | null>(null)
  const [isLoadingEstablishments, setIsLoadingEstablishments] = useState(false)
  const profileEnsuredRef = useRef(false)

  const loadEstablishments = useCallback(async () => {
    setIsLoadingEstablishments(true)
    try {
      const data = await getUserEstablishments()
      setEstablishments(data)

      if (data.length === 1 && !currentEstablishment) {
        setCurrentEstablishment(data[0])
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Falha ao carregar estabelecimentos.')
    } finally {
      setIsLoadingEstablishments(false)
    }
  }, [currentEstablishment])

  /**
   * Guarantees that the authenticated user has a profile in `public.profiles`.
   * The database normally creates it (trigger on `auth.users`); this is an
   * idempotent safety net for accounts created before the trigger existed.
   */
  const ensureProfile = useCallback(async () => {
    if (profileEnsuredRef.current) return

    try {
      await ensureProfileRpc()
      profileEnsuredRef.current = true
    } catch {
      // Not fatal: the database repairs the profile when an establishment is created.
    }
  }, [])

  const loadUserData = useCallback(async () => {
    await ensureProfile()
    await loadEstablishments()
  }, [ensureProfile, loadEstablishments])

  useEffect(() => {
    let isMounted = true

    // Subscribe BEFORE reading the session so we never miss an INITIAL_SESSION
    // or SIGNED_IN event. The implicit OAuth flow resolves asynchronously while
    // the client initializes (detectSessionInUrl), so the auth state listener is
    // our authoritative source for the post-redirect session.
    const subscription = onAuthStateChange((event, session) => {
      if (!isMounted) return

      if (event === 'SIGNED_OUT' || event === 'USER_DELETED') {
        setUser(null)
        setEstablishments([])
        setCurrentEstablishment(null)
        setIsLoading(false)
        profileEnsuredRef.current = false
        return
      }

      // INITIAL_SESSION, SIGNED_IN, TOKEN_REFRESHED, etc.
      setUser(session?.user ?? null)
      setIsLoading(false)

      if (session?.user) {
        void loadUserData()
      } else {
        setEstablishments([])
        setCurrentEstablishment(null)
      }
    })

    const initializeSession = async () => {
      try {
        const session = await getCurrentSession()
        if (!isMounted) return
        setUser(session?.user ?? null)
        if (session?.user) {
          await loadUserData()
        }
      } catch {
        // Do not surface internals; the auth listener / UI will handle state.
        if (!isMounted) return
        setError('Falha ao iniciar a sessão. Tente novamente.')
      } finally {
        if (isMounted) setIsLoading(false)
      }
    }

    void initializeSession()

    return () => {
      isMounted = false
      subscription.unsubscribe()
    }
  }, [loadUserData])

  const handleSignInWithGoogle = useCallback(async () => {
    setError(null)
    setIsLoading(true)
    try {
      await signInWithGoogle()
    } catch (err) {
      setIsLoading(false)
      setError(err instanceof Error ? err.message : 'Falha ao iniciar login com Google.')
      throw err
    }
  }, [])

  const handleSignInWithEmail = useCallback(async (email: string, password: string) => {
    setError(null)
    setIsLoading(true)
    try {
      const { user: signedInUser } = await signInWithEmail(email, password)
      setUser(signedInUser)
      if (signedInUser) {
        await loadUserData()
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Falha ao entrar.')
      throw err
    } finally {
      setIsLoading(false)
    }
  }, [loadUserData])

  const handleSignUpWithEmail = useCallback(async (email: string, password: string, fullName: string) => {
    setError(null)
    setIsLoading(true)
    try {
      const result = await signUpWithEmail(email, password, fullName)
      setUser(result.user ?? null)
      if (result.user) {
        await loadUserData()
      }
      return result
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Falha ao criar conta.')
      throw err
    } finally {
      setIsLoading(false)
    }
  }, [loadUserData])

  const handleSignOut = useCallback(async () => {
    setError(null)
    setIsLoading(true)
    try {
      await signOut()
      setUser(null)
      setEstablishments([])
      setCurrentEstablishment(null)
      profileEnsuredRef.current = false
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Falha ao sair.')
      throw err
    } finally {
      setIsLoading(false)
    }
  }, [])

  const handleCreateEstablishment = useCallback(
    async (input: {
      name: string
      type: Establishment['type']
      slug: string
      phone?: string | null
      email?: string | null
      city?: string | null
      state?: string | null
      address?: string | null
    }) => {
      setError(null)
      try {
        const id = await createEstablishmentRpc(input)
        await loadEstablishments()
        return id
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Falha ao criar estabelecimento.')
        throw err
      }
    },
    [loadEstablishments],
  )

  const handleSelectEstablishment = useCallback((establishment: UserEstablishment | null) => {
    setCurrentEstablishment(establishment)
  }, [])

  const handleRefreshEstablishments = useCallback(async () => {
    setError(null)
    await loadEstablishments()
  }, [loadEstablishments])

  const clearError = useCallback(() => setError(null), [])

  const value = useMemo(
    () => ({
      user,
      isLoading,
      isAuthenticated: !!user,
      establishments,
      currentEstablishment,
      isLoadingEstablishments,
      signInWithGoogle: handleSignInWithGoogle,
      signInWithEmail: handleSignInWithEmail,
      signUpWithEmail: handleSignUpWithEmail,
      signOut: handleSignOut,
      refreshEstablishments: handleRefreshEstablishments,
      selectEstablishment: handleSelectEstablishment,
      createEstablishment: handleCreateEstablishment,
      error,
      clearError,
    }),
    [
      user,
      isLoading,
      establishments,
      currentEstablishment,
      isLoadingEstablishments,
      handleSignInWithGoogle,
      handleSignInWithEmail,
      handleSignUpWithEmail,
      handleSignOut,
      handleRefreshEstablishments,
      handleSelectEstablishment,
      handleCreateEstablishment,
      error,
      clearError,
    ],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
