# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato é baseado no [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), e este projeto adota o versionamento semântico quando houver releases oficiais.

## [Não publicado]

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

---

### Notas

- Este projeto ainda não possui versões oficiais publicadas.
- Alterações triviais, como ajustes de formatação sem impacto funcional, não serão registradas no changelog.
