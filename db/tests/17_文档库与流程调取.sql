SET timezone='Australia/Sydney';
SET app.actor='工程经理-陈总';
\set ON_ERROR_STOP off

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','小陈','hourly',80,'2025-01-01');
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','rough_in',now(),500000);
INSERT INTO project_party(id,project_id,trade,company,contact_name,phone)
VALUES('cccc0000-0000-0000-0000-00000000000e','aaaaaaaa-0000-0000-0000-00000000000a','electrician','Spark电气','Tony','0422000222');

\echo ''
\echo '=========== 一、建文档库（三类） ==========='
INSERT INTO document(id,doc_code,title,doc_type,audience,language,owner_role) VALUES
 ('d0000000-0000-0000-0000-000000000001','DOC-SM1-GUIDE','SM1 进场作业指引','internal_guide','staff','zh','工程经理'),
 ('d0000000-0000-0000-0000-000000000002','DOC-SM2-FINISH','完成面(Finish)文档','external_notice','electrician','bilingual','工程经理'),
 ('d0000000-0000-0000-0000-000000000003','DOC-BUILDER-FLOW','致 Builder 施工配合说明','external_notice','builder','bilingual','工程经理'),
 ('d0000000-0000-0000-0000-000000000004','DOC-HANDOVER-MANUAL','客户交付手册','client_doc','client','zh','工程经理'),
 ('d0000000-0000-0000-0000-000000000005','DOC-MAINT-GUIDE','客户维护说明','client_doc','client','zh','运维经理');

\echo '--- 发布版本（v1） ---'
INSERT INTO document_version(document_id,version_no,file_url,file_name,change_note) VALUES
 ('d0000000-0000-0000-0000-000000000002',1,'https://x/finish_v1.pdf','Finish_v1.pdf','初版'),
 ('d0000000-0000-0000-0000-000000000004',1,'https://x/manual_v1.pdf','Manual_v1.pdf','初版'),
 ('d0000000-0000-0000-0000-000000000005',1,'https://x/maint_v1.pdf','Maint_v1.pdf','初版');

\echo ''
\echo '=========== 二、绑到流程节点 ==========='
INSERT INTO document_binding(node,document_id,required,need_ack) VALUES
 ('sm2','d0000000-0000-0000-0000-000000000002',true,true),    -- Finish 给电工，要签收
 ('handover','d0000000-0000-0000-0000-000000000004',true,false),
 ('handover','d0000000-0000-0000-0000-000000000005',true,false);
\echo '--- ★工程人员打开 SM2 任务，看到该带什么 ---'
SELECT node, title AS 文档, audience AS 给谁, version_no AS 版本, required AS 必带, need_ack AS 需签收, file_url
FROM v_node_documents WHERE node='sm2';

\echo ''
\echo '=========== 三、Finish 文档改版 → v2 ==========='
INSERT INTO document_version(document_id,version_no,file_url,file_name,change_note)
VALUES('d0000000-0000-0000-0000-000000000002',2,'https://x/finish_v2.pdf','Finish_v2.pdf','增加地暖回路完成面标高');
SELECT title AS 文档, version_no AS 当前版本, total_versions AS 共几版, change_note AS 本版改动
FROM v_document_current WHERE doc_code='DOC-SM2-FINISH';

\echo ''
\echo '=========== 四、SM2：文档没签收就想完成 → 应拒 ==========='
INSERT INTO site_meeting(id,project_id,sm_no) VALUES('bbbb0000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-00000000000a',1);
UPDATE site_meeting SET completed_at=now() WHERE id='bbbb0000-0000-0000-0000-000000000001';
INSERT INTO site_meeting(id,project_id,sm_no) VALUES('bbbb0000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-00000000000a',2);
UPDATE site_meeting SET completed_at=now() WHERE id='bbbb0000-0000-0000-0000-000000000002';

\echo ''
\echo '--- 发 Finish v2 给电工 Tony ---'
INSERT INTO document_issue(id,project_id,node,version_id,to_party_id,recipient_name,channel,issued_by)
SELECT 'ffff0000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-00000000000a','sm2',v.id,
       'cccc0000-0000-0000-0000-00000000000e','Tony','email','工程经理-陈总'
FROM document_version v WHERE v.document_id='d0000000-0000-0000-0000-000000000002' AND v.version_no=2;
\echo '--- 发了但没签收 → 仍不能完成 SM2 ---'
UPDATE site_meeting SET completed_at=now() WHERE id='bbbb0000-0000-0000-0000-000000000002';
\echo '--- 电工签字确认收到 → 可以完成 ---'
UPDATE document_issue SET acknowledged=true, ack_sign_url='https://x/tony_sign.jpg'
 WHERE id='ffff0000-0000-0000-0000-000000000001';
UPDATE site_meeting SET completed_at=now() WHERE id='bbbb0000-0000-0000-0000-000000000002';
SELECT sm_no, completed_at IS NOT NULL AS 已完成 FROM site_meeting ORDER BY sm_no;

\echo ''
\echo '=========== 五、★电工签的是哪一版，永久记着 ==========='
SELECT title AS 文档, version_no AS 签的是第几版, recipient AS 谁签的, acknowledged AS 已签收,
       is_current_version AS 是否最新版, latest_version_no AS 现在最新是第几版
FROM v_document_issue_status WHERE project_code='KX-2026-0142';

\echo ''
\echo '--- Finish 又出 v3：Tony 签过的仍是 v2，不会被偷换 ---'
INSERT INTO document_version(document_id,version_no,file_url,change_note)
VALUES('d0000000-0000-0000-0000-000000000002',3,'https://x/finish_v3.pdf','修正三楼标高');
SELECT version_no AS Tony签的版本, is_current_version AS 是否最新版, latest_version_no AS 现最新版
FROM v_document_issue_status WHERE project_code='KX-2026-0142';

\echo ''
\echo '--- 已发放的版本想偷换文件 → 应拒 ---'
UPDATE document_version SET file_url='https://x/finish_v2_modified.pdf'
 WHERE document_id='d0000000-0000-0000-0000-000000000002' AND version_no=2;

\echo ''
\echo '=========== 六、交付：客户文档没交齐不许完成 ==========='
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a',3,now()),('aaaaaaaa-0000-0000-0000-00000000000a',4,now());
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,amount_due,status,settle_reason)
VALUES('f0000000-0000-0000-0000-00000000000a','aaaaaaaa-0000-0000-0000-00000000000a','contract','S4',10,50000,'settled','已结清');
INSERT INTO delivery_review(project_id,decision,reviewed_by) VALUES('aaaaaaaa-0000-0000-0000-00000000000a','ready','11111111-1111-1111-1111-111111111111');
\echo '--- 交付手册和维护说明都没交 → 应拒 ---'
INSERT INTO handover_job(id,project_id,staff_id,scheduled_date,client_sign_url,client_sign_name,client_sign_at,completed_at)
VALUES('cccc1111-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',current_date,'https://x/s.jpg','王先生',now(),now());
\echo '--- 交付前核对表：还差什么 ---'
SELECT node, title AS 文档, required AS 必交, issued AS 已发放, status_cn AS 状态
FROM v_node_doc_checklist WHERE project_code='KX-2026-0142' AND node='handover';
\echo '--- 两份都交给客户 → 可以完成交付 ---'
INSERT INTO document_issue(project_id,node,version_id,to_client,recipient_name,channel,issued_by)
SELECT 'aaaaaaaa-0000-0000-0000-00000000000a','handover',v.id,true,'王先生','onsite','工程经理-陈总'
FROM document_version v WHERE v.document_id IN
 ('d0000000-0000-0000-0000-000000000004','d0000000-0000-0000-0000-000000000005');
INSERT INTO handover_job(project_id,staff_id,scheduled_date,client_sign_url,client_sign_name,client_sign_at,completed_at)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111',current_date,'https://x/s.jpg','王先生',now(),now());
SELECT node, title AS 文档, status_cn AS 状态 FROM v_node_doc_checklist WHERE project_code='KX-2026-0142' AND node='handover';
SELECT code, status AS 项目状态 FROM project;
