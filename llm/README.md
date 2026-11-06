# Prompts do Claude Code

Os prompts que construíram a etapa 3 (bundle, silver, gold). Cada um é colado **inteiro** no Claude Code, aberto na
raiz do repositório, nesta ordem. Troque `<perfil>` pelo nome do seu profile do Databricks CLI
(`databricks auth profiles` lista os seus).

| # | Arquivo | O que o Claude Code faz | Como conferir |
|---|---|---|---|
| 1 | [`prompt_01.md`](prompt_01.md) | conferência da bronze e pipeline `vertice_medalhao` com a silver (7 tabelas) | 9 linhas `ok` · 4.917 tarefas · custo R$ 193,35 mi |
| 2 | [`prompt_02.md`](prompt_02.md) | gold (3 tabelas) e 10 testes que derrubam o job | 10 testes `ok` · 7 críticos · 10 em atenção · 4 melancias · estouro de R$ 6,47 mi |

Antes do prompt 1, faça o passo a passo de [`docs/etapa-3-como-reproduzir.md`](../docs/etapa-3-como-reproduzir.md).

**Como usar**

- Prompt 1: `Shift+Tab` até `plan mode on`, cole, leia o plano e só então aprove. Prompt 2 em diante: modo `auto`.
- Se o Claude Code recusar um comando por causa das chaves, rode você mesmo, com `!` na frente.
- Nunca dispare um run com outro ainda ativo: o Free Edition limita o compute serverless (`RESOURCE_EXHAUSTED`).
- Chave do data lake nunca entra em arquivo versionado.

Os prompts foram adaptados dos prompts da imersão (veja o [`NOTICE.md`](../NOTICE.md)): profile próprio, pastas do
repositório e os ajustes que o dado pediu (por exemplo, o teste 9).
