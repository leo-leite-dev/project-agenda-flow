-- Read-only report of foreign keys affecting profiles and tenant ownership.
-- It does not modify schema or data.

SELECT
  source_ns.nspname AS source_schema,
  source_table.relname AS source_table,
  constraint_name.conname AS constraint_name,
  target_ns.nspname AS target_schema,
  target_table.relname AS target_table,
  CASE constraint_name.confdeltype
    WHEN 'a' THEN 'NO ACTION'
    WHEN 'r' THEN 'RESTRICT'
    WHEN 'c' THEN 'CASCADE'
    WHEN 'n' THEN 'SET NULL'
    WHEN 'd' THEN 'SET DEFAULT'
    ELSE 'UNKNOWN'
  END AS on_delete,
  pg_get_constraintdef(constraint_name.oid) AS definition
FROM pg_constraint constraint_name
JOIN pg_class source_table ON source_table.oid = constraint_name.conrelid
JOIN pg_namespace source_ns ON source_ns.oid = source_table.relnamespace
JOIN pg_class target_table ON target_table.oid = constraint_name.confrelid
JOIN pg_namespace target_ns ON target_ns.oid = target_table.relnamespace
WHERE constraint_name.contype = 'f'
  AND (
    (source_ns.nspname = 'public' AND source_table.relname IN (
      'profiles', 'establishments', 'establishment_members',
      'member_permissions', 'establishment_invitations',
      'establishment_services', 'establishment_professionals',
      'establishment_professional_services'
    ))
    OR target_table.relname IN ('users', 'profiles', 'establishments', 'establishment_members')
  )
ORDER BY source_ns.nspname, source_table.relname, constraint_name.conname;
