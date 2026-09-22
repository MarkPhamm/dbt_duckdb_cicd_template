-- One row per order, with payment totals folded in.
--
-- Note that this model refs one staging model and one intermediate model.
-- That matters for the CI lessons: when you edit stg_payments, dbt must
-- rebuild this model (it depends on the change, two hops up) -- but it does
-- NOT need to rebuild stg_orders. Holding that distinction in your head is
-- most of what `--defer` is about.

with orders as (

    select * from {{ ref('stg_orders') }}

),

order_payments as (

    select * from {{ ref('int_order_payments') }}

)

select
    orders.order_id,
    orders.customer_id,
    orders.order_date,
    orders.status,
    coalesce(order_payments.payment_count, 0) as payment_count,
    coalesce(order_payments.total_amount, 0)  as amount

from orders
left join order_payments
    on orders.order_id = order_payments.order_id
