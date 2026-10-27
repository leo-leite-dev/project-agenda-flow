# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato é baseado no [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), e este projeto adota o versionamento semântico quando houver releases oficiais.

## [Não publicado]
> **Correção do estabelecimento duplicado (Etapa 6.1):** a tela "Escolha um estabelecimento" exibia a mesma empresa duas vezes e o clique não avançava para o dashboard. A causa raiz era a consulta do frontend, que lia `public.establishment_members` sem filtrar pelo usuário autenticado — como a RLS permite que um membro leia os vínculos dos colegas do mesmo tenant (necessário para a tela de equipe), o resultado trazia o vínculo do proprietário e o do profissional (pessoas diferentes). A migration `00008` (integridade dos vínculos) foi confirmada como aplicada no Supabase remoto em 27/10/2026.
>
> **Estado da Etapa 6:** implementada e validada (lint aprovado, 115 testes unitários, 19/19 verificações de banco em PostgreSQL real e build aprovado). As migrations `00006`, `00007` e `00008` estão aplicadas no Supabase remoto. Limitações conhecidas do fluxo de convites: compartilhamento manual (sem serviço de e-mail transacional), convite vinculado ao e-mail (a autenticação por telefone não está habilitada), contexto do convite preservado apenas no navegador de origem e a ser validado no domínio de produção.
>
> **Estado da Etapa 7 (Gestão de Profissionais):** implementada e validada localmente (lint aprovado, **135 testes unitários**, **24/24 verificações de banco em PostgreSQL real** e build aprovado). As migrations `00009_professionals.sql` e `00010_profile_deletion_safety.sql` estão aplicadas no Supabase remoto. A auditoria remota somente leitura foi concluída sem falhas; o proprietário removeu intencionalmente os dados de teste e o banco está vazio de dados de aplicação.

### Corrigido

- Estabelecimento duplicado na tela de seleção: a listagem passa a ser filtrada pelo `user_id` do usuário autenticado (`getUserEstablishments`), de modo que os vínculos de outras pessoas nunca chegam ao estado da aplicação. A duplicação visual do caso "BarberLeo" vinha de dois vínculos de **usuários diferentes** (proprietário e profissional), não de um usuário com dois vínculos.
- Clique sem efeito na seleção de estabelecimento: a tela apenas atualizava o estado e não navegava. Agora o clique valida o vínculo do usuário, ativa o estabelecimento, reconhece o cargo daquele vínculo e redireciona para o dashboard.
- Redirecionamento devolvido pelo dashboard: com a lista inflada por vínculos alheios, o usuário era reencaminhado endlessmente para a tela de seleção. A decisão de onboarding agora considera o estabelecimento já escolhido.
- Escolha do estabelecimento perdida ao atualizar a página: o estabelecimento ativo passa a ser gravado no navegador (por usuário) e só é restaurado quando continua na lista autorizada do usuário.
- Efeito colateral de segurança: um profissional podia receber na interface o cargo `owner` vindo do vínculo de um colega, expondo controles administrativos na tela. Com o filtro por `user_id`, o cargo exibido é sempre o do próprio vínculo.
- Carregamento repetido dos estabelecimentos: `loadEstablishments` dependia do próprio estado e reexecutava a consulta a cada mudança; a dependência foi eliminada.
- Convite para empresa da qual a pessoa já faz parte: recusado na origem (`create_establishment_invitation`) e recusado no aceite (`accept_establishment_invitation`) sem criar segundo vínculo e sem trocar ou rebaixar o cargo — inclusive o cargo de proprietário.
- **Fluxo de convites sem transferência de propriedade**: `create_establishment_invitation` agora aceita apenas os cargos de funcionário `manager`, `professional` e `receptionist`; o cargo `owner` é recusado pelo banco (a propriedade é definida em `establishments.owner_id` e pelo trigger de criação, e nunca é transferida por convite). O proprietário atual e o vínculo de proprietário são preservados.
- **Permissões de convite validadas no PostgreSQL**: o parâmetro `p_permissions` deixou de aceitar qualquer valor. Um gerente podia informar permissões arbitrárias (inclusive administrativas) e elas eram gravadas na aceitação. Agora a RPC valida, no banco, que as chaves pertencem à matriz do projeto e que o gerente concede **apenas as permissões que possui** (delegação); o proprietário continua podendo conceder qualquer chave válida. Permissão desconhecida ou não autorizada é recusada com mensagem explícita.
- **Gerentes sem criação de administradores**: só o proprietário pode conceder o cargo de `manager`; o gerente convida apenas `professional`/`receptionist` e não consegue convidar em outro estabelecimento.
- **Convites existentes revalidados no aceite**: convites antigos (criados fora do fluxo atual) são conferidos novamente em `accept_establishment_invitation` — não conseguem conceder cargo de proprietário, permissões acima das do concedente nem chaves inexistentes, sem criar vínculo.
- **Migration 00008 sem nome fixo de constraint**: a detecção da unicidade de `public.establishment_members` passa a comentar o **objeto real existente** (constraint ou índice único, qualquer que seja o nome) em vez de um nome fixo, que fazia a migration falhar quando a unicidade já estava garantida por outro objeto. A idempotência e a ausência de exclusão de dados foram preservadas.

### Alterado

- **Tradução de cargos e permissões para pt-BR**: os cargos agora aparecem sempre como "Proprietário", "Gerente", "Profissional" e "Recepcionista" (inclusive no dashboard), e as grades de permissão das modais de convite e de cargo/permissões exibem ações em português ("Visualizar", "Editar", "Excluir") com `aria-label`/`title` descritivos ("Visualizar agendamentos", "Gerenciar equipe", ...). Os rótulos são centralizados no novo módulo de apresentação `src/lib/labels.ts`; **nenhuma chave técnica, cargo ou valor persistido no banco foi alterado**.
- **Módulo Equipe com abas**: a tela ganhou as abas "Equipe" e "Profissionais" (mesma página, sem duplicação de gestão de funcionários), com resumo contando profissionais habilitados e sem serviços.
- **Dashboard**: o papel do usuário na visão geral passou a usar o rótulo em português; o checklist e os indicadores exibem a etapa "Adicionar profissionais à equipe" com regra real de conclusão (ao menos um membro habilitado) e a aba de indicadores inclui o cartão "Profissionais" com dados reais.

### Segurança

- **Recuperação idempotente de perfis ausentes**: `supabase/tests/repair_missing_profiles.sql` insere somente perfis faltantes a partir de `auth.users`, preserva IDs e linhas existentes, não cria contas nem altera vínculos, e executa em transação.
- **Proteção contra cascata de exclusão de perfil**: a migration `20250127000010_profile_deletion_safety.sql` troca `ON DELETE CASCADE` por `RESTRICT` nas relações de proprietário, funcionário e convite. Aplicação confirmada no Supabase remoto.
- **Auditoria de FKs**: adicionado `supabase/tests/audit_profile_foreign_keys.sql` e ampliado `verify_remote.sql` para detectar cascatas perigosas, além de perfis ausentes, órfãos e falhas do trigger.

### Adicionado

- Migration `20250127000008_membership_integrity.sql`:
  - garante a constraint `UNIQUE (establishment_id, user_id)` em `public.establishment_members` (idempotente; se já existirem vínculos duplicados, a migration aborta com um relatório e **não altera nenhum registro**);
  - recusa o convite para contato que já possui vínculo ativo no mesmo estabelecimento (proteção do proprietário);
  - reorganiza o aceite de convite: identidade verificada antes da verificação de vínculo e mensagem explícita de que a pessoa já pertence ao estabelecimento;
  - mantém a matriz de privilégios (`authenticated` somente leitura nas tabelas de dados, `EXECUTE` das RPCs apenas para `authenticated`) e não enfraquece nenhuma política RLS.
  - helper interno `agenda_flow_private.validate_team_grants(uuid, text, text[], uuid)` (schema privado, sem `USAGE` para `anon`/`authenticated`/`service_role`): valida no PostgreSQL o cargo e as permissões concedidos por um convite, tanto na criação quanto no aceite;
- Cenário automatizado no runner do banco (`npm run test:db`): a migration 00008 é aplicada em um banco isolado com a unicidade garantida por uma **constraint renomeada** e por um **índice único com nome próprio**, provando que a migration não falha, não exclui vínculos e mantém a unicidade em vigor;
- Novos cenários de asserção no banco: tentativa de convidar outro proprietário (pelo proprietário e pelo gerente), gerente tentando conceder permissões superiores às próprias, permissão inválida, delegação válida do gerente, aceite de convites antigos sem escalonamento de privilégios, preservação do vínculo e de `establishments.owner_id` e isolamento entre estabelecimentos;
- Testes de interface que travam a matriz de permissões e os cargos de convite do frontend contra a matriz validada pelo banco.
- Auditoria somente leitura dos vínculos (`supabase/tests/audit_membership_links.sql`): lista todos os vínculos, os grupos duplicados, os estabelecimentos sem proprietário ativo, os vínculos órfãos e as permissões que apontam para cada vínculo — com a correção SQL preparada e comentada (não executada).
- Seção de integridade dos vínculos na auditoria `supabase/tests/verify_remote.sql` (unicidade, duplicados e proprietário ativo por estabelecimento).
- Testes automatizados: deduplicação e resolução do estabelecimento ativo, persistência da escolha por usuário, listagem filtrada pelo usuário autenticado, seleção com redirecionamento para o dashboard, vínculo inativo sem acesso e cenário de Isolamento Multi-Tenant; no banco, unicidade do vínculo, recusa de convite para o próprio proprietário, ausência de vínculo duplicado e preservação do cargo.
- **Gestão de Profissionais (Etapa 7 — migration `20250127000009_professionals.sql`, aplicada no remoto em 27/10/2026)**:
  - tabelas `establishment_professionals` (habilitação do membro com `accepts_appointments` para pausa de atendimentos) e `establishment_professional_services` (associação N:N com `UNIQUE (professional_id, service_id)`);
  - **integridade entre tenants garantida por FKs compostas** (`(member_id, establishment_id)`, `(professional_id, establishment_id)`, `(service_id, establishment_id)`) — um serviço de uma empresa não pode ser associado a um profissional de outra nem contornando a aplicação;
  - RPCs exclusivas do proprietário: `set_establishment_professional` (habilitar/pausar, recusa vínculo desativado e é idempotente por membro), `add_establishment_professional_service` (exige serviço ativo do mesmo tenant, recusa duplicado) e `remove_establishment_professional_service`;
  - RLS de leitura para membros do tenant, `authenticated` somente leitura nas tabelas novas, `anon` sem acesso e matriz de `EXECUTE` explícita;
  - a pausa/reação de atendimentos NÃO altera vínculo, cargo nem permissões administrativas; associações e histórico são preservados (nada é excluído);
  - interface: aba "Profissionais" no módulo Equipe com habilitação por seleção de membro, contagem de serviços, pausa/retomada, modal "Serviços do profissional" com o catálogo real do estabelecimento (serviços inativos não recebem novas associações, associações existentes permanecem visíveis) e estados de carregamento/vazio/erro/sucesso;
  - dashboard com quantidade real de profissionais habilitados e sem serviços, e o checklist liberando a etapa de profissionais com regra real;
  - testes de banco (seed) dos cenários 55 a 68: habilitação com cargos distintos, idempotência, autorização (gerente/profissional/dono alheio são recusados), associações N:N, duplicado, cross-tenant (RPC + FK composta em nível superusuário), serviço inativo, vínculo desativado, escrita direta recusada e leitura isolada por RLS — com vacuidade validada por mutação das guardas;
  - testes de interface para a aba, habilitação, modal de serviços (inativo bloqueado para novas associações), modo somente leitura para não-proprietários;
  - auditoria `verify_remote.sql` estendida às tabelas e RPCs de profissionais (RLS, campos cruzados e matriz de EXECUTE).

> **Estado da Etapa 6:** implementada e validada localmente (lint, 83 testes unitários, 12/12 verificações de banco em PostgreSQL real e build). As migrations `00006` e `00007` permanecem **pendentes de aplicação no Supabase remoto** — a gestão de equipe, os convites e o onboarding priorizado por convite não funcionam em produção até a aplicação. Limitações conhecidas do fluxo de convites: compartilhamento manual (sem serviço de e-mail transacional), convite vinculado ao e-mail (a autenticação por telefone não está habilitada), contexto do convite preservado apenas no navegador de origem e a ser validado no domínio de produção.

### Adicionado

- Gestão de equipe, convites e permissões (Etapa 6 — migrations 0006 e 0007 aplicadas no Supabase remoto em 27/10/2026):
  - migration `20250127000006_team_management.sql`, que **reaproveita** `establishment_members`, `member_permissions` e `establishment_invitations` (nenhuma tabela de funcionários criada);
  - RPCs `update_establishment_member_role`, `set_establishment_member_active` e `set_establishment_member_permissions` — SECURITY DEFINER, `search_path` vazio, `auth.uid()` validado e autorização de proprietário conferida no banco;
  - reimplementação de `create_establishment_invitation` (recusa de convite pendente duplicado e validação de cargo) e de `accept_establishment_invitation` (bloqueio de linha `FOR UPDATE`, serializando aceites concorrentes);
  - policy de `establishment_members` ajustada: o vínculo desativado não enxerga mais o estabelecimento;
  - privilégio mínimo: `authenticated` mantém apenas `SELECT` em `establishment_members`, `member_permissions` e `establishment_invitations`;
  - tela **Equipe** com listagem real (nome, avatar, cargo, situação, data de entrada e permissões), busca por nome, filtros por cargo e situação, convites pendentes com situação real e cancelamento;
  - convite por e-mail com link seguro exibido uma única vez, compartilhamento manual por e-mail (`mailto:`) ou WhatsApp (`wa.me`), sem envio automático e sem simular envio;
  - fluxo de aceite em `/convite/:token`, exigindo autenticação e preservando o link pelo login (inclusive OAuth do Google);
  - edição de cargo e permissões refinadas (somente chaves já previstas no schema), desativação/reativação lógica do vínculo com confirmação;
  - preservadas as restrições de cargo do banco: gerentes não promovem a proprietário, profissionais e recepcionistas não administram cargos ou permissões, e o proprietário não altera o próprio cargo nem o próprio vínculo;
  - correção do onboarding (migration 20250127000007_pending_invitations.sql): a RPC get_my_pending_invitations lista os convites pendentes do e-mail confirmado do próprio usuário, e a decisão de tela inicial passa a priorizar o aceite do convite — um funcionário convidado nunca é obrigado a criar um estabelecimento;
  - o contexto do convite é preservado no sessionStorage durante cadastro, confirmação de e-mail, login (e-mail/senha e Google) e atualização da página;
  - ações administrativas do catálogo de serviços passaram a ser exibidas apenas ao proprietário (a garantia permanece no banco).

## [0.2.0] - 2026-10-27

Etapa 5 — Gestão de Serviços. Migration 00005 confirmada no histórico remoto por `supabase migration list --linked`; nenhuma migration reaplicada nesta entrega.

### Adicionado

- Gestão de serviços (Etapa 5):
  - migration `20250127000005_establishment_services.sql`: tabela `establishment_services` com preço em centavos inteiros, categoria, duração e status; constraints (`duration_minutes > 0`, `price_cents >= 0`, categorias válidas, limite de descrição), índices por estabelecimento/categoria/status e índice único de nome por tenant (insensível a maiúsculas e espaços);
  - RLS habilitado com policy de SELECT para membros ativos do estabelecimento; nenhuma policy de escrita — todas as operações de escrita passam pelas RPCs `create_establishment_service`, `update_establishment_service` e `set_establishment_service_active` (SECURITY DEFINER, `search_path` vazio, autenticação obrigatória e verificação de papel de **proprietário** no banco);
  - `GRANT SELECT` na tabela e `GRANT EXECUTE` das RPCs apenas para `authenticated` (sem privilégios para `anon`);
  - página Serviços no dashboard: listagem com nome, categoria, duração, preço formatado em reais e status; busca por nome, filtros por categoria e status; estados de carregamento, erro e lista vazia; feedback de sucesso/falha;
  - formulário em modal com validação client-side e server-side: nome obrigatório, descrição opcional, categoria, duração em minutos (> 0) e preço em reais com máscara de digitação convertida para centavos;
  - ativação/desativação lógica (sem exclusão) com diálogo de confirmação;
  - checklist do dashboard reflete progresso real: a etapa de serviços é contabilizada como concluída quando o estabelecimento possui pelo menos um serviço ativo (regra documentada);
  - testes: unitários (listagem, filtros, validações, edição, ativação/desativação, erros do banco) e de banco com papéis equivalentes a usuários reais (proprietário, gestor, profissional, usuário sem vínculo, outro tenant, `anon`), incluindo isolamento entre estabelecimentos e recusa de escrita direta sem privilégios.

### Corrigido

- Validação da duração no formulário recusa minutos fracionados em vez de truncá-los silenciosamente.
- Etapa de serviços pendente no checklist leva ao cadastro, sem indicar que o módulo funcional está "Em breve".
- Testes SQL negativos de serviços falham efetivamente quando uma operação inválida é aceita, sem capturar a própria exceção de falha.

### Alterado

- README atualizado com operação do catálogo, regras de autorização, preços em centavos, checklist e confirmação do histórico remoto de 00005, preservando a distinção entre testes locais e validação manual/remota.

## [0.1.0] - 2026-10-27

Primeira versão publicada do Agenda Flow: autenticação, cadastro e seleção de
estabelecimentos, dashboard administrativo e estrutura multi-tenant com
segurança no banco de dados.

### Adicionado

- Estrutura inicial do projeto com Vite, React 19 e TypeScript.
- Página inicial de apresentação do Agenda Flow (`App.tsx`).
- Sistema de estilos base com variáveis CSS e layout responsivo.
- Configuração do linter Oxlint para React e TypeScript.
- Arquivo `.env.example` com as variáveis de ambiente iniciais.
- Arquivo `README.md` com documentação profissional do projeto.
- Arquivo `CHANGELOG.md` para registro de mudanças relevantes.
- Arquivo `AGENTS.md` com regras permanentes de documentação, commits e publicação.
- Integração com Supabase através do pacote `@supabase/supabase-js`.
- Migrations SQL versionadas para o schema multi-tenant:
  - Tabelas `profiles`, `establishments`, `establishment_members`, `member_permissions` e `establishment_invitations`.
  - Funções auxiliares atômicas: `create_establishment`, `create_establishment_invitation`, `accept_establishment_invitation`, `cancel_establishment_invitation`.
- Políticas Row Level Security (RLS) em todas as tabelas de dados.
- Seed local `supabase/seed.sql` com testes de isolamento entre tenants e prevenção de escalonamento de privilégios.
- Tipagens TypeScript do schema em `src/lib/database.types.ts`.
- Variáveis de ambiente `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY`.
- Revisão de segurança nas migrations: normalização de telefone, verificação de e-mail/telefone confirmados e rejeição de convites para usuários já membros.
- Roteamento com React Router (`react-router-dom`).
- Contexto de autenticação (`AuthContext`/`AuthProvider`) e hook `useAuth`.
- Página de login (`LoginPage`) com botão "Continuar com Google" e formulário de e-mail/senha.
- Página de callback OAuth (`AuthCallbackPage`) para processar o retorno do Google.
- Página de dashboard provisória (`DashboardPage`) protegida por autenticação.
- Componente `ProtectedRoute` para proteger rotas privadas.
- Tratamento de erros, estados de carregamento e logout.
- Ajuste no trigger `handle_new_user` para reconhecer campos `name` e `picture` comuns no OAuth do Google.
- Migration `20250127000002_add_establishment_type.sql` adicionando coluna `type` à tabela `establishments`.
- Páginas `WelcomePage`, `CreateEstablishmentPage` e `SelectEstablishmentPage`.
- Fluxo de primeiro acesso após login (cadastro, seleção ou dashboard).
- Função `create_establishment` atualizada para aceitar tipo e dados de endereço.
- Estado de estabelecimentos no `AuthProvider` com carregamento e seleção.
- Migration `20250127000003_ensure_user_profiles.sql`:
  - função interna `public.upsert_profile_from_auth_user(uuid)` (`SECURITY DEFINER`, com `EXECUTE` revogado de `PUBLIC`);
  - trigger `on_auth_user_created` recriado de forma idempotente em `auth.users`, com falhas convertidas em `WARNING` para nunca bloquear a autenticação;
  - função pública `public.ensure_profile()` que garante o perfil do usuário autenticado de forma idempotente;
  - backfill dos perfis ausentes a partir de `auth.users` (apenas registros faltantes, sem sobrescrever dados existentes);
  - `create_establishment` passa a garantir o perfil do proprietário antes do `INSERT`, eliminando o erro de integridade `23503`;
  - remoção da sobrecarga obsoleta de `create_establishment` (assinatura sem `p_type`);
  - verificação e criação idempotente da coluna `type` e do constraint `valid_establishment_type` (estado da migration `20250127000002`);
  - hardening de todas as funções `SECURITY DEFINER` do schema: `search_path` vazio com referências totalmente qualificadas (`schema.objeto`);
  - schema privado `agenda_flow_private` (não exposto ao PostgREST) recebendo as funções internas — `upsert_profile_from_auth_user`, `handle_new_user`, `handle_new_establishment` e `set_updated_at` — com `USAGE` revogado para `PUBLIC`, `anon`, `authenticated` e `service_role`; os triggers correspondentes foram recriados apontando para o schema privado e as cópias remanescentes no schema `public` foram removidas;
  - recriação das funções de convite (`create_establishment_invitation`, `accept_establishment_invitation`, `cancel_establishment_invitation`) com `search_path = public, extensions`;
  - garantia idempotente da extensão `pgcrypto` e verificação, no momento da aplicação, de que `gen_random_bytes()`/`digest()` são resolvíveis com o `search_path` usado pelas RPCs de convites;
  - matriz completa de `EXECUTE` por função, aplicada **no mesmo ponto em que cada função é criada** (sem janela de exposição entre migrations).
- Migration `20250127000004_grants_and_rls_review.sql`:
  - privilégio mínimo nas tabelas: `authenticated` recebe somente `SELECT`; nenhuma escrita direta é concedida; `anon` fica sem qualquer acesso;
  - `REVOKE CREATE ON SCHEMA public` para `PUBLIC`, `anon` e `authenticated`;
  - re-habilitação explícita de RLS em todas as tabelas de dados;
  - **neutralização dos privilégios padrão já existentes em `pg_default_acl`**, com distinção por proprietário: as entradas que concediam DML automático a `PUBLIC`/`anon`/`authenticated` para novas tabelas e sequences do schema `public` são revogadas **para os papéis do projeto** (o role que executa a migration e o `postgres`), incluindo `TRUNCATE`, `REFERENCES`, `TRIGGER` e `MAINTAIN`; as default privileges de papéis internos da plataforma (ex.: `supabase_admin`), que o role `postgres` não pode alterar, são preservadas e apenas reportadas na auditoria. Para funções, o `EXECUTE` padrão para `PUBLIC` — que é o *default global do sistema* e não uma entrada de `pg_default_acl` — é removido pela forma **global** do comando (`ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`, sem `IN SCHEMA`), aplicada apenas ao role dono dos objetos do projeto. Os privilégios padrão dos roles gerenciados pela plataforma Supabase não são alterados;
  - bloco de verificação que falha de forma explícita se o estado de privilégios divergir do esperado (funções, schema privado, tabelas, RLS, `pg_default_acl` e concessões herdadas de `PUBLIC`).
- Script de auditoria somente leitura `supabase/tests/verify_remote.sql` (perfis, trigger, funções, permissões, RLS, `pg_default_acl` e concessões herdadas de `PUBLIC`).
- Runner de integração `supabase/tests/pglite/` que executa as migrations, o seed de asserções e a auditoria em um PostgreSQL real (PGlite), sem depender de Docker (`npm run test:db`).
- Ferramenta de diagnóstico `supabase/tests/pglite/inspect.mjs` (`npm run test:db:inspect`) que imprime o estado de `pg_default_acl`, os privilégios por tabela e a matriz de `EXECUTE` antes e depois das migrations.
- Emulação do ambiente Supabase para os testes (`supabase/tests/pglite/bootstrap.sql`): schema `auth`, `auth.users`, `auth.uid()`, `auth.role()`, roles `anon`/`authenticated`/`service_role`, `pgcrypto` no schema `extensions` e as concedões padrão da plataforma (`pg_default_acl` concedendo DML a `anon`/`authenticated`).
- Chamada `ensureProfile()` no `AuthProvider`, executada antes do carregamento dos estabelecimentos, como rede de segurança para contas criadas antes do trigger.
- Testes automatizados: `src/lib/__tests__/ensureProfile.test.ts` e `src/contexts/__tests__/AuthProvider.test.tsx`.
- Seed local reescrito: cenários de RLS executados com `SET LOCAL ROLE authenticated` e claims JWT simuladas (as políticas passam a ser realmente avaliadas), fluxo real de convite (criação + aceite por RPC), papel sonda para provar o bloqueio de escalonamento na camada de política e novos cenários de integridade de perfis.
- Dashboard administrativo (etapa 4):
  - layout compartilhado (`DashboardLayout`) com sidebar, cabeçalho e área principal, incluindo os guards existentes (carregamento, ausência de estabelecimento e seleção);
  - sidebar com Visão geral, Agenda, Serviços, Equipe, Clientes, Financeiro e Configurações — módulos não implementados aparecem com o selo "Em breve" e apontam para páginas honestas de placeholder, sem rotas quebradas;
  - cabeçalho com o nome do estabelecimento ativo (dados reais do Supabase), identificação do usuário, área de notificações desabilitada ("disponível em breve"), troca de estabelecimento e menu de perfil com logout funcional;
  - visão geral com boas-vindas personalizada, checklist de configuração (horários, serviços, equipe e agenda), indicadores futuros em estados vazios honestos e resumo dos dados reais do estabelecimento;
  - responsividade: drawer com backdrop em telas menores, transições discretas e navegação por teclado com foco visível;
  - componentes reutilizáveis em `src/components/dashboard/` (layout, sidebar, header, placeholder, ícones SVG inline e configuração de navegação) para as próximas etapas;
  - rota `/dashboard/:module` para os módulos planejados, com redirecionamento de rotas desconhecidas para a Visão geral.
- Testes do dashboard (`src/pages/__tests__/DashboardPage.test.tsx`): dados reais do estabelecimento, checklist, estados vazios, navegação entre módulos, redirecionamentos de guarda, logout e módulo desconhecido.

---

### Corrigido

- Redirect do Google OAuth agora utiliza `window.location.origin`, garantindo que o callback ocorra no mesmo domínio da aplicação (localhost em desenvolvimento e domínio de produção em deploy).
- `AuthCallbackPage` aguarda o carregamento dos estabelecimentos e redireciona para `/welcome`, `/dashboard` ou `/select-establishment` conforme a situação do usuário.
- Vite configurado com porta fixa `5173` (`strictPort: true`) para evitar que o servidor mude silenciosamente para outra porta e invalide as URLs de redirect autorizadas no Supabase.
- Removida variável de ambiente obsoleta `VITE_APP_URL` de `.env.example`, `src/env.d.ts` e documentação.
- Corrigida condição de corrida no callback OAuth do Google (`AuthCallbackPage`): a página agora aguarda a finalização da inicialização assíncrona da sessão no `AuthProvider` (`isLoading === false`) antes de decidir o redirecionamento, eliminando o falso erro "Não foi possível recuperar a sessão após o login." disparado pelo timeout fixo anterior. O cliente Supabase foi explicitamente configurado com `flowType: 'implicit'`, `detectSessionInUrl: true`, `persistSession: true` e `autoRefreshToken: true`, compatível com o retorno `#access_token=...`. Não é utilizado `exchangeCodeForSession` (destinado ao fluxo PKCE) e os tokens da URL não são lidos manualmente.
- Corrigido o erro de integridade `23503` (`establishments_owner_id_fkey`) que impedia o cadastro de estabelecimentos: usuários autenticados que não possuíam registro em `public.profiles` não conseguiam vincular o proprietário. A causa raiz era a ausência do registro de perfil para contas criadas sem o trigger de `auth.users` ativo (o perfil é referenciado pela FK de `establishments.owner_id` e de `establishment_members.user_id`). A correção é garantida no banco (trigger recriado, backfill idempotente e autocorreção em `ensure_profile()`/`create_establishment`), sem depender de ajustes improvisados no frontend.
- Corrigido um bug latente no fluxo de convites: as funções `create_establishment_invitation` e `accept_establishment_invitation` (migration `20250127000000`) declaravam `SET search_path = public` e chamavam `gen_random_bytes()`/`digest()`, que pertencem ao `pgcrypto`. No Supabase o `pgcrypto` é instalado no schema `extensions`, que não faz parte de um `search_path` restrito a `public` — a criação de convites falhava em runtime com `function gen_random_bytes(integer) does not exist`. As funções foram recriadas com `SET search_path = public, extensions`, que resolve o `pgcrypto` em qualquer das duas instalações.

---

### Segurança

- `public.profiles` não pode mais ser escrito diretamente pelo role `authenticated` (sem `INSERT`/`DELETE`): perfis são criados exclusivamente por trigger, backfill ou `ensure_profile()`, impedindo falsificação de identidade e de vínculos de tenancy.
- O role `authenticated` passou a ter acesso **somente leitura** às tabelas de dados. As escritas diretas foram removidas das concessões e passaram a ocorrer exclusivamente por RPCs `SECURITY DEFINER`, que aplicam as invariantes de negócio de forma atômica.
- O role `anon` não possui mais nenhum privilégio sobre as tabelas do projeto.
- Funções internas de trigger e de apoio têm `EXECUTE` revogado de `PUBLIC`, `anon` e `authenticated`.
- Nenhuma função do schema `public` mantém o `EXECUTE` implícito herdado de `PUBLIC`; a matriz de `EXECUTE` é explícita por função e verificada por migration e por auditoria.
- Funções `SECURITY DEFINER` recriadas com `search_path` vazio e referências totalmente qualificadas, eliminando dependência de search_path manipulável.
- `REVOKE CREATE ON SCHEMA public` para `PUBLIC`, `anon` e `authenticated`, impedindo criação de objetos no schema exposto.
- Removido o `ALTER DEFAULT PRIVILEGES` que concedia DML automático a novas tabelas públicas **e neutralizadas as entradas já existentes em `pg_default_acl`** dos papéis do projeto (inclusive as criadas pela plataforma Supabase no provisionamento), de modo que qualquer tabela nova no schema `public` exija uma migration própria com as permissões necessárias. As default privileges de papéis internos da plataforma (`supabase_admin`), que o role `postgres` não tem permissão para alterar, são preservadas.
- Corrigido falso positivo na verificação de default privileges: a checagem passou a considerar o **proprietário** da default privilege. Entradas de `supabase_admin` (infraestrutura da plataforma, não alterável pelo `postgres`) são reportadas na auditoria, mas não bloqueiam a migration; entradas de `postgres` (objetos do Agenda Flow) continuam sendo removidas e verificadas em todos os tipos de privilégio.
- Corrigido falso positivo na auditoria de funções públicas do schema `public`: funções `RETURNS event_trigger` vinculadas a `pg_event_trigger` (caso real do projeto Supabase: `public.rls_auto_enable`, usada para habilitar RLS automaticamente) deixavam de ser apontadas. A exceção é específica — exige o tipo `event_trigger` **e** o vínculo real em `pg_event_trigger` —, as referenciadas continuam intactas e a auditoria global das funções comuns segue valendo. A regra foi centralizada em `agenda_flow_private.publicly_exposed_functions()` e ganhou teste de regressão.
- Corrigido o tratamento dos privilégios padrão de funções: o `EXECUTE` para `PUBLIC` é o default global do sistema e não era removido pelo comando per-schema (um *no-op* silencioso). Passou a ser revogado pela forma global do comando, e a migration verifica o efeito real criando e testando uma função sonda — o bloqueio explícito de `EXECUTE` das funções privilegiadas e a política de menor privilégio para novas funções foram preservados.
- Funções internas confinadas ao schema privado `agenda_flow_private`, que não é exposto ao PostgREST e não concede `USAGE` aos papéis da API.
- Script `supabase/tests/verify_remote.sql` audita, em ambiente remoto, a existência de perfis, o trigger, as permissões, o isolamento do schema privado, os `pg_default_acl`, a habilitação de RLS em todas as tabelas públicas e a ausência de concessões herdadas de `PUBLIC`.

---

### Notas

- Esta é a primeira versão publicada do Agenda Flow.
- Alterações triviais, como ajustes de formatação sem impacto funcional, não serão registradas no changelog.
