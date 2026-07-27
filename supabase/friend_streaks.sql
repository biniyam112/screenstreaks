-- ============================================================================
-- ScreenStreaks — Weekly friend matching + friend streaks
-- Run in the SQL Editor AFTER schema.sql, feed.sql, feed_comments.sql.
--
-- Mechanic:
--   • Each week (Monday-based) users are paired.
--   • You can request a friend for the UPCOMING week (select_friend). A
--     one-sided request is enough. Mutual requests are honoured first.
--   • Everyone still unpaired is matched RANDOMLY — but only with one of their
--     own connections (never a stranger who can't see their data).
--   • A "friend streak" = consecutive days from that Monday where BOTH friends
--     stayed under their limit. Milestones (3/5/7) post a friend_streak event.
--
-- Requires the pg_cron extension (Supabase: Database → Extensions → enable
-- "pg_cron", or the create extension below if your role may create it).
-- ============================================================================

create extension if not exists pg_cron;

-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------
create table if not exists public.match_selections (
    user_id uuid not null references public.profiles (id) on delete cascade,
    target_id uuid not null references public.profiles (id) on delete cascade,
    week_start date not null,
    created_at timestamptz not null default now(),
    primary key (user_id, week_start),
    check (user_id <> target_id)
);

create table if not exists public.friend_matches (
    id uuid primary key default gen_random_uuid (),
    week_start date not null,
    user_a uuid not null references public.profiles (id) on delete cascade,
    user_b uuid not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (week_start, user_a),
    unique (week_start, user_b),
    check (user_a < user_b)
);

-- ----------------------------------------------------------------------------
-- feed_events: add friend-streak columns + re-key uniqueness with partial
-- indexes (one rule for solo 'streak', one for weekly 'friend_streak').
-- ----------------------------------------------------------------------------

-- Migration cleanup: an earlier version of this file used "partner" naming.
-- Drop those artefacts (function, the index that pointed at partner_id, and the
-- column itself) so this script re-runs cleanly under the new "friend" names.
drop function if exists public.select_partner(uuid);
drop index if exists public.feed_events_friend_uniq;
alter table public.feed_events drop column if exists partner_id;

alter table public.feed_events
add column if not exists friend_id uuid references public.profiles (id) on delete cascade;

alter table public.feed_events
add column if not exists week_start date;

alter table public.feed_events
drop constraint if exists feed_events_user_id_kind_milestone_key;

create unique index if not exists feed_events_streak_uniq on public.feed_events (user_id, milestone)
where
    kind = 'streak';

create unique index if not exists feed_events_friend_uniq on public.feed_events (
    user_id,
    friend_id,
    milestone,
    week_start
)
where
    kind = 'friend_streak';

-- Solo-streak trigger: point ON CONFLICT at the new partial index.
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
      on conflict (user_id, milestone) where kind = 'streak' do nothing;
    end if;
  end if;
  return NEW;
end;
$$;

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------
create or replace function public.are_connected(x uuid, y uuid)
returns boolean language sql stable set search_path = public as $$
  select exists (
    select 1 from public.connections c
    where c.status = 'accepted'
      and ((c.requester_id = x and c.addressee_id = y)
        or (c.requester_id = y and c.addressee_id = x))
  );
$$;

create or replace function public.match_exists(u uuid, wk date)
returns boolean language sql stable set search_path = public as $$
  select exists (
    select 1 from public.friend_matches m
    where m.week_start = wk and (m.user_a = u or m.user_b = u)
  );
$$;

-- ----------------------------------------------------------------------------
-- Request a friend for the UPCOMING week (one-sided is enough).
-- ----------------------------------------------------------------------------
create or replace function public.select_friend(target uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  wk date := (date_trunc('week', now()) + interval '7 days')::date; -- next Monday
begin
  if target = auth.uid() then
    raise exception 'You cannot match with yourself';
  end if;
  if not public.are_connected(auth.uid(), target) then
    raise exception 'You can only match with a friend';
  end if;
  insert into public.match_selections (user_id, target_id, week_start)
  values (auth.uid(), target, wk)
  on conflict (user_id, week_start)
    do update set target_id = excluded.target_id, created_at = now();
end;
$$;

-- ----------------------------------------------------------------------------
-- Weekly matching — run each Monday for the just-started week.
-- ----------------------------------------------------------------------------
create or replace function public.run_weekly_matching()
returns void language plpgsql security definer set search_path = public as $$
declare
  wk    date := date_trunc('week', now())::date;
  rec   record;
  a     uuid;
  b     uuid;
  other uuid;
begin
  -- (1) Mutual selections first.
  for rec in
    select s1.user_id as u, s1.target_id as t
    from public.match_selections s1
    join public.match_selections s2
      on s2.user_id = s1.target_id and s2.target_id = s1.user_id and s2.week_start = wk
    where s1.week_start = wk and s1.user_id < s1.target_id
  loop
    if not public.match_exists(rec.u, wk) and not public.match_exists(rec.t, wk)
       and public.are_connected(rec.u, rec.t) then
      a := least(rec.u, rec.t); b := greatest(rec.u, rec.t);
      insert into public.friend_matches (week_start, user_a, user_b)
      values (wk, a, b) on conflict do nothing;
    end if;
  end loop;

  -- (2) One-sided selections (earliest first).
  for rec in
    select user_id as u, target_id as t
    from public.match_selections where week_start = wk order by created_at
  loop
    if not public.match_exists(rec.u, wk) and not public.match_exists(rec.t, wk)
       and public.are_connected(rec.u, rec.t) then
      a := least(rec.u, rec.t); b := greatest(rec.u, rec.t);
      insert into public.friend_matches (week_start, user_a, user_b)
      values (wk, a, b) on conflict do nothing;
    end if;
  end loop;

  -- (3) Random fallback: pair each remaining user with a random unmatched
  --     connection (never a stranger).
  for rec in select id as u from public.profiles order by random() loop
    if public.match_exists(rec.u, wk) then continue; end if;
    select cxn into other from (
      select case when c.requester_id = rec.u then c.addressee_id else c.requester_id end as cxn
      from public.connections c
      where c.status = 'accepted'
        and (c.requester_id = rec.u or c.addressee_id = rec.u)
    ) x
    where not public.match_exists(x.cxn, wk)
    order by random() limit 1;

    if other is not null then
      a := least(rec.u, other); b := greatest(rec.u, other);
      insert into public.friend_matches (week_start, user_a, user_b)
      values (wk, a, b) on conflict do nothing;
    end if;
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- Score friend streaks — run daily. Consecutive both-met days from Monday.
-- ----------------------------------------------------------------------------
create or replace function public.run_friend_streaks()
returns void language plpgsql security definer set search_path = public as $$
declare
  wk     date := date_trunc('week', now())::date;
  m      record;
  d      date;
  c      int;
  streak int;
  ms     int;
begin
  for m in
    select week_start, user_a, user_b
    from public.friend_matches where week_start = wk
  loop
    streak := 0;
    for d in
      select generate_series(m.week_start, least(current_date, m.week_start + 6),
                             interval '1 day')::date
    loop
      select count(distinct user_id) into c
      from public.daily_records
      where day = d and limit_met = true and user_id in (m.user_a, m.user_b);
      if c = 2 then streak := streak + 1; else exit; end if;
    end loop;

    foreach ms in array array[3, 5, 7] loop
      if streak >= ms then
        insert into public.feed_events (user_id, friend_id, kind, milestone, week_start)
        values (m.user_a, m.user_b, 'friend_streak', ms, wk)
        on conflict (user_id, friend_id, milestone, week_start)
          where kind = 'friend_streak' do nothing;
      end if;
    end loop;
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- This week's match for the current user (for an optional in-app banner).
-- ----------------------------------------------------------------------------
-- Drop first: the earlier "partner" version returned different column names,
-- and a function's return columns can't be changed via CREATE OR REPLACE.
drop function if exists public.get_current_match();
create function public.get_current_match()
returns table (friend_id uuid, friend_name text, streak int)
language plpgsql stable security definer set search_path = public as $$
declare
  wk    date := date_trunc('week', now())::date;
  m     record;
  d     date;
  c     int;
  s     int := 0;
  other uuid;
begin
  select * into m from public.friend_matches
   where week_start = wk and (user_a = auth.uid() or user_b = auth.uid()) limit 1;
  if not found then return; end if;

  other := case when m.user_a = auth.uid() then m.user_b else m.user_a end;
  for d in
    select generate_series(m.week_start, least(current_date, m.week_start + 6),
                           interval '1 day')::date
  loop
    select count(distinct user_id) into c from public.daily_records
    where day = d and limit_met = true and user_id in (m.user_a, m.user_b);
    if c = 2 then s := s + 1; else exit; end if;
  end loop;

  return query
    select other, (select display_name from public.profiles where id = other), s;
end;
$$;

-- ----------------------------------------------------------------------------
-- get_feed() — recreated to carry friend_streak friend info (drop first, as
-- the return signature changes).
-- ----------------------------------------------------------------------------
drop function if exists public.get_feed ();

create function public.get_feed()
returns table (
  id               uuid,
  user_id          uuid,
  display_name     text,
  kind             text,
  milestone        int,
  created_at       timestamptz,
  celebrate_count  bigint,
  i_celebrated     boolean,
  comment_count    bigint,
  friend_id       uuid,
  friend_name     text,
  viewer_is_owner  boolean,
  viewer_is_friend boolean
)
language sql stable security definer set search_path = public as $$
  select
    e.id, e.user_id, p.display_name, e.kind, e.milestone, e.created_at,
    (select count(*) from public.feed_reactions r
       where r.event_id = e.id and r.kind = 'celebrate') as celebrate_count,
    exists (select 1 from public.feed_reactions r
       where r.event_id = e.id and r.kind = 'celebrate'
         and r.user_id = auth.uid()) as i_celebrated,
    (select count(*) from public.feed_comments c
       where c.event_id = e.id) as comment_count,
    e.friend_id,
    pp.display_name as friend_name,
    (e.user_id = auth.uid()) as viewer_is_owner,
    (e.friend_id = auth.uid()) as viewer_is_friend
  from public.feed_events e
  join public.profiles p on p.id = e.user_id
  left join public.profiles pp on pp.id = e.friend_id
  where e.user_id = auth.uid()
     or e.friend_id = auth.uid()
     or public.is_connected(e.user_id)
  order by e.created_at desc
  limit 100;
$$;

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table public.match_selections enable row level security;

alter table public.friend_matches enable row level security;

drop policy if exists match_selections_rw on public.match_selections;

create policy match_selections_rw on public.match_selections for all using (user_id = auth.uid ())
with
    check (user_id = auth.uid ());

drop policy if exists friend_matches_select on public.friend_matches;

create policy friend_matches_select on public.friend_matches for
select using (
        user_a = auth.uid ()
        or user_b = auth.uid ()
    );

-- ----------------------------------------------------------------------------
-- Schedules (UTC). Monday 00:05 = matching; daily 00:15 = scoring.
-- ----------------------------------------------------------------------------
do $$ begin perform cron.unschedule('weekly-matching'); exception when others then null; end $$;

do $$ begin perform cron.unschedule('friend-streaks');  exception when others then null; end $$;

select cron.schedule (
        'weekly-matching', '5 0 * * 1', $$select public.run_weekly_matching();$$
    );

select cron.schedule (
        'friend-streaks', '15 0 * * *', $$select public.run_friend_streaks();$$
    );

-- ----------------------------------------------------------------------------
-- Test it now (optional): record a selection for THIS week, then run both jobs.
--   insert into public.match_selections (user_id, target_id, week_start)
--   values (auth.uid(), '<friend-uuid>', date_trunc('week', now())::date)
--   on conflict (user_id, week_start) do update set target_id = excluded.target_id;
--   select public.run_weekly_matching();
--   select public.run_friend_streaks();
-- ----------------------------------------------------------------------------