SET timezone='Australia/Sydney';
SET app.actor='库管-老张';
\set ON_ERROR_STOP off

INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('CNY',0.2100,'google');
INSERT INTO material(id,code,category,protocol,internal_name,spec,supplier,purchase_class,reorder_point,price_cny,freight_aud,margin_pct,warranty_months)
VALUES('99990000-0000-0000-0000-000000000001','M0001','面板','knx','KNX四联面板','白','深圳某某','C1',20,320,18,0.45,24),
      ('99990000-0000-0000-0000-000000000002','M0002','面板','knx','KNX四联面板','黑','深圳某某','C1',10,320,18,0.45,24);
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','rough_in',now(),500000);
INSERT INTO project_party(id,project_id,trade,company,contact_name,phone)
VALUES('cccc0000-0000-0000-0000-00000000000e','aaaaaaaa-0000-0000-0000-00000000000a','electrician','Spark电气','Tony','0422000222');
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a',1,now()),('aaaaaaaa-0000-0000-0000-00000000000a',2,now()),
 ('aaaaaaaa-0000-0000-0000-00000000000a',3,now());
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('f0000000-0000-0000-0000-00000000000a','aaaaaaaa-0000-0000-0000-00000000000a','contract','S2',40,'INV-S2',now());
INSERT INTO payment_receipt(milestone_id,method,amount,received_at) VALUES('f0000000-0000-0000-0000-00000000000a','bank',200000,now());
UPDATE payment_milestone SET status='settled' WHERE id='f0000000-0000-0000-0000-00000000000a';
INSERT INTO purchase_order(id,po_no,source_type,supplier,ordered_at,status) VALUES('dddd0000-0000-0000-0000-000000000001','PO-0001','bulk','深圳某某',now(),'ordered');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud) VALUES
 ('dddd0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',100,100,85.20),
 ('dddd0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000002',40,40,85.20);
INSERT INTO stock_out(id,out_no,project_id,receiver_party_id) VALUES('eeee0000-0000-0000-0000-000000000001','OUT-01','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000e');
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud) VALUES('eeee0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',20,85.20);
INSERT INTO stock_return(id,return_no,project_id,returner_party_id,returner_name) VALUES('bbbb0000-0000-0000-0000-000000000001','RET-01','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000e','Tony');
INSERT INTO stock_return_line(return_id,material_id,qty,condition,unit_cost_aud) VALUES
 ('bbbb0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',5,'good',85.20),
 ('bbbb0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',2,'damaged',85.20);

\echo ''
\echo '=========== ★ v0.17 的 bug 已修：退回的好料回到库存了 ==========='
SELECT display_name AS 物料, qty_arrived_total AS 到货, qty_out_total AS 出库,
       qty_returned_good AS 退回好料, qty_adjusted AS 盘点调整, qty_on_hand AS 当前库存
FROM v_material_stock WHERE code='M0001';
\echo '（100 到货 − 20 出库 + 5 退回 = 85；坏的 2 块转 RMA，不回可用库存）'

\echo ''
\echo '=========== 盘点：账面 85，实点只有 82 ==========='
INSERT INTO stocktake(id,take_no,scope,scope_note,counted_by)
VALUES('99000000-0000-0000-0000-000000000001','ST-2026-08-01','partial','A区货架·面板类','库管-老张');
\echo '--- 盘亏不填原因 → 应拒 ---'
INSERT INTO stocktake_line(stocktake_id,material_id,counted_qty)
VALUES('99000000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',82);
\echo '--- 填了原因 → 通过，系统数自动定格 ---'
INSERT INTO stocktake_line(stocktake_id,material_id,counted_qty,reason)
VALUES('99000000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',82,'疑似出库漏录，已查三天无果');
\echo '--- 黑面板盘盈 2 块(盘盈不强制填原因) ---'
INSERT INTO stocktake_line(stocktake_id,material_id,counted_qty,reason)
VALUES('99000000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000002',42,'上批到货多给了');
SELECT code, display_name AS 物料, 账面, 实点, 差额, diff_amount_aud AS 金额, reason AS 原因 FROM v_stocktake_result;

\echo ''
\echo '=========== 审批前：库存不受影响 ==========='
SELECT display_name AS 物料, qty_adjusted AS 盘点调整, qty_on_hand AS 当前库存 FROM v_material_stock WHERE code IN ('M0001','M0002') ORDER BY code;
SELECT take_no, loss_amount_aud AS 盘亏金额, gain_amount_aud AS 盘盈金额,
       approve_threshold AS 审批线, needs_approval AS 需要审批 FROM v_stocktake_summary;

\echo ''
\echo '--- 盘亏 255.60 超过审批线 200，盘点人想自己批 → 应拒 ---'
UPDATE stocktake SET status='approved', approved_by='库管-老张' WHERE id='99000000-0000-0000-0000-000000000001';
\echo '--- 主管审批 → 通过 ---'
SET app.actor='仓储主管-赵经理';
UPDATE stocktake SET status='approved' WHERE id='99000000-0000-0000-0000-000000000001';
SELECT take_no, status, counted_by AS 谁盘的, approved_by AS 谁批的, approved_at::timestamp(0) AS 批准时间 FROM stocktake;

\echo ''
\echo '=========== 审批后：库存自动调整 ==========='
SELECT display_name AS 物料, qty_arrived_total AS 到货, qty_out_total AS 出库,
       qty_returned_good AS 退回, qty_adjusted AS 盘点调整, qty_on_hand AS 当前库存
FROM v_material_stock WHERE code IN ('M0001','M0002') ORDER BY code;

\echo ''
\echo '--- 已审批的盘点单还想改明细 → 应拒 ---'
UPDATE stocktake_line SET counted_qty=90 WHERE stocktake_id='99000000-0000-0000-0000-000000000001';

\echo ''
\echo '=========== 库存流水：四种方向都在，差额永久留痕 ==========='
SELECT display_name AS 物料, direction AS 方向, qty AS 数量, ref_no AS 单号, counterparty AS 对方
FROM v_stock_ledger ORDER BY display_name, direction;
