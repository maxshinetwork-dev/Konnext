SET timezone='Australia/Sydney';
\set ON_ERROR_STOP off
INSERT INTO app_account(id,login_name,full_name,tier,is_core_admin,phone,email,phone_bound_at)
VALUES('a0000000-0000-0000-0000-000000000001','core','陈总',1,true,'0400000000','core@x.com',now());
INSERT INTO app_account(id,login_name,full_name,tier,phone,email,created_by)
VALUES('b0000000-0000-0000-0000-000000000004','finance','王姐',2,'0411000004','f@x.com','a0000000-0000-0000-0000-000000000001');
INSERT INTO account_department(account_id,department) VALUES('b0000000-0000-0000-0000-000000000004','finance');
SET app.account_id='a0000000-0000-0000-0000-000000000001';
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,cost_hourly_rate,phone,hired_at) VALUES
 ('e1111111-1111-1111-1111-111111111111','小陈','hourly',80,80,'0422000001','2025-01-01');
INSERT INTO app_account(id,login_name,full_name,tier,phone,staff_id,backend_access,created_by)
VALUES('c0000000-0000-0000-0000-000000000001','w1','小陈',3,'0422000001','e1111111-1111-1111-1111-111111111111',false,'a0000000-0000-0000-0000-000000000001');
INSERT INTO project(id,code,name,build_stage,step6_signed_at,contract_price,o1_name,addr_street,addr_suburb,addr_state)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','Cherrybrook 王宅','rough_in',now(),500000,
       '王先生','8 Franklin Rd','Cherrybrook','NSW');

\echo ''
\echo '════ ① 通知：没项目又不标 scope → 应拒 ════'
INSERT INTO notification(ref_kind,channel,recipient,subject,body)
VALUES('test','email','x@y.com','测试','没有项目也没标公司级');
\echo '--- 明确标公司级 → 通过 ---'
INSERT INTO notification(ref_kind,channel,recipient,subject,body,scope,scope_reason)
VALUES('test','email','x@y.com','库存红线预警','面板低于红线','company','库存预警不属于单个项目');
\echo '--- 挂项目 → 自动标 project ---'
INSERT INTO notification(project_id,ref_kind,channel,recipient,subject,body)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','test','email','x@y.com','变更知会','客厅加两个开关');
SELECT subject AS 主题, scope, COALESCE(scope_reason,'—') AS 例外原因 FROM notification ORDER BY subject;

\echo ''
\echo '════ ② 报销（新模块）════'
\echo '--- 不填项目也不标 scope → 应拒 ---'
INSERT INTO expense_claim(claim_no,claimant_staff_id,category,amount_aud)
VALUES('EXP-001','e1111111-1111-1111-1111-111111111111','parking',18.50);
\echo '--- 落到项目 → 通过 ---'
INSERT INTO expense_claim(claim_no,claimant_staff_id,project_id,category,amount_aud,gst_amount,receipt_url,description)
VALUES('EXP-001','e1111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-00000000000a',
       'parking',18.50,1.68,'https://x/r1.jpg','Cherrybrook 现场停车');
\echo '--- 公司级报销必须填原因 → 不填应拒 ---'
INSERT INTO expense_claim(claim_no,claimant_staff_id,category,amount_aud,scope)
VALUES('EXP-002','e1111111-1111-1111-1111-111111111111','tool',260.00,'company');
\echo '--- 填了原因 → 通过 ---'
INSERT INTO expense_claim(claim_no,claimant_staff_id,category,amount_aud,scope,scope_reason,receipt_url)
VALUES('EXP-002','e1111111-1111-1111-1111-111111111111','tool',260.00,'company',
       '公司通用工具采购，多项目共用','https://x/r2.jpg');
\echo '--- 提交但没收据 → 应拒 ---'
INSERT INTO expense_claim(claim_no,claimant_staff_id,project_id,category,amount_aud,status)
VALUES('EXP-003','e1111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-00000000000a',
       'fuel',45.00,'submitted');
\echo '--- 提交 EXP-001 ---'
UPDATE expense_claim SET status='submitted' WHERE claim_no='EXP-001';
\echo '--- 自己批自己 → 应拒 ---'
UPDATE expense_claim SET status='approved', approved_by='c0000000-0000-0000-0000-000000000001'
 WHERE claim_no='EXP-001';
\echo '--- 财务批准 → 通过 ---'
UPDATE expense_claim SET status='approved', approved_by='b0000000-0000-0000-0000-000000000004'
 WHERE claim_no='EXP-001';
SELECT claim_no, category AS 类别, amount_aud AS 金额, scope,
       COALESCE(scope_reason,'—') AS 例外原因, status FROM expense_claim ORDER BY claim_no;

\echo ''
\echo '════ ③ 报销进项目成本 / 公司级单列 ════'
SELECT pj_code AS 项目编号, pj_addr AS 项目地址, claim_count AS 笔数, expense_total AS 合计
FROM v_project_expense;
SELECT scope, scope_reason AS 原因, category AS 类别, expense_total AS 合计 FROM v_company_expense;

\echo ''
\echo '════ ④ 项目归属登记表（每张表怎么追回项目） ════'
SELECT kind_cn AS 归属类型, count(*) AS 表数,
       string_agg(table_name,', ' ORDER BY table_name) AS 表
FROM project_scope_registry GROUP BY kind_cn, kind ORDER BY kind;

\echo ''
\echo '════ ⑤ 待办：项目编号 + 项目地址在最前 ════'
SELECT 项目编号, left(项目地址,32) AS 项目地址, scope, kind_cn AS 类型, left(title,22) AS 事项, owner AS 归谁
FROM v_open_tasks ORDER BY scope, kind LIMIT 12;

\echo ''
\echo '════ ⑥ 断言 ════'
SELECT * FROM fn_assertion_summary();
SELECT code, severity, label, status FROM fn_run_assertions() WHERE violations<>0;
