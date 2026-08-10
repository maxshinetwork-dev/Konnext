-- 32 派工排班表（v0.38 · 决策记录 §16 四十一~四十四轮）
--
-- ★为什么排班必须和打卡分成两张表：
--   work_log 是【打卡】—— 实际发生了什么，工人在现场按的
--   eng_schedule 是【排班】—— 计划要发生什么，工程管理提前排的
--   只有打卡，就永远看不出「派了工没去」。这一列（计划 vs 实际）是工程流水账的核心，
--   而它在没有排班表的时候根本算不出来。
--
-- ★最要命的三条（都是「不报错、只是数字悄悄错了」那一类）：
--   同一人两段重叠 → 两边都以为他会去，结果他只到了一处，另一处白等一天
--   给过去的日期补排班 → 「计划 vs 实际」永远相等，那个对比彻底失效
--   倒休排超余额 → 公司白发工资，要等到年底对账才可能发现
-- 期望拦截：19 次
SET timezone='Australia/Sydney';
SET app.actor='工程管理-陈工';
\set ON_ERROR_STOP off

\echo '════════ ① 造数 ════════'
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,cost_hourly_rate,phone,hired_at) VALUES
 ('e3200000-0000-0000-0000-000000000001','小陈','hourly',80,60,'0411000111','2025-01-01'),
 ('e3200000-0000-0000-0000-000000000002','小李','hourly',75,55,'0411000222','2025-01-01');
INSERT INTO project(id,code,name,addr_street,addr_suburb,addr_state,build_stage,
                    step6_signed_at,contract_price,status,handover_at,free_warranty_months) VALUES
 ('a3200000-0000-0000-0000-000000000001','KX-T32-01','王宅','8 Franklin Rd','Cherrybrook','NSW',
  'rough_in',now(),500000,'in_construction',NULL,3),
 ('a3200000-0000-0000-0000-000000000002','KX-T32-02','陈宅','22 Rosamond St','Hornsby','NSW',
  'rough_in',now(),400000,'maintaining',now()-interval '3 months',12);
-- 小李攒了 6 小时倒休
INSERT INTO toil_ledger(staff_id,entry_type,minutes,reason,created_by)
VALUES('e3200000-0000-0000-0000-000000000002','accrue',360,'两次周末加班累计','财务-王姐');

\echo ''
\echo '════════ ② 排班基本门禁 ════════'
\echo '--- ★应拦：起始时间不是 15 分钟档（16:20 这种，工时统计和路线预估全对不齐）---'
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,project_id,created_by)
VALUES('e3200000-0000-0000-0000-000000000001',current_date+1,980,1020,'install',
       'a3200000-0000-0000-0000-000000000001','陈工');
\echo '--- ★应拦：截止早于开始 ---'
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,project_id,created_by)
VALUES('e3200000-0000-0000-0000-000000000001',current_date+1,990,480,'install',
       'a3200000-0000-0000-0000-000000000001','陈工');
\echo '--- ★应拦：非倒休任务不挂项目（这段工时进不了任何项目成本，人干了活成本凭空消失）---'
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,created_by)
VALUES('e3200000-0000-0000-0000-000000000001',current_date+1,480,990,'install','陈工');
\echo '--- ★应拦：倒休却挂了项目（休假不是工作）---'
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,project_id,created_by)
VALUES('e3200000-0000-0000-0000-000000000002',current_date+1,480,960,'toil',
       'a3200000-0000-0000-0000-000000000001','陈工');

\echo ''
\echo '--- 正常：小陈周一 08:00–16:30（★开始时间不固定，时长自动算）---'
INSERT INTO eng_schedule(id,staff_id,work_date,start_min,end_min,task_type,project_id,content,created_by)
VALUES('50320000-0000-0000-0000-000000000001','e3200000-0000-0000-0000-000000000001',
       current_date+1,480,990,'install','a3200000-0000-0000-0000-000000000001',
       E'客厅回路穿线\n主卧面板底盒定位','陈工');
SELECT staff_name, time_range AS 起止, minutes AS 分钟, dur_label AS 显示,
       remaining_snap AS 剩余工作
  FROM v_sched_week WHERE id='50320000-0000-0000-0000-000000000001';

\echo '--- ★应拦：同一人同一天两段重叠（一个人不能同时在两个工地）---'
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,project_id,created_by)
VALUES('e3200000-0000-0000-0000-000000000001',current_date+1,900,1080,'maintenance',
       'a3200000-0000-0000-0000-000000000002','陈工');
\echo '--- 正常：紧挨着不算重叠（16:30 结束，16:30 开始）---'
INSERT INTO eng_schedule(id,staff_id,work_date,start_min,end_min,task_type,project_id,content,created_by)
VALUES('50320000-0000-0000-0000-000000000002','e3200000-0000-0000-0000-000000000001',
       current_date+1,990,1185,'maintenance','a3200000-0000-0000-0000-000000000002',
       '客厅面板复检','陈工');

\echo ''
\echo '════════ ③ ★倒休余额不足直接拦 ════════'
\echo '--- ★应拦：小李只有 6 小时倒休，想休 8 小时 ---'
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,created_by)
VALUES('e3200000-0000-0000-0000-000000000002',current_date+2,480,960,'toil','陈工');
\echo '--- 正常：休 6 小时（480→840 = 360 分钟）---'
INSERT INTO eng_schedule(id,staff_id,work_date,start_min,end_min,task_type,created_by)
VALUES('50320000-0000-0000-0000-000000000003','e3200000-0000-0000-0000-000000000002',
       current_date+2,480,840,'toil','陈工');
\echo '--- ★应拦：余额已经排光了，再排一次（含同期已排未休的）---'
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,created_by)
VALUES('e3200000-0000-0000-0000-000000000002',current_date+3,480,600,'toil','陈工');
--   ★这里用 fn_toil_balance_min 而不是 v_toil_balance.balance_hours：
--     后者裹着薪酬遮罩，回归里没有身份，查出来是 NULL（遮罩正常工作）。
--     门禁与断言都必须用真实值 —— 详见 v0.38 那个 GENERATED 列的坑（决策记录 §25.三）
SELECT st.name, fn_toil_balance_min(st.id)/60.0 AS 余额H,
       (SELECT COALESCE(SUM(minutes),0)/60.0 FROM eng_schedule s
         WHERE s.staff_id=st.id AND s.task_type='toil' AND s.cancelled_at IS NULL) AS 已排H
  FROM eng_staff st WHERE st.name='小李';

\echo ''
\echo '════════ ④ ★不能给过去的日期排班 ════════'
--   事后补一条计划，「计划 vs 实际」就永远相等 —— 那个对比是用来发现
--   「派了工没去」「去了没派工」的，补出来的计划让它彻底失效，而且不会报错
\echo '--- ★应拦：给上周排班 ---'
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,project_id,created_by)
VALUES('e3200000-0000-0000-0000-000000000001',current_date-7,480,990,'install',
       'a3200000-0000-0000-0000-000000000001','陈工');

\echo ''
\echo '════════ ⑤ 锁定 · 改动 · 取消 ════════'
\echo '--- 锁定（＝已下发给本人）---'
UPDATE eng_schedule SET locked_at=now(), locked_by='陈工'
 WHERE id='50320000-0000-0000-0000-000000000001';
\echo '--- ★应拦：锁定之后直接改时间（工人手机上的日程会和这里对不上）---'
UPDATE eng_schedule SET end_min=1080 WHERE id='50320000-0000-0000-0000-000000000001';
\echo '--- 正常：先解锁再改（解锁留痕）。改成 08:00–16:00，不碰后面那段 16:30 起的维护 ---'
UPDATE eng_schedule SET locked_at=NULL WHERE id='50320000-0000-0000-0000-000000000001';
UPDATE eng_schedule SET end_min=960 WHERE id='50320000-0000-0000-0000-000000000001';
\echo '--- 锁定期间可以记回执（红点→绿点，不算改实质内容）---'
UPDATE eng_schedule SET locked_at=now(), notified_at=now()
 WHERE id='50320000-0000-0000-0000-000000000001';
UPDATE eng_schedule SET confirmed_at=now() WHERE id='50320000-0000-0000-0000-000000000001';
SELECT staff_name, time_range AS 起止, confirm_dot AS 红绿点
  FROM v_sched_week WHERE id='50320000-0000-0000-0000-000000000001';

\echo '--- ★应拦：取消不写原因 ---'
UPDATE eng_schedule SET cancelled_at=now() WHERE id='50320000-0000-0000-0000-000000000002';
\echo '--- 正常：取消并写原因（★被取消的人要回 Yes）---'
UPDATE eng_schedule SET cancelled_at=now(), cancel_reason='业主临时出差，改到下周'
 WHERE id='50320000-0000-0000-0000-000000000002';
SELECT staff_name, task_label, state AS 状态 FROM v_sched_confirm
 WHERE staff_name='小陈' ORDER BY state;

\echo ''
\echo '════════ ⑥ ★历史排班：不许改、不许删 ════════'
--   造历史数据只能绕过「不许给过去排班」那道门禁——这是【测试造数据】手段。
--   ★正式系统上线要导入历史排班时，必须走专门的导入通道（像期初库存移库那样一次性、
--     留痕、只能做一遍），绝不是让人来 DISABLE TRIGGER。
ALTER TABLE eng_schedule DISABLE TRIGGER sched_gate;
INSERT INTO eng_schedule(id,staff_id,work_date,start_min,end_min,task_type,project_id,content,created_by)
VALUES('50320000-0000-0000-0000-00000000000a','e3200000-0000-0000-0000-000000000001',
       current_date-3,480,990,'install','a3200000-0000-0000-0000-000000000001','上周四的活','陈工'),
      ('50320000-0000-0000-0000-00000000000b','e3200000-0000-0000-0000-000000000002',
       current_date-10,540,900,'maintenance','a3200000-0000-0000-0000-000000000002','上次巡检','陈工');
ALTER TABLE eng_schedule ENABLE TRIGGER sched_gate;

\echo '--- ★应拦：改过去的排班（历史就是历史）---'
UPDATE eng_schedule SET end_min=1080 WHERE id='50320000-0000-0000-0000-00000000000a';
\echo '--- ★应拦：删过去的排班（删了「计划 vs 实际」就少一半，看着像本来就没派人）---'
DELETE FROM eng_schedule WHERE id='50320000-0000-0000-0000-00000000000a';

\echo ''
\echo '════════ ⑦ ★计划 vs 实际：派了工没打卡 ════════'
--   这一列就是没有排班表时算不出来的东西
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method)
VALUES('a3200000-0000-0000-0000-000000000002','e3200000-0000-0000-0000-000000000002','maintenance',
       (current_date-10)::timestamptz+interval '9 hours',
       (current_date-10)::timestamptz+interval '15 hours','gps');
SELECT staff_name, work_date, task_label, actual_state AS 计划vs实际
  FROM v_project_schedule
 WHERE project_id IN ('a3200000-0000-0000-0000-000000000001','a3200000-0000-0000-0000-000000000002')
 ORDER BY work_date;

\echo ''
\echo '════════ ⑧ ★维护：上次没填剩余工作，这次派不了工 ════════'
--   上次没做完又没写，下一个人到了现场根本不知道该接着干什么 —— 白跑一趟没人会报错
\echo '--- ★应拦：上次巡检（10 天前）没填剩余 ---'
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,project_id,content,created_by)
VALUES('e3200000-0000-0000-0000-000000000001',current_date+4,540,720,'maintenance',
       'a3200000-0000-0000-0000-000000000002','继续上次的巡检','陈工');

\echo '--- 让上次上门的人补填剩余工作 ---'
INSERT INTO daily_report(id,staff_id,report_date,submitted_at)
VALUES('d3200000-0000-0000-0000-000000000001','e3200000-0000-0000-0000-000000000002',
       current_date-10,now());
\echo '--- ★应拦：上报分段不写「今天做了什么」---'
INSERT INTO daily_report_line(report_id,project_id,did_what)
VALUES('d3200000-0000-0000-0000-000000000001','a3200000-0000-0000-0000-000000000002','');
\echo '--- ★应拦：上报分段既没项目也没标公司级 ---'
INSERT INTO daily_report_line(report_id,did_what)
VALUES('d3200000-0000-0000-0000-000000000001','巡检了一遍');
\echo '--- 正常：写清做了什么 + ★还剩什么 ---'
INSERT INTO daily_report_line(report_id,project_id,sched_id,did_what,remaining)
VALUES('d3200000-0000-0000-0000-000000000001','a3200000-0000-0000-0000-000000000002',
       '50320000-0000-0000-0000-00000000000b',
       '巡检了一层与二层的面板，更换了客厅一只故障面板',
       '三层还没巡；主卧窗帘电机异响未处理');

\echo '--- 现在派得了工了，而且★剩余工作自动带出（不用手填）---'
INSERT INTO eng_schedule(id,staff_id,work_date,start_min,end_min,task_type,project_id,content,created_by)
VALUES('50320000-0000-0000-0000-000000000004','e3200000-0000-0000-0000-000000000001',
       current_date+4,540,720,'maintenance','a3200000-0000-0000-0000-000000000002',
       '继续上次的巡检','陈工');
SELECT staff_name, task_label, remaining_snap AS 剩余工作, remaining_src AS 来源
  FROM v_sched_week WHERE id='50320000-0000-0000-0000-000000000004';

\echo '--- ★SM 阶段不存在剩余工作（不带任何东西出来）---'
INSERT INTO eng_schedule(id,staff_id,work_date,start_min,end_min,task_type,project_id,content,created_by)
VALUES('50320000-0000-0000-0000-000000000005','e3200000-0000-0000-0000-000000000002',
       current_date+5,540,720,'sm','a3200000-0000-0000-0000-000000000002','SM3 检查布线','陈工');
SELECT task_label, COALESCE(remaining_snap,'（SM 阶段不存在剩余工作）') AS 剩余工作
  FROM v_sched_week WHERE id='50320000-0000-0000-0000-000000000005';

\echo ''
\echo '════════ ⑨ ★排班挂的出货单必须同项目 ════════'
INSERT INTO mat_req(id,req_no,project_id,job_kind,need_by,for_staff_id,raised_by)
VALUES('73200000-0000-0000-0000-000000000001','MR-T32-1','a3200000-0000-0000-0000-000000000001',
       'install',current_date+6,'e3200000-0000-0000-0000-000000000001','陈工');
\echo '--- ★应拦：排班是 KX-T32-02 的，出货单却是 KX-T32-01 的（货会发错工地）---'
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,project_id,
                         need_pickup,mat_req_id,created_by)
VALUES('e3200000-0000-0000-0000-000000000002',current_date+6,480,990,'install',
       'a3200000-0000-0000-0000-000000000002',true,'73200000-0000-0000-0000-000000000001','陈工');
\echo '--- 正常：同一个项目，勾「去仓库办提货」---'
INSERT INTO eng_schedule(id,staff_id,work_date,start_min,end_min,task_type,project_id,
                         need_pickup,pickup_note,mat_req_id,created_by)
VALUES('50320000-0000-0000-0000-000000000006','e3200000-0000-0000-0000-000000000001',
       current_date+6,480,990,'install','a3200000-0000-0000-0000-000000000001',
       true,'首次进场，顺路把面板一次性拉走','73200000-0000-0000-0000-000000000001','陈工');
SELECT s.staff_name, s.need_pickup AS 去提货, m.req_no AS 出货单
  FROM v_sched_week s JOIN mat_req m ON m.id=s.mat_req_id
 WHERE s.id='50320000-0000-0000-0000-000000000006';

\echo ''
\echo '════════ ⑩ 任务类型：内建不可删 · 用过的删不掉 ════════'
\echo '--- ★应拦：删内建类型（工时与倒休的算法认的就是这几个）---'
DELETE FROM sched_task_type WHERE code='toil';
\echo '--- ★应拦：改内建类型的代码（算法是按代码认的）---'
UPDATE sched_task_type SET code='toil2' WHERE code='toil';
\echo '--- 自建一个类型（默认计工时 + 合理时长 4 小时）---'
INSERT INTO sched_task_type(code,label,sort_no) VALUES ('survey','现场勘查',7);
SELECT code, label, builtin AS 内建, counts_hours AS 计工时, std_minutes AS 合理时长
  FROM sched_task_type ORDER BY sort_no;
\echo '--- 没用过的自建类型可以删 ---'
DELETE FROM sched_task_type WHERE code='survey';
\echo '--- ★应拦：用过的自建类型删不掉 ---'
INSERT INTO sched_task_type(code,label,sort_no) VALUES ('survey','现场勘查',7);
INSERT INTO eng_schedule(staff_id,work_date,start_min,end_min,task_type,project_id,created_by)
VALUES('e3200000-0000-0000-0000-000000000002',current_date+7,540,660,'survey',
       'a3200000-0000-0000-0000-000000000001','陈工');
DELETE FROM sched_task_type WHERE code='survey';

\echo ''
\echo '════════ ⑪ ★合理时长偏差：只提示不拦 ════════'
--   现场千差万别，拦死了只会逼人乱填一个数糊弄过去
INSERT INTO eng_schedule(id,staff_id,work_date,start_min,end_min,task_type,project_id,content,created_by)
VALUES('50320000-0000-0000-0000-000000000007','e3200000-0000-0000-0000-000000000001',
       current_date+8,480,1185,'sm','a3200000-0000-0000-0000-000000000001','SM4 封板核对','陈工');
SELECT task_label, dur_label AS 时长, std_minutes AS 合理时长, dev_pct AS 偏差百分比,
       dev_hint AS 提示 FROM v_sched_week WHERE id='50320000-0000-0000-0000-000000000007';

\echo ''
\echo '════════ ⑫ 点人名看当天路线：A/B/C/D ════════'
SELECT staff_name, stop_no AS 站点, start_at AS 出发, task_label, addr_street, addr_suburb
  FROM v_sched_route WHERE work_date=current_date+1 AND staff_name='小陈' ORDER BY stop_no;

\echo ''
\echo '════════ ⑬ ★运维作废维护单 → 连带取消排班 ════════'
--   不连带的话，工程那边的人还照着排班去现场，到了才发现单子早作废了
INSERT INTO maintenance_case(id,project_id,title,report_channel,rd_skip_reason)
VALUES('c3200000-0000-0000-0000-000000000001','a3200000-0000-0000-0000-000000000002',
       '二楼走廊感应灯不亮','phone','客户描述明确，直接上门');
INSERT INTO eng_schedule(id,staff_id,work_date,start_min,end_min,task_type,project_id,ref_id,content,created_by)
VALUES('50320000-0000-0000-0000-000000000008','e3200000-0000-0000-0000-000000000002',
       current_date+9,600,720,'maintenance','a3200000-0000-0000-0000-000000000002',
       'c3200000-0000-0000-0000-000000000001','上门换感应器','陈工');
UPDATE maintenance_case SET status='void' WHERE id='c3200000-0000-0000-0000-000000000001';
SELECT staff_name, task_label, cancel_reason AS 取消原因
  FROM v_sched_week WHERE id='50320000-0000-0000-0000-000000000008';

\echo ''
\echo '════════ ⑭ 周五提醒：下周谁一条都没排 ════════'
SELECT name, task_n AS 下周任务数 FROM v_sched_next_week_gap ORDER BY name;

\echo ''
\echo '════════ ⑮ 断言复核：这一版新增的五条 ════════'
SELECT code, label, violations FROM fn_run_assertions()
 WHERE code LIKE 'INV-SCH-%' ORDER BY code;
