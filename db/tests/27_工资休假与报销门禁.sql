-- 27 工资休假与报销门禁（v0.34）：成本时薪 · 挂起补录 · 倒休休假/透支 · 报销三类 · 工程追加变更
-- 期望拦截：16 次
\echo '════════ ① 人员：成本时薪门禁 + 邮箱列 ════════'
INSERT INTO eng_staff(name,pay_type,monthly_salary,cost_hourly_rate,email)
VALUES ('测试小陈','monthly',5800,34.9,'chen@x.com');
INSERT INTO eng_staff(name,pay_type,pay_hourly_rate) VALUES ('测试阿强','hourly',42);
\echo '--- ⑴ 月薪制不填成本时薪 → 应拦 ---'
INSERT INTO eng_staff(name,pay_type,monthly_salary) VALUES ('测试老李','monthly',6200);

INSERT INTO project(code,name,addr_suburb,addr_state,build_stage,step6_signed_at,created_at)
VALUES ('KX-T27-01','测试工资宅','Ryde','NSW','structure',now()-interval '60 days',now()-interval '90 days');

\echo '════════ ② 挂起补录：类别+详说(≥10字)+补录人 缺一不可 ════════'
INSERT INTO daily_payroll(staff_id,work_date,day_type,pay_type_snap,status,unrecorded)
SELECT id,'2026-07-29','weekday','monthly','unrecorded_held',true
  FROM eng_staff WHERE name='测试小陈';
\echo '--- ⑵ 补录不选原因类别 → 应拦 ---'
UPDATE daily_payroll SET status='released',
       backfilled_by=(SELECT id FROM eng_staff WHERE name='测试阿强'),
       backfill_note='早上直接去了现场布线忘了在App打卡确有出工'
 WHERE work_date='2026-07-29';
\echo '--- ⑶ 详细说明不足 10 字 → 应拦 ---'
UPDATE daily_payroll SET status='released',
       backfilled_by=(SELECT id FROM eng_staff WHERE name='测试阿强'),
       backfill_reason_cat='forgot_punch', backfill_note='忘了打卡'
 WHERE work_date='2026-07-29';
\echo '--- 规范补录（类别+详说+补录人）→ 应成功 ---'
UPDATE daily_payroll SET status='released',
       backfilled_by=(SELECT id FROM eng_staff WHERE name='测试阿强'),
       backfill_reason_cat='forgot_punch',
       backfill_note='早上直接去了现场布线，忘了在 App 打卡，负责人核实确有出工'
 WHERE work_date='2026-07-29';
SELECT status, backfill_reason_cat, (backfilled_at IS NOT NULL) AS 补录时刻已落格
  FROM daily_payroll WHERE work_date='2026-07-29';

\echo '════════ ③ 倒休休假：回 Y 自动扣 · 强制扣减留痕 · 不能透支 ════════'
INSERT INTO toil_ledger(staff_id,entry_type,minutes,reason)
SELECT id,'accrue',600,'07 月加班转倒休' FROM eng_staff WHERE name='测试小陈';
\echo '--- ⑷ 休假区间 至 早于 从 → 应拦 ---'
INSERT INTO leave_request(staff_id,from_ts,to_ts,minutes)
SELECT id,'2026-08-06 17:00+10','2026-08-06 09:00+10',480 FROM eng_staff WHERE name='测试小陈';
\echo '--- ⑸ 确认扣减 720 分钟（余额 600）→ 应拦（透支） ---'
INSERT INTO leave_request(staff_id,from_ts,to_ts,minutes)
SELECT id,'2026-08-05 09:00+10','2026-08-05 21:00+10',720 FROM eng_staff WHERE name='测试小陈';
UPDATE leave_request SET status='confirmed', sms_replied_at=now() WHERE minutes=720;
\echo '--- 480 分钟 · 员工回 Y → 应成功，流水自动扣、单据挂流水号 ---'
INSERT INTO leave_request(staff_id,from_ts,to_ts,minutes,created_by)
SELECT id,'2026-08-07 09:00+10','2026-08-07 17:00+10',480,'王姐' FROM eng_staff WHERE name='测试小陈';
UPDATE leave_request SET status='confirmed', sms_replied_at=now() WHERE minutes=480;
SELECT lr.status, (lr.toil_entry_id IS NOT NULL) AS 已挂流水,
       (SELECT SUM(minutes) FROM toil_ledger t JOIN eng_staff s ON s.id=t.staff_id
         WHERE s.name='测试小陈') AS 余额分钟
  FROM leave_request lr WHERE lr.minutes=480;
\echo '--- ⑹ 强制扣减不记操作人 → 应拦 ---'
INSERT INTO leave_request(staff_id,from_ts,to_ts,minutes)
SELECT id,'2026-08-08 09:00+10','2026-08-08 10:00+10',60 FROM eng_staff WHERE name='测试小陈';
UPDATE leave_request SET status='forced_deducted' WHERE minutes=60;
\echo '--- 强制扣减留痕（decided_by）→ 应成功，余额 600-480-60=60 ---'
UPDATE leave_request SET status='forced_deducted', decided_by='王姐' WHERE minutes=60;
SELECT (SELECT SUM(minutes) FROM toil_ledger t JOIN eng_staff s ON s.id=t.staff_id
         WHERE s.name='测试小陈') AS 余额分钟_应60;
\echo '--- ⑺ 绕开休假单直插流水扣 120（余额 60）→ 应拦（透支） ---'
INSERT INTO toil_ledger(staff_id,entry_type,minutes,reason)
SELECT id,'take',-120,'直插测试' FROM eng_staff WHERE name='测试小陈';
\echo '--- ⑻ 已扣减的休假单再改状态 → 应拦 ---'
UPDATE leave_request SET status='cancelled' WHERE minutes=480;

\echo '════════ ④ 报销：三类正名 · 收据必填 · 无「已付」 ════════'
\echo '--- ⑼ 类别 meal → 应拦（只有 material/tool/transport） ---'
INSERT INTO expense_claim(claim_no,claimant_staff_id,project_id,category,amount_aud,receipt_url,status)
SELECT 'EX-T27-01',s.id,p.id,'meal',30,'https://x/r0.jpg','submitted'
  FROM eng_staff s, project p WHERE s.name='测试小陈' AND p.code='KX-T27-01';
\echo '--- ⑽ 无收据照片提交 → 应拦 ---'
INSERT INTO expense_claim(claim_no,claimant_staff_id,project_id,category,amount_aud,status)
SELECT 'EX-T27-02',s.id,p.id,'material',186.5,'submitted'
  FROM eng_staff s, project p WHERE s.name='测试小陈' AND p.code='KX-T27-01';
\echo '--- 三类之一 + 收据链接 → 应成功 ---'
INSERT INTO expense_claim(claim_no,claimant_staff_id,project_id,category,amount_aud,receipt_url,status)
SELECT 'EX-T27-03',s.id,p.id,'transport',42,'https://x/r1.jpg','submitted'
  FROM eng_staff s, project p WHERE s.name='测试小陈' AND p.code='KX-T27-01';
\echo '--- ⑾ 标记「已付」→ 应拦（付款不走本系统） ---'
UPDATE expense_claim SET status='paid' WHERE claim_no='EX-T27-03';

\echo '════════ ⑤ 工程追加变更（2026-08-02 拍板：放开 + 告知短信） ════════'
\echo '--- ⑿ origin 乱值 → 应拦 ---'
INSERT INTO variation(project_id,origin,change_type,description)
SELECT id,'wechat','add','乱来' FROM project WHERE code='KX-T27-01';
\echo '--- ⒀ SM3 未完成就工程追加 → 应拦 ---'
INSERT INTO variation(project_id,origin,change_type,description)
SELECT id,'post_sm3','add','走廊补感应地脚灯' FROM project WHERE code='KX-T27-01';
INSERT INTO site_meeting(project_id,sm_no,completed_at)
SELECT id,1,now()-interval '30 days' FROM project WHERE code='KX-T27-01';
INSERT INTO site_meeting(project_id,sm_no,completed_at)
SELECT id,2,now()-interval '20 days' FROM project WHERE code='KX-T27-01';
INSERT INTO site_meeting(project_id,sm_no,completed_at)
SELECT id,3,now()-interval '10 days' FROM project WHERE code='KX-T27-01';
UPDATE project SET status='in_construction' WHERE code='KX-T27-01';
\echo '--- ⒁ 预计工时负数 → 应拦 ---'
INSERT INTO variation(project_id,origin,change_type,description,labor_hours_est)
SELECT id,'post_sm3','add','负工时测试',-5 FROM project WHERE code='KX-T27-01';
\echo '--- 规范工程追加 → 应成功，告知短信时刻自动落格 ---'
INSERT INTO variation(project_id,origin,change_type,description,labor_hours_est)
SELECT id,'post_sm3','add','走廊补 3 个感应地脚灯（业主安装期提出）',6 FROM project WHERE code='KX-T27-01';
SELECT origin, labor_hours_est, (payer_notified_at IS NOT NULL) AS 已发告知短信
  FROM variation WHERE origin='post_sm3';
\echo '--- ⒂ 项目不在施工中（烂尾示例）再追加 → 应拦 ---'
UPDATE project SET status='stalled' WHERE code='KX-T27-01';
INSERT INTO variation(project_id,origin,change_type,description)
SELECT id,'post_sm3','add','烂尾后追加' FROM project WHERE code='KX-T27-01';
\echo '--- ⒃ 变更来源登记后改动 → 应拦 ---'
UPDATE variation SET origin='sm3' WHERE origin='post_sm3';

\echo '════════ ⑥ 邮箱列就位（三处选填） ════════'
INSERT INTO household_member(project_id,member_type,age,email)
SELECT id,'adult',40,'owner@x.com' FROM project WHERE code='KX-T27-01';
INSERT INTO project_party(project_id,trade,company,contact_name,phone,email)
SELECT id,'builder','BuildCo','Mike','0422 000 111','mike@buildco.com.au' FROM project WHERE code='KX-T27-01';
SELECT (SELECT email FROM eng_staff WHERE name='测试小陈') AS 人员邮箱,
       (SELECT email FROM project_party WHERE contact_name='Mike') AS 参建方邮箱;
