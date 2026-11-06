# Dashboards e Genie

## Dashboard da gold

`gold/gerar_dashboard.py` escreve `gold/portfolio.lvdash.json`: o dashboard AI/BI "Projeto Farol · Portfólio", sobre a
camada **gold**, com três páginas. **Portfólio** (KPIs da carteira em andamento, estouro previsto por projeto, SPI × CPI,
tendência semanal e o farol do gerente ao lado do farol pelo número), **Pessoas** (custo da hora parada, utilização e
causas de bloqueio lidas do status) e **Fornecedores** (prazo real ÷ prometido e entregas vencidas, sobre
`silver.entregas_fornecedor`). "Hoje" é 16/10/2026.

```bash
python3 dashboards/gold/gerar_dashboard.py        # regera o JSON
databricks bundle deploy --profile SEU-PERFIL     # publica (resources/dashboard.dashboard.yml)
```

O deploy é pelo bundle: catálogo e schema (`gold`) vêm do recurso, por isso as queries usam o nome puro das tabelas.
Editar o dashboard direto no workspace trava o próximo deploy ("modified remotely"): a mudança vai para o script,
que regera o JSON.

## Dashboard da bronze (AI/BI)

O dashboard é código: `bronze/gerar_dashboard.py` escreve `bronze/portfolio-bronze.lvdash.json` e, com `--deploy`,
publica no workspace.

```bash
python3 dashboards/bronze/gerar_dashboard.py                              # só escreve o JSON
python3 dashboards/bronze/gerar_dashboard.py --deploy --profile SEU-PERFIL
```

Os SQLs dos datasets estão em `bronze/datasets/` para quem prefere criar o dashboard pela interface. Eles dependem do
rascunho `bronze.rascunho_tarefas` (parte 5 de `analises/01-sql-na-bronze.sql`).

Editar o dashboard direto no workspace trava o próximo deploy ("modified remotely"): leve a mudança para o JSON do
repositório antes de publicar de novo.

## Genie

`../genie/bronze.json` define um espaço Genie sobre as tabelas bronze, **sem curadoria**: ele responde com
segurança, mas erra as perguntas da diretoria (conta projetos encerrados como atrasados, por exemplo). É a base de
comparação para o Genie curado das próximas etapas.

```bash
python3 tools/genie.py publicar genie/bronze.json --titulo "Farol · Bronze (sem curadoria)" --profile SEU-PERFIL
python3 tools/genie.py perguntar "Farol · Bronze (sem curadoria)" "Quanto esse atraso vai me custar?" --profile SEU-PERFIL
```
