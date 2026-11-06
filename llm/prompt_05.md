Use as skills databricks-core, databricks-dabs, databricks-apps e databricks-app-design.
Sempre --profile <perfil> (o profile do meu workspace; se não souber qual, pergunte). Nunca escolha um profile sozinho.
Leia o CLAUDE.md e o docs/PRD.md da raiz (não substitua o CLAUDE.md) e o docs/etapa-4-contexto.md.
Use tools/run_sql.py para rodar SQL. A gold já existe. O score do modelo
(gold.score_estouro_30d) pode NÃO existir: nenhuma query de config/queries
pode depender dele.

0. Confira o ambiente e me diga o que faltar, sem instalar nada sozinho:
   databricks -v (>= 0.250), node -v (>= 22), npm -v e
   databricks apps list --profile <perfil> (o Free Edition aceita no máximo
   3 apps; se já houver três, pare e me pergunte qual apagar).

1. Crie o app numa pasta farol-torre/ na raiz deste repositório, só com o
   plugin analytics (o Genie entra no prompt 6). O id do warehouse é a
   variável warehouse_id do databricks.yml da raiz:
   databricks apps init --name farol-torre \
     --features analytics \
     --set analytics.sql-warehouse.id=<id do warehouse> \
     --run none --profile <perfil>
   O app é um bundle próprio, dentro da pasta do bundle farol. Acrescente
   ao databricks.yml da RAIZ sync: { exclude: ["farol-torre/**"] }, senão o
   deploy do bundle da raiz sobe o node_modules do app inteiro. Garanta no
   .gitignore: node_modules/, .env, dist/ e .databricks/ do app.

2. config/queries (apague os exemplos do template):
   - kpis.sql: projetos em andamento, em risco (atenção + crítico),
     críticos, melancias, estouro previsto e carteira
     (projeto_situacao_atual). Nada do score aqui.
   - projetos_risco.sql: projetos em andamento do pior para o melhor, com
     SPI, CPI, estouro, atraso projetado, farol do gerente × calculado,
     melancia, a causa mais frequente no status_estruturado dos últimos 90
     dias e os dias de impacto por falta_sre e por rotatividade.
   - pessoas_ociosas.sql: pessoas com utilização < 20% nas últimas 12
     semanas (utilizacao_pessoa_semana), com horas paradas e custo ocioso
     MÉDIOS por semana e custo_hora.
   Use DATE'2026-10-16' como "hoje" (nunca current_date()).
   A probabilidade por projeto (gold.score_estouro_30d) vem de uma rota
   GET /api/score-estouro no servidor que responde {disponivel, linhas}:
   se a tabela não existir, a tela mostra "—" em vez de quebrar o build.
   O KPI "alto risco em 30 dias" (faixa_risco = 'alto') sai dessa rota.

3. Telas (português, R$, índices com 2 casas, Number() em tudo que vem do
   warehouse):
   - Projetos em risco: 4 KPIs (em risco, estouro previsto, carteira, alto
     risco em 30 dias) + tabela (situação com cor: crítico vermelho, atenção
     âmbar; farol do gerente com 🍉 quando é melancia; coluna P(estouro)).
   - Simulador: escolher uma pessoa ociosa e um projeto destino (só atenção
     ou crítico; para SRE, ordene pelos dias de falta_sre); mostrar horas no
     mês (× 4 semanas), ociosidade que deixa de ser paga, dias de cronograma
     recuperados (dias de impacto da causa nos últimos 90 dias ÷ 90 × 30),
     mobilização = horas de onboarding (editável, 40) × custo_hora, e saldo.
     Explique a conta num <details>.
   Menu com as duas telas (a terceira, Perguntar, entra no prompt 6).
   Sem cache no createApp. Título "Projeto Farol".

4. Dentro de farol-torre/: npm run typecheck, npm run lint,
   databricks apps validate --profile <perfil>.
   Depois: databricks bundle deploy --profile <perfil> (cria o app e o
   service principal). Crie tools/conceder_acesso.py (Python, para rodar no
   Windows; recebe o profile e o nome do app, lê o service_principal_client_id
   com databricks apps get -o json e dá USE CATALOG em lakehouse_vertice e
   USE SCHEMA + SELECT na gold e na silver, usando o tools/run_sql.py),
   rode e faça databricks apps deploy --profile <perfil> (dentro de
   farol-torre/). Sem os GRANT o build falha com INSUFFICIENT_PERMISSIONS:
   é esperado.

5. Documentação: no CLAUDE.md, acrescente farol-torre/ na tabela de pastas
   e uma linha sobre o limite de 3 apps e os GRANT do service principal.

Trabalhe direto. Não faça commit nem push: eu reviso antes.
Me mostre a saída de cada comando de verificação e, no fim, a URL do app.
