SET timezone='Australia/Sydney';
\set ON_ERROR_STOP off
\set QUIET on

-- ============ 铺底数据 ============
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,cost_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','张三','hourly',80,80,'2025-01-01'),
 ('22222222-2222-2222-2222-222222222222','李四(负责人)','hourly',120,120,'2025-01-01');
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,planned_labor_hours)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001','KX-2026-0142','rough_in',now(),500000,100),
       ('aaaaaaaa-0000-0000-0000-000000000002','KX-2026-0143','rough_in',now(),300000,60);
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001',1,now());

\echo ''
\echo '=========== 门禁 1：SM4 没完成就派安装 ==========='
INSERT INTO install_job(project_id,staff_id,scheduled_date,planned_minutes)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','2026-07-20',180);

-- 补齐 SM2/3/4
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001',2,now()),
 ('aaaaaaaa-0000-0000-0000-000000000001',3,now()),
 ('aaaaaaaa-0000-0000-0000-000000000001',4,now());
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000002',1,now()),('aaaaaaaa-0000-0000-0000-000000000002',2,now()),
 ('aaaaaaaa-0000-0000-0000-000000000002',3,now()),('aaaaaaaa-0000-0000-0000-000000000002',4,now());
\echo '--- SM4 完成后再派 → 应通过 ---'
INSERT INTO install_job(id,project_id,staff_id,scheduled_date,planned_minutes) VALUES
 ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','2026-07-20',180),
 ('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','2026-07-20',120);

\echo ''
\echo '=========== 门禁 2：出发前清单没勾完就点完成 ==========='
INSERT INTO job_checklist(job_kind,job_id,item_key,item_label)
VALUES('install','bbbbbbbb-0000-0000-0000-000000000001','tools','带调试笔记本');
UPDATE install_job SET completed_at=now() WHERE id='bbbbbbbb-0000-0000-0000-000000000001';
\echo '--- 勾上后再完成 → 应通过 ---'
UPDATE job_checklist SET checked=true WHERE job_id='bbbbbbbb-0000-0000-0000-000000000001';
UPDATE install_job SET completed_at=now() WHERE id='bbbbbbbb-0000-0000-0000-000000000001';

\echo ''
\echo '=========== 门禁 3：安装剩余没清零就点完工 ==========='
INSERT INTO install_item(project_id,title,status) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','客厅灯光调试','done'),
 ('aaaaaaaa-0000-0000-0000-000000000001','影音室装机','pending'),
 ('aaaaaaaa-0000-0000-0000-000000000001','二楼地暖联动','pending');
UPDATE project SET install_completed_at=now(), install_completed_by='22222222-2222-2222-2222-222222222222'
 WHERE id='aaaaaaaa-0000-0000-0000-000000000001';

\echo '--- 后门1：取消但不填原因 → 应拒(CHECK) ---'
UPDATE install_item SET status='cancelled' WHERE title='影音室装机';
\echo '--- 后门2：取消并填原因 → 应通过 ---'
UPDATE install_item SET status='cancelled', reason='客户临时说这间不装了' WHERE title='影音室装机';
UPDATE install_item SET status='suspended', reason='空调队未完工', blocked_by='HVAC 分包' WHERE title='二楼地暖联动';

\echo '--- 清零了但没填负责人 → 应拒 ---'
UPDATE project SET install_completed_at=now() WHERE id='aaaaaaaa-0000-0000-0000-000000000001';
\echo '--- 清零 + 负责人确认 → 应通过 ---'
UPDATE project SET install_completed_at=now(), install_completed_by='22222222-2222-2222-2222-222222222222'
 WHERE id='aaaaaaaa-0000-0000-0000-000000000001';

\echo ''
\echo '=========== 门禁 4：S4 没结清就安排交付（硬卡，无后门） ==========='
INSERT INTO payment_milestone(project_id,stage,ratio_pct,amount_due,status)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','S4',10,50000,'invoiced');
INSERT INTO handover_job(project_id,staff_id,scheduled_date,planned_minutes)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','2026-07-25',120);

\echo '--- S4 结清了，但工程管理还没确认交付条件 → 应拒 ---'
INSERT INTO payment_receipt(milestone_id,method,amount,received_at) SELECT id,'bank',50000,now() FROM payment_milestone WHERE project_id='aaaaaaaa-0000-0000-0000-000000000001' AND stage='S4';
UPDATE payment_milestone SET status='settled' WHERE project_id='aaaaaaaa-0000-0000-0000-000000000001' AND stage='S4';
INSERT INTO handover_job(project_id,staff_id,scheduled_date,planned_minutes)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','2026-07-25',120);

\echo '--- 工程管理看流水账后确认 ready → 应通过 ---'
INSERT INTO delivery_review(project_id,decision,reviewed_by,note)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','ready','22222222-2222-2222-2222-222222222222','已核对流水账，工时正常，可交付');
INSERT INTO handover_job(id,project_id,staff_id,scheduled_date,planned_minutes)
VALUES('cccccccc-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','2026-07-25',120);

\echo '--- 交付完成但没客户签字 → 应拒 ---'
UPDATE handover_job SET completed_at=now() WHERE id='cccccccc-0000-0000-0000-000000000001';
\echo '--- 有客户签收 → 应通过，并自动回写项目状态 ---'
UPDATE handover_job SET client_sign_url='https://x/sign.jpg', client_sign_name='王先生',
 client_sign_at=now(), completed_at=now() WHERE id='cccccccc-0000-0000-0000-000000000001';
SELECT code, status, handover_at IS NOT NULL AS 已交付 FROM project WHERE code='KX-2026-0142';

\echo ''
\echo '=========== 门禁 5：维护无单派工 ==========='
\echo '--- 无单且不填原因 → 应拒 ---'
INSERT INTO maintenance_job(project_id,staff_id,scheduled_date,planned_minutes)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','2026-07-20',60);
\echo '--- 无单但填原因 → 应通过（留痕后门） ---'
INSERT INTO maintenance_job(project_id,staff_id,scheduled_date,planned_minutes,no_case_reason)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','2026-07-20',60,'客户电话急报灯不亮，先派人后补单');

\echo ''
\echo '=========== 检查 6：维护单只受理已交付项目 ==========='
\echo '--- 未交付项目建维护单 → 应拒 ---'
INSERT INTO maintenance_case(project_id,title,estimate_amount)
VALUES('aaaaaaaa-0000-0000-0000-000000000002','施工期客户报修(项目未交付)',800);
\echo '--- 已交付项目 → 通过 ---'
INSERT INTO maintenance_case(project_id,title,estimate_amount)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','交付后客户报修',800);
SELECT p.code, m.title FROM maintenance_case m JOIN project p ON p.id=m.project_id;

\echo ''
\echo '=========== 门禁 7：当日超时不填问题就提交 ==========='
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','execution','2026-07-20 09:00+10','2026-07-20 12:00+10','gps'),
 ('aaaaaaaa-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','execution','2026-07-20 15:00+10','2026-07-20 18:30+10','gps');
INSERT INTO daily_report(id,staff_id,report_date)
VALUES('dddddddd-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','2026-07-20');
\echo '--- 直接提交(未填问题) → 应拒 ---'
UPDATE daily_report SET submitted_at=now() WHERE id='dddddddd-0000-0000-0000-000000000001';
\echo '--- 填了问题再提交 → 应通过 ---'
INSERT INTO daily_issue(report_id,issue_type,project_id,description)
VALUES('dddddddd-0000-0000-0000-000000000001','scheduling','aaaaaaaa-0000-0000-0000-000000000002','两个工地间隔太远，路上耗了3小时');
UPDATE daily_report SET submitted_at=now() WHERE id='dddddddd-0000-0000-0000-000000000001';
SELECT planned_minutes AS 计划分, onsite_minutes AS 在场分, span_minutes AS 首尾分,
       over_plan_min AS 计划超, over_span_min AS 工时超 FROM daily_report;

\echo ''
\echo '=========== 检查 8：路上时间自动派生 ==========='
SELECT seq, depart_at::time AS 离场, arrive_at::time AS 到场, travel_min AS 路上分钟 FROM v_travel_slot;
SELECT work_date, onsite_min AS 在场, span_min AS 首尾, travel_min AS 路上, project_count AS 跑几个项目 FROM v_daily_attendance;

\echo ''
\echo '=========== 检查 9：路上成本摊给下一站 ==========='
SELECT p.code, l.onsite_hours AS 在场时, l.travel_hours AS 路上时, l.onsite_cost AS 在场费, l.travel_cost AS 路上费, l.labor_cost AS 人工合计
FROM v_project_labor_cost l JOIN project p ON p.id=l.project_id ORDER BY p.code;

\echo ''
\echo '=========== 检查 10：午餐自动扣除 ==========='
SELECT span_minutes AS 首尾, lunch_min AS 午餐扣, paid_minutes AS 付薪, over_span_min AS 工时超 FROM daily_report;
SELECT work_date, onsite_min AS 在场, span_min AS 首尾, lunch_min AS 午餐, paid_min AS 付薪, travel_min AS 路上 FROM v_daily_attendance;
SELECT seq, travel_min AS 路上分钟, crosses_lunch AS 跨午餐 FROM v_travel_slot;
SELECT p.code AS 午餐扣给谁, l.lunch_min FROM v_daily_lunch l LEFT JOIN project p ON p.id=l.charged_project_id;
SELECT p.code, l.onsite_hours AS 在场时, l.travel_hours AS 路上时, l.lunch_hours AS 午餐时, l.labor_cost AS 人工合计
FROM v_project_labor_cost l JOIN project p ON p.id=l.project_id ORDER BY p.code;

\echo '--- 短工日(4小时)不扣午餐 ---'
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method)
VALUES('aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','sm','2026-07-21 09:00+10','2026-07-21 13:00+10','gps');
SELECT work_date, span_min AS 首尾, lunch_min AS 午餐, paid_min AS 付薪 FROM v_daily_attendance WHERE work_date='2026-07-21';
