-- One row per customer, with their order history summarised.
-- Sits at the very bottom of the DAG, so almost any upstream change reaches it.

with customers as (

    select * from {{ ref('stg_customers') }}

),

orders as (

    select * from {{ ref('orders') }}

),

customer_orders as (

    select
        customer_id,
        min(order_date)  as first_order,
        max(order_date)  as most_recent_order,
        count(order_id)  as number_of_orders,
        sum(amount)      as lifetime_value

    from orders
    group by customer_id

)

select
    customers.customer_id,
    customers.first_name,
    customers.last_name,
    customer_orders.first_order,
    customer_orders.most_recent_order,
    coalesce(customer_orders.number_of_orders, 0) as number_of_orders,
    coalesce(customer_orders.lifetime_value, 0)   as lifetime_value

from customers
left join customer_orders
    on customers.customer_id = customer_orders.customer_id
