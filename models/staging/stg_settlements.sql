-- UNNEST isolado no staging: transforma o JOIN no mart de O(N×M) para O(N+M).
-- Esta é a mudança com maior impacto no custo do BigQuery.

WITH source AS (
    SELECT * FROM {{ source('raw', 'settlements') }}
),

unnested AS (
    SELECT
        settlement_id,
        transaction_id,
        net_amount_cents,
        fee_amount_cents,
        settlement_date,
        paid_at
    FROM source, UNNEST(transaction_ids) AS transaction_id
),

typed AS (
    SELECT
        settlement_id,
        transaction_id,
        ROUND(CAST(net_amount_cents AS NUMERIC) / 100, 2) AS net_amount,
        ROUND(CAST(fee_amount_cents AS NUMERIC) / 100, 2) AS fee_amount,
        settlement_date,
        paid_at
    FROM unnested
)

SELECT * FROM typed