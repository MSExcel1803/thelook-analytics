{#
    Rounds a monetary expression consistently to 2dp as NUMERIC.
    Prevents float drift showing up as $1,204,882.9999999 in a dashboard.
#}
{% macro money(expression) -%}
    round(cast({{ expression }} as numeric), 2)
{%- endmacro %}
