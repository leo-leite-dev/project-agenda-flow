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

  console.log('\nRecuperação idempotente de perfil ausente')
  const recoverySql = readFileSync(join(supabaseDir, 'tests', 'repair_missing_profiles.sql'), 'utf8')
  try {
    await db.exec(`
      INSERT INTO auth.users (id, email, raw_user_meta_data, role)
      VALUES (
        'abababab-abab-4bab-8bab-abababababab',
        'profile-recovery@agenda.flow.test',
        '{"full_name":"Profile Recovery"}',
        'authenticated'
      )
      ON CONFLICT (id) DO NOTHING;
      DELETE FROM public.profiles
      WHERE id = 'abababab-abab-4bab-8bab-abababababab';
    `)
    await db.exec(recoverySql)
    await db.exec(recoverySql)

    const recovered = await db.query(`
      SELECT id, full_name
      FROM public.profiles
      WHERE id = 'abababab-abab-4bab-8bab-abababababab'
    `)
    if (recovered.rows.length !== 1 || recovered.rows[0].full_name !== 'Profile Recovery') {
      report('fail', 'recuperação não preservou o ID ou os metadados do perfil')
      return 1
    }
    report('ok', 'perfil ausente recuperado e procedimento reaplicado sem duplicação')
  } catch (error) {
    report('fail', `recuperação de perfil: ${error.message}`)
    console.log(lineContext(recoverySql, error.position))
    return 1
  }

  console.log('\nReaplicação da migration 00010 (proteção de exclusão)')
  const deletionSafetyMigration = migrationFiles.find((file) => file.startsWith('20250127000010'))
  if (!deletionSafetyMigration) {
    report('fail', 'migration 20250127000010_profile_deletion_safety.sql não encontrada')
    return 1
  }

  const deletionSafetySql = neutralizePgcryptoExtension(
    readFileSync(join(migrationsDir, deletionSafetyMigration), 'utf8'),
  )
  try {
    await db.exec(deletionSafetySql)
    const deletionRules = await db.query(`
      SELECT c.conname, c.confdeltype
      FROM pg_constraint c
      WHERE c.conname IN (
        'establishments_owner_id_fkey',
        'establishment_members_user_id_fkey',
        'establishment_invitations_invited_by_fkey'
      )
    `)
    if (deletionRules.rows.length !== 3 || deletionRules.rows.some((row) => row.confdeltype !== 'r')) {
      report('fail', 'reaplicação da 00010 não preservou as três FKs como RESTRICT')
      return 1
    }
    report('ok', 'migration 00010 reaplicada e as três FKs permanecem como RESTRICT')
  } catch (error) {
    report('fail', `reaplicação da 00010: ${error.message}`)
    console.log(lineContext(deletionSafetySql, error.position))
    return 1
  }

  console.log('\nReaplicação da migration 00009 (idempotência e preservação de dados)')
  const professionalsMigration = migrationFiles.find((file) => file.startsWith('20250127000009'))
  const beforeReapply = await db.query(`
    SELECT
      (SELECT coalesce(jsonb_agg(to_jsonb(ep) ORDER BY ep.id), '[]'::jsonb)
       FROM public.establishment_professionals ep) AS professionals,
      (SELECT coalesce(jsonb_agg(to_jsonb(eps) ORDER BY eps.id), '[]'::jsonb)
       FROM public.establishment_professional_services eps) AS professional_services
  `)

  if (!professionalsMigration) {
    report('fail', 'migration 20250127000009_professionals.sql não encontrada')
    return 1
  }

  const reapplySql = neutralizePgcryptoExtension(
    readFileSync(join(migrationsDir, professionalsMigration), 'utf8'),
  )

  try {
    await db.exec(reapplySql)
    const afterReapply = await db.query(`
      SELECT
        (SELECT coalesce(jsonb_agg(to_jsonb(ep) ORDER BY ep.id), '[]'::jsonb)
         FROM public.establishment_professionals ep) AS professionals,
        (SELECT coalesce(jsonb_agg(to_jsonb(eps) ORDER BY eps.id), '[]'::jsonb)
         FROM public.establishment_professional_services eps) AS professional_services
    `)
    const before = beforeReapply.rows[0]
    const after = afterReapply.rows[0]

    if (JSON.stringify(before.professionals) !== JSON.stringify(after.professionals) ||
        JSON.stringify(before.professional_services) !== JSON.stringify(after.professional_services)) {
      report('fail', 'reaplicação da 00009 alterou a quantidade de dados')
      return 1
    }

    report('ok', 'migration 00009 reaplicada sem falhas e sem perda de dados')
  } catch (error) {
    report('fail', `reaplicação da 00009: ${error.message}`)
    console.log(lineContext(reapplySql, error.position))
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

  await db.close()

  const scenarioCode = await runCustomUniquenessScenario(migrationFiles)
  if (scenarioCode !== 0) {
    return scenarioCode
  }

  const failures = results.filter((result) => result.status === 'fail')

  console.log(`\n${results.length - failures.length}/${results.length} verificações concluídas com sucesso.`)

  return failures.length === 0 ? 0 : 1
}

/**
 * Cenário: a unicidade dos vínculos já está garantida por um objeto com NOME
 * DIFERENTE do esperado pela migration 00008.
 *
 * A migration detecta a constraint/índice pelo conjunto de colunas (e não pelo
 * nome) e comenta o objeto realmente existente. Este cenário prova que:
 *   • a migration 00008 aplica sem falhar com uma constraint renomeada;
 *   • a migration 00008 aplica sem falhar com um índice único (sem constraint);
 *   • nenhum registro é excluído ou alterado;
 *   • a unicidade continua em vigor (o vínculo duplicado é recusado).
 */
async function runCustomUniquenessScenario(migrationFiles) {
  console.log('\nCenário: unicidade de vínculo garantida por objeto com nome diferente')

  const target = '20250127000008_membership_integrity.sql'
  const targetFile = migrationFiles.find((file) => file.startsWith('20250127000008'))

  if (!targetFile) {
    report('fail', `migration ${target} não encontrada`)
    return 1
  }

  const variants = [
    {
      label: 'constraint renomeada',
      prepare: `
        ALTER TABLE public.establishment_members
          RENAME CONSTRAINT establishment_members_establishment_id_user_id_key
          TO uq_memberships_custom_name;
      `,
    },
    {
      label: 'índice único com nome próprio',
      prepare: `
        ALTER TABLE public.establishment_members
          DROP CONSTRAINT establishment_members_establishment_id_user_id_key;
        CREATE UNIQUE INDEX uq_memberships_custom_index
          ON public.establishment_members (establishment_id, user_id);
      `,
    },
  ]

  for (const variant of variants) {
    const db = await new PGlite()

    try {
      await db.exec(readFileSync(bootstrapFile, 'utf8'))

      for (const file of migrationFiles) {
        if (file === targetFile) continue
        await db.exec(neutralizePgcryptoExtension(readFileSync(join(migrationsDir, file), 'utf8')))
      }

      await db.exec(variant.prepare)

      // Dataset mínimo: um usuário com o vínculo de proprietário (criado pelo
      // trigger de criação do estabelecimento).
      await db.exec(`
        INSERT INTO auth.users (id, email, email_confirmed_at)
        VALUES ('11111111-1111-1111-1111-111111111111', 'cenario@agenda.flow.test', now());

        INSERT INTO public.establishments (owner_id, name, slug, type)
        VALUES (
          '11111111-1111-1111-1111-111111111111',
          'Barbearia Cenario',
          'barbearia-cenario',
          'barbershop'
        );
      `)

      const before = await db.query('SELECT count(*)::int AS total FROM public.establishment_members')

      await db.exec(neutralizePgcryptoExtension(readFileSync(join(migrationsDir, targetFile), 'utf8')))
      report('ok', `00008 aplicada com ${variant.label} (sem falhar)`)

      const after = await db.query('SELECT count(*)::int AS total FROM public.establishment_members')

      if (after.rows[0].total !== before.rows[0].total) {
        report('fail', `${variant.label}: a migration alterou a quantidade de vínculos`)
        await db.close()
        return 1
      }

      report('ok', `${variant.label}: nenhum vínculo foi excluído ou alterado`)

      // A unicidade continua em vigor: um vínculo duplicado é recusado.
      const duplicates = await db.query(`
        DO $$
        DECLARE
          v_establishment uuid;
          v_user uuid;
        BEGIN
          SELECT establishment_id, user_id INTO v_establishment, v_user
          FROM public.establishment_members LIMIT 1;

          BEGIN
            INSERT INTO public.establishment_members (establishment_id, user_id, role)
            VALUES (v_establishment, v_user, 'professional');
            RAISE EXCEPTION 'Duplicated link was accepted';
          EXCEPTION WHEN unique_violation THEN
            RAISE NOTICE 'Duplicated link refused by the database.';
          END;
        END $$;
      `)

      if (!duplicates) {
        report('fail', `${variant.label}: falha ao verificar a unicidade`)
        await db.close()
        return 1
      }

      report('ok', `${variant.label}: vínculo duplicado continua recusado pelo banco`)
    } catch (error) {
      report('fail', `${variant.label}: ${error.message}`)
      console.log(lineContext(readFileSync(join(migrationsDir, targetFile), 'utf8'), error.position))
      await db.close()
      return 1
    }

    await db.close()
  }

  return 0
}

main()
  .then((code) => process.exit(code))
  .catch((error) => {
    console.error('Erro inesperado no runner:', error)
    process.exit(1)
  })
