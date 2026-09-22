-- Intermediate: a reusable building block that isn't meant for end users.
--
-- This logic used to live inside `orders`. Pulling it out is typical dbt
-- practice -- but for this course it also does something useful: it makes the
-- chain below stg_payments one model longer, so `state:modified+` has a
-- deeper subgraph to select in Lesson 03.

with payments as (

    select * from {{ ref('stg_payments') }}

)

select
    order_id,
    count(*)    as payment_count,
    sum(amount) as total_amount

from payments
group by order_id
