import { readdirSync, readFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

import { PGlite } from '@electric-sql/pglite'

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, '..', '..', '..')
const supabaseDir = join(root, 'supabase')
const db = await new PGlite()

const neutralize = (sql) =>
  sql.replace(/CREATE EXTENSION\s+(IF NOT EXISTS\s+)?["]?pgcrypto["]?[^;]*;/gi, '-- neutralizado')

await db.exec(readFileSync(join(supabaseDir, 'tests', 'pglite', 'bootstrap.sql'), 'utf8'))

const before = await db.query(`
  SELECT d.defaclrole::regrole::text AS role, d.defaclobjtype::text AS obj,
         CASE WHEN d.defaclnamespace = 0 THEN 'GLOBAL' ELSE n.nspname END AS schema,
         pg_get_userbyid(g.grantee) AS grantee, g.privilege_type
  FROM pg_default_acl d
  LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
  CROSS JOIN LATERAL aclexplode(d.defaclacl) g
  WHERE n.nspname = 'public' OR d.defaclnamespace = 0
  ORDER BY schema, role, obj, grantee
`)
console.log('=== pg_default_acl ANTES das migrations ===')
console.table(before.rows)

for (const file of readdirSync(join(supabaseDir, 'migrations')).sort()) {
  await db.exec(neutralize(readFileSync(join(supabaseDir, 'migrations', file), 'utf8')))
}

const after = await db.query(`
  SELECT d.defaclrole::regrole::text AS role, d.defaclobjtype::text AS obj,
         CASE WHEN d.defaclnamespace = 0 THEN 'GLOBAL' ELSE n.nspname END AS schema,
         pg_get_userbyid(g.grantee) AS grantee, g.privilege_type
  FROM pg_default_acl d
  LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
  CROSS JOIN LATERAL aclexplode(d.defaclacl) g
  WHERE n.nspname = 'public' OR d.defaclnamespace = 0
  ORDER BY schema, role, obj, grantee
`)
console.log('=== pg_default_acl DEPOIS das migrations ===')
console.table(after.rows)

const privs = await db.query(`
  SELECT table_name,
         has_table_privilege('anon', 'public.' || table_name, 'SELECT') AS anon_sel,
         has_table_privilege('authenticated', 'public.' || table_name, 'SELECT') AS auth_sel,
         has_table_privilege('authenticated', 'public.' || table_name, 'INSERT,UPDATE,DELETE') AS auth_write
  FROM information_schema.tables
  WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
  ORDER BY table_name
`)
console.log('=== privilegios finais nas tabelas ===')
console.table(privs.rows)

const fns = await db.query(`
  SELECT n.nspname AS schema, p.proname AS function,
         has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
         has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'agenda_flow_private')
  ORDER BY n.nspname, p.proname
`)
console.log('=== matriz EXECUTE ===')
console.table(fns.rows)

await db.exec(
  'CREATE FUNCTION public.af_probe_after_migrations() RETURNS integer LANGUAGE sql AS $p$ SELECT 1 $p$;',
)
const probe = await db.query(
  "select has_function_privilege('anon', 'public.af_probe_after_migrations()', 'EXECUTE') as anon_exec, has_function_privilege('authenticated', 'public.af_probe_after_migrations()', 'EXECUTE') as auth_exec",
)
console.log('=== função criada DEPOIS das migrations (default de privilégios) ===')
console.table(probe.rows)
await db.exec('DROP FUNCTION public.af_probe_after_migrations();')
