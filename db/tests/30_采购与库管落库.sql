-- 30 采购与库管落库（v0.36 ②）
-- 把 2026-08-04 五十七~六十一轮 UI 定下来的口径钉在数据库里：
--   ★要不要采购的指令由库管下达，采购不能自己决定
--   ★调价必须写原因（三个月后有人问「这个料怎么贵了 5 块」，靠的就是这句）
--   ★汇率下单即定格（否则上月买的东西这月成本自己变，账永远对不上）
--   ★退换四步只能往前推，每步必填凭据
--   ★到货点数对不上按实收入库、差额交采购 —— 库管不许把数字改成"刚好"
-- 期望拦截：14 次
-- ★写这个文件时撞出一个真 bug：集中采购（没有项目）标到货时，fn_notify_dept 插的
--   部门交接没标 scope='company'，被项目归属三态门禁拒掉 —— 集中采购根本标不了到货。
--   已在 v0.36 修（见契约 fn_notify_dept）。⑤ 里那步「到货」就是它的回归。

\echo '════════ ① 造数：供应商 + 物料 + 项目 ════════'
INSERT INTO supplier(name,contact,phone,email,currency,lead_days,terms,note)
VALUES ('KNX Asia Trading','Alex','+852 9123 4567','alex@knxasia.com','USD',28,'预付 30%',
        '春节前后要提前两周下单');
INSERT INTO project(code,name,addr_suburb,addr_state,build_stage,created_at)
VALUES ('KX-T30-01','测试宅','Ryde','NSW','structure',now()-interval '60 days');
INSERT INTO material(code,internal_name,category,protocol,purchase_class,price_aud,
                     warranty_months,reorder_point,supplier_id)
VALUES ('T30-M-1','测试面板','panel','knx','C1',120,24,20,
        (SELECT id FROM supplier WHERE name='KNX Asia Trading'));

\echo '════════ ② 供应商门禁 ════════'
\echo '--- ★应拦：标准交期填 0（ETA 全算成当天 → 从此没有任何一单超期，准时率永远 100%）---'
INSERT INTO supplier(name,currency,lead_days) VALUES ('零交期供应商','AUD',0);
\echo '--- ★应拦：重名 ---'
INSERT INTO supplier(name,currency,lead_days) VALUES ('KNX Asia Trading','AUD',10);
\echo '--- ★应拦：被物料引用的供应商删不掉（要改用停用）---'
DELETE FROM supplier WHERE name='KNX Asia Trading';
\echo '--- 停用可以（历史照旧可查）---'
UPDATE supplier SET active=false WHERE name='KNX Asia Trading';
SELECT name, active FROM supplier WHERE name='KNX Asia Trading';
UPDATE supplier SET active=true WHERE name='KNX Asia Trading';

\echo '════════ ③ 调价流水：原因必填、同价不许记 ════════'
\echo '--- ★应拦：原因少于 4 字 ---'
INSERT INTO material_price_log(material_id,currency,price_from,price_to,reason,changed_by)
SELECT id,'AUD',120,130,'涨','老张' FROM material WHERE code='T30-M-1';
\echo '--- ★应拦：新价和原价一样（没改就别记一笔，调价历史要干净）---'
INSERT INTO material_price_log(material_id,currency,price_from,price_to,reason,changed_by)
SELECT id,'AUD',120,120,'供应商说没变','老张' FROM material WHERE code='T30-M-1';
\echo '--- 正常调价：写清楚原因 ---'
INSERT INTO material_price_log(material_id,currency,price_from,price_to,reason,changed_by)
SELECT id,'AUD',120,130,'供应商年度调价 +8.3%（已收确认函）','老张' FROM material WHERE code='T30-M-1';
UPDATE material SET price_aud=130 WHERE code='T30-M-1';
\echo '--- 趋势视图：这个料最近一次调的是什么、距今多久 ---'
SELECT code, last_from, last_to, last_pct, days_since, change_n FROM v_material_price_trend
 WHERE code='T30-M-1';

\echo '════════ ④ 采购需求：★采购永远是执行者，不能自己决定要不要买 ════════'
--   ⚠ v0.37 口径变更：项目料的提单人从【库管】改成【工程人员】（老板 2026-08-05 拍板）。
--     来源五档 quote / sm2_change / build_add / warehouse_restock / maintenance，
--     'project_demand' 这个 v0.36 的值已经不存在了（31 号回归专门测它）。
--     不变的是这一条：来源里【没有 procurement】—— 采购不能自己开需求。
\echo '--- ★应拦：采购自己开需求（来源里根本没有 procurement 这一档）---'
INSERT INTO purchase_req(req_no,source,material_id,qty,why,raised_by)
SELECT 'RQ-T30-X','procurement',id,10,'采购觉得该买了','老张' FROM material WHERE code='T30-M-1';
\echo '--- ★应拦：项目提料却没有项目 ---'
INSERT INTO purchase_req(req_no,source,material_id,qty,why,raised_by)
SELECT 'RQ-T30-Y','quote',id,10,'按方案 BOM 提料','工程 小陈' FROM material WHERE code='T30-M-1';
\echo '--- 正常：库管补货建议（公司级，不挂项目）---'
INSERT INTO purchase_req(req_no,source,material_id,qty,why,raised_by)
SELECT 'RQ-T30-1','warehouse_restock',id,40,'库存 12 低于红线 20（C1 常备件）','库管（系统现算）'
  FROM material WHERE code='T30-M-1';
\echo '--- ★应拦：退回库管却不写原因 ---'
UPDATE purchase_req SET status='returned' WHERE req_no='RQ-T30-1';
\echo '--- 正常：退回并写明原因 ---'
UPDATE purchase_req SET status='returned', returned_reason='这个料下周有替代品到货，先别买'
 WHERE req_no='RQ-T30-1';
SELECT req_no, source, status, returned_reason FROM purchase_req WHERE req_no='RQ-T30-1';

\echo '════════ ⑤ 采购单：汇率下单即定格 ════════'
INSERT INTO purchase_order(po_no,source_type,supplier_id,currency,fx_rate_frozen,
                           ordered_at,expected_at,status,reason)
VALUES ('PO-T30-1','bulk',(SELECT id FROM supplier WHERE name='KNX Asia Trading'),
        'USD',1.5180,now()-interval '20 days',(now()-interval '5 days')::date,'ordered',
        '集中采购 · 常备件补货');
\echo '--- ★应拦：改已定格的汇率（改了历史成本跟着变）---'
UPDATE purchase_order SET fx_rate_frozen=1.60 WHERE po_no='PO-T30-1';
\echo '--- 到货 ---'
UPDATE purchase_order SET arrived_at=now(), status='arrived' WHERE po_no='PO-T30-1';
\echo '--- ★应拦：已到货还想改预计到货日（准时率靠它算）---'
UPDATE purchase_order SET expected_at=current_date WHERE po_no='PO-T30-1';
\echo '--- 供应商准时率现算 ---'
SELECT name, done_n, ontime_n, on_way_n FROM v_supplier_perf WHERE name='KNX Asia Trading';

\echo '════════ ⑥ 到货差异：按实收入库，差额交采购 ════════'
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud)
SELECT (SELECT id FROM purchase_order WHERE po_no='PO-T30-1'), id, 40, 37, 130
  FROM material WHERE code='T30-M-1';
\echo '--- ★应拦：差异原因少于 4 字 ---'
INSERT INTO goods_receipt_diff(diff_no,po_line_id,qty_ordered,qty_received,reason,raised_by)
SELECT 'DF-T30-X',(SELECT id FROM purchase_order_line LIMIT 1),40,37,'少','老张';
\echo '--- ★应拦：没差异也开单 ---'
INSERT INTO goods_receipt_diff(diff_no,po_line_id,qty_ordered,qty_received,reason,raised_by)
SELECT 'DF-T30-Y',(SELECT id FROM purchase_order_line LIMIT 1),40,40,'点数一样也开一张','老张';
\echo '--- 正常：少收 3 件，写清楚，交采购 ---'
INSERT INTO goods_receipt_diff(diff_no,po_line_id,qty_ordered,qty_received,reason,raised_by)
SELECT 'DF-T30-1',(SELECT id FROM purchase_order_line LIMIT 1),40,37,
       '外箱完好但内数不足 3 件，已拍照','老张';
\echo '--- ★应拦：了结却不写处理结果 ---'
UPDATE goods_receipt_diff SET status='closed' WHERE diff_no='DF-T30-1';
\echo '--- 正常了结 ---'
UPDATE goods_receipt_diff SET status='closed', closed_note='供应商下批补发 3 件，已确认',
       closed_at=now() WHERE diff_no='DF-T30-1';
SELECT diff_no, kind, qty_ordered, qty_received, status FROM goods_receipt_diff;

\echo '════════ ⑦ 退换四步：只能往前推，每步必填凭据 ════════'
INSERT INTO rma_case(rma_no,project_id,material_id,qty,damage_cause,reporter_name,cost_bucket)
SELECT 'RMA-T30-1',(SELECT id FROM project WHERE code='KX-T30-01'),id,2,'product_defect','小周','maintenance'
  FROM material WHERE code='T30-M-1';
\echo '--- ★应拦：没写凭据就想推进 ---'
UPDATE rma_case SET track_status='supplier_received' WHERE rma_no='RMA-T30-1';
\echo '--- 正常：先写凭据，再推进 ---'
INSERT INTO rma_track(rma_id,to_status,evidence,moved_by)
SELECT id,'supplier_received','Alex 邮件确认签收，已转技术检测','老张' FROM rma_case WHERE rma_no='RMA-T30-1';
UPDATE rma_case SET track_status='supplier_received' WHERE rma_no='RMA-T30-1';
\echo '--- ★应拦：跳级（对方已收 → 直接已接收）---'
INSERT INTO rma_track(rma_id,to_status,evidence,moved_by)
SELECT id,'received_back','跳一步试试','老张' FROM rma_case WHERE rma_no='RMA-T30-1';
UPDATE rma_case SET track_status='received_back', received_qty=2 WHERE rma_no='RMA-T30-1';
\echo '--- ★应拦：往回退 ---'
UPDATE rma_case SET track_status='returned' WHERE rma_no='RMA-T30-1';
\echo '--- 正常推进到已发货 ---'
INSERT INTO rma_track(rma_id,to_status,evidence,moved_by)
SELECT id,'supplier_shipped','换新件已发出 AU Post 7788 1122','老张' FROM rma_case WHERE rma_no='RMA-T30-1';
UPDATE rma_case SET track_status='supplier_shipped' WHERE rma_no='RMA-T30-1';
\echo '--- ★应拦：标已接收却不填实收数量（少收就被悄悄抹平了）---'
UPDATE rma_case SET track_status='received_back' WHERE rma_no='RMA-T30-1';
\echo '--- ★应拦：收到的比寄回去的还多 ---'
UPDATE rma_case SET track_status='received_back', received_qty=5 WHERE rma_no='RMA-T30-1';
\echo '--- 正常：实收 2 件，采购跟踪结束，通知库管入库 ---'
UPDATE rma_case SET track_status='received_back', received_qty=2, received_back_at=now()
 WHERE rma_no='RMA-T30-1';
SELECT rma_no, track_status, qty, received_qty, chase_n, stuck_days FROM v_rma_tracking
 WHERE rma_no='RMA-T30-1';

\echo '════════ ⑧ 断言复核：四条新断言必须绿 ════════'
SELECT code, violations, status FROM fn_run_assertions()
 WHERE code IN ('INV-PC-01','INV-PC-02','INV-PC-03','INV-WH-01');
