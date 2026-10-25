{# Parse a 'YYYYMMDD' string to a date on each supported warehouse. #}
{% macro parse_yyyymmdd(expr) -%}
    {{ return(adapter.dispatch('parse_yyyymmdd')(expr)) }}
{%- endmacro %}

{% macro default__parse_yyyymmdd(expr) -%}
    to_date({{ expr }}, 'yyyyMMdd')
{%- endmacro %}

{% macro duckdb__parse_yyyymmdd(expr) -%}
    cast(strptime({{ expr }}, '%Y%m%d') as date)
{%- endmacro %}

{% macro snowflake__parse_yyyymmdd(expr) -%}
    to_date({{ expr }}, 'YYYYMMDD')
{%- endmacro %}
