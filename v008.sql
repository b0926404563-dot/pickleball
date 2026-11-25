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
