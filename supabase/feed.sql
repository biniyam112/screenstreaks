-- ============================================================================
-- ScreenStreaks — Social feed (run in the Supabase SQL Editor, after schema.sql)
--
-- Model:
--   feed_events    — one row per milestone a user reaches (auto-created by a
--                    trigger on daily_records). v1 kind = 'streak', fired at
--                    every 7-day mark (7, 14, 21 … "weekly streak").
--   feed_reactions — "celebrate" reactions from friends (one per user/event).
--
-- You see events from yourself + your accepted connections (reuses is_connected
-- from schema.sql). Everything is read/written through security-definer RPCs.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------
create table if not exists public.feed_events (
    id uuid primary key default gen_random_uuid (),
    user_id uuid not null references public.profiles (id) on delete cascade,
    kind text not null, -- 'streak'
    milestone int not null, -- streak length (7, 14, 21 …)
    created_at timestamptz not null default now(),
    unique (user_id, kind, milestone) -- each milestone celebrates once
);

create index if not exists feed_events_created_idx on public.feed_events (created_at desc);

create table if not exists public.feed_reactions (
    event_id uuid not null references public.feed_events (id) on delete cascade,
    user_id uuid not null references public.profiles (id) on delete cascade,
    kind text not null default 'celebrate',
    created_at timestamptz not null default now(),
    primary key (event_id, user_id, kind)
);

-- ----------------------------------------------------------------------------
-- Auto-generate milestone events from daily_records
-- ----------------------------------------------------------------------------
-- When a met-day is written, measure the current streak (the contiguous island
-- of met days ending on that day) and, if it's a multiple of 7, record a
-- 'streak' event. The unique constraint makes this idempotent.
create or replace function public.on_daily_record_feed()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  streak int;
begin
  if NEW.limit_met is true then
    with met as (
      select day, (day - (row_number() over (order by day))::int) as grp
      from public.daily_records
      where user_id = NEW.user_id and limit_met = true and day <= NEW.day
    )
    select count(*) into streak
    from met
    where grp = (select grp from met where day = NEW.day);

    if streak >= 7 and streak % 7 = 0 then
      insert into public.feed_events (user_id, kind, milestone)
      values (NEW.user_id, 'streak', streak)
      on conflict (user_id, kind, milestone) do nothing;
    end if;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_daily_record_feed on public.daily_records;

create trigger trg_daily_record_feed
  after insert or update on public.daily_records
  for each row execute procedure public.on_daily_record_feed();

-- ----------------------------------------------------------------------------
-- Read the feed (self + connections), with reaction counts + my own reaction.
-- ----------------------------------------------------------------------------
-- Drop-before-create: changing a function's return columns needs a DROP first,
-- so later migrations (feed_comments.sql, friend_streaks.sql) can re-shape it.
drop function if exists public.get_feed ();

create function public.get_feed()
returns table (
  id              uuid,
  user_id         uuid,
  display_name    text,
  kind            text,
  milestone       int,
  created_at      timestamptz,
  celebrate_count bigint,
  i_celebrated    boolean
)
language sql stable security definer set search_path = public as $$
  select
    e.id,
    e.user_id,
    p.display_name,
    e.kind,
    e.milestone,
    e.created_at,
    count(r.user_id) as celebrate_count,
    coalesce(bool_or(r.user_id = auth.uid()), false) as i_celebrated
  from public.feed_events e
  join public.profiles p on p.id = e.user_id
  left join public.feed_reactions r
    on r.event_id = e.id and r.kind = 'celebrate'
  where e.user_id = auth.uid() or public.is_connected(e.user_id)
  group by e.id, p.display_name
  order by e.created_at desc
  limit 100;
$$;

-- ----------------------------------------------------------------------------
-- Toggle a 'celebrate' reaction. Returns the new state (true = celebrated).
-- ----------------------------------------------------------------------------
create or replace function public.toggle_celebrate(event uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from public.feed_events e
    where e.id = event
      and (e.user_id = auth.uid() or public.is_connected(e.user_id))
  ) then
    raise exception 'Not allowed';
  end if;

  delete from public.feed_reactions
   where event_id = event and user_id = auth.uid() and kind = 'celebrate';
  if found then
    return false;
  end if;

  insert into public.feed_reactions (event_id, user_id, kind)
  values (event, auth.uid(), 'celebrate');
  return true;
end;
$$;

-- ============================================================================
-- Row Level Security (RPCs above are security-definer; these guard direct access)
-- ============================================================================
alter table public.feed_events enable row level security;

alter table public.feed_reactions enable row level security;

drop policy if exists feed_events_select on public.feed_events;

create policy feed_events_select on public.feed_events for
select using (
        user_id = auth.uid ()
        or public.is_connected (user_id)
    );

drop policy if exists feed_reactions_select on public.feed_reactions;

create policy feed_reactions_select on public.feed_reactions for
select using (
        exists (
            select 1
            from public.feed_events e
            where
                e.id = event_id
                and (
                    e.user_id = auth.uid ()
                    or public.is_connected (e.user_id)
                )
        )
    );

drop policy if exists feed_reactions_write on public.feed_reactions;

create policy feed_reactions_write on public.feed_reactions for all using (user_id = auth.uid ())
with
    check (user_id = auth.uid ());

-- ============================================================================
-- Backfill: create milestone events for everyone's CURRENT streak, so the feed
-- isn't empty for existing users / the demo seed. Safe to re-run.
-- ============================================================================
do $$
declare
  rec record;
  s   int;
  m   int;
begin
  for rec in select id from public.profiles loop
    with met as (
      select day, (day - (row_number() over (order by day))::int) as grp
      from public.daily_records
      where user_id = rec.id and limit_met = true
    )
    select count(*) into s
    from met
    where grp = (select grp from met order by day desc limit 1);

    s := coalesce(s, 0);
    m := 7;
    while m <= s loop
      insert into public.feed_events (user_id, kind, milestone, created_at)
      values (rec.id, 'streak', m, now() - ((s - m) || ' days')::interval)
      on conflict (user_id, kind, milestone) do nothing;
      m := m + 7;
    end loop;
  end loop;
end $$;