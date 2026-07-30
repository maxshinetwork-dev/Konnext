SET timezone='Australia/Sydney';
SET app.actor='库管-老张';
\set ON_ERROR_STOP off

INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('CNY',0.2100,'google');
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,phone,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','小陈','hourly',80,'0411000111','2025-01-01');
INSERT INTO material(id,code,category,protocol,internal_name,spec,supplier,purchase_class,reorder_point,price_cny,freight_aud,margin_pct,warranty_months)
VALUES('99990000-0000-0000-0000-000000000001','M0001','面板','knx','KNX四联面板','白','深圳某某','C1',20,320,18,0.45,24);
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,o1_name,o1_email)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','rough_in',now(),500000,'王先生','wang@example.com');
INSERT INTO project_party(id,project_id,trade,company,contact_name,phone) VALUES
 ('cccc0000-0000-0000-0000-00000000000e','aaaaaaaa-0000-0000-0000-00000000000a','electrician','Spark电气','Tony','0422000222'),
 ('cccc0000-0000-0000-0000-00000000000b','aaaaaaaa-0000-0000-0000-00000000000a','builder','BuildCo','Mike','0433000333');
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a',1,now()),('aaaaaaaa-0000-0000-0000-00000000000a',2,now()),
 ('aaaaaaaa-0000-0000-0000-00000000000a',3,now());
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('f0000000-0000-0000-0000-00000000000a','aaaaaaaa-0000-0000-0000-00000000000a','contract','S2',40,'INV-S2',now()-interval '200 days');
INSERT INTO payment_receipt(milestone_id,method,amount,received_at) VALUES('f0000000-0000-0000-0000-00000000000a','bank',200000,now()-interval '200 days');
UPDATE payment_milestone SET status='settled', settled_at=now()-interval '200 days' WHERE id='f0000000-0000-0000-0000-00000000000a';
INSERT INTO purchase_order(id,po_no,source_type,supplier,ordered_at,status) VALUES('dddd0000-0000-0000-0000-000000000001','PO-0001','bulk','深圳某某',now(),'ordered');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud)
VALUES('dddd0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',100,100,85.20);

\echo ''
\echo '=========== 出库给电工 Tony 20 块 ==========='
INSERT INTO stock_out(id,out_no,project_id,receiver_party_id,created_by)
VALUES('eeee0000-0000-0000-0000-000000000001','OUT-0142-01','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000e','库管-老张');
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud)
VALUES('eeee0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',20,85.20);

\echo '--- ★ 自动告知 Builder：这是未退料计入 Variation 的责任凭证 ---'
SELECT ref_kind, recipient AS 发给谁, subject FROM notification WHERE ref_kind='stock_out_builder';
SELECT body AS 告知内容 FROM notification WHERE ref_kind='stock_out_builder';

\echo ''
\echo '=========== 退库：好料 5 块 + 坏料 2 块 ==========='
INSERT INTO stock_return(id,return_no,project_id,stock_out_id,returner_party_id,received_by)
VALUES('bbbb0000-0000-0000-0000-000000000001','RET-0142-01','aaaaaaaa-0000-0000-0000-00000000000a',
       'eeee0000-0000-0000-0000-000000000001','cccc0000-0000-0000-0000-00000000000e','库管-老张');
UPDATE stock_return SET returner_name='Tony' WHERE id='bbbb0000-0000-0000-0000-000000000001';
\echo '--- 退的比名下未退的还多 → 应拒 ---'
INSERT INTO stock_return_line(return_id,material_id,qty,condition,unit_cost_aud)
VALUES('bbbb0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',30,'good',85.20);
\echo '--- 正常退 5 好 + 2 坏 ---'
INSERT INTO stock_return_line(return_id,material_id,qty,condition,unit_cost_aud) VALUES
 ('bbbb0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',5,'good',85.20),
 ('bbbb0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',2,'damaged',85.20);

\echo ''
\echo '=========== 物料在谁手里 ==========='
SELECT holder AS 在谁手里, display_name AS 物料, qty_out AS 领了, qty_returned AS 退了,
       qty_unreturned AS 未退, is_external AS 外部人员 FROM v_material_custody;

\echo ''
\echo '=========== ★ 未退料 → 计入客户 Variation ==========='
SELECT project_code, holder AS 谁手里, display_name AS 物料, qty_unreturned AS 未退数,
       sell_price_aud AS 售卖价, variation_amount AS 计入变更金额 FROM v_unreturned_to_variation;

\echo ''
\echo '=========== 坏货自动开 RMA + 保修判定（起算=S2结清日） ==========='
SELECT rma_no, display_name AS 物料, qty AS 数量, reporter_name AS 谁退的,
       supplier AS 供应商, warranty_months AS 原厂保修月, s2_settled_on AS S2结清日,
       rma_days AS RMA滞留天, warranty_days_elapsed AS 已过天数, warranty_until AS 保到,
       in_warranty AS 在保, cost_bucket AS 成本归属 FROM v_rma_board;

\echo ''
\echo '=========== 拒收：必须记录谁拒的、原因、货在谁名下 ==========='
\echo '--- 拒收但不填原因 → 应拒 ---'
INSERT INTO stock_return(return_no,project_id,returner_party_id,status)
VALUES('RET-0142-02','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000e','rejected');
\echo '--- 填全了 → 通过 ---'
INSERT INTO stock_return(return_no,project_id,returner_party_id,status,rejected_by,reject_reason,holder_after,returner_name)
VALUES('RET-0142-02','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000e','rejected',
       '库管-老张','货不对版：送回的是三联面板，不是我司发出的四联','Tony(Spark电气)','Tony');
SELECT return_no, status, rejected_by AS 谁拒的, reject_reason AS 原因, holder_after AS 货在谁名下 FROM stock_return WHERE status='rejected';

\echo ''
\echo '=========== RMA 返供应商：四道跟踪 ==========='
\echo '--- 还没寄出就说供应商接货了 → 应拒 ---'
UPDATE rma_case SET supplier_received=true;
\echo '--- 供应商没接货就说返还了 → 应拒 ---'
UPDATE rma_case SET supplier_sent_at=now()-interval '40 days', supplier_returned=true;
\echo '--- 正常流程 ---'
UPDATE rma_case SET disposition='to_supplier', supplier_sent_at=now()-interval '40 days', supplier_received=true, freight_fee_aud=35;
SELECT rma_no, sent_on AS 寄出日, 已接货, 已返还, days_at_supplier AS 在供应商处天数, freight_fee_aud AS 运费 FROM v_rma_supplier_track;

\echo ''
\echo '=========== 清理报废件必须留痕 ==========='
UPDATE rma_case SET disposition='purged';
UPDATE rma_case SET disposition='purged', purge_reason='过保报废，仓库积压清理';
SELECT rma_no, disposition, purged_by AS 谁删的, purge_reason AS 原因 FROM rma_case;

\echo ''
\echo '=========== RMA 成本归集 ==========='
SELECT p.code, c.cost_bucket AS 成本归属, c.repair_fee_total AS 修理费, c.freight_fee_total AS 运费,
       c.rma_cost_total AS 合计 FROM v_rma_cost c JOIN project p ON p.id=c.project_id;
