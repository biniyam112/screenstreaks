-- Streak passes and the group-pass algorithm.
--
-- A group day that breaks is recovered by spending one member's personal
-- pass. The database picks who, so every device agrees on the answer —
-- computing it client-side would let two phones reach different conclusions
-- and spend the pass twice.

-- ---------------------------------------------------------------- schema

alter table public.streak_passes
    add column if not exists kind text not null default 'personal';
-- kind: 'personal' | 'sleep' | 'group' | 'group_debt'
--   sleep      — an hour of use between 2 and 5am, screen left on
--   group      — paid from the loser's unspent weekly pass
--   group_debt — borrowed against next week, shown as -1 in the app

alter table public.daily_records
    add column if not exists partial boolean not null default false;

-- ------------------------------------------------------------- standings

-- Consecutive misses ending on on_day. Used instead of a streak because
-- when several people break the same day their streaks are all zero, while
-- their miss runs still differ.
create or replace function public.miss_run(uid uuid, on_day date)
returns int
language sql
security definer
stable
as $$
    with misses as (
        select day
        from public.daily_records
        where user_id = uid and not partial and not limit_met and day <= on_day
    ),
    -- day minus its position is constant within a consecutive run
    runs as (
        select day - (row_number() over (order by day))::int as grp, day
        from misses
    )
    select coalesce((
        select count(*)::int
        from runs
        where grp = (select grp from runs where day = on_day)
    ), 0);
$$;

-- Longest run of met days ever. Counts days recovered with a pass, so it
-- matches what the app shows rather than judging more strictly.
create or replace function public.best_streak(uid uuid)
returns int
language sql
security definer
stable
as $$
    with met as (
        select r.day
        from public.daily_records r
        where r.user_id = uid
          and not r.partial
          and (r.limit_met or exists (
                select 1 from public.streak_passes p
                where p.user_id = uid and p.day = r.day))
    ),
    runs as (
        select day - (row_number() over (order by day))::int as grp
        from met
    )
    select coalesce((
        select max(c)::int from (
            select count(*) as c from runs group by grp
        ) t
    ), 0);
$$;

create or replace function public.member_standing(uid uuid, on_day date)
returns table (
    miss_run int,
    limit_minutes int,
    personal_record int,
    rate_30 numeric
)
language sql
security definer
stable
as $$
    select
        public.miss_run(uid, on_day),
        coalesce((select daily_limit_minutes from public.profiles where id = uid), 0),
        public.best_streak(uid),
        coalesce((
            select round(
                count(*) filter (where limit_met)::numeric
                / nullif(count(*), 0) * 100, 1)
            from public.daily_records
            where user_id = uid
              and not partial
              and day >= on_day - 30
              and day < on_day
        ), 0);
$$;

-- ------------------------------------------------------------- selection

-- Who pays for the group's pass. Only people whose day was judged and
-- missed are considered — an unjudged day isn't anyone's fault.
create or replace function public.pass_loser(gid uuid, on_day date)
returns uuid
language sql
security definer
stable
as $$
    select m.user_id
    from public.group_members m
    join public.daily_records r
      on r.user_id = m.user_id and r.day = on_day
    cross join lateral public.member_standing(m.user_id, on_day) s
    where m.group_id = gid
      and not r.limit_met
      and not r.partial
    order by
        s.miss_run desc,           -- missing repeatedly costs the group most
        s.limit_minutes desc,      -- most generous limit, least excuse
        s.personal_record asc,     -- least they've ever managed
        s.rate_30 asc,             -- weakest recent form
        m.user_id                  -- stable, so every device agrees
    limit 1;
$$;

create or replace function public.spend_group_pass(gid uuid, on_day date)
returns uuid
language plpgsql
security definer
as $$
declare
    loser uuid;
    used_this_week int;
begin
    if exists (
        select 1 from public.streak_passes
        where group_id = gid and day = on_day
    ) then
        return null;
    end if;

    loser := public.pass_loser(gid, on_day);
    if loser is null then
        return null;
    end if;

    select count(*) into used_this_week
    from public.streak_passes
    where user_id = loser
      and kind = 'personal'
      and group_id is null
      and created_at >= date_trunc('week', now());

    insert into public.streak_passes (user_id, group_id, day, kind)
    values (loser, gid, on_day,
            case when used_this_week > 0 then 'group_debt' else 'group' end);

    return loser;
end;
$$;

-- --------------------------------------------------------------- trigger

-- Runs when the last member of a group reports a judged day.
create or replace function public.check_group_day()
returns trigger
language plpgsql
security definer
as $$
declare
    g record;
    member_count int;
    reported_count int;
begin
    if new.partial then
        return new;
    end if;

    for g in
        select group_id from public.group_members where user_id = new.user_id
    loop
        select count(*) into member_count
        from public.group_members where group_id = g.group_id;

        select count(*) into reported_count
        from public.group_members m
        join public.daily_records r
          on r.user_id = m.user_id and r.day = new.day and not r.partial
        where m.group_id = g.group_id;

        if reported_count >= member_count
           and exists (
               select 1 from public.group_members m
               join public.daily_records r
                 on r.user_id = m.user_id and r.day = new.day
               where m.group_id = g.group_id
                 and not r.limit_met and not r.partial
           )
        then
            perform public.spend_group_pass(g.group_id, new.day);
        end if;
    end loop;

    return new;
end;
$$;

drop trigger if exists on_daily_record_saved on public.daily_records;

create trigger on_daily_record_saved
    after insert or update on public.daily_records
    for each row execute function public.check_group_day();
