SET timezone='Australia/Sydney';
SET app.actor='运维-小周';
\set ON_ERROR_STOP off

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','小周','hourly',80,'2025-01-01');
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,handover_at,status,free_warranty_months)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','KX-2026-8002','rough_in',now(),600000,
       now()-interval '2 months','delivered',12);
-- S2 结清 + 采购(物料保修起算)
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,amount_due,status,invoice_no,invoice_sent_at,settle_reason)
VALUES('e0000000-0000-0000-0000-0000000000e2','bbbbbbbb-0000-0000-0000-00000000000b','contract','S2',40,240000,
       'settled','INV-S2-v1',now()-interval '8 months','已结清');
INSERT INTO procurement(project_id,supplier,cost_amount,warranty_months,status)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','面板供应商',60000,12,'draft');

\echo ''
\echo '=========== ① 受理：建维护单（还不知道多少钱） ==========='
SET app.actor='工程经理-陈总';
INSERT INTO maintenance_case(id,project_id,title,estimate_amount,estimate_note)
VALUES('cccccccc-0000-0000-0000-00000000000c','bbbbbbbb-0000-0000-0000-00000000000b','客厅面板失灵',
       350,'电话里客户问大概多少，按换一块面板+一小时人工估的');
SELECT title, status AS 状态, estimate_amount AS 口头预估, estimated_by AS 谁估的,
       estimated_at IS NOT NULL AS 已留痕 FROM maintenance_case;
SET app.actor='运维-小周';

\echo ''
\echo '=========== ② 人还没去就想开票 → 应拒 ==========='
INSERT INTO payment_milestone(project_id,kind,case_id,amount_due,invoice_no,invoice_sent_at)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','maintenance','cccccccc-0000-0000-0000-00000000000c',
       350,'INV-M001-v1',now());

\echo ''
\echo '=========== ③ 派工上门 ==========='
INSERT INTO maintenance_job(id,project_id,case_id,staff_id,scheduled_date,planned_minutes)
VALUES('dddddddd-0000-0000-0000-00000000000d','bbbbbbbb-0000-0000-0000-00000000000b',
       'cccccccc-0000-0000-0000-00000000000c','11111111-1111-1111-1111-111111111111',current_date,120);
INSERT INTO work_log(project_id,staff_id,work_type,ref_id,checkin_at,checkout_at,checkin_method)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','11111111-1111-1111-1111-111111111111','maintenance',
       'dddddddd-0000-0000-0000-00000000000d',now()-interval '3 hours',now()-interval '1 hour','gps');

\echo '--- 修完直接想走(没确认归因) → 应拒 ---'
UPDATE maintenance_job SET completed_at=now() WHERE id='dddddddd-0000-0000-0000-00000000000d';
\echo '--- 归因填了但没写服务内容 → 应拒 ---'
UPDATE maintenance_job SET fault_cause='product_defect', completed_at=now()
 WHERE id='dddddddd-0000-0000-0000-00000000000d';
\echo '--- 写了服务内容但客户没签字 → 应拒 ---'
UPDATE maintenance_job SET fault_cause='product_defect',
 service_summary='更换客厅四联面板一块，重新绑定回路，现场测试通过', completed_at=now()
 WHERE id='dddddddd-0000-0000-0000-00000000000d';
\echo '--- 客户当面签字确认 → 才可以离开 ---'
UPDATE maintenance_job SET fault_cause='product_defect',
 service_summary='更换客厅四联面板一块，重新绑定回路，现场测试通过',
 client_sign_url='https://x/sign_m001.jpg', client_sign_name='王先生', client_sign_at=now(),
 completed_at=now() WHERE id='dddddddd-0000-0000-0000-00000000000d';
SELECT title, status AS 单据状态, fault_cause AS 归因带回 FROM maintenance_case;

\echo ''
\echo '=========== ④ 办公室定价依据（一屏看全） ==========='
SELECT project_code, title, fault_cause AS 归因, visits_done AS 已上门次数,
       labor_hours AS 实际工时, in_free_warranty AS 免责期内, suggest_free AS 建议全免,
       material_expires_at::date AS 物料保到期 FROM v_maintenance_billing_basis;
SELECT service_summaries AS 客户签过的服务内容 FROM v_maintenance_billing_basis;

\echo ''
\echo '=========== ⑤ 免责覆盖 → 开 $0 Invoice ==========='
INSERT INTO payment_milestone(id,project_id,kind,case_id,amount_due,invoice_no,invoice_sent_at)
VALUES('e0000000-0000-0000-0000-0000000000e9','bbbbbbbb-0000-0000-0000-00000000000b','maintenance',
       'cccccccc-0000-0000-0000-00000000000c',0,'INV-M001-v1',now());
UPDATE maintenance_case SET status='invoiced' WHERE id='cccccccc-0000-0000-0000-00000000000c';
UPDATE payment_milestone SET status='settled' WHERE id='e0000000-0000-0000-0000-0000000000e9';
UPDATE maintenance_case SET status='paid_closed' WHERE id='cccccccc-0000-0000-0000-00000000000c';
SELECT title, status AS 最终状态, fault_cause AS 归因, is_free_warranty AS 免责覆盖 FROM maintenance_case;
SELECT invoice_no, amount_due AS 应收, status FROM payment_milestone WHERE kind='maintenance';

\echo ''
\echo '=========== ⑥ 预估 vs 实际：工程管理估得准不准 ==========='
SELECT title, estimate_amount AS 口头预估, estimated_by AS 谁估的,
       invoiced_amount AS 实际开票, diff AS 差额, diff_pct AS 偏差百分比,
       is_free_warranty AS 免责覆盖 FROM v_maintenance_estimate_accuracy;
