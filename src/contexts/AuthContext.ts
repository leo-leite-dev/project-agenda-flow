import { createContext } from 'react'
import type { AuthResponse, User } from '@supabase/supabase-js'

import type { Establishment } from '../lib/supabase'

export interface UserEstablishment extends Establishment {
  role: string
}

export interface AuthContextValue {
  user: User | null
  isLoading: boolean
  isAuthenticated: boolean
  establishments: UserEstablishment[]
  currentEstablishment: UserEstablishment | null
  isLoadingEstablishments: boolean
  signInWithGoogle: () => Promise<void>
  signInWithEmail: (email: string, password: string) => Promise<void>
  signUpWithEmail: (email: string, password: string, fullName: string) => Promise<AuthResponse['data']>
  signOut: () => Promise<void>
  refreshEstablishments: () => Promise<void>
  selectEstablishment: (establishment: UserEstablishment | null) => void
  createEstablishment: (input: {
    name: string
    type: Establishment['type']
    slug: string
    phone?: string | null
    email?: string | null
    city?: string | null
    state?: string | null
    address?: string | null
  }) => Promise<string>
  error: string | null
  clearError: () => void
}

export const AuthContext = createContext<AuthContextValue | null>(null)
