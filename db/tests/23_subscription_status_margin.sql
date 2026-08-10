SET timezone='Australia/Sydney';
SET app.actor='运维-小周';
\set ON_ERROR_STOP off

-- 建核心管理员并登录，否则金额被遮罩（未登录按最低权限，这是正确行为）
INSERT INTO app_account(id,login_name,full_name,tier,is_core_admin,phone,email,phone_bound_at)
VALUES('a0000000-0000-0000-0000-000000000001','core','陈总',1,true,'0400000000','core@x.com',now());
SET app.account_id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('CNY',0.2100,'google');
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,cost_hourly_rate,phone,hired_at)
VALUES('e1111111-1111-1111-1111-111111111111','小陈','hourly',80,80,'0422000001','2025-01-01');

INSERT INTO material(id,code,category,protocol,internal_name,spec,supplier,purchase_class,reorder_point,price_cny,freight_aud,margin_pct,warranty_months)
VALUES('99990000-0000-0000-0000-000000000001','M0001','面板','knx','KNX四联面板','白','深圳','C1',20,320,18,0.45,24);

-- 项目A：已交付（可签订阅）
INSERT INTO project(id,code,name,build_stage,step6_signed_at,contract_price,handover_at,status,free_warranty_months,
  o1_name,o1_phone,addr_street,addr_suburb,addr_state)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','Cherrybrook 王宅','rough_in',
       now()-interval '300 days',500000,now()-interval '60 days','delivered',12,
       '王先生','0433111222','8 Franklin Rd','Cherrybrook','NSW');
-- 项目B：谈判失败
INSERT INTO project(id,code,name,build_stage,contract_price,o1_name,addr_street,addr_suburb,addr_state)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','KX-2026-0155','Epping 李宅','da',300000,'李先生',
       '7 Beecroft Rd','Epping','NSW');
-- 项目C：施工中断
INSERT INTO project(id,code,name,build_stage,step6_signed_at,contract_price,status,o1_name,
  addr_street,addr_suburb,addr_state)
VALUES('cccccccc-0000-0000-0000-00000000000c','KX-2026-0160','Ryde 张宅','structure',
       now()-interval '250 days',400000,'in_construction','张先生','31 Blaxland Rd','Ryde','NSW');

\echo ''
\echo '════════ ① 订阅：只能建在已交付项目上 ════════'
\echo '--- 未交付项目想签订阅 → 应拒 ---'
INSERT INTO subscription(project_id,tier,annual_fee) VALUES('cccccccc-0000-0000-0000-00000000000c',2,1200);
\echo '--- 已交付项目签第2档，年费 1200 → 通过 ---'
INSERT INTO subscription(project_id,tier,annual_fee,created_by)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a',2,1200,'运维-小周');
INSERT INTO project(id,code,name,build_stage,step6_signed_at,contract_price,handover_at,status,o1_name)
VALUES('eeeeeeee-0000-0000-0000-00000000000e','KX-2026-0180','Hornsby 陈宅','rough_in',
       now()-interval '200 days',350000,now()-interval '30 days','delivered','陈女士');
UPDATE project SET addr_street='22 Rosamond St', addr_suburb='Hornsby', addr_state='NSW'
 WHERE code='KX-2026-0180';
\echo '--- 第5档(不订阅)却填了年费 → 应拒 ---'
INSERT INTO subscription(project_id,tier,annual_fee) VALUES('eeeeeeee-0000-0000-0000-00000000000e',5,800);
\echo '--- 第5档正常(不订阅，无年费) → 通过 ---'
INSERT INTO subscription(project_id,tier,created_by) VALUES('eeeeeeee-0000-0000-0000-00000000000e',5,'运维-小周');
\echo '--- 1~4档不填年费 → 应拒 ---'
UPDATE subscription SET annual_fee=NULL WHERE tier=2;

\echo ''
\echo '════════ ② 订阅四色状态 ════════'
SELECT project_code, owner_name AS 业主, tier_cn AS 档位, annual_fee AS 年费,
       period_start AS 本期起, period_end AS 本期止, days_to_expiry AS 剩余天,
       sub_status_cn AS 状态, color_token AS 颜色 FROM v_subscription_status;
\echo '--- 改成 20 天后到期 → 应变黄「即将到期」---'
UPDATE subscription SET period_end=now()::date+20 WHERE tier=2;
SELECT project_code, sub_status_cn AS 状态, color_token AS 颜色, days_to_expiry AS 剩余天 FROM v_subscription_status;
\echo '--- 改成已过期 → 应变红「已逾期」---'
UPDATE subscription SET period_end=now()::date-5 WHERE tier=2;
SELECT project_code, sub_status_cn AS 状态, color_token AS 颜色 FROM v_subscription_status;
\echo '--- 退订 → 灰「已退订」，历史已收仍留 ---'
UPDATE subscription SET cancelled_at=now()::date, cancel_reason='业主自住转出租，不再需要' WHERE tier=2;
SELECT project_code, sub_status_cn AS 状态, color_token AS 颜色 FROM v_subscription_status;
UPDATE subscription SET cancelled_at=NULL, period_end=now()::date+300 WHERE tier=2;

\echo ''
\echo '════════ ③ 留标 与 已烂尾 的边界 ════════'
\echo '--- 项目B 未进收款阶段 → 可置留标 ---'
UPDATE project SET status='bid_lost' WHERE code='KX-2026-0155';
\echo '--- 项目C 已签约施工、未交付 → 可置已烂尾 ---'
UPDATE project SET status='stalled' WHERE code='KX-2026-0160';
\echo '--- 已交付项目想置已烂尾 → 应拒 ---'
UPDATE project SET status='stalled' WHERE code='KX-2026-0142';
\echo '--- 有已结清合同款的项目想置留标 → 应拒 ---'
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due,status,settle_reason)
VALUES('cccccccc-0000-0000-0000-00000000000c','contract','S1',10,40000,'settled','已收');
UPDATE project SET status='bid_lost' WHERE code='KX-2026-0160';
\echo '--- 未签约项目想置已烂尾 → 应拒 ---'
INSERT INTO project(id,code,name,build_stage,contract_price,addr_suburb,addr_state)
VALUES('dddddddd-0000-0000-0000-00000000000d','KX-2026-0170','Lane Cove 吴宅','da',100000,'Lane Cove','NSW');
UPDATE project SET status='stalled' WHERE code='KX-2026-0170';

\echo ''
\echo '════════ ④ 卡住天数 ════════'
UPDATE project SET status_since=now()-interval '80 days' WHERE code='KX-2026-0142';
UPDATE project SET status_since=now()-interval '10 days' WHERE code='KX-2026-0160';
SELECT code, status_cn AS 状态, days_in_status AS 停留天数, threshold_days AS 阈值,
       is_stalled AS 卡住了, days_overdue AS 超出天数 FROM v_project_stall ORDER BY code;
\echo '--- 状态一变，停留天数自动归零 ---'
UPDATE project SET status='maintaining' WHERE code='KX-2026-0142';
SELECT code, status_cn AS 状态, days_in_status AS 停留天数, threshold_days AS 阈值 FROM v_project_stall WHERE code='KX-2026-0142';

\echo ''
\echo '════════ ⑤ 利润率：合同额−材料−人工+维护，★不含订阅 ════════'
-- 铺成本：出库物料 + 工时
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a',1,now()-interval '280 days'),
 ('aaaaaaaa-0000-0000-0000-00000000000a',2,now()-interval '270 days'),
 ('aaaaaaaa-0000-0000-0000-00000000000a',3,now()-interval '260 days');
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,amount_due,status,settle_reason)
VALUES('f0000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-00000000000a','contract','S2',40,200000,'settled','已收');
INSERT INTO purchase_order(id,po_no,source_type,supplier,ordered_at,status)
VALUES('dddd0000-0000-0000-0000-000000000001','PO-1','bulk','深圳',now()-interval '250 days','ordered');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud)
VALUES('dddd0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',2000,2000,85.20);
INSERT INTO stock_out(id,out_no,project_id,receiver_staff_id)
VALUES('eeee0000-0000-0000-0000-000000000001','OUT-1','aaaaaaaa-0000-0000-0000-00000000000a','e1111111-1111-1111-1111-111111111111');
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud)
VALUES('eeee0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',1760,85.20);
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method)
SELECT 'aaaaaaaa-0000-0000-0000-00000000000a','e1111111-1111-1111-1111-111111111111','execution',
       (now()-interval '200 days')::date+(d||' days')::interval+interval '8 hours',
       (now()-interval '200 days')::date+(d||' days')::interval+interval '17 hours','gps'
FROM generate_series(1,80) d;
-- 维护：收入 5000 / 成本 1800
-- v0.37：报修渠道无条件必填 + 上门前要有排查结论，造数据一并带上
INSERT INTO maintenance_case(id,project_id,title,labor_cost,material_cost,fault_cause,status,
                             report_channel,rd_conclusion,rd_by,rd_at)
VALUES('cc000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-00000000000a','面板更换',1200,600,'product_defect','paid_closed',
       'phone','远程排查确认面板固件损坏，需更换','研发-小赵',now());
INSERT INTO maintenance_job(project_id,case_id,staff_id,scheduled_date,fault_cause,service_summary,client_sign_url,client_sign_name,client_sign_at,completed_at)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','cc000000-0000-0000-0000-000000000001','e1111111-1111-1111-1111-111111111111',current_date,'product_defect','换面板','https://x/s.jpg','王先生',now(),now());
INSERT INTO payment_milestone(id,project_id,kind,case_id,amount_due,status,settle_reason)
VALUES('f0000000-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-00000000000a','maintenance','cc000000-0000-0000-0000-000000000001',5000,'settled','已收');
INSERT INTO payment_receipt(milestone_id,method,amount,received_at) VALUES('f0000000-0000-0000-0000-000000000009','bank',5000,now());
-- ★订阅收款 1200：不该进利润率
INSERT INTO payment_milestone(id,project_id,kind,amount_due,status,settle_reason)
VALUES('f0000000-0000-0000-0000-00000000000b','aaaaaaaa-0000-0000-0000-00000000000a','subscription',1200,'settled','订阅年费已收');
INSERT INTO payment_receipt(milestone_id,method,amount,received_at) VALUES('f0000000-0000-0000-0000-00000000000b','bank',1200,now());

SELECT code, contract_value AS 合同额, material_cost AS 材料, labor_cost AS 人工,
       maint_revenue AS 维护收入, maint_cost AS 维护成本, maint_net AS 维护净额,
       profit AS 利润, margin_pct AS 利润率, margin_band AS 配色档,
       maint_provisional AS 维护含预估 FROM v_project_margin WHERE code='KX-2026-0142';
\echo '--- 订阅已收 1200，验证它没被算进利润 ---'
SELECT kind, amount_due AS 应收 FROM payment_milestone WHERE project_id='aaaaaaaa-0000-0000-0000-00000000000a' ORDER BY kind;

\echo ''
\echo '════════ ⑥ 订阅汇总（公司级） ════════'
SELECT tier_cn AS 档位, sub_count AS 订阅数, active_count AS 生效中, overdue_count AS 逾期,
       annualised_fee AS 年化, monthly_run_rate AS 月均, paid_total_all_time AS 累计已收
FROM v_subscription_rollup ORDER BY tier;

\echo ''
\echo '════════ ⑦ 风险看板 ════════'
SELECT code, status_cn AS 状态, risk_type AS 风险类型, days_in_status AS 停留天数,
       subscription_status AS 订阅状态, subscription_color AS 订阅色, margin_pct AS 利润率, margin_band AS 档
FROM v_risk_board ORDER BY code;

UPDATE project SET eng_margin_locked=55.872, eng_margin_locked_at=handover_at WHERE handover_at IS NOT NULL;
\echo ''
\echo '════════ ⑧ 断言 ════════'
SELECT * FROM fn_assertion_summary();
SELECT code, severity, label, status FROM fn_run_assertions() WHERE violations<>0;

\echo ''
\echo '════════ ⑨ 项目总目录：每个部门都用这一个（编号+地址必带） ════════'
SELECT code AS 编号, addr_full AS 地址, owner_name AS 业主, status_cn AS 状态,
       days_in_status AS 停留, is_stalled AS 卡住, contract_price AS 合同额,
       margin_pct AS 利润率, subscription_status AS 订阅, pending_handoffs AS 待办
FROM v_project_directory ORDER BY code;

\echo ''
\echo '════════ ⑩ 换成库管登录：项目与地址照样看得见，金额全遮 ════════'
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM app_account WHERE login_name='stock') THEN
    INSERT INTO app_account(id,login_name,full_name,tier,phone,email,created_by)
    VALUES('b0000000-0000-0000-0000-000000000003','stock','老张',2,'0411000003','s@x.com',
           'a0000000-0000-0000-0000-000000000001');
    INSERT INTO account_department(account_id,department) VALUES
     ('b0000000-0000-0000-0000-000000000003','procurement'),
     ('b0000000-0000-0000-0000-000000000003','warehouse');
  END IF;
END $$;
SET app.account_id = 'b0000000-0000-0000-0000-000000000003';
SELECT code AS 编号, addr_full AS 地址, owner_name AS 业主, status_cn AS 状态,
       contract_price AS 合同额, margin_pct AS 利润率 FROM v_project_directory ORDER BY code LIMIT 3;

\echo ''
\echo '════════ ⑪ 任意视图都带得出编号与地址 ════════'
SET app.account_id = 'a0000000-0000-0000-0000-000000000001';
SELECT pj_code AS 编号, pj_suburb AS Suburb, display_name AS 物料, qty_unreturned AS 未退
FROM v_material_custody LIMIT 3;
SELECT pj_code AS 编号, pj_addr AS 地址, event_label AS 交接事件, to_dept_cn AS 通知谁
FROM v_pending_handoff LIMIT 3;
