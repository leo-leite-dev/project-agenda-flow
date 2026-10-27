import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'

import { AuthContext, type AuthContextValue, type UserEstablishment } from '../../contexts/AuthContext'
import { ServicesPage } from '../ServicesPage'
import type { EstablishmentService } from '../../lib/services'

const servicesMock = vi.hoisted(() => ({
  listServices: vi.fn(),
  createService: vi.fn(),
  updateService: vi.fn(),
  setServiceActive: vi.fn(),
}))

vi.mock('../../lib/services', async (importOriginal) => ({
  ...(await importOriginal<object>()),
  listServices: servicesMock.listServices,
  createService: servicesMock.createService,
  updateService: servicesMock.updateService,
  setServiceActive: servicesMock.setServiceActive,
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
    phone: null,
    email: null,
    address: null,
    is_active: true,
    created_at: '2026-01-15T10:00:00Z',
    updated_at: '2026-01-15T10:00:00Z',
    role: 'owner',
    ...overrides,
  }
}

function serviceFixture(overrides: Partial<EstablishmentService> = {}): EstablishmentService {
  return {
    id: 'svc-1',
    establishment_id: 'est-1',
    name: 'Corte Masculino',
    description: null,
    category: 'cabelo',
    duration_minutes: 30,
    price_cents: 3500,
    is_active: true,
    created_at: '2026-01-20T10:00:00Z',
    updated_at: '2026-01-20T10:00:00Z',
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
    signUpWithEmail: async () => ({}) as never,
    signOut: async () => {},
    refreshEstablishments: async () => {},
    selectEstablishment: () => {},
    createEstablishment: async () => 'id',
    error: null,
    clearError: () => {},
    ...overrides,
  }
}

function renderServices(value: AuthContextValue) {
  return render(
    <MemoryRouter initialEntries={['/dashboard/servicos']}>
      <AuthContext.Provider value={value}>
        <Routes>
          <Route path="/dashboard/servicos" element={<ServicesPage />} />
          <Route path="/dashboard" element={<div>VISAO GERAL</div>} />
          <Route path="/login" element={<div>LOGIN</div>} />
        </Routes>
      </AuthContext.Provider>
    </MemoryRouter>,
  )
}

describe('ServicesPage', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    servicesMock.listServices.mockResolvedValue([])
  })

  it('exibe a lista com preço formatado, categoria, duração e status', async () => {
    servicesMock.listServices.mockResolvedValue([
      serviceFixture(),
      serviceFixture({
        id: 'svc-2',
        name: 'Barba',
        category: 'barba',
        duration_minutes: 20,
        price_cents: 2500,
        is_active: false,
      }),
    ])

    renderServices(baseValue())

    expect(await screen.findByText('Corte Masculino')).toBeInTheDocument()
    expect(screen.getByText(/R\$\s*35,00/)).toBeInTheDocument()
    expect(screen.getAllByText('Cabelo').length).toBeGreaterThan(0)
    expect(screen.getAllByText('30 min').length).toBeGreaterThan(0)
    expect(screen.getByText(/R\$\s*25,00/)).toBeInTheDocument()
    expect(screen.getAllByText('Ativo').length).toBeGreaterThan(0)
    expect(screen.getAllByText('Inativo').length).toBeGreaterThan(0)
  })

  it('mostra estado vazio quando não há serviços cadastrados', async () => {
    servicesMock.listServices.mockResolvedValue([])

    renderServices(baseValue())

    expect(await screen.findByText(/Nenhum serviço cadastrado ainda/i)).toBeInTheDocument()
  })

  it('mostra estado de erro com botão para tentar novamente', async () => {
    servicesMock.listServices.mockRejectedValue(new Error('falha'))

    renderServices(baseValue())

    expect(
      await screen.findByText(/Não foi possível carregar os serviços/i),
    ).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Tentar novamente/i })).toBeInTheDocument()
  })

  it('filtra por busca e status', async () => {
    servicesMock.listServices.mockResolvedValue([
      serviceFixture(),
      serviceFixture({ id: 'svc-2', name: 'Barba', category: 'barba', price_cents: 2500 }),
      serviceFixture({ id: 'svc-3', name: 'Corte Feminino', is_active: false }),
    ])

    renderServices(baseValue())

    await screen.findByText('Corte Masculino')
    const region = screen.getByRole('region', { name: 'Lista de serviços' })

    fireEvent.change(screen.getByLabelText('Buscar'), { target: { value: 'barba' } })

    expect(within(region).getAllByText('Barba').length).toBeGreaterThan(0)
    expect(within(region).queryByText('Corte Masculino')).not.toBeInTheDocument()
    expect(within(region).queryByText('Corte Feminino')).not.toBeInTheDocument()

    fireEvent.change(screen.getByLabelText('Buscar'), { target: { value: '' } })
    fireEvent.change(screen.getByLabelText('Status'), { target: { value: 'inativos' } })

    expect(within(region).getByText('Corte Feminino')).toBeInTheDocument()
    expect(within(region).queryByText('Corte Masculino')).not.toBeInTheDocument()
    expect(within(region).queryByText('Barba')).not.toBeInTheDocument()

    fireEvent.change(screen.getByLabelText('Status'), { target: { value: 'todos' } })
    fireEvent.change(screen.getByLabelText('Categoria'), { target: { value: 'cabelo' } })

    expect(within(region).getByText('Corte Masculino')).toBeInTheDocument()
    expect(within(region).queryByText('Barba')).not.toBeInTheDocument()
  })

  it('cadastra um serviço válido convertendo o preço para centavos', async () => {
    servicesMock.createService.mockResolvedValue('svc-novo')

    renderServices(baseValue())

    fireEvent.click(await screen.findByRole('button', { name: 'Novo serviço' }))

    fireEvent.change(screen.getByLabelText(/Nome do serviço/i), {
      target: { value: 'Hidratação Capilar' },
    })
    fireEvent.change(screen.getByLabelText(/Duração/i), { target: { value: '45' } })
    fireEvent.change(screen.getByLabelText(/^Preço/i), { target: { value: '8000' } })

    fireEvent.click(screen.getByRole('button', { name: /Cadastrar serviço/i }))

    await waitFor(() => {
      expect(servicesMock.createService).toHaveBeenCalledWith('est-1', {
        name: 'Hidratação Capilar',
        description: null,
        category: 'cabelo',
        duration_minutes: 45,
        price_cents: 8000,
        is_active: true,
      })
    })

    expect(await screen.findByText(/Serviço cadastrado com sucesso/i)).toBeInTheDocument()
  })

  it('valida o formulário antes de enviar (nome vazio, duração inválida, preço vazio)', async () => {
    renderServices(baseValue())

    fireEvent.click(await screen.findByRole('button', { name: 'Novo serviço' }))

    fireEvent.change(screen.getByLabelText(/Duração/i), { target: { value: '0' } })

    fireEvent.click(screen.getByRole('button', { name: /Cadastrar serviço/i }))

    expect(await screen.findByText(/Informe o nome do serviço/i)).toBeInTheDocument()
    expect(screen.getByText(/A duração deve ser maior que zero/i)).toBeInTheDocument()
    expect(screen.getByText(/Informe o preço do serviço/i)).toBeInTheDocument()
    expect(servicesMock.createService).not.toHaveBeenCalled()
  })

  it('recusa duração fracionada sem truncar o valor informado', async () => {
    renderServices(baseValue())
    fireEvent.click(await screen.findByRole('button', { name: 'Novo serviço' }))
    fireEvent.change(screen.getByLabelText(/Nome do serviço/i), { target: { value: 'Corte' } })
    fireEvent.change(screen.getByLabelText(/Duração/i), { target: { value: '30.5' } })
    fireEvent.change(screen.getByLabelText(/^Preço/i), { target: { value: '3550' } })
    fireEvent.click(screen.getByRole('button', { name: /Cadastrar serviço/i }))
    expect(await screen.findByText('Informe a duração em minutos inteiros.')).toBeInTheDocument()
    expect(servicesMock.createService).not.toHaveBeenCalled()
  })

  it('edita um serviço existente', async () => {
    servicesMock.listServices.mockResolvedValue([serviceFixture()])
    servicesMock.updateService.mockResolvedValue(undefined)

    renderServices(baseValue())

    fireEvent.click(await screen.findByRole('button', { name: 'Editar' }))

    const dialog = screen.getByRole('dialog')
    expect(within(dialog).getByRole('heading', { name: /Editar serviço/i })).toBeInTheDocument()

    fireEvent.change(within(dialog).getByLabelText(/Nome do serviço/i), {
      target: { value: 'Corte Masculino Premium' },
    })
    fireEvent.change(within(dialog).getByLabelText(/^Preço/i), { target: { value: '5000' } })

    fireEvent.click(within(dialog).getByRole('button', { name: /Salvar alterações/i }))

    await waitFor(() => {
      expect(servicesMock.updateService).toHaveBeenCalledWith('svc-1', {
        name: 'Corte Masculino Premium',
        description: null,
        category: 'cabelo',
        duration_minutes: 30,
        price_cents: 5000,
        is_active: true,
      })
    })

    expect(await screen.findByText(/Serviço atualizado com sucesso/i)).toBeInTheDocument()
  })

  it('desativa um serviço com confirmação e ativa sem pendências', async () => {
    // A primeira carga traz o serviço ativo; após a desativação, a recarga
    // traz o serviço inativo (dados persistidos no Supabase).
    servicesMock.listServices
      .mockResolvedValueOnce([serviceFixture()])
      .mockResolvedValueOnce([serviceFixture({ is_active: false })])
      .mockResolvedValueOnce([serviceFixture()])
    servicesMock.setServiceActive.mockResolvedValue(undefined)

    renderServices(baseValue())

    fireEvent.click(await screen.findByRole('button', { name: 'Desativar' }))

    const confirmDialog = await screen.findByRole('alertdialog')
    expect(within(confirmDialog).getByText(/Desativar o serviço "Corte Masculino"/i)).toBeInTheDocument()

    fireEvent.click(within(confirmDialog).getByRole('button', { name: 'Desativar' }))

    await waitFor(() => {
      expect(servicesMock.setServiceActive).toHaveBeenCalledWith('svc-1', false)
    })

    expect(await screen.findByText(/desativado\./i)).toBeInTheDocument()
    expect(await screen.findByRole('button', { name: 'Ativar' })).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Ativar' }))
    const activateDialog = await screen.findByRole('alertdialog')
    fireEvent.click(within(activateDialog).getByRole('button', { name: 'Ativar' }))

    await waitFor(() => {
      expect(servicesMock.setServiceActive).toHaveBeenCalledWith('svc-1', true)
    })
  })

  it('exibe erro do banco no formulário quando a operação falha', async () => {
    servicesMock.createService.mockRejectedValue(
      new Error('Ja existe um servico com esse nome neste estabelecimento'),
    )

    renderServices(baseValue())

    fireEvent.click(await screen.findByRole('button', { name: 'Novo serviço' }))
    fireEvent.change(screen.getByLabelText(/Nome do serviço/i), { target: { value: 'Corte' } })
    fireEvent.change(screen.getByLabelText(/^Preço/i), { target: { value: '3500' } })

    fireEvent.click(screen.getByRole('button', { name: /Cadastrar serviço/i }))

    expect(
      await screen.findByText(/Ja existe um servico com esse nome/i),
    ).toBeInTheDocument()
  })
})
