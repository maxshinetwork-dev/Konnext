-- 28 并发与陈旧覆盖（v0.35）：乐观锁全库推广
-- 场景（用户 2026-08-03 提）：管理员在办公室电脑开着页面没关，回家用另一台改了东西，
--   同事碰了办公室那台 —— 那台屏幕上是旧数据。纯阅读没事，怕的是「在旧页面上点一下」：
--   旧快照覆盖新数据，不报错、只是数字悄悄错了。乐观锁就是把这种覆盖变成<报错>。
-- 期望拦截：3 次（陈旧覆盖 ×2 · 版本号乱填 ×1）
\echo '════════ ① 造数：一个项目 + 一份物料 ════════'
INSERT INTO project(code,name,addr_suburb,addr_state,build_stage,created_at)
VALUES ('KX-T28-01','测试并发宅','Ryde','NSW','structure',now()-interval '30 days');
INSERT INTO material(code,internal_name,category,protocol,purchase_class,price_aud,warranty_months)
VALUES ('T28-M-1','测试面板','panel','knx','C2',120,24);

\echo '--- 新建的行 version 应为 1 ---'
SELECT code, version FROM project WHERE code='KX-T28-01';

\echo '════════ ② 正常：带对版本号改 → 成功，version 自增 ════════'
SET app.expected_version = '1';
UPDATE project SET name='测试并发宅（改名一次）' WHERE code='KX-T28-01';
RESET app.expected_version;
SELECT code, name, version FROM project WHERE code='KX-T28-01';

\echo '════════ ③ ★陈旧覆盖：同事拿着第 1 版的旧页面又点了保存 → 应拦 ════════'
SET app.expected_version = '1';
\echo '--- 期望第 1 版、实际已是第 2 版 → 应拦（不许静默覆盖） ---'
UPDATE project SET name='被旧页面覆盖掉的名字' WHERE code='KX-T28-01';
RESET app.expected_version;
\echo '--- 确认名字没被改坏 ---'
SELECT code, name, version FROM project WHERE code='KX-T28-01';

\echo '════════ ④ 刷新后拿最新版本再改 → 应成功 ════════'
SET app.expected_version = '2';
UPDATE project SET name='刷新后正常改名' WHERE code='KX-T28-01';
RESET app.expected_version;
SELECT code, name, version FROM project WHERE code='KX-T28-01';

\echo '════════ ⑤ 不设 expected_version（系统内部更新/后台脚本）→ 放行 ════════'
UPDATE project SET addr_suburb='Epping' WHERE code='KX-T28-01';
SELECT code, addr_suburb, version FROM project WHERE code='KX-T28-01';

\echo '════════ ⑥ 不只 project：随便另一张可改业务表也一样挡 ════════'
SET app.expected_version = '1';
UPDATE material SET internal_name='测试面板（第二版）' WHERE code='T28-M-1';
RESET app.expected_version;
SET app.expected_version = '1';
\echo '--- material 拿旧版本再改 → 应拦 ---'
UPDATE material SET internal_name='被旧页面覆盖的物料名' WHERE code='T28-M-1';
RESET app.expected_version;
SELECT code, internal_name, version FROM material WHERE code='T28-M-1';

\echo '════════ ⑦ 版本号是系统算的，不许手填 ════════'
SET app.expected_version = '4';
\echo '--- 想把 version 直接写成 99（绕过并发检查）→ 触发器照样按 OLD.version+1 覆盖回去 ---'
UPDATE project SET version = 99 WHERE code='KX-T28-01';
RESET app.expected_version;
\echo '--- 应为 5（不是 99）---'
SELECT code, version FROM project WHERE code='KX-T28-01';

\echo '════════ ⑧ 版本号乱填 → 应拦 ════════'
SET app.expected_version = 'abc';
\echo '--- expected_version 不是数字 → 应拦（宁可报错，不要静默放过） ---'
UPDATE project SET name='版本号乱填也想改' WHERE code='KX-T28-01';
RESET app.expected_version;

\echo '════════ ⑨ 断言：可改的表必须挂乐观锁 ════════'
SELECT code, status FROM fn_run_assertions() WHERE code='INV-CC-01';

\echo '════════ ⑩ 覆盖率：有 UPDATE 策略的表全都挂上了 ════════'
SELECT count(*) AS 有更新策略的表,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM pg_trigger tg WHERE tg.tgrelid=c.oid AND NOT tg.tgisinternal
            AND tg.tgname = c.relname || '_optlock')) AS 已挂锁
  FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='public' AND c.relkind='r'
   AND EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname='public'
                AND p.tablename=c.relname AND p.cmd IN ('UPDATE','ALL'));

\echo '════════ ⑪ 清理 ════════'
DELETE FROM material WHERE code='T28-M-1';
DELETE FROM project WHERE code='KX-T28-01';
