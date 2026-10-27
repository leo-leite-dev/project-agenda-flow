import { describe, expect, it } from 'vitest'

import { formatBRL, parseBRLToCents, buildBRLMask } from '../services'

/**
 * Intl.NumberFormat('pt-BR') usa espaço não separável (U+00A0) entre o
 * símbolo e o valor.
 */
const brl = (value: string) => `R$\u00A0${value}`

describe('formatBRL', () => {
  it('formata valores em reais com centavos', () => {
    expect(formatBRL(3500)).toBe(brl('35,00'))
    expect(formatBRL(3550)).toBe(brl('35,50'))
    expect(formatBRL(123456)).toBe(brl('1.234,56'))
    expect(formatBRL(0)).toBe(brl('0,00'))
  })
})

describe('parseBRLToCents', () => {
  it('interpreta os dígitos como centavos (padrão da máscara de digitação)', () => {
    expect(parseBRLToCents('35')).toBe(35)
    expect(parseBRLToCents('35,50')).toBe(3550)
    expect(parseBRLToCents('R$ 1.234,56')).toBe(123456)
    expect(parseBRLToCents('0')).toBe(0)
    expect(parseBRLToCents('0,00')).toBe(0)
  })

  it('retorna null quando o campo está vazio', () => {
    expect(parseBRLToCents('')).toBeNull()
    expect(parseBRLToCents('R$ ')).toBeNull()
    expect(parseBRLToCents('   ')).toBeNull()
  })

  it('a máscara e a conversão são consistentes entre si', () => {
    const typed = '5000'

    expect(parseBRLToCents(buildBRLMask(typed))).toBe(5000)
  })
})

describe('buildBRLMask', () => {
  it('reconstrói a moeda a partir dos dígitos digitados', () => {
    expect(buildBRLMask('350')).toBe(brl('3,50'))
    expect(buildBRLMask('3500')).toBe(brl('35,00'))
    expect(buildBRLMask('123456')).toBe(brl('1.234,56'))
  })

  it('retorna vazio quando não há dígitos', () => {
    expect(buildBRLMask('')).toBe('')
    expect(buildBRLMask('abc')).toBe('')
  })
})
