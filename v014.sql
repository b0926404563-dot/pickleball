-- V014：華府面數暫不顯示（各來源不一致：場地資料寫 2 面、實景插畫可見 4 面，待確認正式面數）
update venues set courts = null where id = 'tn-huafu';
