{#
    Drops the per-PR schema when a pull request is closed.
    Usage: dbt run-operation drop_ci_schema --target ci

    Guard rails: only runs on the ci target, inside ci_development,
    and only for schemas named pr_<something>.
#}
{% macro drop_ci_schema() %}

    {% if target.name != 'ci' %}
        {{ exceptions.raise_compiler_error("drop_ci_schema only runs on the ci target, not '" ~ target.name ~ "'") }}
    {% endif %}

    {% if target.database != 'ci_development' %}
        {{ exceptions.raise_compiler_error("Refusing to drop a schema outside ci_development") }}
    {% endif %}

    {% if not (target.schema | lower).startswith('pr_') %}
        {{ exceptions.raise_compiler_error("Schema must start with pr_ to be dropped, got '" ~ target.schema ~ "'") }}
    {% endif %}

    {% set sql %}
        DROP SCHEMA IF EXISTS {{ target.database }}.{{ target.schema }} CASCADE
    {% endset %}

    {{ log("Running: " ~ sql, info=true) }}
    {% do run_query(sql) %}

{% endmacro %}
