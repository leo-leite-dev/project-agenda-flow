import type { SVGProps } from 'react'

type IconProps = SVGProps<SVGSVGElement>

function base(props: IconProps) {
  return {
    width: 20,
    height: 20,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.8,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    'aria-hidden': true,
    focusable: false,
    ...props,
  }
}

export function OverviewIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M3.5 3.5h7v7h-7zM13.5 3.5h7v4h-7zM13.5 12.5h7v8h-7zM3.5 14.5h7v6h-7z" />
    </svg>
  )
}

export function CalendarIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <rect x="3.5" y="5" width="17" height="15.5" rx="2.5" />
      <path d="M3.5 9.5h17M8 3v4M16 3v4M8 13.5h3M8 17h8" />
    </svg>
  )
}

export function ServicesIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <circle cx="6" cy="6" r="2.8" />
      <circle cx="6" cy="18" r="2.8" />
      <path d="M8.2 7.8 20 19.5M8.2 16.2 20 4.5M14 14l2.5 2.5M17 11l3 3" />
    </svg>
  )
}

export function TeamIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <circle cx="9" cy="8" r="3.2" />
      <path d="M3.5 20c.6-3.2 2.8-5 5.5-5s4.9 1.8 5.5 5" />
      <path d="M16 5.4a3 3 0 0 1 0 5.8M17.5 15.4c1.7.7 2.7 2.3 3 4.6" />
    </svg>
  )
}

export function ClientsIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <circle cx="12" cy="8" r="3.4" />
      <path d="M5.5 20c.8-3.6 3.3-5.6 6.5-5.6s5.7 2 6.5 5.6" />
    </svg>
  )
}

export function FinanceIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <rect x="3.5" y="6" width="17" height="12.5" rx="2.5" />
      <path d="M3.5 10h17M16.5 14.5h1.5" />
    </svg>
  )
}

export function SettingsIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <circle cx="12" cy="12" r="3.2" />
      <path d="M12 3v2.4M12 18.6V21M4.2 7.5l2 1.2M17.8 15.3l2 1.2M4.2 16.5l2-1.2M17.8 8.7l2-1.2M3 12h2.4M18.6 12H21" />
    </svg>
  )
}

export function BellIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M18 15.5V11a6 6 0 1 0-12 0v4.5L4.5 18h15z" />
      <path d="M10 21h4" />
    </svg>
  )
}

export function SignOutIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M14 4.5H6.5v15H14M10.5 12H20M17 8.5 20.5 12 17 15.5" />
    </svg>
  )
}

export function SwapIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M4 8h13M14 4.5 17.5 8 14 11.5M20 16H7M10 12.5 6.5 16l3.5 3.5" />
    </svg>
  )
}

export function MenuIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M4 6.5h16M4 12h16M4 17.5h16" />
    </svg>
  )
}

export function CloseIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M6 6l12 12M18 6 6 18" />
    </svg>
  )
}

export function CheckIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M5 12.5 10 17.5 19 7" />
    </svg>
  )
}

export function ClockIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <circle cx="12" cy="12" r="8.5" />
      <path d="M12 7.5V12l3 2" />
    </svg>
  )
}

export function SparkIcon(props: IconProps) {
  return (
    <svg {...base(props)}>
      <path d="M12 3.5 13.8 9l5.7 1.8-5.7 1.8L12 18.5l-1.8-5.9L4.5 10.8 10.2 9z" />
    </svg>
  )
}

export function CalendarEmptyIcon(props: IconProps) {
  return CalendarIcon({ width: 28, height: 28, ...props })
}

export function ClockEmptyIcon(props: IconProps) {
  return ClockIcon({ width: 28, height: 28, ...props })
}

export function ClientsEmptyIcon(props: IconProps) {
  return ClientsIcon({ width: 28, height: 28, ...props })
}

export function FinanceEmptyIcon(props: IconProps) {
  return FinanceIcon({ width: 28, height: 28, ...props })
}
