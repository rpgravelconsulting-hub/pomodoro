create extension if not exists pgcrypto;

-- Lock down sessions/settings so the anon key can't read/write more than intended.
alter table sessions enable row level security;
alter table settings enable row level security;

drop policy if exists "Allow insert sessions" on sessions;
create policy "Allow insert sessions" on sessions
    for insert to public with check (true);

drop policy if exists "Allow read settings" on settings;
create policy "Allow read settings" on settings
    for select to public using (true);

drop policy if exists "Allow update settings" on settings;
create policy "Allow update settings" on settings
    for update to public using (true) with check (true);

-- Password lives only in a table with no RLS policies, so it's unreachable
-- via the anon key except through the SECURITY DEFINER functions below.
create table if not exists app_secrets (
    key text primary key,
    value text not null
);
alter table app_secrets enable row level security;

-- The actual password hash is NOT set here (never commit a real secret to
-- git). After running this migration, set it once via the SQL editor:
--   insert into app_secrets (key, value)
--   values ('analytics_password_hash', extensions.crypt('your-password', extensions.gen_salt('bf')))
--   on conflict (key) do update set value = excluded.value;

create or replace function verify_analytics_password(input_password text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    stored_hash text;
begin
    select value into stored_hash from app_secrets where key = 'analytics_password_hash';
    return stored_hash is not null and extensions.crypt(input_password, stored_hash) = stored_hash;
end;
$$;

create or replace function get_pomodoro_stats(input_password text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    result json;
    streak_days integer;
begin
    if not verify_analytics_password(input_password) then
        raise exception 'Invalid password' using errcode = '28000';
    end if;

    with recursive streak as (
        select current_date as d, 1 as n
        where exists (
            select 1 from sessions where type = 'focus' and completed_at::date = current_date
        )
        union all
        select streak.d - 1, streak.n + 1
        from streak
        where exists (
            select 1 from sessions where type = 'focus' and completed_at::date = streak.d - 1
        )
    )
    select coalesce(max(n), 0) into streak_days from streak;

    select json_build_object(
        'today_focus_minutes', round(coalesce(sum(duration_seconds) filter (
            where completed_at::date = current_date), 0) / 60.0, 1),
        'today_sessions', count(*) filter (where completed_at::date = current_date),
        'total_focus_minutes', round(coalesce(sum(duration_seconds), 0) / 60.0, 1),
        'current_streak_days', streak_days
    ) into result
    from sessions
    where type = 'focus';

    return result;
end;
$$;

grant execute on function verify_analytics_password(text) to anon, authenticated;
grant execute on function get_pomodoro_stats(text) to anon, authenticated;
