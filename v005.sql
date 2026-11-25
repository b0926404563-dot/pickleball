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

-- 清掉現在已經沒人的等待中房間
update sessions set status = 'done', ended_at = now()
 where status = 'lobby' and cardinality(present) = 0 and started_at < now() - interval '2 minutes';
