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
