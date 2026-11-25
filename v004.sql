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
