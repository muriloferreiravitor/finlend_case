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