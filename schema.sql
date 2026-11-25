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
  status text not null default 'live' check (status in ('live','done')),
  present uuid[] not null default '{}',             -- 出席球員 id
  away uuid[] not null default '{}',                -- 先離場的球員 id
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_by uuid references profiles(id) default auth.uid()
);
create index on sessions(club_id, started_at desc);

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
create policy pl_ins on players for insert to authenticated with check (is_member(club_id) and user_id is null);
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

grant select, insert, update, delete on profiles, clubs, members, players, sessions, games to authenticated;

-- ---------- 即時同步 ----------
do $$ begin
  alter publication supabase_realtime add table games, sessions, players, members;
exception when others then null; end $$;
