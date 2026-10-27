#!/usr/bin/env node
/**
 * Runner de integração do banco de dados.
 *
 * Executa as migrations versionadas e o seed de asserções em um PostgreSQL
 * real (PGlite: PostgreSQL compilado para WebAssembly), sem necessidade de
 * Docker. As políticas RLS são de fato avaliadas, porque os cenários rodam
 * com `SET LOCAL ROLE authenticated` e claims JWT simuladas.
 *
 * Uso:
 *   npm run test:db
 *
 * Saída:
 *   0 = todas as asserções passaram
 *   1 = alguma asserção falhou (a mensagem indica o cenário)
 */

import { readdirSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import { PGlite } from '@electric-sql/pglite'

const here = dirname(fileURLToPath(import.meta.url))
const supabaseDir = resolve(here, '..', '..')
const migrationsDir = join(supabaseDir, 'migrations')
const seedFile = join(supabaseDir, 'seed.sql')
const bootstrapFile = join(here, 'bootstrap.sql')

const results = []

function report(status, message) {
  results.push({ status, message })
  const label = status === 'ok' ? 'OK  ' : 'FAIL'
  console.log(`  ${label} ${message}`)
}

/**
 * O build do PGlite não embarca o arquivo de controle da extensão pgcrypto.
 * No Supabase a extensão existe (criada pela migration 20250127000000 ou
 * pelas funções de bootstrap) e as funções da extensão são fornecidas pelo
 * bootstrap de teste, no schema "extensions" (mesmo layout do Supabase).
 */
function neutralizePgcryptoExtension(sql) {
  return sql.replace(
    /CREATE EXTENSION\s+(IF NOT EXISTS\s+)?["]?pgcrypto["]?[^;]*;/gi,
    '-- CREATE EXTENSION pgcrypto; -- neutralizado no runner PGlite',
  )
}

function lineContext(sql, position) {
  if (!position) return ''
  const index = sql.slice(0, position).split('\n').length
  const lines = sql.split('\n')
  const start = Math.max(0, index - 3)
  const end = Math.min(lines.length, index + 2)
  return lines
    .slice(start, end)
    .map((line, i) => `${String(start + i + 1).padStart(4)} | ${line}`)
    .join('\n')
}

async function main() {
  console.log('Agenda Flow — testes de integração do banco de dados (PostgreSQL real via PGlite)\n')

  const db = await new PGlite()

  console.log('Bootstrap (emulação do ambiente Supabase)')
  try {
    await db.exec(readFileSync(bootstrapFile, 'utf8'))
    report('ok', 'schema auth, roles e funções de pgcrypto disponíveis')
  } catch (error) {
    report('fail', `bootstrap falhou: ${error.message}`)
    return 1
  }

  const migrationFiles = readdirSync(migrationsDir)
    .filter((file) => file.endsWith('.sql'))
    .sort()

  console.log('\nMigrations')
  for (const file of migrationFiles) {
    const raw = readFileSync(join(migrationsDir, file), 'utf8')
    const sql = neutralizePgcryptoExtension(raw)

    try {
      await db.exec(sql)
      report('ok', file)
    } catch (error) {
      report('fail', `${file}: ${error.message}`)
      console.log(lineContext(sql, error.position))
      return 1
    }

    // Verificação intermediária: logo após a 20250127000003, nenhuma função
    // nova pode estar exposta a PUBLIC/anon (sem janela de exposição entre
    // migrations).
    if (file.startsWith('20250127000003')) {
      const check = await db.query(`
        SELECT
          has_function_privilege('anon', 'agenda_flow_private.upsert_profile_from_auth_user(uuid)', 'EXECUTE') AS anon_internal,
          has_function_privilege('authenticated', 'agenda_flow_private.upsert_profile_from_auth_user(uuid)', 'EXECUTE') AS auth_internal,
          has_function_privilege('anon', 'agenda_flow_private.handle_new_user()', 'EXECUTE') AS anon_trigger,
          has_function_privilege('authenticated', 'agenda_flow_private.handle_new_user()', 'EXECUTE') AS auth_trigger,
          has_schema_privilege('anon', 'agenda_flow_private', 'USAGE') AS anon_private_schema,
          has_schema_privilege('authenticated', 'agenda_flow_private', 'USAGE') AS auth_private_schema,
          has_function_privilege('anon', 'public.ensure_profile()', 'EXECUTE') AS anon_ensure,
          has_function_privilege('authenticated', 'public.ensure_profile()', 'EXECUTE') AS auth_ensure
      `)

      const row = check.rows[0]
      const leaked = Object.entries(row).filter(([key, value]) => {
        if (key.startsWith('anon_')) return value === true
        if (key.startsWith('auth_internal') || key.startsWith('auth_trigger')) return value === true
        if (key.startsWith('auth_private')) return value === true
        return false
      })

      if (leaked.length > 0) {
        report('fail', `20250127000003: funções privilegiadas expostas antes da 00004 (${leaked.map(([k]) => k).join(', ')})`)
        return 1
      }

      if (row.anon_ensure !== false || row.auth_ensure !== true) {
        report('fail', '20250127000003: ensure_profile com permissões incorretas antes da 00004')
        return 1
      }

      report('ok', 'estado intermediário após a 20250127000003 sem funções privilegiadas expostas')
    }
  }

  console.log('\nSeed de asserções (RLS, multi-tenant e integridade de perfis)')
  const seedSql = readFileSync(seedFile, 'utf8')

  try {
    await db.exec(seedSql)
    report('ok', 'todas as asserções do seed passaram')
  } catch (error) {
    report('fail', `seed: ${error.message}`)
    console.log(lineContext(seedSql, error.position))
    return 1
  }

  console.log('\nAuditoria do banco (supabase/tests/verify_remote.sql)')
  const verifySql = readFileSync(join(supabaseDir, 'tests', 'verify_remote.sql'), 'utf8')

  try {
    await db.exec(verifySql)
    report('ok', 'verify_remote.sql executado sem falhas')
  } catch (error) {
    report('fail', `verify_remote.sql: ${error.message}`)
    console.log(lineContext(verifySql, error.position))
    return 1
  }

  console.log('\nEstado final das permissões')
  const summary = await db.query(`
    SELECT
      (SELECT count(*) FROM auth.users)            AS auth_users,
      (SELECT count(*) FROM public.profiles)       AS profiles,
      (SELECT count(*) FROM public.establishments) AS establishments,
      (SELECT count(*) FROM public.establishment_members) AS memberships
  `)

  console.log(`  ${JSON.stringify(summary.rows[0])}`)

  const failures = results.filter((result) => result.status === 'fail')

  console.log(`\n${results.length - failures.length}/${results.length} verificações concluídas com sucesso.`)

  return failures.length === 0 ? 0 : 1
}

main()
  .then((code) => process.exit(code))
  .catch((error) => {
    console.error('Erro inesperado no runner:', error)
    process.exit(1)
  })
