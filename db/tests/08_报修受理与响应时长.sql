SET timezone='Australia/Sydney';
SET app.actor='运维-小周';
\set ON_ERROR_STOP off

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','小周','hourly',80,'2025-01-01');
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,handover_at,status,free_warranty_months)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','KX-2026-8002','rough_in',now(),600000,
       now()-interval '2 months','delivered',12);

\echo ''
\echo '=========== 情况一：记得清楚——周一上午客户来电 ==========='
INSERT INTO maintenance_case(id,project_id,title,reported_at,report_channel,taken_by,report_note)
VALUES('cccccccc-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-00000000000b','客厅面板失灵',
       now()-interval '4 days', 'phone','前台-小李','客户说面板按了没反应，昨晚开始的');

\echo '=========== 情况二：记不清——选未知 ==========='
INSERT INTO maintenance_case(id,project_id,title)
VALUES('cccccccc-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-00000000000b','影音室没声音');

\echo ''
\echo '--- 报修时间晚于建单时间(顺序反了) → 应拒 ---'
INSERT INTO maintenance_case(project_id,title,reported_at,report_channel)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','测试单',now()+interval '2 days','phone');
\echo '--- 记得时间却漏选渠道 → 应拒 ---'
INSERT INTO maintenance_case(project_id,title,reported_at)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','测试单2',now()-interval '1 day');

\echo ''
\echo '=========== 两单都上门修完 ==========='
INSERT INTO maintenance_job(id,project_id,case_id,staff_id,scheduled_date,planned_minutes,
  fault_cause,service_summary,client_sign_url,client_sign_name,client_sign_at,completed_at) VALUES
 ('dddddddd-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-00000000000b','cccccccc-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',current_date,120,'product_defect','更换客厅四联面板','https://x/s1.jpg','王先生',now()-interval '1 day',now()-interval '1 day'),
 ('dddddddd-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-00000000000b','cccccccc-0000-0000-0000-000000000002',
  '11111111-1111-1111-1111-111111111111',current_date,90,'human','客户误拔功放电源线，已复位','https://x/s2.jpg','王先生',now(),now());

\echo ''
\echo '=========== 响应时长：算得出的算，算不出的写"未知" ==========='
SELECT title, report_channel AS 渠道, taken_by AS 谁接的,
       intake_hours AS 报修到建单H, response_hours AS 报修到上门H,
       response_unknown AS 响应未知 FROM v_maintenance_response ORDER BY title;

\echo ''
\echo '=========== 数据质量：多少单连报修时间都没记 ==========='
SELECT total_cases AS 总单数, with_report_time AS 有报修时间,
       unknown_report_time AS 未知, unknown_pct AS 未知占比 FROM v_response_data_quality;
