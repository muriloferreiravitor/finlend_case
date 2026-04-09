{{ config(materialized='table', cluster_by=['mcc_code']) }}

WITH revenue AS (
    SELECT * FROM {{ ref('fct_revenue') }}
),

aggregated AS (
    SELECT
        merchant_id,
        merchant_name,
        mcc_code,

        COUNT(*)                       AS total_transactions,
        COUNTIF(status = 'captured')   AS captured_transactions,
        COUNTIF(status = 'refunded')   AS refunded_transactions,
        COUNTIF(status = 'chargeback') AS chargeback_transactions,

        COUNTIF(payment_method = 'pix')         AS pix_transactions,
        COUNTIF(payment_method = 'credit_card')  AS credit_card_transactions,
        COUNTIF(payment_method = 'debit_card')   AS debit_card_transactions,
        COUNTIF(payment_method = 'boleto')       AS boleto_transactions,

        SUM(gmv_impact)                AS total_gmv,
        SUM(finlend_revenue_impact)    AS total_finlend_revenue,
        SUM(merchant_net_impact)       AS total_merchant_net,
        SUM(CASE WHEN status = 'captured' THEN fee_amount ELSE 0 END) AS total_fees_captured,

        SAFE_DIVIDE(COUNTIF(status = 'chargeback'), COUNT(*)) AS chargeback_rate,
        SAFE_DIVIDE(
            SUM(CASE WHEN status = 'chargeback' THEN amount_brl ELSE 0 END),
            SUM(CASE WHEN status = 'captured' THEN amount_brl ELSE 0 END)
        ) AS chargeback_amount_rate,
        SAFE_DIVIDE(COUNTIF(status = 'refunded'), COUNT(*)) AS refund_rate,
        SAFE_DIVIDE(
            SUM(CASE WHEN status = 'captured' THEN fee_amount ELSE 0 END),
            SUM(CASE WHEN status = 'captured' THEN amount_brl ELSE 0 END)
        ) AS take_rate,

        MIN(transaction_date)            AS first_transaction_date,
        MAX(transaction_date)            AS last_transaction_date,
        COUNT(DISTINCT transaction_date) AS active_days,
        AVG(DATE_DIFF(settlement_date, transaction_date, DAY)) AS avg_settlement_days,
        COUNTIF(is_pending_settlement)   AS pending_settlements

    FROM revenue
    GROUP BY merchant_id, merchant_name, mcc_code
)

SELECT * FROM aggregated