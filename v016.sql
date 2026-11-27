-- v016：比分簡化確認
--   場上球員或房主送出比分 → 直接算數（不用等對手確認）
--   打完 30 分鐘內，場上球員或房主發現打錯，可以直接改
--   其他人代送（非場上、非房主）仍維持「待確認」
create or replace function report_score(gid uuid, x int, y int) returns void
language plpgsql security definer set search_path = public as $$
declare g games; side text; ok boolean;
begin
  select * into g from games where id = gid;
  if g.id is null or not is_member(g.club_id) then raise exception '沒有權限'; end if;
  if x is null or y is null or x < 0 or y < 0 or x > 99 or y > 99 then raise exception '比分格式不對'; end if;
  if x = y then raise exception '比分不能平手'; end if;
  ok := can_score(g);
  if g.status = 'confirmed' and not is_admin(g.club_id)
     and not (ok and g.ended_at > now() - interval '30 minutes') then
    raise exception '已超過 30 分鐘，只有管理者能修改比分';
  end if;
  side := my_side(g);
  update games set sa = x, sb = y,
         status = case when ok or is_admin(g.club_id) then 'confirmed' else 'pending' end,
         reported_by = auth.uid(), reported_side = side,
         confirmed_by = case when ok or is_admin(g.club_id) then auth.uid() end,
         ended_at = case when g.status = 'confirmed' and g.ended_at is not null then g.ended_at else now() end
   where id = gid;
end $$;
