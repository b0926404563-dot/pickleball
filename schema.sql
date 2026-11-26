-- =========================================================
--  今天誰贏球 · 俱樂部版  資料庫結構（Supabase / PostgreSQL）
--  使用方式：Supabase 後台 → SQL Editor → 貼上全部 → Run
--  可以重複執行（會先清掉舊的同名物件）
-- =========================================================

-- ---------- 清除（重跑用） ----------
drop table if exists games cascade;
drop table if exists sessions cascade;
drop table if exists players cascade;
drop table if exists members cascade;
drop table if exists clubs cascade;
drop table if exists profiles cascade;

-- ---------- 資料表 ----------
create table profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text unique check (char_length(trim(nickname)) between 1 and 20),
  dupr  numeric(4,3) check (dupr  between 1 and 8),   -- 匹克球起始分數
  bdupr numeric(4,3) check (bdupr between 1 and 8),   -- 羽球起始分數
  avatar jsonb not null default '{}'::jsonb check (octet_length(avatar::text) < 1000),  -- 虛擬人偶外觀
  created_at timestamptz not null default now()
);

create table clubs(
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 40),
  join_code text not null unique default substr(md5(random()::text || clock_timestamp()::text), 1, 6),
  owner uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

create table members(
  club_id uuid not null references clubs(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  primary key (club_id, user_id)
);

-- 球員：有帳號的（user_id）或臨時球員（user_id 為空）
create table players(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references clubs(id) on delete cascade,
  user_id uuid references profiles(id) on delete set null,
  name text not null check (char_length(trim(name)) between 1 and 24),
  dupr  numeric(4,3) check (dupr  between 1 and 8),
  bdupr numeric(4,3) check (bdupr between 1 and 8),
  hidden boolean not null default false,
  created_at timestamptz not null default now(),
  unique (club_id, name),
  unique (club_id, user_id)
);

create table sessions(
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references clubs(id) on delete cascade,
  sport text not null default 'pickleball' check (sport in ('pickleball','badminton')),
  cfg jsonb not null default '{}'::jsonb,           -- {mode, courts, target}
  place text,
  name text,                                        -- 房間名稱
  status text not null default 'lobby' check (status in ('lobby','live','done')),  -- 等待中/比賽中/結束
  present uuid[] not null default '{}',             -- 出席球員 id
  code text,                                        -- 6 碼房間代碼（PS1234）
  ready uuid[] not null default '{}',               -- 已準備的球員 id
  pending uuid[] not null default '{}',             -- 申請加入、等房主同意的球員 id
  away uuid[] not null default '{}',                -- 先離場的球員 id
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_by uuid references profiles(id) default auth.uid()
);
create index on sessions(club_id, started_at desc);
create unique index sessions_open_code on sessions(code) where status <> 'done' and code is not null;

create table games(
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,
  club_id uuid not null references clubs(id) on delete cascade,
  rn int not null,                                   -- 第幾輪
  court int not null,                                -- 場地
  a uuid[] not null,                                 -- A 隊球員 id
  b uuid[] not null,                                 -- B 隊球員 id
  sa int, sb int,
  status text not null default 'open' check (status in ('open','pending','confirmed')),
  reported_by uuid references profiles(id),
  reported_side text check (reported_side in ('a','b')),
  confirmed_by uuid references profiles(id),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  started_at timestamptz,                           -- 房主按「開始這場」的時間
  unique (session_id, rn, court)
);
create index on games(club_id);

-- ---------- 權限小工具 ----------
create or replace function is_member(cid uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists(select 1 from members where club_id = cid and user_id = auth.uid())
$$;
create or replace function is_admin(cid uuid) returns boolean
language sql security definer stable set search_path = public as $$
  select exists(select 1 from members where club_id = cid and user_id = auth.uid() and role in ('owner','admin'))
$$;

-- ---------- RLS ----------
alter table profiles enable row level security;
alter table clubs    enable row level security;
alter table members  enable row level security;
alter table players  enable row level security;
alter table sessions enable row level security;
alter table games    enable row level security;

create policy p_sel on profiles for select to authenticated using (true);
create policy p_ins on profiles for insert to authenticated with check (id = auth.uid());
create policy p_upd on profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy c_sel on clubs for select to authenticated using (is_member(id));
create policy c_upd on clubs for update to authenticated using (owner = auth.uid()) with check (owner = auth.uid());
create policy c_del on clubs for delete to authenticated using (owner = auth.uid());

create policy m_sel on members for select to authenticated using (is_member(club_id));
create policy m_upd on members for update to authenticated
  using (exists(select 1 from clubs c where c.id = club_id and c.owner = auth.uid()) and user_id <> auth.uid());
create policy m_del on members for delete to authenticated
  using ((user_id = auth.uid() and role <> 'owner') or (is_admin(club_id) and role = 'member'));

create policy pl_sel on players for select to authenticated using (is_member(club_id));
-- 不開放直接新增球員：每位球員都必須有自己的帳號（只能透過 create_club / join_club 加入）
create policy pl_upd on players for update to authenticated
  using (is_member(club_id) and (user_id is null or user_id = auth.uid() or is_admin(club_id)))
  with check (is_member(club_id) and (user_id is null or user_id = auth.uid() or is_admin(club_id)));
create policy pl_del on players for delete to authenticated using (is_admin(club_id));

create policy s_sel on sessions for select to authenticated using (is_member(club_id));
create policy s_ins on sessions for insert to authenticated with check (is_member(club_id));
create policy s_upd on sessions for update to authenticated using (is_member(club_id)) with check (is_member(club_id));
create policy s_del on sessions for delete to authenticated using (is_admin(club_id));

create policy g_sel on games for select to authenticated using (is_member(club_id));
create policy g_ins on games for insert to authenticated
  with check (is_member(club_id) and status = 'open'
              and exists(select 1 from sessions s where s.id = session_id and s.club_id = games.club_id and s.status = 'live'));
create policy g_del on games for delete to authenticated
  using (is_member(club_id) and (status = 'open' or is_admin(club_id)));
-- 比分只能透過下面的函式回報／確認，不開放直接修改

-- ---------- 函式 ----------
create or replace function create_club(p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid; nick text; pd numeric; pb numeric;
begin
  select nickname, dupr, bdupr into nick, pd, pb from profiles where id = auth.uid();
  if nick is null then raise exception '請先設定暱稱'; end if;
  insert into clubs(name, owner) values (trim(p_name), auth.uid()) returning id into cid;
  insert into members(club_id, user_id, role) values (cid, auth.uid(), 'owner');
  insert into players(club_id, user_id, name, dupr, bdupr) values (cid, auth.uid(), nick, pd, pb);
  return cid;
end $$;

create or replace function join_club(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid; nick text; pd numeric; pb numeric; gid uuid; nm text;
begin
  select id into cid from clubs where join_code = lower(trim(p_code));
  if cid is null then raise exception '找不到這個邀請碼'; end if;
  select nickname, dupr, bdupr into nick, pd, pb from profiles where id = auth.uid();
  if nick is null then raise exception '請先設定暱稱'; end if;
  insert into members(club_id, user_id) values (cid, auth.uid()) on conflict do nothing;
  if not exists(select 1 from players where club_id = cid and user_id = auth.uid()) then
    -- 名單上有同名的臨時球員：直接接上（過去戰績一起帶過來）
    select id into gid from players where club_id = cid and name = nick and user_id is null;
    if gid is not null then
      update players set user_id = auth.uid(), hidden = false,
             dupr = coalesce(dupr, pd), bdupr = coalesce(bdupr, pb) where id = gid;
    else
      nm := nick;
      if exists(select 1 from players where club_id = cid and name = nm) then
        nm := left(nick, 18) || '#' || substr(auth.uid()::text, 1, 4);
      end if;
      insert into players(club_id, user_id, name, dupr, bdupr) values (cid, auth.uid(), nm, pd, pb);
    end if;
  end if;
  return cid;
end $$;

-- 認領臨時球員（例如管理者先幫你建了名字、打過幾場，你註冊後接上）
create or replace function claim_player(pid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid; mine uuid;
begin
  select club_id into cid from players where id = pid and user_id is null;
  if cid is null or not is_member(cid) then raise exception '這位球員無法認領'; end if;
  select id into mine from players where club_id = cid and user_id = auth.uid();
  if mine is not null then
    if exists(select 1 from games where club_id = cid and (mine = any(a) or mine = any(b))) then
      raise exception '你的帳號已經有比賽紀錄，請管理者協助合併';
    end if;
    update sessions set present = array_remove(present, mine), away = array_remove(away, mine) where club_id = cid;
    delete from players where id = mine;
  end if;
  update players set user_id = auth.uid(), hidden = false where id = pid;
end $$;

create or replace function my_side(g games) returns text
language sql security definer stable set search_path = public as $$
  select case when p.id = any(g.a) then 'a' when p.id = any(g.b) then 'b' end
  from players p where p.club_id = g.club_id and p.user_id = auth.uid()
$$;

create or replace function report_score(gid uuid, x int, y int) returns void
language plpgsql security definer set search_path = public as $$
declare g games; side text; opp uuid[]; auto boolean;
begin
  select * into g from games where id = gid;
  if g.id is null or not is_member(g.club_id) then raise exception '沒有權限'; end if;
  if x is null or y is null or x < 0 or y < 0 or x > 99 or y > 99 then raise exception '比分格式不對'; end if;
  if x = y then raise exception '比分不能平手'; end if;
  if g.status = 'confirmed' and not is_admin(g.club_id) then raise exception '已確認的比分只有管理者能修改'; end if;
  side := my_side(g);
  opp := case side when 'a' then g.b when 'b' then g.a else g.a || g.b end;
  -- 管理者回報、而且對手都是沒有帳號的臨時球員：直接確認
  auto := is_admin(g.club_id) and not exists(select 1 from players p where p.id = any(opp) and p.user_id is not null);
  update games set sa = x, sb = y,
         status = case when auto then 'confirmed' else 'pending' end,
         reported_by = auth.uid(), reported_side = side,
         confirmed_by = case when auto then auth.uid() end, ended_at = now()
   where id = gid;
end $$;

create or replace function confirm_score(gid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g games; side text; opp uuid[];
begin
  select * into g from games where id = gid;
  if g.id is null or not is_member(g.club_id) then raise exception '沒有權限'; end if;
  if g.status <> 'pending' then raise exception '這場目前不需要確認'; end if;
  side := my_side(g);
  opp := case g.reported_side when 'a' then g.b when 'b' then g.a else g.a || g.b end;
  if not (
       is_admin(g.club_id)
    or (side is not null and g.reported_side is not null and side <> g.reported_side)
    or (side is not null and g.reported_side is null and g.reported_by <> auth.uid())
    or (g.reported_by <> auth.uid()
        and not exists(select 1 from players p where p.id = any(opp) and p.user_id is not null))
  ) then
    raise exception '要由對手（或管理者）確認';
  end if;
  update games set status = 'confirmed', confirmed_by = auth.uid() where id = gid;
end $$;

grant execute on function create_club(text), join_club(text), claim_player(uuid),
  report_score(uuid,int,int), confirm_score(uuid), is_member(uuid), is_admin(uuid) to authenticated;
revoke execute on function my_side(games) from public, anon;

-- ---------- 對戰房間 ----------
create or replace function room_join(sid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid; st text; pid uuid; lk boolean; pres uuid[]; host uuid;
begin
  select club_id, status, coalesce((cfg->>'lock')::boolean, false), present, created_by
    into cid, st, lk, pres, host from sessions where id = sid;
  if cid is null or not is_member(cid) then raise exception '找不到這個房間'; end if;
  if st = 'done' then raise exception '這個房間已經關閉了'; end if;
  select id into pid from players where club_id = cid and user_id = auth.uid();
  if pid is null then raise exception '你在這個俱樂部還沒有球員資料'; end if;
  if lk and host is distinct from auth.uid() and not (pid = any(coalesce(pres, '{}'))) then
    raise exception '房主已鎖住這個房間，請房主先開放加入';
  end if;
  -- 一次只能待在一個房間：離開同俱樂部其他房間
  update sessions set present = array_remove(present, pid)
    where club_id = cid and id <> sid and status = 'lobby' and pid = any(present);
  update sessions set away = array_append(coalesce(away,'{}'), pid)
    where club_id = cid and id <> sid and status = 'live' and pid = any(present) and not (pid = any(coalesce(away,'{}')));
  update sessions set
    present = case when pid = any(present) then present else array_append(present, pid) end,
    away = array_remove(coalesce(away,'{}'), pid)
  where id = sid;
end $$;

create or replace function room_leave(sid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid; st text; pid uuid;
begin
  select club_id, status into cid, st from sessions where id = sid;
  if cid is null or not is_member(cid) then raise exception '找不到這個房間'; end if;
  select id into pid from players where club_id = cid and user_id = auth.uid();
  if pid is null then return; end if;
  if st = 'lobby' then
    update sessions set present = array_remove(present, pid) where id = sid;
  elsif st = 'live' then
    update sessions set away = array_append(array_remove(coalesce(away,'{}'), pid), pid) where id = sid;
  end if;
end $$;

grant execute on function room_join(uuid), room_leave(uuid) to authenticated;


grant select, insert, update, delete on profiles, clubs, members, players, sessions, games to authenticated;

-- ---------- 即時同步 ----------
do $$ begin
  alter publication supabase_realtime add table games, sessions, players, members;
exception when others then null; end $$;

-- ---------- 即時計分 ----------
create table if not exists score_events(
  id bigint generated always as identity primary key,
  game_id uuid not null references games(id) on delete cascade,
  club_id uuid not null references clubs(id) on delete cascade,
  side text not null check (side in ('a','b')),
  client_id uuid not null unique,                   -- 防止網路重送造成重複得分
  voided boolean not null default false,            -- 復原＝作廢最後一分
  created_by uuid references profiles(id) default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists score_events_game on score_events(game_id, id);
alter table score_events enable row level security;
drop policy if exists se_sel on score_events;
create policy se_sel on score_events for select to authenticated using (is_member(club_id));
grant select on score_events to authenticated;

create or replace function can_score(g games) returns boolean
language sql security definer stable set search_path = public as $$
  select is_admin(g.club_id)
      or my_side(g) is not null
      or exists(select 1 from sessions s where s.id = g.session_id and s.created_by = auth.uid())
$$;

create or replace function score_point(gid uuid, sd text, cid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g games;
begin
  select * into g from games where id = gid;
  if g.id is null or not is_member(g.club_id) then raise exception '沒有權限'; end if;
  if sd not in ('a','b') then raise exception '隊伍不對'; end if;
  if g.status <> 'open' then raise exception '這場已經送出比分了'; end if;
  if not exists(select 1 from sessions s where s.id = g.session_id and s.status = 'live') then raise exception '比賽尚未開始或已結束'; end if;
  if not can_score(g) then raise exception '只有場上球員或房主可以記分'; end if;
  insert into score_events(game_id, club_id, side, client_id) values (gid, g.club_id, sd, cid)
  on conflict (client_id) do nothing;
end $$;

create or replace function score_undo(gid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g games;
begin
  select * into g from games where id = gid;
  if g.id is null or not is_member(g.club_id) then raise exception '沒有權限'; end if;
  if g.status <> 'open' then raise exception '這場已經送出比分了'; end if;
  if not can_score(g) then raise exception '只有場上球員或房主可以記分'; end if;
  update score_events set voided = true
   where id = (select id from score_events where game_id = gid and not voided order by id desc limit 1);
end $$;

revoke execute on function can_score(games) from public, anon;
grant execute on function score_point(uuid,text,uuid), score_undo(uuid) to authenticated;

do $$ begin
  alter publication supabase_realtime add table score_events;
exception when others then null; end $$;

-- ---------- V001：房間代碼、準備、場次開打 ----------
create or replace function room_by_code(p_code text) returns uuid
language plpgsql security definer stable set search_path = public as $$
declare sid uuid;
begin
  select id into sid from sessions
   where upper(code) = upper(trim(p_code)) and status <> 'done' and is_member(club_id)
   order by started_at desc limit 1;
  if sid is null then raise exception '找不到這個房間代碼（或你不是這個球團的成員）'; end if;
  return sid;
end $$;

create or replace function room_ready(sid uuid, val boolean) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid; pid uuid;
begin
  select club_id into cid from sessions where id = sid;
  if cid is null or not is_member(cid) then raise exception '找不到這個房間'; end if;
  select id into pid from players where club_id = cid and user_id = auth.uid();
  if pid is null then raise exception '你在這個球團還沒有球員資料'; end if;
  update sessions set ready = case when val then (case when pid = any(ready) then ready else array_append(ready, pid) end)
                                   else array_remove(ready, pid) end
   where id = sid;
end $$;

create or replace function game_start(gid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g games; s sessions; n int;
begin
  select * into g from games where id = gid;
  if g.id is null or not is_member(g.club_id) then raise exception '沒有權限'; end if;
  select * into s from sessions where id = g.session_id;
  if s.status <> 'live' then raise exception '比賽還沒開始或已結束'; end if;
  if not (s.created_by = auth.uid() or is_admin(g.club_id)) then raise exception '只有房主或團長／幹部可以開始場次'; end if;
  if g.status <> 'open' then raise exception '這場已經打完了'; end if;
  if g.started_at is not null then return; end if;
  if exists(select 1 from games x where x.session_id = g.session_id and x.id <> g.id and x.status = 'open'
             and x.started_at is not null and (x.a || x.b) && (g.a || g.b)) then
    raise exception '有球員正在另一場比賽中';
  end if;
  select count(*) into n from games x where x.session_id = g.session_id and x.status = 'open' and x.started_at is not null;
  if n >= coalesce((s.cfg->>'courts')::int, 1) then raise exception '場地都在使用中'; end if;
  update games set started_at = now() where id = gid;
end $$;

create or replace function game_stop(gid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g games; s sessions;
begin
  select * into g from games where id = gid;
  if g.id is null or not is_member(g.club_id) then raise exception '沒有權限'; end if;
  select * into s from sessions where id = g.session_id;
  if not (s.created_by = auth.uid() or is_admin(g.club_id)) then raise exception '只有房主或團長／幹部可以取消開打'; end if;
  if g.status <> 'open' then raise exception '這場已經送出比分了'; end if;
  if exists(select 1 from score_events e where e.game_id = gid and not e.voided) then raise exception '這場已經有記分，請先復原到 0:0'; end if;
  update games set started_at = null where id = gid;
end $$;

create or replace function score_point(gid uuid, sd text, cid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g games;
begin
  select * into g from games where id = gid;
  if g.id is null or not is_member(g.club_id) then raise exception '沒有權限'; end if;
  if sd not in ('a','b') then raise exception '隊伍不對'; end if;
  if g.status <> 'open' then raise exception '這場已經送出比分了'; end if;
  if g.started_at is null then raise exception '這場還沒開始，請房主先按「開始這場」'; end if;
  if not exists(select 1 from sessions s where s.id = g.session_id and s.status = 'live') then raise exception '比賽尚未開始或已結束'; end if;
  if not can_score(g) then raise exception '只有場上球員或房主可以記分'; end if;
  insert into score_events(game_id, club_id, side, client_id) values (gid, g.club_id, sd, cid)
  on conflict (client_id) do nothing;
end $$;

grant execute on function room_by_code(text), room_ready(uuid,boolean), game_start(uuid), game_stop(uuid) to authenticated;

-- ========== V003 房主同意制 ==========
-- V003：房主同意制（取代 V002 的鎖房）
--   一般人 room_join → 進入 pending 申請名單；房主 room_admit 同意 / room_reject 拒絕
--   房主也可以 room_admit 直接把球團成員加進房間
alter table sessions add column if not exists pending uuid[] not null default '{}';

-- 內部用：把球員放進房間（同時離開其他房間、移出申請名單）
create or replace function _room_put(sid uuid, pid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select club_id into cid from sessions where id = sid;
  update sessions set present = array_remove(present, pid), pending = array_remove(pending, pid)
    where club_id = cid and id <> sid and status = 'lobby' and (pid = any(present) or pid = any(pending));
  update sessions set pending = array_remove(pending, pid)
    where club_id = cid and id <> sid and status = 'live' and pid = any(pending);
  update sessions set away = array_append(coalesce(away,'{}'), pid)
    where club_id = cid and id <> sid and status = 'live' and pid = any(present) and not (pid = any(coalesce(away,'{}')));
  update sessions set
    present = case when pid = any(present) then present else array_append(present, pid) end,
    away = array_remove(coalesce(away,'{}'), pid),
    pending = array_remove(pending, pid)
  where id = sid;
end $$;
revoke all on function _room_put(uuid, uuid) from public, anon, authenticated;

drop function if exists room_join(uuid);
create function room_join(sid uuid) returns text
language plpgsql security definer set search_path = public as $$
declare cid uuid; st text; pid uuid; pres uuid[]; host uuid;
begin
  select club_id, status, present, created_by into cid, st, pres, host from sessions where id = sid;
  if cid is null or not is_member(cid) then raise exception '找不到這個房間'; end if;
  if st = 'done' then raise exception '這個房間已經關閉了'; end if;
  select id into pid from players where club_id = cid and user_id = auth.uid();
  if pid is null then raise exception '你在這個俱樂部還沒有球員資料'; end if;
  if host = auth.uid() or pid = any(coalesce(pres, '{}')) then
    perform _room_put(sid, pid);
    return 'joined';
  end if;
  update sessions set pending = array_append(array_remove(pending, pid), pid) where id = sid;
  return 'pending';
end $$;

create or replace function room_admit(sid uuid, p_pid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid; st text; host uuid;
begin
  select club_id, status, created_by into cid, st, host from sessions where id = sid;
  if cid is null or host is distinct from auth.uid() then raise exception '只有房主可以同意或加人'; end if;
  if st = 'done' then raise exception '這個房間已經關閉了'; end if;
  if not exists (select 1 from players where id = p_pid and club_id = cid and user_id is not null) then
    raise exception '找不到這位球員';
  end if;
  perform _room_put(sid, p_pid);
end $$;

create or replace function room_reject(sid uuid, p_pid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare host uuid;
begin
  select created_by into host from sessions where id = sid;
  if host is distinct from auth.uid() then raise exception '只有房主可以拒絕申請'; end if;
  update sessions set pending = array_remove(pending, p_pid) where id = sid;
end $$;

create or replace function room_leave(sid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid; st text; pid uuid;
begin
  select club_id, status into cid, st from sessions where id = sid;
  if cid is null or not is_member(cid) then raise exception '找不到這個房間'; end if;
  select id into pid from players where club_id = cid and user_id = auth.uid();
  if pid is null then return; end if;
  update sessions set pending = array_remove(pending, pid) where id = sid;   -- 取消申請
  if st = 'lobby' then
    update sessions set present = array_remove(present, pid) where id = sid;
  elsif st = 'live' and pid = any(present) then
    update sessions set away = array_append(array_remove(coalesce(away,'{}'), pid), pid) where id = sid;
  end if;
end $$;

grant execute on function room_join(uuid), room_admit(uuid, uuid), room_reject(uuid, uuid), room_leave(uuid) to authenticated;

-- 防止繞過：一般球員直接改資料表時，不能把人加進房間名單（只有房主可以）
create or replace function sessions_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' and new.created_by is distinct from auth.uid()
     and not (coalesce(new.present, '{}') <@ coalesce(old.present, '{}')) then
    raise exception '只有房主可以把人加進房間';
  end if;
  return new;
end $$;
drop trigger if exists sessions_guard on sessions;
create trigger sessions_guard before update on sessions for each row execute function sessions_guard();


-- ========== V004 每場分數變化 ==========
-- V004：每場比賽的分數變化（賽前 → 加減 → 賽後），確認時存下來，之後不再變動
create table if not exists rating_snaps(
  game_id uuid not null references games(id) on delete cascade,
  club_id uuid not null references clubs(id) on delete cascade,
  player_id uuid not null references players(id) on delete cascade,
  before numeric(5,3) not null,
  after numeric(5,3) not null,
  created_at timestamptz not null default now(),
  primary key (game_id, player_id)
);
create index if not exists rating_snaps_club on rating_snaps(club_id);
alter table rating_snaps enable row level security;
drop policy if exists rs_sel on rating_snaps;
drop policy if exists rs_ins on rating_snaps;
drop policy if exists rs_upd on rating_snaps;
create policy rs_sel on rating_snaps for select to authenticated using (is_member(club_id));
create policy rs_ins on rating_snaps for insert to authenticated with check (
  is_member(club_id) and exists (select 1 from games g where g.id = game_id and g.club_id = rating_snaps.club_id and g.status = 'confirmed'));
create policy rs_upd on rating_snaps for update to authenticated using (is_member(club_id)) with check (is_member(club_id));
grant select, insert, update on rating_snaps to authenticated;


-- ========== V005 房間沒人自動關閉＋room_leave 修正 ==========
-- V005：房間沒人就自動關閉
--   等待中：房內名單變成 0 人 → 自動關閉（取消）
--   比賽中：所有人都離開 → 自動結束（還沒開打的場次清掉，已填的比分保留）
create or replace function sessions_autoclose() returns trigger
language plpgsql security definer set search_path = public as $$
declare act_old int; act_new int;
begin
  if new.status = 'lobby' and cardinality(coalesce(new.present,'{}')) = 0
     and cardinality(coalesce(old.present,'{}')) > 0 then
    new.status := 'done'; new.ended_at := now();
  elsif new.status = 'live' then
    select count(*) into act_new from unnest(coalesce(new.present,'{}')) p where not (p = any(coalesce(new.away,'{}')));
    select count(*) into act_old from unnest(coalesce(old.present,'{}')) p where not (p = any(coalesce(old.away,'{}')));
    if act_new = 0 and act_old > 0 then
      delete from games where session_id = new.id and status = 'open' and started_at is null;
      new.status := 'done'; new.ended_at := now();
    end if;
  end if;
  return new;
end $$;
drop trigger if exists sessions_autoclose on sessions;
create trigger sessions_autoclose before update on sessions for each row execute function sessions_autoclose();

-- 修正：比賽中按「我先離開」會出錯（V003 的 room_leave）
create or replace function room_leave(sid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid; st text; pid uuid; pres uuid[];
begin
  select club_id, status, present into cid, st, pres from sessions where id = sid;
  if cid is null or not is_member(cid) then raise exception '找不到這個房間'; end if;
  select id into pid from players where club_id = cid and user_id = auth.uid();
  if pid is null then return; end if;
  update sessions set pending = array_remove(pending, pid) where id = sid;   -- 取消申請
  if st = 'lobby' then
    update sessions set present = array_remove(present, pid) where id = sid;
  elsif st = 'live' and pid = any(coalesce(pres, '{}')) then
    update sessions set away = array_append(array_remove(coalesce(away,'{}'), pid), pid) where id = sid;
  end if;
end $$;
grant execute on function room_leave(uuid) to authenticated;



-- ========== V006 天梯排行・全部球團 ==========
-- V006：天梯排行「全部球團」——跨球團的正式比賽（只回傳帳號 id 與比分，不含球團內部資料）
create or replace function global_ladder(p_sport text)
returns table(gid uuid, a uuid[], b uuid[], sa int, sb int, t timestamptz)
language sql stable security definer set search_path = public as $$
  select g.id,
    (select array_agg(p.user_id order by x.o) from unnest(g.a) with ordinality x(pid, o) join players p on p.id = x.pid where p.user_id is not null),
    (select array_agg(p.user_id order by x.o) from unnest(g.b) with ordinality x(pid, o) join players p on p.id = x.pid where p.user_id is not null),
    g.sa, g.sb, coalesce(g.ended_at, s.started_at, g.created_at)
  from games g join sessions s on s.id = g.session_id
  where auth.uid() is not null and g.status = 'confirmed' and s.sport = p_sport
    and g.sa is not null and g.sb is not null
  order by 6
$$;
-- 排行榜上要顯示的暱稱、角色、所屬球團
create or replace function global_people(p_ids uuid[])
returns table(id uuid, nickname text, avatar jsonb, clubs text)
language sql stable security definer set search_path = public as $$
  select pr.id, pr.nickname, pr.avatar,
    (select string_agg(c.name, '、' order by c.name) from members m join clubs c on c.id = m.club_id where m.user_id = pr.id)
  from profiles pr
  where auth.uid() is not null and pr.id = any(p_ids)
$$;
grant execute on function global_ladder(text), global_people(uuid[]) to authenticated;


-- ========== V007 global_ladder 加球團名稱 ==========
-- V007：global_ladder 多回傳球團名稱（個人戰績跨球團合計時顯示是在哪個球團打的）
drop function if exists global_ladder(text);
create function global_ladder(p_sport text)
returns table(gid uuid, a uuid[], b uuid[], sa int, sb int, t timestamptz, club text)
language sql stable security definer set search_path = public as $$
  select g.id,
    (select array_agg(p.user_id order by x.o) from unnest(g.a) with ordinality x(pid, o) join players p on p.id = x.pid where p.user_id is not null),
    (select array_agg(p.user_id order by x.o) from unnest(g.b) with ordinality x(pid, o) join players p on p.id = x.pid where p.user_id is not null),
    g.sa, g.sb, coalesce(g.ended_at, s.started_at, g.created_at), c.name
  from games g join sessions s on s.id = g.session_id join clubs c on c.id = g.club_id
  where auth.uid() is not null and g.status = 'confirmed' and s.sport = p_sport
    and g.sa is not null and g.sb is not null
  order by 6
$$;
grant execute on function global_ladder(text) to authenticated;

-- V008：好友（追蹤制）。追蹤不需要對方同意；每個人只看得到自己追蹤了誰
create table if not exists follows(
  follower uuid not null default auth.uid() references auth.users(id) on delete cascade,
  followee uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower, followee),
  check (follower <> followee)
);
alter table follows enable row level security;
drop policy if exists follows_sel on follows;
drop policy if exists follows_ins on follows;
drop policy if exists follows_del on follows;
create policy follows_sel on follows for select to authenticated using (follower = auth.uid());
create policy follows_ins on follows for insert to authenticated with check (follower = auth.uid());
create policy follows_del on follows for delete to authenticated using (follower = auth.uid());
grant select, insert, delete on follows to authenticated;

-- V009：預設球團（打開 App 直接進這團；存在帳號裡，換手機也一樣）
alter table profiles add column if not exists default_club uuid references clubs(id) on delete set null;

-- V010：道館（場地）。道館清單由管理者用 SQL 建立；開房時選道館；道館排行跨球團
create table if not exists venues(
  id text primary key,
  name text not null,
  city text not null,
  address text,
  indoor boolean,
  courts int,
  art text,
  sort int not null default 0,
  active boolean not null default true
);
alter table venues enable row level security;
drop policy if exists venues_sel on venues;
create policy venues_sel on venues for select to authenticated using (true);
grant select on venues to authenticated;

alter table sessions add column if not exists venue_id text references venues(id) on delete set null;

insert into venues(id, name, city, address, indoor, courts, sort) values
  ('tn-huafu',     '華府匹克球球場',            '台南', '安平區府平路77號',      false, 2, 10),
  ('tn-smashdink', 'Smash Dink 粉碎丁克',        '台南', '永康區中華路1023號',    true,  2, 20),
  ('tn-jingpai',   '羽潮・永康勁拍館',           '台南', '永康區中正南路378-2號', true,  2, 30),
  ('ks-clike',     'CLiKE CLUB 克萊克',          '高雄', '三民區通化街111-1號',   true,  3, 40),
  ('ks-shenqi',    '神綺匹克球場',               '高雄', null,                    true,  1, 50)
on conflict (id) do update set name = excluded.name, city = excluded.city, address = excluded.address,
  indoor = excluded.indoor, courts = excluded.courts, sort = excluded.sort;

-- global_ladder 多回傳道館 id
drop function if exists global_ladder(text);
create function global_ladder(p_sport text)
returns table(gid uuid, a uuid[], b uuid[], sa int, sb int, t timestamptz, club text, venue text)
language sql stable security definer set search_path = public as $$
  select g.id,
    (select array_agg(p.user_id order by x.o) from unnest(g.a) with ordinality x(pid, o) join players p on p.id = x.pid where p.user_id is not null),
    (select array_agg(p.user_id order by x.o) from unnest(g.b) with ordinality x(pid, o) join players p on p.id = x.pid where p.user_id is not null),
    g.sa, g.sb, coalesce(g.ended_at, s.started_at, g.created_at), c.name, s.venue_id
  from games g join sessions s on s.id = g.session_id join clubs c on c.id = g.club_id
  where auth.uid() is not null and g.status = 'confirmed' and s.sport = p_sport
    and g.sa is not null and g.sb is not null
  order by 6
$$;
grant execute on function global_ladder(text) to authenticated;

-- V011：房主邀請 → 對方手機立刻跳出邀請，按接受才進房（取代「直接加進房間」）
alter table sessions add column if not exists invited uuid[] not null default '{}';

-- 放進房間時，一併移出邀請名單
create or replace function _room_put(sid uuid, pid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  select club_id into cid from sessions where id = sid;
  update sessions set present = array_remove(present, pid), pending = array_remove(pending, pid)
    where club_id = cid and id <> sid and status = 'lobby' and (pid = any(present) or pid = any(pending));
  update sessions set pending = array_remove(pending, pid)
    where club_id = cid and id <> sid and status = 'live' and pid = any(pending);
  update sessions set away = array_append(coalesce(away,'{}'), pid)
    where club_id = cid and id <> sid and status = 'live' and pid = any(present) and not (pid = any(coalesce(away,'{}')));
  update sessions set
    present = case when pid = any(present) then present else array_append(present, pid) end,
    away = array_remove(coalesce(away,'{}'), pid),
    pending = array_remove(pending, pid),
    invited = array_remove(invited, pid)
  where id = sid;
end $$;
revoke all on function _room_put(uuid, uuid) from public, anon, authenticated;

-- 房主邀請（可一次多人）；對方如果本來就在申請，直接放進來
create or replace function room_invite(sid uuid, p_pids uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare cid uuid; st text; host uuid; pid uuid; n int := 0; pend uuid[]; pres uuid[];
begin
  select club_id, status, created_by, pending, present into cid, st, host, pend, pres from sessions where id = sid;
  if cid is null or host is distinct from auth.uid() then raise exception '只有房主可以邀請'; end if;
  if st = 'done' then raise exception '這個房間已經關閉了'; end if;
  foreach pid in array coalesce(p_pids, '{}') loop
    if not exists (select 1 from players where id = pid and club_id = cid and user_id is not null) then continue; end if;
    if pid = any(coalesce(pres, '{}')) then continue; end if;
    if pid = any(coalesce(pend, '{}')) then perform _room_put(sid, pid);
    else update sessions set invited = array_append(array_remove(invited, pid), pid) where id = sid; end if;
    n := n + 1;
  end loop;
  return n;
end $$;

-- 被邀請的人回覆：接受就進房，拒絕就移出邀請名單
create or replace function room_invite_reply(sid uuid, ok boolean) returns text
language plpgsql security definer set search_path = public as $$
declare cid uuid; st text; pid uuid; inv uuid[];
begin
  select club_id, status, invited into cid, st, inv from sessions where id = sid;
  if cid is null or not is_member(cid) then raise exception '找不到這個房間'; end if;
  select id into pid from players where club_id = cid and user_id = auth.uid();
  if pid is null or not (pid = any(coalesce(inv, '{}'))) then return 'gone'; end if;
  update sessions set invited = array_remove(invited, pid) where id = sid;
  if not ok then return 'declined'; end if;
  if st = 'done' then return 'closed'; end if;
  perform _room_put(sid, pid);
  return 'joined';
end $$;

-- 房主取消邀請
create or replace function room_uninvite(sid uuid, p_pid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare host uuid;
begin
  select created_by into host from sessions where id = sid;
  if host is distinct from auth.uid() then raise exception '只有房主可以取消邀請'; end if;
  update sessions set invited = array_remove(invited, p_pid) where id = sid;
end $$;

grant execute on function room_invite(uuid, uuid[]), room_invite_reply(uuid, boolean), room_uninvite(uuid, uuid) to authenticated;

-- 防止繞過：非房主不能直接改邀請名單（只能透過 room_invite_reply 移除自己）
create or replace function sessions_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user = 'authenticated' and new.created_by is distinct from auth.uid() then
    if not (coalesce(new.present, '{}') <@ coalesce(old.present, '{}')) then
      raise exception '只有房主可以把人加進房間';
    end if;
    if not (coalesce(new.invited, '{}') <@ coalesce(old.invited, '{}')) then
      raise exception '只有房主可以邀請';
    end if;
  end if;
  return new;
end $$;

-- V012：道館卡片插畫（實拍轉繪版）
update venues set art = 'assets/venues/' || id || '-photo.webp'
where id in ('tn-huafu','tn-smashdink','tn-jingpai','ks-clike','ks-shenqi');

-- V013：global_ladder 多回傳開團的人和場地名稱（比賽紀錄顯示「在哪個道館、誰開的團」）
drop function if exists global_ladder(text);
create function global_ladder(p_sport text)
returns table(gid uuid, a uuid[], b uuid[], sa int, sb int, t timestamptz, club text, venue text, host uuid, place text)
language sql stable security definer set search_path = public as $$
  select g.id,
    (select array_agg(p.user_id order by x.o) from unnest(g.a) with ordinality x(pid, o) join players p on p.id = x.pid where p.user_id is not null),
    (select array_agg(p.user_id order by x.o) from unnest(g.b) with ordinality x(pid, o) join players p on p.id = x.pid where p.user_id is not null),
    g.sa, g.sb, coalesce(g.ended_at, s.started_at, g.created_at), c.name, s.venue_id, s.created_by, s.place
  from games g join sessions s on s.id = g.session_id join clubs c on c.id = g.club_id
  where auth.uid() is not null and g.status = 'confirmed' and s.sport = p_sport
    and g.sa is not null and g.sb is not null
  order by 6
$$;
grant execute on function global_ladder(text) to authenticated;

-- V014：華府面數暫不顯示（各來源不一致：場地資料寫 2 面、實景插畫可見 4 面，待確認正式面數）
update venues set courts = null where id = 'tn-huafu';
