/**
 * Normalizes a string into a URL-friendly slug.
 * Example: "Barbearia Alpha" -> "barbearia-alpha"
 */
export function slugify(input: string): string {
  return input
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
}

/**
 * Generates a unique-ish slug from a name by appending a short random suffix.
 */
export function generateSlug(name: string): string {
  const base = slugify(name) || 'estabelecimento'
  const suffix = Math.random().toString(36).slice(2, 7)
  return `${base}-${suffix}`
}

/**
 * Formats a Brazilian phone number for display.
 * Accepts only digits; returns empty string for invalid input.
 */
export function formatPhone(input: string): string {
  const digits = input.replace(/\D/g, '')

  if (digits.length === 11) {
    return digits.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3')
  }

  if (digits.length === 10) {
    return digits.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3')
  }

  return input
}
