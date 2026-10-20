"""Stand-ins for dbt_utils macros so SQLFluff's jinja templater can render models
without a database connection. Only used for linting, never by dbt itself."""


def generate_surrogate_key(field_list):
    return "md5(concat_ws('-', " + ", ".join(field_list) + "))"
