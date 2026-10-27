# Agenda Flow

Sistema de gerenciamento de agenda, clientes e finanças para cabeleireiros, barbearias e salões de beleza.

![Estado do projeto](https://img.shields.io/badge/estado-em%20desenvolvimento-orange)
![Licença](https://img.shields.io/badge/licença-privativa-lightgrey)

---

## Apresentação

O **Agenda Flow** é uma plataforma SaaS de gestão para **barbearias e salões de beleza**. A aplicação centraliza em um único painel administrativo o controle da agenda de atendimentos, o cadastro de clientes, a equipe e o acompanhamento financeiro do negócio.

Cada estabelecimento é um **tenant** independente: possui seus próprios dados, funcionários e vínculos de usuários, com isolamento garantido no banco de dados por **Row Level Security (RLS)** — a arquitetura é **multi-tenant**, com um único banco PostgreSQL compartilhado e políticas que impedem o acesso cruzado entre estabelecimentos.

> **Status atual:** autenticação (Google e e-mail/senha), cadastro e seleção de estabelecimentos e o dashboard administrativo (Visão geral com navegação por módulos) estão implementados. Os módulos de agenda, serviços, equipe, clientes e financeiro constam do roadmap.

---

## Objetivo

Reduzir a dependência de planilhas, cadernos e mensagens dispersas ao oferecer um ambiente digital seguro e acessível para:

- Organizar a agenda de atendimentos.
- Manter um cadastro atualizado de clientes.
- Acompanhar a saúde financeira do negócio.
- Melhorar a experiência do profissional e do cliente final.

---

## Funcionalidades implementadas

| Funcionalidade | Descrição |
| --- | --- |
| Autenticação com Google | Login via `signInWithOAuth({ provider: 'google' })` com callback dedicado e processamento do fluxo implícito. |
| Autenticação com e-mail e senha | Login e cadastro tradicionais, com confirmação de e-mail no Supabase. |
| Gerenciamento de sessão | Contexto de autenticação (`AuthProvider`), hook `useAuth`, proteção de rotas e logout. |
| Cadastro de estabelecimentos | Formulário para cadastrar barbearias/salões (nome, tipo, contato, endereço) com criação atômica do vínculo de proprietário. |
| Seleção de estabelecimento | Tela de seleção quando o usuário possui mais de um vínculo; troca de estabelecimento pelo cabeçalho do dashboard. |
| Identificação do estabelecimento ativo | Cabeçalho e visão geral exibem o nome, tipo e papel do estabelecimento ativo, sempre a partir dos dados reais da sessão. |
| Dashboard administrativo | Área administrativa com sidebar (Visão geral, Agenda, Serviços, Equipe, Clientes, Financeiro e Configurações), boas-vindas personalizada, checklist de configuração e indicadores em estados vazios honestos. |
| Gestão de serviços (Etapa 5) | Catálogo por estabelecimento: cadastro em modal, edição, ativação/desativação lógica com confirmação, busca por nome, filtros por categoria e status, preços em centavos formatados em R$. Escritas por RPCs que validam autenticação e papel de proprietário no banco. |
| Navegação responsiva | Layout adaptativo: sidebar fixa no desktop e drawer com backdrop em tablets e smartphones. |
| Logout | Encerramento de sessão pelo menu do perfil do dashboard. |
| Roteamento protegido | Rotas públicas e protegidas com React Router e `ProtectedRoute`. |
| Integração com Supabase | Cliente `@supabase/supabase-js` configurado com tipagens do banco de dados. |
| Banco de dados multi-tenant | Schema PostgreSQL com isolamento por estabelecimento (`profiles`, `establishments`, `establishment_members`, `member_permissions`, `establishment_invitations`). |
| Row Level Security (RLS) | Políticas de segurança em todas as tabelas de dados, com funções auxiliares `SECURITY DEFINER`. |
| Provisionamento de perfis | Trigger em `auth.users` cria o perfil público de todo usuário autenticado (Google e e-mail/senha), com backfill idempotente dos perfis ausentes e função `ensure_profile()` de autocorreção. |
| Permissões versionadas | Privilégio mínimo registrado em migration: `authenticated` com leitura apenas, `anon` sem acesso, matriz de `EXECUTE` explícita por função e verificação automatizada do estado. |
| Estrutura de convites de funcionários | Tabelas e RPCs de convites com token hasheado, prazo de validade, verificação de identidade e controle de utilização única (interface em desenvolvimento). |
| Testes de integração do banco | Runner com PostgreSQL real (PGlite) que aplica as migrations e executa as asserções de RLS, multi-tenant e integridade de perfis (`npm run test:db`). |
| Auditoria do banco | Script somente leitura (`supabase/tests/verify_remote.sql`) que valida perfis, trigger, permissões, RLS e default privileges. |

> Mecanismos de autorização e isolamento: o acesso a cada linha é decidido pelas políticas RLS (papéis `owner`, `manager`, `professional`, `receptionist`), as escritas passam por RPCs `SECURITY DEFINER` com validações atômicas e o role `authenticated` tem somente leitura nas tabelas de dados.

---

### Gestão de serviços — uso e regras

- Acesse **Serviços** na sidebar do Dashboard do estabelecimento ativo. Os dados são consultados com filtro por `establishment_id` e novamente limitados pela RLS.
- Use **Novo serviço** ou **Editar**: nome (até 120 caracteres), descrição opcional (até 500), categorias **Cabelo, Barba, Estética, Unhas e Outros**, duração inteira de **1 a 1440 minutos**, preço não negativo e status ativo/inativo.
- O preço usa máscara de centavos: digitar `3550` representa **R$ 35,50**, persistidos como o inteiro `3550`. Não há exclusão definitiva; desativar preserva o registro.
- Membros ativos podem consultar o catálogo. **Somente proprietários** podem gerenciá-lo, conforme validação PostgreSQL nas RPCs `create_establishment_service`, `update_establishment_service` e `set_establishment_service_active`. `authenticated` não recebe escrita direta.
- A etapa de serviços do checklist fica concluída quando há **pelo menos um serviço ativo**. Sem serviços ativos, o link permite cadastrá-los; as demais etapas permanecem futuras.
- Para testar localmente: configure as variáveis do Supabase, execute `npm install` e `npm run dev`, autentique-se e selecione um estabelecimento. `npm run test:db` usa um banco isolado em memória; ele não popula o Supabase configurado na interface.
- Os testes de interface usam mocks; os testes SQL usam PGlite com Auth e funções criptográficas auxiliares de teste. A consulta ao histórico remoto confirma aplicação, **não substitui testes funcionais autenticados no Supabase nem valida o pgcrypto de produção**.

## Roadmap

Funcionalidades planejadas para as próximas etapas (ainda não implementadas):

- **Evolução do catálogo de serviços** — categorias personalizadas e paginação (o cadastro, edição e controle de status já estão implementados).
- **Gestão de funcionários** — profissionais do estabelecimento e papéis.
- **Horários de funcionamento** — dias e horários de atendimento.
- **Agenda de atendimentos** — visualização diária, semanal e mensal.
- **Cadastro de clientes** — histórico de atendimentos, preferências e contato.
- **Gestão financeira** — receitas, despesas e relatórios.
- **Convites de funcionários** — interface para criação e aceite de convites (as RPCs já existem no banco).
- **Permissões administrativas mais completas** — gestão de permissões granulares por membro.
- **Área administrativa global da plataforma** — visão operacional entre estabelecimentos.
- **Notificações** — lembretes por e-mail ou WhatsApp.

---

## Tecnologias utilizadas

### Core

| Tecnologia | Versão | Finalidade |
| --- | --- | --- |
| [React](https://react.dev/) | ^19.3.1 | Biblioteca para construção da interface. |
| [React DOM](https://react.dev/) | ^19.3.1 | Renderização dos componentes no navegador. |
| [TypeScript](https://www.typescriptlang.org/) | ~6.0.3 | Tipagem estática e segurança no desenvolvimento. |
| [Vite](https://vitejs.dev/) | ^8.3.4 | Build tool e servidor de desenvolvimento. |
| [React Router](https://reactrouter.com/) | ^7.x | Roteamento e navegação entre páginas. |
| [Supabase](https://supabase.com/) | — | Backend-as-a-Service: PostgreSQL, Auth, Storage e Edge Functions. |
| [@supabase/supabase-js](https://github.com/supabase/supabase-js) | ^2.x | Cliente oficial do Supabase para React/TypeScript. |

### Qualidade de código

| Tecnologia | Versão | Finalidade |
| --- | --- | --- |
| [Oxlint](https://oxc.rs/docs/guide/usage/linter.html) | ^1.88.0 | Linter rápido para React e TypeScript. |
| [Vitest](https://vitest.dev/) | ^3.2.7 | Testes unitários (React/TypeScript). |
| [PGlite](https://github.com/electric-sql/pglite) | ^0.3.7 | PostgreSQL real para os testes de integração do banco. |

### Tipagens

| Tecnologia | Versão | Finalidade |
| --- | --- | --- |
| @types/node | ^24.19.2 | Tipagens para APIs do Node.js. |
| @types/react | ^19.3.0 | Tipagens para o React. |
| @types/react-dom | ^19.3.0 | Tipagens para o React DOM. |

### Infraestrutura

| Tecnologia | Finalidade |
| --- | --- |
| [Supabase](https://supabase.com/) | Backend-as-a-Service: PostgreSQL, Auth, Storage e Edge Functions. |
| [Supabase Auth](https://supabase.com/docs/guides/auth) | Autenticação com Google e e-mail/senha (GoTrue). |
| [PostgreSQL](https://www.postgresql.org/) | Banco relacional com Row Level Security (versão 17). |
| [GitHub](https://github.com/) | Controle de versão (repositório `leo-leite-dev/project-agenda-flow`). |
| [Cloudflare Pages](https://pages.cloudflare.com/) | Hospedagem estática com deploy automático a partir do GitHub. |

---

## Estrutura de diretórios

```text
agenda-flow/
├── .env.example          # Exemplo de variáveis de ambiente
├── .env.local            # Variáveis locais (não versionado)
├── .gitignore            # Arquivos e diretórios ignorados pelo Git
├── .oxlintrc.json        # Configuração do linter Oxlint
├── CHANGELOG.md          # Histórico de mudanças do projeto
├── index.html            # Entrada HTML da aplicação
├── package.json          # Dependências e scripts do projeto
├── README.md             # Documentação principal
├── supabase/             # Configuração e migrations do Supabase
│   ├── config.toml       # Configuração do Supabase CLI
│   ├── seed.sql          # Seed de testes para ambiente local
│   ├── migrations/       # Migrations versionadas do PostgreSQL
│   │   ├── 20250127000000_initial_schema.sql
│   │   ├── 20250127000001_rls_policies.sql
│   │   ├── 20250127000002_add_establishment_type.sql
│   │   ├── 20250127000003_ensure_user_profiles.sql
│   │   └── 20250127000004_grants_and_rls_review.sql
│   └── tests/            # Testes e auditoria do banco
│       ├── verify_remote.sql   # Auditoria somente leitura (SQL Editor)
│       └── pglite/
│           ├── bootstrap.sql    # Emulação do ambiente Supabase
│           ├── run.mjs         # Runner de integração (npm run test:db)
│           └── inspect.mjs     # Diagnóstico de privilégios (npm run test:db:inspect)
├── tsconfig.app.json     # Configuração do TypeScript para a aplicação
├── tsconfig.json         # Configuração raiz do TypeScript
├── tsconfig.node.json    # Configuração do TypeScript para o Vite
├── vite.config.ts        # Configuração do Vite
├── public/               # Arquivos estáticos públicos
│   ├── favicon.svg
│   └── icons.svg
└── src/                  # Código-fonte da aplicação
    ├── components/       # Componentes reutilizáveis
    │   ├── ProtectedRoute.tsx
    │   └── dashboard/    # Componentes do dashboard administrativo
    │       ├── DashboardHeader.tsx
    │       ├── DashboardLayout.tsx
    │       ├── DashboardSidebar.tsx
    │       ├── ModulePlaceholder.tsx
    │       ├── icons.tsx
    │       └── navigation.ts
    ├── contexts/         # Contextos React
    │   ├── AuthContext.ts
    │   └── AuthProvider.tsx
    ├── env.d.ts          # Tipagens das variáveis de ambiente Vite
    ├── hooks/            # Hooks customizados
    │   └── useAuth.ts
    ├── lib/              # Utilitários e integrações
    │   ├── database.types.ts
    │   ├── supabase.ts
    │   └── utils.ts
    ├── pages/            # Páginas da aplicação
    │   ├── AuthCallbackPage.tsx
    │   ├── CreateEstablishmentPage.tsx
    │   ├── DashboardModulePage.tsx
    │   ├── DashboardPage.tsx
    │   ├── HomePage.tsx
    │   ├── LoginPage.tsx
    │   ├── SelectEstablishmentPage.tsx
    │   └── WelcomePage.tsx
    ├── App.css           # Estilos da aplicação
    ├── App.tsx           # Configuração de rotas
    ├── index.css         # Estilos globais e variáveis
    ├── main.tsx          # Ponto de entrada da aplicação React
    └── assets/           # Imagens e recursos
        ├── hero.png
        ├── react.svg
        └── vite.svg
```

---

## Instruções de instalação e execução local

### Pré-requisitos

- [Node.js](https://nodejs.org/) na versão recomendada pelo ecossistema do projeto.
- Gerenciador de pacotes `npm` (instalado junto com o Node.js).

### Passo a passo

1. Clone o repositório:

   ```bash
   git clone <url-do-repositorio>
   cd agenda-flow
   ```

2. Instale as dependências:

   ```bash
   npm install
   ```

3. Configure as variáveis de ambiente (veja a seção abaixo).

4. Inicie o servidor de desenvolvimento:

   ```bash
   npm run dev
   ```

5. Acesse a aplicação no navegador:

   ```text
   http://localhost:5173
   ```

---

## Configuração de variáveis de ambiente

O projeto utiliza um arquivo `.env.local` para armazenar configurações sensíveis e específicas do ambiente local. O repositório inclui o arquivo `.env.example` como modelo seguro, sem valores reais.

> **Atenção:** nunca commite arquivos `.env.local`, `.env` ou similares contendo credenciais. Eles já estão listados no `.gitignore`.

1. Copie o arquivo de exemplo:

   ```bash
   cp .env.example .env.local
   ```

2. Preencha os valores conforme o ambiente:

   | Variável | Descrição | Exemplo |
   | --- | --- | --- |
   | `VITE_SUPABASE_URL` | URL do projeto Supabase. | `https://xxxx.supabase.co` |
   | `VITE_SUPABASE_PUBLISHABLE_KEY` | Chave pública (`anon`) do Supabase. | `eyJhbG...` |

   > A URL pública da aplicação é detectada automaticamente via `window.location.origin`, portanto não é necessário configurar `VITE_APP_URL`.

   > Apenas a chave **publishable/anon** pode ser exposta no navegador. Nunca use `service_role` ou outras chaves privadas em variáveis `VITE_`.

### Obtendo as credenciais do Supabase

1. Acesse o painel do projeto no [Supabase Dashboard](https://supabase.com/dashboard).
2. Vá em **Project Settings > API**.
3. Copie:
   - **Project URL** → `VITE_SUPABASE_URL`
   - **anon / public** key → `VITE_SUPABASE_PUBLISHABLE_KEY`

### Configurações obrigatórias de segurança no Supabase

Para que os convites de funcionários sejam seguros, ative a confirmação dos canais de contato usados nos convites:

| Canal | Configuração no Dashboard | Local no `config.toml` |
| --- | --- | --- |
| E-mail | **Authentication > Providers > Email > Confirm email** habilitado. | `[auth.email] enable_confirmations = true` |
| Telefone | **Authentication > Providers > Phone** habilitado com provedor (Twilio, etc.) e confirmação ativa. | `[auth.sms] enable_confirmations = true` |

> Sem essas confirmações, qualquer pessoa pode criar uma conta com o e-mail/telefone de outra pessoa e aceitar o convite em seu lugar.

### Configuração do Google OAuth

1. No Supabase Dashboard, vá em **Authentication > Providers > Google**.
2. Insira o **Client ID** e **Client Secret** obtidos no Google Cloud Console.
3. Em **Authorized Redirect URIs** do Google Cloud Console, adicione:
   - `http://localhost:5173/auth/callback`
   - `https://<sua-url-de-producao>/auth/callback`
4. Em **Authentication > URL Configuration** no Supabase, adicione as mesmas URLs em **Redirect URLs**.

> **Atenção:** o Vite está configurado para usar a porta `5173` de forma fixa (`strictPort: true`). Se outro processo estiver usando essa porta, o servidor não iniciará em outra porta automaticamente. Certifique-se de que a URL local autorizada no Supabase seja exatamente `http://localhost:5173/auth/callback`.

> O Client Secret do Google nunca deve ser incluído no código ou em variáveis `VITE_`. Ele deve permanecer apenas no painel seguro do Supabase.

### Alinhamento de versão do PostgreSQL

Verifique a versão do PostgreSQL do projeto remoto em **Project Settings > Database** e atualize o `supabase/config.toml` se necessário:

```toml
[db]
major_version = 17  # ajuste para a versão do seu projeto Supabase
```

---

## Arquitetura do banco de dados

O Agenda Flow adota uma arquitetura **SaaS multi-tenant** com um único banco PostgreSQL compartilhado. Cada estabelecimento é um *tenant* e o isolamento dos dados é garantido por **Row Level Security (RLS)**.

### Diagrama de relacionamentos

```text
auth.users
    │
    ▼
profiles (1:1)
    │
    ├──< establishment_members >── establishments
    │       (N:N com papel)
    │
    ├──< member_permissions >────── establishment_members
    │       (permissões granulares)
    │
    └──< establishment_invitations >── establishments
            (convites de acesso)
```

### Tabelas principais

| Tabela | Propósito |
| --- | --- |
| `profiles` | Extensão dos usuários autenticados (`auth.users`). |
| `establishments` | Dados de cada estabelecimento (barbearia/salão). |
| `establishment_members` | Vínculo entre usuário e estabelecimento, com papel. |
| `member_permissions` | Permissões granulares opcionais por vínculo. |
| `establishment_invitations` | Convites individuais, com token hasheado e validade. |

### Arquitetura de permissões

| Schema | Conteúdo | Exposto ao PostgREST |
| --- | --- | --- |
| `public` | RPCs chamadas pelo frontend (`create_establishment`, `ensure_profile`, convites) e auxiliares de leitura usadas pelas políticas RLS. | Sim |
| `agenda_flow_private` | Funções de trigger e helper interno de provisionamento de perfil. | Não |

| Papel | Tabelas de dados | RPCs de negócio | Auxiliares de leitura |
| --- | --- | --- | --- |
| `anon` | sem acesso | sem acesso | leitura (somente do próprio chamador) |
| `authenticated` | `SELECT` | `EXECUTE` | leitura (somente do próprio tenant) |
| `service_role` | inalterado (ignora RLS) | inalterado | inalterado |

### Papéis (roles)

| Papel | Descrição |
| --- | --- |
| `owner` | Proprietário do estabelecimento. Controle total, incluindo gestão de administradores. |
| `manager` | Gestor operacional. Não pode criar outros gestores ou proprietários. |
| `professional` | Profissional de atendimento. Acesso à agenda e clientes, conforme permissões. |
| `receptionist` | Recepcionista. Acesso limitado à agenda e clientes. |

### Princípios de segurança

- RLS ativado em todas as tabelas de dados.
- Acesso negado por padrão.
- O role `authenticated` tem **somente leitura** (`SELECT`) nas tabelas de dados; nenhuma escrita direta é concedida. Todas as escritas passam por RPCs `SECURITY DEFINER` que aplicam as regras de negócio de forma atômica.
- O role `anon` não possui nenhum privilégio sobre as tabelas do projeto.
- Nenhuma função do schema `public` mantém o `EXECUTE` implícito herdado de `PUBLIC`: cada função tem sua matriz de `EXECUTE` explicitamente definida (verificada por migration e por auditoria). Exceção justificada: funções `RETURNS event_trigger` vinculadas a `pg_event_trigger` (caso real: `public.rls_auto_enable`), que só executam como event trigger e não são chamáveis por SQL nem expostas pelo PostgREST.
- Funções internas (triggers e helper de provisionamento) vivem no schema privado `agenda_flow_private`, que não é exposto ao PostgREST e não tem `USAGE` para os papéis da API.
- Funções `SECURITY DEFINER` são criadas com `search_path` vazio e referências totalmente qualificadas (`schema.objeto`), eliminando dependência de search_path manipulável.
- A criação de um estabelecimento sempre cria, de forma atômica, o vínculo do proprietário.
- Apenas proprietários podem promover/cadastrar outros proprietários ou gestores.
- Convites armazenam hash SHA-256 do token; a identidade do destinatário é verificada no aceite.
- Nenhuma chave privada do Supabase é armazenada no código ou exposta ao navegador.
- `public.profiles` não aceita `INSERT`/`DELETE` direto do role `authenticated`: perfis só são criados pelo trigger, pelo backfill ou por `ensure_profile()`.
- Concessões automáticas (`ALTER DEFAULT PRIVILEGES`) foram **neutralizadas para os objetos do projeto**: as default privileges do role `postgres` (que cria as tabelas e funções do Agenda Flow) para `PUBLIC`/`anon`/`authenticated` são revogadas — incluindo `TRUNCATE`, `REFERENCES`, `TRIGGER` e `MAINTAIN`. As default privileges de papéis internos da plataforma (ex.: `supabase_admin`) **não são alteráveis** pelo role `postgres` e, por isso, são preservadas e apenas reportadas na auditoria.

---

## Scripts disponíveis

| Comando | Descrição |
| --- | --- |
| `npm run dev` | Inicia o servidor de desenvolvimento com hot reload. |
| `npm run build` | Executa a checagem de tipos e gera a build de produção na pasta `dist/`. |
| `npm run preview` | Visualiza localmente a build de produção. |
| `npm run lint` | Executa o linter Oxlint para verificar padrões de código. |
| `npm run test` | Executa a suíte de testes unitários (Vitest). |
| `npm run test:db` | Executa os testes de integração do banco (PostgreSQL real via PGlite, sem Docker). |
| `npm run test:db:inspect` | Imprime o estado de privilégios (pg_default_acl, tabelas e matriz EXECUTE) após aplicar as migrations. |
| `npm run test:db:state` | Resume o estado final das default privileges (por proprietário) e o resultado dos helpers de auditoria. |

---

## Instruções de build e publicação

### Build de produção

```bash
npm run build
```

O comando acima executa duas etapas:

1. `tsc -b` — verifica a consistência dos tipos TypeScript.
2. `vite build` — gera os arquivos otimizados no diretório `dist/`.

### Preview local da build

```bash
npm run preview
```

### Publicação (Cloudflare Pages)

O Agenda Flow é publicado no **Cloudflare Pages**, integrado ao repositório do GitHub:

| Configuração | Valor |
| --- | --- |
| Repositório | `leo-leite-dev/project-agenda-flow` |
| Branch de produção | `main` |
| Build command | `npm run build` |
| Output directory | `dist` |
| Endereço de produção | `https://project-agenda-flow.pages.dev` |

Fluxo de publicação:

1. As alterações são enviadas para a branch `main` do GitHub.
2. A integração do Cloudflare Pages detecta o push e inicia o deployment automaticamente.
3. O build (`tsc -b && vite build`) é executado e o conteúdo de `dist/` é publicado.

Procedimento para futuras atualizações:

```bash
# 1. Validar localmente
npm run lint
npm run test
npm run build

# 2. Enviar para a branch de produção
git push origin main
```

**Variáveis de ambiente no Cloudflare Pages:** as variáveis `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` precisam estar configuradas no projeto do Cloudflare Pages (*Settings > Environment variables*), com os mesmos valores do `.env.local` — apenas a chave pública (anon/publishable).

> Antes de publicar, certifique-se de que as variáveis de ambiente de produção estão configuradas corretamente e de que nenhum arquivo sensível foi incluído no pacote.

---

## Aplicação das migrations no Supabase

As migrations estão versionadas em `supabase/migrations/`. O comando somente leitura `npx supabase migration list --linked`, executado em **27/10/2026**, confirmou as migrations **00000 a 00005 registradas como aplicadas no Supabase remoto**. A finalização desta entrega não reaplicou migrations nem modificou dados remotos.

Todas as migrations são **idempotentes**: podem ser executadas mais de uma vez sem duplicar dados, sem sobrescrever perfis existentes e sem alterar credenciais em `auth.users`.

> A verificação automatizada do banco remoto (`supabase/tests/verify_remote.sql`, somente leitura) ainda não possui evidência de execução registrada — recomenda-se executá-la no SQL Editor após qualquer mudança de schema.

### Ordem de aplicação

| Ordem | Migration | Conteúdo |
| --- | --- | --- |
| 1 | `20250127000000_initial_schema.sql` | Tabelas, índices, funções e trigger de criação de perfis. |
| 2 | `20250127000001_rls_policies.sql` | Políticas RLS de todas as tabelas. |
| 3 | `20250127000002_add_establishment_type.sql` | Coluna `type` e `create_establishment` com tipo. |
| 4 | `20250127000003_ensure_user_profiles.sql` | Provisionamento garantido de perfis, backfill idempotente, `ensure_profile()`, autocorreção em `create_establishment`, schema privado para as funções internas, hardening do `search_path` e matriz de `EXECUTE`. |
| 5 | `20250127000004_grants_and_rls_review.sql` | Privilégio mínimo nas tabelas (somente `SELECT` para `authenticated`), neutralização dos privilégios padrão herdados (`pg_default_acl`), revisão do RLS e verificação explícita de todo o estado de privilégios. |
| 6 | `20250127000005_establishment_services.sql` | Catálogo de serviços por estabelecimento: tabela com preço em centavos, constraints, índices, RLS e RPCs de escrita exclusivas do proprietário. **Aplicação confirmada pelo histórico remoto.** |

### Opção 1: Supabase CLI (recomendado)

```bash
# Login na CLI (se ainda não estiver autenticado)
npx supabase login

# Vincular o projeto local
npx supabase link --project-ref <project-ref>

# Aplicar migrations no banco remoto
npx supabase db push
```

> O histórico remoto já contém 00000–00005. Não é necessário `migration repair` nem reaplicar arquivos SQL desta entrega. Para futuras migrations, confira primeiro `npx supabase migration list --linked`; alterações no banco exigem autorização específica.

### Opção 2: SQL Editor no Dashboard

1. Acesse o [SQL Editor](https://supabase.com/dashboard/project/_/sql) do projeto.
2. Execute o conteúdo dos arquivos de migration **em ordem crescente**.
3. Ao final, execute `supabase/tests/verify_remote.sql` (somente leitura) para validar perfis, trigger, permissões e RLS.

### Verificação após a aplicação

```text
supabase/tests/verify_remote.sql
```

O script é somente leitura e falha com uma mensagem explícita caso exista:

- usuário autenticado sem perfil;
- perfil duplicado ou órfão;
- trigger `on_auth_user_created` ausente ou desabilitado;
- assinatura divergente de `create_establishment` / ausência de `ensure_profile`;
- coluna `type` ou constraint `valid_establishment_type` ausentes;
- GRANTs faltando (ou permissões de escrita em `profiles` indevidas);
- tabela pública com RLS desabilitado.

### Testes locais

```bash
# Testes unitários (Vitest)
npm run test

# Testes de integração do banco — PostgreSQL real via PGlite (sem Docker)
npm run test:db
```

O runner `npm run test:db` (`supabase/tests/pglite/run.mjs`) aplica as migrations em ordem, executa o seed de asserções e roda a auditoria `verify_remote.sql` dentro de um PostgreSQL real (PGlite). O ambiente de teste emula o Supabase: schema `auth`, `auth.users`, `auth.uid()`, `auth.role()`, roles `anon`/`authenticated`/`service_role` e o `pgcrypto` no schema `extensions`.

O arquivo `supabase/seed.sql` cria usuários e dados sintéticos e executa asserções que validam:

| Cenário | Validação |
| --- | --- |
| Login social (Google) | Trigger cria o perfil com os metadados `name`/`picture`. |
| Login e-mail/senha | Trigger cria o perfil com o metadado `full_name`. |
| Recuperação de usuário sem perfil | `ensure_profile()` e `create_establishment` recriam o perfil. |
| Cadastro de estabelecimento | Vínculo de proprietário e de membro `owner` criados atomicamente. |
| Prevenção de duplicações | Perfil e `slug` únicos garantidos. |
| Isolamento entre tenants | Membro de um estabelecimento não enxerga outro (estabelecimento, membros, permissões e perfis). |
| Escalonamento de privilégios | `manager` não cria/promove `owner`; `authenticated` não escreve perfis, vínculos nem permissões. |
| Gestão de serviços | Cadastro e edição persistidos, ativação/desativação lógica, valores inválidos recusados, isolamento entre estabelecimentos, bloqueio de gestor/profissional/outro proprietário e recusa de escrita direta. Os testes negativos não capturam a própria falha de asserção. |
| Concessões herdadas de `PUBLIC` | Nenhuma função ou tabela do schema `public` mantém privilégio padrão implícito. |

> Os cenários rodam com `SET LOCAL ROLE authenticated` e claims JWT simuladas — ou seja, com o papel e a identidade equivalentes aos de um usuário real. O dono das tabelas ignora RLS e, portanto, não serviria como teste. Um papel sonda (`agenda_flow_probe`), que recebe temporariamente as permissões de escrita, é usado para provar que as **políticas** — e não apenas o `GRANT` — bloqueiam o escalonamento.
>
> Alternativa com o stack completo do Supabase (requer Docker):
>
> ```bash
> npx supabase start
> npx supabase db reset      # aplica migrations + seed com as asserções
> ```

---

## Estado atual do desenvolvimento

- ✅ Estrutura base do projeto criada com Vite, React e TypeScript.
- ✅ Página inicial de apresentação implementada.
- ✅ Sistema de estilos inicial com identidade visual definida.
- ✅ Configuração de linting ativa.
- ✅ Integração com Supabase (`@supabase/supabase-js`) e tipagens do schema.
- ✅ Schema multi-tenant versionado em migrations.
- ✅ Row Level Security (RLS) implementado em todas as tabelas de dados.
- ✅ Estrutura de convites de funcionários com hash de token e verificação de identidade (RPCs).
- ✅ Seed e testes de integração locais para validar isolamento e permissões.
- ✅ Roteamento com React Router.
- ✅ Autenticação com Google OAuth e gerenciamento de sessão.
- ✅ Autenticação tradicional com e-mail e senha.
- ✅ Proteção de rotas e página de callback OAuth.
- ✅ Cadastro de estabelecimentos (barbearias/salões) com vínculo atômico do proprietário.
- ✅ Seleção de estabelecimento e fluxo de primeiro acesso.
- ✅ Dashboard administrativo (Visão geral) com navegação por módulos, checklist de configuração e indicadores futuros em estados vazios.
- ✅ Provisionamento garantido de `public.profiles` para usuários Google e e-mail/senha (trigger, backfill idempotente e `ensure_profile()`).
- ✅ Permissões do role `authenticated` versionadas em migration, com isolamento multi-tenant preservado.
- ✅ Testes de integração do banco executados em PostgreSQL real (`npm run test:db`), com papéis e identidades equivalentes aos de usuários reais.
- ✅ Migrations 00000–00005 registradas como aplicadas no Supabase remoto (histórico consultado em 27/10/2026).
- ✅ Gestão de serviços (Etapa 5): tela funcional, RPCs, migration 00005 e testes automatizados.
- ✅ Publicação no Cloudflare Pages integrada ao GitHub (branch `main` → `https://project-agenda-flow.pages.dev`).
- As variáveis `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` devem estar configuradas no ambiente de produção do Cloudflare Pages; a validação manual autenticada continua necessária após cada publicação.
- ⏳ Auditoria automatizada do banco remoto (`verify_remote.sql`) sem evidência de execução registrada.
- ⏳ Módulos de agenda, equipe, clientes, financeiro e configurações ainda não iniciados (estrutura de navegação já preparada).
- ⏳ Painel de funcionários e envio real de convites ainda não implementados (RPCs já existem no banco).

Consulte o arquivo [`CHANGELOG.md`](./CHANGELOG.md) para acompanhar as mudanças realizadas.

---

## Contribuição

Este é um projeto privativo. Qualquer alteração deve ser revisada e autorizada antes de ser publicada. Consulte o arquivo [`AGENTS.md`](./AGENTS.md) para as regras de documentação, commits e publicação adotadas no projeto.

---

## Licença

Projeto privativo — todos os direitos reservados.
