import { Link } from 'react-router-dom'

import type { User } from '@supabase/supabase-js'

import { useAuth } from '../hooks/useAuth'
import { DashboardLayout } from '../components/dashboard/DashboardLayout'
import type { UserEstablishment } from '../contexts/AuthContext'
import {
  CalendarEmptyIcon,
  CheckIcon,
  ClockEmptyIcon,
  ClockIcon,
  ClientsEmptyIcon,
  FinanceEmptyIcon,
  SparkIcon,
} from '../components/dashboard/icons'

const ESTABLISHMENT_TYPE_LABEL = {
  barbershop: 'Barbearia',
  salon: 'Salão de beleza',
} as const

interface SetupTask {
  /** Número da etapa. */
  step: number
  title: string
  description: string
  /** Rota do módulo correspondente (página "Em breve" nesta etapa). */
  modulePath: string
  moduleLabel: string
}

const SETUP_TASKS: SetupTask[] = [
  {
    step: 1,
    title: 'Configurar horários de funcionamento',
    description: 'Defina os dias e horários em que o estabelecimento atende.',
    modulePath: '/dashboard/configuracoes',
    moduleLabel: 'Configurações',
  },
  {
    step: 2,
    title: 'Cadastrar os serviços oferecidos',
    description: 'Corte, barba, coloração e demais serviços com duração e preço.',
    modulePath: '/dashboard/servicos',
    moduleLabel: 'Serviços',
  },
  {
    step: 3,
    title: 'Adicionar profissionais à equipe',
    description: 'Convide os profissionais e defina o papel de cada um.',
    modulePath: '/dashboard/equipe',
    moduleLabel: 'Equipe',
  },
  {
    step: 4,
    title: 'Preparar a agenda de atendimentos',
    description: 'Organize os atendimentos por profissional e horário.',
    modulePath: '/dashboard/agenda',
    moduleLabel: 'Agenda',
  },
]

interface FutureMetric {
  key: string
  title: string
  message: string
  icon: typeof CalendarEmptyIcon
}

const FUTURE_METRICS: FutureMetric[] = [
  {
    key: 'today',
    title: 'Agendamentos de hoje',
    message: 'A agenda estará disponível em breve.',
    icon: CalendarEmptyIcon,
  },
  {
    key: 'upcoming',
    title: 'Próximos atendimentos',
    message: 'Os próximos atendimentos aparecerão aqui.',
    icon: ClockEmptyIcon,
  },
  {
    key: 'clients',
    title: 'Clientes cadastrados',
    message: 'O cadastro de clientes estará disponível em breve.',
    icon: ClientsEmptyIcon,
  },
  {
    key: 'revenue',
    title: 'Faturamento',
    message: 'O acompanhamento financeiro estará disponível em breve.',
    icon: FinanceEmptyIcon,
  },
]

function formatDate(value: string): string {
  try {
    return new Intl.DateTimeFormat('pt-BR', { dateStyle: 'long' }).format(new Date(value))
  } catch {
    return value
  }
}

interface OverviewContentProps {
  establishment: UserEstablishment
  user: User | null
}

function OverviewContent({ establishment, user }: OverviewContentProps) {
  const location = establishment.address
  const locationLabel =
    location?.city && location?.state ? `${location.city}, ${location.state}` : null
  const contactLabel = establishment.phone ?? establishment.email ?? null

  return (
    <>
      <section className="dash-welcome">
        <p className="dash-welcome__eyebrow">
          <SparkIcon className="dash-welcome__eyebrow-icon" />
          Visão geral
        </p>
        <h1 className="dash-welcome__title">Bem-vindo ao {establishment.name}</h1>
        <p className="dash-welcome__subtitle">
          {ESTABLISHMENT_TYPE_LABEL[establishment.type]}
          {locationLabel ? ` • ${locationLabel}` : ''} • Seu papel:{' '}
          <strong>{establishment.role === 'owner' ? 'Proprietário' : establishment.role}</strong>
        </p>
      </section>

      <section className="dash-metrics" aria-label="Indicadores do negócio">
        {FUTURE_METRICS.map((metric) => {
          const Icon = metric.icon

          return (
            <article className="dash-card dash-metric" key={metric.key}>
              <header className="dash-metric__head">
                <span className="dash-metric__icon" aria-hidden="true">
                  <Icon />
                </span>
                <h2 className="dash-metric__title">{metric.title}</h2>
              </header>
              <p className="dash-metric__empty">{metric.message}</p>
            </article>
          )
        })}
      </section>

      <section className="dash-card dash-checklist" aria-labelledby="dash-checklist-title">
        <header className="dash-checklist__head">
          <div>
            <h2 className="dash-card__title" id="dash-checklist-title">
              Preparação para os primeiros agendamentos
            </h2>
            <p className="dash-card__subtitle">
              Complete estas etapas para começar a atender. Elas serão liberadas nas próximas
              atualizações.
            </p>
          </div>
          <span className="dash-checklist__progress">0 de 4 concluídas</span>
        </header>

        <ol className="dash-checklist__list">
          {SETUP_TASKS.map((task) => (
            <li className="dash-task" key={task.step}>
              <span className="dash-task__step" aria-hidden="true">
                <CheckIcon />
              </span>
              <div className="dash-task__body">
                <h3 className="dash-task__title">{task.title}</h3>
                <p className="dash-task__description">{task.description}</p>
              </div>
              <Link to={task.modulePath} className="dash-task__action">
                <ClockIcon className="dash-task__action-icon" />
                {task.moduleLabel} • Em breve
              </Link>
            </li>
          ))}
        </ol>
      </section>

      <section className="dash-card dash-summary" aria-labelledby="dash-summary-title">
        <h2 className="dash-card__title" id="dash-summary-title">
          Resumo do estabelecimento
        </h2>
        <dl className="dash-summary__grid">
          <div className="dash-summary__item">
            <dt>Nome</dt>
            <dd>{establishment.name}</dd>
          </div>
          <div className="dash-summary__item">
            <dt>Tipo</dt>
            <dd>{ESTABLISHMENT_TYPE_LABEL[establishment.type]}</dd>
          </div>
          <div className="dash-summary__item">
            <dt>Identificador</dt>
            <dd>{establishment.slug}</dd>
          </div>
          <div className="dash-summary__item">
            <dt>Contato</dt>
            <dd>{contactLabel ?? 'Não informado'}</dd>
          </div>
          <div className="dash-summary__item">
            <dt>Endereço</dt>
            <dd>
              {establishment.address?.address ?? 'Não informado'}
              {locationLabel ? ` — ${locationLabel}` : ''}
            </dd>
          </div>
          <div className="dash-summary__item">
            <dt>Criado em</dt>
            <dd>{formatDate(establishment.created_at)}</dd>
          </div>
        </dl>
        <p className="dash-summary__user">
          Autenticado como <strong>{user?.email ?? user?.phone ?? 'usuário'}</strong>.
        </p>
      </section>
    </>
  )
}

/**
 * Visão geral da área administrativa. Os guards (carregamento, ausência de
 * estabelecimento e seleção) são responsabilidade do DashboardLayout, que
 * usa apenas os dados reais da sessão autorizada por RLS.
 */
export function DashboardPage() {
  const { user, establishments, currentEstablishment } = useAuth()

  const establishment = currentEstablishment ?? establishments[0]

  return (
    <DashboardLayout>
      {establishment ? <OverviewContent establishment={establishment} user={user} /> : null}
    </DashboardLayout>
  )
}
