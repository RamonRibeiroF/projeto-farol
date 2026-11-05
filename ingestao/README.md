# Ingestão

Cria o ambiente no Unity Catalog, coloca os arquivos das ferramentas no volume e monta a camada **bronze**, que guarda
o dado exatamente como veio.

| Ordem | Arquivo | O que faz |
|---|---|---|
| 0 | `00-setup-catalogo.sql` | cria o catálogo `lakehouse_vertice`, os schemas `bronze`, `silver`, `gold` e o volume `bronze.raw` |
| 1 | `01-carregar-dados.py` | notebook: roda o setup, gera os arquivos direto no volume e confere os padrões do dado |
| 2 | `02-bronze.sql` | cria as 9 tabelas bronze com `read_files` (CSV, Excel, JSON e XML) |
| — | `verificacao-bronze.sql` | confere contagens e totais de referência; todas as linhas devem retornar `ok` |

## Decisões

- **Tudo entra como texto** (CSV e Excel, `inferColumnTypes => false`): se o Databricks adivinhasse o tipo, erraria as
  datas em dois formatos e o valor com vírgula decimal, e a sujeira sumiria antes de ser vista.
- **JSON e XML deixam inferir**, para manter a estrutura aninhada.
- A coluna `_rescued_data` (rede de segurança do `read_files`) é removida: nos arquivos do projeto ela vem vazia.

## Execução

No Databricks, abra `01-carregar-dados` como notebook (Git folder) e rode tudo; depois rode `02-bronze.sql` no SQL
Editor. Pelo terminal:

```bash
python3 tools/run_sql.py ingestao/00-setup-catalogo.sql --profile SEU-PERFIL
python3 tools/run_sql.py ingestao/02-bronze.sql --profile SEU-PERFIL
```

Os arquivos precisam estar em `/Volumes/lakehouse_vertice/bronze/raw/<sistema>/` (o notebook faz isso).
A verificação depende do rascunho criado na parte 5 de `analises/01-sql-na-bronze.sql`.
