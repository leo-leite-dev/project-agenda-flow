import { createContext } from 'react'
import type { AuthResponse, User } from '@supabase/supabase-js'

export interface AuthContextValue {
  user: User | null
  isLoading: boolean
  isAuthenticated: boolean
  signInWithGoogle: () => Promise<void>
  signInWithEmail: (email: string, password: string) => Promise<void>
  signUpWithEmail: (email: string, password: string, fullName: string) => Promise<AuthResponse['data']>
  signOut: () => Promise<void>
  error: string | null
  clearError: () => void
}

export const AuthContext = createContext<AuthContextValue | null>(null)
