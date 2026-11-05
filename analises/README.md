# Análises sobre a bronze

Consultas SQL que respondem as duas primeiras perguntas da diretoria **antes** de existir a camada silver. Servem
também como mapa da sujeira do dado, que a silver vai corrigir.

| Arquivo | Pergunta | O que mostra |
|---|---|---|
| `00-time-travel.sql` | alguém duplicou um projeto, dá para voltar? | versões Delta: `DESCRIBE HISTORY`, `VERSION AS OF`, `RESTORE` |
| `01-sql-na-bronze.sql` | o que existe, dá para confiar, quais projetos atrasam? | partes 1 a 5: `SELECT`, `CAST`, `WHERE`, `GROUP BY` e `UNION` das 3 ferramentas num rascunho (`bronze.rascunho_tarefas`) |
| `02-custo-do-atraso.sql` | quanto o atraso vai custar? | EV, CPI, EAC e estouro previsto por projeto, ao lado do farol do gerente |
| `03-leitura-de-contratos-pdf.sql` | o que o contrato diz sobre multa por atraso? | `read_files` com `binaryFile` e `ai_parse_document` |

Os arquivos são notebooks SQL do Databricks: cada comando é uma célula. Execute na ordem, uma célula por vez
(**Shift + Enter**), em vez de *Run all*: na parte 4 do `01` a primeira célula dá erro de propósito e interromperia a
execução em lote. O `02` usa a view criada na parte 5 do `01`.

O "hoje" do dataset é `DATE'2026-10-16'`: não use `current_date()`.
