SET timezone='Australia/Sydney';
SET app.actor='工程经理-陈总';
\set ON_ERROR_STOP off

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','张三(时薪)','hourly',80,'2026-01-05');
INSERT INTO eng_staff(id,name,pay_type,monthly_salary,cost_hourly_rate,hired_at) VALUES
 ('22222222-2222-2222-2222-222222222222','李四(月薪)','monthly',9000,75,'2025-03-01');
\echo '--- 月薪制没填成本时薪 → 应拒 ---'
INSERT INTO eng_staff(name,pay_type,monthly_salary) VALUES('王五','monthly',8000);
\echo '--- 外包 A：日薪 $510 / 参考 10 小时 → 成本时薪应算出 51 ---'
INSERT INTO eng_staff(id,name,pay_type,daily_rate,ref_minutes,hired_at) VALUES
 ('33333333-3333-3333-3333-333333333333','外包A','contractor',510,600,'2026-07-01');
\echo '--- 外包 B：日薪 $480 / 承诺 6 小时 → 成本时薪 80 ---'
INSERT INTO eng_staff(id,name,pay_type,daily_rate,ref_minutes,hired_at) VALUES
 ('44444444-4444-4444-4444-444444444444','外包B','contractor',480,360,'2026-07-01');
\echo '--- 外包没填参考时间 → 应拒 ---'
INSERT INTO eng_staff(name,pay_type,daily_rate) VALUES('外包C','contractor',500);
SELECT name, pay_type, pay_terms AS 计薪方式, cost_hourly_rate AS 成本时薪, hired_at AS 入职 FROM v_staff_overview ORDER BY name;

INSERT INTO project(id,code,build_stage,contract_price) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','KX-2026-0142','rough_in',500000);

\echo ''
\echo '=========== 入职时间门禁 ==========='
\echo '--- 给外包A生成入职前(6/30)的日结 → 应拒 ---'
SELECT fn_lock_daily_payroll('33333333-3333-3333-3333-333333333333','2026-06-30');

\echo ''
\echo '=========== 外包：周日上工也不算加班 ==========='
-- 外包A 周日 2026-07-26 干 9 小时（首尾540，午餐30，付薪510）
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','execution','2026-07-26 08:00+10','2026-07-26 17:00+10','gps');
-- 李四(月薪) 同一个周日也上工 5 小时 → 整天算加班
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','execution','2026-07-26 09:00+10','2026-07-26 14:00+10','gps');
SELECT fn_lock_daily_payroll('33333333-3333-3333-3333-333333333333','2026-07-26');
SELECT fn_lock_daily_payroll('22222222-2222-2222-2222-222222222222','2026-07-26');
SELECT s.name, d.day_type AS 当天性质, d.paid_min AS 付薪分, d.ot_min AS 加班分,
       d.pay_rate_snap AS 费率定格, d.cost_rate_snap AS 成本时薪, d.pay_amount AS 当日应发
FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id WHERE d.work_date='2026-07-26' ORDER BY s.name;

\echo ''
\echo '=========== 外包按天覆盖（说好只来半天，参考时间也改） ==========='
INSERT INTO staff_daily_commitment(staff_id,work_date,ref_minutes,daily_rate_override,note,created_by)
VALUES('33333333-3333-3333-3333-333333333333','2026-07-27',240,280,'只来半天，谈好$280，参考时间也按4小时','工程经理-陈总');
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','execution','2026-07-27 08:00+10','2026-07-27 12:00+10','gps');
SELECT fn_lock_daily_payroll('33333333-3333-3333-3333-333333333333','2026-07-27');
SELECT work_date, paid_min AS 付薪分, pay_rate_snap AS 当日日薪, cost_rate_snap AS 成本时薪, pay_amount AS 应发
FROM daily_payroll WHERE staff_id='33333333-3333-3333-3333-333333333333' ORDER BY work_date;

\echo ''
\echo '=========== 离职清算（月薪制李四，有倒休余额） ==========='
SELECT name, toil_balance_hours AS 倒休余额H FROM v_staff_overview WHERE name LIKE '李四%';
SELECT fn_prepare_termination('22222222-2222-2222-2222-222222222222','2026-07-31');
SELECT toil_balance_min AS 余额分, rate_snap AS 折算费率, toil_value AS 系统应结
FROM termination_settlement;
\echo '--- 实付与应结不符、不填原因 → 应拒 ---'
UPDATE termination_settlement SET paid_amount=200, settled_at=now();
\echo '--- 填原因 → 应通过，倒休自动冲平 ---'
UPDATE termination_settlement SET paid_amount=200, settled_at=now(),
  decision_note='双方协商：其中4小时已在7月调休，余额按协议折半结算' ;
SELECT toil_value AS 应结, paid_amount AS 实付, decision_note AS 原因, decided_by AS 谁定的 FROM termination_settlement;
SELECT name, accrued_hours AS 累计, taken_hours AS 已休, balance_hours AS 冲平后余额 FROM v_toil_balance WHERE name LIKE '李四%';

\echo ''
\echo '--- 离职后再生成日结 → 应拒 ---'
SELECT fn_lock_daily_payroll('22222222-2222-2222-2222-222222222222','2026-08-03');

\echo ''
\echo '=========== 外包成本进项目利润率 ==========='
SELECT p.code, l.onsite_hours AS 在场时, l.labor_cost AS 人工成本
FROM v_project_labor_cost l JOIN project p ON p.id=l.project_id;

\echo ''
\echo '=========== 外包：实付日薪 vs 摊进项目的成本 ==========='
SELECT name, work_date, daily_paid AS 实付日薪, cost_rate AS 成本时薪, onsite_hours AS 在场H,
       charged_to_projects AS 摊进项目, gap AS 差额 FROM v_contractor_cost_gap ORDER BY work_date;
