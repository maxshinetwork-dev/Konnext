SET timezone='Australia/Sydney';
SET app.actor='库管-老张';
\set ON_ERROR_STOP off

INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('CNY',0.2100,'google');
INSERT INTO material(code,category,protocol,internal_name,spec,supplier,purchase_class,reorder_point,price_cny,freight_aud,margin_pct)
VALUES('M0001','面板','knx','KNX四联面板','白','深圳某某','C1',20,320,18,0.45),
      ('M0002','面板','knx','KNX四联面板','黑','深圳某某','C1',10,320,18,0.45);
INSERT INTO material(code,category,protocol,internal_name,supplier,purchase_class,price_aud,margin_pct)
VALUES('M0010','线材','none','Cat6网线','悉尼本地','C2',2.50,0.30);

\echo ''
\echo '=========== 上线前：哪些物料还没做期初 ==========='
SELECT code, internal_name AS 物料, spec AS 规格, opening_done AS 已做期初, current_on_hand AS 当前库存
FROM v_opening_status ORDER BY code;

\echo ''
\echo '=========== 期初移库：把仓库现有存货录进来 ==========='
SELECT fn_opening_stock('M0001', 38, 85.20, '2026-08-01 盘点');
SELECT fn_opening_stock('M0002', 24, 85.20, '2026-08-01 盘点');
SELECT fn_opening_stock('M0010', 500, 2.50, '2026-08-01 盘点');

\echo ''
\echo '--- 同一个物料再做一次期初 → 应拒(否则库存凭空翻倍) ---'
SELECT fn_opening_stock('M0001', 38, 85.20, '手滑又跑了一遍');
\echo '--- 物料编号不存在 → 应拒(不静默跳过) ---'
SELECT fn_opening_stock('M9999', 10, 5.00, NULL);
\echo '--- 期初数量为负 → 应拒 ---'
SELECT fn_opening_stock('M0002', -5, 85.20, NULL);

\echo ''
\echo '=========== 期初完成度 ==========='
SELECT code, internal_name AS 物料, spec, opening_done AS 已做期初,
       opening_qty AS 期初数量, current_on_hand AS 当前库存 FROM v_opening_status ORDER BY code;

\echo ''
\echo '=========== 上线后再采购到货：库存在期初基础上累加 ==========='
INSERT INTO purchase_order(id,po_no,source_type,supplier,ordered_at,status,created_by)
VALUES('dddd0000-0000-0000-0000-000000000001','PO-2026-0090','bulk','深圳某某',now(),'ordered','采购-王小美');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud)
SELECT 'dddd0000-0000-0000-0000-000000000001',id,50,50,85.20 FROM material WHERE code='M0001';
SELECT code, internal_name AS 物料, spec, qty_on_hand AS 当前库存 FROM v_material_stock WHERE code='M0001';

\echo ''
\echo '=========== 库存来源拆分：期初 vs 上线后采购 ==========='
SELECT code, internal_name AS 物料, spec, from_opening AS 来自期初,
       from_purchase AS 来自采购, total_out AS 已出库, on_hand AS 当前库存
FROM v_stock_source_split ORDER BY code;

\echo ''
\echo '=========== 期初也在流水里，来路可查 ==========='
SELECT internal_name AS 物料, spec, direction AS 方向, qty AS 数量, ref_no AS 单号, counterparty AS 对方
FROM v_stock_ledger ORDER BY ref_no, 物料;
