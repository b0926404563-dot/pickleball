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
