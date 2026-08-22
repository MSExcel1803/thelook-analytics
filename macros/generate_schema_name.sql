{#
    Override dbt's default schema naming.

    Default behaviour prefixes the target schema onto every custom schema,
    producing `dbt_harsh_core`. In dev that is what we want (everyone's models
    stay in their own sandbox). In prod we want clean names: `core`, not
    `analytics_core`.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set default_schema = target.schema -%}

    {%- if custom_schema_name is none -%}
        {{ default_schema }}

    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}

    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim }}

    {%- endif -%}

{%- endmacro %}
