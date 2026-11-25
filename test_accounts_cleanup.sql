-- PickleScore：測試完刪除 test01～test10 測試帳號，以及他們打過的比賽（不影響真實球員的分數）
do $$
declare tu uuid[]; tp uuid[];
begin
  select array_agg(id) into tu from auth.users where email like '%@picklescore.test';
  if tu is null then raise notice '沒有測試帳號'; return; end if;
  select coalesce(array_agg(id), '{}') into tp from public.players where user_id = any(tu);

  delete from public.games where a && tp or b && tp;                 -- 有測試帳號參加的比賽
  delete from public.sessions s where s.created_by = any(tu)          -- 測試帳號開的房間
     or (s.present <@ tp and cardinality(s.present) > 0);             -- 只有測試帳號的房間
  update public.sessions set present = (select coalesce(array_agg(x), '{}') from unnest(present) x where not x = any(tp)),
                             ready   = (select coalesce(array_agg(x), '{}') from unnest(ready) x where not x = any(tp)),
                             away    = (select coalesce(array_agg(x), '{}') from unnest(away) x where not x = any(tp))
   where present && tp or ready && tp or away && tp;
  delete from public.players where id = any(tp);
  update public.games set reported_by = null where reported_by = any(tu);
  update public.games set confirmed_by = null where confirmed_by = any(tu);
  update public.score_events set created_by = null where created_by = any(tu);
  delete from auth.users where id = any(tu);                          -- 連帶刪除 profiles、members
end $$;

select count(*) as 剩下的測試帳號 from auth.users where email like '%@picklescore.test';
