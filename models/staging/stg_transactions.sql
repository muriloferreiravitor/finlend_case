WITH source AS (
    SELECT * FROM {{ source('raw', 'transactions') }}
),

test_statuses AS (
    SELECT status FROM {{ ref('seed_test_statuses') }}
),

cleaned AS (
    SELECT
        transaction_id,
        merchant_id,
        customer_id,

        amount_cents,
        ROUND(CAST(amount_cents AS NUMERIC) / 100, 2) AS amount_brl,

        LOWER(TRIM(status)) AS status,
        LOWER(TRIM(payment_method)) AS payment_method,

        created_at,
        updated_at,

        JSON_EXTRACT_SCALAR(metadata, '$.pix_key_type') AS pix_key_type,
        SAFE_CAST(JSON_EXTRACT_SCALAR(metadata, '$.installments') AS INT64) AS installments,
        JSON_EXTRACT_SCALAR(metadata, '$.partner_reference') AS partner_reference,
        metadata AS raw_metadata

    FROM source
    WHERE LOWER(TRIM(status)) NOT IN (SELECT status FROM test_statuses)
)

SELECT * FROM cleaned