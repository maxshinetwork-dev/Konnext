SET timezone='Australia/Sydney';
SET app.actor='财务-王姐';
\set ON_ERROR_STOP off

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,cost_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','张三(时薪制)','hourly',80,80,'2026-01-01');
INSERT INTO eng_staff(id,name,pay_type,monthly_salary,cost_hourly_rate,hired_at) VALUES
 ('22222222-2222-2222-2222-222222222222','李四(月薪制)','monthly',9000,75,'2025-01-01');
\echo '--- 月薪制没填月薪 → 应拒(CHECK) ---'
INSERT INTO eng_staff(name,pay_type,cost_hourly_rate) VALUES('王五','monthly',70);

INSERT INTO project(id,code,build_stage,contract_price) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','KX-2026-0142','rough_in',500000);

-- 张三：周三 9:00-18:30（首尾570，午餐30，付薪540 → 平日超8h=60分加班）
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','execution','2026-07-22 09:00+10','2026-07-22 18:30+10','gps');
-- 李四：周六 9:00-14:00（整天算加班 → 倒休）
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','execution','2026-07-25 09:00+10','2026-07-25 14:00+10','gps');
-- 李四：公共假日 Anzac Day 4/25 上工 8:00-16:00
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','execution','2026-04-25 08:00+10','2026-04-25 16:00+10','gps');

\echo ''
\echo '=========== 当夜0点定格 ==========='
SELECT fn_lock_daily_payroll('11111111-1111-1111-1111-111111111111','2026-07-22');
SELECT fn_lock_daily_payroll('22222222-2222-2222-2222-222222222222','2026-07-25');
SELECT fn_lock_daily_payroll('22222222-2222-2222-2222-222222222222','2026-04-25');
\echo '--- 张三周四没出工也没上报 → 挂起不发 ---'
SELECT fn_lock_daily_payroll('11111111-1111-1111-1111-111111111111','2026-07-23');
SELECT s.name, d.work_date, d.day_type AS 当天性质, d.span_min AS 首尾, d.lunch_min AS 午餐,
       d.paid_min AS 付薪, d.normal_min AS 正常, d.ot_min AS 加班, d.pay_amount AS 当日应发, d.status
FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id ORDER BY s.name, d.work_date;

\echo ''
\echo '=========== 定格后想改 → 应拒 ==========='
UPDATE daily_payroll SET paid_min=600 WHERE work_date='2026-07-22';
\echo '--- 补录放行但没填负责人/说明 → 应拒 ---'
UPDATE daily_payroll SET status='released' WHERE work_date='2026-07-23';
\echo '--- 负责人补录 + 说明 → 应通过 ---'
UPDATE daily_payroll SET status='released', backfilled_by='22222222-2222-2222-2222-222222222222',
  backfill_note='张三当天在工地地下室无信号，事后核实确有出工' WHERE work_date='2026-07-23';
SELECT work_date, status, backfilled_at IS NOT NULL AS 已补录 FROM daily_payroll WHERE work_date='2026-07-23';

\echo ''
\echo '=========== 倒休：月薪制加班不发钱，转倒休 ==========='
SELECT name, pay_type, accrued_hours AS 累计倒休H, taken_hours AS 已休H, balance_hours AS 余额H FROM v_toil_balance;
\echo '--- 李四休掉一天(8小时) ---'
INSERT INTO toil_ledger(staff_id,entry_type,minutes,reason,created_by)
VALUES('22222222-2222-2222-2222-222222222222','take',-480,'调休一天','工程负责人');
SELECT name, accrued_hours AS 累计, taken_hours AS 已休, balance_hours AS 余额 FROM v_toil_balance WHERE pay_type='monthly';

\echo ''
\echo '=========== 加班按性质分列 ==========='
SELECT name, pay_type, month, ot_weekday_h AS 平日, ot_saturday_h AS 周六, ot_sunday_h AS 周日,
       ot_holiday_h AS 公共假日, ot_total_h AS 合计 FROM v_overtime_summary ORDER BY name, month;

\echo ''
\echo '=========== 未记录天数（KPI） ==========='
SELECT name, still_held AS 仍挂起, total_unrecorded AS 累计未记录, last_unrecorded_date AS 最近一次 FROM v_unrecorded_days;

\echo ''
\echo '=========== 月度封账（上月21→本月20） ==========='
SELECT fn_lock_payroll_month('11111111-1111-1111-1111-111111111111','2026-08-20');
SELECT fn_lock_payroll_month('22222222-2222-2222-2222-222222222222','2026-08-20');
SELECT s.name, m.period_start AS 起, m.period_end AS 止, m.work_days AS 天数,
       m.ot_min AS 加班分, m.base_amount AS 基本, m.toil_accrued_min AS 本期倒休分,
       m.backpay_amount AS 补发, m.total_amount AS 合计, m.held_days AS 挂起天
FROM payroll_month m JOIN eng_staff s ON s.id=m.staff_id ORDER BY s.name;

\echo ''
\echo '=========== 成本时薪仍喂利润率（月薪制也算得出） ==========='
SELECT p.code, l.onsite_hours AS 在场时, l.labor_cost AS 人工成本
FROM v_project_labor_cost l JOIN project p ON p.id=l.project_id;
