WITH source AS (
    SELECT * FROM {{ source('raw', 'merchants') }}
),

deduplicated AS (
    SELECT
        id AS merchant_id,
        trade_name,
        mcc_code,
        ROW_NUMBER() OVER (
            PARTITION BY id ORDER BY updated_at DESC, id DESC
        ) AS _row_num
    FROM source
)

SELECT merchant_id, trade_name, mcc_code
FROM deduplicated
WHERE _row_num = 1