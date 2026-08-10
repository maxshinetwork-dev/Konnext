-- 31 项目物料账四段链条 + 提货与出库（v0.37 · 决策记录 §23）
--
--   ①报价原始单（采购上传，版本化只读）→ ②现场在 App 改（★不能删行只能调 0）
--   → ③工程管理审「变量」→ ④库管先看现货（备料＝占住不扣库存）→ 采购只买差额
--
-- ★这一版推翻了 v0.36 的一条口径：项目料的提单人从【库管】改成【工程人员】。
-- ★最要命的两条（都是「不报错、只是数字悄悄错了」那一类）：
--     买多了不标红 → 工程把 18 件改成 0，那 18 件的钱就悄悄留在项目成本里，谁也不会发现
--     备料就扣库存 → 货还在架子上账面却没了，盘点永远对不上
-- 期望拦截：30 次
SET timezone='Australia/Sydney';
SET app.actor='工程-陈工';
\set ON_ERROR_STOP off

\echo '════════ ① 造数：物料 / 项目 / 人 ════════'
INSERT INTO eng_staff(id,name,pay_type,pay_hourly_rate,phone,hired_at) VALUES
 ('e1110000-0000-0000-0000-000000000001','小陈','hourly',80,'0411000111','2025-01-01'),
 ('e1110000-0000-0000-0000-000000000002','小李','hourly',75,'0411000222','2025-01-01');
INSERT INTO material(id,code,category,protocol,internal_name,spec,purchase_class,reorder_point,
                     price_aud,margin_pct) VALUES
 ('99310000-0000-0000-0000-000000000001','T31-PANEL','面板','knx','KNX四联面板','白','C1',20,120,0.45),
 ('99310000-0000-0000-0000-000000000002','T31-PANEL2','面板','knx','KNX六联面板','白','C1',10,180,0.45);
INSERT INTO material(id,code,category,protocol,internal_name,purchase_class,price_aud,margin_pct) VALUES
 ('99310000-0000-0000-0000-000000000010','T31-CABLE','线材','none','Cat6网线','C2',2.50,0.30),
 ('99310000-0000-0000-0000-000000000011','T31-CABLE2','线材','none','HDMI线','C2',18.00,0.30);

-- P1：SM2 还没完成 → 可增可减
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,status) VALUES
 ('a1310000-0000-0000-0000-000000000001','KX-T31-01','rough_in',now(),500000,'in_construction');
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('a1310000-0000-0000-0000-000000000001',1,now());
-- P2：SM1~3 完成、S2 已结清 → 只能增；用来测出库
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,status) VALUES
 ('a1310000-0000-0000-0000-000000000002','KX-T31-02','rough_in',now(),600000,'in_construction');
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('a1310000-0000-0000-0000-000000000002',1,now()),
 ('a1310000-0000-0000-0000-000000000002',2,now()),
 ('a1310000-0000-0000-0000-000000000002',3,now());
INSERT INTO payment_milestone(id,project_id,kind,stage,ratio_pct,invoice_no,invoice_sent_at)
VALUES('f1310000-0000-0000-0000-000000000002','a1310000-0000-0000-0000-000000000002',
       'contract','S2',40,'INV-T31-S2',now());
INSERT INTO payment_receipt(milestone_id,method,amount,received_at)
VALUES('f1310000-0000-0000-0000-000000000002','bank',240000,now());
UPDATE payment_milestone SET status='settled' WHERE id='f1310000-0000-0000-0000-000000000002';
-- P3：S2 没结清 → 测 S2 门禁与 SM2 预提窄通道
INSERT INTO project(id,code,build_stage,step6_signed_at,contract_price,status) VALUES
 ('a1310000-0000-0000-0000-000000000003','KX-T31-03','rough_in',now(),300000,'in_construction');
INSERT INTO site_meeting(project_id,sm_no,completed_at) VALUES
 ('a1310000-0000-0000-0000-000000000003',1,now());
INSERT INTO payment_milestone(project_id,kind,stage,ratio_pct,amount_due,status)
VALUES('a1310000-0000-0000-0000-000000000003','contract','S2',40,120000,'pending');

-- 进货：面板 30 / 六联 5 / 网线 200（库存现算，不落库）
INSERT INTO purchase_order(id,po_no,source_type,ordered_at,expected_at,status,arrived_at)
VALUES('d1310000-0000-0000-0000-000000000001','PO-T31-1','bulk',now()-interval '10 days',
       current_date-1,'arrived',now());
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,qty_arrived,unit_cost_aud) VALUES
 ('d1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000001',30,30,85.20),
 ('d1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000002',5,5,140.00),
 ('d1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000010',200,200,1.80);

\echo ''
\echo '════════ ② 报价原始单：版本化 · 只读 · ★认不上的挂起 ════════'
SET app.actor='采购-王小美';
INSERT INTO quote_bom(id,project_id,ver_no,source_file,uploaded_by)
VALUES('b1310000-0000-0000-0000-000000000001','a1310000-0000-0000-0000-000000000001',
       'V4','KX-T31-01_BOM_V4.xlsx','采购-王小美');
INSERT INTO quote_bom_line(bom_id,line_no,material_id,raw_code,raw_name,qty) VALUES
 ('b1310000-0000-0000-0000-000000000001',1,'99310000-0000-0000-0000-000000000001','T31-PANEL','KNX四联面板',18),
 ('b1310000-0000-0000-0000-000000000001',2,'99310000-0000-0000-0000-000000000010','T31-CABLE','Cat6网线',150);
\echo '--- ★挂起：这个编码库里认不上（material_id 留空），它会卡住工程那一步 ---'
INSERT INTO quote_bom_line(bom_id,line_no,material_id,raw_code,raw_name,qty)
VALUES('b1310000-0000-0000-0000-000000000001',3,NULL,'T31-UNKNOWN','某品牌温控器',4);

\echo '--- ★应拦：删原始单的行（"报价里本来有、后来不要了"这件事会消失）---'
DELETE FROM quote_bom_line WHERE bom_id='b1310000-0000-0000-0000-000000000001' AND line_no=1;
\echo '--- ★应拦：改原始单的数量（基线一改，后面所有"原始→现在"的对比全失去参照）---'
UPDATE quote_bom_line SET qty=10
 WHERE bom_id='b1310000-0000-0000-0000-000000000001' AND line_no=1;
\echo '--- ★应拦：把已认到物料的行改挂别的料 ---'
UPDATE quote_bom_line SET material_id='99310000-0000-0000-0000-000000000002'
 WHERE bom_id='b1310000-0000-0000-0000-000000000001' AND line_no=1;
\echo '--- 唯一允许的改动：给挂起的行补建档 ---'
UPDATE quote_bom_line SET material_id='99310000-0000-0000-0000-000000000011'
 WHERE bom_id='b1310000-0000-0000-0000-000000000001' AND line_no=3;
SELECT line_no, raw_code, (material_id IS NOT NULL) AS 已认到物料
  FROM quote_bom_line WHERE bom_id='b1310000-0000-0000-0000-000000000001' ORDER BY line_no;

\echo ''
\echo '════════ ③ 现场变更：★不能删行只能调 0 · SM2 可增可减 ════════'
SET app.actor='工程-小陈';
INSERT INTO bom_change(id,change_no,project_id,bom_id,raised_by,raised_staff_id,raise_note)
VALUES('c1310000-0000-0000-0000-000000000001','BC-T31-01','a1310000-0000-0000-0000-000000000001',
       'b1310000-0000-0000-0000-000000000001','小陈','e1110000-0000-0000-0000-000000000001',
       '业主取消了主卧那组面板，客厅加一个六联');

\echo '--- ★应拦：Additional 加报价单里本来就有的料（摆成两行，采购看到的应采数就错了）---'
INSERT INTO bom_change_line(change_id,material_id,kind,qty_to,reason)
VALUES('c1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000001',
       'additional',5,'客厅还要加几个');
\echo '--- ★应拦：adjust 改一个报价单里没有的料 ---'
INSERT INTO bom_change_line(change_id,material_id,kind,qty_from,qty_to)
VALUES('c1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000002','adjust',0,3);
\echo '--- ★应拦：Additional 不写理由（工程管理只看变量，没理由没法判断）---'
INSERT INTO bom_change_line(change_id,material_id,kind,qty_to)
VALUES('c1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000002','additional',3);

\echo '--- 正常：SM2 阶段可以减（18 → 12），并 Additional 加六联面板 ---'
INSERT INTO bom_change_line(change_id,material_id,kind,qty_from,qty_to) VALUES
 ('c1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000001','adjust',18,12);
INSERT INTO bom_change_line(change_id,material_id,kind,qty_to,reason) VALUES
 ('c1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000002','additional',3,
  '客厅改成六联面板控制窗帘与灯光两路');
\echo '--- ★应拦：同一个料在一张单里加两遍 ---'
INSERT INTO bom_change_line(change_id,material_id,kind,qty_to,reason)
VALUES('c1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000002','additional',2,
       '又想起来还要两个');

\echo ''
\echo '--- ★应拦：报价单还有物料没建档就提交（改了半天最后发现少几个料，前面的活白干）---'
--     先把刚补的那行退回挂起状态是不行的（只读），所以另开一个项目验证这条
INSERT INTO quote_bom(id,project_id,ver_no,uploaded_by)
VALUES('b1310000-0000-0000-0000-000000000009','a1310000-0000-0000-0000-000000000003','V1','采购-王小美');
INSERT INTO quote_bom_line(bom_id,line_no,material_id,raw_code,qty) VALUES
 ('b1310000-0000-0000-0000-000000000009',1,'99310000-0000-0000-0000-000000000010','T31-CABLE',80),
 ('b1310000-0000-0000-0000-000000000009',2,NULL,'T31-NOTYET',6);
INSERT INTO bom_change(id,change_no,project_id,bom_id,raised_by,raised_staff_id)
VALUES('c1310000-0000-0000-0000-000000000009','BC-T31-09','a1310000-0000-0000-0000-000000000003',
       'b1310000-0000-0000-0000-000000000009','小李','e1110000-0000-0000-0000-000000000002');
INSERT INTO bom_change_line(change_id,material_id,kind,qty_from,qty_to)
VALUES('c1310000-0000-0000-0000-000000000009','99310000-0000-0000-0000-000000000010','adjust',80,100);
UPDATE bom_change SET status='pending' WHERE change_no='BC-T31-09';

\echo '--- ★应拦：一行变量都没有就提交 ---'
INSERT INTO bom_change(id,change_no,project_id,bom_id,raised_by,raised_staff_id)
VALUES('c1310000-0000-0000-0000-00000000000a','BC-T31-0A','a1310000-0000-0000-0000-000000000001',
       'b1310000-0000-0000-0000-000000000001','小陈','e1110000-0000-0000-0000-000000000001');
UPDATE bom_change SET status='pending' WHERE change_no='BC-T31-0A';

\echo ''
\echo '--- 正常提交 BC-T31-01 ---'
UPDATE bom_change SET status='pending' WHERE change_no='BC-T31-01';
SELECT change_no, status, raised_phase FROM bom_change WHERE change_no='BC-T31-01';
\echo '--- ★应拦：提交之后还想改明细（暂存阶段随便改，提交之后要改请先退回）---'
UPDATE bom_change_line SET qty_to=8
 WHERE change_id='c1310000-0000-0000-0000-000000000001'
   AND material_id='99310000-0000-0000-0000-000000000001';

\echo ''
\echo '════════ ④ 工程管理审「变量」：★只摆变量，不摆整表 ════════'
SET app.actor='工程管理-陈工';
SELECT change_no, waiting_days AS 等了几天, line_n AS 变量数, blocked_by_gate AS 会被门禁拦,
       delta_text AS 变量 FROM v_bom_change_pending WHERE change_no='BC-T31-01';

\echo '--- ★应拦：批准一张还没提交的单（暂存的是半成品）---'
UPDATE bom_change SET status='approved', reviewed_by='陈工', reviewed_at=now()
 WHERE change_no='BC-T31-0A';

\echo '--- 批准前：待审的变更【不算进应采】（否则采购会照着还没批的数去下单）---'
SELECT material_code, qty_orig AS 原始, qty_pending AS 待审, qty_required AS 应采, qty_gap AS 还要买
  FROM v_project_bom WHERE project_id='a1310000-0000-0000-0000-000000000001' ORDER BY material_code;

\echo '--- 批准 ---'
UPDATE bom_change SET status='approved', reviewed_by='陈工', reviewed_at=now()
 WHERE change_no='BC-T31-01';
\echo '--- ★批准之后：应采立刻跟着变（面板 18→12，六联 0→3）——需求只存一份，全部现算 ---'
SELECT material_code, qty_orig AS 原始, qty_changed_to AS 变更后, qty_required AS 应采, qty_gap AS 还要买
  FROM v_project_bom WHERE project_id='a1310000-0000-0000-0000-000000000001' ORDER BY material_code;

\echo '--- ★应拦：已批准的单不许再改状态（要撤请新开一张反向变更单）---'
UPDATE bom_change SET status='pending' WHERE change_no='BC-T31-01';

\echo ''
\echo '════════ ⑤ ★SM2 之后只能增不能减 ════════'
--   料可能已经发到工地甚至装上去了，这时候往下减，出库单和物料账立刻对不上，而且不会报错
INSERT INTO quote_bom(id,project_id,ver_no,uploaded_by)
VALUES('b1310000-0000-0000-0000-000000000002','a1310000-0000-0000-0000-000000000002','V2','采购-王小美');
INSERT INTO quote_bom_line(bom_id,line_no,material_id,raw_code,qty) VALUES
 ('b1310000-0000-0000-0000-000000000002',1,'99310000-0000-0000-0000-000000000001','T31-PANEL',20),
 ('b1310000-0000-0000-0000-000000000002',2,'99310000-0000-0000-0000-000000000010','T31-CABLE',120);
INSERT INTO bom_change(id,change_no,project_id,bom_id,raised_by,raised_staff_id)
VALUES('c1310000-0000-0000-0000-000000000002','BC-T31-02','a1310000-0000-0000-0000-000000000002',
       'b1310000-0000-0000-0000-000000000002','小陈','e1110000-0000-0000-0000-000000000001');
\echo '--- ★应拦：施工阶段（SM2 已完成）把 20 减到 15 ---'
INSERT INTO bom_change_line(change_id,material_id,kind,qty_from,qty_to)
VALUES('c1310000-0000-0000-0000-000000000002','99310000-0000-0000-0000-000000000001','adjust',20,15);
\echo '--- 正常：只增（20 → 24）---'
INSERT INTO bom_change_line(change_id,material_id,kind,qty_from,qty_to)
VALUES('c1310000-0000-0000-0000-000000000002','99310000-0000-0000-0000-000000000001','adjust',20,24);
UPDATE bom_change SET status='pending' WHERE change_no='BC-T31-02';
UPDATE bom_change SET status='approved', reviewed_by='陈工', reviewed_at=now()
 WHERE change_no='BC-T31-02';
SELECT material_code, qty_required AS 应采 FROM v_project_bom
 WHERE project_id='a1310000-0000-0000-0000-000000000002' ORDER BY material_code;

\echo ''
\echo '════════ ⑤bis ★提单时还能减，审批时 SM2 已完成 —— 审批这一刻必须拦 ════════'
--   这是 §23.7.1 那条门禁真正会发生的场景：现场提单那天 SM2 还没开，
--   等工程管理去审的时候 SM2 已经完成了。
--   ★阶段【现算不定格】就是为了这一刻 —— 定格成「提单时＝sm2」，这张减量单就会被放行，
--     而料可能已经发到工地了，出库单和物料账立刻对不上，还不会报错。
INSERT INTO bom_change(id,change_no,project_id,bom_id,raised_by,raised_staff_id,raise_note)
VALUES('c1310000-0000-0000-0000-000000000003','BC-T31-03','a1310000-0000-0000-0000-000000000001',
       'b1310000-0000-0000-0000-000000000001','小陈','e1110000-0000-0000-0000-000000000001',
       '业主又想去掉两个面板');
INSERT INTO bom_change_line(change_id,material_id,kind,qty_from,qty_to)
VALUES('c1310000-0000-0000-0000-000000000003','99310000-0000-0000-0000-000000000001','adjust',12,8);
UPDATE bom_change SET status='pending' WHERE change_no='BC-T31-03';
\echo '--- ★应拦：退回不写原因（只写"不行"，现场不知道该怎么改）---'
UPDATE bom_change SET status='returned', reviewed_by='陈工', reviewed_at=now()
 WHERE change_no='BC-T31-03';
\echo '--- 这期间 SM2 完成了 ---'
INSERT INTO site_meeting(project_id,sm_no,completed_at)
VALUES('a1310000-0000-0000-0000-000000000001',2,now());
\echo '--- 审批页当场标出「会被门禁拦」（按钮直接禁用并说明为什么）---'
SELECT change_no, phase_now AS 现在什么阶段, blocked_by_gate AS 会被门禁拦
  FROM v_bom_change_pending WHERE change_no='BC-T31-03';
\echo '--- ★应拦：SM2 之后带减量的单批不了 ---'
UPDATE bom_change SET status='approved', reviewed_by='陈工', reviewed_at=now()
 WHERE change_no='BC-T31-03';
\echo '--- 正常：退回并写清原因，让现场重提一张只增的 ---'
UPDATE bom_change SET status='returned', reviewed_by='陈工', reviewed_at=now(),
       return_reason='SM2 已完成进入施工，带减量的单批不了；请重提一张只增的，要减的部分走退料流程'
 WHERE change_no='BC-T31-03';
SELECT change_no, status, left(return_reason,20) AS 退回原因 FROM bom_change WHERE change_no='BC-T31-03';

\echo ''
\echo '════════ ⑥ 库管备料：★占住但不扣库存 ════════'
SET app.actor='库管-老张';
\echo '--- 备料之前的库存 ---'
SELECT code, qty_on_hand AS 库存 FROM v_material_stock WHERE code IN ('T31-PANEL','T31-CABLE') ORDER BY code;

\echo '--- ★应拦：备的比"还要的"多（应采 24 − 已下单 0 = 24，想备 30）---'
INSERT INTO bom_reserve(project_id,material_id,qty,reserved_by)
VALUES('a1310000-0000-0000-0000-000000000002','99310000-0000-0000-0000-000000000001',30,'老张');
\echo '--- ★应拦：现货不够还想先占后补（库里只有 30 面板，两个项目都想备）---'
INSERT INTO bom_reserve(project_id,material_id,qty,reserved_by)
VALUES('a1310000-0000-0000-0000-000000000002','99310000-0000-0000-0000-000000000001',24,'老张');
INSERT INTO bom_reserve(project_id,material_id,qty,reserved_by)
VALUES('a1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000001',12,'老张');
\echo '--- 正常：给 P1 备 6 个（现货 30 − P2 已备 24 = 6）---'
INSERT INTO bom_reserve(project_id,material_id,qty,reserved_by)
VALUES('a1310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000001',6,'老张');
INSERT INTO bom_reserve(project_id,material_id,qty,reserved_by)
VALUES('a1310000-0000-0000-0000-000000000002','99310000-0000-0000-0000-000000000010',120,'老张');

\echo '--- ★备料之后库存一动不动（真正扣是在出库那一刻）---'
SELECT code, qty_on_hand AS 库存 FROM v_material_stock WHERE code IN ('T31-PANEL','T31-CABLE') ORDER BY code;
\echo '--- 物料账：还要买 ＝ 应采 − 已下单 − 已备 ---'
SELECT material_code, qty_required AS 应采, qty_ordered AS 已下单, qty_reserved AS 已备,
       qty_gap AS 还要买, qty_free_stock AS 仓库还能顶
  FROM v_project_bom WHERE project_id='a1310000-0000-0000-0000-000000000002' ORDER BY material_code;

\echo ''
\echo '════════ ⑦ ★买多了：工程后来减了量，那批货的钱已经花出去了 ════════'
--   原来那行显示绿色「齐了」，18 件的钱就悄悄留在项目成本里，谁也不会发现
INSERT INTO purchase_order(id,po_no,source_type,ref_project_id,ordered_at,expected_at,status)
VALUES('d1310000-0000-0000-0000-000000000002','PO-T31-2','project','a1310000-0000-0000-0000-000000000001',
       now()-interval '5 days',current_date+7,'ordered');
INSERT INTO purchase_order_line(po_id,material_id,qty_ordered,unit_cost_aud)
VALUES('d1310000-0000-0000-0000-000000000002','99310000-0000-0000-0000-000000000001',18,85.20);
SELECT material_code, qty_required AS 应采, qty_ordered AS 已下单, qty_reserved AS 已备,
       qty_gap AS 还要买, qty_over AS ★买多了
  FROM v_project_bom WHERE project_id='a1310000-0000-0000-0000-000000000001'
   AND material_code='T31-PANEL';
\echo '--- 项目总览：现在卡在哪 ---'
SELECT pj_code, bom_ver, gap_total AS 还要买, over_total AS 买多了, stuck_where AS 卡在哪
  FROM v_project_bom_summary WHERE project_id IN
   ('a1310000-0000-0000-0000-000000000001','a1310000-0000-0000-0000-000000000002') ORDER BY pj_code;

\echo ''
\echo '════════ ⑧ 提货人：★没有澳洲手机号就不许通知也不许出库 ════════'
\echo '--- ★应拦：座机（收不到短信，填了就是永远收不到）---'
INSERT INTO party_pickup(project_id,trade,contact_name,phone,created_by)
VALUES('a1310000-0000-0000-0000-000000000002','builder','Mike','0298765432','老张');
\echo '--- ★应拦：境外号（提货人要收中英双语短信，必须澳洲号）---'
INSERT INTO party_pickup(project_id,trade,contact_name,phone,created_by)
VALUES('a1310000-0000-0000-0000-000000000002','builder','Mike','+8613800000000','老张');
\echo '--- 正常：三种写法都归一成 +61 4xx xxx xxx（同一个人三种写法，去重永远对不上）---'
INSERT INTO party_pickup(id,project_id,trade,company,contact_name,phone,lang,created_by) VALUES
 ('91310000-0000-0000-0000-000000000001','a1310000-0000-0000-0000-000000000002','builder','BuildCo','Mike','0433 000 333','both','老张'),
 ('91310000-0000-0000-0000-000000000002','a1310000-0000-0000-0000-000000000002','electrician','Spark','Tony','+61422000222','both','老张'),
 ('91310000-0000-0000-0000-000000000003','a1310000-0000-0000-0000-000000000002','other','泥水','Sam','0061455000555','en','老张');
SELECT contact_name, phone FROM party_pickup
 WHERE project_id='a1310000-0000-0000-0000-000000000002' ORDER BY contact_name;
\echo '--- ★应拦：同一个项目同一个号录两个人（短信回 Y 分不清是谁回的）---'
INSERT INTO party_pickup(project_id,trade,contact_name,phone,created_by)
VALUES('a1310000-0000-0000-0000-000000000002','other','另一个人','0433000333','老张');

\echo ''
\echo '════════ ⑨ 通知来提货（出库之前 · 库管手工）≠ 催提货确认（出库之后）════════'
\echo '--- ★应拦：给第三方发纯中文（他们多半不看中文，发中文等于没发）---'
INSERT INTO wh_call(project_id,pickup_id,to_name,to_phone,lang,wh_address,wh_hours,called_by)
VALUES('a1310000-0000-0000-0000-000000000002','91310000-0000-0000-0000-000000000001','Mike','0433000333',
       'zh','Unit 3, 12 Chaplin Dr','Mon–Fri 8:00–16:30','老张');
\echo '--- 正常：中英双语 + 仓库地址与营业时间定格进短信 ---'
INSERT INTO wh_call(id,project_id,pickup_id,to_name,to_phone,lang,wh_address,wh_hours,called_by)
VALUES('81310000-0000-0000-0000-000000000001','a1310000-0000-0000-0000-000000000002',
       '91310000-0000-0000-0000-000000000001','Mike','0433000333','both',
       (SELECT value_text FROM eng_setting WHERE key='wh_address'),
       (SELECT value_text FROM eng_setting WHERE key='wh_hours'),'老张');
SELECT to_name, to_phone, lang, waited_days AS 等了几天, overdue AS 超期
  FROM v_wh_call_open WHERE project_id='a1310000-0000-0000-0000-000000000002';

\echo ''
\echo '════════ ⑩ 出库：★没手机号不许出库 · S2 门禁 ════════'
\echo '--- ★应拦：提货人没手机号（短信发不出去等于没发，货只会一直堆在仓库）---'
INSERT INTO project_party(id,project_id,trade,company,contact_name)
VALUES('cc310000-0000-0000-0000-000000000001','a1310000-0000-0000-0000-000000000002',
       'builder','NoPhoneCo','无号先生');
INSERT INTO stock_out(out_no,project_id,receiver_party_id,created_by)
VALUES('OUT-T31-X','a1310000-0000-0000-0000-000000000002','cc310000-0000-0000-0000-000000000001','老张');

\echo '--- 正常出库（S2 已结清 + 提货人有澳洲手机号）---'
INSERT INTO stock_out(id,out_no,project_id,receiver_pickup_id,created_by)
VALUES('50310000-0000-0000-0000-000000000001','OUT-T31-1','a1310000-0000-0000-0000-000000000002',
       '91310000-0000-0000-0000-000000000001','老张');
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud)
VALUES('50310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000001',24,85.20);
SELECT out_no, receiver_name AS 提货人, receiver_phone AS 归一后的号码
  FROM stock_out WHERE out_no='OUT-T31-1';
\echo '--- ★出库那一刻才真正扣库存；备料同时销掉（不然同一批货被扣两遍）---'
SELECT code, qty_on_hand AS 库存 FROM v_material_stock WHERE code='T31-PANEL';
SELECT p.code AS 项目, m.code AS 物料, r.qty, (r.released_at IS NOT NULL) AS 已销
  FROM bom_reserve r JOIN project p ON p.id=r.project_id JOIN material m ON m.id=r.material_id
 WHERE m.code='T31-PANEL' ORDER BY p.code;

\echo ''
\echo '════════ ⑪ ★SM2 预提线材窄通道：四道锁 ════════'
--   SM2 那天我方人员要带线材去现场，可那时 S2 物料款还没开（S2 要 SM3 完成才解锁），
--   照原门禁一定被拦下，工地就停在那儿。开一条窄通道，四道锁死。
\echo '--- ★应拦：普通出库，S2 未结清（★这条必须照旧卡死，不能因为开了窄通道就松了）---'
INSERT INTO stock_out(out_no,project_id,receiver_staff_id,created_by)
VALUES('OUT-T31-Y','a1310000-0000-0000-0000-000000000003','e1110000-0000-0000-0000-000000000001','老张');
\echo '--- ★应拦：SM2 预提但用途写不清（≥4 字）---'
INSERT INTO stock_out(out_no,project_id,receiver_staff_id,sm2_cable_release,sm2_purpose,created_by)
VALUES('OUT-T31-Z','a1310000-0000-0000-0000-000000000003','e1110000-0000-0000-0000-000000000001',
       true,'带线','老张');
\echo '--- ★应拦：SM2 预提给第三方（第三方一律等 S2 结清）---'
INSERT INTO party_pickup(id,project_id,trade,contact_name,phone,created_by)
VALUES('91310000-0000-0000-0000-000000000009','a1310000-0000-0000-0000-000000000003',
       'electrician','Leo','0466000666','老张');
INSERT INTO stock_out(out_no,project_id,receiver_pickup_id,sm2_cable_release,sm2_purpose,created_by)
VALUES('OUT-T31-W','a1310000-0000-0000-0000-000000000003','91310000-0000-0000-0000-000000000009',
       true,'SM2 现场布线用','老张');
\echo '--- 正常：我方人员 + 用途写清 → 放行 ---'
INSERT INTO stock_out(id,out_no,project_id,receiver_staff_id,sm2_cable_release,sm2_purpose,created_by)
VALUES('50310000-0000-0000-0000-000000000002','OUT-T31-2','a1310000-0000-0000-0000-000000000003',
       'e1110000-0000-0000-0000-000000000001',true,'SM2 当天现场布线，先带 60m Cat6 过去','老张');
\echo '--- ★应拦：走这条通道却想提面板（钱的大头照旧卡 S2）---'
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud)
VALUES('50310000-0000-0000-0000-000000000002','99310000-0000-0000-0000-000000000001',2,85.20);
\echo '--- 正常：只提线材，★照样定格单价（按 S4 结算，一分钱不会丢）---'
INSERT INTO stock_out_line(stock_out_id,material_id,qty,unit_cost_aud)
VALUES('50310000-0000-0000-0000-000000000002','99310000-0000-0000-0000-000000000010',60,1.80);
SELECT o.out_no, m.code AS 物料, l.qty, l.unit_cost_aud AS 定格单价
  FROM stock_out_line l JOIN stock_out o ON o.id=l.stock_out_id JOIN material m ON m.id=l.material_id
 WHERE o.out_no='OUT-T31-2';

\echo ''
\echo '════════ ⑫ 出货单（从派工排班来）════════'
SET app.actor='工程-陈工';
\echo '--- ★应拦：SM2 预提出货单没写是谁去提 ---'
INSERT INTO mat_req(req_no,project_id,job_kind,is_sm2_cable,purpose,raised_by)
VALUES('MR-T31-X','a1310000-0000-0000-0000-000000000003','sm',true,'SM2 现场布线用','陈工');
\echo '--- ★应拦：SM2 预提挂在安装排班上（只能挂 Site Meeting）---'
INSERT INTO mat_req(req_no,project_id,job_kind,for_staff_id,is_sm2_cable,purpose,raised_by)
VALUES('MR-T31-Y','a1310000-0000-0000-0000-000000000003','install',
       'e1110000-0000-0000-0000-000000000001',true,'SM2 现场布线用','陈工');
\echo '--- ★应拦：SM2 预提用途少于 4 字 ---'
INSERT INTO mat_req(req_no,project_id,job_kind,for_staff_id,is_sm2_cable,purpose,raised_by)
VALUES('MR-T31-Z','a1310000-0000-0000-0000-000000000003','sm',
       'e1110000-0000-0000-0000-000000000001',true,'带线','陈工');
\echo '--- 正常出货单 ---'
INSERT INTO mat_req(id,req_no,project_id,job_kind,need_by,for_staff_id,raised_by)
VALUES('71310000-0000-0000-0000-000000000001','MR-T31-1','a1310000-0000-0000-0000-000000000002',
       'install',current_date+2,'e1110000-0000-0000-0000-000000000001','陈工');
INSERT INTO mat_req_line(req_id,material_id,qty)
VALUES('71310000-0000-0000-0000-000000000001','99310000-0000-0000-0000-000000000010',120);
\echo '--- ★应拦：SM2 预提出货单里放面板 ---'
INSERT INTO mat_req(id,req_no,project_id,job_kind,for_staff_id,is_sm2_cable,purpose,raised_by)
VALUES('71310000-0000-0000-0000-000000000002','MR-T31-2','a1310000-0000-0000-0000-000000000003',
       'sm','e1110000-0000-0000-0000-000000000001',true,'SM2 当天现场布线要用','陈工');
INSERT INTO mat_req_line(req_id,material_id,qty)
VALUES('71310000-0000-0000-0000-000000000002','99310000-0000-0000-0000-000000000001',2);
\echo '--- ★应拦：标缺货却不填交期（不填就只是「缺货」两个字，工程既不知道等多久也没法改排班）---'
UPDATE mat_req SET status='short' WHERE req_no='MR-T31-1';
\echo '--- 正常：缺货 + 问采购拿到 lead time 填回来 ---'
UPDATE mat_req SET status='short',
       lead_time_note='网线已下单 PO-T31-3，供应商说 ETA 08/22，先按 08/23 排班'
 WHERE req_no='MR-T31-1';
SELECT req_no, status, lead_time_note FROM mat_req WHERE req_no='MR-T31-1';

\echo ''
\echo '════════ ⑬ 库管「项目出库状态」：★一个项目只落一类 ════════'
SELECT pj_code, state_tab AS 状态页签, gap_total AS 还要买, open_req_n AS 出货单,
       called_not_come_n AS 叫了没来, no_ack_n AS 没回执
  FROM v_wh_project_state WHERE project_code LIKE 'KX-T31-%' ORDER BY pj_code;

\echo ''
\echo '════════ ⑭ 采购需求：★项目料由工程人员提（推翻 v0.36 的库管下达）════════'
SET app.actor='采购-王小美';
\echo '--- ★应拦：v0.36 的旧来源值 project_demand 已经不存在了（带上项目，确保拦它的是来源枚举本身）---'
INSERT INTO purchase_req(req_no,source,project_id,material_id,qty,why,raised_by)
VALUES('RQ-T31-X','project_demand','a1310000-0000-0000-0000-000000000001',
       '99310000-0000-0000-0000-000000000001',10,'按方案 BOM 提料','库管 老张');
\echo '--- ★应拦：项目料却没有项目 ---'
INSERT INTO purchase_req(req_no,source,material_id,qty,why,raised_by)
VALUES('RQ-T31-Y','sm2_change','99310000-0000-0000-0000-000000000001',10,'SM2 现场加的','工程 小陈');
\echo '--- 正常：库管补货是公司级（这一档不变）---'
INSERT INTO purchase_req(req_no,source,material_id,qty,why,raised_by)
VALUES('RQ-T31-1','warehouse_restock','99310000-0000-0000-0000-000000000001',40,
       '库存低于红线 20（C1 常备件）','库管（系统现算）');
\echo '--- 正常：工程人员提的项目料 ---'
INSERT INTO purchase_req(req_no,source,project_id,material_id,qty,why,raised_by)
VALUES('RQ-T31-2','build_add','a1310000-0000-0000-0000-000000000002',
       '99310000-0000-0000-0000-000000000002',3,'现场加了一组六联面板，工程管理已批','工程 小陈');
\echo '--- 正常：运维缺料（维护料不在报价物料账里，只有它单独进采购需求）---'
INSERT INTO purchase_req(req_no,source,project_id,material_id,qty,why,raised_by)
VALUES('RQ-T31-3','maintenance','a1310000-0000-0000-0000-000000000002',
       '99310000-0000-0000-0000-000000000011',2,'维护换件：HDMI 线烧了两根','运维 小周');
SELECT req_no, source, (project_id IS NOT NULL) AS 有项目, status FROM purchase_req
 WHERE req_no LIKE 'RQ-T31-%' ORDER BY req_no;

\echo ''
\echo '════════ ⑮ 断言复核：这一版新增的九条 ════════'
SELECT code, label, violations FROM fn_run_assertions()
 WHERE code LIKE 'INV-BOM-%' OR code IN ('INV-WH-02','INV-WH-03','INV-MT-01','INV-MT-02','INV-PC-02')
 ORDER BY code;
