# Instruções para Agentes — Agenda Flow

Este arquivo contém as regras obrigatórias para agentes de IA que trabalham no projeto **Agenda Flow**.

---

## 1. Propósito do projeto

Agenda Flow é um sistema de gerenciamento de agenda, clientes e finanças para cabeleireiros, barbearias e salões de beleza.

- O frontend utiliza **React 19**, **TypeScript** e **Vite 8**.
- O projeto está em fase inicial de desenvolvimento.
- O agente deve preservar a organização do código e seguir os padrões já estabelecidos.

---

## 2. Regras de documentação

Sempre que uma alteração for implementada e o usuário autorizar seu commit ou publicação no GitHub, o agente deve verificar se a documentação precisa ser atualizada.

### 2.1 README.md

O arquivo `README.md` deve ser mantido profissional, específico do Agenda Flow e bem estruturado com títulos, subtítulos, tabelas, blocos de código e listas.

Quando uma alteração afetar informações relevantes, atualize as seções apropriadas:

- **Apresentação do Agenda Flow**
- **Objetivo do projeto**
- **Funcionalidades implementadas**
- **Funcionalidades planejadas**
- **Tecnologias utilizadas**
- **Estrutura de diretórios**
- **Instruções de instalação e execução local**
- **Configuração de variáveis de ambiente** (sem divulgar credenciais)
- **Instruções de build e publicação**
- **Estado atual do desenvolvimento**

#### Regras de atualização

1. Documente apenas informações verdadeiras e verificadas.
2. Diferencie claramente funcionalidades implementadas das planejadas.
3. Não altere o `README.md` quando a mudança não afetar informações relevantes.
4. Preserve o padrão visual e organizacional existente.
5. Atualize instruções de configuração caso sejam modificadas.
6. Remova informações obsoletas.

### 2.2 CHANGELOG.md

O arquivo `CHANGELOG.md` registra mudanças relevantes no projeto e segue uma organização inspirada no padrão Keep a Changelog.

#### Categorias obrigatórias

- `Adicionado` — novas funcionalidades.
- `Alterado` — mudanças em funcionalidades existentes.
- `Corrigido` — correções de bugs.
- `Removido` — funcionalidades ou arquivos removidos.
- `Segurança` — correções ou melhorias relacionadas à segurança.

#### Regras de atualização

1. Mantenha uma seção `[Não publicado]` para alterações ainda não lançadas.
2. Não invente versões, datas ou funcionalidades.
3. Não registre alterações triviais sem relevância para o histórico do produto.
4. Atualize o changelog toda vez que uma mudança relevante for implementada.

---

## 3. Padrão para commits

Utilize mensagens de commit claras, preferencialmente seguindo o padrão **Conventional Commits**:

| Tipo | Uso |
| --- | --- |
| `feat` | Nova funcionalidade. |
| `fix` | Correção de bug. |
| `refactor` | Refatoração de código. |
| `docs` | Atualização de documentação. |
| `chore` | Ajustes de configuração ou tarefas auxiliares. |

Exemplos:

- `feat: implementa cadastro de clientes`
- `fix: corrige conflito de agendamentos`
- `refactor: reorganiza componentes da agenda`
- `docs: atualiza documentação do projeto`
- `chore: ajusta configurações do ambiente`

As mensagens devem representar fielmente as mudanças realizadas.

---

## 4. Antes de enviar alterações ao GitHub

O agente só deve publicar alterações no GitHub quando o usuário autorizar explicitamente. Antes de qualquer push, execute as seguintes verificações:

1. Revise o código modificado.
2. Execute as verificações e testes pertinentes (por exemplo, `npm run lint` e `npm run build`).
3. Verifique se há informações sensíveis expostas (credenciais, chaves, tokens, arquivos `.env`).
4. Atualize a documentação quando aplicável (`README.md` e/ou `CHANGELOG.md`).
5. Utilize o `.gitignore` corretamente.
6. Revise os arquivos incluídos no commit.
7. Não faça push se houver erros críticos conhecidos sem informar o usuário.
8. **Nunca** utilize `git push --force` sem autorização explícita.

Não publique alterações sem autorização do usuário.

---

## 5. Comandos úteis do projeto

| Comando | Descrição |
| --- | --- |
| `npm install` | Instala as dependências. |
| `npm run dev` | Inicia o servidor de desenvolvimento. |
| `npm run build` | Gera a build de produção. |
| `npm run preview` | Visualiza a build localmente. |
| `npm run lint` | Executa o linter Oxlint. |

---

## 6. Considerações finais

- Sempre mantenha o código simples e alinhado aos padrões existentes.
- Faça mudanças mínimas necessárias para atender ao objetivo.
- Valide o que foi implementado antes de solicitar autorização de publicação.
- Preserve a qualidade da documentação como parte da entrega.
