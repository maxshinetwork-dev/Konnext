SET timezone='Australia/Sydney';
SET app.actor='采购-王小美';
\set ON_ERROR_STOP off

\echo '=========== 汇率：只增不改 ==========='
INSERT INTO fx_rate(currency,rate_to_aud,source,created_by) VALUES
 ('CNY',0.2050,'google','system'),('USD',1.5100,'google','system');
INSERT INTO fx_rate(currency,rate_to_aud,source,created_by) VALUES
 ('CNY',0.2100,'google','system'),('USD',1.5200,'google','system');
SELECT currency, rate_to_aud AS 当前汇率, source AS 来源, days_stale AS 几天没更新, is_stale AS 过期
FROM v_fx_current ORDER BY currency;
SELECT count(*) AS 汇率历史条数 FROM fx_rate;

\echo ''
\echo '=========== 物料主表 ==========='
\echo '--- C1 不填红线 → 应拒 ---'
INSERT INTO material(code,category,protocol,internal_name,purchase_class,price_cny)
VALUES('M0001','面板','knx','KNX四联面板-白','C1',320);
\echo '--- C2 却填了红线 → 应拒(严格不设红线) ---'
INSERT INTO material(code,category,protocol,internal_name,purchase_class,reorder_point,price_aud)
VALUES('M0002','线材','none','Cat6网线','C2',50,2.5);
\echo '--- 三个币种价格全空 → 应拒 ---'
INSERT INTO material(code,category,internal_name,purchase_class,reorder_point)
VALUES('M0003','开关','测试','C1',10);
\echo '--- 利润率填 100% → 应拒(会除以零) ---'
INSERT INTO material(code,category,internal_name,purchase_class,reorder_point,price_aud,margin_pct)
VALUES('M0004','开关','测试2','C1',10,50,1.0);

\echo ''
\echo '--- 正常录入 ---'
INSERT INTO material(code,category,protocol,internal_name,supplier_model,supplier,spec,
  purchase_class,reorder_point,price_cny,freight_aud,margin_pct,warranty_months,updated_by) VALUES
 ('M0001','面板','knx','KNX四联面板','MTN6215-6035','深圳某某电子','白','C1',20,320,18,0.45,24,'采购-王小美'),
 ('M0002','面板','knx','KNX四联面板','MTN6215-6034','深圳某某电子','黑','C1',10,320,18,0.45,24,'采购-王小美');
INSERT INTO material(code,category,protocol,internal_name,supplier,purchase_class,price_aud,margin_pct,updated_by)
VALUES('M0010','线材','none','Cat6网线','悉尼本地电材','C2',2.50,0.30,'采购-王小美');
INSERT INTO material(code,category,protocol,internal_name,supplier,purchase_class,reorder_point,price_usd,freight_aud,margin_pct,updated_by)
VALUES('M0020','网关','knx','KNX/IP 网关','美国供应商','C1',5,480,45,0.40,'采购-王小美');

SELECT code, internal_name AS 物料名, spec AS 规格, purchase_class AS 类,
       cost_converted_aud AS 折算AUD, freight_aud AS 运费, cost_total_aud AS 成本合计,
       margin_pct AS 毛利率, sell_price_aud AS 售卖价, fx_stale AS 汇率过期
FROM v_material_price ORDER BY code;

\echo ''
\echo '=========== 汇率一变，全表售卖价跟着变 ==========='
INSERT INTO fx_rate(currency,rate_to_aud,source,created_by) VALUES ('CNY',0.2300,'google','system');
SELECT code, internal_name AS 物料名, cost_total_aud AS 成本合计, sell_price_aud AS 售卖价
FROM v_material_price WHERE price_cny IS NOT NULL ORDER BY code;

\echo ''
\echo '=========== 调价 / 调利润率：自动留痕 ==========='
SET app.actor='采购经理-李工';
UPDATE material SET price_cny=350 WHERE code='M0001';
UPDATE material SET margin_pct=0.50 WHERE code='M0001';
SELECT at::timestamp(0) AS 时间, actor AS 谁改的, code, internal_name AS 物料,
       old_cny AS 原价CNY, new_cny AS 新价CNY, old_margin AS 原毛利率, new_margin AS 新毛利率
FROM v_material_price_history ORDER BY at;

\echo ''
\echo '=========== 汇率抓取失败：人工填并标记，不静默 ==========='
INSERT INTO fx_rate(currency,rate_to_aud,source,note,created_by)
VALUES('USD',1.5350,'manual','Google 抓取失败，按 CBA 当日牌价','运维-小周');
SELECT currency, rate_to_aud AS 汇率, source AS 来源, note AS 说明 FROM v_fx_current WHERE currency='USD';
