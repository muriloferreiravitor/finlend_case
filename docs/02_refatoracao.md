# Parte 2 · Refatoração Seletiva

## Justificativa da Escolha

As 3 frentes foram selecionadas por cobertura: 11 dos 13 problemas resolvidos em 3 escopos coesos.

| Frente | Problemas | Lógica |
|--------|-----------|--------|
| 1. Staging completo | P1, P2, P4, P9, P10, P11 | Fundação: sem staging correto, nenhum mart é confiável |
| 2. fct_revenue | P3, P7, P8 | Custo de infra + semântica financeira |
| 3. merchant_summary | P5, P12 | Risco regulatório + interface para IA |

## Estrutura de Pastas

```
finlend/
├── dbt_project.yml
├── seeds/
│   └── seed_test_statuses.csv
└── models/
    ├── staging/
    │   ├── _sources.yml
    │   ├── _stg_models.yml
    │   ├── stg_transactions.sql
    │   ├── stg_merchants.sql
    │   └── stg_settlements.sql
    └── marts/
        ├── _marts_models.yml
        ├── fct_revenue.sql
        └── merchant_summary.sql
```


## Frente 1 · Staging

**Arquivos:**

- `models/staging/_sources.yml`
- `models/staging/_stg_models.yml`
- `models/staging/stg_transactions.sql`
- `models/staging/stg_merchants.sql`
- `models/staging/stg_settlements.sql`


## Frente 2 · fct_revenue

Renomeado de `revenue_report` para `fct_revenue` (tabela de fatos, não report de BI).

**Arquivo:** `models/marts/fct_revenue.sql`

**Decisões técnicas:** o filtro de status (`WHERE status IN (...)`) foi posicionado antes do JOIN para reduzir o volume processado. Partição mensal evita o limite de 4.000 partições. Clustering por `merchant_id` e `status` otimiza as queries mais frequentes do negócio.


## Frente 3 · merchant_summary

**Arquivo:** `models/marts/merchant_summary.sql`

---

## DAG

```
seed_test_statuses ──────────────────────┐
                                         │
raw.transactions ──→ stg_transactions ───┤
raw.merchants ────→ stg_merchants ───────┤
raw.settlements ──→ stg_settlements ─────┘
                                         ↓
                                    fct_revenue
                                         ↓
                                  merchant_summary
```

## Impacto Estimado no Custo

| Componente | Antes | Depois | Redução |
|-----------|-------|--------|---------|
| JOIN settlements | Cross-join (UNNEST no mart) | Equi-join (staging pré-computado) | ~90-95% |
| Materialização | Full table (histórico inteiro) | Incremental (3 dias) | ~85-95% |
| Filtro de status | Após JOIN | Antes do JOIN | ~20-40% |
| Cache | Invalidado por CURRENT_TIMESTAMP | Funcional | 100% |
| **Total** | | | **~90-97%** |