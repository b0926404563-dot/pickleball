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
