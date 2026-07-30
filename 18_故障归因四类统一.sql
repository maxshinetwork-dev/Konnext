SET timezone='Australia/Sydney';
SET app.actor='运维-小周';
\set ON_ERROR_STOP off
INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('CNY',0.2100,'google');
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES('11111111-1111-1111-1111-111111111111','小周','hourly',80,'2025-01-01');
INSERT INTO material(id,code,category,protocol,internal_name,spec,supplier,purchase_class,reorder_point,price_cny,freight_aud,margin_pct,warranty_months)
VALUES('99990000-0000-0000-0000-000000000001','M0001','面板','knx','KNX四联面板','白','深圳某某','C1',20,320,18,0.45,24);
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,handover_at,status,free_warranty_months)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','KX-2026-8002','rough_in',now(),600000,now()-interval '2 months','delivered',12);
INSERT INTO project_party(id,project_id,trade,company,contact_name,phone) VALUES('cccc0000-0000-0000-0000-00000000000e','bbbbbbbb-0000-0000-0000-00000000000b','electrician','Spark','Tony','0422000222');
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('bbbbbbbb-0000-0000-0000-00000000000b',1,now()),('bbbbbbbb-0000-0000-0000-00000000000b',2,now()),('bbbbbbbb-0000-0000-0000-00000000000b',3,now());
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('f0000000-0000-0000-0000-00000000000a','bbbbbbbb-0000-0000-0000-00000000000b','contract','S2',40,'INV-S2',now()-interval '300 days');
INSERT INTO payment_receipt(milestone_id,method,amount,received_at) VALUES('f0000000-0000-0000-0000-00000000000a','bank',240000,now()-interval '300 days');
UPDATE payment_milestone SET status='settled', settled_at=now()-interval '300 days' WHERE id='f0000000-0000-0000-0000-00000000000a';
INSERT INTO purchase_order(id,po_no,source_type,supplier,ordered_at,status) VALUES('dddd0000-0000-0000-0000-000000000001','PO-1','bulk','深圳某某',now(),'ordered');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud) VALUES('dddd0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',50,50,85.20);
INSERT INTO stock_out(id,out_no,project_id,receiver_party_id) VALUES('eeee0000-0000-0000-0000-000000000001','OUT-1','bbbbbbbb-0000-0000-0000-00000000000b','cccc0000-0000-0000-0000-00000000000e');
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud) VALUES('eeee0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',10,85.20);

\echo '════ 现场退坏货：一次填清损坏原因 ════'
INSERT INTO stock_return(id,return_no,project_id,returner_party_id,returner_name)
VALUES('bbbb0000-0000-0000-0000-000000000001','RET-1','bbbbbbbb-0000-0000-0000-00000000000b','cccc0000-0000-0000-0000-00000000000e','Tony');
INSERT INTO stock_return_line(return_id,material_id,qty,condition,damage_cause,unit_cost_aud) VALUES
 ('bbbb0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',2,'damaged','product_defect',85.20);
INSERT INTO stock_return_line(return_id,material_id,qty,condition,unit_cost_aud) VALUES
 ('bbbb0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',1,'good',85.20);

\echo '════ RMA 直接继承现场归因，不用第二个人再猜 ════'
SELECT rma_no, display_name AS 物料, damage_cause AS 归因, reporter_name AS 谁退的 FROM v_rma_board;

\echo ''
\echo '════ ★处置建议：产品缺陷 + 在保 → 找供应商索赔 ════'
SELECT rma_no, cause_cn AS 原因, in_warranty AS 在保, warranty_until AS 保到, suggested_action AS 建议处置 FROM v_rma_action;

\echo ''
\echo '════ 对比：人为损坏的建议完全不同 ════'
INSERT INTO stock_return(id,return_no,project_id,returner_party_id,returner_name)
VALUES('bbbb0000-0000-0000-0000-000000000002','RET-2','bbbbbbbb-0000-0000-0000-00000000000b','cccc0000-0000-0000-0000-00000000000e','Tony');
INSERT INTO stock_return_line(return_id,material_id,qty,condition,damage_cause,unit_cost_aud)
VALUES('bbbb0000-0000-0000-0000-000000000002','99990000-0000-0000-0000-000000000001',1,'damaged','human',85.20);
SELECT cause_cn AS 原因, in_warranty AS 在保, suggested_action AS 建议处置 FROM v_rma_action ORDER BY rma_no;

\echo ''
\echo '════ 维护单：四类归因 + 免责判定 ════'
INSERT INTO maintenance_case(id,project_id,title) VALUES('cccccccc-0000-0000-0000-00000000000c','bbbbbbbb-0000-0000-0000-00000000000b','客厅面板失灵');
INSERT INTO maintenance_job(id,project_id,case_id,staff_id,scheduled_date,planned_minutes,
  fault_cause,service_summary,client_sign_url,client_sign_name,client_sign_at,completed_at)
VALUES('dddddddd-0000-0000-0000-00000000000d','bbbbbbbb-0000-0000-0000-00000000000b','cccccccc-0000-0000-0000-00000000000c',
       '11111111-1111-1111-1111-111111111111',current_date,120,'product_defect','更换面板，同批次第三次故障',
       'https://x/s.jpg','王先生',now(),now());
UPDATE maintenance_case SET status='paid_closed' WHERE id='cccccccc-0000-0000-0000-00000000000c';
SELECT title, fault_cause AS 归因, is_free_warranty AS 免责维保覆盖 FROM maintenance_case;
\echo '--- 若是人为损坏，免责维保不覆盖 ---'
INSERT INTO maintenance_case(id,project_id,title,fault_cause,status)
VALUES('cccccccc-0000-0000-0000-00000000000e','bbbbbbbb-0000-0000-0000-00000000000b','客户摔坏面板','human','paid_closed');
SELECT title, fault_cause AS 归因, is_free_warranty AS 免责覆盖 FROM maintenance_case ORDER BY title;
