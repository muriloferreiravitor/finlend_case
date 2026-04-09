# Parte 5 · Desafio Extra

## 5.1 Análise de Custo do BigQuery

O aumento de 3x na conta é explicado pela combinação de três fatores presentes no código legado.

**Fator principal: JOIN com UNNEST no mart.** O padrão `ON t.transaction_id IN UNNEST(s.transaction_ids)` gera cross-join implícito com complexidade O(N × M × K). O custo cresce de forma quadrática com o volume de transações e settlements.

**Fator secundário: materialização table (full refresh).** O modelo `revenue_report` recria a tabela inteira a cada execução, reprocessando o JOIN acima contra todo o histórico. O custo de cada run é proporcional ao volume acumulado, não ao delta.

**Fator terciário: CURRENT_TIMESTAMP() no staging.** Invalida o results cache do BigQuery a cada execução.

**Efeito composto:** crescimento de 70% no volume (compatível com uma startup em expansão) gera aumento de ~190% no custo (crescimento quadrático do JOIN multiplicado pelo reprocessamento integral). Isso explica quantitativamente o "triplicou".

**Soluções implementadas e impacto estimado:**

| Solução | Redução |
|---------|---------|
| UNNEST isolado no staging (equi-join no mart) | 90-95% |
| Materialização incremental (merge, lookback 3 dias) | 85-95% |
| Filtro de status antes do JOIN | 20-40% |
| Remoção de CURRENT_TIMESTAMP (cache restaurado) | 100% do cache |
| **Total** | **~90-97%** |

## 5.2 Teste Singular de Negócio

**Regra validada:** a comissão da plataforma (`fee_amount`) não pode exceder o valor bruto da transação (`amount_brl`). No modelo de correspondente bancário, a fee é uma fração do amount. Uma violação indica erro de conversão, dados corrompidos na source, ou settlement incorretamente associado.

**Arquivo:** `tests/singular/assert_fee_not_greater_than_amount.sql`

```sql
SELECT
    transaction_id,
    merchant_id,
    merchant_name,
    amount_brl,
    fee_amount,
    net_amount,
    status,
    settlement_id,
    transaction_date,
    ROUND(fee_amount - amount_brl, 2) AS excess_amount,
    ROUND(SAFE_DIVIDE(fee_amount, amount_brl), 4) AS fee_to_amount_ratio
FROM {{ ref('fct_revenue') }}
WHERE fee_amount IS NOT NULL
  AND amount_brl IS NOT NULL
  AND fee_amount > amount_brl
  AND status = 'captured'
```

O teste passa quando retorna zero linhas. Quando falha, os campos `excess_amount` e `fee_to_amount_ratio` auxiliam no diagnóstico da causa raiz.

**Impacto de negócio da violação:**
- `take_rate` inflado (possivelmente > 100%) no merchant_summary
- `merchant_net_impact` negativo em transações captured
- Receita reportada ao board e investidores potencialmente inflada