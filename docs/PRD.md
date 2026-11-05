# PRD · Projeto Farol: Torre de Controle de Projetos

## Visão geral

O Projeto Farol constrói, no **Databricks Free Edition**, a **Torre de Controle de Projetos** de uma empresa de
tecnologia: a **Vértice Tecnologia** (fictícia, 520 pessoas, 60 projetos de clientes).

O problema é simples de dizer e difícil de resolver: ninguém sabe quais projetos estão atrasados, porque cada
gerente controla o seu numa ferramenta diferente (planilhas Excel, ClickUp ou MS Project) e o PMO consolida tudo à
mão, toda sexta.

O produto cobre a plataforma de ponta a ponta: ingestão de qualquer formato (`read_files` com Excel, JSON e XML),
integração e transformação (Lakeflow), IA sobre texto livre (`ai_classify`, `ai_extract`, `ai_parse_document`), KPIs
governados (Metric Views), dashboards AI/BI, Genie, um modelo de previsão (MLflow + Unity Catalog), um Data App com
Lakebase para registrar decisões e um agente que lê os contratos de fornecedor.

## Objetivo do produto

Responder, toda segunda de manhã, as quatro perguntas do dono da Vértice:

1. **Quais projetos estão atrasados, e de quais clientes?**
2. **Quanto esse atraso vai me custar?**
3. **Tenho gente parada enquanto outro projeto pede gente?**
4. **O que vai dar errado no próximo mês, e o que eu faço agora?**

| Métrica do produto | Hoje (cenário) | Com a Torre |
| --- | --- | --- |
| Projetos com SPI/CPI atualizados toda semana | 0% (cada ferramenta de um jeito) | 100% das 3 ferramentas |
| Tempo para responder "por que o projeto X atrasou?" | dias (ler o status de cada gerente) | menos de 1 minuto (Genie) |
| Antecedência na detecção de estouro | 0 dias (o cliente reclama) | cerca de 41 dias (modelo de previsão) |
| Farol confiável | farol do gerente | farol calculado pelo número |
| Decisões de realocação registradas | e-mail e WhatsApp | 100% no app, com dono e horário |

## Cenário de negócio

A Vértice desenvolve e implanta sistemas para grandes clientes de varejo, financeiro, saúde, logística e indústria:
60 projetos (41 em andamento) e R$ 305 mi de carteira.

| Fonte | Onde mora | O que traz |
| --- | --- | --- |
| Cronogramas | 20 planilhas Excel · 25 listas do ClickUp (JSON) · 15 arquivos do MS Project (XML) | tarefas, baseline, realizado, % concluído, horas |
| PMO | cadastro de projetos (o de-para) + status semanal em texto livre | ferramenta de cada projeto, farol do gerente, bloqueios |
| RH e timesheet | colaboradores e apontamentos semanais | quem está onde e quanto trabalhou |
| Financeiro | lançamentos de custo | pessoal, consultoria, cloud, licenças, despesas |
| Compras | entregas das consultorias | prometido × entregue |
| Documentos | 8 contratos de fornecedor/SaaS (PDF) | multa, SLA, renovação, aviso prévio |

### Personas

| Persona | O que precisa | Como usa a Torre |
| --- | --- | --- |
| Dono / diretoria | quais projetos atrasam, de quais clientes, quanto custa | dashboard e perguntas ao Genie |
| PMO | as 3 ferramentas numa visão só, simular realocação | app: simula, aprova e registra |
| Gerente de projeto | a causa do desvio, sem farol de enfeite | causa extraída do status semanal |
| Financeiro | margem por contrato, estouro previsto, multa de fornecedor | EAC, margem e exposição contratual governados |
| Compras | consultoria que atrasa | ranking de fornecedor e multa cobrável |

## KPIs

| KPI | Definição |
| --- | --- |
| SPI | horas agregadas ÷ horas planejadas (baseline) |
| CPI | EV ÷ custo real, com EV = orçamento × horas agregadas ÷ horas totais |
| EAC · estouro previsto · margem projetada | orçamento ÷ CPI · EAC − orçamento (só positivo) · (contrato − EAC) ÷ contrato |
| Atraso projetado | duração ÷ SPI − duração |
| Farol calculado · melancia | verde ≥ 0,95, amarelo ≥ 0,90 · farol do gerente verde com SPI < 0,9 |
| Utilização · horas e custo ociosos | apontadas ÷ disponíveis; menos de 20% em 12 semanas = parado |
| Prazo real ÷ prometido do fornecedor | média por fornecedor normalizado |
| Probabilidade de estouro em 30 dias | modelo: o pior índice cruza 0,9 em até 4 semanas |
| Multa cobrável · aviso prévio vencendo | contrato × entregas atrasadas · fim da vigência − aviso prévio |

Regra de corte: SPI ou CPI < 0,9 = atenção; < 0,8 = crítico. O "hoje" do dataset é **16/10/2026**.

## Padrões embutidos no dado (seed 42)

1. 8 projetos com CPI caindo a partir do 6º mês (escopo cresce sem aditivo).
2. O change freeze da Black Friday (01/11 a 10/01) trava os 3 projetos de e-commerce; o de 2026 começa em 01/11.
3. A consultoria CodeForge entrega com prazo 41% acima do prometido e aparece escrita de 4 jeitos.
4. Duas SREs seniores a cerca de 5% no PRJ-007 (ainda no discovery) enquanto o status do PRJ-011 pede SRE há 12 semanas.
5. Dois squads com rotatividade alta (PRJ-016 e PRJ-030), os piores SPI da carteira.
6. Bônus: 4 projetos com farol verde e SPI abaixo de 0,9.

A sujeira é proposital e é o trabalho da camada silver: cada ferramenta com seu formato de data, percentual e hora;
linha de TOTAL na planilha; tarefas-resumo no Project; status escrito de 12 jeitos; ferramenta escrita de 8 jeitos;
vírgula decimal; estornos; pessoa duplicada; status vazio.

## Escopo por etapa

| Etapa | Foco | Entrega |
| --- | --- | --- |
| 1 · Ingestão e análise | SQL no navegador | bronze lendo Excel, JSON e XML; análises SQL até o SPI das 3 ferramentas (UNION à mão); dashboard; Genie sem curadoria, que erra |
| 2 · Ingestão automatizada | Python e jobs | data lake (S3/boto3) → raw → bronze, API de feriados, job diário de ingestão |
| 3 · Modelagem | engenharia de analytics | bundle, pipeline Lakeflow que integra as 3 ferramentas (`silver.tarefas`), gold, testes, IA nos status semanais, metric view `mv_projetos`, dashboard |
| 4 · IA e produto | ciência de dados e IA | modelo de estouro em 30 dias (MLflow + Unity Catalog), Genie curado, app da Torre (AppKit) com simulador e aprovação no Lakebase, agente de contratos |

## Fora de escopo

- Conectores reais com Excel Online, ClickUp e MS Project (a ingestão é por arquivo exportado no volume).
- Endpoint de modelo próprio (o Free Edition só serve modelos de base): o score roda em lote e grava na gold.
- Knowledge Assistant e Supervisor Agent (marcados como legado no Free Edition): o agente é Genie sobre tabelas extraídas.

## Riscos

| Risco | Mitigação |
| --- | --- |
| O Free Edition muda com o tempo | documentar limitações e workarounds por etapa |
| Limite de 3 apps no Free Edition | liberar um app antes do deploy |
| IA lenta ou cara | IA só nos textos com bloqueio dos últimos 90 dias; MERGE incremental |
| Dado diferente entre execuções | seed fixa (42) e validador dos padrões em `data/validar_padroes.py` |
