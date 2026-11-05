# CLAUDE.md

Projeto Farol: Torre de Controle de Projetos da **Vértice Tecnologia** (empresa fictícia, 520 pessoas, 60 projetos)
no Databricks Free Edition. Contexto completo em `README.md` e `docs/PRD.md`.

## Organização

| Pasta | Conteúdo |
|---|---|
| `ingestao/` | catálogo, carga dos dados no volume (notebook) e tabelas bronze, com verificação |
| `analises/` | análises SQL exploratórias sobre a bronze |
| `dashboards/` | dashboard AI/BI como código (`gerar_dashboard.py` gera o JSON) |
| `genie/` | espaço Genie em JSON |
| `data/` | gerador do dataset sintético e validador dos padrões |
| `tools/` | `run_sql.py` (roda `.sql` statement por statement) e `genie.py` (publica, pergunta, benchmark) |

## Databricks

- Carregue a skill `databricks-core` antes de qualquer ação, mais a do produto em uso.
- **Nunca escolha um profile sozinho:** pergunte qual usar e passe sempre `--profile`.
- Ambiente-alvo: Free Edition, serverless. Catálogo `lakehouse_vertice`; `CREATE CATALOG` só via SQL (a API do UC recusa no Free Edition).
- `read_files` lê Excel (`format => 'excel'`, `headerRows => 1`), XML (`rowTag => 'Task'`) e JSON (`multiLine`). No Excel use
  `inferColumnTypes => false` (tudo texto; `_metadata.file_name` vem codificado: `url_decode`). No XML e no JSON deixe inferir.
- Volume não aceita escrita fora de ordem: o `.xlsx` é montado em memória (`data/xlsx_simples.py`).
- Metric Views só pela API de statements (`tools/run_sql.py` já usa isso).
- Editar dashboard ou Genie direto no workspace trava o deploy: leve a mudança para o JSON do repositório.

## Dataset

`python3 data/gerar_dataset.py --saida ./dados --seed 42` e `python3 data/validar_padroes.py --dados ./dados`.

- **"Hoje" = 2026-10-16.** Nunca `current_date()`.
- **A sujeira é conteúdo, não bug.** Não conserte o gerador para limpar dado; a limpeza é na silver.
- Seed fixa. Se mudar o gerador, rode o validador, regere, recarregue a bronze e atualize os números esperados em
  `ingestao/verificacao-bronze.sql` e no README.

## Convenções

- SQL legível, não esperto. Tabelas e colunas em snake_case e português.
- Referência completa `lakehouse_vertice.<schema>.<tabela>` nos `.sql`; no JSON do dashboard, nome sem catálogo.
- Nada de `mode: development` no bundle (prefixa os schemas).
- API externa no Free Edition (serverless só resolve domínios liberados): se a chamada original falhar com `NameResolutionError`, publique o JSON em `data/`, aponte para `raw.githubusercontent.com` e registre o código original em `docs/decisoes/001-apis-externas-no-free-edition.md`.
- Responda em português, curto e direto.
