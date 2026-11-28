-- v018：新增高雄 Yuni 羽球館（鼓山區龍水一街65號，紫色比賽規格場地，2025/5/25 開幕；場地面數待確認）
insert into venues(id, name, city, address, indoor, courts, sort, art) values
  ('ks-yuni', 'Yuni 羽球館', '高雄', '鼓山區龍水一街65號', true, null, 60, 'assets/venues/ks-yuni-photo.webp')
on conflict (id) do update set name = excluded.name, city = excluded.city, address = excluded.address,
  indoor = excluded.indoor, sort = excluded.sort, art = excluded.art;
