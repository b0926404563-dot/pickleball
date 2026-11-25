-- PickleScore 測試帳號：建立 test01～test10@picklescore.test，並加入「中山獼猴」
-- 使用前：把下面第 5 行的「在這裡輸入密碼」改成你要的測試密碼（10 個帳號共用，至少 6 個字），再按 Run。
do $$
declare
  pw text := '在這裡輸入密碼';
  cid uuid; uid uuid; em text; nick text; i int;
begin
  if pw = '在這裡輸入密碼' or char_length(pw) < 6 then
    raise exception '請先把密碼改掉（至少 6 個字）';
  end if;
  select id into cid from public.clubs where join_code = 'a3e0c9';
  if cid is null then raise exception '找不到中山獼猴球團'; end if;

  for i in 1..10 loop
    em := 'test' || lpad(i::text, 2, '0') || '@picklescore.test';
    nick := '測試' || lpad(i::text, 2, '0');
    select id into uid from auth.users where email = em;
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, email_change, email_change_token_new, recovery_token)
      values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
        extensions.crypt(pw, extensions.gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('name', nick), now(), now(),
        '', '', '', '');
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), uid, uid::text,
        jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true), 'email', now(), now(), now());
    else
      update auth.users set encrypted_password = extensions.crypt(pw, extensions.gen_salt('bf')) where id = uid;
    end if;

    insert into public.profiles (id, nickname, avatar)
    values (uid, nick, jsonb_build_object(
      'av', 'avatar_preset_0' || (((i - 1) % 6) + 1),
      'pb', 'paddle_0' || (((i - 1) % 4) + 1),
      'bd', 'racket_0' || (((i - 1) % 3) + 1), 'v', 1))
    on conflict (id) do nothing;
    insert into public.members (club_id, user_id) values (cid, uid) on conflict do nothing;
    if not exists (select 1 from public.players where club_id = cid and user_id = uid) then
      insert into public.players (club_id, user_id, name) values (cid, uid, nick);
    end if;
  end loop;
end $$;

select email from auth.users where email like '%@picklescore.test' order by email;
