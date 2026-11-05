# Dashboards e Genie sobre a bronze

## Dashboard de portfólio (AI/BI)

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
