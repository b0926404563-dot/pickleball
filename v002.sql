-- V002：房主可以鎖住房間（sessions.cfg.lock = true 時，只有已在房內名單的人能再進來）
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
grant execute on function room_join(uuid) to authenticated;
