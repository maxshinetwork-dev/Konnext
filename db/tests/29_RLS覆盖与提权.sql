-- 29 RLS 覆盖与提权（v0.36）
-- 背景：2026-08-04 全面回归查出 20 张表一条 RLS 策略都没有，而降权角色 konnext_app
--   对它们有完整 DML。最要紧三张：auth_otp（能读别人的验证码＝可被盗号）·
--   audit_log（留痕可被改删）· account_department（改部门＝提权）。
--   以前一路全绿，是因为 INV-SEC-07 只手列了 10 张「关键表」——
--   「能自动扫全库的地方绝不手列清单：手列一定会漏且不报错」。
-- 这个文件把当时手工验证过的那几刀固化下来，防回归。
-- 期望拦截：7 次（读验证码 ×1 · 提权 ×1 · 塞后门自检 ×1 · 改汇率 ×1 · 改表归属/金额口径/停留阈值 ×3）
--   注：RLS 拦 SELECT/DELETE/UPDATE 时是「看不见 / 影响 0 行」，不报错；
--   拦 INSERT 与带 WITH CHECK 的 UPDATE 时才报 ERROR。所以下面既数 ERROR，也用
--   \echo 把「应该是 0 行」的结果打出来人眼可核。

\echo '════════ ① 造数：一个核心管理员 + 一个售前负责人（tier2）════════'
INSERT INTO app_account(login_name,full_name,phone,email,tier,is_core_admin,active)
VALUES ('chen','陈总','+61400000001','admin@konnext.com.au',1,true,true);
INSERT INTO app_account(login_name,full_name,phone,tier,active,created_by)
VALUES ('lin','小林','+61400000002',2,true,(SELECT id FROM app_account WHERE is_core_admin));
INSERT INTO account_department(account_id,department)
  SELECT id,'presales' FROM app_account WHERE login_name='lin';

-- 一条别人的验证码 + 一条留痕，用来验证"看不看得到 / 删不删得掉"
INSERT INTO auth_otp(account_id,channel,sent_to,code_hash,expires_at)
  SELECT id,'sms','+61400000001','deadbeef',now()+interval '10 min'
    FROM app_account WHERE is_core_admin;
INSERT INTO audit_log(actor,action,table_name) VALUES ('陈总','测试留痕','project');

\echo '════════ ② 全库 RLS 覆盖：不许再有「一条策略都没有」的表 ════════'
\echo '--- 期望 0 行 ---'
SELECT c.relname AS 没开RLS的表
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='public' AND c.relkind='r' AND NOT c.relrowsecurity
 ORDER BY 1;

\echo '════════ ③ 建降权角色（上线时由 db/deploy/10_app_role.sql 跑）════════'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='konnext_app') THEN
    CREATE ROLE konnext_app NOLOGIN;
  END IF;
END $$;
GRANT konnext_app TO CURRENT_USER;
GRANT USAGE ON SCHEMA public TO konnext_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO konnext_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO konnext_app;
-- ★上线脚本里这一句是关键：验证码表连表级权限都收回
REVOKE ALL ON auth_otp FROM konnext_app;

\echo '════════ ④ 以「售前负责人」的身份，逐个试探 ════════'
-- 先以 owner 身份把 id 取出来：还没注入身份就查 app_account 会被 RLS 挡住
SELECT id::text AS lin_id FROM app_account WHERE login_name='lin' \gset

\echo '--- 对照组：本职该能做的（读断言定义）应当正常 ---'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
\echo '--- 期望 77 ---'
SELECT count(*) AS 能读断言定义 FROM assertion_def;
ROLLBACK;

\echo '--- ★应拦：读别人的验证码（库里明明有 1 条）---'
\echo '    这里是表级 REVOKE 先发作 → permission denied，比行级更硬'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
SELECT count(*) AS 看得到几条验证码 FROM auth_otp;
ROLLBACK;

\echo '--- 下面这几刀 RLS 是「静默挡住」：不报错，但影响 0 行 ---'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
\echo '--- ★期望 DELETE 0：删不掉审计日志（库里有 1 条）---'
DELETE FROM audit_log;
\echo '--- ★期望 UPDATE 0：改不了系统自检 ---'
UPDATE assertion_def SET query='SELECT 1 WHERE false' WHERE code='INV-SEC-09';
\echo '--- ★期望 DELETE 0：删不掉系统自检 ---'
DELETE FROM assertion_def;
\echo '--- ★期望 UPDATE 0：改不了自己的部门归属 ---'
UPDATE account_department SET department='finance' WHERE account_id = :'lin_id'::uuid;
ROLLBACK;

\echo '--- 复核：上面几刀一条都没得手 ---'
SELECT (SELECT count(*) FROM audit_log)      AS 审计日志还在,
       (SELECT count(*) FROM assertion_def)  AS 自检还在,
       (SELECT department FROM account_department
         WHERE account_id = :'lin_id'::uuid) AS 部门没被改;

\echo '════════ ⑤ 提权与越权写：这几刀应当直接报错 ════════'

\echo '--- ★应拦：给自己加一个财务部门（提权）---'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
INSERT INTO account_department(account_id,department) VALUES (:'lin_id'::uuid,'finance');
ROLLBACK;

\echo '--- ★应拦：新增一条系统自检（塞进自己的后门）---'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
INSERT INTO assertion_def(code,label,severity,query)
VALUES ('BACKDOOR','假断言','medium','SELECT 1 WHERE false');
ROLLBACK;

\echo '--- ★应拦：售前不是采购/财务，不能写汇率（汇率错了成本全错还不报错）---'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('USD',99,'manual');
ROLLBACK;

\echo '--- ★应拦：售前不能改表的写入归属（改了就能给自己开权限）---'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
INSERT INTO table_ownership(table_name,write_dept) VALUES ('后门表',ARRAY['presales']);
ROLLBACK;

\echo '--- ★应拦：售前不能改「谁能看哪类金额」的口径表 ---'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
INSERT INTO money_visibility(bucket,bucket_cn,guard_fn,visible_to,examples)
VALUES ('backdoor','后门','fn_true','所有人','—');
ROLLBACK;

\echo '--- ★应拦：售前不能改停留阈值（阈值一改，卡点表就永远不报警）---'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
INSERT INTO status_stall_threshold(status,stall_days) VALUES ('后门状态',9999);
ROLLBACK;

\echo '════════ ⑥ 该放行的必须放行：写审计留痕（每个动作都要留痕）════════'
BEGIN;
SET LOCAL ROLE konnext_app;
SELECT set_config('app.account_id', :'lin_id', true);
\echo '--- 期望 INSERT 1 ---'
INSERT INTO audit_log(actor,action,table_name) VALUES ('小林','正常留痕','project');
ROLLBACK;

\echo '════════ ⑦ 断言复核：INV-SEC-09 必须绿 ════════'
SELECT code, violations, status FROM fn_run_assertions() WHERE code IN ('INV-SEC-07','INV-SEC-09');
