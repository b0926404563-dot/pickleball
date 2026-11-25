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
