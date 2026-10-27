export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string
          full_name: string
          phone: string | null
          avatar_url: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          full_name?: string
          phone?: string | null
          avatar_url?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          full_name?: string
          phone?: string | null
          avatar_url?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'profiles_id_fkey'
            columns: ['id']
            referencedRelation: 'users'
            referencedColumns: ['id']
          },
        ]
      }
      establishments: {
        Row: {
          id: string
          owner_id: string
          name: string
          slug: string
          document: string | null
          phone: string | null
          email: string | null
          address: Json | null
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          owner_id: string
          name: string
          slug: string
          document?: string | null
          phone?: string | null
          email?: string | null
          address?: Json | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          owner_id?: string
          name?: string
          slug?: string
          document?: string | null
          phone?: string | null
          email?: string | null
          address?: Json | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'establishments_owner_id_fkey'
            columns: ['owner_id']
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
      establishment_members: {
        Row: {
          id: string
          establishment_id: string
          user_id: string
          role: 'owner' | 'manager' | 'professional' | 'receptionist'
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          establishment_id: string
          user_id: string
          role?: 'owner' | 'manager' | 'professional' | 'receptionist'
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          establishment_id?: string
          user_id?: string
          role?: 'owner' | 'manager' | 'professional' | 'receptionist'
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'establishment_members_establishment_id_fkey'
            columns: ['establishment_id']
            referencedRelation: 'establishments'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'establishment_members_user_id_fkey'
            columns: ['user_id']
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
      member_permissions: {
        Row: {
          id: string
          member_id: string
          permission_key: string
          granted_by: string | null
          created_at: string
        }
        Insert: {
          id?: string
          member_id: string
          permission_key: string
          granted_by?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          member_id?: string
          permission_key?: string
          granted_by?: string | null
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'member_permissions_member_id_fkey'
            columns: ['member_id']
            referencedRelation: 'establishment_members'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'member_permissions_granted_by_fkey'
            columns: ['granted_by']
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
      establishment_invitations: {
        Row: {
          id: string
          establishment_id: string
          email: string | null
          phone: string | null
          token_hash: string
          role: 'owner' | 'manager' | 'professional' | 'receptionist'
          permissions: string[]
          invited_by: string
          expires_at: string
          accepted_at: string | null
          cancelled_at: string | null
          created_at: string
        }
        Insert: {
          id?: string
          establishment_id: string
          email?: string | null
          phone?: string | null
          token_hash: string
          role?: 'owner' | 'manager' | 'professional' | 'receptionist'
          permissions?: string[]
          invited_by: string
          expires_at: string
          accepted_at?: string | null
          cancelled_at?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          establishment_id?: string
          email?: string | null
          phone?: string | null
          token_hash?: string
          role?: 'owner' | 'manager' | 'professional' | 'receptionist'
          permissions?: string[]
          invited_by?: string
          expires_at?: string
          accepted_at?: string | null
          cancelled_at?: string | null
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'establishment_invitations_establishment_id_fkey'
            columns: ['establishment_id']
            referencedRelation: 'establishments'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'establishment_invitations_invited_by_fkey'
            columns: ['invited_by']
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
    }
    Views: Record<string, never>
    Functions: {
      create_establishment: {
        Args: {
          p_name: string
          p_slug: string
          p_document?: string
          p_phone?: string
          p_email?: string
          p_address?: Json
        }
        Returns: string
      }
      create_establishment_invitation: {
        Args: {
          p_establishment_id: string
          p_email?: string
          p_phone?: string
          p_role?: string
          p_permissions?: string[]
          p_expires_in?: string
        }
        Returns: string
      }
      accept_establishment_invitation: {
        Args: {
          p_token: string
        }
        Returns: string
      }
      cancel_establishment_invitation: {
        Args: {
          p_invitation_id: string
        }
        Returns: void
      }
      get_user_establishment_role: {
        Args: {
          p_establishment_id: string
        }
        Returns: string
      }
      is_establishment_member: {
        Args: {
          p_establishment_id: string
        }
        Returns: boolean
      }
      is_establishment_owner: {
        Args: {
          p_establishment_id: string
        }
        Returns: boolean
      }
      is_establishment_owner_or_manager: {
        Args: {
          p_establishment_id: string
        }
        Returns: boolean
      }
      normalize_phone: {
        Args: {
          p_phone: string
        }
        Returns: string
      }
      has_permission: {
        Args: {
          p_establishment_id: string
          p_permission_key: string
        }
        Returns: boolean
      }
    }
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
