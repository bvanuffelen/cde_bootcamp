{#
    production : use the schema configured in dbt_project.yml
                 (marketing_staging, marketing_intermediate, marketing, ...)
    dev / ci   : put everything in the target schema (dbt_<you> or pr_<n>),
                 so a developer or a PR gets ONE isolated, easy-to-drop schema.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if target.name == 'production' and custom_schema_name is not none -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}
{%- endmacro %}
