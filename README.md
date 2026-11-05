# 🔦 Projeto Farol · Torre de Controle de Projetos

Plataforma de dados no **Databricks** que responde, toda segunda de manhã, quais projetos de uma empresa estão
atrasados, quanto isso custa e o que fazer a respeito. Dos arquivos crus de Excel, ClickUp e MS Project até um
modelo de previsão e um app de decisão, com IA lendo status semanais e contratos.

**Stack:** Databricks Free Edition (serverless) · SQL · Python · Unity Catalog · Lakeflow · AI/BI Dashboards ·
Genie · MLflow · Databricks Apps · Lakebase · Claude Code

---

## 🧭 O problema

A **Vértice Tecnologia** (empresa fictícia, 520 pessoas) tem 60 projetos de clientes de varejo, financeiro, saúde,
logística e indústria. Cada gerente controla o seu do seu jeito: **20 em planilhas Excel, 25 no ClickUp e 15 no
MS Project**. O PMO consolida tudo à mão, toda sexta, e o farol do status semanal está quase todo verde.

A diretoria faz quatro perguntas:

| # | Pergunta | O que a Torre mede |
|---|---|---|
| 1 | **Quais projetos estão atrasados, e de quais clientes?** | SPI, CPI, situação, farol calculado × farol do gerente |
| 2 | **Quanto esse atraso vai me custar?** | EAC, estouro previsto, margem projetada, atraso projetado |
| 3 | **Tenho gente parada enquanto outro projeto pede gente?** | utilização por pessoa e projeto, horas ociosas, causa no status |
| 4 | **O que vai dar errado no próximo mês, e o que eu faço agora?** | probabilidade de estouro em 30 dias, entregas de fornecedor atrasadas, contratos |

Regra de corte: **SPI ou CPI < 0,9 = atenção · < 0,8 = crítico.**

## 🏛️ Arquitetura

```
 FONTES                         LAKEHOUSE · UNITY CATALOG · lakehouse_vertice              CONSUMO
 ──────                         ──────────────────────────────────────────────            ────────────────────
 Excel (20 .xlsx)          ─┐   ┌──────────┐   ┌────────────────┐   ┌───────────────┐     ┌ AI/BI Dashboards
 ClickUp (25 .json)         │   │  BRONZE  │   │     SILVER     │   │     GOLD      │     │
 MS Project (15 .xml)       ├──▶│ como veio│──▶│ as 3 ferramen- │──▶│ KPIs por      │──┬─▶├ Genie
 PMO: status semanal        │   │ read_files│   │ tas num modelo │   │ projeto e     │  │  │   (perguntas do dono)
 RH · timesheet             │   │ lê tudo  │   │ só, testado    │   │ semana        │  │  ├ App da Torre
 Financeiro · compras       │   └──────────┘   │ ai_extract nos │   │ Metric Views  │  │  │   + Lakebase (decisões)
 Contratos em PDF ──────────┘                  │ textos         │   └───────────────┘  │  └ Agente de contratos
                                               └────────────────┘                      │
                                     Modelo de estouro em 30 dias (MLflow, UC) ◀───────┘
```

Os KPIs são definidos **uma vez** (Metric Views no Unity Catalog) e reusados no dashboard, no Genie, no app e no agente.

## 🗺️ Estado do projeto

| Etapa | Foco | Status |
|---|---|---|
| 1 · Ingestão e análise | catálogo, bronze lendo Excel, JSON e XML, análises SQL, dashboard e Genie sobre a bronze | ✅ disponível |
| 2 · Ingestão automatizada | data lake (S3/boto3), API de feriados, job diário | 🚧 em construção |
| 3 · Modelagem | bundle, silver, gold, testes, IA no status, metric view, dashboard | 🚧 em construção |
| 4 · IA e produto | modelo de estouro, Genie curado, app da Torre, agente de contratos | 🚧 em construção |

### O que a etapa 1 já responde

Sobre a camada bronze, com as três ferramentas empilhadas à mão em SQL:

| Resultado | Valor |
|---|---|
| Projetos em andamento / em risco / críticos | 41 / 17 / 7 |
| Estouro previsto se nada mudar | R$ 6,47 mi |
| Faróis verdes de gerente com SPI abaixo de 0,9 ("melancias") | 4 projetos (de 32 faróis verdes) |

## 📁 Estrutura

```
ingestao/      catálogo, carga dos dados no volume e tabelas bronze, com verificação
analises/      análises SQL exploratórias sobre a bronze, até o custo do atraso
dashboards/    dashboard AI/BI de portfólio, gerado como código (JSON)
genie/         espaço Genie sobre a bronze, definido em JSON
data/          gerador do dataset sintético (seed fixa) e validador dos padrões
tools/         utilitários: rodar .sql no warehouse, publicar e testar Genie
docs/          PRD do projeto
```

## 🚀 Como executar

Sem instalar nada:

1. Crie a conta gratuita: [databricks.com/learn/free-edition](https://www.databricks.com/learn/free-edition).
2. No Databricks: **Workspace → Create → Git folder** → `https://github.com/RamonRibeiroF/projeto-farol`.
3. Abra `ingestao/01-carregar-dados` e clique em **Run all**. O catálogo é criado e os dados são gerados direto no volume.
4. Abra `ingestao/02-bronze.sql` no **SQL Editor** e rode tudo.
5. Rode as análises em ordem (`analises/`) e, por fim, `ingestao/verificacao-bronze.sql`: todas as linhas devem
   retornar `ok`.

Pelo terminal (com a [CLI do Databricks](https://docs.databricks.com/aws/en/dev-tools/cli/install) ≥ 0.250):

```bash
databricks auth login --profile SEU-PERFIL
python3 tools/run_sql.py ingestao/00-setup-catalogo.sql --profile SEU-PERFIL
python3 tools/run_sql.py ingestao/02-bronze.sql --profile SEU-PERFIL
python3 tools/run_sql.py ingestao/verificacao-bronze.sql --profile SEU-PERFIL
```

## 🗄️ O dataset

Gerado por [`data/gerar_dataset.py`](data/gerar_dataset.py): só biblioteca padrão do Python, **seed fixa 42**, cerca
de 7 MB, em menos de 1 segundo. O "hoje" do dataset é **16/10/2026**.

```bash
python3 data/gerar_dataset.py --saida ./dados --seed 42
python3 data/validar_padroes.py --dados ./dados      # junta as 3 ferramentas e confere os 5 padrões
```

| Sistema | O que vem | Linhas |
|---|---|---:|
| PMO | `projetos` · `status_semanal` (texto livre e farol) | 60 · 3.911 |
| Excel | 20 planilhas `.xlsx`, uma por projeto | 1.663 |
| ClickUp | 25 exports `.json` da API | 2.119 tarefas |
| MS Project | 15 arquivos `.xml` | 1.260 tarefas |
| RH e timesheet | `colaboradores` · `apontamentos` | 523 · 30.883 |
| Financeiro | `custos` | 23.640 |
| Compras | `entregas_fornecedor` | 640 |
| Documentos | contratos de fornecedor e SaaS (PDF) | 8 |

O dado é **simulado, não sorteado**: cada projeto avança semana a semana, e freeze, falta de SRE e rotatividade
atrasam; cada avanço consome horas e gera custo. Por isso SPI, CPI e ociosidade saem coerentes entre si. Padrões
embutidos:

1. 8 projetos com CPI caindo a partir do 6º mês (escopo cresce sem aditivo);
2. o change freeze da Black Friday (01/11 a 10/01) trava os 3 projetos de e-commerce;
3. a consultoria CodeForge entrega com prazo 41% acima do prometido e aparece escrita de 4 jeitos;
4. dois SREs seniores ociosos num projeto ainda no desenho, enquanto o status de outro pede SRE toda semana;
5. dois squads com rotatividade alta e os piores SPI da carteira.

A sujeira é proposital (formatos de data e percentual diferentes por ferramenta, linha de TOTAL, tarefas-resumo,
vírgula decimal, estornos, pessoa duplicada, status vazio) e é tratada na camada silver. O gerador não deve ser
"consertado" para limpar dado.

## 📖 Glossário

| Termo | Em uma frase |
|---|---|
| **SPI** | quanto do trabalho planejado já foi feito. 1 = no prazo; 0,8 = 20% atrás |
| **CPI** | quanto vale o que foi feito ÷ quanto custou. Abaixo de 1 = gastando mais do que entrega |
| **EAC / estouro** | quanto o projeto vai custar no fim, se seguir no ritmo de hoje; o estouro é o que passa do orçamento |
| **Melancia** | projeto verde por fora (farol do gerente) e vermelho por dentro (SPI abaixo de 0,9) |
| **Bronze · silver · gold** | o dado como chegou · limpo e unificado · pronto para responder à diretoria |
| **Unity Catalog** | o "endereço" e a portaria de todo dado: `catálogo.schema.tabela`, com dono e permissão |
| **Volume** | uma pasta de arquivos (xlsx, json, xml, pdf) dentro do catálogo |
| **Metric view** | onde mora a fórmula do KPI, para dashboard, Genie e app usarem a mesma |
| **Genie** | o chat que transforma pergunta em português em SQL sobre as tabelas |

## 🔑 Convenções

- Catálogo **`lakehouse_vertice`**, schemas `bronze` / `silver` / `gold`, volume `bronze.raw`.
- Tabelas e colunas em snake_case e português.
- "Hoje" é sempre `DATE'2026-10-16'`, nunca `current_date()`.
- Sempre `--profile` nos comandos do Databricks.
- A bronze guarda o dado **como veio**. Limpeza e integração acontecem na silver.

---

Dados e empresas fictícios.
