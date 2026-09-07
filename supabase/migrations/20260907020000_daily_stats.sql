create or replace function get_daily_focus_stats(input_password text, days_back integer default 14)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    result json;
begin
    if not verify_analytics_password(input_password) then
        raise exception 'Invalid password' using errcode = '28000';
    end if;

    select json_agg(day_stats order by day_stats.day) into result
    from (
        select
            gs.day::date as day,
            round(coalesce(sum(s.duration_seconds), 0) / 60.0, 1) as focus_minutes,
            count(s.id) as focus_sessions
        from generate_series(current_date - (days_back - 1), current_date, interval '1 day') as gs(day)
        left join sessions s
            on s.type = 'focus' and s.completed_at::date = gs.day::date
        group by gs.day
    ) day_stats;

    return coalesce(result, '[]'::json);
end;
$$;

grant execute on function get_daily_focus_stats(text, integer) to anon, authenticated;
