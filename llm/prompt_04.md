Use as skills databricks-core, databricks-dabs e databricks-aibi-dashboards.
Sempre --profile <perfil> (o profile do meu workspace). Nunca escolha um profile sozinho.
Leia o CLAUDE.md e o docs/PRD.md da raiz (não substitua o CLAUDE.md) e use
tools/run_sql.py para rodar SQL.

Continue o bundle na raiz deste repositório. O job está pronto e a gold,
atualizada (inclui gold.status_estruturado). Agora o dashboard, como código.
O "hoje" é DATE'2026-10-16'. Nunca current_date().

Antes de começar, leia dashboards/bronze/gerar_dashboard.py: é o dashboard
anterior, sobre a bronze, e mostra a estrutura do JSON AI/BI (GRID_V1), o tema
e como os widgets são montados. Reaproveite o formato e a paleta. Esse
dashboard antigo continua como está; não o apague nem o mexa.

1. dashboards/gold/gerar_dashboard.py gera dashboards/gold/portfolio.lvdash.json
   (AI/BI, GRID_V1). As queries da gold usam o nome de tabela PURO (sem catálogo
   nem schema); a silver.entregas_fornecedor vai com o nome completo
   lakehouse_vertice.silver.entregas_fornecedor. Três páginas:

   Portfólio
   - KPIs da carteira em andamento, calculados na projeto_situacao_atual
     (WHERE status = 'em_andamento'): carteira (SUM(valor_contrato)), SPI
     (SUM(ev)/SUM(pv)), CPI (SUM(ev)/SUM(ac)), estouro previsto, projetos em
     risco (atenção + crítico), críticos e melancias. Razão é SUM/SUM, nunca
     AVG de razão.
   - barra de estouro previsto por projeto, colorida por situação
     (crítico #FF5F46, atenção #F6C344, ok #22C2F4)
   - dispersão SPI × CPI, um ponto por projeto
   - linha de SPI e CPI semanais da carteira (SUM(ev)/SUM(pv) por semana no
     fato_projeto_semana, a partir de 2025-03-07)
   - tabela dos projetos em andamento com o farol do gerente ao lado do
     farol pelo número e a coluna melancia

   Pessoas
   - top 15 pessoas por custo da hora parada (utilizacao_pessoa_semana,
     semana > DATE'2026-07-24', as últimas 12 semanas)
   - tabela de utilização por pessoa e projeto, da mais parada à mais ocupada
   - barras de causas de bloqueio por projeto (status_estruturado,
     data_status >= DATE'2026-07-18', sem 'sem_bloqueio' e 'nao_reportado')

   Fornecedores (sobre silver.entregas_fornecedor)
   - tabela por fornecedor: grafias no cadastro, entregas, prazo real ÷
     prometido, % no prazo, em atraso hoje
   - tabela das entregas em atraso hoje

   Tema: #0059DB e #22C2F4, fundo #14141A no escuro (a mesma paleta do
   dashboard da bronze). Um título de texto em cada página com a pergunta do
   dono que ela responde. Nada de "aula", "noite" ou "prompt" em títulos,
   nomes ou comentários.

2. resources/dashboard.dashboard.yml: recurso dashboard_portfolio, display
   name "Projeto Farol · Portfólio", file_path ../dashboards/gold/portfolio.lvdash.json,
   dataset_catalog ${var.catalog}, dataset_schema gold, warehouse_id
   ${var.warehouse_id}. Sem mode: development.

3. Documentação: no dashboards/README.md acrescente uma seção "Dashboard da
   gold" (o que é, como gerar o JSON, que o deploy é pelo bundle e que editar
   no workspace trava o próximo deploy: a mudança vai para o script). No
   CLAUDE.md, atualize a linha de dashboards/ (bronze e gold).

Antes do deploy, rode cada query do dashboard com tools/run_sql.py
(prefixando lakehouse_vertice.gold. nas tabelas da gold) e me mostre a
contagem de linhas de cada uma e os valores dos KPIs.

Trabalhe direto. Não faça commit nem push: eu reviso antes.

Rode e me mostre a saída:
  python3 dashboards/gold/gerar_dashboard.py
  databricks bundle validate --profile <perfil>
  databricks bundle deploy --profile <perfil>
  databricks bundle summary --profile <perfil>
No fim, me diga a URL do dashboard (do bundle summary).