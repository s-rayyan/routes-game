-- Routes leaderboard for Supabase.
-- Paste this whole file into Supabase -> SQL Editor -> New query, then press Run.
-- Safe to run again later; it only creates what is missing and refreshes the functions.
--
-- The game talks to these three functions straight from the browser:
--   routes_submit        post your best all-time score
--   routes_submit_daily  post your score on today's daily map
--   routes_board         read the top 30 (all-time or one day) plus your own rank
--   routes_signup, routes_login, routes_logout, routes_sync_get, routes_sync_put   accounts + cross-device saves (bottom of file)
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

-- ===================== Accounts and cross-device saves =====================
-- Username + password accounts, checked inside the database (passwords are bcrypt-hashed).
-- Logging in gives the device its own session token; your saves and stats sync to your account.

alter table public.routes_players
  add column if not exists username     text,
  add column if not exists pass_hash    text,
  add column if not exists fails        integer not null default 0,
  add column if not exists locked_until timestamptz;
create unique index if not exists routes_players_username on public.routes_players (lower(username)) where username is not null;

create table if not exists public.routes_sessions (
  token_hash text primary key,
  id         uuid not null references public.routes_players(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_used  timestamptz not null default now()
);
create index if not exists routes_sessions_id on public.routes_sessions (id);

create table if not exists public.routes_saves (
  id         uuid primary key references public.routes_players(id) on delete cascade,
  save       jsonb,
  stats      jsonb,
  best       integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.routes_sessions enable row level security;
alter table public.routes_saves    enable row level security;
revoke all on public.routes_sessions, public.routes_saves from public, anon, authenticated;

-- True if p_secret is this player's device secret or one of their login tokens.
create or replace function public.routes_auth(p_id uuid, p_secret text)
returns boolean language plpgsql security definer set search_path = public as $$
declare h text; ok boolean;
begin
  if p_id is null or p_secret is null or length(p_secret) < 16 or length(p_secret) > 128 then return false; end if;
  h := encode(sha256(convert_to(p_secret, 'UTF8')), 'hex');
  select secret_hash = h into ok from routes_players where id = p_id;
  if ok then return true; end if;
  update routes_sessions set last_used = now() where token_hash = h and id = p_id;
  return found;
end $$;

create or replace function public.routes_me(p_id uuid, p_secret text, p_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_id is null or p_secret is null or length(p_secret) < 16 or length(p_secret) > 128 then
    raise exception 'bad device id';
  end if;
  if p_name is null or p_name !~ '^[A-Za-z0-9 _.-]{2,16}$' then
    raise exception 'bad name';
  end if;
  if not exists (select 1 from routes_players where id = p_id) then
    insert into routes_players (id, secret_hash, name)
    values (p_id, encode(sha256(convert_to(p_secret, 'UTF8')), 'hex'), p_name);
  elsif not routes_auth(p_id, p_secret) then
    raise exception 'not your entry';
  else
    update routes_players set name = p_name where id = p_id and name <> p_name;
  end if;
end $$;

-- Turn this device's player into an account (keeps its scores).
create or replace function public.routes_signup(p_id uuid, p_secret text, p_name text, p_username text, p_password text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if p_username is null or p_username !~ '^[A-Za-z0-9_.-]{3,16}$' then
    return json_build_object('error', 'Usernames are 3–16 letters, numbers, _ . or -');
  end if;
  if p_password is null or length(p_password) < 6 or length(p_password) > 72 then
    return json_build_object('error', 'Passwords need at least 6 characters');
  end if;
  perform routes_me(p_id, p_secret, p_name);
  if (select username from routes_players where id = p_id) is not null then
    return json_build_object('error', 'You already have an account on this device');
  end if;
  if exists (select 1 from routes_players where lower(username) = lower(p_username)) then
    return json_build_object('error', 'That username is taken');
  end if;
  update routes_players
     set username = p_username, pass_hash = extensions.crypt(p_password, extensions.gen_salt('bf', 10))
   where id = p_id;
  insert into routes_saves (id) values (p_id) on conflict do nothing;
  return json_build_object('username', p_username, 'name', p_name);
end $$;

-- Log in. Returns a fresh token for this device. If the device had its own (guest) entry,
-- its best scores move into the account and the guest entry is removed.
create or replace function public.routes_login(p_username text, p_password text, p_old_id uuid default null, p_old_secret text default null)
returns json language plpgsql security definer set search_path = public as $$
declare
  p   routes_players%rowtype;
  tok text;
  o   routes_players%rowtype;
begin
  select * into p from routes_players where lower(username) = lower(coalesce(p_username, '')) for update;
  if not found or p_password is null then
    return json_build_object('error', 'Wrong username or password');
  end if;
  if p.locked_until is not null and p.locked_until > now() then
    return json_build_object('error', 'Too many tries. Wait a minute and try again');
  end if;
  if extensions.crypt(p_password, p.pass_hash) <> p.pass_hash then
    update routes_players
       set fails = fails + 1,
           locked_until = case when fails + 1 >= 5 then now() + make_interval(mins => least(60, (2 ^ (fails + 1 - 5))::int)) else null end
     where id = p.id;
    return json_build_object('error', 'Wrong username or password');
  end if;
  update routes_players set fails = 0, locked_until = null where id = p.id;

  -- fold a guest entry from this device into the account
  if p_old_id is not null and p_old_id <> p.id and routes_auth(p_old_id, p_old_secret) then
    select * into o from routes_players where id = p_old_id;
    if o.username is null then
      if o.score > p.score then
        update routes_players set score = o.score, week = o.week, city = o.city, updated_at = o.updated_at where id = p.id;
      end if;
      insert into routes_daily as d (day, id, score, week, updated_at)
        select day, p.id, score, week, updated_at from routes_daily where id = o.id
      on conflict (day, id) do update set score = excluded.score, week = excluded.week, updated_at = excluded.updated_at
        where d.score < excluded.score;
      delete from routes_players where id = o.id;
    end if;
  end if;

  tok := encode(extensions.gen_random_bytes(24), 'hex');
  insert into routes_sessions (token_hash, id) values (encode(sha256(convert_to(tok, 'UTF8')), 'hex'), p.id);
  delete from routes_sessions where id = p.id and token_hash not in
    (select token_hash from routes_sessions where id = p.id order by last_used desc limit 20);
  insert into routes_saves (id) values (p.id) on conflict do nothing;
  return json_build_object('id', p.id, 'token', tok, 'name', p.name, 'username', p.username);
end $$;

create or replace function public.routes_logout(p_id uuid, p_token text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if p_token is null then return json_build_object('ok', false); end if;
  delete from routes_sessions where id = p_id and token_hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex');
  return json_build_object('ok', true);
end $$;

create or replace function public.routes_sync_get(p_id uuid, p_secret text)
returns json language plpgsql security definer set search_path = public as $$
declare r routes_saves%rowtype; u text;
begin
  if not routes_auth(p_id, p_secret) then raise exception 'not signed in'; end if;
  select username into u from routes_players where id = p_id;
  if u is null then return json_build_object('error', 'no account'); end if;
  select * into r from routes_saves where id = p_id;
  return json_build_object('username', u, 'save', r.save, 'stats', r.stats, 'best', coalesce(r.best, 0), 'updated_at', r.updated_at);
end $$;

-- Merges two stats objects the way the game does: numbers keep the higher value,
-- nested objects (best per city, daily scores) merge key by key, dates keep the later one.
create or replace function public.routes_jmax(a jsonb, b jsonb)
returns jsonb language plpgsql immutable set search_path = public as $$
declare k text; v jsonb; o jsonb;
begin
  if a is null or jsonb_typeof(a) <> 'object' then return b; end if;
  if b is null or jsonb_typeof(b) <> 'object' then return a; end if;
  o := a;
  for k, v in select * from jsonb_each(b) loop
    if not (o ? k) then
      o := o || jsonb_build_object(k, v);
    elsif jsonb_typeof(v) = 'number' and jsonb_typeof(o -> k) = 'number' then
      if (v #>> '{}')::numeric > (o ->> k)::numeric then o := o || jsonb_build_object(k, v); end if;
    elsif jsonb_typeof(v) = 'object' and jsonb_typeof(o -> k) = 'object' then
      o := o || jsonb_build_object(k, routes_jmax(o -> k, v));
    elsif jsonb_typeof(v) = 'string' and jsonb_typeof(o -> k) = 'string' then
      if (v #>> '{}') > (o ->> k) then o := o || jsonb_build_object(k, v); end if;
    end if;
  end loop;
  return o;
end $$;

-- Saves this account's game and stats (stats are merged, never lowered). p_clear removes the saved game (after a game ends).
create or replace function public.routes_sync_put(p_id uuid, p_secret text, p_save jsonb default null, p_stats jsonb default null, p_best integer default null, p_clear boolean default false)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not routes_auth(p_id, p_secret) then raise exception 'not signed in'; end if;
  if (select username from routes_players where id = p_id) is null then return json_build_object('error', 'no account'); end if;
  if p_save is not null and (jsonb_typeof(p_save) <> 'object' or octet_length(p_save::text) > 200000) then raise exception 'save too big'; end if;
  if p_stats is not null and (jsonb_typeof(p_stats) <> 'object' or octet_length(p_stats::text) > 50000) then raise exception 'stats too big'; end if;
  insert into routes_saves (id) values (p_id) on conflict do nothing;
  update routes_saves set
    save  = case when p_clear then null when p_save is not null then p_save else save end,
    stats = case when p_stats is null then stats else routes_jmax(stats, p_stats) end,
    best  = greatest(best, least(coalesce(p_best, 0), 1000000)),
    updated_at = now()
  where id = p_id;
  return json_build_object('ok', true);
end $$;

revoke all on function public.routes_auth(uuid, text) from public, anon, authenticated;
revoke all on function public.routes_jmax(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.routes_me(uuid, text, text) from public, anon, authenticated;
revoke all on function public.routes_signup(uuid, text, text, text, text) from public;
revoke all on function public.routes_login(text, text, uuid, text) from public;
revoke all on function public.routes_logout(uuid, text) from public;
revoke all on function public.routes_sync_get(uuid, text) from public;
revoke all on function public.routes_sync_put(uuid, text, jsonb, jsonb, integer, boolean) from public;
grant execute on function public.routes_signup(uuid, text, text, text, text) to anon, authenticated;
grant execute on function public.routes_login(text, text, uuid, text) to anon, authenticated;
grant execute on function public.routes_logout(uuid, text) to anon, authenticated;
grant execute on function public.routes_sync_get(uuid, text) to anon, authenticated;
grant execute on function public.routes_sync_put(uuid, text, jsonb, jsonb, integer, boolean) to anon, authenticated;
