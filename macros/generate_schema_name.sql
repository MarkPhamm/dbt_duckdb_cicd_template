{#
    Decides which schema every model is built into.

    dbt calls this macro once per model, passing the model's `+schema:` config
    (from dbt_project.yml) as `custom_schema_name`. Whatever this returns IS
    the schema. There is no other mechanism -- which means environments are,
    quite literally, whatever this macro says they are.

    Our rule:

        target    +schema        -> schema written
        --------  -------------  -------------------
        prod      staging        -> staging
        prod      intermediate   -> intermediate
        prod      marts          -> marts
        dev       (any)          -> dev
        ci        (any)          -> ci_pr_42

    Production splits into layers because it has many consumers -- analysts and
    BI tools need `marts.customers` to be a stable address, and want no chance
    of querying a staging view by accident.

    Dev and CI each have exactly one consumer (you, or one pull request), so
    splitting six models across three schemas buys nothing -- and makes
    teardown three statements instead of one. `drop schema ci_pr_42 cascade`
    should clean up everything a pull request created.

    HEADS UP: this is NOT dbt's default behaviour. The built-in version
    CONCATENATES, so `+schema: staging` would normally give you `dev_staging`
    in dev and `prod_staging` in prod. We deliberately discard the custom
    schema outside prod. If you ever wonder why `+schema: staging` appears to
    do nothing in dev -- this macro is the reason.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- if target.name == 'prod' and custom_schema_name is not none -%}

        {{ custom_schema_name | trim }}

    {%- else -%}

        {{ target.schema }}

    {%- endif -%}

{%- endmacro %}
