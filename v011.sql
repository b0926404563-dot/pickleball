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
