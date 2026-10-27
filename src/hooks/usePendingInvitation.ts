import { useCallback, useEffect, useState } from 'react'

import { useAuth } from '../hooks/useAuth'
import {
  PENDING_INVITATION_CHANGED_EVENT,
  readPendingInvitationPath,
} from '../lib/onboarding'
import { getMyPendingInvitations, type PendingInvitation } from '../lib/team'

interface PendingInvitationState {
  /** Convites pendentes do usuário autenticado (dados reais do banco). */
  invitations: PendingInvitation[]
  hasPendingInvitation: boolean
  /** Caminho do convite em andamento, quando o navegador o preservou. */
  pendingInvitationPath: string | null
  isLoading: boolean
}

/**
 * Descobre se a identidade autenticada possui convite pendente e recupera o
 * caminho do convite em andamento (preservado no sessionStorage durante o
 * cadastro/login). O caminho é apenas um endereço de navegação — a
 * autorização do aceite é validada pelo banco.
 */
export function usePendingInvitation(): PendingInvitationState {
  const { user, isAuthenticated, isLoadingEstablishments, establishments } = useAuth()

  const [invitations, setInvitations] = useState<PendingInvitation[]>([])
  const [pendingInvitationPath, setPendingInvitationPath] = useState<string | null>(() =>
    readPendingInvitationPath(),
  )
  const [isLoading, setIsLoading] = useState(false)

  // A consulta de convites pendentes só é necessária quando o usuário ainda
  // não tem vínculo — é o único cenário em que a decisão de onboarding muda.
  const shouldQuery =
    isAuthenticated && Boolean(user) && !isLoadingEstablishments && establishments.length === 0

  const refreshPath = useCallback(() => {
    setPendingInvitationPath(readPendingInvitationPath())
  }, [])

  useEffect(() => {
    window.addEventListener(PENDING_INVITATION_CHANGED_EVENT, refreshPath)
    return () => window.removeEventListener(PENDING_INVITATION_CHANGED_EVENT, refreshPath)
  }, [refreshPath])

  useEffect(() => {
    if (!shouldQuery) {
      return
    }

    let isMounted = true
    // eslint-disable-next-line react-hooks/exhaustive-deps -- indicador de carga da consulta assíncrona
    setIsLoading(true)

    void getMyPendingInvitations()
      .then((data) => {
        if (isMounted) setInvitations(data)
      })
      .catch(() => {
        if (isMounted) setInvitations([])
      })
      .finally(() => {
        if (isMounted) setIsLoading(false)
      })

    return () => {
      isMounted = false
    }
  }, [shouldQuery, user])

  const effectiveInvitations = shouldQuery ? invitations : []

  return {
    invitations: effectiveInvitations,
    hasPendingInvitation: effectiveInvitations.length > 0,
    pendingInvitationPath,
    isLoading: shouldQuery ? isLoading : false,
  }
}
