SET timezone='Australia/Sydney';
\set ON_ERROR_STOP off

\echo '════ 一、系统初始化：第一个账号必须是核心管理员 ════'
\echo '--- 第一个账号想建成部门账号 → 应拒 ---'
INSERT INTO app_account(login_name,full_name,tier,phone,email) VALUES('a1','张部门',2,'0400000001','a1@x.com');
\echo '--- 建核心管理员 → 通过（自举） ---'
INSERT INTO app_account(id,login_name,full_name,tier,is_core_admin,phone,email,phone_bound_at)
VALUES('a0000000-0000-0000-0000-000000000001','core','陈总(核心管理员)',1,true,'0400000000','core@x.com',now());

\echo ''
\echo '════ 二、管理员账号：只有核心管理员能建，上限 3 ════'
INSERT INTO app_account(id,login_name,full_name,tier,phone,email,phone_bound_at,created_by)
VALUES('a0000000-0000-0000-0000-000000000002','admin2','李副总',1,'0400000002','a2@x.com',now(),'a0000000-0000-0000-0000-000000000001'),
      ('a0000000-0000-0000-0000-000000000003','admin3','王董',1,'0400000003','a3@x.com',now(),'a0000000-0000-0000-0000-000000000001');
\echo '--- 第 4 个管理员 → 应拒(上限3) ---'
INSERT INTO app_account(login_name,full_name,tier,phone,email,created_by)
VALUES('admin4','赵总',1,'0400000004','a4@x.com','a0000000-0000-0000-0000-000000000001');
\echo '--- 管理员没填邮箱 → 应拒(要靠邮箱自主找回) ---'
INSERT INTO app_account(login_name,full_name,tier,phone,created_by)
VALUES('admin5','孙总',1,'0400000005','a0000000-0000-0000-0000-000000000001');
\echo '--- 再来一个核心管理员 → 应拒(核心唯一) ---'
UPDATE app_account SET is_core_admin=true WHERE login_name='admin2';

\echo ''
\echo '════ 三、部门账号（六个部门，可兼任） ════'
INSERT INTO app_account(id,login_name,full_name,tier,phone,email,created_by) VALUES
 ('b0000000-0000-0000-0000-000000000001','presales','小林(售前)',2,'0411000001','p@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000002','engmgmt','陈工(工程管理)',2,'0411000002','e@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000003','stock','老张(采购兼库管)',2,'0411000003','s@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000004','finance','王姐(财务)',2,'0411000004','f@x.com','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000005','maint','小周(运维)',2,'0411000005','m@x.com','a0000000-0000-0000-0000-000000000001');
INSERT INTO account_department(account_id,department,granted_by) VALUES
 ('b0000000-0000-0000-0000-000000000001','presales','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000002','eng_mgmt','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000003','procurement','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000003','warehouse','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000004','finance','a0000000-0000-0000-0000-000000000001'),
 ('b0000000-0000-0000-0000-000000000005','maintenance','a0000000-0000-0000-0000-000000000001');
\echo '--- 部门账号想由部门账号来建 → 应拒 ---'
INSERT INTO app_account(login_name,full_name,tier,phone,email,created_by)
VALUES('presales2','小刘',2,'0411000009','p2@x.com','b0000000-0000-0000-0000-000000000001');
\echo '--- 给管理员挂部门 → 应拒(管理员是全局) ---'
INSERT INTO account_department(account_id,department) VALUES('a0000000-0000-0000-0000-000000000002','finance');

\echo ''
\echo '════ 四、施工人员：只能由工程管理建，且不能进后台 ════'
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,phone,hired_at) VALUES
 ('e1111111-1111-1111-1111-111111111111','小陈','hourly',80,'0422000001','2025-01-01');
INSERT INTO eng_staff(id,name,pay_type,daily_rate,ref_minutes,phone,hired_at) VALUES
 ('e2222222-2222-2222-2222-222222222222','外包A','contractor',510,600,'0422000002','2026-07-01');
\echo '--- 财务想建施工人员账号 → 应拒 ---'
INSERT INTO app_account(login_name,full_name,tier,phone,staff_id,backend_access,created_by)
VALUES('w1','小陈',3,'0422000001','e1111111-1111-1111-1111-111111111111',false,'b0000000-0000-0000-0000-000000000004');
\echo '--- 工程管理来建 → 通过 ---'
INSERT INTO app_account(id,login_name,full_name,tier,phone,staff_id,backend_access,created_by)
VALUES('c0000000-0000-0000-0000-000000000001','w1','小陈',3,'0422000001','e1111111-1111-1111-1111-111111111111',false,'b0000000-0000-0000-0000-000000000002');
\echo '--- 施工人员想开后台权限 → 应拒 ---'
INSERT INTO app_account(login_name,full_name,tier,phone,staff_id,backend_access,created_by)
VALUES('w9','小李',3,'0422000009','e1111111-1111-1111-1111-111111111111',true,'b0000000-0000-0000-0000-000000000002');
\echo '--- 外包账号：由我们代建，按第三级用 ---'
INSERT INTO app_account(id,login_name,full_name,tier,phone,staff_id,is_contractor,backend_access,created_by)
VALUES('c0000000-0000-0000-0000-000000000002','out_a','外包A',3,'0422000002','e2222222-2222-2222-2222-222222222222',true,false,'b0000000-0000-0000-0000-000000000002');
\echo '--- 给施工人员挂部门 → 应拒(只上报) ---'
INSERT INTO account_department(account_id,department) VALUES('c0000000-0000-0000-0000-000000000001','eng_mgmt');

\echo ''
\echo '════ 五、账号总览 ════'
SELECT tier_cn AS 级别, login_name, full_name AS 姓名, departments AS 部门,
       backend_access AS 可进后台, is_contractor AS 外包, created_by_name AS 谁建的
FROM v_account_overview WHERE active ORDER BY tier, login_name;

\echo ''
\echo '════ 六、兼任风险提醒 ════'
SELECT full_name AS 谁, risk_note AS 风险 FROM v_dual_role_alert;

\echo ''
\echo '════ 七、账号找回：只有管理员能自主找回 ════'
\echo '--- 施工人员想自主找回 → 应拒 ---'
INSERT INTO account_reset_log(account_id,action,performed_by)
VALUES('c0000000-0000-0000-0000-000000000001','self_recover','c0000000-0000-0000-0000-000000000001');
\echo '--- 部门账号让财务帮着重置 → 应拒(只能管理员) ---'
INSERT INTO account_reset_log(account_id,action,old_value,new_value,performed_by)
VALUES('b0000000-0000-0000-0000-000000000001','reset_phone','0411000001','0411009999','b0000000-0000-0000-0000-000000000004');
\echo '--- 管理员重置 → 通过，留痕 ---'
INSERT INTO account_reset_log(account_id,action,old_value,new_value,performed_by,reason)
VALUES('b0000000-0000-0000-0000-000000000001','reset_phone','0411000001','0411009999','a0000000-0000-0000-0000-000000000001','小林换号了');
\echo '--- 管理员自主找回 → 通过 ---'
INSERT INTO account_reset_log(account_id,action,performed_by)
VALUES('a0000000-0000-0000-0000-000000000002','self_recover','a0000000-0000-0000-0000-000000000002');
SELECT a.full_name AS 谁的账号, r.action AS 动作, r.old_value AS 原值, r.new_value AS 新值,
       p.full_name AS 谁操作的, r.reason AS 原因
FROM account_reset_log r JOIN app_account a ON a.id=r.account_id
LEFT JOIN app_account p ON p.id=r.performed_by ORDER BY r.at;

\echo ''
\echo '════ 八、停用账号 ════'
\echo '--- 部门账号想停用管理员 → 应拒 ---'
UPDATE app_account SET active=false, deactivated_by='b0000000-0000-0000-0000-000000000004' WHERE login_name='admin3';
\echo '--- 核心管理员想停用自己 → 应拒 ---'
UPDATE app_account SET active=false, deactivated_by='a0000000-0000-0000-0000-000000000001' WHERE login_name='core';
\echo '--- 核心管理员停用别的管理员 → 通过 ---'
UPDATE app_account SET active=false, deactivated_by='a0000000-0000-0000-0000-000000000001' WHERE login_name='admin3';

\echo ''
\echo '════ 九、管理员账号健康检查 ════'
SELECT admin_count AS 管理员数, admin_limit AS 上限, core_admin_count AS 核心管理员,
       admin_unbound_phone AS 未绑手机, admin_no_email AS 无邮箱 FROM v_admin_health;
