-- V009：預設球團（打開 App 直接進這團；存在帳號裡，換手機也一樣）
alter table profiles add column if not exists default_club uuid references clubs(id) on delete set null;
