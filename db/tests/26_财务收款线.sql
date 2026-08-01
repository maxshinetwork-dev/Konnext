-- 26 财务收款线（v0.33）：催款记录 · 烂尾不催款门禁 · 付款人指定 · 财务设置键
-- 期望拦截：4 次
\echo '════════ ① 造数：签约项目 + S1 节点（S1 无 SM 前置门禁） ════════'
INSERT INTO project(code,name,addr_suburb,addr_state,build_stage,step6_signed_at,created_at)
VALUES ('KX-T26-01','测试收款宅','Ryde','NSW','structure',now()-interval '90 days',now()-interval '120 days');
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due,invoice_no,invoice_sent_at,first_invoice_sent_at,status)
SELECT id,'contract','S1',10,40000,'INV-T26-S1',now()-interval '40 days',now()-interval '50 days','invoiced'
  FROM project WHERE code='KX-T26-01';

\echo '--- 正常项目催款（常规·短信·中文）→ 应成功 ---'
INSERT INTO payment_remind_log(milestone_id,channel,lang,level,sent_by)
SELECT m.id,'sms','zh','normal','王姐'
  FROM payment_milestone m JOIN project p ON p.id=m.project_id WHERE p.code='KX-T26-01';

\echo '--- 最终催款（短信+邮件·英文）→ 应成功；短信不回 Y 也不挡任何进展 ---'
INSERT INTO payment_remind_log(milestone_id,channel,lang,level,sent_by)
SELECT m.id,'both','en','final','王姐'
  FROM payment_milestone m JOIN project p ON p.id=m.project_id WHERE p.code='KX-T26-01';

\echo '════════ ② 门禁：烂尾项目不再关联催款 ════════'
UPDATE project SET status='stalled' WHERE code='KX-T26-01';
\echo '--- 烂尾后再催款 → 应拦 ---'
INSERT INTO payment_remind_log(milestone_id,channel,lang,level,sent_by)
SELECT m.id,'sms','zh','final','王姐'
  FROM payment_milestone m JOIN project p ON p.id=m.project_id WHERE p.code='KX-T26-01';

\echo '════════ ③ 枚举 CHECK：渠道/级别 ════════'
UPDATE project SET status='in_construction' WHERE code='KX-T26-01';
\echo '--- channel=wechat → 应拦 ---'
INSERT INTO payment_remind_log(milestone_id,channel,lang,level,sent_by)
SELECT m.id,'wechat','zh','normal','王姐'
  FROM payment_milestone m JOIN project p ON p.id=m.project_id WHERE p.code='KX-T26-01';
\echo '--- level=urgent → 应拦 ---'
INSERT INTO payment_remind_log(milestone_id,channel,lang,level,sent_by)
SELECT m.id,'sms','zh','urgent','王姐'
  FROM payment_milestone m JOIN project p ON p.id=m.project_id WHERE p.code='KX-T26-01';

\echo '════════ ④ 付款人指定：候选来源受限 ════════'
\echo '--- payer_source=builder + 快照 → 应成功 ---'
UPDATE project SET payer_source='builder', payer_name='Sam', payer_phone='0400 000 000',
       payer_email='sam@northbuild.com.au', payer_company='NorthBuild', payer_title='Builder'
 WHERE code='KX-T26-01';
\echo '--- payer_source=wechat_friend → 应拦（候选只有 联系人1/2·干系人·Builder·电工） ---'
UPDATE project SET payer_source='wechat_friend' WHERE code='KX-T26-01';

\echo '════════ ⑤ 财务设置键就位 ════════'
SELECT key, value_num, write_depts FROM eng_setting
 WHERE key IN ('gst_bank_pct','gst_cash_pct','suspend_server_days','overdue_days') ORDER BY key;
SELECT count(*) AS 催款模版键数 FROM eng_setting WHERE key LIKE 'remind_tpl_%';
SELECT level, channel, lang FROM payment_remind_log ORDER BY remind_at;
