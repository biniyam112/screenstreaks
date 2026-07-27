-- ============================================================================
-- ScreenStreaks — demo friends seed
-- Run this in the Supabase SQL Editor (Dashboard → SQL Editor → New query).
--
-- Creates 3 demo users:
--   • Maya Chen   — CONNECTED to you, met yesterday, long current streak
--   • Leo Martins — CONNECTED to you, slacked yesterday (over limit)
--   • Aisha Bello — NOT connected; connect to her in-app with code  AISHA9
--
-- Idempotent: safe to re-run (it removes the demo users first, then recreates).
-- Prereq: sign into the app once with biniyamdemissew112@gmail.com so your
--         auth user exists (the script links the demos to it by email).
-- Cleanup: see the DELETE at the very bottom (commented out).
-- ============================================================================

create extension if not exists pgcrypto;

-- 1) Remove any previous run. Deleting the auth user cascades to the
--    profile, its daily_records, and its connections.
delete from auth.users
where
    id in (
        '11111111-1111-4111-8111-111111111111',
        '22222222-2222-4222-8222-222222222222',
        '33333333-3333-4333-8333-333333333333'
    );

-- 2) Create the three demo auth users. They never log in — they exist only so
--    profiles (which reference auth.users) have something to point at.
insert into
    auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        created_at,
        updated_at,
        raw_app_meta_data,
        raw_user_meta_data,
        confirmation_token,
        recovery_token,
        email_change,
        email_change_token_new,
        reauthentication_token
    )
values (
        '00000000-0000-0000-0000-000000000000',
        '11111111-1111-4111-8111-111111111111',
        'authenticated',
        'authenticated',
        'maya.demo@screenstreaks.app',
        crypt (
            'demo-password',
            gen_salt ('bf')
        ),
        now(),
        now(),
        now(),
        '{"provider":"email","providers":["email"]}',
        '{"display_name":"Maya Chen"}',
        '',
        '',
        '',
        '',
        ''
    ),
    (
        '00000000-0000-0000-0000-000000000000',
        '22222222-2222-4222-8222-222222222222',
        'authenticated',
        'authenticated',
        'leo.demo@screenstreaks.app',
        crypt (
            'demo-password',
            gen_salt ('bf')
        ),
        now(),
        now(),
        now(),
        '{"provider":"email","providers":["email"]}',
        '{"display_name":"Leo Martins"}',
        '',
        '',
        '',
        '',
        ''
    ),
    (
        '00000000-0000-0000-0000-000000000000',
        '33333333-3333-4333-8333-333333333333',
        'authenticated',
        'authenticated',
        'aisha.demo@screenstreaks.app',
        crypt (
            'demo-password',
            gen_salt ('bf')
        ),
        now(),
        now(),
        now(),
        '{"provider":"email","providers":["email"]}',
        '{"display_name":"Aisha Bello"}',
        '',
        '',
        '',
        '',
        ''
    );

-- 3) Set each profile's limit + share code. (handle_new_user() already created
--    the profile rows on insert above; here we set the fields we care about.)
insert into
    public.profiles (
        id,
        display_name,
        daily_limit_minutes,
        share_code
    )
values (
        '11111111-1111-4111-8111-111111111111',
        'Maya Chen',
        90,
        'MAYA24'
    ),
    (
        '22222222-2222-4222-8222-222222222222',
        'Leo Martins',
        150,
        'LEO377'
    ),
    (
        '33333333-3333-4333-8333-333333333333',
        'Aisha Bello',
        120,
        'AISHA9'
    )
on conflict (id) do
update
set
    display_name = excluded.display_name,
    daily_limit_minutes = excluded.daily_limit_minutes,
    share_code = excluded.share_code;

-- 4) ~14 weeks of daily records → drives streaks, the weekly strip, and the grid.

-- Maya: steady, and the last 14 days (incl. yesterday & today) are all met,
--       so she has a live, long current streak.
insert into
    public.daily_records (
        user_id,
        day,
        limit_met,
        used_minutes,
        limit_minutes,
        source
    )
select
    '11111111-1111-4111-8111-111111111111',
    d::date,
    met,
    case
        when met then 54
        else 116
    end,
    90,
    'auto'
from (
        select d, (
                d::date >= current_date - 13
                or random() < 0.82
            ) as met
        from generate_series(
                current_date - 97, current_date, interval '1 day'
            ) d
    ) s;

-- Leo: fine earlier, but OVER his limit the last two days (incl. yesterday);
--      today is left unlogged → current streak 0, fresh red on the recent days.
insert into
    public.daily_records (
        user_id,
        day,
        limit_met,
        used_minutes,
        limit_minutes,
        source
    )
select
    '22222222-2222-4222-8222-222222222222',
    d::date,
    met,
    case
        when met then 92
        else 190
    end,
    150,
    'auto'
from (
        select
            d, case
                when d::date >= current_date - 2 then false
                else random() < 0.6
            end as met
        from generate_series(
                current_date - 97, current_date - 1, interval '1 day'
            ) d
    ) s;

-- Aisha: moderate history plus a small fresh streak (last 4 days met), so her
--        profile looks alive once you connect to her.
insert into
    public.daily_records (
        user_id,
        day,
        limit_met,
        used_minutes,
        limit_minutes,
        source
    )
select
    '33333333-3333-4333-8333-333333333333',
    d::date,
    met,
    case
        when met then 70
        else 150
    end,
    120,
    'auto'
from (
        select d, (
                d::date >= current_date - 3
                or random() < 0.7
            ) as met
        from generate_series(
                current_date - 97, current_date, interval '1 day'
            ) d
    ) s;

-- 5) Connect Maya + Leo to YOU (found by email). Aisha is left unconnected.
do $$
declare me uuid;
begin
  select id into me from auth.users
   where email = 'biniyamdemissew112@gmail.com'
   order by created_at desc limit 1;

  if me is null then
    raise exception
      'No account found for biniyamdemissew112@gmail.com. Open the app, sign in with Google once, then re-run this script.';
  end if;

  insert into public.connections (requester_id, addressee_id, status)
  values
    (me, '11111111-1111-4111-8111-111111111111', 'accepted'),
    (me, '22222222-2222-4222-8222-222222222222', 'accepted')
  on conflict (requester_id, addressee_id) do update set status = 'accepted';
end $$;

-- Confirmation: this is the friend to add in-app (Connect → enter code).
select
    display_name as connect_with,
    share_code as code
from public.profiles
where
    id = '33333333-3333-4333-8333-333333333333';

-- ----------------------------------------------------------------------------
-- To remove all demo data later, run just this line:
-- delete from auth.users where id in (
--   '11111111-1111-4111-8111-111111111111',
--   '22222222-2222-4222-8222-222222222222',
--   '33333333-3333-4333-8333-333333333333');
-- ----------------------------------------------------------------------------