SET timezone='Australia/Sydney';
\set ON_ERROR_STOP off

-- 铺账号与数据（superuser 身份，RLS 不作用于 superuser，所以先铺好）
INSERT INTO app_account(id,login_name,full_name,tier,is_core_admin,phone,email,phone_bound_at)
VALUES('a0000000-0000-0000-0000-000000000001','core','陈总',1,true,'0400000000','core@x.com',now());
INSERT INTO app_account(id,login_name,full_name,tier,phone,email,created_by) VALUES
 ('b0000000-0000-0000-0000-000000000001','presales','小林(售前)',2,'0411000001','p@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000003','stock','老张(库管)',2,'0411000003','s@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000004','finance','王姐(财务)',2,'0411000004','f@x.com','a0000000-0000-0000-0000-000000000001');
INSERT INTO account_department(account_id,department) VALUES
 ('b0000000-0000-0000-0000-000000000001','presales'),
 ('b0000000-0000-0000-0000-000000000003','warehouse'),
 ('b0000000-0000-0000-0000-000000000004','finance');
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,cost_hourly_rate,hired_at)
VALUES('e1111111-1111-1111-1111-111111111111','小陈','hourly',80,80,'2025-01-01');
INSERT INTO app_account(id,login_name,full_name,tier,phone,staff_id,backend_access,created_by)
VALUES('c0000000-0000-0000-0000-000000000001','w1','小陈(施工)',3,'0422000001','e1111111-1111-1111-1111-111111111111',false,'a0000000-0000-0000-0000-000000000001');
INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('CNY',0.2100,'google');
INSERT INTO material(code,category,protocol,internal_name,spec,supplier,purchase_class,reorder_point,price_cny,freight_aud,margin_pct,warranty_months)
VALUES('M0001','面板','knx','KNX四联面板','白','深圳某某','C1',20,320,18,0.45,24);
INSERT INTO project(id,code,name,build_stage,step6_signed_at,contract_price,planned_labor_hours)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','王宅','rough_in',now(),500000,400);
UPDATE project SET eng_margin_locked=55.872 WHERE code='KX-2026-0142';

-- 建一个测试用户，分别赋不同部门角色
-- ★ 真实部署方式：应用只用一个数据库用户，登录后 SET app.account_id 指明是谁
--   不给这个用户任何 konnext_* 角色，权限完全由账号+部门表决定
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='app_user') THEN CREATE ROLE app_user LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO app_user;

\echo ''
\echo '════════ ① 权限矩阵（管理员看的全景，节选） ════════'
SELECT table_name, matrix FROM v_permission_matrix
 WHERE table_name IN ('project','payment_milestone','stock_out','material','site_meeting','daily_payroll');

\echo ''
\echo '════════ ② 库管登录：读全部 ✓，写本部门 ✓，写别人的 ✗ ════════'
SET ROLE app_user;
SET app.account_id = 'b0000000-0000-0000-0000-000000000003';   -- 老张(库管)
\echo '--- 库管能看到项目（全流程可见） ---'
SELECT code, name, status FROM project;
\echo '--- 库管能看到财务的付款记录（下游查上游） ---'
SELECT count(*) AS 能看到几条付款节点 FROM payment_milestone;
\echo '--- 库管想写付款节点 → 应拒 ---'
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','contract','S1',10,50000);
\echo '--- 库管想改项目签约价 → 应拒(RLS 过滤掉这行，改不动) ---'
UPDATE project SET contract_price=999999 WHERE code='KX-2026-0142';
SELECT contract_price AS 签约价没被改动 FROM v_project_masked;

\echo ''
\echo '════════ ③ 敏感数字：库管看不到薪酬 / 利润率 / 采购价 ════════'
SELECT name, pay_type, pay_hourly_rate AS 时薪, cost_hourly_rate AS 成本时薪, salary_visible AS 薪酬可见
FROM v_staff_masked;
SELECT code, contract_price AS 签约价, eng_margin_locked AS 工程利润率, margin_visible AS 利润可见 FROM v_project_masked;
SELECT display_name AS 物料, reorder_point AS 红线, price_cny AS 采购价CNY, margin_pct AS 毛利率, price_visible AS 价格可见
FROM v_material_masked;

\echo ''
\echo '════════ ④ 换成财务登录：薪酬和利润率都看得到 ════════'
SET app.account_id = 'b0000000-0000-0000-0000-000000000004';
SELECT name, pay_hourly_rate AS 时薪, cost_hourly_rate AS 成本时薪, salary_visible AS 薪酬可见 FROM v_staff_masked;
SELECT code, contract_price AS 签约价, eng_margin_locked AS 工程利润率, margin_visible AS 利润可见 FROM v_project_masked;
\echo '--- 但财务仍看不到采购价与毛利率 ---'
SELECT display_name AS 物料, price_cny AS 采购价, margin_pct AS 毛利率, price_visible AS 价格可见 FROM v_material_masked;
\echo '--- 财务能写付款节点 ✓ ---'
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','contract','S2',40,200000);
SELECT stage, amount_due FROM payment_milestone ORDER BY stage;

\echo ''
\echo '════════ ⑤ 施工人员登录：连项目都读不到（只上报） ════════'
SET app.account_id = 'c0000000-0000-0000-0000-000000000001';
SELECT count(*) AS 施工人员能看到几个项目 FROM project;
SELECT count(*) AS 能看到几条付款 FROM payment_milestone;
\echo '--- 但自己的工时能写 ---'
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','e1111111-1111-1111-1111-111111111111','execution',
       now()-interval '8 hours',now(),'gps');
SELECT count(*) AS 自己的工时 FROM work_log;
\echo '--- 想替别人写工时 → 应拒 ---'
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','e9999999-9999-9999-9999-999999999999','execution',
       now()-interval '8 hours',now(),'gps');

\echo ''
\echo '════════ ⑥ 我能写哪些表（界面据此显示按钮） ════════'
SET app.account_id = 'b0000000-0000-0000-0000-000000000003';
SELECT table_name, can_write FROM v_my_permissions
 WHERE table_name IN ('stock_out','stocktake','payment_milestone','site_meeting','material') ORDER BY table_name;

\echo ''
\echo '════════ ⑦ 管理员：全读全写 ════════'
SET app.account_id = 'a0000000-0000-0000-0000-000000000001';
SELECT name, pay_hourly_rate AS 时薪, salary_visible FROM v_staff_masked;
SELECT display_name AS 物料, price_cny AS 采购价, margin_pct AS 毛利率, price_visible FROM v_material_masked;


-- ===== 接续：金额遮罩与视图 RLS =====
\echo '════════ 视图是否全部按查询者权限执行 ════════'
SELECT count(*) AS 未开security_invoker的视图 FROM pg_class
 WHERE relkind='v' AND relnamespace='public'::regnamespace
   AND (reloptions IS NULL OR NOT ('security_invoker=true' = ANY(reloptions)));

\echo ''
\echo '════════ 库管登录：业务流水可见，数字全遮 ════════'
SET app.account_id = 'b0000000-0000-0000-0000-000000000003';
\echo '--- 业务流水：看得见 ---'
SELECT code, name, status FROM project;
SELECT display_name AS 物料, reorder_point AS 红线, qty_on_hand AS 库存 FROM v_material_stock;
\echo '--- 数字：全部遮住 ---'
SELECT code, s4_base AS S4基数, variation_add AS 变更增, s4_payable AS S4应收 FROM v_s4_settlement;
SELECT display_name AS 物料, cost_total_aud AS 采购成本, sell_price_aud AS 售卖价 FROM v_material_price;
SELECT stage, amount_due AS 应收 FROM v_milestone_settlement;
SELECT code, contract_price AS 签约价, eng_margin_locked AS 工程利润率 FROM v_project_masked;
SELECT project_id IS NOT NULL AS 有项目, actual_hours AS 工时, labor_cost AS 人工成本 FROM v_project_labor_cost LIMIT 1;

\echo ''
\echo '════════ 库管能看的钱：库存成本（本职工作需要） ════════'
SELECT bucket_cn AS 类别, visible_to AS 谁能看 FROM money_visibility ORDER BY bucket;

\echo ''
\echo '════════ 财务登录：合同金额+成本+薪酬可见，采购价仍遮 ════════'
SET app.account_id = 'b0000000-0000-0000-0000-000000000004';
SELECT code, s4_base AS S4基数, s4_payable AS S4应收 FROM v_s4_settlement;
SELECT stage, amount_due AS 应收 FROM v_milestone_settlement;
SELECT code, contract_price AS 签约价, eng_margin_locked AS 工程利润率 FROM v_project_masked;
SELECT display_name AS 物料, cost_total_aud AS 采购成本没给看, sell_price_aud AS 售卖价可看 FROM v_material_price;

\echo ''
\echo '════════ 售前登录：只看合同金额，成本与采购价都遮 ════════'
SET app.account_id = 'b0000000-0000-0000-0000-000000000001';
SELECT code, s4_base AS S4基数可看, s4_payable AS S4应收可看 FROM v_s4_settlement;
SELECT code, contract_price AS 签约价, eng_margin_locked AS 工程利润率没给看 FROM v_project_masked;
SELECT name, pay_hourly_rate AS 时薪没给看 FROM v_staff_masked;

\echo ''
\echo '════════ 每个带钱的视图由谁看守（自查表） ════════'
SELECT view_name, guarded_by FROM v_money_guard_map LIMIT 12;
