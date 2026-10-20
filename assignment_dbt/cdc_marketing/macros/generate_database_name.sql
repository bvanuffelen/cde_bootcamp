{#
    production : silver_production (staging, intermediate, seeds, elementary)
                 gold_production   (marts consumed by analysts, BI and AI)
    dev / ci   : always the target catalog (ci_development), so non-production
                 runs can never write into a production catalog.
#}
{% macro generate_database_name(custom_database_name=none, node=none) -%}
    {%- if target.name == 'production' and custom_database_name is not none -%}
        {{ custom_database_name | trim }}
    {%- else -%}
        {{ target.database }}
    {%- endif -%}
{%- endmacro %}
