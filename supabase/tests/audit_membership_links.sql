-- Auditoria de vínculos (somente leitura) — establishments / establishment_members
--
-- Objetivo
-- -------
-- Identificar, sem alterar NADA, os vínculos de public.establishment_members:
--   • vínculos duplicados (mesmo estabelecimento e mesmo usuário);
--   • vínculos de proprietário (preservados em qualquer correção);
--   • vínculos sem vínculo de proprietário no estabelecimento;
--   • vínculos de usuários que já não existem em auth.users;
--   • vínculos que apontam para o estabelecimento "BarberLeo".
--
-- Uso
-- ---
-- Cole o conteúdo no SQL Editor do Supabase (projeto remoto) e execute.
-- O script é 100% de leitura: não há DELETE, UPDATE, INSERT ou DDL.
--
-- Observação
-- ----------
-- O vínculo do proprietário NUNCA deve ser removido. A regra de negócio do
-- Agenda Flow é: um usuário possui no máximo um vínculo efetivo por
-- estabelecimento, com um cargo definido nesse vínculo. O mesmo usuário pode
-- ter vínculos em empresas diferentes.

--------------------------------------------------------------------------------
-- 1. Todos os vínculos com identificação do estabelecimento e do usuário
--------------------------------------------------------------------------------
SELECT
  m.id                AS vinculo_id,
  m.establishment_id,
  e.name              AS estabelecimento,
  e.slug,
  m.user_id,
  u.email             AS usuario,
  m.role              AS cargo,
  m.is_active,
  m.created_at,
  (e.owner_id = m.user_id) AS e_proprietario_do_estabelecimento
FROM public.establishment_members m
JOIN public.establishments e ON e.id = m.establishment_id
JOIN auth.users u ON u.id = m.user_id
ORDER BY e.name, m.role, m.created_at;

--------------------------------------------------------------------------------
-- 2. Vínculos duplicados (mesmo estabelecimento e mesmo usuário)
--------------------------------------------------------------------------------
SELECT
  m.establishment_id,
  e.name            AS estabelecimento,
  m.user_id,
  u.email           AS usuario,
  count(*)          AS ocorrencias,
  string_agg(m.id::text, ', ' ORDER BY m.created_at, m.id) AS ids,
  string_agg(m.role, ', ' ORDER BY m.created_at, m.id)     AS cargos
FROM public.establishment_members m
JOIN public.establishments e ON e.id = m.establishment_id
JOIN auth.users u ON u.id = m.user_id
GROUP BY m.establishment_id, e.name, m.user_id, u.email
HAVING count(*) > 1
ORDER BY e.name, u.email;

--------------------------------------------------------------------------------
-- 3. Estabelecimentos sem vínculo de proprietário ativo
--------------------------------------------------------------------------------
SELECT
  e.id,
  e.name,
  e.slug,
  e.owner_id,
  u.email AS proprietario_cadastrado
FROM public.establishments e
LEFT JOIN auth.users u ON u.id = e.owner_id
WHERE NOT EXISTS (
  SELECT 1
  FROM public.establishment_members m
  WHERE m.establishment_id = e.id
    AND m.role = 'owner'
    AND m.is_active = true
);

--------------------------------------------------------------------------------
-- 4. Vínculos cujo usuário não existe mais em auth.users (órfãos)
--------------------------------------------------------------------------------
SELECT
  m.id AS vinculo_id,
  m.establishment_id,
  e.name AS estabelecimento,
  m.user_id,
  m.role,
  m.is_active
FROM public.establishment_members m
JOIN public.establishments e ON e.id = m.establishment_id
WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = m.user_id);

--------------------------------------------------------------------------------
-- 5. Permissões granulares que apontam para vínculos (referências antes de
--    qualquer remoção de um vínculo redundante)
--------------------------------------------------------------------------------
SELECT
  mp.id            AS permissao_id,
  mp.member_id,
  mp.permission_key,
  m.establishment_id,
  e.name          AS estabelecimento,
  m.user_id,
  u.email         AS usuario,
  m.role          AS cargo
FROM public.member_permissions mp
JOIN public.establishment_members m ON m.id = mp.member_id
JOIN public.establishments e ON e.id = m.establishment_id
JOIN auth.users u ON u.id = m.user_id
ORDER BY e.name, u.email, mp.permission_key;

--------------------------------------------------------------------------------
-- 6. Vínculos do estabelecimento "BarberLeo" (conferência direta do caso)
--------------------------------------------------------------------------------
SELECT
  m.id AS vinculo_id,
  m.user_id,
  u.email AS usuario,
  m.role AS cargo,
  m.is_active,
  m.created_at
FROM public.establishment_members m
JOIN auth.users u ON u.id = m.user_id
JOIN public.establishments e ON e.id = m.establishment_id
WHERE e.slug = 'barberleo'
ORDER BY m.created_at;

--------------------------------------------------------------------------------
-- 7. Estado da constraint de unicidade dos vínculos
--------------------------------------------------------------------------------
SELECT
  c.conname,
  c.contype,
  pg_get_constraintdef(c.oid) AS definicao,
  c.convalidated
FROM pg_constraint c
WHERE c.conrelid = 'public.establishment_members'::regclass
  AND c.contype = 'u';

--------------------------------------------------------------------------------
-- CORREÇÃO PREPARADA (NÃO EXECUTAR SEM AUTORIZAÇÃO)
--------------------------------------------------------------------------------
-- Se a consulta 2 devolver grupos duplicados, o vínculo redundante é o mais
-- ANTIGO ou o que NÃO é o de proprietário. O padrão seguro é preservar o
-- vínculo de proprietário e remover apenas os demais.
--
-- Substitua os identificadores pelos valores observados na consulta 2 e
-- rode o bloco abaixo como superusuário do projeto (dashboard postgres):
--
-- BEGIN;
--
-- -- Guarda dos vínculos que serão preservados (para conferência posterior).
-- CREATE TEMP TABLE af_vinculos_preservados AS
-- SELECT id, establishment_id, user_id, role, is_active, created_at
-- FROM public.establishment_members
-- WHERE establishment_id = '<ESTABELECIMENTO_ID>'
--   AND user_id = '<USUARIO_ID>'
--   AND (role = 'owner' OR id = '<ID_DO_VINCULO_VALIDO>');
--
-- -- Remoção APENAS dos vínculos redundantes (nunca o de proprietário).
-- DELETE FROM public.establishment_members m
-- WHERE m.establishment_id = '<ESTABELECIMENTO_ID>'
--   AND m.user_id = '<USUARIO_ID>'
--   AND NOT EXISTS (
--     SELECT 1 FROM af_vinculos_preservados p WHERE p.id = m.id
--   );
--
-- -- Confirmação: deve restar exatamente um vínculo por (estabelecimento, usuário).
-- SELECT establishment_id, user_id, count(*)
-- FROM public.establishment_members
-- GROUP BY establishment_id, user_id
-- HAVING count(*) > 1;
--
-- ROLLBACK;  -- usar ROLLBACK para uma execução de teste sem_commit permanente
