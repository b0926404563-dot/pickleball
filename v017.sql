-- v017：比賽後評分（經驗公式 V1）— 每場存完整計算過程，方便追蹤與重算
alter table rating_snaps add column if not exists ea numeric;        -- 該球員隊伍的預期得分比例 E
alter table rating_snaps add column if not exists sa_ratio numeric;  -- 該球員隊伍的實際得分比例 S
alter table rating_snaps add column if not exists perf numeric;      -- S − E
alter table rating_snaps add column if not exists k numeric;         -- 這場用的 K 值
alter table rating_snaps add column if not exists delta numeric;     -- 這場分數變化 Δ
alter table rating_snaps add column if not exists ver int default 1; -- 2 = 經驗公式 V1
