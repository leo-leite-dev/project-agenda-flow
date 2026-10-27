# Agenda Flow

Sistema de gerenciamento de agenda, clientes e finanças para cabeleireiros, barbearias e salões de beleza.

![Estado do projeto](https://img.shields.io/badge/estado-em%20desenvolvimento-orange)
![Licença](https://img.shields.io/badge/licença-privativa-lightgrey)

---

## Apresentação

O **Agenda Flow** é uma aplicação web pensada para simplificar o dia a dia de profissionais e negócios do setor de beleza. A plataforma centraliza o controle de agendamentos, cadastro de clientes e acompanhamento financeiro em uma única interface moderna e responsiva.

> **Status atual:** o projeto está em fase inicial de construção. A interface pública de apresentação já foi estruturada e as próximas etapas envolvem a criação dos módulos funcionais.

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
| Página inicial de apresentação | Tela de boas-vindas com identidade visual do Agenda Flow e mensagem de lançamento futuro. |
| Configuração do ambiente React + Vite | Estrutura base do projeto com React 19, TypeScript e Vite 8. |
| Padronização de estilos | Sistema de cores, tipografia e layout responsivo definidos em CSS. |
| Linting com Oxlint | Configuração de linting para React e TypeScript. |
| Roteamento com React Router | Navegação entre páginas públicas e protegidas. |
| Autenticação com Google OAuth | Login via `signInWithOAuth({ provider: 'google' })` com callback e gerenciamento de sessão. |
| Autenticação com e-mail e senha | Login e cadastro tradicionais preservados. |
| Gerenciamento de sessão | Contexto de autenticação com `AuthProvider`, hook `useAuth` e proteção de rotas. |
| Integração com Supabase | Cliente `@supabase/supabase-js` configurado com tipagens do banco de dados. |
| Banco de dados multi-tenant | Schema PostgreSQL com isolamento por estabelecimento (`profiles`, `establishments`, `establishment_members`, `member_permissions`, `establishment_invitations`). |
| Row Level Security (RLS) | Políticas de segurança em todas as tabelas de dados, com funções auxiliares `SECURITY DEFINER`. |
| Convites de funcionários | Estrutura de convites com token hasheado, prazo de validade, verificação de identidade e controle de utilização única. |
| Seed de testes local | Script `supabase/seed.sql` com cenários que validam isolamento entre tenants e prevenção de escalonamento de privilégios. |

---

## Funcionalidades planejadas

- **Agenda inteligente:** visualização diária, semanal e mensal de agendamentos.
- **Cadastro de clientes:** histórico de atendimentos, preferências e contato.
- **Gestão financeira:** controle de receitas, despesas e relatórios simplificados.
- **Notificações:** lembretes de agendamento por e-mail ou WhatsApp.
- **Autenticação e autorização:** login seguro para profissionais e administradores.
- **Painel administrativo:** configurações do negócio, serviços e colaboradores.

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

### Tipagens

| Tecnologia | Versão | Finalidade |
| --- | --- | --- |
| @types/node | ^24.19.2 | Tipagens para APIs do Node.js. |
| @types/react | ^19.3.0 | Tipagens para o React. |
| @types/react-dom | ^19.3.0 | Tipagens para o React DOM. |

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
│   └── migrations/       # Migrations versionadas do PostgreSQL
│       ├── 20250127000000_initial_schema.sql
│       └── 20250127000001_rls_policies.sql
├── tsconfig.app.json     # Configuração do TypeScript para a aplicação
├── tsconfig.json         # Configuração raiz do TypeScript
├── tsconfig.node.json    # Configuração do TypeScript para o Vite
├── vite.config.ts        # Configuração do Vite
├── public/               # Arquivos estáticos públicos
│   ├── favicon.svg
│   └── icons.svg
└── src/                  # Código-fonte da aplicação
    ├── components/       # Componentes reutilizáveis
    │   └── ProtectedRoute.tsx
    ├── contexts/         # Contextos React
    │   ├── AuthContext.ts
    │   └── AuthProvider.tsx
    ├── env.d.ts          # Tipagens das variáveis de ambiente Vite
    ├── hooks/            # Hooks customizados
    │   └── useAuth.ts
    ├── lib/              # Utilitários e integrações
    │   ├── database.types.ts
    │   └── supabase.ts
    ├── pages/            # Páginas da aplicação
    │   ├── AuthCallbackPage.tsx
    │   ├── DashboardPage.tsx
    │   ├── HomePage.tsx
    │   └── LoginPage.tsx
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
   | `VITE_APP_NAME` | Nome exibido pela aplicação. | `Agenda Flow` |
   | `VITE_APP_URL` | URL pública da aplicação. | `http://localhost:5173` |
   | `VITE_SUPABASE_URL` | URL do projeto Supabase. | `https://xxxx.supabase.co` |
   | `VITE_SUPABASE_PUBLISHABLE_KEY` | Chave pública (`anon`) do Supabase. | `eyJhbG...` |

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
5. Certifique-se de que `VITE_APP_URL` no `.env.local` aponte para a URL correta do ambiente:
   - Local: `http://localhost:5173`
   - Produção: `https://<sua-url-de-producao>`

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
- Funções auxiliares são `SECURITY DEFINER` para evitar recursão nas políticas.
- A criação de um estabelecimento sempre cria, de forma atômica, o vínculo do proprietário.
- Apenas proprietários podem promover/cadastrar outros proprietários ou gestores.
- Convites armazenam hash SHA-256 do token; a identidade do destinatário é verificada no aceite.
- Nenhuma chave privada do Supabase é armazenada no código ou exposta ao navegador.

---

## Scripts disponíveis

| Comando | Descrição |
| --- | --- |
| `npm run dev` | Inicia o servidor de desenvolvimento com hot reload. |
| `npm run build` | Executa a checagem de tipos e gera a build de produção na pasta `dist/`. |
| `npm run preview` | Visualiza localmente a build de produção. |
| `npm run lint` | Executa o linter Oxlint para verificar padrões de código. |

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

### Publicação

A publicação pode ser feita em qualquer serviço de hospedagem de aplicações estáticas, como:

- [Vercel](https://vercel.com/)
- [Netlify](https://www.netlify.com/)
- [GitHub Pages](https://pages.github.com/)
- Servidor próprio com CDN

> Antes de publicar, certifique-se de que as variáveis de ambiente de produção estão configuradas corretamente e de que nenhum arquivo sensível foi incluído no pacote.

---

## Aplicação das migrations no Supabase

As migrations estão versionadas em `supabase/migrations/` e **devem ser aplicadas apenas com autorização explícita**.

### Opção 1: Supabase CLI (recomendado)

```bash
# Login na CLI (se ainda não estiver autenticado)
npx supabase login

# Vincular o projeto local
npx supabase link --project-ref <project-ref>

# Aplicar migrations no banco remoto
npx supabase db push
```

### Opção 2: SQL Editor no Dashboard

1. Acesse o [SQL Editor](https://supabase.com/dashboard/project/_/sql) do projeto.
2. Execute o conteúdo dos arquivos de migration em ordem crescente:
   - `20250127000000_initial_schema.sql`
   - `20250127000001_rls_policies.sql`

### Testes locais

```bash
# Iniciar o stack local (Docker)
npx supabase start

# Resetar o banco e aplicar migrations + seed
npx supabase db reset
```

O arquivo `supabase/seed.sql` cria usuários e dados sintéticos e executa asserções que validam o isolamento entre estabelecimentos e a prevenção de escalonamento de privilégios.

---

## Estado atual do desenvolvimento

- ✅ Estrutura base do projeto criada com Vite, React e TypeScript.
- ✅ Página inicial de apresentação implementada.
- ✅ Sistema de estilos inicial com identidade visual definida.
- ✅ Configuração de linting ativa.
- ✅ Integração com Supabase (`@supabase/supabase-js`) e tipagens do schema.
- ✅ Schema multi-tenant planejado e migrations versionadas preparadas.
- ✅ Row Level Security (RLS) implementado em todas as tabelas de dados.
- ✅ Estrutura de convites de funcionários com hash de token e verificação de identidade.
- ✅ Seed de testes locais para validar isolamento e permissões.
- ✅ Roteamento com React Router.
- ✅ Autenticação com Google OAuth e gerenciamento de sessão.
- ✅ Autenticação tradicional com e-mail e senha preservada.
- ✅ Proteção de rotas e página de callback OAuth.
- ⏳ Migrations ainda não aplicadas ao banco de produção.
- ⏳ Módulos de agenda, clientes e finanças ainda não iniciados.
- ⏳ Painel de funcionários e envio real de convites ainda não implementados.

Consulte o arquivo [`CHANGELOG.md`](./CHANGELOG.md) para acompanhar as mudanças realizadas.

---

## Contribuição

Este é um projeto privativo. Qualquer alteração deve ser revisada e autorizada antes de ser publicada. Consulte o arquivo [`AGENTS.md`](./AGENTS.md) para as regras de documentação, commits e publicação adotadas no projeto.

---

## Licença

Projeto privativo — todos os direitos reservados.
