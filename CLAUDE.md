# CLAUDE.md

Projeto Farol: Torre de Controle de Projetos da **Vértice Tecnologia** (empresa fictícia, 520 pessoas, 60 projetos)
no Databricks Free Edition. Contexto completo em `README.md` e `docs/PRD.md`.

## Organização

| Pasta | Conteúdo |
|---|---|
| `ingestao/` | catálogo, carga dos dados no volume (notebook) e tabelas bronze, com verificação |
| `analises/` | análises SQL exploratórias sobre a bronze |
| `dashboards/` | dashboards AI/BI como código: `bronze/` (deploy pelo próprio script) e `gold/` (`gerar_dashboard.py` gera o JSON; deploy pelo bundle) |
| `genie/` | Genie como código: `bronze.json` (sem curadoria), `gerar_genie.py` gera `diretoria.geniespace.json` ("Farol · Diretoria", deploy pelo bundle) e `benchmark-diretoria.json` (20 perguntas com SQL de referência) |
| `data/` | gerador do dataset sintético e validador dos padrões |
| `tools/` | `run_sql.py` (roda `.sql` statement por statement) e `genie.py` (publica, pergunta, benchmark) |
| `resources/` | recursos do bundle: job `vertice_farol` e pipeline `vertice_medalhao` |
| `farol-torre/` | Databricks App da Torre (AppKit, plugin analytics): bundle próprio, fora do sync da raiz; queries em `config/queries/` |
| `src/` | `conferencia/` (sql_task da bronze), `silver/` e `gold/` (pipeline Lakeflow, um arquivo por assunto), `testes/`, `ia/` e `metricas/` (sql_task; `metricas/` cria a metric view `gold.mv_projetos`, sem `;` dentro do YAML) |

## Databricks

- Carregue a skill `databricks-core` antes de qualquer ação, mais a do produto em uso.
- **Nunca escolha um profile sozinho:** pergunte qual usar e passe sempre `--profile`.
- Ambiente-alvo: Free Edition, serverless. Catálogo `lakehouse_vertice`; `CREATE CATALOG` só via SQL (a API do UC recusa no Free Edition).
- `read_files` lê Excel (`format => 'excel'`, `headerRows => 1`), XML (`rowTag => 'Task'`) e JSON (`multiLine`). No Excel use
  `inferColumnTypes => false` (tudo texto; `_metadata.file_name` vem codificado: `url_decode`). No XML e no JSON deixe inferir.
- Volume não aceita escrita fora de ordem: o `.xlsx` é montado em memória (`data/xlsx_simples.py`).
- Metric Views só pela API de statements (`tools/run_sql.py` já usa isso).
- Editar dashboard ou Genie direto no workspace trava o deploy: leve a mudança para o JSON do repositório.
- Apps: o Free Edition aceita no máximo 3; confira com `databricks apps list` antes de criar. O app roda como service
  principal: depois do primeiro `bundle deploy` do app, rode `python tools/conceder_acesso.py --profile <perfil> --app farol-torre`
  (USE CATALOG, USE SCHEMA e SELECT na gold e na silver), senão o build falha com INSUFFICIENT_PERMISSIONS.

## Dataset

`python3 data/gerar_dataset.py --saida ./dados --seed 42` e `python3 data/validar_padroes.py --dados ./dados`.

- **"Hoje" = 2026-10-16.** Nunca `current_date()`.
- **A sujeira é conteúdo, não bug.** Não conserte o gerador para limpar dado; a limpeza é na silver.
- Seed fixa. Se mudar o gerador, rode o validador, regere, recarregue a bronze e atualize os números esperados em
  `ingestao/verificacao-bronze.sql` e no README.

## Silver (regras de limpeza)

Sete tabelas, nem uma a mais: `projetos`, `tarefas`, `status_semanal`, `custos`, `colaboradores`, `apontamentos`,
`entregas_fornecedor`. Pipeline SQL: `CREATE OR REFRESH MATERIALIZED VIEW` (nunca `CREATE OR REPLACE`),
`CREATE TEMPORARY VIEW` para o intermediário, `EXPECT ... ON VIOLATION FAIL UPDATE`, `COMMENT` em toda tabela.
Bronze pelo nome completo; silver só pelo nome. Janela dentro de agregação quebra: janela num CTE, agrega no seguinte.

| Sujeira | Onde | Decisão |
|---|---|---|
| data em `yyyy-MM-dd` e `dd/MM/yyyy` | `projetos.data_inicio` | coalesce de dois `try_to_date` |
| ferramenta de 8 jeitos; código vazio (2) | `projetos` | `excel`/`clickup`/`msproject` por LIKE; Excel cai no `PRJ-xxx` do arquivo, ClickUp no nome da lista |
| data texto ou número de série; `%` em 3 formatos (11 > 100); linha TOTAL; `'40h'` | `excel_tarefas` | `/` → `dd/MM/yyyy`, senão `date_add(DATE'1899-12-30', n)`; `least(...,100)` com flag; tira TOTAL; tira o `h` |
| datas em ms; %, fase e baseline em `custom_fields`; status de 12 jeitos | `clickup_tarefas` | `timestamp_millis`; `filter(...)[0].value`; `concluida`/`a_fazer`/`em_andamento` |
| tarefas-resumo; fase fora da tarefa; `'PT40H0M0S'` | `msproject_tarefas` | `Summary = 0`; `last_value` do OutlineLevel 1; `regexp_extract` |
| vírgula decimal (671); estorno negativo | `custos` | `replace` antes do CAST (nunca `try_cast`); mantém com flag `estorno` |
| CodeForge com 4 grafias | `entregas_fornecedor` | normaliza, guarda `fornecedor_como_veio` |
| pessoa duplicada (COL0102, COL0257, COL0433) | `colaboradores` | fica o cadastro com `papel` em minúsculas |
| farol `Verde`/`VERDE`; status vazio (51) | `status_semanal` | `lower(trim())`; flag `status_vazio`, não descarta |

Gold: 3 materialized views do pipeline (`fato_projeto_semana`, `projeto_situacao_atual`, `utilizacao_pessoa_semana`) e
`status_estruturado`, tabela comum da sql_task `src/ia/`: acumula (`CREATE TABLE IF NOT EXISTS` + `MERGE` só dos status novos),
a IA só roda nos últimos 90 dias com bloqueio e nunca é refeita.

Números de teste (seed 42): silver.tarefas 4.917 (Excel 1.643, ClickUp 2.119, MS Project 1.155) · custo real R$ 193,35 mi ·
5 entregas em atraso, todas da CodeForge · 41 projetos em andamento, 7 críticos e 10 em atenção.

## Convenções

- SQL legível, não esperto. Tabelas e colunas em snake_case e português.
- Referência completa `lakehouse_vertice.<schema>.<tabela>` nos `.sql`; no JSON do dashboard, nome sem catálogo.
- Nada de `mode: development` no bundle (prefixa os schemas).
- API externa no Free Edition (serverless só resolve domínios liberados): se a chamada original falhar com `NameResolutionError`, publique o JSON em `data/`, aponte para `raw.githubusercontent.com` e registre o código original em `docs/decisoes/001-apis-externas-no-free-edition.md`.
- Responda em português, curto e direto.
