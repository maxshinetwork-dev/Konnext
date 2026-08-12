-- 33 部门授权：★最高管理者默认对别的部门只读（v0.39 · 用户 2026-08-10 提出）
--
-- 用户的原话点出的是这套系统最后一个结构性风险：
--   最高管理者是【唯一一个能写所有部门】的角色，所以他是唯一可能和别人撞车的人。
--   乐观锁的做法是「撞了才报错」，这一版改成【根本不让它撞】——
--   默认只能看，部门负责人点了「休假授权」才能动。
--
-- 顺带解决另一件事：出了问题说得清是谁动的。
--   「为什么这单是陈总改的？」——「小林 8/12 授权到 8/20，日志里有。」
--
-- ★划分是天然的，不手列清单：
--   表在 table_ownership 里【有部门归属】→ 管理员写它＝代那个部门干活 → 要授权
--   表【没有部门归属】（决策看板/账号权限/断言定义/登记表）→ 本职 → 照旧
-- 期望拦截：11 次
SET timezone='Australia/Sydney';
\set ON_ERROR_STOP off

\echo '════════ ① 造数：陈总（核心管理员）· 小林（售前负责人）· 王姐（财务负责人）════════'
INSERT INTO app_account(login_name,full_name,phone,email,tier,is_core_admin,active)
VALUES ('chen','陈总','+61400000001','admin@konnext.com.au',1,true,true);
INSERT INTO app_account(login_name,full_name,phone,tier,active,created_by)
VALUES ('lin','小林','+61400000002',2,true,(SELECT id FROM app_account WHERE is_core_admin)),
       ('wang','王姐','+61400000003',2,true,(SELECT id FROM app_account WHERE is_core_admin));
INSERT INTO account_department(account_id,department,is_head)
  SELECT id,'presales',true FROM app_account WHERE login_name='lin';
INSERT INTO account_department(account_id,department,is_head)
  SELECT id,'finance',true FROM app_account WHERE login_name='wang';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='konnext_app') THEN
    CREATE ROLE konnext_app NOLOGIN;
  END IF;
END $$;
GRANT konnext_app TO CURRENT_USER;
GRANT USAGE ON SCHEMA public TO konnext_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO konnext_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO konnext_app;
REVOKE ALL ON auth_otp FROM konnext_app;

SELECT id::text AS chen_id FROM app_account WHERE login_name='chen' \gset
SELECT id::text AS lin_id  FROM app_account WHERE login_name='lin'  \gset
SELECT id::text AS wang_id FROM app_account WHERE login_name='wang' \gset

\echo '--- project 这张表归谁写（下面所有测试的靶子）---'
SELECT table_name, write_dept FROM table_ownership WHERE table_name='project';

\echo ''
\echo '════════ ② ★没有授权时：管理员写不了别的部门 ════════'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'chen_id', true);
-- 对照组放在【应拦那条之前】—— 一旦 INSERT 被拦，事务就中止了，
-- 后面所有语句都会报「current transaction is aborted」，那是假拦截，会混进计数
\echo '--- 对照：他【看得见】售前的东西（只读完全不受影响）---'
SELECT count(*) AS 能读项目表 FROM project;
\echo '--- ★应拦：陈总建一个售前的项目（project 归 presales 写）---'
INSERT INTO project(code,build_stage) VALUES ('KX-T33-01','rough_in');
ROLLBACK;

\echo ''
\echo '════════ ③ 管理员的【本职操作】不受影响 ════════'
--   这些表在 table_ownership 里没有部门归属 —— 决策页那一摊，本来就是他的活
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'chen_id', true);
\echo '--- 正常：改断言定义（决策级，没有部门归属）---'
UPDATE assertion_def SET hint = hint WHERE code='INV-SEC-03';
SELECT count(*) AS 改动行数 FROM assertion_def WHERE code='INV-SEC-03';
\echo '--- 正常：改表归属登记（决策级）---'
UPDATE table_ownership SET note = note WHERE table_name='project';
\echo '--- 正常：加一个账号（账号与权限是决策页的事）---'
INSERT INTO app_account(login_name,full_name,phone,tier,active,created_by)
VALUES ('zhou','小周','+61400000009',2,true,:'chen_id');
SELECT login_name FROM app_account WHERE login_name='zhou';
ROLLBACK;

\echo ''
\echo '════════ ④ 部门负责人写自己的部门：照旧 ════════'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
\echo '--- 正常：小林建自己部门的项目 ---'
INSERT INTO project(code,build_stage) VALUES ('KX-T33-01','rough_in');
SELECT code FROM project WHERE code='KX-T33-01';
\echo '--- ★应拦：小林去写财务的表（payment_milestone 归 finance）---'
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due)
SELECT id,'contract','S1',10,50000 FROM project WHERE code='KX-T33-01';
ROLLBACK;

-- 用 owner 把项目建好，后面的测试都拿它当靶子
INSERT INTO project(id,code,build_stage) VALUES
 ('a3300000-0000-0000-0000-000000000001','KX-T33-01','rough_in');

\echo ''
\echo '════════ ⑤ 休假授权的门禁 ════════'
\echo '--- ★应拦：到期日填成昨天（填了等于没授权）---'
INSERT INTO dept_delegation(department,kind,granted_by,until_date)
VALUES ('presales','leave',:'lin_id',current_date-1);
\echo '--- ★应拦：授权到半年后（休假不会休三个月，多半是填错了年份）---'
INSERT INTO dept_delegation(department,kind,granted_by,until_date)
VALUES ('presales','leave',:'lin_id',current_date+180);
\echo '--- ★应拦：王姐（财务负责人）替售前点休假授权 ---'
INSERT INTO dept_delegation(department,kind,granted_by,until_date)
VALUES ('presales','leave',:'wang_id',current_date+7);
\echo '--- ★应拦：强制接管不写原因 ---'
INSERT INTO dept_delegation(department,kind,granted_by,until_date)
VALUES ('presales','takeover',:'chen_id',current_date+7);
\echo '--- ★应拦：小林（tier2）自己点强制接管 ---'
INSERT INTO dept_delegation(department,kind,granted_by,until_date,reason)
VALUES ('presales','takeover',:'lin_id',current_date+7,'我自己接管我自己的部门试试');

\echo ''
\echo '--- 正常：小林本人点休假授权，到下周 ---'
INSERT INTO dept_delegation(id,department,kind,granted_by,until_date)
VALUES ('de300000-0000-0000-0000-000000000001','presales','leave',:'lin_id',current_date+7);
SELECT dept_cn AS 部门, kind_cn AS 方式, granted_by_name AS 谁授权的,
       days_left AS 还剩几天, head_name AS 部门负责人
  FROM v_dept_delegation WHERE department='presales';

\echo '--- ★应拦：同一个部门再点一次（两条并存＝解除了一条还剩一条，人以为收回了实际没有）---'
INSERT INTO dept_delegation(department,kind,granted_by,until_date)
VALUES ('presales','leave',:'lin_id',current_date+3);

\echo ''
\echo '════════ ⑥ ★授权之后：管理员能写了 ════════'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'chen_id', true);
\echo '--- 正常：陈总现在能改售前的项目了 ---'
UPDATE project SET name='陈总代改的' WHERE code='KX-T33-01';
SELECT code, name AS 项目名 FROM project WHERE code='KX-T33-01';
\echo '--- ★但财务那边照旧写不了（授权是【按部门】给的，不是一次给全部）---'
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due)
VALUES ('a3300000-0000-0000-0000-000000000001','contract','S1',10,50000);
ROLLBACK;

\echo ''
\echo '════════ ⑦ 到期自动失效（不用手动收回）════════'
UPDATE dept_delegation SET until_date=current_date-1
 WHERE id='de300000-0000-0000-0000-000000000001';
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'chen_id', true);
\echo '--- ★应拦：授权过期了，陈总又写不了了 ---'
INSERT INTO project(code,build_stage) VALUES ('KX-T33-02','rough_in');
ROLLBACK;
\echo '--- 过期的不再出现在「现在谁管着哪个部门」里 ---'
SELECT count(*) AS 生效中的授权 FROM v_dept_delegation;

\echo ''
\echo '════════ ⑧ ★强制接管：写原因 + 自动通知本人 ════════'
--   这是联系不上部门负责人时的出口。不写原因＝事后无法复盘；
--   不通知本人＝偷偷摸摸接管 —— 缺一样，这个出口就变成后门
UPDATE dept_delegation SET revoked_at=now(), revoked_by=:'lin_id'
 WHERE id='de300000-0000-0000-0000-000000000001';
INSERT INTO dept_delegation(id,department,kind,granted_by,until_date,reason)
VALUES ('de300000-0000-0000-0000-000000000002','presales','takeover',:'chen_id',
        current_date+3,'小林突发急病住院，联系不上，客户签约今天必须出，我先接管三天');
SELECT dept_cn AS 部门, kind_cn AS 方式, left(reason,20) AS 原因,
       (notified_at IS NOT NULL) AS 已通知本人
  FROM v_dept_delegation WHERE department='presales';
\echo '--- 通知内容（短信发给部门负责人本人）---'
SELECT recipient AS 发给, left(body,58) AS 短信内容 FROM notification
 WHERE ref_kind='dept_delegation';

BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'chen_id', true);
\echo '--- 正常：接管期间陈总能写售前 ---'
INSERT INTO project(code,build_stage) VALUES ('KX-T33-03','rough_in');
SELECT code FROM project WHERE code='KX-T33-03';
ROLLBACK;

\echo ''
\echo '════════ ⑨ ★删除比修改更危险，同样要授权 ════════'
UPDATE dept_delegation SET revoked_at=now(), revoked_by=:'chen_id',
       revoke_note='小林出院回来了'
 WHERE id='de300000-0000-0000-0000-000000000002';
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'chen_id', true);
\echo '--- 授权已收回：删除影响 0 行（RLS 拦 DELETE 不报错，看行数）---'
DELETE FROM project WHERE code='KX-T33-01';
\echo '--- 期望：项目还在 ---'
SELECT code FROM project WHERE code='KX-T33-01';
ROLLBACK;

\echo ''
\echo '════════ ⑩ 授权记录只增不删（能删的授权记录等于没有记录）════════'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'chen_id', true);
\echo '--- 删除影响 0 行：dept_delegation 故意没有 DELETE 策略 ---'
DELETE FROM dept_delegation WHERE id='de300000-0000-0000-0000-000000000002';
ROLLBACK;
\echo '--- 期望：两条记录都还在（一条休假、一条接管，都已解除）---'
SELECT kind AS 方式, (revoked_at IS NOT NULL) AS 已解除,
       to_char(until_date,'MM-DD') AS 原定到期
  FROM dept_delegation ORDER BY granted_at;

\echo ''
\echo '════════ ⑪ ★v0.40：查漏 —— 「没登记归属」的表曾经是敞开的 ════════'
--   用户 2026-08-10 追问「是不是有遗漏」，全库扫出四处绕过了这道门：
--     work_log（打卡）· daily_report / daily_issue（每日上报）· eng_setting（各部门设置键）
--   ★根子上的错：v0.39 把「没登记部门归属」当成「决策级本职 → 放行」。方向反了 ——
--     没登记绝大多数时候是【忘了登记】，于是每张忘登记的业务表对管理员都是敞开的，还不报错。
\echo '--- 全库扫：有写策略却没登记归属的表（期望 0 行）---'
SELECT c.relname AS 没登记归属的表
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relkind='r'
   AND EXISTS(SELECT 1 FROM pg_policies p WHERE p.schemaname='public'
               AND p.tablename=c.relname AND p.cmd IN ('INSERT','UPDATE','ALL'))
   AND NOT EXISTS(SELECT 1 FROM table_ownership o WHERE o.table_name=c.relname);

BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'chen_id', true);
\echo '--- ★应拦：没授权时改打卡记录（work_log 归工程/运维，v0.39 时它是敞开的）---'
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkin_method)
VALUES('a3300000-0000-0000-0000-000000000001',
       (SELECT id FROM eng_staff LIMIT 1),'execution',now(),'gps');
ROLLBACK;

-- 造一个工程人员，好验「本部门照旧」
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at)
VALUES('e3300000-0000-0000-0000-000000000001','阿强','hourly',70,'2025-01-01');
INSERT INTO app_account(id,login_name,full_name,phone,tier,active,created_by)
VALUES('ac330000-0000-0000-0000-000000000001','gong','陈工','+61400000004',2,true,:'chen_id');
INSERT INTO account_department(account_id,department,is_head)
VALUES('ac330000-0000-0000-0000-000000000001','eng_mgmt',true);
SELECT 'ac330000-0000-0000-0000-000000000001' AS gong_id \gset

BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'gong_id', true);
\echo '--- 正常：工程负责人写自己部门的打卡记录 ---'
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkin_method)
VALUES('a3300000-0000-0000-0000-000000000001',
       'e3300000-0000-0000-0000-000000000001','execution',now(),'gps');
SELECT count(*) AS 打卡条数 FROM work_log;
ROLLBACK;

\echo ''
\echo '--- ★eng_setting 按【键】判，不按表判 ---'
--   一张表装六个部门的设置：财务 15 个键、运维 8 个、售前 7 个、库管 6 个、采购 5 个。
--   按表判的话，管理员改财务的 GST、运维的 SLA、库管的仓库地址统统不受约束
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'chen_id', true);
\echo '--- 改财务的 GST（影响 0 行 = 拦住了；RLS 拦 UPDATE 不报错，看行数）---'
UPDATE eng_setting SET value_num=15 WHERE key='gst_bank_pct';
\echo '--- 期望：还是 10 ---'
SELECT key, value_num AS 现在的值 FROM eng_setting WHERE key='gst_bank_pct';
\echo '--- 正常：改决策级的键（账号上限，无部门归属＝本职）---'
UPDATE eng_setting SET value_num=3 WHERE key='max_admin_accounts';
SELECT key, value_num AS 现在的值 FROM eng_setting WHERE key='max_admin_accounts';
ROLLBACK;

\echo '--- 财务授权之后，陈总就能改财务的键了 ---'
INSERT INTO dept_delegation(department,kind,granted_by,until_date)
VALUES ('finance','leave',:'wang_id',current_date+5);
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'chen_id', true);
UPDATE eng_setting SET value_num=15 WHERE key='gst_bank_pct';
SELECT key, value_num AS 授权后改成 FROM eng_setting WHERE key='gst_bank_pct';
\echo '--- ★但运维的键照旧改不了（授权是按部门给的）---'
UPDATE eng_setting SET value_num=99 WHERE key='mt_sla_p0';
SELECT key, value_num AS 运维的键没被改动 FROM eng_setting WHERE key='mt_sla_p0';
ROLLBACK;
UPDATE dept_delegation SET revoked_at=now(), revoked_by=:'wang_id' WHERE department='finance';

\echo ''
\echo '════════ ⑫ 断言复核 ════════'
SELECT code, label, violations FROM fn_run_assertions()
 WHERE code LIKE 'INV-DEL-%' ORDER BY code;
