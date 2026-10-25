{# Money is stored as fixed-point decimals so sums tie to the cent. #}
{% macro money(expr) -%}
    cast(round({{ expr }}, 2) as decimal(18, 2))
{%- endmacro %}
