{{
    config(
        materialized='incremental',
        unique_key='transaction_id',
        partition_by={"field": "transaction_date", "data_type": "date", "granularity": "month"},
        cluster_by=['merchant_id', 'status'],
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

WITH transactions AS (
    SELECT *
    FROM {{ ref('stg_transactions') }}
    WHERE status IN ('captured', 'refunded', 'chargeback')
    {% if is_incremental() %}
        AND created_at >= (
            SELECT DATE_SUB(
                MAX(created_at),
                INTERVAL {{ var('incremental_lookback_days', 3) }} DAY
            ) FROM {{ this }}
        )
    {% endif %}
),

merchants AS (
    SELECT * FROM {{ ref('stg_merchants') }}
),

settlements AS (
    SELECT * FROM {{ ref('stg_settlements') }}
),

joined AS (
    SELECT
        t.transaction_id,
        t.merchant_id,
        m.trade_name          AS merchant_name,
        m.mcc_code,
        t.amount_brl,
        t.status,
        t.payment_method,
        DATE(t.created_at)    AS transaction_date,
        t.created_at,
        t.pix_key_type,
        t.installments,
        s.settlement_id,
        s.net_amount,
        s.fee_amount,
        s.settlement_date,
        s.paid_at
    FROM transactions t
    LEFT JOIN merchants m   ON t.merchant_id = m.merchant_id
    LEFT JOIN settlements s ON t.transaction_id = s.transaction_id
),

deduplicated AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY transaction_id
            ORDER BY settlement_date DESC, settlement_id DESC
        ) AS _dedup_rank
    FROM joined
),

final AS (
    SELECT
        transaction_id, merchant_id, merchant_name, mcc_code,
        status, payment_method, transaction_date, created_at,
        pix_key_type, installments,
        amount_brl, settlement_id, net_amount, fee_amount,
        settlement_date, paid_at,

        -- GMV (volume bruto, NÃO é receita)
        CASE
            WHEN status = 'captured'   THEN amount_brl
            WHEN status = 'refunded'   THEN -amount_brl
            WHEN status = 'chargeback' THEN -amount_brl
        END AS gmv_impact,

        -- Receita da plataforma (fees)
        CASE
            WHEN status = 'captured'   THEN COALESCE(fee_amount, 0)
            WHEN status = 'refunded'   THEN -COALESCE(fee_amount, 0)
            WHEN status = 'chargeback' THEN -COALESCE(fee_amount, 0)
        END AS finlend_revenue_impact,

        -- Líquido do merchant
        CASE
            WHEN status = 'captured'   THEN COALESCE(net_amount, 0)
            WHEN status = 'refunded'   THEN -COALESCE(net_amount, 0)
            WHEN status = 'chargeback' THEN -COALESCE(net_amount, 0)
        END AS merchant_net_impact,

        CASE
            WHEN status = 'captured' AND settlement_id IS NULL THEN TRUE
            ELSE FALSE
        END AS is_pending_settlement

    FROM deduplicated
    WHERE _dedup_rank = 1
)

SELECT * FROM final