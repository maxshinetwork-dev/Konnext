SET timezone='Australia/Sydney';
SET app.actor='工程-小陈';
\set ON_ERROR_STOP off

INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','小陈','hourly',80,'2025-01-01');
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-7001','rough_in',now(),500000);

\echo ''
\echo '=========== SM3 登记变更：只留痕，不碰金额 ==========='
INSERT INTO variation(id,project_id,change_type,description,logged_by) VALUES
 ('11110000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-00000000000a','add','客厅加两个开关点位','11111111-1111-1111-1111-111111111111'),
 ('11110000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-00000000000a','move','主卧面板从床头移到门口','11111111-1111-1111-1111-111111111111'),
 ('11110000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-00000000000a','remove','取消车库两个感应器','11111111-1111-1111-1111-111111111111');
SELECT change_type AS 类型, description AS 描述, settle_amount AS 金额, settle_status AS 结算状态 FROM variation ORDER BY change_type;

\echo ''
\echo '--- 金额还没填就想标已结算 → 应拒 ---'
UPDATE variation SET settle_status='settled_s4' WHERE id='11110000-0000-0000-0000-000000000001';

\echo ''
\echo '=========== 财务+库管在外部算完，填回来 ==========='
SET app.actor='财务-王姐';
UPDATE variation SET settle_amount=4800, settle_source='external_system',
  settle_ext_ref='VAR-2026-7001-计算表.xlsx', settle_status='settled_s4',
  settle_note='依据 SM3 照片 + 库管出库单，2个点位含面板与布线'
 WHERE id='11110000-0000-0000-0000-000000000001';
UPDATE variation SET settle_amount=1200, settle_source='external_system',
  settle_ext_ref='VAR-2026-7001-计算表.xlsx', settle_status='settled_s4',
  settle_note='移位只计人工，物料复用'
 WHERE id='11110000-0000-0000-0000-000000000002';
UPDATE variation SET settle_amount=-1500, settle_source='external_system',
  settle_ext_ref='VAR-2026-7001-计算表.xlsx', settle_status='settled_s4',
  settle_note='退回2个感应器，按采购价扣'
 WHERE id='11110000-0000-0000-0000-000000000003';
SELECT change_type AS 类型, settle_amount AS 金额, settle_source AS 来源,
       settle_by AS 谁填的, settle_at IS NOT NULL AS 已留痕 FROM variation ORDER BY change_type;

\echo ''
\echo '=========== S4 开票前：财务照这张台账核对 ==========='
SELECT project_code, total_count AS 变更总数, priced_count AS 已估价, unpriced_count AS 未估价,
       add_count AS 加, remove_count AS 减, move_count AS 移,
       settle_total AS 变更合计, s4_expected AS S4应收预期 FROM v_variation_settlement;

\echo ''
\echo '=========== 发 S4：金额自动叠加变更 ==========='
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','contract','S4',10,'INV-7001-S4-v1',now());
SELECT stage, amount_due AS S4应收, invoice_no FROM payment_milestone WHERE stage='S4';

\echo ''
\echo '=========== S4 已发出后再改变更金额 → 应拒 ==========='
UPDATE variation SET settle_amount=6000 WHERE id='11110000-0000-0000-0000-000000000001';
SELECT change_type AS 类型, settle_amount AS 金额没被改动 FROM variation WHERE id='11110000-0000-0000-0000-000000000001';
