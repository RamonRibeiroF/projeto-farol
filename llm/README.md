# Prompts do Claude Code

Os prompts que construíram a etapa 3 (bundle, silver, gold, IA no texto do status, job completo, dashboard) e a etapa 4 (app, metric view, agente). Cada um é colado **inteiro** no Claude Code, aberto na
raiz do repositório, nesta ordem. Troque `<perfil>` pelo nome do seu profile do Databricks CLI
(`databricks auth profiles` lista os seus).

| # | Arquivo | O que o Claude Code faz | Como conferir |
|---|---|---|---|
| 1 | [`prompt_01.md`](prompt_01.md) | conferência da bronze e pipeline `vertice_medalhao` com a silver (7 tabelas) | 9 linhas `ok` · 4.917 tarefas · custo R$ 193,35 mi |
| 2 | [`prompt_02.md`](prompt_02.md) | gold (3 tabelas) e 10 testes que derrubam o job | 10 testes `ok` · 7 críticos · 10 em atenção · 4 melancias · estouro de R$ 6,47 mi |
| 3 | [`prompt_03.md`](prompt_03.md) | `gold.status_estruturado` (IA lê o texto do status, `MERGE` incremental) e o job completo de 6 tarefas | `ia` 163 · `regra` 2.954 · `palavra_chave` 794 · PRJ-011: `falta_sre`, 12 semanas, 57 dias · 2ª execução insere 0 linhas |
| 4 | [`prompt_04.md`](prompt_04.md) | dashboard "Projeto Farol · Portfólio" (3 páginas) como código no bundle, lendo a gold | R$ 208,6 mi · SPI 0,92 · CPI 0,96 · estouro R$ 6,5 mi · 17 em risco · 7 críticos · 4 melancias · CodeForge ×1,41 e 0% no prazo |
| 5 | [`prompt_05.md`](prompt_05.md) | app "Projeto Farol" (Databricks App, AppKit): projetos em risco e simulador de realocação, com o login do workspace | 17 de 41 em risco · 7 críticos · 4 melancias · estouro R$ 6,5 mi · simulador COL0017 → PRJ-011: saldo R$ 22,1 mil |
| 6 | [`prompt_06.md`](prompt_06.md) | metric view `gold.mv_projetos`, Genie "Farol · Diretoria" como código e a aba Perguntar no app | `MEASURE`: 0,92 · 0,97 · R$ 6,47 mi · 7 · 4 · benchmark de 20 perguntas ≥ 16/20 |

Antes do prompt 1, faça o passo a passo de [`docs/etapa-3-como-reproduzir.md`](../docs/etapa-3-como-reproduzir.md).
Antes do prompt 5, leia [`docs/etapa-4-contexto.md`](../docs/etapa-4-contexto.md) (o Claude Code também o lê).

**Como usar**

- Prompt 1: `Shift+Tab` até `plan mode on`, cole, leia o plano e só então aprove. Prompt 2 em diante: modo `auto`.
- Se o Claude Code recusar um comando por causa das chaves, rode você mesmo, com `!` na frente.
- Nunca dispare um run com outro ainda ativo: o Free Edition limita o compute serverless (`RESOURCE_EXHAUSTED`).
- Chave do data lake nunca entra em arquivo versionado.

Os prompts foram adaptados dos prompts da imersão (veja o [`NOTICE.md`](../NOTICE.md)): profile próprio, pastas do
repositório e os ajustes que o dado pediu (por exemplo, o teste 9).

**Prompt 3 · se der errado**

| Sintoma | Causa | Correção |
|---|---|---|
| tarefa da IA passa de 10 min | a IA está rodando em todos os ~3,9 mil status | só os últimos 90 dias **com bloqueio** vão para a IA; o resto é regra ou palavra-chave (`metodo`) |
| `dias_impacto` vem como texto | `ai_extract` sem schema tipado | JSON schema com `"type": "number"` e `map('version','2.0')` |
| `causa_bloqueio` nulo nas linhas da IA | leu o VARIANT sem `:response[0]` | `ai_classify(...):response[0]::STRING` |
| `TABLE_OR_VIEW_ALREADY_EXISTS` | `CREATE TABLE` sem `IF NOT EXISTS` | a tabela acumula: `CREATE TABLE IF NOT EXISTS` |
| rodou de novo e inseriu tudo outra vez | faltou o `LEFT ANTI JOIN` | o `MERGE` só recebe o que ainda não está na tabela |
| uma tarefa falhou no meio | qualquer erro numa camada | **Repair run** no workspace: refaz só a que falhou e as seguintes |
