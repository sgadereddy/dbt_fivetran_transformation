{{
    config(
        materialized='incremental',
        partition_by = {'field': 'valid_starting_on', 'data_type': 'date'},
        unique_key='issue_day_id'
    )
}}

with daily_field_history as (

    select * 
    from {{ ref('int_jira__daily_field_history') }}

    {% if is_incremental() %}
    where valid_starting_on >= (select max(valid_starting_on) from {{ this }} )
    {% endif %}
),

pivot_out as (

    -- pivot out default columns (status and sprint) and others specified in the issue_field_history_columns var
    -- only days on which a field value was actively changed will have a non-null value. the nulls will need to 
    -- be filled in the final daily issue field history model
    select 
        valid_starting_on, 
        issue_id,
        max(case when lower(field_name) = 'status' then field_value end) as status,
        max(case when lower(field_name) = 'sprint' then field_value end) as sprint,

        {% for col in var('issue_field_history_columns') -%}
            max(case when lower(field_name) = '{{ col | lower }}' then field_value end) as {{ col | replace(' ', '_') }}
            {% if not loop.last %},{% endif %}
        {% endfor -%}

    from daily_field_history

    group by 1,2
),

surrogate_key as (

    select 
        *,
        {{ dbt_utils.surrogate_key(['valid_starting_on','issue_id']) }} as issue_day_id

    from pivot_out
)

select * from surrogate_key 