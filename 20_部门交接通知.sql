SET timezone='Australia/Sydney';
SET app.actor='售前-小林';
\set ON_ERROR_STOP off

-- 账号：六个部门都建好（交接短信要发给他们）
INSERT INTO app_account(id,login_name,full_name,tier,is_core_admin,phone,email,phone_bound_at)
VALUES('a0000000-0000-0000-0000-000000000001','core','陈总',1,true,'0400000000','core@x.com',now());
INSERT INTO app_account(id,login_name,full_name,tier,phone,email,created_by) VALUES
 ('b0000000-0000-0000-0000-000000000001','presales','小林(售前)',2,'0411000001','p@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000002','engmgmt','陈工(工程管理)',2,'0411000002','e@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000003','stock','老张(采购兼库管)',2,'0411000003','s@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000004','finance','王姐(财务)',2,'0411000004','f@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000005','maint','小周(运维)',2,'0411000005','m@x.com','a0000000-0000-0000-0000-000000000001');
INSERT INTO account_department(account_id,department) VALUES
 ('b0000000-0000-0000-0000-000000000001','presales'),
 ('b0000000-0000-0000-0000-000000000002','eng_mgmt'),
 ('b0000000-0000-0000-0000-000000000003','procurement'),
 ('b0000000-0000-0000-0000-000000000003','warehouse'),
 ('b0000000-0000-0000-0000-000000000004','finance'),
 ('b0000000-0000-0000-0000-000000000005','maintenance');
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES('e1111111-1111-1111-1111-111111111111','小陈','hourly',80,'2025-01-01');

\echo ''
\echo '════ ① 售前签字 → 自动短信通知财务 ════'
INSERT INTO project(id,code,name,build_stage,step6_signed_at,contract_price)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','王宅','rough_in',now(),500000);
SELECT event_label AS 事件, from_dept_cn AS 从, to_dept_cn AS 到, action_needed AS 对方要做什么, sla_hours AS SLA小时
FROM v_pending_handoff;
SELECT channel AS 方式, recipient AS 发给谁, status FROM v_handoff_notifications WHERE event_label LIKE '%签字%';
SELECT body AS 短信内容 FROM v_handoff_notifications WHERE event_label LIKE '%签字%' LIMIT 1;

\echo ''
\echo '════ ② S1 结清 → 通知工程管理进场 ════'
SET app.actor='财务-王姐';
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,amount_due,status,settle_reason)
VALUES('f0000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-00000000000a','contract','S1',10,50000,'settled','已收');
SELECT event_label AS 事件, to_dept_cn AS 通知谁, action_needed AS 要做什么 FROM v_pending_handoff ORDER BY raised_at DESC LIMIT 1;

\echo ''
\echo '════ ③ SM3 完成 → 通知财务开 S2 ════'
SET app.actor='工程-小陈';
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a',1,now()),('aaaaaaaa-0000-0000-0000-00000000000a',2,now());
INSERT INTO site_meeting(id,project_id,sm_no,completed_at) VALUES('bb000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-00000000000a',3,now());
\echo '--- SM3 顺带登记一条变更 → 也通知财务估价 ---'
INSERT INTO variation(project_id,origin,change_type,description,logged_by)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','sm3','add','客厅加两个开关点位','e1111111-1111-1111-1111-111111111111');
SELECT event_label AS 事件, to_dept_cn AS 通知谁, action_needed AS 要做什么 FROM v_pending_handoff ORDER BY raised_at DESC LIMIT 2;

\echo ''
\echo '════ ④ S2 结清 → 同时通知采购和库管（两条不同的话） ════'
SET app.actor='财务-王姐';
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('f0000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-00000000000a','contract','S2',40,'INV-S2',now());
INSERT INTO payment_receipt(milestone_id,method,amount,received_at) VALUES('f0000000-0000-0000-0000-000000000002','bank',200000,now());
UPDATE payment_milestone SET status='settled' WHERE id='f0000000-0000-0000-0000-000000000002';
SELECT event_label AS 事件, to_dept_cn AS 通知谁, action_needed AS 要做什么 FROM v_pending_handoff ORDER BY raised_at DESC LIMIT 2;

\echo ''
\echo '════ ⑤ 全流程交接一览：谁在等谁 ════'
SELECT event_label AS 事件, from_dept_cn AS 从, to_dept_cn AS 到,
       waiting_hours AS 等了几小时, sla_hours AS SLA, overdue AS 已超期, notified_count AS 通知了几人
FROM v_pending_handoff ORDER BY raised_at;

\echo ''
\echo '════ ⑥ 各部门待办量（管理层看板） ════'
SELECT * FROM v_dept_workload ORDER BY 待办总数 DESC;

\echo ''
\echo '════ ⑦ 财务点"已知悉" → 从待办里消失 ════'
UPDATE dept_handoff SET acknowledged_at=now(), acknowledged_by='b0000000-0000-0000-0000-000000000004'
 WHERE event_key='sm3_done';
SELECT event_label AS 事件, unacknowledged AS 未响应, acknowledged_by_name AS 谁响应的 FROM v_pending_handoff WHERE event_key='sm3_done';

\echo ''
\echo '════ ⑧ 模拟超期：SLA 24 小时，已等 30 小时 ════'
UPDATE dept_handoff SET raised_at=now()-interval '30 hours' WHERE event_key='s2_settled';
SELECT event_label AS 事件, to_dept_cn AS 谁在等, waiting_hours AS 等了, sla_hours AS SLA, overdue AS 超期
FROM v_pending_handoff WHERE event_key='s2_settled';
SELECT * FROM v_dept_workload ORDER BY 已超期 DESC;

\echo ''
\echo '════ ⑨ 拒付停服 → 通知全部门（SLA 4 小时） ════'
UPDATE project SET service_suspended_at=now(), service_suspended_by='财务-王姐',
  service_suspended_reason='客户明确拒付维护费' WHERE code='KX-2026-0142';
SELECT event_label AS 事件, to_dept_cn AS 通知谁, sla_hours AS SLA, notified_count AS 通知人数 FROM v_pending_handoff WHERE event_key='payment_dispute';
SELECT DISTINCT recipient AS 收到短信的号码 FROM v_handoff_notifications WHERE event_label LIKE '%拒付%' ORDER BY 1;
