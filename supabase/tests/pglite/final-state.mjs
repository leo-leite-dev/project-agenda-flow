import { readdirSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import { PGlite } from '@electric-sql/pglite'

const here = dirname(fileURLToPath(import.meta.url))
const supabaseDir = resolve(here, '..', '..')
const db = await new PGlite()
const neutralize = (sql) =>
  sql.replace(/CREATE EXTENSION\s+(IF NOT EXISTS\s+)?["]?pgcrypto["]?[^;]*;/gi, '-- neutralizado')

await db.exec(readFileSync(join(supabaseDir, 'tests', 'pglite', 'bootstrap.sql'), 'utf8'))
for (const f of readdirSync(join(supabaseDir, 'migrations')).sort()) {
  await db.exec(neutralize(readFileSync(join(supabaseDir, 'migrations', f), 'utf8')))
}

const q = await db.query(`
  SELECT d.defaclrole::regrole::text AS owner,
         CASE WHEN g.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(g.grantee) END AS grantee,
         count(*) AS entradas,
         string_agg(DISTINCT g.privilege_type, ', ' ORDER BY g.privilege_type) AS privilegios
  FROM pg_default_acl d
  JOIN pg_namespace n ON n.oid = d.defaclnamespace
  CROSS JOIN LATERAL aclexplode(d.defaclacl) g
  WHERE n.nspname = 'public' AND d.defaclobjtype IN ('r','S')
  GROUP BY 1, 2 ORDER BY 1, 2
`)
console.log('=== pg_default_acl FINAL (schema public, tabelas/sequences) ===')
console.table(q.rows)

const helpers = await db.query(`
  SELECT
    agenda_flow_private.unexpected_default_privileges() AS bloqueantes,
    agenda_flow_private.platform_default_privileges() AS plataforma,
    agenda_flow_private.publicly_exposed_functions() AS funcoes_expostas
`)
console.log('=== helpers de auditoria ===')
console.table(helpers.rows)
