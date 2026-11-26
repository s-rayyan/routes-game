-- Routes leaderboard for Supabase.
-- Paste this whole file into Supabase -> SQL Editor -> New query, then press Run.
-- Safe to run again later; it only creates what is missing and refreshes the functions.
--
-- The game talks to these three functions straight from the browser:
--   routes_submit        post your best all-time score
--   routes_submit_daily  post your score on today's daily map
--   routes_board         read the top 30 (all-time or one day) plus your own rank
-- The tables themselves are locked: nobody can read the secrets or edit anyone's row.
-- Each device keeps a random secret, and only that device can update its own entry.

create table if not exists public.routes_players (
  id          uuid primary key,
  secret_hash text not null,
  name        text not null,
  score       integer not null default 0,
  week        integer not null default 1,
  city        text not null default '',
  updated_at  timestamptz not null default now()
);
create index if not exists routes_players_score on public.routes_players (score desc, updated_at);

create table if not exists public.routes_daily (
  day        date not null,
  id         uuid not null references public.routes_players(id) on delete cascade,
  score      integer not null default 0,
  week       integer not null default 1,
  updated_at timestamptz not null default now(),
  primary key (day, id)
);
create index if not exists routes_daily_score on public.routes_daily (day, score desc, updated_at);

alter table public.routes_players enable row level security;
alter table public.routes_daily  enable row level security;
revoke all on public.routes_players, public.routes_daily from public, anon, authenticated;

-- Checks the device secret (or registers a new device) and keeps the nickname current.
create or replace function public.routes_me(p_id uuid, p_secret text, p_name text)
returns void language plpgsql security definer set search_path = public as $$
declare
  h   text;
  old text;
begin
  if p_id is null or p_secret is null or length(p_secret) < 16 or length(p_secret) > 128 then
    raise exception 'bad device id';
  end if;
  if p_name is null or p_name !~ '^[A-Za-z0-9 _.-]{2,16}$' then
    raise exception 'bad name';
  end if;
  h := encode(sha256(convert_to(p_secret, 'UTF8')), 'hex');
  select secret_hash into old from routes_players where id = p_id for update;
  if not found then
    insert into routes_players (id, secret_hash, name) values (p_id, h, p_name);
  elsif old <> h then
    raise exception 'not your entry';
  else
    update routes_players set name = p_name where id = p_id and name <> p_name;
  end if;
end $$;

create or replace function public.routes_submit(
  p_id uuid, p_secret text, p_name text, p_score integer, p_week integer, p_city text)
returns json language plpgsql security definer set search_path = public as $$
declare s integer;
begin
  perform routes_me(p_id, p_secret, p_name);
  if p_score is null or p_score < 0 or p_score > 1000000 then raise exception 'bad score'; end if;
  update routes_players
     set score = p_score,
         week = greatest(1, least(coalesce(p_week, 1), 10000)),
         city = left(coalesce(p_city, ''), 16),
         updated_at = now()
   where id = p_id and (p_score > score or (p_score = score and greatest(1, least(coalesce(p_week, 1), 10000)) > week));
  select score into s from routes_players where id = p_id;
  return json_build_object(
    'score', s,
    'rank', (select count(*) + 1 from routes_players where score > s),
    'of',   greatest(1, (select count(*) from routes_players where score > 0)));
end $$;

create or replace function public.routes_submit_daily(
  p_id uuid, p_secret text, p_name text, p_day date, p_score integer, p_week integer)
returns json language plpgsql security definer set search_path = public as $$
declare s integer;
begin
  perform routes_me(p_id, p_secret, p_name);
  if p_day is null or p_day < current_date - 1 or p_day > current_date + 1 then raise exception 'bad day'; end if;
  if p_score is null or p_score < 0 or p_score > 1000000 then raise exception 'bad score'; end if;
  insert into routes_daily as d (day, id, score, week)
       values (p_day, p_id, p_score, greatest(1, least(coalesce(p_week, 1), 10000)))
  on conflict (day, id) do update
       set score = excluded.score, week = excluded.week, updated_at = now()
     where d.score < excluded.score or (d.score = excluded.score and d.week < excluded.week);
  select score into s from routes_daily where day = p_day and id = p_id;
  return json_build_object(
    'score', s,
    'rank', (select count(*) + 1 from routes_daily where day = p_day and score > s),
    'of',   greatest(1, (select count(*) from routes_daily where day = p_day and score > 0)));
end $$;

create or replace function public.routes_board(p_kind text, p_day date default null, p_id uuid default null)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  rows json;
  me   json;
  ms   integer;
begin
  if p_kind = 'daily' then
    select coalesce(json_agg(r), '[]'::json) into rows from (
      select d.id, p.name, d.score, d.week from routes_daily d join routes_players p on p.id = d.id
       where d.day = p_day and d.score > 0
       order by d.score desc, d.updated_at limit 30) r;
    select d.score, json_build_object('id', d.id, 'name', p.name, 'score', d.score, 'week', d.week)
      into ms, me
      from routes_daily d join routes_players p on p.id = d.id where d.day = p_day and d.id = p_id;
    return json_build_object('rows', rows, 'me', me,
      'myRank', case when ms is null then 0 else (select count(*) + 1 from routes_daily where day = p_day and score > ms) end);
  end if;
  select coalesce(json_agg(r), '[]'::json) into rows from (
    select id, name, score, week, city from routes_players
     where score > 0 order by score desc, updated_at limit 30) r;
  select score, json_build_object('id', id, 'name', name, 'score', score, 'week', week, 'city', city)
    into ms, me from routes_players where id = p_id;
  return json_build_object('rows', rows, 'me', me,
    'myRank', case when ms is null then 0 else (select count(*) + 1 from routes_players where score > ms) end);
end $$;

revoke all on function public.routes_me(uuid, text, text) from public, anon, authenticated;
revoke all on function public.routes_submit(uuid, text, text, integer, integer, text) from public;
revoke all on function public.routes_submit_daily(uuid, text, text, date, integer, integer) from public;
revoke all on function public.routes_board(text, date, uuid) from public;
grant execute on function public.routes_submit(uuid, text, text, integer, integer, text) to anon, authenticated;
grant execute on function public.routes_submit_daily(uuid, text, text, date, integer, integer) to anon, authenticated;
grant execute on function public.routes_board(text, date, uuid) to anon, authenticated;
