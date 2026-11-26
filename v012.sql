-- V012：道館卡片插畫（實拍轉繪版）
update venues set art = 'assets/venues/' || id || '-photo.webp'
where id in ('tn-huafu','tn-smashdink','tn-jingpai','ks-clike','ks-shenqi');
