import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import type { AuthResponse } from '@supabase/supabase-js'

import { AuthContext, type AuthContextValue, type UserEstablishment } from '../../contexts/AuthContext'
import { DashboardPage } from '../DashboardPage'
import { DashboardModulePage } from '../DashboardModulePage'
import type { EstablishmentProfessional } from '../../lib/professionals'

function professionalFixture(overrides: Partial<EstablishmentProfessional> = {}): EstablishmentProfessional {
  return {
    id: 'pro-1',
    member_id: 'mem-2',
    user_id: 'user-2',
    role: 'professional',
    is_active: true,
    accepts_appointments: true,
    created_at: '2026-02-01T10:00:00Z',
    full_name: 'Carlos Silva',
    avatar_url: null,
    services: [],
    ...overrides,
  }
}

const servicesMock = vi.hoisted(() => ({
  listServices: vi.fn(),
}))

const professionalsMock = vi.hoisted(() => ({
  listEstablishmentProfessionals: vi.fn(),
}))

vi.mock('../../lib/services', () => ({
  listServices: servicesMock.listServices,
}))

vi.mock('../../lib/professionals', () => ({
  listEstablishmentProfessionals: professionalsMock.listEstablishmentProfessionals,
}))

vi.mock('../../lib/supabase', () => ({
  supabase: {},
}))

function establishmentFixture(overrides: Partial<UserEstablishment> = {}): UserEstablishment {
  return {
    id: 'est-1',
    owner_id: 'user-1',
    name: 'Barbearia Alpha',
    slug: 'barbearia-alpha',
    type: 'barbershop',
    document: null,
    phone: '+5511999990000',
    email: 'contato@alpha.test',
    address: { city: 'São Paulo', state: 'SP', address: 'Rua das Tesouras, 10' },
    is_active: true,
    created_at: '2026-01-15T10:00:00Z',
    updated_at: '2026-01-15T10:00:00Z',
    role: 'owner',
    ...overrides,
  }
}

function baseValue(overrides: Partial<AuthContextValue> = {}): AuthContextValue {
  return {
    user: { id: 'user-1', email: 'owner@alpha.test' } as AuthContextValue['user'],
    isLoading: false,
    isAuthenticated: true,
    establishments: [establishmentFixture()],
    currentEstablishment: establishmentFixture(),
    isLoadingEstablishments: false,
    signInWithGoogle: async () => {},
    signInWithEmail: async () => {},
    signUpWithEmail: async () => ({}) as AuthResponse['data'],
    signOut: vi.fn(async () => {}),
    refreshEstablishments: async () => {},
    selectEstablishment: () => {},
    createEstablishment: async () => 'id',
    error: null,
    clearError: () => {},
    ...overrides,
  }
}

function renderDashboard(value: AuthContextValue) {
  return render(
    <MemoryRouter initialEntries={['/dashboard']}>
      <AuthContext.Provider value={value}>
        <Routes>
          <Route path="/dashboard" element={<DashboardPage />} />
          <Route path="/dashboard/agenda" element={<DashboardModulePage />} />
          <Route path="/dashboard/servicos" element={<DashboardModulePage />} />
          <Route path="/dashboard/equipe" element={<DashboardModulePage />} />
          <Route path="/dashboard/configuracoes" element={<DashboardModulePage />} />
          <Route path="/welcome" element={<div>WELCOME</div>} />
          <Route path="/select-establishment" element={<div>SELECT</div>} />
          <Route path="/login" element={<div>LOGIN</div>} />
        </Routes>
      </AuthContext.Provider>
    </MemoryRouter>,
  )
}

describe('DashboardPage (visão geral)', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    servicesMock.listServices.mockResolvedValue([])
    professionalsMock.listEstablishmentProfessionals.mockResolvedValue([])
  })

  it('mostra o nome real do estabelecimento e os dados do usuário', async () => {
    renderDashboard(baseValue())

    expect(await screen.findByRole('heading', { name: /Barbearia Alpha/i })).toBeInTheDocument()
    expect(screen.getAllByText(/owner@alpha.test/i).length).toBeGreaterThan(0)
    expect(screen.getAllByText(/Barbearia/i).length).toBeGreaterThan(0)
  })

  it('exibe o checklist de configuração com as quatro etapas pendentes', async () => {
    renderDashboard(baseValue())

    expect(screen.getByText(/Preparação para os primeiros agendamentos/i)).toBeInTheDocument()
    expect(screen.getByText(/Configurar horários de funcionamento/i)).toBeInTheDocument()
    expect(screen.getByText(/Cadastrar os serviços oferecidos/i)).toBeInTheDocument()
    expect(screen.getByText(/Adicionar profissionais à equipe/i)).toBeInTheDocument()
    expect(screen.getByText(/Preparar a agenda de atendimentos/i)).toBeInTheDocument()
    expect(screen.getByText('0 de 4 concluídas')).toBeInTheDocument()
    await screen.findByText(/Cadastrar serviços/i)
    expect(screen.getByText(/Habilitar profissionais/i)).toBeInTheDocument()
    expect(await screen.findAllByText('Em breve').then((items) => items.length)).toBeGreaterThanOrEqual(2)
  })

  it('exibe a quantidade real de profissionais habilitados e sem serviços', async () => {
    professionalsMock.listEstablishmentProfessionals.mockResolvedValue([
      professionalFixture({
        id: 'pro-1',
        full_name: 'Carlos Silva',
        services: [{ id: 'svc-1', name: 'Corte', category: 'cabelo', is_active: true }],
      }),
      professionalFixture({
        id: 'pro-2',
        full_name: 'Mariana',
        member_id: 'mem-3',
        user_id: 'user-4',
        services: [],
      }),
      professionalFixture({
        id: 'pro-3',
        full_name: 'Bruno',
        member_id: 'mem-4',
        user_id: 'user-5',
        services: [],
      }),
    ])

    renderDashboard(baseValue())

    expect(await screen.findByText('3 habilitado(s) para atendimentos • 2 sem serviços')).toBeInTheDocument()
    expect(screen.getByText('1 de 4 concluídas')).toBeInTheDocument()
    expect(screen.getByText(/Equipe • Concluída/i)).toBeInTheDocument()
  })

  it('exibe estado de carregamento honesto quando os profissionais falham', async () => {
    professionalsMock.listEstablishmentProfessionals.mockRejectedValue(new Error('offline'))

    renderDashboard(baseValue())

    expect(await screen.findByText('Carregando...')).toBeInTheDocument()
    expect(screen.getByText('0 de 4 concluídas')).toBeInTheDocument()
  })

  it('marca a etapa de serviços como concluída quando há um serviço ativo', async () => {
    servicesMock.listServices.mockResolvedValue([
      { id: 'svc-1', establishment_id: 'est-1', name: 'Corte', description: null, category: 'cabelo', duration_minutes: 30, price_cents: 3500, is_active: true, created_at: '', updated_at: '' },
    ])

    renderDashboard(baseValue())

    expect(await screen.findByText('1 de 4 concluídas')).toBeInTheDocument()
    expect(screen.getByText(/Serviços • Concluída/i)).toBeInTheDocument()
  })

  it('apresenta estados vazios honestos nos indicadores futuros', async () => {
    renderDashboard(baseValue())

    expect(await screen.findByText(/Agendamentos de hoje/i)).toBeInTheDocument()
    expect(screen.getByText(/A agenda estará disponível em breve/i)).toBeInTheDocument()
    expect(screen.getByText(/Faturamento/i)).toBeInTheDocument()
    expect(screen.getByText(/O acompanhamento financeiro estará disponível em breve/i)).toBeInTheDocument()
  })

  it('navega para o módulo "Em breve" pelo checklist e pela sidebar', () => {
    renderDashboard(baseValue())

    fireEvent.click(screen.getByRole('link', { name: /Equipe • Habilitar profissionais/i }))
    expect(screen.getByRole('heading', { name: 'Equipe' })).toBeInTheDocument()
    expect(screen.getByText(/Este módulo faz parte das próximas etapas/i)).toBeInTheDocument()

    fireEvent.click(screen.getAllByRole('link', { name: /Agenda/i })[0])
    expect(screen.getByRole('heading', { name: 'Agenda' })).toBeInTheDocument()
  })

  it('redireciona para /welcome quando o usuário não tem estabelecimentos', () => {
    renderDashboard(baseValue({ establishments: [], currentEstablishment: null }))

    expect(screen.getByText('WELCOME')).toBeInTheDocument()
  })

  it('redireciona para a seleção quando há mais de um estabelecimento sem escolha', () => {
    renderDashboard(
      baseValue({
        establishments: [establishmentFixture(), establishmentFixture({ id: 'est-2', name: 'Salão Beta' })],
        currentEstablishment: null,
      }),
    )

    expect(screen.getByText('SELECT')).toBeInTheDocument()
  })

  it('redireciona módulo desconhecido para a visão geral', async () => {
    render(
      <MemoryRouter initialEntries={['/dashboard/modulo-inexistente']}>
        <AuthContext.Provider value={baseValue()}>
          <Routes>
            <Route path="/dashboard" element={<DashboardPage />} />
            <Route path="/dashboard/:module" element={<DashboardModulePage />} />
            <Route path="/login" element={<div>LOGIN</div>} />
          </Routes>
        </AuthContext.Provider>
      </MemoryRouter>,
    )

    expect(await screen.findByRole('heading', { name: /Barbearia Alpha/i })).toBeInTheDocument()
  })

  it('encerra a sessão pelo menu do perfil', async () => {
    const signOut = vi.fn(async () => {})
    renderDashboard(baseValue({ signOut }))

    fireEvent.click(screen.getByRole('button', { name: /owner@alpha.test/i }))

    const signOutButton = await screen.findByRole('menuitem', { name: /Sair da conta/i })
    fireEvent.click(signOutButton)

    expect(signOut).toHaveBeenCalledTimes(1)
    await screen.findByText('LOGIN')
  })
})
