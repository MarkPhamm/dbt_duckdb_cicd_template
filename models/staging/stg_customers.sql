-- Staging: rename and lightly clean one raw source. Nothing clever on purpose.
with source as (

    select * from {{ ref('raw_customers') }}

)

select
    id          as customer_id,
    first_name,
    last_name

from source
