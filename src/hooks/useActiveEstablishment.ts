import { useMemo } from 'react'

import { useAuth } from './useAuth'
import { isEstablishmentAuthorized } from '../lib/establishments'
import type { UserEstablishment } from '../contexts/AuthContext'

/**
 * Estabelecimento ativo da sessão.
 *
 * O estabelecimento escolhido só é usado quando continua na lista autorizada
 * do usuário autenticado; caso contrário, a aplicação volta ao primeiro
 * vínculo válido. Assim, uma escolha obsoleta (por exemplo, de outra conta
 * no mesmo navegador) nunca abre um estabelecimento não autorizado.
 */
export function useActiveEstablishment(): UserEstablishment | null {
  const { establishments, currentEstablishment } = useAuth()

  return useMemo(() => {
    if (
      currentEstablishment &&
      isEstablishmentAuthorized(establishments, currentEstablishment.id)
    ) {
      return establishments.find((item) => item.id === currentEstablishment.id) ?? null
    }

    return establishments[0] ?? null
  }, [currentEstablishment, establishments])
}
