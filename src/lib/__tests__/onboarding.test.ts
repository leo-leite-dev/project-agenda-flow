import { describe, expect, it } from 'vitest'

import {
  isInvitationPath,
  readPendingInvitationPath,
  resolveOnboardingDecision,
  storePendingInvitationPath,
} from '../onboarding'

describe('resolveOnboardingDecision', () => {
  const base = {
    isAuthenticated: true,
    isLoading: false,
    isLoadingEstablishments: false,
    isLoadingInvitations: false,
    establishmentCount: 0,
    hasPendingInvitation: false,
    pendingInvitationPath: null,
  }

  it('aguarda o carregamento antes de decidir (lista vazia não é ausência de vínculos)', () => {
    expect(resolveOnboardingDecision({ ...base, isLoading: true })).toEqual({ kind: 'loading' })
    expect(resolveOnboardingDecision({ ...base, isLoadingEstablishments: true })).toEqual({
      kind: 'loading',
    })
    expect(resolveOnboardingDecision({ ...base, isLoadingInvitations: true })).toEqual({
      kind: 'loading',
    })
  })

  it('sem vínculo e sem convite: pode criar o próprio estabelecimento', () => {
    expect(resolveOnboardingDecision(base)).toEqual({ kind: 'welcome' })
  })

  it('com convite pendente: prioriza o aceite e NUNCA exige criar estabelecimento', () => {
    const decision = resolveOnboardingDecision({
      ...base,
      hasPendingInvitation: true,
      pendingInvitationPath: '/convite/abc',
    })

    expect(decision).toEqual({ kind: 'invitation', path: '/convite/abc' })
    expect(decision.kind).not.toBe('welcome')
  })

  it('com convite pendente e sem link conhecido: orienta a buscar o link', () => {
    expect(resolveOnboardingDecision({ ...base, hasPendingInvitation: true })).toEqual({
      kind: 'pending-invitation',
    })
  })

  it('com um vínculo: entra direto no estabelecimento', () => {
    expect(resolveOnboardingDecision({ ...base, establishmentCount: 1 })).toEqual({
      kind: 'dashboard',
    })
  })

  it('com vários vínculos: permite selecionar o estabelecimento', () => {
    expect(resolveOnboardingDecision({ ...base, establishmentCount: 3 })).toEqual({
      kind: 'select-establishment',
    })
  })

  it('com vários vínculos e um estabelecimento já escolhido: entra no dashboard', () => {
    expect(
      resolveOnboardingDecision({
        ...base,
        establishmentCount: 3,
        hasActiveEstablishment: true,
      }),
    ).toEqual({ kind: 'dashboard' })
  })

  it('com um vínculo escolhido que não está na lista: volta a exigir a escolha', () => {
    expect(
      resolveOnboardingDecision({
        ...base,
        establishmentCount: 0,
        hasActiveEstablishment: true,
      }),
    ).toEqual({ kind: 'welcome' })
  })

  it('não autenticado: leva ao login', () => {
    expect(resolveOnboardingDecision({ ...base, isAuthenticated: false })).toEqual({
      kind: 'login',
    })
  })

  it('não entra em loop: um convite com establishments zerados não redireciona para /welcome', () => {
    const decision = resolveOnboardingDecision({
      ...base,
      hasPendingInvitation: true,
      pendingInvitationPath: '/convite/abc',
    })

    expect(decision.kind === 'welcome').toBe(false)
  })
})

describe('contexto do convite', () => {
  it('reconhece apenas caminhos internos de convite', () => {
    expect(isInvitationPath('/convite/abc')).toBe(true)
    expect(isInvitationPath('/dashboard')).toBe(false)
    expect(isInvitationPath('//evil.example.com/convite')).toBe(false)
    expect(isInvitationPath(null)).toBe(false)
  })

  it('preserva o convite entre o login e a atualização da página', () => {
    storePendingInvitationPath('/convite/abc')
    expect(readPendingInvitationPath()).toBe('/convite/abc')

    storePendingInvitationPath(null)
    expect(readPendingInvitationPath()).toBeNull()
  })

  it('ignora caminhos externos ao guardar o contexto', () => {
    storePendingInvitationPath('https://evil.example.com/convite/abc')
    expect(readPendingInvitationPath()).toBeNull()
  })
})
