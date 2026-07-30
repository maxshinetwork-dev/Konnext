SET timezone='Australia/Sydney';
SET app.actor = '财务-王姐';
\set ON_ERROR_STOP off

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,cost_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','张三','hourly',80,80,'2025-01-01'),
 ('22222222-2222-2222-2222-222222222222','李四(负责人)','hourly',120,120,'2025-01-01');
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,planned_labor_hours,free_warranty_months)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001','KX-2026-0142','rough_in',now(),500000,100,12);
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001',1,now()),('aaaaaaaa-0000-0000-0000-000000000001',2,now()),
 ('aaaaaaaa-0000-0000-0000-000000000001',3,now()),('aaaaaaaa-0000-0000-0000-000000000001',4,now());

\echo ''
\echo '=========== 财务 1：应收金额发出时自动现算带出 ==========='
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('e0000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','contract','S2',40,
       'INV-0142-S2-v1', now()-interval '45 days');
SELECT stage, ratio_pct AS 比例, amount_due AS 应收, status, invoice_ver AS 版本 FROM payment_milestone WHERE stage='S2';

\echo ''
\echo '=========== 财务 2：Invoice 发出后偷改金额（不升版本） → 应拒 ==========='
UPDATE payment_milestone SET amount_due=220000 WHERE stage='S2';
\echo '--- 升版本重开 v2 → 应通过；账龄起点不变 ---'
UPDATE payment_milestone SET amount_due=220000, invoice_ver=2, invoice_no='INV-0142-S2-v2',
       invoice_sent_at=now()-interval '10 days' WHERE stage='S2';
SELECT invoice_no, amount_due AS 应收, invoice_ver AS 版本,
       (now()::date-invoice_sent_at::date) AS 本期超期, (now()::date-first_invoice_sent_at::date) AS 账龄
FROM payment_milestone WHERE stage='S2';

\echo ''
\echo '=========== 财务 3：收款自动 partial + 不足额结清 ==========='
INSERT INTO payment_receipt(milestone_id,method,amount,gst_amount,received_at)
VALUES('e0000000-0000-0000-0000-000000000002','bank',200000,20000,now());
SELECT status AS 收款后状态 FROM payment_milestone WHERE stage='S2';
\echo '--- 还差 20000 就点结清、不填原因 → 应拒 ---'
UPDATE payment_milestone SET status='settled' WHERE stage='S2';
\echo '--- 填原因 → 应通过，差额定格 ---'
UPDATE payment_milestone SET status='settled', settle_reason='客户抹零，老板同意' WHERE stage='S2';
SELECT amount_due AS 应收, shortfall_amount AS 批准时差额, settle_reason AS 原因, settled_by AS 谁批的
FROM payment_milestone WHERE stage='S2';
\echo '--- 后来客户又补了 20000：差额是历史事实，不该变 ---'
INSERT INTO payment_receipt(milestone_id,method,amount,received_at)
VALUES('e0000000-0000-0000-0000-000000000002','cash',20000,now());
SELECT s.received AS 现已收, s.outstanding AS 现在还差, m.shortfall_amount AS 当时批准的差额
FROM v_milestone_settlement s JOIN payment_milestone m ON m.id=s.milestone_id WHERE m.stage='S2';

\echo ''
\echo '=========== 财务 4：超期两个天数（改版归零 vs 账龄抹不掉） ==========='
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,amount_due,invoice_no,invoice_sent_at,first_invoice_sent_at)
VALUES('e0000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001','contract','S3',40,200000,
       'INV-0142-S3-v3', now()-interval '5 days', now()-interval '95 days');
SELECT stage, overdue_days_current AS 本期超期, aging_days AS 账龄, is_overdue AS 算超期
FROM v_overdue WHERE stage='S3';

\echo ''
\echo '=========== 交付：定格工程利润率 ==========='
INSERT INTO procurement(project_id,supplier,cost_amount,warranty_months,status)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','KNX 供应商A',180000,24,'draft'),
      ('aaaaaaaa-0000-0000-0000-000000000001','影音供应商B',40000,12,'draft');
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','execution',
       now()-interval '20 days', now()-interval '20 days'+interval '8 hours','gps');
UPDATE payment_milestone SET status='settled' WHERE stage='S3';
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due,status,invoice_no,invoice_sent_at,settle_reason)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','contract','S4',10,50000,'settled','INV-0142-S4-v1',now(),'尾款已收');
INSERT INTO delivery_review(project_id,decision,reviewed_by) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','ready','22222222-2222-2222-2222-222222222222');
INSERT INTO handover_job(project_id,staff_id,scheduled_date,client_sign_url,client_sign_name,client_sign_at,completed_at)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222',current_date,
       'https://x/s.jpg','王先生',now(),now());
SELECT code, status, eng_margin_locked AS 工程利润率定格 FROM project;

\echo ''
\echo '=========== 维保：两套钟 + 交付日物料保修剩余 ==========='
SELECT free_warranty_months AS 免责月, free_warranty_until::date AS 免责到期, in_free_warranty AS 免责期内,
       s2_settled_at::date AS S2结清日, min_material_months AS 最短物料保,
       material_months_left_at_handover AS 交付日物料保剩余月 FROM v_warranty;
SELECT supplier, warranty_months AS 保修月, expires_at::date AS 到期, still_covered AS 在保 FROM v_material_warranty;

\echo ''
\echo '=========== 维护：免责单走同一套应收表（$0 Invoice） ==========='
INSERT INTO maintenance_case(id,project_id,title,quote_amount,labor_cost,material_cost)
VALUES('f0000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','客厅面板失灵',0,320,150);
INSERT INTO payment_milestone(id,project_id,kind,case_id,amount_due,invoice_no,invoice_sent_at)
VALUES('e0000000-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000001','maintenance',
       'f0000000-0000-0000-0000-000000000001',0,'INV-0142-M001-v1',now());
\echo '--- 归因没填就结案 → 应拒 ---'
UPDATE maintenance_case SET status='paid_closed' WHERE id='f0000000-0000-0000-0000-000000000001';
\echo '--- 填产品缺陷 → 通过，自动判定为免责维保覆盖 ---'
UPDATE maintenance_case SET fault_cause='product_defect', status='paid_closed' WHERE id='f0000000-0000-0000-0000-000000000001';
SELECT title, fault_cause AS 归因, is_free_warranty AS 免责覆盖, cost_bucket AS 成本归属 FROM maintenance_case;
UPDATE payment_milestone SET status='settled' WHERE id='e0000000-0000-0000-0000-000000000009';

\echo ''
\echo '=========== 拒付：项目级全面停服 ==========='
UPDATE project SET service_suspended_at=now()-interval '95 days', service_suspended_by='财务-王姐',
       service_suspended_reason='客户明确表示拒付维护费';
INSERT INTO maintenance_job(project_id,staff_id,scheduled_date,no_case_reason)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111',current_date,'客户又来电');
SELECT code, suspended_days AS 停服天数, server_shutdown_due AS 该停服务器了 FROM v_service_suspension;

\echo ''
\echo '=========== 长期利润率 ==========='
SELECT code, eng_margin_locked AS 工程利润率, eng_profit AS 工程利润,
       maint_revenue AS 运维收入, maint_labor AS 运维人力, maint_material AS 运维物料,
       free_warranty_cost AS 免责维保免掉, long_term_profit AS 长期利润 FROM v_long_term_margin;
