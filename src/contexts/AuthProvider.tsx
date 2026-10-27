import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'

import { AuthContext, type AuthContextValue } from './AuthContext'
import {
  getCurrentSession,
  onAuthStateChange,
  signInWithEmail,
  signInWithGoogle,
  signOut,
  signUpWithEmail,
} from '../lib/supabase'

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthContextValue['user']>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let isMounted = true

    const initializeSession = async () => {
      try {
        const session = await getCurrentSession()
        if (!isMounted) return
        setUser(session?.user ?? null)
      } catch (err) {
        if (!isMounted) return
        setError(err instanceof Error ? err.message : 'Erro desconhecido')
      } finally {
        if (isMounted) setIsLoading(false)
      }
    }

    initializeSession()

    const subscription = onAuthStateChange((_event, session) => {
      if (!isMounted) return
      setUser(session?.user ?? null)
      setIsLoading(false)
    })

    return () => {
      isMounted = false
      subscription.unsubscribe()
    }
  }, [])

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
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Falha ao entrar.')
      throw err
    } finally {
      setIsLoading(false)
    }
  }, [])

  const handleSignUpWithEmail = useCallback(async (email: string, password: string, fullName: string) => {
    setError(null)
    setIsLoading(true)
    try {
      const result = await signUpWithEmail(email, password, fullName)
      setUser(result.user ?? null)
      return result
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Falha ao criar conta.')
      throw err
    } finally {
      setIsLoading(false)
    }
  }, [])

  const handleSignOut = useCallback(async () => {
    setError(null)
    setIsLoading(true)
    try {
      await signOut()
      setUser(null)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Falha ao sair.')
      throw err
    } finally {
      setIsLoading(false)
    }
  }, [])

  const clearError = useCallback(() => setError(null), [])

  const value = useMemo(
    () => ({
      user,
      isLoading,
      isAuthenticated: !!user,
      signInWithGoogle: handleSignInWithGoogle,
      signInWithEmail: handleSignInWithEmail,
      signUpWithEmail: handleSignUpWithEmail,
      signOut: handleSignOut,
      error,
      clearError,
    }),
    [
      user,
      isLoading,
      handleSignInWithGoogle,
      handleSignInWithEmail,
      handleSignUpWithEmail,
      handleSignOut,
      error,
      clearError,
    ],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
