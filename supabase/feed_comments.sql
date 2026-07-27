-- ============================================================================
-- ScreenStreaks — Feed comments (run in the SQL Editor, after feed.sql)
--
-- Adds short comments on feed events, and upgrades get_feed() to also return a
-- comment_count. Additive + idempotent — safe to run on top of feed.sql.
-- ============================================================================

create table if not exists public.feed_comments (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.feed_events (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  body       text not null,
  created_at timestamptz not null default now()
);

create index if not exists feed_comments_event_idx
  on public.feed_comments (event_id, created_at);

alter table public.feed_comments enable row level security;

drop policy if exists feed_comments_select on public.feed_comments;
create policy feed_comments_select on public.feed_comments for select
  using (exists (
    select 1 from public.feed_events e
    where e.id = event_id
      and (e.user_id = auth.uid() or public.is_connected(e.user_id))
  ));

drop policy if exists feed_comments_write on public.feed_comments;
create policy feed_comments_write on public.feed_comments for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- List comments on an event (author name included), oldest first.
-- ----------------------------------------------------------------------------
create or replace function public.get_comments(event uuid)
returns table (
  id           uuid,
  user_id      uuid,
  display_name text,
  body         text,
  created_at   timestamptz
)
language sql stable security definer set search_path = public as $$
  select c.id, c.user_id, p.display_name, c.body, c.created_at
  from public.feed_comments c
  join public.profiles p on p.id = c.user_id
  where c.event_id = event
    and exists (
      select 1 from public.feed_events e
      where e.id = event
        and (e.user_id = auth.uid() or public.is_connected(e.user_id))
    )
  order by c.created_at asc;
$$;

-- ----------------------------------------------------------------------------
-- Add a comment (trimmed, capped at 300 chars). Returns the new comment id.
-- ----------------------------------------------------------------------------
create or replace function public.add_comment(event uuid, body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
begin
  if not exists (
    select 1 from public.feed_events e
    where e.id = event
      and (e.user_id = auth.uid() or public.is_connected(e.user_id))
  ) then
    raise exception 'Not allowed';
  end if;
  if length(trim(coalesce(body, ''))) = 0 then
    raise exception 'Comment is empty';
  end if;

  insert into public.feed_comments (event_id, user_id, body)
  values (event, auth.uid(), left(trim(body), 300))
  returning id into new_id;
  return new_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- Upgrade get_feed() to include comment_count (scalar subqueries avoid join
-- fan-out between reactions and comments).
--
-- NOTE: get_feed() already exists (from feed.sql) with a different return
-- signature, and Postgres won't let CREATE OR REPLACE change a function's
-- return columns — so it must be dropped first.
-- ----------------------------------------------------------------------------
drop function if exists public.get_feed();
create function public.get_feed()
returns table (
  id              uuid,
  user_id         uuid,
  display_name    text,
  kind            text,
  milestone       int,
  created_at      timestamptz,
  celebrate_count bigint,
  i_celebrated    boolean,
  comment_count   bigint
)
language sql stable security definer set search_path = public as $$
  select
    e.id,
    e.user_id,
    p.display_name,
    e.kind,
    e.milestone,
    e.created_at,
    (select count(*) from public.feed_reactions r
       where r.event_id = e.id and r.kind = 'celebrate') as celebrate_count,
    exists (select 1 from public.feed_reactions r
       where r.event_id = e.id and r.kind = 'celebrate'
         and r.user_id = auth.uid()) as i_celebrated,
    (select count(*) from public.feed_comments c
       where c.event_id = e.id) as comment_count
  from public.feed_events e
  join public.profiles p on p.id = e.user_id
  where e.user_id = auth.uid() or public.is_connected(e.user_id)
  order by e.created_at desc
  limit 100;
$$;
