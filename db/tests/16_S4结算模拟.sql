SET timezone='Australia/Sydney';
SET app.actor='财务-王姐';
\set ON_ERROR_STOP off

-- ============ 铺一个完整项目 ============
INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('CNY',0.2100,'google');
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,cost_hourly_rate,phone,hired_at) VALUES
 ('11111111-1111-1111-1111-111111111111','小陈(工程师)','hourly',80,80,'0411000111','2025-01-01'),
 ('22222222-2222-2222-2222-222222222222','李四(负责人)','hourly',120,120,'0411000222','2025-01-01');
INSERT INTO material(id,code,category,protocol,internal_name,spec,supplier,purchase_class,reorder_point,price_cny,freight_aud,margin_pct,warranty_months)
VALUES('99990000-0000-0000-0000-000000000001','M0001','面板','knx','KNX四联面板','白','深圳某某','C1',20,320,18,0.45,24);

INSERT INTO project(id,code,name,build_stage,step6_signed_at,contract_price,planned_labor_hours,o1_name,o1_email)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','KX-2026-0142','Cherrybrook 王宅','rough_in',
       now()-interval '300 days',500000,400,'王先生','wang@example.com');
INSERT INTO project_party(id,project_id,trade,company,contact_name,phone) VALUES
 ('cccc0000-0000-0000-0000-00000000000e','aaaaaaaa-0000-0000-0000-00000000000a','electrician','Spark电气','Tony','0422000222'),
 ('cccc0000-0000-0000-0000-00000000000b','aaaaaaaa-0000-0000-0000-00000000000a','builder','BuildCo','Mike','0433000333');

-- SM1~4 全部完成
INSERT INTO site_meeting(project_id,sm_no,completed_at,owner_staff_id) VALUES
 ('aaaaaaaa-0000-0000-0000-00000000000a',1,now()-interval '280 days','11111111-1111-1111-1111-111111111111'),
 ('aaaaaaaa-0000-0000-0000-00000000000a',2,now()-interval '250 days','11111111-1111-1111-1111-111111111111'),
 ('aaaaaaaa-0000-0000-0000-00000000000a',3,now()-interval '200 days','11111111-1111-1111-1111-111111111111'),
 ('aaaaaaaa-0000-0000-0000-00000000000a',4,now()-interval '100 days','11111111-1111-1111-1111-111111111111');

-- S1~S3 已结清
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at) VALUES
 ('f0000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-00000000000a','contract','S1',10,'INV-0142-S1',now()-interval '290 days'),
 ('f0000000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-00000000000a','contract','S2',40,'INV-0142-S2',now()-interval '190 days'),
 ('f0000000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-00000000000a','contract','S3',40,'INV-0142-S3',now()-interval '90 days');
INSERT INTO payment_receipt(milestone_id,method,amount,gst_amount,received_at) VALUES
 ('f0000000-0000-0000-0000-000000000001','bank',50000,5000,now()-interval '285 days'),
 ('f0000000-0000-0000-0000-000000000002','bank',200000,20000,now()-interval '185 days'),
 ('f0000000-0000-0000-0000-000000000003','bank',200000,20000,now()-interval '85 days');
UPDATE payment_milestone SET status='settled' WHERE stage IN ('S1','S2','S3');

-- SM3 登记三条变更
INSERT INTO variation(id,project_id,origin,change_type,description,logged_by,created_at,
  notified_design,notified_procure,notified_finance) VALUES
 ('11110000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-00000000000a','sm3','add',
  '客厅加两个开关点位（业主现场提出）','11111111-1111-1111-1111-111111111111',now()-interval '200 days',true,true,true),
 ('11110000-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-00000000000a','sm3','move',
  '主卧面板从床头移到门口（设计图有误）','11111111-1111-1111-1111-111111111111',now()-interval '200 days',true,true,true),
 ('11110000-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-00000000000a','sm3','remove',
  '取消车库两个感应器（业主删减）','11111111-1111-1111-1111-111111111111',now()-interval '200 days',true,true,true);

-- 采购到货 + 出库给电工 + 部分退回
INSERT INTO purchase_order(id,po_no,source_type,supplier,ordered_at,status) VALUES('dddd0000-0000-0000-0000-000000000001','PO-0087','bulk','深圳某某',now()-interval '180 days','ordered');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud) VALUES('dddd0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',100,100,85.20);
INSERT INTO stock_out(id,out_no,project_id,receiver_party_id,released_at) VALUES('eeee0000-0000-0000-0000-000000000001','OUT-0142-01','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000e',now()-interval '150 days');
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud) VALUES('eeee0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',20,85.20);
INSERT INTO stock_return(id,return_no,project_id,returner_party_id,returner_name,returned_at) VALUES('bbbb0000-0000-0000-0000-000000000001','RET-0142-01','aaaaaaaa-0000-0000-0000-00000000000a','cccc0000-0000-0000-0000-00000000000e','Tony',now()-interval '20 days');
INSERT INTO stock_return_line(return_id,material_id,qty,condition,unit_cost_aud) VALUES('bbbb0000-0000-0000-0000-000000000001','99990000-0000-0000-0000-000000000001',7,'good',85.20);

-- 工时（SM + 安装）
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method)
SELECT 'aaaaaaaa-0000-0000-0000-00000000000a','11111111-1111-1111-1111-111111111111','execution',
       (now()-interval '90 days')::date + (d||' days')::interval + interval '8 hours',
       (now()-interval '90 days')::date + (d||' days')::interval + interval '17 hours','gps'
FROM generate_series(1,45) d;
INSERT INTO work_log(project_id,staff_id,work_type,checkin_at,checkout_at,checkin_method)
SELECT 'aaaaaaaa-0000-0000-0000-00000000000a','22222222-2222-2222-2222-222222222222','sm',
       (now()-interval '280 days')::date + (d*60||' days')::interval + interval '9 hours',
       (now()-interval '280 days')::date + (d*60||' days')::interval + interval '13 hours','gps'
FROM generate_series(0,3) d;

-- 财务+库管在外部算完变更金额，填回来
UPDATE variation SET settle_amount=4800, settle_source='external_system', settle_ext_ref='VAR-0142-计算表.xlsx',
  settle_status='settled_s4', settle_note='依据 SM3 照片+库管出库单：2点位含面板2块与布线' WHERE id='11110000-0000-0000-0000-000000000001';
-- ★移位属电工整改，不向客户计费：只留痕，不填金额
UPDATE variation SET settle_note='移位属电工装错位置，已告知电工整改，不向客户计费'
 WHERE id='11110000-0000-0000-0000-000000000002';
UPDATE variation SET settle_amount=-1500, settle_source='external_system', settle_ext_ref='VAR-0142-计算表.xlsx',
  settle_status='settled_s4', settle_note='退回2个感应器，按采购价扣' WHERE id='11110000-0000-0000-0000-000000000003';
SET app.actor='财务-王姐';
\echo '════ ① 开票前：系统提示还有未退料没结算 ════'
SELECT s4_base AS S4基数, variation_add AS 变更增, variation_less AS 变更减,
       nonbillable_count AS 不计费项, pending_unreturned AS 待结算未退料,
       need_settle_unreturned AS 需先结算, s4_payable AS 当前应收
FROM v_s4_settlement WHERE code='KX-2026-0142';
\echo '════ ② 结算未退料 ════'
SELECT fn_settle_unreturned('aaaaaaaa-0000-0000-0000-00000000000a');
\echo '════ ③ 结算后 ════'
SELECT pending_unreturned AS 待结算未退料, need_settle_unreturned AS 需先结算, s4_payable AS S4应收
FROM v_s4_settlement WHERE code='KX-2026-0142';
\echo '════ ④ 开 S4 发票：发票金额 vs 明细表金额 ════'
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('aaaaaaaa-0000-0000-0000-00000000000a','contract','S4',10,'INV-0142-S4-v1',now());
SELECT m.invoice_no AS 发票号, m.amount_due AS 发票金额, s.s4_payable AS 明细表金额,
       (m.amount_due = s.s4_payable) AS 对得上
FROM payment_milestone m JOIN v_s4_settlement s ON s.project_id=m.project_id
WHERE m.stage='S4';
\echo '════ ⑤ S4 发票已发出后再想追加未退料 → 应拒 ════'
SELECT fn_settle_unreturned('aaaaaaaa-0000-0000-0000-00000000000a');
