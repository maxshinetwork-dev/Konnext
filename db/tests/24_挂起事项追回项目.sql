SET timezone='Australia/Sydney';
\set ON_ERROR_STOP off
INSERT INTO app_account(id,login_name,full_name,tier,is_core_admin,phone,email,phone_bound_at)
VALUES('a0000000-0000-0000-0000-000000000001','core','陈总',1,true,'0400000000','core@x.com',now());
SET app.account_id='a0000000-0000-0000-0000-000000000001';
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,cost_hourly_rate,phone,hired_at)
VALUES('e1111111-1111-1111-1111-111111111111','小陈','hourly',80,80,'0422000001','2025-01-01');
INSERT INTO project(id,code,name,build_stage,step6_signed_at,contract_price,
  o1_name,addr_street,addr_suburb,addr_state)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','Cherrybrook 王宅','rough_in',now(),500000,
       '王先生','8 Franklin Rd','Cherrybrook','NSW'),
      ('bbbbbbbb-0000-0000-0000-00000000000b','KX-2026-0180','Hornsby 陈宅','rough_in',now(),350000,
       '陈女士','22 Rosamond St','Hornsby','NSW');

\echo ''
\echo '════ ① 问题上报：不填项目也不标公司级 → 应拒 ════'
INSERT INTO daily_report(id,staff_id,report_date)
VALUES('dd000000-0000-0000-0000-000000000001','e1111111-1111-1111-1111-111111111111','2026-07-28');
INSERT INTO daily_issue(report_id,issue_type,description)
VALUES('dd000000-0000-0000-0000-000000000001','product','面板批次问题');

\echo '--- 落到项目 → 通过 ---'
INSERT INTO daily_issue(report_id,issue_type,project_id,description)
VALUES('dd000000-0000-0000-0000-000000000001','product','aaaaaaaa-0000-0000-0000-00000000000a',
       '同批面板第三次同样故障，怀疑批次问题');
\echo '--- 明确标为公司级 → 通过 ---'
INSERT INTO daily_issue(report_id,issue_type,description,is_company_level)
VALUES('dd000000-0000-0000-0000-000000000001','standardization','出库单流程需标准化',true);
SELECT issue_type_cn AS 类型, pj_code AS 编号, pj_label AS 项目标识, pj_suburb AS Suburb
FROM v_daily_issue_detail ORDER BY 类型;

\echo ''
\echo '════ ② 某人某天涉及哪些项目（跨项目追溯的底座） ════'
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a','e1111111-1111-1111-1111-111111111111','execution',
  '2026-07-28 09:00+10','2026-07-28 12:00+10','gps'),
 ('bbbbbbbb-0000-0000-0000-00000000000b','e1111111-1111-1111-1111-111111111111','execution',
  '2026-07-28 15:00+10','2026-07-28 18:30+10','gps');
SELECT staff_name AS 谁, work_date AS 日期, project_count AS 跑了几个项目,
       project_codes AS 项目编号, project_suburbs AS 地点 FROM v_daily_projects;

\echo ''
\echo '════ ③ ★挂起的日结：管理人员据此知道该去哪个项目补录 ════'
SELECT fn_lock_daily_payroll('e1111111-1111-1111-1111-111111111111','2026-07-28');
\echo '--- 再造一天：没打卡也没派工 → 挂起且无从追溯 ---'
SELECT fn_lock_daily_payroll('e1111111-1111-1111-1111-111111111111','2026-07-29');
SELECT staff_name AS 谁, work_date AS 日期, status AS 状态, project_count AS 项目数,
       project_codes AS 当天项目, backfill_hint AS 补录线索
FROM v_daily_payroll_detail ORDER BY work_date;

\echo ''
\echo '════ ④ 倒休来源：哪天的加班、那天在哪些项目 ════'
INSERT INTO eng_staff(id,name,pay_type,monthly_salary,cost_hourly_rate,phone,hired_at)
VALUES('e2222222-2222-2222-2222-222222222222','李四','monthly',9000,75,'0422000002','2025-01-01');
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','e2222222-2222-2222-2222-222222222222','execution',
       '2026-07-26 09:00+10','2026-07-26 14:00+10','gps');
SELECT fn_lock_daily_payroll('e2222222-2222-2222-2222-222222222222','2026-07-26');
SELECT staff_name AS 谁, entry_type AS 类型, hours AS 小时, source_work_date AS 来自哪天,
       source_day_type AS 当天性质, source_project_codes AS 来自哪个项目 FROM v_toil_detail;

\echo ''
\echo '════ ⑤ ★悬而未决总表：每行都说得清是哪个项目 ════'
SELECT kind_cn AS 类型, pj_code AS 编号, pj_suburb AS Suburb,
       left(title,24) AS 事项, left(action,22) AS 要做什么, owner AS 归谁, overdue AS 超期
FROM v_open_tasks ORDER BY overdue DESC, kind LIMIT 12;

\echo ''
\echo '════ ⑥ 断言 ════'
SELECT * FROM fn_assertion_summary();
SELECT code, severity, label, status FROM fn_run_assertions() WHERE violations<>0;
