-- 08 报修受理与响应时长
-- ★v0.37 重写（决策记录 §九·补四 · M1）：「报修时间」拆成两个。
--   报修时间 reported_at  = 客户什么时候【告诉我们】的 —— 永远知道（接到电话那一刻）→ SLA 起点，必填
--   问题出现 issue_since  = 问题什么时候【开始】的     —— 客户经常说不清（"好几天了"）→ 可空
--   ★原来的洞：只有一个「报修时间」还允许留空 → 客户说不清就留空 → 这一单退出响应时长统计
--     → 真正响应慢的单最容易从统计里漏掉，报表永远好看。不报错，只是数字悄悄错了。
-- 期望拦截：6 次
SET timezone='Australia/Sydney';
SET app.actor='运维-小周';
\set ON_ERROR_STOP off

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','小周','hourly',80,'2025-01-01');
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,handover_at,status,free_warranty_months)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','KX-2026-8002','rough_in',now(),600000,
       now()-interval '2 months','delivered',12);

\echo ''
\echo '=========== 情况一：两个时间都记得清楚 ==========='
INSERT INTO maintenance_case(id,project_id,title,reported_at,issue_since,pri,
                             report_channel,taken_by,report_note,rd_conclusion,rd_by,rd_at)
VALUES('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-00000000000b','客厅面板失灵',
       now()-interval '4 days', now()-interval '5 days', 'P1',
       'phone','前台-小李','客户说面板按了没反应，昨晚开始的',
       '远程看网关在线、面板离线，判断面板本体故障','研发-小赵',now()-interval '4 days');

\echo '=========== 情况二：★问题什么时候开始的说不清（这个才可以空）==========='
--     ——但「客户什么时候告诉我们的」永远知道，所以 reported_at 照填
INSERT INTO maintenance_case(id,project_id,title,reported_at,report_channel,taken_by,pri,
                             rd_skip_reason)
VALUES('cccccccc-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-00000000000b','影音室没声音',
       now()-interval '2 days','wechat','前台-小李','P2',
       '客户说是自己动过接线，直接上门看比远程快');

\echo ''
\echo '--- ★应拦：报修时间晚于建单时间（顺序反了）---'
INSERT INTO maintenance_case(project_id,title,reported_at,report_channel)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','测试单',now()+interval '2 days','phone');
\echo '--- ★应拦：漏选报修渠道（v0.37 起无条件必填——接电话那一刻就知道是怎么找过来的）---'
INSERT INTO maintenance_case(project_id,title,reported_at)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','测试单2',now()-interval '1 day');
\echo '--- ★应拦：显式把报修时间置空（v0.37 起必填——留空那一单就退出 SLA 统计，'
\echo '            于是真正响应慢的最容易漏掉，报表永远好看）---'
INSERT INTO maintenance_case(project_id,title,reported_at,report_channel)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','测试单3',NULL,'phone');
\echo '--- 不写报修时间 → 默认「现在」，正常受理（接电话那一刻就建单，默认值就是准确值）---'
INSERT INTO maintenance_case(project_id,title,report_channel,rd_skip_reason)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','厨房灯带闪烁','phone','客户描述明确，直接上门');
SELECT title, (reported_at IS NOT NULL) AS 报修时间已落
  FROM maintenance_case WHERE title='厨房灯带闪烁';
\echo '--- ★应拦：问题出现时间晚于报修时间（问题总得先出现，客户才会打电话）---'
INSERT INTO maintenance_case(project_id,title,reported_at,issue_since,report_channel)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','测试单4',
       now()-interval '3 days', now()-interval '1 day','phone');

\echo ''
\echo '=========== 两单都上门修完 ==========='
INSERT INTO maintenance_job(id,project_id,case_id,staff_id,scheduled_date,planned_minutes,
  fault_cause,service_summary,client_sign_url,client_sign_name,client_sign_at,completed_at) VALUES
 ('dddddddd-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-00000000000b','cccccccc-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',current_date,120,'product_defect','更换客厅四联面板','https://x/s1.jpg','王先生',now()-interval '1 day',now()-interval '1 day'),
 ('dddddddd-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-00000000000b','cccccccc-0000-0000-0000-000000000002',
  '11111111-1111-1111-1111-111111111111',current_date,90,'human','客户误拔功放电源线，已复位','https://x/s2.jpg','王先生',now(),now());

\echo ''
\echo '=========== ★响应时长：每一单都参与 SLA（不再有"未知"这个出口）==========='
SELECT title, pri AS 分级, sla_hours AS SLA小时, report_channel AS 渠道,
       intake_hours AS 报修到建单H, response_hours AS 报修到上门H,
       sla_breached AS 超SLA, waited_days_before_report AS 客户拖了几天才报
  FROM v_maintenance_response ORDER BY title;

\echo ''
\echo '=========== ★时间对不上（报修晚于上门）：标出来并退出统计，不许算成负数 ==========='
--     负数会被平均进 SLA 报表，把真实的响应慢冲掉，而且不报错
INSERT INTO maintenance_case(id,project_id,title,reported_at,report_channel,rd_skip_reason)
VALUES('cccccccc-0000-0000-0000-000000000003','bbbbbbbb-0000-0000-0000-00000000000b','阳台灯不亮',
       now()-interval '1 hour','phone','小问题，直接上门');
INSERT INTO maintenance_job(project_id,case_id,staff_id,scheduled_date,planned_minutes,
  fault_cause,service_summary,client_sign_url,client_sign_name,client_sign_at,completed_at)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','cccccccc-0000-0000-0000-000000000003',
  '11111111-1111-1111-1111-111111111111',current_date,30,'wear_out','换灯珠','https://x/s3.jpg','王先生',
  now()-interval '3 days',now()-interval '3 days');
SELECT title, time_inconsistent AS 时间对不上, response_hours AS 响应H, sla_breached AS 超SLA
  FROM v_maintenance_response WHERE title='阳台灯不亮';

\echo ''
\echo '=========== 数据质量：★现在统计的是「问题出现时间」的未知率 ==========='
--     报修时间已改必填，不会再未知；这个比例只影响"客户拖了多久才报"这个分析，不影响 SLA
SELECT total_cases AS 总单数, with_issue_since AS 有出现时间,
       unknown_issue_since AS 说不清, unknown_pct AS 说不清占比 FROM v_response_data_quality;

\echo ''
\echo '=========== ★M3 分级 SLA：超本档的自动进待办 ==========='
SELECT project_code, title, pri AS 分级, sla_hours AS SLA小时, elapsed_hours AS 已用H
  FROM v_mt_sla_breach ORDER BY title;
