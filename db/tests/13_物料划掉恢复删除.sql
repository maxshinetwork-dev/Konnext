SET timezone='Australia/Sydney';
SET app.actor='采购-王小美';
\set ON_ERROR_STOP off

INSERT INTO fx_rate(currency,rate_to_aud,source) VALUES ('CNY',0.2100,'google');
INSERT INTO material(code,category,protocol,internal_name,spec,supplier,purchase_class,reorder_point,price_cny,freight_aud,margin_pct)
VALUES('M0001','面板','knx','KNX四联面板','白','深圳某某','C1',20,320,18,0.45),
      ('M0002','面板','knx','KNX四联面板','黑','深圳某某','C1',10,320,18,0.45);
INSERT INTO material(code,category,protocol,internal_name,supplier,purchase_class,price_aud,margin_pct)
VALUES('M0090','面板','knx','旧款三联面板','深圳某某','C2',60,0.40),
      ('M0099','开关','knx','录错的测试项','深圳某某','C2',10,0.30);

-- M0001 有流水（采购到货 + 出库）
INSERT INTO purchase_order(id,po_no,source_type,supplier,ordered_at,status)
VALUES('dddd0000-0000-0000-0000-000000000001','PO-0001','bulk','深圳某某',now(),'ordered');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud)
SELECT 'dddd0000-0000-0000-0000-000000000001',id,50,50,85.20 FROM material WHERE code='M0001';
-- M0090 也进过一批货，还剩着
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud)
SELECT 'dddd0000-0000-0000-0000-000000000001',id,12,12,60.00 FROM material WHERE code='M0090';

\echo ''
\echo '=========== 一、划掉：必须填原因 ==========='
SELECT fn_archive_material('M0090', NULL);
\echo '--- 填了原因 → 通过，并提示还有存货 ---'
SELECT fn_archive_material('M0090', '厂家停产，改用四联款');
SELECT fn_archive_material('M0099', '录入时打错了，从没用过');

\echo ''
\echo '=========== 二、划掉后不再被任何系统调用 ==========='
\echo '--- 想给已划掉的物料下单入库 → 应拒 ---'
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud)
SELECT 'dddd0000-0000-0000-0000-000000000001',id,5,5,60.00 FROM material WHERE code='M0090';

\echo ''
\echo '=========== 三、界面清单：划掉的带删除线标记 ==========='
SELECT code, display_name AS 物料, active AS 启用, strikethrough AS 画横线,
       archive_reason AS 划掉原因, qty_on_hand AS 库存, can_hard_delete AS 可彻底删除
FROM v_material_list ORDER BY active DESC, code;

\echo ''
\echo '=========== 四、划掉但仍有库存 → 必须看得见，不能成账外物资 ==========='
SELECT code, display_name AS 物料, qty_on_hand AS 剩余库存, archive_reason AS 原因, action_needed AS 要办的事
FROM v_archived_with_stock;

\echo ''
\echo '=========== 五、彻底删除 ==========='
\echo '--- M0001 有流水 → 应拒 ---'
SELECT fn_delete_material('M0001');
\echo '--- M0090 有流水(虽已划掉) → 应拒 ---'
SELECT fn_delete_material('M0090');
\echo '--- M0002 从没用过，但还没划掉 → 应拒(防手滑) ---'
SELECT fn_delete_material('M0002');
\echo '--- M0099 已划掉 + 从没用过 → 允许彻底删除 ---'
SELECT fn_delete_material('M0099');

\echo ''
\echo '=========== 六、恢复 ==========='
SET app.actor='采购经理-李工';
SELECT fn_restore_material('M0090');
\echo '--- 恢复后可以继续下单 ---'
INSERT INTO purchase_order(id,po_no,source_type,supplier,ordered_at,status)
VALUES('dddd0000-0000-0000-0000-000000000002','PO-0002','bulk','深圳某某',now(),'ordered');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud)
SELECT 'dddd0000-0000-0000-0000-000000000002',id,5,5,60.00 FROM material WHERE code='M0090';
SELECT code, display_name AS 物料, qty_on_hand AS 恢复后库存 FROM v_material_list WHERE code='M0090';
SELECT code, display_name AS 物料, active AS 启用, archived_at::date AS 曾划掉于,
       archive_reason AS 当时原因, restored_by AS 谁恢复的 FROM v_material_list WHERE code='M0090';

\echo ''
\echo '=========== 七、划掉/恢复/删除全程留痕 ==========='
SELECT at::timestamp(0) AS 时间, actor AS 谁, code, display_name AS 物料, action_cn AS 动作, reason AS 原因
FROM v_material_archive_history ORDER BY at;
