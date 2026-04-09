# Guia Semântico para Agente de IA

Orientações para geração de SQL correto contra os modelos dbt da FinLend. Complementa as meta tags do `_marts_models.yml`.

## 1. Roteamento de Modelos

| Modelo | Grain | Quando usar |
|--------|-------|-------------|
| `fct_revenue` | 1 linha por transação | Perguntas com filtro temporal ou detalhamento transacional |
| `merchant_summary` | 1 linha por merchant | Performance geral, rankings, métricas de risco (all-time) |

**Regra:** se a pergunta menciona período ("último mês", "esse trimestre"), usar `fct_revenue`. Caso contrário, preferir `merchant_summary` (mais rápido, mais barato).

| Pergunta | Modelo | Motivo |
|----------|--------|--------|
| Volume Pix do merchant X no último mês | fct_revenue | Filtro temporal |
| Merchants com chargeback acima de 2% | merchant_summary | Métrica pré-calculada, sem período |
| Faturamento em taxas na última semana | fct_revenue | Filtro temporal |
| Top 10 merchants por receita | merchant_summary | Ranking all-time |
| Total de transações Pix do merchant X | merchant_summary | pix_transactions pré-agregado |

## 2. Perguntas Respondíveis (exemplos de SQL)

**Receita:**
```sql
-- Faturamento da última semana
SELECT SUM(finlend_revenue_impact)
FROM fct_revenue
WHERE transaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)

-- Take rate médio
SELECT AVG(take_rate) FROM merchant_summary WHERE take_rate IS NOT NULL
```

**Volume:**
```sql
-- Transações Pix do merchant X no último mês
SELECT COUNT(*) AS qtd, SUM(gmv_impact) AS volume
FROM fct_revenue
WHERE merchant_name LIKE '%X%'
  AND payment_method = 'pix'
  AND transaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
```

**Risco:**
```sql
-- Chargeback rate acima de 2% no trimestre
SELECT merchant_id, merchant_name,
  SAFE_DIVIDE(COUNTIF(status = 'chargeback'), COUNT(*)) AS cb_rate
FROM fct_revenue
WHERE transaction_date >= DATE_TRUNC(CURRENT_DATE(), QUARTER)
GROUP BY merchant_id, merchant_name
HAVING cb_rate > 0.02
ORDER BY cb_rate DESC
```

## 3. Armadilhas Críticas

### 3.1 GMV ≠ Receita

`gmv_impact` mede o volume bruto transacionado. `finlend_revenue_impact` mede as comissões retidas pela plataforma. A diferença pode ser de 50 a 200 vezes dependendo do take rate. Se a pergunta menciona "receita", "faturamento" ou "quanto a empresa ganhou", o campo correto é `finlend_revenue_impact`.

**Defesa:** meta tags `warning` e `business_alias` em ambos os campos.

### 3.2 merchant_summary é all-time

As métricas do `merchant_summary` acumulam desde a primeira transação. Perguntas com recorte temporal exigem `fct_revenue` com `WHERE transaction_date` e `GROUP BY`.

**Defesa:** `warning` no nível do modelo.

### 3.3 payment_method é lowercase

Todos os valores são normalizados no staging. O filtro correto é `WHERE payment_method = 'pix'`, não `'Pix'` ou `'PIX'`. No `merchant_summary`, usar `pix_transactions` diretamente (sem JOIN com fct_revenue).

### 3.4 Ratios, não percentuais

`chargeback_rate`, `refund_rate` e `take_rate` retornam valores entre 0 e 1. Para filtrar "acima de 2%", usar `WHERE chargeback_rate > 0.02`.

**Defesa:** `unit: ratio` na meta tag de cada campo.

### 3.5 JOINs desnecessários

`fct_revenue` já contém `merchant_name` desnormalizado. `merchant_summary` já contém métricas por payment method. Evitar JOINs quando a informação está disponível no próprio modelo.

### 3.6 Transações sem settlement

`fee_amount` pode ser NULL (settlement pendente). O campo `finlend_revenue_impact` já aplica COALESCE para zero. Para transparência, o agente pode informar o total de `pending_settlements` do período.

## 4. Lacunas para Camada Semântica Completa

**Alta prioridade:**
- dbt Semantic Layer / MetricFlow para definição canônica de métricas com time-grain dinâmico
- Dimensões de parceiro financeiro e tipo de produto (inexistentes na modelagem atual)
- Enriquecimento de `stg_merchants` com região, tier, data de onboarding

**Média prioridade:**
- Modelos temporais intermediários (`merchant_monthly_metrics`) para evitar scan do fct_revenue em perguntas com período
- Testes semânticos (fee < amount, take_rate < 0.30, settlement_date >= transaction_date)
- System prompt estruturado para o agente, gerado automaticamente do schema.yml