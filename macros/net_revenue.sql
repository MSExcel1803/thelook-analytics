{#
    The revenue definition, expressed once as a macro so any ad-hoc analysis
    in analyses/ uses exactly the same rule the marts do.

    Usage:  select {{ net_revenue('sale_price', 'status') }} as net_revenue
#}
{% macro net_revenue(price_column, status_column) -%}
    case
        when {{ status_column }} in ({{ "'" ~ var('revenue_statuses') | join("', '") ~ "'" }})
        then {{ price_column }}
        else 0
    end
{%- endmacro %}
