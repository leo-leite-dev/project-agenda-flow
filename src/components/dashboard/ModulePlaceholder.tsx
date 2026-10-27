import type { DashboardNavItem } from './navigation'
import { ClockIcon } from './icons'

interface ModulePlaceholderProps {
  module: DashboardNavItem
}

/**
 * Página honesta de "Em breve" para os módulos ainda não implementados.
 * Não simula funcionalidades, dados ou estados.
 */
export function ModulePlaceholder({ module }: ModulePlaceholderProps) {
  const Icon = module.icon

  return (
    <section className="dash-module">
      <div className="dash-card dash-module__card">
        <span className="dash-module__icon" aria-hidden="true">
          <Icon width={26} height={26} />
        </span>

        <p className="dash-module__badge">Em breve</p>
        <h1 className="dash-module__title">{module.label}</h1>
        <p className="dash-module__description">{module.description}</p>

        <div className="dash-module__note">
          <ClockIcon className="dash-module__note-icon" />
          <p>
            Este módulo faz parte das próximas etapas do Agenda Flow. Enquanto não estiver
            disponível, nenhuma informação é exibida aqui.
          </p>
        </div>
      </div>
    </section>
  )
}
