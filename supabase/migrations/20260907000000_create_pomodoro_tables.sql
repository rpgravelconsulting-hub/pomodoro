create table if not exists sessions (
    id bigint generated always as identity primary key,
    type text not null check (type in ('focus', 'break')),
    duration_seconds integer not null check (duration_seconds > 0),
    round integer not null check (round > 0),
    completed_at timestamptz not null default now()
);

create table if not exists settings (
    id bigint primary key,
    work_minutes integer not null check (work_minutes > 0 and work_minutes <= 180),
    break_minutes integer not null check (break_minutes > 0 and break_minutes <= 60),
    rounds integer not null check (rounds > 0 and rounds <= 20)
);

insert into settings (id, work_minutes, break_minutes, rounds)
values (1, 25, 5, 4)
on conflict (id) do nothing;
