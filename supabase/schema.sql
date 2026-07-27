-- ============================================================================
-- ScreenStreaks — Supabase schema
-- Run this in the Supabase SQL Editor (one time).
--
-- Model: the core signal is ONE BOOLEAN per user per day ("did I stay under my
-- limit?"). Streaks and the GitHub-style tiles are derived from daily_records.
-- Works identically for Android (derived from real minutes) and iOS (derived
-- from a DeviceActivityMonitor threshold) — neither needs to store raw minutes.
-- ============================================================================

-- Needed for gen_random_uuid() (present on Supabase by default).
create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- profiles: one row per auth user
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null default 'Friend',
    daily_limit_minutes int not null default 120,
    -- Short code embedded in the share link so a friend can connect to you.
    share_code text not null unique default upper(
        substr(md5(random()::text), 1, 6)
    ),
    timezone text not null default 'UTC',
    created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- daily_records: the streak / tile data (one row per user per day)
-- ----------------------------------------------------------------------------
create table if not exists public.daily_records (
    id uuid primary key default gen_random_uuid (),
    user_id uuid not null references public.profiles (id) on delete cascade,
    day date not null,
    limit_met boolean not null,
    used_minutes int, -- optional; null on iOS (privacy sandbox)
    limit_minutes int not null,
    source text not null default 'auto', -- 'auto' | 'manual'
    updated_at timestamptz not null default now(),
    unique (user_id, day)
);

create index if not exists daily_records_user_day_idx on public.daily_records (user_id, day desc);

-- ----------------------------------------------------------------------------
-- connections: accountability friends (undirected, auto-accepted for MVP)
-- ----------------------------------------------------------------------------
create table if not exists public.connections (
    id uuid primary key default gen_random_uuid (),
    requester_id uuid not null references public.profiles (id) on delete cascade,
    addressee_id uuid not null references public.profiles (id) on delete cascade,
    status text not null default 'accepted', -- 'pending' | 'accepted'
    created_at timestamptz not null default now(),
    unique (requester_id, addressee_id),
    check (requester_id <> addressee_id)
);

-- Helper: is the current user connected to :other_id ?
create or replace function public.is_connected(other_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.connections c
    where c.status = 'accepted'
      and (
        (c.requester_id = auth.uid() and c.addressee_id = other_id) or
        (c.addressee_id = auth.uid() and c.requester_id = other_id)
      )
  );
$$;

-- ----------------------------------------------------------------------------
-- Auto-create a profile when a new auth user signs up
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name',
      new.raw_user_meta_data ->> 'display_name',
      'Friend'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ----------------------------------------------------------------------------
-- Connect via a share code (bypasses RLS safely; auto-accepts both ways)
-- ----------------------------------------------------------------------------
create or replace function public.redeem_share_code(code text)
returns public.profiles language plpgsql security definer set search_path = public as $$
declare
  target public.profiles;
begin
  select * into target from public.profiles
   where share_code = upper(code);

  if target.id is null then
    raise exception 'Invalid share code';
  end if;
  if target.id = auth.uid() then
    raise exception 'You cannot connect with yourself';
  end if;

  insert into public.connections (requester_id, addressee_id, status)
  values (auth.uid(), target.id, 'accepted')
  on conflict (requester_id, addressee_id) do update set status = 'accepted';

  return target;
end;
$$;

-- ============================================================================
-- Row Level Security
-- ============================================================================
alter table public.profiles enable row level security;

alter table public.daily_records enable row level security;

alter table public.connections enable row level security;

-- profiles: read your own + your connections'; update only your own.
drop policy if exists profiles_select on public.profiles;

create policy profiles_select on public.profiles for
select using (
        id = auth.uid ()
        or public.is_connected (id)
    );

drop policy if exists profiles_update on public.profiles;

create policy profiles_update on public.profiles
for update
    using (id = auth.uid ())
with
    check (id = auth.uid ());

-- daily_records: read your own + your connections'; write only your own.
drop policy if exists records_select on public.daily_records;

create policy records_select on public.daily_records for
select using (
        user_id = auth.uid ()
        or public.is_connected (user_id)
    );

drop policy if exists records_insert on public.daily_records;

create policy records_insert on public.daily_records for insert
with
    check (user_id = auth.uid ());

drop policy if exists records_update on public.daily_records;

create policy records_update on public.daily_records
for update
    using (user_id = auth.uid ())
with
    check (user_id = auth.uid ());

-- connections: see rows you're part of; create where you're the requester.
drop policy if exists connections_select on public.connections;

create policy connections_select on public.connections for
select using (
        requester_id = auth.uid ()
        or addressee_id = auth.uid ()
    );

drop policy if exists connections_insert on public.connections;

create policy connections_insert on public.connections for insert
with
    check (requester_id = auth.uid ());

drop policy if exists connections_delete on public.connections;

create policy connections_delete on public.connections for delete using (
    requester_id = auth.uid ()
    or addressee_id = auth.uid ()
);