SET timezone='Australia/Sydney';
SET app.actor='库管-老张';
\set ON_ERROR_STOP off

INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('CNY',0.2100,'google'),('USD',1.5200,'google');
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,phone,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','小陈','hourly',80,'0411000111','2025-01-01');
INSERT INTO material(id,code,category,protocol,internal_name,spec,supplier,purchase_class,reorder_point,price_cny,freight_aud,margin_pct)
VALUES('99990000-0000-0000-0000-000000000001','M0001','面板','knx','KNX四联面板','白','深圳某某','C1',20,320,18,0.45),
      ('99990000-0000-0000-0000-000000000002','M0002','面板','knx','KNX四联面板','黑','深圳某某','C1',10,320,18,0.45);
INSERT INTO material(id,code,category,protocol,internal_name,supplier,purchase_class,price_aud,margin_pct)
VALUES('99990000-0000-0000-0000-000000000010','M0010','线材','none','Cat6网线','悉尼本地','C2',2.50,0.30);

-- 两个项目：A 已结清 S2，B 没结清
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','rough_in',now(),500000),
 ('bbbbbbbb-0000-0000-0000-00000000000b','KX-2026-0143','rough_in',now(),300000);
-- 项目A：S2 已结清（走完整流程：SM1~3 完成 → 开票 → 收款 → 结清）
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a',1,now()),
 ('aaaaaaaa-0000-0000-0000-00000000000a',2,now()),
 ('aaaaaaaa-0000-0000-0000-00000000000a',3,now());
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('f0000000-0000-0000-0000-00000000000a','aaaaaaaa-0000-0000-0000-00000000000a','contract','S2',40,'INV-A-S2',now());
INSERT INTO payment_receipt(milestone_id,method,amount,received_at)
VALUES('f0000000-0000-0000-0000-00000000000a','bank',200000,now());
UPDATE payment_milestone SET status='settled' WHERE id='f0000000-0000-0000-0000-00000000000a';
-- 项目B：S2 还没结清
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due,status)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','contract','S2',40,120000,'pending');
INSERT INTO project_party(id,project_id,trade,company,contact_name,phone) VALUES
 ('cccc0000-0000-0000-0000-00000000000a','aaaaaaaa-0000-0000-0000-00000000000a','electrician','Spark电气','Tony','0422000222'),
 ('cccc0000-0000-0000-0000-00000000000b','bbbbbbbb-0000-0000-0000-00000000000b','builder','BuildCo','Mike','0433000333');

\echo ''
\echo '=========== 一、采购下单（还没到货，算在途） ==========='
INSERT INTO purchase_order(id,po_no,source_type,supplier,ordered_at,expected_at,status,created_by)
VALUES('dddd0000-0000-0000-0000-000000000001','PO-2026-0087','bulk','深圳某某',now()-interval '10 days',current_date+3,'ordered','采购-王小美');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,unit_cost_aud) VALUES
 ('dddd0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',50,85.20),
 ('dddd0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000002',30,85.20);
SELECT code, internal_name AS 物料, spec AS 规格, qty_in_transit AS 在途, qty_on_hand AS 库存,
       reorder_point AS 红线, below_reorder AS 低于红线 FROM v_material_stock ORDER BY code;

\echo ''
\echo '=========== 二、到货入库：自动转"已入库" ==========='
UPDATE purchase_order_line SET qty_arrived=50 WHERE po_id='dddd0000-0000-0000-0000-000000000001' AND material_id='99990000-0000-0000-0000-000000000001';
SELECT po_no, status AS 单据状态, arrived_at IS NOT NULL AS 已到货 FROM purchase_order;
\echo '--- 剩下那批也到齐 ---'
UPDATE purchase_order_line SET qty_arrived=30 WHERE po_id='dddd0000-0000-0000-0000-000000000001' AND material_id='99990000-0000-0000-0000-000000000002';
SELECT po_no, status AS 单据状态, arrived_at::timestamp(0) AS 到货时间 FROM purchase_order;
\echo '--- 到货数超过下单数 → 应拒 ---'
UPDATE purchase_order_line SET qty_arrived=60 WHERE po_id='dddd0000-0000-0000-0000-000000000001' AND material_id='99990000-0000-0000-0000-000000000001';

\echo ''
\echo '=========== 三、出库门禁 ==========='
\echo '--- 项目B 的 S2 没结清 → 不放货 ---'
INSERT INTO stock_out(out_no,project_id,receiver_staff_id)
VALUES('OUT-B-01','bbbbbbbb-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111');
\echo '--- 拿别的项目的电工来提本项目的货 → 应拒 ---'
INSERT INTO stock_out(out_no,project_id,receiver_party_id)
VALUES('OUT-A-99','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000b');
\echo '--- 既选自己人又选参建方 → 应拒 ---'
INSERT INTO stock_out(out_no,project_id,receiver_staff_id,receiver_party_id)
VALUES('OUT-A-98','aaaaaaaa-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111','cccc0000-0000-0000-0000-00000000000a');

\echo ''
\echo '--- 正常出库给项目A的电工 Tony ---'
INSERT INTO stock_out(id,out_no,project_id,receiver_party_id,created_by)
VALUES('eeee0000-0000-0000-0000-000000000001','OUT-2026-0142-01','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000a','库管-老张');
SELECT out_no, receiver_name AS 提货人, receiver_phone AS 手机, status FROM stock_out;
\echo '--- 出库数量超过库存 → 应拒 ---'
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud)
VALUES('eeee0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',80,85.20);
\echo '--- 正常出库 12 白 + 6 黑 ---'
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud) VALUES
 ('eeee0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',12,85.20),
 ('eeee0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000002',6,85.20);

\echo ''
\echo '=========== 四、提货清单短信自动生成 ==========='
SELECT channel, recipient AS 发给谁, status FROM notification WHERE ref_kind='stock_out';
SELECT body AS 短信内容 FROM notification WHERE ref_kind='stock_out';

\echo ''
\echo '=========== 五、提货人回 yes → 自动置"已接收" ==========='
UPDATE notification SET status='sent', sent_at=now() WHERE ref_kind='stock_out';
UPDATE notification SET status='replied_yes', replied_at=now() WHERE ref_kind='stock_out';
SELECT out_no, status AS 出库状态, received_via AS 确认方式, received_at::timestamp(0) AS 确认时间 FROM stock_out;

\echo ''
\echo '=========== 六、库存现算 + 红线预警 ==========='
SELECT code, internal_name AS 物料, spec AS 规格, qty_arrived_total AS 累计到货,
       qty_out_total AS 累计出库, qty_on_hand AS 当前库存, reorder_point AS 红线,
       below_reorder AS 低于红线 FROM v_material_stock ORDER BY code;
SELECT internal_name AS 需补货, spec, qty_on_hand AS 现有, shortfall AS 缺口 FROM v_reorder_alert;

\echo ''
\echo '=========== 七、库存流水 + 项目物料成本 ==========='
SELECT internal_name AS 物料, spec, direction AS 方向, qty AS 数量, ref_no AS 单号, counterparty AS 对方
FROM v_stock_ledger ORDER BY at, direction;
SELECT project_code, material_cost_aud AS 物料成本, pending_confirm AS 待确认, confirmed AS 已确认
FROM v_project_material_cost;
