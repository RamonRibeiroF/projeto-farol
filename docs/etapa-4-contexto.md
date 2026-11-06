# Etapa 4 · Contexto: o app, a metric view e o agente

Este arquivo é lido pelos prompts 5 e 6 (`llm/`). Ele completa o `CLAUDE.md` e o `docs/PRD.md` da raiz, que continuam
valendo. Adaptado do material da imersão (ver [`NOTICE.md`](../NOTICE.md)).

> **A pergunta da etapa: "O que vai dar errado no próximo mês? E o dono, que não escreve SQL?"**
> A etapa 3 deixou a Torre rodando sozinha toda segunda às 6h, com um dashboard. Agora ela ganha um app com URL,
> a fórmula de cada KPI num lugar só (metric view) e um agente que responde em português.

## 1. O que já existe

Catálogo `lakehouse_vertice`. O "hoje" do dataset é **16/10/2026**: nunca use `current_date()`.
O bundle `farol` está na raiz do repositório, com o job `vertice_farol` (6 tarefas: 2 de ingestão, conferência,
medalhão, testes, IA no status) e o dashboard "Projeto Farol · Portfólio".

| Tabela | O que é |
|---|---|
| `gold.projeto_situacao_atual` | fotografia de hoje por projeto: SPI, CPI, EAC, estouro previsto, margem, atraso projetado, situação (ok, atenção, crítico, concluído), farol do gerente × farol calculado, `melancia` |
| `gold.fato_projeto_semana` | projeto × semana: PV, EV, AC **acumulados**, SPI, CPI, farol, horas |
| `gold.status_estruturado` | status semanal em colunas: causa_bloqueio (change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio, nao_reportado), bloqueio, quem_destrava, dias_impacto |
| `gold.utilizacao_pessoa_semana` | pessoa × projeto × semana: papel, senioridade, utilização, horas e custo ociosos |
| `silver.entregas_fornecedor` | cada entrega de fornecedor: prometido × entregue, `em_atraso` (a CodeForge entrega com prazo ×1,41) |

## 2. O que a etapa 4 constrói

```
 job vertice_farol (o mesmo da etapa 3, mais 1 tarefa)
   ... testes_de_qualidade ─┬─ metricas_governadas ──▶ gold.mv_projetos (metric view)
   ... status_com_ia ───────┘

 Genie "Farol · Diretoria" (recurso do bundle farol) ◀── gold + mv_projetos + entregas_fornecedor
        ▲                                                 (+ gold.score_estouro_30d, se existir)
        │ aba "Perguntar"
 App "Projeto Farol" (Databricks App, AppKit, bundle próprio em farol-torre/)
        ├── leitura: config/queries/*.sql no SQL warehouse (gold)
        ├── score: rota do servidor /api/score-estouro (opcional, não quebra o build)
        └── telas: Projetos em risco · Simulador de realocação · Perguntar
```

| Prompt | Entrega |
|---|---|
| 5 · o app | `farol-torre/` (AppKit, só o plugin `analytics`): KPIs, projetos em risco com P(estouro), simulador |
| 6 · o agente | `src/metricas/metricas.sql` (`mv_projetos`), tarefa `metricas_governadas`, `genie/gerar_genie.py` + `resources/genie.genie_space.yml`; no fim, o plugin `genie` no app (aba Perguntar) |

O **modelo de previsão** (`gold.score_estouro_30d`) é opcional e fica para outro momento: o Genie só inclui a tabela se
ela existir, e o app lê o score por uma rota do servidor que responde `{disponivel:false}`. Nenhuma query de
`config/queries` usa o score.

**Contrato do score** (o Genie e o app leem daqui; nome e tipo fixos):
`projeto_id STRING, data_referencia DATE, prob_estouro_30d DOUBLE, ranking INT, faixa_risco STRING, principais_fatores STRING`.
Faixas: alto ≥ 0,5, medio ≥ 0,2, baixo.

## 3. Armadilhas medidas neste workspace (Free Edition, outubro/2026)

### Métricas e Genie

| Armadilha | O que fazer |
|---|---|
| Metric view pelo `aitools tools query` falha (`Missing required creator property 'expr'`) | O YAML perde a indentação: use a `sql_task` ou `python3 tools/run_sql.py` |
| A `sql_task` corta o arquivo em todo `;`, inclusive dentro do `$$ ... $$` | Nada de `;` dentro do YAML da metric view (nem em comment) |
| O Genie do bundle falha com `Table ... does not exist` | O Genie precisa das tabelas existindo: deploy → run → deploy |
| Editar o Genie no workspace trava o `bundle deploy` ("modified remotely") | Leve a mudança para o `genie/gerar_genie.py`; `--force` só depois |
| `CREATE OR REPLACE` | A regra do `CLAUDE.md` vale para as materialized views do pipeline. A metric view usa `CREATE OR REPLACE VIEW ... WITH METRICS` |

### App

| Armadilha | O que fazer |
|---|---|
| **O Free Edition aceita no máximo 3 apps por workspace** (`reached the maximum limit of 3 apps`) | Antes de criar, `databricks apps list`; apague um app que você não usa mais |
| O app dentro da pasta do bundle `farol` | `sync: { exclude: ["farol-torre/**"] }` no `databricks.yml` da raiz, senão o deploy sobe o `node_modules` |
| `bundle deploy` cria o app **parado** | O deploy do código é `databricks apps deploy --profile <perfil>`, dentro da pasta do app |
| O app é um **usuário do Unity Catalog** e nasce sem acesso | Depois do `bundle deploy`: `GRANT USE CATALOG`, `USE SCHEMA` e `SELECT` na gold e na silver para o service principal (`apps get` → `service_principal_client_id`). Sem isso o **build** falha no typegen com `INSUFFICIENT_PERMISSIONS` |
| Query em `config/queries/` com tabela inexistente **quebra o build** (typegen `--wait`) | Tabela que pode faltar (o score) é lida por uma rota do servidor que responde `{disponivel:false}` |
| `npm run typegen` fora do deploy dá `OFFLINE` em 0 s | Carregue o `.env` antes e rode `npm run typegen -- --wait` |
| O warehouse devolve **todo número como string** | `Number()` antes de formatar; `z.coerce.number()` no servidor |
| Arquivo `*.geniespace.json` dentro da pasta do app | `Requested node type [UNKNOWN] is not supported`: o JSON do Genie mora em `genie/`, nunca no app |
| A 1ª visita ao app pede **consentimento OAuth** ("Permission Requested") | É esperado: o app pede para usar o Genie em seu nome. Authorize uma vez |

## 4. Convenções

- Nome do app: **≤ 26 caracteres**, minúsculas e hífen (`farol-torre`).
- Leitura = `config/queries/*.sql`. Telas em português, números em `R$` e índices com 2 casas.
- No `.gitignore`: `node_modules/`, `.env`, `dist/` e `.databricks/` do app.
- Sempre `--profile <perfil>`.

## 5. Números que servem como teste (seed 42)

| O que | Valor |
|---|---|
| `mv_projetos`: SPI · CPI · estouro · críticos · melancias | 0,92 · 0,97 · R$ 6,47 mi · 7 · 4 |
| Genie "Farol · Diretoria" | 20/20 em `genie/benchmark-diretoria.json` (ensaio do material, sem o score) |
| App: em risco · críticos · melancias · estouro | **17 de 41** · 7 · 4 · R$ 6,5 mi (o "alto risco em 30 dias" fica "—" sem o modelo) |
| SREs ociosos | COL0017 e COL0018 no PRJ-007, uso de 5 a 6% |
| PRJ-011 | 12 semanas com `falta_sre`, 57 dias de impacto declarados em 90 dias |
| Simulador COL0017 (PRJ-007) → PRJ-011 | 151 h no mês · R$ 30,1 mil de ociosidade evitada · 19,0 dias recuperados · onboarding R$ 8,0 mil · saldo R$ 22,1 mil |
