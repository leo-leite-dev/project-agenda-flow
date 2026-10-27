import type { ComponentType, SVGProps } from 'react'

import {
  CalendarIcon,
  ClientsIcon,
  FinanceIcon,
  OverviewIcon,
  ServicesIcon,
  SettingsIcon,
  TeamIcon,
} from './icons'

export interface DashboardNavItem {
  /** Caminho relativo à área do dashboard. */
  path: string
  label: string
  icon: ComponentType<SVGProps<SVGSVGElement>>
  /** Módulo já implementado. */
  implemented: boolean
  /** Descrição usada na página "Em breve". */
  description: string
}

/**
 * Navegação da área administrativa. A Visão Geral é a página inicial.
 * Módulos ainda não implementados apontam para uma página honesta de
 * "Em breve" — nenhuma funcionalidade é simulada.
 */
export const dashboardNav: DashboardNavItem[] = [
  {
    path: '/dashboard',
    label: 'Visão geral',
    icon: OverviewIcon,
    implemented: true,
    description: 'Resumo do estabelecimento e próximos passos de configuração.',
  },
  {
    path: '/dashboard/agenda',
    label: 'Agenda',
    icon: CalendarIcon,
    implemented: false,
    description:
      'Agenda de atendimentos por profissional, com visualização diária, semanal e mensal.',
  },
  {
    path: '/dashboard/servicos',
    label: 'Serviços',
    icon: ServicesIcon,
    implemented: false,
    description:
      'Catálogo de serviços com duração e preço, base para a agenda e o financeiro.',
  },
  {
    path: '/dashboard/equipe',
    label: 'Equipe',
    icon: TeamIcon,
    implemented: false,
    description:
      'Profissionais do estabelecimento, papéis e permissões de acesso.',
  },
  {
    path: '/dashboard/clientes',
    label: 'Clientes',
    icon: ClientsIcon,
    implemented: false,
    description:
      'Cadastro de clientes com histórico de atendimentos e preferências.',
  },
  {
    path: '/dashboard/financeiro',
    label: 'Financeiro',
    icon: FinanceIcon,
    implemented: false,
    description:
      'Receitas, despesas e acompanhamento do faturamento do negócio.',
  },
  {
    path: '/dashboard/configuracoes',
    label: 'Configurações',
    icon: SettingsIcon,
    implemented: false,
    description:
      'Dados do estabelecimento, horários de funcionamento e preferências.',
  },
]

/** Resolve as informações do módulo a partir do caminho atual. */
export function resolveNavItem(pathname: string): DashboardNavItem | undefined {
  return dashboardNav.find((item) => item.path === pathname)
}
