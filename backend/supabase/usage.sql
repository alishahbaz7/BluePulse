-- App usage monitoring for every app — the server side (app-control skill; first used by BluePulse).
--
-- Run in Supabase → SQL Editor. Safe to run again: it brings any older version of this schema up to
-- date and keeps every row. It creates:
--   schema usage           private: not served by the API, so an app's key can never read it
--     installs            one row per copy of an app, named by `app` (the user list's source)
--     sessions            one row per start of an app; each app's own counters in `metrics`
--     events              updates, errors, first start, version changes, anything an app records
--     apps, users, recent_sessions, daily, versions, activity   views to read it all
--   public.usage_report   the one thing an app's key may call: it writes reports, nothing else
--
-- Where to look: Table Editor → schema "usage" → users (or apps). Times in the views are IST.
-- An app posts {install, sessions, events} to <project URL>/rest/v1/rpc/usage_report; the format is
-- in report-format.md (app-control skill) and backend/supabase/README.md.
--
-- Version 3 · 10-11-2026 · v2 added installs.app · v3 moved app-specific session counters to `metrics`

create schema if not exists usage;
revoke all on schema usage from public;

-- The views are made again at the end; dropped first so the columns they read may change below.
drop view if exists usage.apps, usage.users, usage.recent_sessions, usage.daily, usage.versions, usage.activity;

-- ── Tables ──────────────────────────────────────────────────────────────────────────────────────

create table if not exists usage.installs (
  id           text primary key check (id ~ '^[0-9a-f]{32}$'),
  app          text not null,
  name         text,
  team         text,            -- not asked since v2; kept for rows that have one
  login        text,
  computer     text,
  platform     text not null,
  os           text,
  device       text,
  app_version  text not null,
  build        text not null,
  launcher     boolean,
  time_zone    text,
  first_seen   timestamptz not null default now(),
  last_seen    timestamptz not null default now()
);

-- v2: one server for every app, so each copy names its app. Rows from before were BluePulse.
alter table usage.installs add column if not exists app text;
update usage.installs set app = 'BluePulse' where app is null;
alter table usage.installs alter column app set not null;
create index if not exists installs_app_seen on usage.installs (app, last_seen desc);

create table if not exists usage.sessions (
  id              text primary key check (id ~ '^[0-9a-f]{32}$'),
  install_id      text not null references usage.installs (id) on delete cascade,
  app_version     text,
  started_at      timestamptz not null,
  last_active_at  timestamptz not null,
  ended_at        timestamptz,
  open_seconds    integer not null default 0,
  pages           jsonb   not null default '{}'::jsonb,
  errors          integer not null default 0,
  metrics         jsonb   not null default '{}'::jsonb,   -- the app's own counters, its own names
  received_at     timestamptz not null default now()
);
create index if not exists sessions_install_started on usage.sessions (install_id, started_at desc);
create index if not exists sessions_started on usage.sessions (started_at desc);

-- v3: each app keeps its own counters in `metrics`, so no app adds columns. BluePulse's former
-- columns move there under the names the app now sends.
alter table usage.sessions add column if not exists metrics jsonb not null default '{}'::jsonb;
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'usage' and table_name = 'sessions' and column_name = 'live_seconds') then
    update usage.sessions set metrics = metrics
      || jsonb_build_object('liveSeconds', live_seconds, 'demoSeconds', demo_seconds,
                            'devices', devices, 'packets', packets)
      || case when bluetooth is null then '{}'::jsonb else jsonb_build_object('bluetooth', bluetooth) end;
    alter table usage.sessions
      drop column live_seconds, drop column demo_seconds, drop column devices,
      drop column packets, drop column bluetooth;
  end if;
end $$;

create table if not exists usage.events (
  id           text primary key check (id ~ '^[0-9a-f]{32}$'),
  install_id   text not null references usage.installs (id) on delete cascade,
  session_id   text,
  at           timestamptz not null,
  kind         text not null,
  data         jsonb not null default '{}'::jsonb,
  received_at  timestamptz not null default now()
);
create index if not exists events_install_at on usage.events (install_id, at desc);
create index if not exists events_kind_at on usage.events (kind, at desc);

-- Nobody but the owner reads or writes these directly; the function below writes for the apps.
alter table usage.installs enable row level security;
alter table usage.sessions enable row level security;
alter table usage.events   enable row level security;

-- ── The report an app sends ─────────────────────────────────────────────────────────────────────

create or replace function public.usage_report(
  install  jsonb,
  sessions jsonb default '[]'::jsonb,
  events   jsonb default '[]'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id text := install->>'id';
begin
  if jsonb_typeof(install) is distinct from 'object' or v_id is null or v_id !~ '^[0-9a-f]{32}$' then
    raise exception 'install.id is missing or not 32 hex digits' using errcode = '22023';
  end if;
  if jsonb_typeof(sessions) is distinct from 'array' or jsonb_typeof(events) is distinct from 'array' then
    raise exception 'sessions and events must be arrays' using errcode = '22023';
  end if;
  if jsonb_array_length(sessions) > 200 or jsonb_array_length(events) > 500 then
    raise exception 'too many records in one report' using errcode = '22023';
  end if;

  insert into usage.installs as i
    (id, app, name, login, computer, platform, os, device, app_version, build, launcher, time_zone)
  values (
    v_id,
    coalesce(nullif(left(install->>'app', 60), ''), 'unknown'),
    nullif(left(install->>'name', 120), ''),
    nullif(left(install->>'login', 120), ''),
    nullif(left(install->>'computer', 120), ''),
    coalesce(nullif(left(install->>'platform', 20), ''), 'unknown'),
    nullif(left(install->>'os', 120), ''),
    nullif(left(install->>'device', 120), ''),
    coalesce(nullif(left(install->>'appVersion', 40), ''), 'unknown'),
    coalesce(nullif(left(install->>'build', 10), ''), 'unknown'),
    case when jsonb_typeof(install->'launcher') = 'boolean' then (install->>'launcher')::boolean end,
    nullif(left(install->>'timeZone', 60), '')
  )
  on conflict (id) do update set
    -- A report without an app name (a copy built before it was sent) keeps the one on record.
    app         = case when nullif(install->>'app', '') is not null then excluded.app else i.app end,
    -- A name is never cleared by a report without one: the first start sends before it is asked.
    name        = coalesce(excluded.name, i.name),
    login       = coalesce(excluded.login, i.login),
    computer    = coalesce(excluded.computer, i.computer),
    platform    = excluded.platform,
    os          = coalesce(excluded.os, i.os),
    device      = coalesce(excluded.device, i.device),
    app_version = excluded.app_version,
    build       = excluded.build,
    launcher    = coalesce(excluded.launcher, i.launcher),
    time_zone   = coalesce(excluded.time_zone, i.time_zone),
    last_seen   = now();

  -- Each report carries the latest snapshot of a session; the newest one wins.
  insert into usage.sessions as s
    (id, install_id, app_version, started_at, last_active_at, ended_at, open_seconds, pages, errors, metrics)
  select distinct on (x->>'id')
    x->>'id',
    v_id,
    left(x->>'appVersion', 40),
    (x->>'startedAt')::timestamptz,
    coalesce((x->>'lastActiveAt')::timestamptz, (x->>'startedAt')::timestamptz),
    (x->>'endedAt')::timestamptz,
    greatest(coalesce((x->>'openSeconds')::integer, 0), 0),
    case when jsonb_typeof(x->'pages') = 'object' then x->'pages' else '{}'::jsonb end,
    greatest(coalesce((x->>'errors')::integer, 0), 0),
    -- The app's own counters, as it names them; a runaway object is not stored.
    case when jsonb_typeof(x->'metrics') = 'object' and length((x->'metrics')::text) <= 4000
         then x->'metrics' else '{}'::jsonb end
  from jsonb_array_elements(sessions) as x
  where x->>'id' ~ '^[0-9a-f]{32}$' and x->>'startedAt' is not null
  order by x->>'id', (x->>'lastActiveAt') desc
  on conflict (id) do update set
    app_version    = excluded.app_version,
    last_active_at = excluded.last_active_at,
    ended_at       = excluded.ended_at,
    open_seconds   = excluded.open_seconds,
    pages          = excluded.pages,
    errors         = excluded.errors,
    metrics        = excluded.metrics,
    received_at    = now()
  -- One copy cannot overwrite another's session, and an older snapshot never replaces a newer one.
  where s.install_id = excluded.install_id and excluded.last_active_at >= s.last_active_at;

  insert into usage.events (id, install_id, session_id, at, kind, data)
  select
    x->>'id',
    v_id,
    case when x->>'sessionId' ~ '^[0-9a-f]{32}$' then x->>'sessionId' end,
    (x->>'at')::timestamptz,
    x->>'kind',
    case when jsonb_typeof(x->'data') = 'object' then x->'data' else '{}'::jsonb end
  from jsonb_array_elements(events) as x
  where x->>'id' ~ '^[0-9a-f]{32}$' and x->>'kind' ~ '^[a-z_]{1,40}$' and x->>'at' is not null
  on conflict (id) do nothing;

  -- Control (next) answers here with this copy's policy: allowed or blocked, version, features.
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.usage_report(jsonb, jsonb, jsonb) from public;
grant execute on function public.usage_report(jsonb, jsonb, jsonb) to anon, authenticated;
-- The API reaches the function through schema public. Granted here as well, so the call works
-- whichever Data API defaults the project was created with ("Automatically expose new tables" off).
grant usage on schema public to anon, authenticated;

-- ── Views: how to read it ──────────────────────────────────────────────────────────────────────

-- One row per app: how many people, how active, which version is out.
create view usage.apps with (security_invoker = on) as
select
  i.app,
  count(*)                                                             as installs,
  count(*) filter (where i.last_seen > now() - interval '7 days')      as seen_7d,
  count(*) filter (where i.last_seen > now() - interval '30 days')     as seen_30d,
  (select count(*) from usage.sessions s join usage.installs j on j.id = s.install_id
    where j.app = i.app and s.started_at > now() - interval '7 days')  as launches_7d,
  (array_agg(i.app_version order by i.last_seen desc))[1]              as newest_seen_version,
  (max(i.last_seen) at time zone 'Asia/Kolkata')                       as last_seen_ist
from usage.installs i
group by i.app
order by seen_7d desc, installs desc;

-- The user list: one row per copy, most recently seen first.
create view usage.users with (security_invoker = on) as
select
  i.app,
  i.name,
  i.app_version                                                        as version,
  i.platform,
  (i.last_seen at time zone 'Asia/Kolkata')                            as last_seen_ist,
  (i.first_seen at time zone 'Asia/Kolkata')                           as first_seen_ist,
  count(s.id)                                                          as launches,
  count(s.id) filter (where s.started_at > now() - interval '7 days')  as launches_7d,
  coalesce(sum(s.errors), 0)                                           as errors,
  i.login,
  i.computer,
  i.device,
  i.os,
  i.build,
  i.launcher,
  i.time_zone,
  i.id                                                                 as install_id
from usage.installs i
left join usage.sessions s on s.install_id = i.id
group by i.id
order by i.last_seen desc;

-- Every start of an app, newest first.
create view usage.recent_sessions with (security_invoker = on) as
select
  i.app,
  i.name,
  s.app_version                                                        as version,
  (s.started_at at time zone 'Asia/Kolkata')                           as started_ist,
  round(extract(epoch from (coalesce(s.ended_at, s.last_active_at) - s.started_at)) / 60.0, 1) as minutes,
  s.ended_at is not null                                               as closed_normally,
  s.pages,
  s.errors,
  s.metrics,
  i.computer,
  i.device,
  s.install_id,
  s.id                                                                 as session_id
from usage.sessions s
join usage.installs i on i.id = s.install_id
order by s.started_at desc;

-- People and starts per day, per app.
create view usage.daily with (security_invoker = on) as
select
  (s.started_at at time zone 'Asia/Kolkata')::date                     as day,
  i.app,
  count(distinct s.install_id)                                         as users,
  count(*)                                                             as launches
from usage.sessions s
join usage.installs i on i.id = s.install_id
group by 1, 2
order by 1 desc, 2;

-- Which versions of each app are out there.
create view usage.versions with (security_invoker = on) as
select
  app,
  app_version                                                          as version,
  platform,
  count(*)                                                             as installs,
  count(*) filter (where last_seen > now() - interval '30 days')       as seen_30d,
  (max(last_seen) at time zone 'Asia/Kolkata')                         as last_seen_ist
from usage.installs
group by app, app_version, platform
order by app, seen_30d desc, installs desc;

-- Updates, errors, first starts, version changes and each app's own events, newest first.
create view usage.activity with (security_invoker = on) as
select
  (e.at at time zone 'Asia/Kolkata')                                   as at_ist,
  i.app,
  i.name,
  e.kind,
  e.data,
  i.app_version                                                        as version_now,
  e.install_id,
  e.session_id
from usage.events e
join usage.installs i on i.id = e.install_id
order by e.at desc;

revoke all on all tables in schema usage from public;

-- Tell the API about the function now rather than at its next schema refresh.
notify pgrst, 'reload schema';
