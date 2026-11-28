-- v020：道館標記運動種類（匹克球場／羽球場，可兩者都有）
alter table venues add column if not exists sports text[] not null default '{pickleball}';
update venues set sports = '{pickleball}'            where id in ('tn-huafu','tn-smashdink','ks-clike','ks-shenqi');
update venues set sports = '{pickleball,badminton}'  where id = 'tn-jingpai';
update venues set sports = '{badminton}'             where id = 'ks-yuni';
