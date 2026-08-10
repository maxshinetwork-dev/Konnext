SET timezone='Australia/Sydney';
SET app.actor='运维-小周';
\set ON_ERROR_STOP off

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','小周','hourly',80,'2025-01-01');
-- 项目A：施工中，未交付
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-8001','rough_in',now(),400000);
-- 项目B：已交付
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,handover_at,status,free_warranty_months) VALUES
 ('bbbbbbbb-0000-0000-0000-00000000000b','KX-2026-8002','rough_in',now(),600000,now()-interval '2 months','delivered',12);

\echo ''
\echo '=========== 未交付项目报修 → 不予受理 ==========='
-- v0.37：报修渠道无条件必填，造数据一并带上，免得被渠道门禁先拦掉、这条根本没测到
INSERT INTO maintenance_case(project_id,title,estimate_amount,report_channel)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','客户说客厅灯不亮',0,'phone');
\echo '--- 连派工也一起卡住 ---'
INSERT INTO maintenance_job(project_id,staff_id,scheduled_date,no_case_reason)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',current_date,'客户催');
\echo '--- 正确做法：走安装剩余项 ---'
INSERT INTO install_item(project_id,title,area) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a','客厅灯光回路复查','客厅');
SELECT p.code, i.title AS 走剩余项处理, i.status FROM install_item i JOIN project p ON p.id=i.project_id;

\echo ''
\echo '=========== 已交付项目报修 → 正常受理 ==========='
INSERT INTO maintenance_case(id,project_id,title,estimate_amount,labor_cost,material_cost,
                             report_channel,rd_conclusion,rd_by,rd_at)
VALUES('cccccccc-0000-0000-0000-00000000000c','bbbbbbbb-0000-0000-0000-00000000000b','客厅面板失灵',0,320,150,
       'phone','远程连不上这块面板，网关在线，判断是面板本体故障，需上门更换','研发-小赵',now());
\echo '--- ★v0.37 M4：没有排查结论就派人上门 → 应拒 ---'
--     靠自觉的话忙起来一定直接派人，人到了现场才发现是个远程五分钟能解决的事
INSERT INTO maintenance_case(id,project_id,title,report_channel)
VALUES('cccccccc-0000-0000-0000-0000000000cd','bbbbbbbb-0000-0000-0000-00000000000b',
       '书房开关偶尔失灵','wechat');
INSERT INTO maintenance_job(project_id,case_id,staff_id,scheduled_date,planned_minutes)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','cccccccc-0000-0000-0000-0000000000cd',
       '11111111-1111-1111-1111-111111111111',current_date,60);
\echo '--- 明确标「无需排查」并写清原因 → 放行 ---'
UPDATE maintenance_case SET rd_skip_reason='客户现场已复现且描述明确，是机械按键卡死，远程查不出来'
 WHERE id='cccccccc-0000-0000-0000-0000000000cd';
INSERT INTO maintenance_job(project_id,case_id,staff_id,scheduled_date,planned_minutes)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','cccccccc-0000-0000-0000-0000000000cd',
       '11111111-1111-1111-1111-111111111111',current_date,60);
SELECT title, left(COALESCE(rd_conclusion,rd_skip_reason),18) AS 排查
  FROM maintenance_case WHERE id='cccccccc-0000-0000-0000-0000000000cd';

INSERT INTO maintenance_job(project_id,case_id,staff_id,scheduled_date,planned_minutes)
VALUES('bbbbbbbb-0000-0000-0000-00000000000b','cccccccc-0000-0000-0000-00000000000c',
       '11111111-1111-1111-1111-111111111111',current_date,120);
\echo '--- 归因没填就结案 → 应拒 ---'
UPDATE maintenance_case SET status='paid_closed' WHERE id='cccccccc-0000-0000-0000-00000000000c';
\echo '--- 填产品缺陷 → 通过，自动判定免责覆盖 ---'
UPDATE maintenance_case SET fault_cause='product_defect', status='paid_closed'
 WHERE id='cccccccc-0000-0000-0000-00000000000c';
SELECT title, fault_cause AS 归因, is_free_warranty AS 免责覆盖 FROM maintenance_case;

\echo ''
\echo '=========== 长期利润率（不再需要成本归属过滤） ==========='
SELECT code, maint_labor AS 运维人力, maint_material AS 运维物料,
       free_warranty_cost AS 免责维保免掉 FROM v_long_term_margin WHERE code='KX-2026-8002';
