SET timezone='Australia/Sydney';
SET app.actor='测试';
\set ON_ERROR_STOP off

-- ============ 铺一份"干净"的完整数据 ============
INSERT INTO app_account(id,login_name,full_name,tier,is_core_admin,phone,email,phone_bound_at)
VALUES('a0000000-0000-0000-0000-000000000001','core','陈总',1,true,'0400000000','core@x.com',now());
INSERT INTO app_account(id,login_name,full_name,tier,phone,email,created_by) VALUES
 ('b0000000-0000-0000-0000-000000000002','engmgmt','陈工',2,'0411000002','e@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000004','finance','王姐',2,'0411000004','f@x.com','a0000000-0000-0000-0000-000000000001');
INSERT INTO account_department(account_id,department) VALUES
 ('b0000000-0000-0000-0000-000000000002','eng_mgmt'),('b0000000-0000-0000-0000-000000000004','finance');
INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('CNY',0.2100,'google'),('USD',1.5200,'google');
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,cost_hourly_rate,phone,hired_at)
VALUES('e1111111-1111-1111-1111-111111111111','小陈','hourly',80,80,'0422000001','2025-01-01');
INSERT INTO material(id,code,category,protocol,internal_name,spec,supplier,purchase_class,reorder_point,price_cny,freight_aud,margin_pct,warranty_months)
VALUES('99990000-0000-0000-0000-000000000001','M0001','面板','knx','KNX四联面板','白','深圳','C1',20,320,18,0.45,24);
INSERT INTO project(id,code,name,build_stage,step6_signed_at,contract_price,planned_labor_hours)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','王宅','rough_in',now()-interval '200 days',500000,400);
INSERT INTO project_party(id,project_id,trade,company,contact_name,phone)
VALUES('cccc0000-0000-0000-0000-00000000000e','aaaaaaaa-0000-0000-0000-00000000000a','electrician','Spark','Tony','0422000222');
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a',1,now()-interval '180 days'),
 ('aaaaaaaa-0000-0000-0000-00000000000a',2,now()-interval '170 days'),
 ('aaaaaaaa-0000-0000-0000-00000000000a',3,now()-interval '160 days'),
 ('aaaaaaaa-0000-0000-0000-00000000000a',4,now()-interval '100 days');
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at) VALUES
 ('f0000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-00000000000a','contract','S2',40,'INV-S2',now()-interval '150 days');
INSERT INTO payment_receipt(milestone_id,method,amount,gst_amount,received_at)
VALUES('f0000000-0000-0000-0000-000000000002','bank',200000,20000,now()-interval '148 days');
UPDATE payment_milestone SET status='settled' WHERE id='f0000000-0000-0000-0000-000000000002';
INSERT INTO purchase_order(id,po_no,source_type,supplier,ordered_at,status)
VALUES('dddd0000-0000-0000-0000-000000000001','PO-0087','bulk','深圳',now()-interval '140 days','ordered');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud)
VALUES('dddd0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',100,100,85.20);
INSERT INTO stock_out(id,out_no,project_id,receiver_party_id,released_at)
VALUES('eeee0000-0000-0000-0000-000000000001','OUT-01','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000e',now()-interval '120 days');
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud)
VALUES('eeee0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',20,85.20);
INSERT INTO stock_return(id,return_no,project_id,returner_party_id,returner_name,returned_at)
VALUES('bbbb0000-0000-0000-0000-000000000001','RET-01','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000e','Tony',now()-interval '20 days');
INSERT INTO stock_return_line(return_id,material_id,qty,condition,unit_cost_aud)
VALUES('bbbb0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',7,'good',85.20);
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','e1111111-1111-1111-1111-111111111111','execution',
       now()-interval '30 days'+interval '8 hours', now()-interval '30 days'+interval '17 hours','gps');
SELECT fn_lock_daily_payroll('e1111111-1111-1111-1111-111111111111',(now()-interval '30 days')::date);
INSERT INTO variation(id,project_id,origin,change_type,description,settle_amount,settle_by,settle_status,billable)
VALUES('11110000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-00000000000a','sm3','add','客厅加两个开关',4800,'王姐','settled_s4',true);
INSERT INTO variation(id,project_id,origin,change_type,description,settle_by)
VALUES('11110000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-00000000000a','sm3','move','主卧面板移位','王姐');

\echo ''
\echo '════════════ 干净数据：断言应全过 ════════════'
SELECT * FROM fn_assertion_summary();
SELECT code, severity, label, status FROM fn_run_assertions() WHERE violations <> 0;

\echo ''
\echo '════════════ 现在故意搞坏，看断言抓不抓得到 ════════════'
\echo ''
\echo '① 破坏库存：偷偷把到货数改小（模拟"退库没进库存"那类 bug）'
UPDATE purchase_order_line SET qty_arrived=10
 WHERE po_id='dddd0000-0000-0000-0000-000000000001';
SELECT code, label, status FROM fn_run_assertions() WHERE violations<>0 AND code LIKE 'INV-STOCK%';
SELECT jsonb_pretty(d) AS 违规明细 FROM fn_assertion_detail('INV-STOCK-01') d;
UPDATE purchase_order_line SET qty_arrived=100 WHERE po_id='dddd0000-0000-0000-0000-000000000001';

\echo ''
\echo '② 破坏发票：变更漏估了一条（模拟"未退料不进发票"那类 bug）'
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','contract','S4',10,'INV-S4-v1',now());
INSERT INTO variation(project_id,origin,change_type,description,settle_amount,settle_by,settle_status)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','unreturned','add','面板×13 未退',2013.83,'王姐','settled_s4');
SELECT code, label, status, hint FROM fn_run_assertions() WHERE violations<>0 AND code='INV-FIN-01';
SELECT jsonb_pretty(d) AS 违规明细 FROM fn_assertion_detail('INV-FIN-01') d;

\echo ''
\echo '③ 破坏工资：偷偷改付薪时长（模拟日结算错）'
-- 日结有"定格不可改"门禁，改不动；这里用停掉触发器的方式模拟"数据被别的途径写坏"
ALTER TABLE daily_payroll DISABLE TRIGGER daily_payroll_immutable;
UPDATE daily_payroll SET paid_min=999 WHERE staff_id='e1111111-1111-1111-1111-111111111111';
ALTER TABLE daily_payroll ENABLE TRIGGER daily_payroll_immutable;
SELECT code, label, status FROM fn_run_assertions() WHERE violations<>0 AND code LIKE 'INV-PAY%';

\echo ''
\echo '④ 破坏权限：给视图关掉 security_invoker（模拟"视图绕过 RLS"那个洞）'
ALTER VIEW v_s4_settlement SET (security_invoker = false);
ALTER VIEW v_material_price SET (security_invoker = false);
SELECT code, label, status, hint FROM fn_run_assertions() WHERE violations<>0 AND code='INV-SEC-01';
SELECT jsonb_pretty(d) AS 哪些视图漏了 FROM fn_assertion_detail('INV-SEC-01') d;

\echo ''
\echo '⑤ 破坏流程：把移位变更填上金额（该向客户收电工的钱）'
-- 同理：S4 已发出后变更金额有门禁；停掉触发器模拟绕过
ALTER TABLE variation DISABLE TRIGGER variation_billable;
ALTER TABLE variation DISABLE TRIGGER variation_after_s4;
UPDATE variation SET billable=true, settle_amount=1200 WHERE change_type='move';
ALTER TABLE variation ENABLE TRIGGER variation_billable;
ALTER TABLE variation ENABLE TRIGGER variation_after_s4;
SELECT code, label, status FROM fn_run_assertions() WHERE violations<>0 AND code IN ('INV-FIN-03','INV-PAY-01');

\echo ''
\echo '════════════ 全部破坏后的总结 ════════════'
SELECT * FROM fn_assertion_summary();
SELECT code, severity, label, status FROM fn_run_assertions() WHERE violations<>0 ORDER BY severity, code;
