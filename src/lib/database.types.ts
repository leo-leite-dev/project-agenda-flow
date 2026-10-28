export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface EstablishmentAddress {
  city?: string | null
  state?: string | null
  address?: string | null
}

export type ServiceCategory = 'cabelo' | 'barba' | 'estetica' | 'unhas' | 'outros'

export interface Database {
  public: {
    Tables: {
      establishment_services: {
        Row: {
          id: string
          establishment_id: string
          name: string
          description: string | null
          category: ServiceCategory
          duration_minutes: number
          price_cents: number
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          establishment_id: string
          name: string
          description?: string | null
          category?: ServiceCategory
          duration_minutes: number
          price_cents: number
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          establishment_id?: string
          name?: string
          description?: string | null
          category?: ServiceCategory
          duration_minutes?: number
          price_cents?: number
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'establishment_services_establishment_id_fkey'
            columns: ['establishment_id']
            referencedRelation: 'establishments'
            referencedColumns: ['id']
          },
        ]
      }
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
          type: 'barbershop' | 'salon'
          document: string | null
          phone: string | null
          email: string | null
          address: EstablishmentAddress | null
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          owner_id: string
          name: string
          slug: string
          type?: 'barbershop' | 'salon'
          document?: string | null
          phone?: string | null
          email?: string | null
          address?: EstablishmentAddress | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          owner_id?: string
          name?: string
          slug?: string
          type?: 'barbershop' | 'salon'
          document?: string | null
          phone?: string | null
          email?: string | null
          address?: EstablishmentAddress | null
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
      establishment_professionals: {
        Row: {
          id: string
          establishment_id: string
          member_id: string
          accepts_appointments: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          establishment_id: string
          member_id: string
          accepts_appointments?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          establishment_id?: string
          member_id?: string
          accepts_appointments?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'establishment_professionals_establishment_id_fkey'
            columns: ['establishment_id']
            referencedRelation: 'establishments'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'establishment_professionals_member_establishment_fkey'
            columns: ['member_id', 'establishment_id']
            referencedRelation: 'establishment_members'
            referencedColumns: ['id', 'establishment_id']
          },
        ]
      }
      establishment_professional_services: {
        Row: {
          id: string
          establishment_id: string
          professional_id: string
          service_id: string
          created_at: string
        }
        Insert: {
          id?: string
          establishment_id: string
          professional_id: string
          service_id: string
          created_at?: string
        }
        Update: {
          id?: string
          establishment_id?: string
          professional_id?: string
          service_id?: string
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'establishment_professional_services_establishment_id_fkey'
            columns: ['establishment_id']
            referencedRelation: 'establishments'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'establishment_professional_services_professional_establishment_fkey'
            columns: ['professional_id', 'establishment_id']
            referencedRelation: 'establishment_professionals'
            referencedColumns: ['id', 'establishment_id']
          },
          {
            foreignKeyName: 'establishment_professional_services_service_establishment_fkey'
            columns: ['service_id', 'establishment_id']
            referencedRelation: 'establishment_services'
            referencedColumns: ['id', 'establishment_id']
          },
        ]
      }
      establishment_schedules: {
        Row: {
          id: string
          establishment_id: string
          member_id: string
          weekday: number
          is_day_off: boolean
          start_time: string | null
          end_time: string | null
          break_start: string | null
          break_end: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          establishment_id: string
          member_id: string
          weekday: number
          is_day_off?: boolean
          start_time?: string | null
          end_time?: string | null
          break_start?: string | null
          break_end?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          establishment_id?: string
          member_id?: string
          weekday?: number
          is_day_off?: boolean
          start_time?: string | null
          end_time?: string | null
          break_start?: string | null
          break_end?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'establishment_schedules_establishment_id_fkey'
            columns: ['establishment_id']
            referencedRelation: 'establishments'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'establishment_schedules_member_establishment_fkey'
            columns: ['member_id', 'establishment_id']
            referencedRelation: 'establishment_members'
            referencedColumns: ['id', 'establishment_id']
          },
        ]
      }
      attendance_records: {
        Row: {
          id: string
          establishment_id: string
          member_id: string
          work_date: string
          check_in_at: string | null
          check_out_at: string | null
          check_in_source: string | null
          check_out_source: string | null
          corrected_by: string | null
          corrected_at: string | null
          correction_reason: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          establishment_id: string
          member_id: string
          work_date: string
          check_in_at?: string | null
          check_out_at?: string | null
          check_in_source?: string | null
          check_out_source?: string | null
          corrected_by?: string | null
          corrected_at?: string | null
          correction_reason?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          establishment_id?: string
          member_id?: string
          work_date?: string
          check_in_at?: string | null
          check_out_at?: string | null
          check_in_source?: string | null
          check_out_source?: string | null
          corrected_by?: string | null
          corrected_at?: string | null
          correction_reason?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'attendance_records_establishment_id_fkey'
            columns: ['establishment_id']
            referencedRelation: 'establishments'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'attendance_records_member_establishment_fkey'
            columns: ['member_id', 'establishment_id']
            referencedRelation: 'establishment_members'
            referencedColumns: ['id', 'establishment_id']
          },
          {
            foreignKeyName: 'attendance_records_corrected_by_fkey'
            columns: ['corrected_by']
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
      attendance_exceptions: {
        Row: {
          id: string
          establishment_id: string
          member_id: string
          start_date: string
          end_date: string
          exception_type: 'absence' | 'justified_delay' | 'early_leave' | 'exceptional_day_off' | 'vacation' | 'schedule_adjustment'
          reason: string | null
          recorded_by: string
          created_at: string
        }
        Insert: {
          id?: string
          establishment_id: string
          member_id: string
          start_date: string
          end_date: string
          exception_type?: 'absence' | 'justified_delay' | 'early_leave' | 'exceptional_day_off' | 'vacation' | 'schedule_adjustment'
          reason?: string | null
          recorded_by: string
          created_at?: string
        }
        Update: {
          id?: string
          establishment_id?: string
          member_id?: string
          start_date?: string
          end_date?: string
          exception_type?: 'absence' | 'justified_delay' | 'early_leave' | 'exceptional_day_off' | 'vacation' | 'schedule_adjustment'
          reason?: string | null
          recorded_by?: string
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'attendance_exceptions_establishment_id_fkey'
            columns: ['establishment_id']
            referencedRelation: 'establishments'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'attendance_exceptions_member_establishment_fkey'
            columns: ['member_id', 'establishment_id']
            referencedRelation: 'establishment_members'
            referencedColumns: ['id', 'establishment_id']
          },
          {
            foreignKeyName: 'attendance_exceptions_recorded_by_fkey'
            columns: ['recorded_by']
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
      attendance_corrections: {
        Row: {
          id: string
          establishment_id: string
          attendance_id: string
          previous_check_in_at: string | null
          previous_check_out_at: string | null
          check_in_at: string | null
          check_out_at: string | null
          reason: string
          corrected_by: string
          created_at: string
        }
        Insert: {
          id?: string
          establishment_id: string
          attendance_id: string
          previous_check_in_at?: string | null
          previous_check_out_at?: string | null
          check_in_at?: string | null
          check_out_at?: string | null
          reason: string
          corrected_by: string
          created_at?: string
        }
        Update: {
          id?: string
          establishment_id?: string
          attendance_id?: string
          previous_check_in_at?: string | null
          previous_check_out_at?: string | null
          check_in_at?: string | null
          check_out_at?: string | null
          reason?: string
          corrected_by?: string
          created_at?: string
        }
        Relationships: [
          {
            foreignKeyName: 'attendance_corrections_establishment_id_fkey'
            columns: ['establishment_id']
            referencedRelation: 'establishments'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'attendance_corrections_attendance_id_fkey'
            columns: ['attendance_id']
            referencedRelation: 'attendance_records'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'attendance_corrections_corrected_by_fkey'
            columns: ['corrected_by']
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
      get_my_pending_invitations: {
        Args: Record<string, never>
        Returns: {
          establishment_id: string
          establishment_name: string
          role: string
          expires_at: string
        }[]
      }
      update_establishment_member_role: {
        Args: {
          p_member_id: string
          p_role: string
        }
        Returns: null
      }
      set_establishment_member_active: {
        Args: {
          p_member_id: string
          p_is_active: boolean
        }
        Returns: null
      }
      set_establishment_member_permissions: {
        Args: {
          p_member_id: string
          p_permission_keys: string[]
        }
        Returns: null
      }
      create_establishment_service: {
        Args: {
          p_establishment_id: string
          p_name: string
          p_description?: string
          p_category?: string
          p_duration_minutes: number
          p_price_cents: number
          p_is_active?: boolean
        }
        Returns: string
      }
      update_establishment_service: {
        Args: {
          p_service_id: string
          p_name: string
          p_description?: string
          p_category?: string
          p_duration_minutes?: number
          p_price_cents?: number
          p_is_active?: boolean
        }
        Returns: null
      }
      set_establishment_service_active: {
        Args: {
          p_service_id: string
          p_is_active: boolean
        }
        Returns: null
      }
      set_establishment_professional: {
        Args: {
          p_member_id: string
          p_accepts_appointments: boolean
        }
        Returns: null
      }
      add_establishment_professional_service: {
        Args: {
          p_professional_id: string
          p_service_id: string
        }
        Returns: null
      }
      remove_establishment_professional_service: {
        Args: {
          p_professional_id: string
          p_service_id: string
        }
        Returns: null
      }
      get_establishment_clock: {
        Args: {
          p_establishment_id: string
        }
        Returns: Json
      }
      set_establishment_schedule: {
        Args: {
          p_member_id: string
          p_schedules: Json
        }
        Returns: null
      }
      record_attendance_check_in: {
        Args: {
          p_establishment_id: string
        }
        Returns: {
          id: string
          establishment_id: string
          member_id: string
          work_date: string
          check_in_at: string | null
          check_out_at: string | null
          check_in_source: string | null
          check_out_source: string | null
          corrected_by: string | null
          corrected_at: string | null
          correction_reason: string | null
          created_at: string
          updated_at: string
        }
      }
      record_attendance_check_out: {
        Args: {
          p_establishment_id: string
        }
        Returns: {
          id: string
          establishment_id: string
          member_id: string
          work_date: string
          check_in_at: string | null
          check_out_at: string | null
          check_in_source: string | null
          check_out_source: string | null
          corrected_by: string | null
          corrected_at: string | null
          correction_reason: string | null
          created_at: string
          updated_at: string
        }
      }
      record_attendance_exception: {
        Args: {
          p_member_id: string
          p_exception_type: string
          p_start_date: string
          p_end_date: string
          p_reason?: string | null
        }
        Returns: {
          id: string
          establishment_id: string
          member_id: string
          start_date: string
          end_date: string
          exception_type: 'absence' | 'justified_delay' | 'early_leave' | 'exceptional_day_off' | 'vacation' | 'schedule_adjustment'
          reason: string | null
          recorded_by: string
          created_at: string
        }
      }
      correct_attendance_record: {
        Args: {
          p_attendance_id: string
          p_check_in?: string | null
          p_check_out?: string | null
          p_reason?: string | null
        }
        Returns: {
          id: string
          establishment_id: string
          member_id: string
          work_date: string
          check_in_at: string | null
          check_out_at: string | null
          check_in_source: string | null
          check_out_source: string | null
          corrected_by: string | null
          corrected_at: string | null
          correction_reason: string | null
          created_at: string
          updated_at: string
        }
      }
      ensure_profile: {
        Args: Record<string, never>
        Returns: string
      }
      create_establishment: {
        Args: {
          p_name: string
          p_slug: string
          p_type?: string
          p_document?: string
          p_phone?: string
          p_email?: string
          p_address?: EstablishmentAddress
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
