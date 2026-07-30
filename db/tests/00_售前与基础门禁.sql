SET timezone='Australia/Sydney';
SET app.actor='售前-小林';
\set ON_ERROR_STOP off

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','张三','hourly',80,'2025-01-01');

\echo ''
\echo '=========== 售前 1：第六步没签字，就想置"已签署报价" ==========='
INSERT INTO project(id,code,build_stage,status)
VALUES('aaaaaaaa-0000-0000-0000-0000000000a1','KX-2026-9001','da','quote_signed');

\echo '=========== 售前 2：方案没定版，就想跳进"施工中" ==========='
INSERT INTO project(id,code,build_stage,status)
VALUES('aaaaaaaa-0000-0000-0000-0000000000a2','KX-2026-9002','da','in_construction');

\echo '=========== 售前 3：先正常建项目(接洽中) → 应通过 ==========='
INSERT INTO project(id,code,build_stage) VALUES
 ('aaaaaaaa-0000-0000-0000-0000000000a3','KX-2026-9003','da');
\echo '--- 没签字就改成 quote_signed → 应拒 ---'
UPDATE project SET status='quote_signed' WHERE code='KX-2026-9003';
\echo '--- 补上第六步签字后再改 → 应通过 ---'
UPDATE project SET step6_signed_at=now() WHERE code='KX-2026-9003';
UPDATE project SET status='quote_signed' WHERE code='KX-2026-9003';
SELECT code, status, proposal_locked AS 方案已定版 FROM v_project_overview WHERE code='KX-2026-9003';

\echo ''
\echo '=========== 售前 4：乐观锁——两个人同时改同一条 ==========='
SELECT version AS 当前版本 FROM project WHERE code='KX-2026-9003';
SET app.expected_version = '1';
\echo '--- 拿着过期的版本号去改 → 应拒 ---'
UPDATE project SET name='被小王改的' WHERE code='KX-2026-9003';
RESET app.expected_version;

\echo ''
\echo '=========== SM 顺序 1：SM1 还没建，就想完成 SM2 ==========='
INSERT INTO site_meeting(project_id,sm_no,completed_at)
VALUES('aaaaaaaa-0000-0000-0000-0000000000a3',2,now());

\echo '=========== SM 顺序 2：SM1 建了但没完成，就想完成 SM2 ==========='
INSERT INTO site_meeting(project_id,sm_no) VALUES('aaaaaaaa-0000-0000-0000-0000000000a3',1);
INSERT INTO site_meeting(project_id,sm_no,completed_at)
VALUES('aaaaaaaa-0000-0000-0000-0000000000a3',2,now());

\echo '=========== SM 顺序 3：老项目把 SM1 标不适用 → SM2 应放行 ==========='
UPDATE site_meeting SET na_flag=true, na_reason='老项目接手时已过进场阶段', na_by='工程经理', na_at=now()
 WHERE project_id='aaaaaaaa-0000-0000-0000-0000000000a3' AND sm_no=1;
INSERT INTO site_meeting(project_id,sm_no,completed_at)
VALUES('aaaaaaaa-0000-0000-0000-0000000000a3',2,now());
SELECT sm_no, completed_at IS NOT NULL AS 已完成, na_flag AS 标不适用 FROM site_meeting
 WHERE project_id='aaaaaaaa-0000-0000-0000-0000000000a3' ORDER BY sm_no;

\echo ''
\echo '=========== SM 清单：适用项没勾完就完成 SM3 ==========='
INSERT INTO site_meeting(id,project_id,sm_no)
VALUES('bbbbbbbb-0000-0000-0000-0000000000b3','aaaaaaaa-0000-0000-0000-0000000000a3',3);
INSERT INTO job_checklist(job_kind,job_id,item_key,item_label) VALUES
 ('sm','bbbbbbbb-0000-0000-0000-0000000000b3','tape','带卷尺'),
 ('sm','bbbbbbbb-0000-0000-0000-0000000000b3','drawing','带最新图纸');
UPDATE site_meeting SET completed_at=now() WHERE id='bbbbbbbb-0000-0000-0000-0000000000b3';
\echo '--- 条件项不适用(本项目无KNX)时不该拦 ---'
UPDATE job_checklist SET checked=true WHERE job_id='bbbbbbbb-0000-0000-0000-0000000000b3' AND item_key='tape';
INSERT INTO job_checklist(job_kind,job_id,item_key,item_label,is_conditional,applicable)
VALUES('sm','bbbbbbbb-0000-0000-0000-0000000000b3','knx_cable','带KNX线',true,false);
UPDATE site_meeting SET completed_at=now() WHERE id='bbbbbbbb-0000-0000-0000-0000000000b3';
\echo '--- 剩下那项也勾上 → 应通过 ---'
UPDATE job_checklist SET checked=true WHERE job_id='bbbbbbbb-0000-0000-0000-0000000000b3' AND item_key='drawing';
UPDATE site_meeting SET completed_at=now() WHERE id='bbbbbbbb-0000-0000-0000-0000000000b3';
SELECT sm_no, completed_at IS NOT NULL AS SM3已完成 FROM site_meeting WHERE id='bbbbbbbb-0000-0000-0000-0000000000b3';

\echo ''
\echo '=========== 付款 1：SM3 没完成就想发 S2 物料款 ==========='
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price)
VALUES('aaaaaaaa-0000-0000-0000-0000000000a4','KX-2026-9004','da',now(),400000);
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-0000000000a4',1,now()),('aaaaaaaa-0000-0000-0000-0000000000a4',2,now());
INSERT INTO site_meeting(project_id,sm_no) VALUES('aaaaaaaa-0000-0000-0000-0000000000a4',3);
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due,status)
VALUES('aaaaaaaa-0000-0000-0000-0000000000a4','contract','S2',40,160000,'invoiced');

\echo '=========== 付款 2：SM4 没完成就想发 S3 人工款 ==========='
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due,status)
VALUES('aaaaaaaa-0000-0000-0000-0000000000a4','contract','S3',40,160000,'invoiced');

\echo ''
\echo '=========== 采购 1：S2 没结清就想下单 ==========='
INSERT INTO procurement(project_id,supplier,cost_amount,status)
VALUES('aaaaaaaa-0000-0000-0000-0000000000a4','供应商甲',80000,'ordered');

\echo '=========== 采购 2：S2 结清了 → 下单应通过 ==========='
UPDATE site_meeting SET completed_at=now() WHERE project_id='aaaaaaaa-0000-0000-0000-0000000000a4' AND sm_no=3;
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('aaaaaaaa-0000-0000-0000-0000000000a4','contract','S2',40,'INV-9004-S2-v1',now());
INSERT INTO payment_receipt(milestone_id,method,amount,received_at)
 SELECT id,'bank',160000,now() FROM payment_milestone
  WHERE project_id='aaaaaaaa-0000-0000-0000-0000000000a4' AND stage='S2';
UPDATE payment_milestone SET status='settled'
 WHERE project_id='aaaaaaaa-0000-0000-0000-0000000000a4' AND stage='S2';
INSERT INTO procurement(id,project_id,supplier,cost_amount,status)
VALUES('cccccccc-0000-0000-0000-0000000000c1','aaaaaaaa-0000-0000-0000-0000000000a4','供应商甲',80000,'ordered');

\echo '=========== 采购 3：工程还没预配就想发货 ==========='
UPDATE procurement SET status='shipped' WHERE id='cccccccc-0000-0000-0000-0000000000c1';
\echo '--- 预配完成后发货 → 应通过 ---'
UPDATE procurement SET prewired_at=now(), status='prewired' WHERE id='cccccccc-0000-0000-0000-0000000000c1';
UPDATE procurement SET status='shipped', shipped_at=now() WHERE id='cccccccc-0000-0000-0000-0000000000c1';
SELECT supplier, status FROM procurement;

\echo ''
\echo '=========== 审计：改动有没有真的留痕 ==========='
SELECT table_name, action, count(*) AS 条数 FROM audit_log
 GROUP BY table_name, action ORDER BY table_name, action;
