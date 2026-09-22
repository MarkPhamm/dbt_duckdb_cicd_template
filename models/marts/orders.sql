-- One row per order, with payment totals folded in.
--
-- This model refs TWO staging models. That matters for the CI lessons: when
-- you edit stg_payments, dbt must rebuild this model too (it depends on the
-- change) -- but it does NOT need to rebuild stg_orders. Holding that
-- distinction in your head is most of what `--defer` is about.

with orders as (

    select * from {{ ref('stg_orders') }}

),

payments as (

    select * from {{ ref('stg_payments') }}

),

order_payments as (

    select
        order_id,
        sum(amount) as amount

    from payments
    group by order_id

)

select
    orders.order_id,
    orders.customer_id,
    orders.order_date,
    orders.status,
    coalesce(order_payments.amount, 0) as amount

from orders
left join order_payments
    on orders.order_id = order_payments.order_id
