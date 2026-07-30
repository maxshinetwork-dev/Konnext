SET timezone='Australia/Sydney';
SET app.actor='工程经理-陈总';
\set ON_ERROR_STOP off

\echo '=========== 工程管理设置全局加班倍数 ==========='
UPDATE eng_setting SET value_num=1.5 WHERE key='ot_rate_weekday';
UPDATE eng_setting SET value_num=1.5 WHERE key='ot_rate_saturday';
UPDATE eng_setting SET value_num=2.0 WHERE key='ot_rate_sunday';
UPDATE eng_setting SET value_num=2.0 WHERE key='ot_rate_holiday';
SELECT key, value_num AS 倍数, updated_by AS 谁改的 FROM eng_setting WHERE key LIKE 'ot_rate%' ORDER BY key;

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','张三(跟全局)','hourly',80,'2025-01-01'),
 ('22222222-2222-2222-2222-222222222222','赵六(单谈的)','hourly',80,'2025-01-01');
\echo ''
\echo '--- 给赵六单独设：周日 2.5 倍 ---'
UPDATE eng_staff SET ot_rate_sunday=2.5 WHERE id='22222222-2222-2222-2222-222222222222';
\echo '--- 想设成 0.8 倍(比平时还低) → 应拒 ---'
UPDATE eng_staff SET ot_rate_weekday=0.8 WHERE id='22222222-2222-2222-2222-222222222222';
SELECT name, weekday AS 平日, saturday AS 周六, sunday AS 周日, holiday AS 假日, has_override AS 有单独设置
FROM v_ot_rate_config ORDER BY name;

INSERT INTO project(id,code,build_stage,contract_price) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','KX-2026-0142','rough_in',500000);

\echo ''
\echo '=========== 平日加班 1.5 倍（张三 9:00-18:30 → 加班1小时）==========='
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','execution','2026-07-22 09:00+10','2026-07-22 18:30+10','gps');
SELECT fn_lock_daily_payroll('11111111-1111-1111-1111-111111111111','2026-07-22');

\echo '=========== 周日：张三 2.0 倍 vs 赵六 2.5 倍（同样干5小时）==========='
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','execution','2026-07-26 09:00+10','2026-07-26 14:00+10','gps'),
 ('aaaaaaaa-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','execution','2026-07-26 09:00+10','2026-07-26 14:00+10','gps');
SELECT fn_lock_daily_payroll('11111111-1111-1111-1111-111111111111','2026-07-26');
SELECT fn_lock_daily_payroll('22222222-2222-2222-2222-222222222222','2026-07-26');

\echo '=========== 公共假日 Anzac Day：2.0 倍 ==========='
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','execution','2026-04-25 08:00+10','2026-04-25 16:00+10','gps');
SELECT fn_lock_daily_payroll('11111111-1111-1111-1111-111111111111','2026-04-25');

SELECT s.name, d.work_date, d.day_type AS 性质, d.normal_min AS 正常分, d.ot_min AS 加班分,
       d.ot_rate_snap AS 倍数定格, d.pay_amount AS 当日应发
FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id ORDER BY d.work_date, s.name;

\echo ''
\echo '=========== 倍数定格：以后改倍数，不影响已发的单 ==========='
UPDATE eng_setting SET value_num=3.0 WHERE key='ot_rate_sunday';
SELECT s.name, d.work_date, d.ot_rate_snap AS 当时定格的倍数, d.pay_amount AS 当时应发
FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id WHERE d.work_date='2026-07-26' ORDER BY s.name;

\echo ''
\echo '=========== 改倍数留痕 ==========='
SELECT actor AS 谁改的, table_name, action,
       (before->>'value_num') AS 改前, (after->>'value_num') AS 改后, (after->>'key') AS 项目
FROM audit_log WHERE table_name='eng_setting' ORDER BY at;
