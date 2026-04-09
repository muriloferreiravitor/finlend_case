# FinLend · Refatoração do Projeto dbt

## Visão Geral

Projeto dbt herdado com falhas críticas de correção financeira, custo operacional e ausência de testes. Este repositório contém o diagnóstico completo (13 problemas identificados), a refatoração seletiva (3 frentes cobrindo 11 dos 13 problemas), a preparação dos modelos para consumo por agente de IA e o desafio extra (análise de custo + teste de negócio).

## Estrutura do Repositório

```
finlend/
├── README.md
├── GLOSSARIO.md
├── SEMANTIC_NOTES.md
├── dbt_project.yml
├── seeds/
│   └── seed_test_statuses.csv
├── models/
│   ├── staging/
│   │   ├── _sources.yml
│   │   ├── _stg_models.yml
│   │   ├── stg_transactions.sql
│   │   ├── stg_merchants.sql
│   │   └── stg_settlements.sql
│   └── marts/
│       ├── _marts_models.yml
│       ├── fct_revenue.sql
│       └── merchant_summary.sql
├── tests/
│   └── singular/
│       └── assert_fee_not_greater_than_amount.sql
└── docs/
    ├── 01_diagnostico.md
    ├── 02_refatoracao.md
    ├── 03_preparacao_ia.md
    └── 04_desafio_extra.md
```

## Navegação

| Entregável | Documento | Resumo |
|-----------|-----------|--------|
| Parte 1 | `docs/01_diagnostico.md` | 13 problemas ordenados por gravidade com impacto e correção |
| Parte 2 | `docs/02_refatoracao.md` | 3 frentes de refatoração em código dbt |
| Parte 3 | `docs/03_preparacao_ia.md` + `SEMANTIC_NOTES.md` + `_marts_models.yml` | Meta tags, documentação semântica e guia para agente LLM |
| Parte 4 | `README.md` | Este documento |
| Parte 5 | `docs/04_desafio_extra.md` + `tests/singular/` | Análise de custo BigQuery e teste singular de negócio |
| Referência | `GLOSSARIO.md` | Termos do domínio financeiro aplicados ao contexto FinLend |

## Processo

**Sequência adotada:** entendimento do modelo de negócio → leitura do código rastreando o fluxo financeiro → diagnóstico priorizado por impacto no negócio → agrupamento em frentes de execução → refatoração → preparação para IA.

A priorização seguiu cinco critérios em ordem: (1) correção dos números financeiros, (2) risco regulatório, (3) custo de infraestrutura, (4) escalabilidade e (5) viabilidade do produto de IA.

O agrupamento dos 13 problemas em 3 frentes (staging, fct_revenue, merchant_summary) permitiu resolver 11 deles com superfície mínima de mudança. Os 2 restantes (schema.yml vazio e ausência de meta tags) foram endereçados na Parte 3.

## Uso de IA

Utilizei o Claude (Anthropic) como par ao longo do processo. A IA contribuiu com velocidade de análise e amplitude de cobertura. As principais intervenções manuais foram:

| Situação | Intervenção |
|----------|------------|
| Diagnóstico genérico sem contexto de negócio | Reescrita com profundidade de domínio (correspondente bancário, regulação, investidores) |
| P8 não identificado (confusão GMV vs receita) | Problema semântico, não sintático: só emerge com entendimento do modelo de receita por fees |
| Seeds não implementadas apesar de mencionadas | Exigi consistência entre diagnóstico e código |
| Inconsistências entre partes (6 encontradas) | Revisões cruzadas em 3 momentos distintos |
| Melhores práticas dbt ausentes | Adição de dbt_project.yml, materialização por camada, yml co-localizado |

A principal limitação observada: a IA é eficaz para identificar problemas técnicos (breadth), mas requer supervisão humana para avaliar impacto de negócio (depth).

## Próximos Passos (com mais tempo)

**Imediato (1-2 semanas):** testes singulares de negócio adicionais, source freshness calibrado por parceiro, testes de volume (alerta de queda > 30%).

**Curto prazo (2-4 semanas):** dimensões enriquecidas (região, tier, parceiro, produto), modelos temporais intermediários (`merchant_monthly_metrics`), exposures para rastreabilidade.

**Médio prazo (1-2 meses):** dbt Semantic Layer com MetricFlow, orquestração em produção (dbt Cloud ou Airflow), monitoramento de custos via INFORMATION_SCHEMA.

**Longo prazo (3+ meses):** system prompt estruturado para o agente de IA, data contracts nos marts, column-level lineage.

## Decisões sob Ambiguidade

| Ambiguidade | Decisão | Justificativa |
|-------------|---------|---------------|
| Duplicatas em merchants | Deduplicação preventiva no staging | Custo marginal, proteção contra CDC |
| Campos do JSON metadata | Extraídos pix_key_type, installments, partner_reference | Baseado nas perguntas de negócio do case |
| Granularidade de partição | Mensal | Evita limite de 4.000 partições; alinha com queries típicas |
| Filtrar testes no staging | Sim, via seed | Lixo óbvio; seed permite edição sem SQL |
| merchant_summary incremental | Não, full refresh | ~10k linhas; complexidade não se justifica |
| Lookback incremental | 3 dias (configurável via var) | Cobre D+2 de liquidação dos parceiros |
| stg_settlements view ou table | View | Consumido por um único mart |
