-- =====================================================================
--  KONNEXT 办公管理平台 · 契约快照 v0.39
--  v0.39 变更（2026-08-10 · 部门授权，用户当天提出）：
--   ★最高管理者默认对【别的部门】只读 —— 他是唯一能写所有部门的角色，
--     也就是唯一可能和别人撞车的人。乐观锁是「撞了才报错」，这一版改成【根本不让它撞】。
--   ① dept_delegation 部门授权表：
--      · 休假授权 leave —— 部门负责人【本人】点，★到期日必填（忘了收回就等于白设）
--      · 强制接管 takeover —— 联系不上时的出口：★原因 ≥10 字 + 短信通知本人 + 日志标红
--      · 一个部门同时只能有一条生效的授权；授权记录只增不删
--   ② 写权限重写（一处改、全库 32 处策略生效）：
--      fn_can_write = 本部门的人(fn_in_dept) OR (管理员 AND fn_admin_may_write)
--      ★fn_in_dept 是新加的 —— fn_has_dept 里第一句就是 fn_is_admin()，
--        用它判断「是不是本部门的人」，管理员永远混在里面，授权门形同虚设
--      ★「本职 vs 代部门」的划分是天然的，不手列清单：
--        表在 table_ownership 里有部门归属 → 代部门 → 要授权
--        没有部门归属（决策看板/账号权限/断言定义/登记表）→ 本职 → 照旧
--   ③ 删除策略同改（删比改更危险）：自动扫全库把 USING(fn_is_admin()) 换成 fn_can_delete()
--   ④ 断言 +3（95→98）：INV-DEL-01..03
--  （原 v0.38 头注如下）
--  KONNEXT 办公管理平台 · 契约快照 v0.38
--  v0.38 变更（2026-08-10 · 派工排班表落库 —— 清欠账表第 1 条，规则见决策记录 §16 四十一~四十四轮）：
--   ★背景：UI 上那张周视图排班表从四十一轮做到现在，契约里一直没有。
--     `work_log` 是【打卡】不是【排班】—— 一个是实际发生的，一个是计划要发生的。
--     两者分开，「计划 vs 实际」才对得上；只有打卡，就永远看不出「派了工没去」。
--   ① sched_task_type 排班任务类型：六类内建不可删（与工时/倒休算法绑死）+ 自建；
--      ★被排班用过的删不掉；每类带【合理时长】（跟客户解释工期的依据，只提示不拦）
--   ② eng_schedule 派工排班表 —— 门禁八条：
--      · 起止时间 15 分钟一档（05:00~23:45），★时长＝区间自动算，不手填
--      · ★同一人同一天两段不许重叠（一个人不能同时在两个工地）
--      · ★非倒休任务必须关联项目（休假不是工作）
--      · ★倒休余额不足直接拦（含同期其他已排的倒休）
--      · ★不许给过去的日期排班 —— 事后补计划＝让「计划 vs 实际」永远相等，那个对比就废了
--      · ★过去的排班不许改不许删（历史就是历史）
--      · ★锁定（按天/整周）之后要先解锁才能改，解锁留痕
--      · ★维护：上次上门没填剩余工作，这次派不了工
--   ③ daily_report_line 每日上报【分段】（一人一天可跑多个项目）：
--      「今天做了什么」+ ★「还剩什么没做」。★没有它，排班的「剩余工作自动带出」与
--      「维护没填剩余就拦派工」两条门禁都落不了 —— 原 daily_report 只挂人+日期，没有项目也没有剩余
--   ④ 排班 → 出货单（§23.九）：安装勾「去仓库办提货」· SM 勾「带线材」· 维护填「这次带什么」
--      → 生成 mat_req 交库管。★入口在排班，因为谁去提、什么时候提只有排班这一刻才知道
--   ⑤ 运维作废维护单 → 连带取消对应排班并留痕（§18）
--   ⑥ 断言 +5（90→95）：INV-SCH-01..05
--  （原 v0.37 头注如下）
--  KONNEXT 办公管理平台 · 契约快照 v0.37
--  v0.37 变更（2026-08-10 · 项目物料账四段链条 + 提货 + 部门试用反馈，见决策记录 §23）：
--   ★这一版最重要的一条口径【推翻了 v0.36】：
--     项目料的提单人从【库管】改成【工程人员】。方案和现场情况工程人员最清楚，
--     库管管的是仓库不是项目。purchase_req.source 四档重写、INV-PC-02 与 30 号回归同改。
--     库管补货那一档不变（C1 低于红线，系统现算）。
--   ① 项目物料账四段链条落库（§23）：
--      quote_bom / quote_bom_line   报价原始单，版本化 · ★只读（行永远不删，只能调 0）
--                                   ★认不上的编码挂起（material_id 为空），卡住下一步
--      bom_change / bom_change_line 现场变更：暂存 draft → 提交 pending → 批准/退回
--                                   ★SM2 可增可减、施工中只能增 · Additional 必写理由
--                                   ★同一个料不许重复加 · 报价单里有的不许再 Additional
--      bom_reserve                  库管备料：★占住但不扣库存（真正扣在出库那一刻）
--      mat_req / mat_req_line       出货单（从排班来）：够→出库 · 不够→同时提醒采购与工程
--      v_project_bom                ★项目料需求只存一份，全部由物料账现算
--                                   （原始+已批变更=应采 −已下单 −已备 =还要买；负数=★买多了）
--   ② 提货与出库（§23.八~九）：
--      party_pickup   提货人两类（第三方·工地 / 我方·办公室）★没手机号不许通知也不许出库
--      wh_call        「通知来提货」（出库前 · 库管手工）≠「催提货确认」（出库后 · 等回 YES）
--      fn_norm_au_mobile / fn_is_au_mobile  澳洲手机号归一 + 校验（★座机收不到短信）
--      ★SM2 预提线材窄通道：四道锁（只我方 · 只线材 · 用途≥4字 · 照样定格单价按 S4 结），
--        S2 门禁对其余出库【照旧卡死】
--   ③ 部门试用反馈落库（§九·补四、补五）：
--      M1 maintenance_case.reported_at 改必填（★原来允许留空＝那单退出 SLA 统计，
--         真正响应慢的最容易漏掉，报表永远好看）+ 新列 issue_since（问题首次出现，可未知）
--      M3 pri P0~P3 + 四档 SLA 键（超本档自动进待办）
--      M4 研发排查：rd_conclusion / rd_skip_reason + 状态 'rd' +
--         ★上门前必须先有排查结论（或明确标「无需排查」并写原因）；
--         work_log.work_type 加 'remote_diag'（远程排查工时进成本）
--      M5 finish_note 完结交财务（≥10 字，财务照着往发票上写）
--      E5 project_note 项目备忘（内容≥6字 + ★跟进日期必填，取最近一条当「下次跟进」）
--      E6 project.pj_level A/B/C + ★分级原因必填 ≥6 字（只影响排序与提醒，不改任何门禁）
--   ④ fn_apply_optlock()：v0.35 那个末尾 DO 块收成函数，与 fn_apply_view_conventions()
--      配成一对 —— 以后任何一轮加完表/视图，末尾各调一次即可，不必记住去哪儿重跑
--   ⑤ 断言 +9（81→90）：INV-BOM-01..05 · INV-WH-02..03 · INV-MT-01..02
--  （原 v0.36 头注补记：v0.36 落库时漏了写头注，此处补上）
--  KONNEXT 办公管理平台 · 契约快照 v0.36
--  v0.36 变更（2026-08-04 · 全面回归查出的 RLS 大洞 + 采购库管落库）：
--   ① 补 RLS：20 张表一条策略都没有（auth_otp 能读别人验证码 / audit_log 可被改删 /
--      account_department 改自己部门＝提权）。原 INV-SEC-07 手列 10 张表，一次都没提过 ——
--      已加 INV-SEC-09 自动扫全库兜底。现在没开 RLS 的表 0 张。
--   ② 采购与库管落库七件：supplier · material_price_log · 采购单定格汇率 · purchase_req ·
--      rma 四态 · goods_receipt_diff · 阈值与选项键
--   ③ fn_apply_view_conventions()：新增视图之后调一次（security_invoker + pj_label）
--   ★同时修掉一个真 bug：集中采购到货标不了（fn_notify_dept 没标 scope=company），
--     它一直在把假拦截混进回归计数
--  （原 v0.35 头注如下）
--  KONNEXT 办公管理平台 · 契约快照 v0.35
--  v0.35 变更（2026-08-03 · 并发控制专版，规则见决策记录 §17）：
--   ★背景（用户提的真实场景）：部门管理员在办公室电脑打开页面没关，回家用另一台改了东西，
--     同事碰了办公室那台 —— 那台还挂着他的登录态，屏幕上是旧数据。
--     纯阅读不会出事（读不写库），出事的是「同事在旧页面上点了一下」：
--     旧快照覆盖新数据，不报错、只是数字悄悄错了 —— 正是本项目最怕的那类 bug。
--   ① 乐观锁从 project 一张表推广到<全部有 UPDATE 策略的业务表>（42 张）：
--      每张加 version（自增）+ updated_at（自动刷新）；写操作带 app.expected_version，
--      对不上就 RAISE 中文原句拒绝。不设该 GUC 时放行 —— 系统函数与触发器内部更新照常走。
--   ② 通用触发器 trg_row_touch / trg_row_optlock 取代 project 专用两只（专用函数删除）
--   ③ 断言 +1（75→76）：INV-CC-01 —— 凡是有 UPDATE 策略的表都必须挂乐观锁触发器
--      （自动扫全库，以后新增表忘了挂，断言直接报违规，不靠人记）
--  ⚠ v0.35 只清并发这一项；工程线欠账（attendance / eng_document(+version) / 三张选项表）
--    与发送人身份四键留待 v0.36。
--  （原 v0.34 头注如下）
--  KONNEXT 办公管理平台 · 契约快照 v0.34
--  v0.34 变更（2026-08-02 · 财务 UI 定稿清欠账 + 工程追加变更拍板，规则见决策记录 §7.3/§15）：
--   ① variation：origin CHECK('sm3','post_sm3','unreturned'——系统未退料值) + labor_hours_est（工程填，只进成本）+
--      追加告知（payer_notified_at 登记即发 / payer_sms_replied_at 仅记录）+
--      门禁：post_sm3 需 SM3 完成且项目交付前；来源登记后不可改
--   ② expense_claim：类别收窄三值正名 material/tool/transport（材料补购/工具采购/交通递送）；
--      删「已付」状态与付款列——付款不走本系统（相关视图同步改）
--   ③ daily_payroll：补录收紧——backfill_reason_cat 五类 + 说明≥10字 + 补录人必填（门禁）；
--      表归属改 eng_mgmt（补录=工程负责人写，财务只读）
--   ④ 新表 leave_request 倒休休假单（短信回 Y 自动扣 / 强制扣减留痕）+ toil_ledger 透支门禁
--   ⑤ 新表 todo_action_log 待办三动作留痕（已知悉/处理/搁置，只增不改，RLS 限本人行）
--   ⑥ household_member / project_party / eng_staff 补 email 列（选填不强制）
--   ⑦ 断言 +2（73→75）：INV-TOIL-01 倒休余额不为负 · INV-EXP-01 已批准报销必有收据
--  （原 v0.33 头注如下）
--  KONNEXT 办公管理平台 · 契约快照 v0.33
--  v0.33 变更（2026-08-02 · 财务收款线 UI 已定口径对齐，规则见决策记录 §15；工资线待续）：
--   ① 新表 payment_remind_log 催款记录（渠道 sms/email/both · 语言 zh/en · 级别 normal/final ·
--      发送人留痕）+ 门禁：已烂尾项目不再关联催款（P0001 原句）
--   ② project 新增付款人指定六列：payer_source（contact1/contact2/rel/builder/electrician）
--      + 姓名/电话/邮箱/公司/title 快照（财务从售前采集的候选里选定后落格）
--   ③ eng_setting 财务键：gst_bank_pct=10 / gst_cash_pct=0 / suspend_server_days=90
--      （write_depts=finance）；overdue_days 开放给财务共写
--   ④ 催款模版 12 键（常规/最终 × 中/英 × 短信/邮件标题/邮件正文，write_depts=finance，
--      变量花括号占位由应用层渲染；不含项目昵称——对外用完整地址）
--  （原 v0.32 头注如下）
--  KONNEXT 办公管理平台 · 契约快照 v0.32
--  v0.32 变更（2026-08-01 · 售前 UI 样板定稿对齐，规则见决策记录 §14）：
--   ① 售前七步 → 6+1：step1..6 = 接洽中/设计中/报价中/修订中/待签约/已签约 的定格日期；
--      第⑦红勾=已流失=status 'bid_lost'（原「已流失」并入，中文标签统一为「已流失」）；
--      status 枚举删去 to_contact（6+1 里没有「待联系」）；停留一律现算
--   ② quote_version / quote_status 废弃删除；新增 est_quote_low/high 预测报价范围（立项第5步填）
--   ③ project 新增 财务注释/工程注释 + 已读回执共六列（售前填，对方部门必读，读了落谁/何时）
--   ④ eng_setting 新增 pre_stage_remind_days（默认3天，write_depts=售前）
--      与 6 个下拉选项键（角色/工种/房屋类型/施工阶段/楼层用途/屋顶——售前设置页维护，不写死；
--      对应放开 project.house_type/build_stage/roof_type 的硬编码 CHECK，build_stage 保持必填）
--   ⑤ 新增视图 v_presales_pipeline（售前大表/内生提醒数据源，全现算）
--      + fn_presales_reminders_today()（每天提醒生成：一项目一条，不累积）
--  v0.31 变更（2026-07-30）：
--   ① eng_setting 新增 write_depts 列（按键控制写权限）；
--      加班倍数四键开放给财务；新增订阅五档年费四键（运维填）
--   ② eng_setting / eng_staff 启用 RLS（补缺口：此前只登记未强制）
--   ③ 新增视图 v_subscription_fee_standard（五档年费标准）
--  范围：v0.13 全部 + 采购下单|入库|出库(落项目)|提货短信确认；库存现算
--  任务四类，按现场先后：① SM ② 安装调试 ③ 交付 ④ 技术维护
--        + 通用能力(工时考勤 work_log / 通知 notification)
--  数据库：PostgreSQL 14+ / Supabase
--
--  设计原则（本项目一贯）：
--   1) 只增不改：原始事实 append，当前状态尽量派生（视图现算）
--   2) 字段级所有权：每个数据只有一个写入方，从根上杜绝覆盖冲突
--   3) 定格的落库、会变的现算
--   4) 卡点(门禁)由 DB 触发器强制，UI 只是第二道
--   5) 外部系统(报价/设计)只读单向镜像，先手填占位
--   6) 通用能力(考勤、通知)抽离复用，不做成某模块专属
--
--  说明：本版仍是“快照”，字段以占位为主(JSONB / text)，重在【关系】与【卡点】。
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =====================================================================
--  第一部分：售前立项（沿用 v0.1，补充报价对接占位 + 预测工时 + 工程利润率）
-- =====================================================================

CREATE TABLE project (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code              text UNIQUE NOT NULL,
    name              text,

    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    updated_by        text,

    -- 地址
    addr_street       text,
    addr_suburb       text,
    addr_state        text CHECK (addr_state IN ('NSW','VIC','QLD','SA','WA','TAS','ACT','NT')),
    geo_lat           numeric(9,6),      -- 项目坐标：地图 + 考勤围栏圆心
    geo_lng           numeric(9,6),
    geofence_radius_m integer NOT NULL DEFAULT 100,   -- 考勤围栏半径(米)，工程负责人可调

    -- 联系人 ×3（平铺）
    o1_name text, o1_nickname text, o1_phone text, o1_email text, o1_role text,
    o2_name text, o2_nickname text, o2_phone text, o2_email text, o2_role text,
    rel_name text, rel_nickname text, rel_phone text, rel_email text, rel_role text,

    -- 佣金
    commission_type   text CHECK (commission_type IN ('percent','fixed')),
    commission_value  numeric(12,2),

    -- 房屋
    usage_type        text CHECK (usage_type IN ('self_live','sell','mixed','commercial')),
    -- v0.32：房屋类型/施工阶段/屋顶 不再硬编码枚举 —— 选项列表在 eng_setting
    --   （pre_house_types / pre_build_stages / pre_floor_uses / pre_roof_types，售前设置页可增减）
    house_type        text,
    build_stage       text NOT NULL,   -- 必填不变；取值来自 pre_build_stages 选项键
    build_stage_other text,

    -- 楼层结构 ×5
    floor_basement    text DEFAULT 'none',
    floor_l1          text DEFAULT 'none',
    floor_l2          text DEFAULT 'none',
    floor_l3          text DEFAULT 'none',
    floor_l4p         text DEFAULT 'none',
    floor_other_note  text,
    roof_type         text,
    roof_other_note   text,

    -- 售前 6+1（v0.32 定稿对齐）：6 个顺序勾的定格日期 —— 勾到哪 = 处于哪，
    -- 反选回退时清掉后面的勾；停留天数一律现算（见 v_presales_pipeline），不落库
    step1_intro_at    timestamptz,   -- ① 接洽中
    step2_design_at   timestamptz,   -- ② 设计中
    step3_review_at   timestamptz,   -- ③ 报价中
    step4_draft_at    timestamptz,   -- ④ 修订中
    step5_revise_at   timestamptz,   -- ⑤ 待签约（报价单号/预测工时/签约定价 此时一并填）
    step6_signed_at   timestamptz,   -- ⑥ 已签约 = 方案定版信号 → 通知财务开 S1
                                     -- 第⑦红勾 = 已流失 = status 'bid_lost'，不是时间列
    step7_deposit_at  timestamptz,   -- 财务写入定金时间(占位，非售前勾)

    -- 关键钱数
    contract_price    numeric(14,2), -- 签约价(售前手填)
    deposit_amount    numeric(14,2), -- 定金(仅财务可写)
    deposit_paid_at   timestamptz,

    -- ★ 报价对接占位（外部报价系统唯一写入；现在手填 + 来源标记）
    quote_ext_id      text,          -- 报价系统里的项目/单号
    quote_amount      numeric(14,2), -- 报价金额
    -- v0.32：quote_version / quote_status 废弃删除（售前定稿：报价无版本概念）
    est_quote_low     numeric(14,2), -- 预测报价范围·低（立项第5步填，售前写）
    est_quote_high    numeric(14,2), -- 预测报价范围·高
    CONSTRAINT chk_est_quote_range CHECK (est_quote_low IS NULL OR est_quote_high IS NULL
                                          OR est_quote_low <= est_quote_high),
    quote_synced_at   timestamptz,   -- 最后同步时间
    quote_snapshot    jsonb,         -- 报价/BOQ 明细快照(将来 API 落这里)
    quote_source      text NOT NULL DEFAULT 'manual'
                        CHECK (quote_source IN ('manual','quote_system')),  -- 手填/系统同步

    -- ★ 预测人工时长（分母，来自报价系统；现在手填，放签约价后）
    planned_labor_hours numeric(10,2),  -- 应有人工工时
    planned_labor_source text NOT NULL DEFAULT 'manual'
                        CHECK (planned_labor_source IN ('manual','quote_system')),

    -- ★ 工程利润率（交付时定格落库；推进中的值用视图现算）
    eng_margin_locked   numeric(6,3),   -- 交付当天锁定的工程利润率(%)，未交付为 NULL
    eng_margin_locked_at timestamptz,

    -- ★ 安装整体完工（剩余清零 + 负责人确认，两个都要）
    install_completed_at timestamptz,
    install_completed_by uuid,          -- 工程负责人(eng_staff)，FK 后置

    -- ★ 交付（handover_job 完成时回写；运维/工程成本分界线）
    handover_at       timestamptz,

    -- ★ 免责维保（售前签约时手填：默认3个月，可加到12个月）
    --   起算=交付之日；期内非人为故障，人工+物料全免，成本计入维保成本
    free_warranty_months integer NOT NULL DEFAULT 3
                        CHECK (free_warranty_months BETWEEN 0 AND 12),

    -- ★ 拒付停服（财务手动标；项目级全面停服，不是单张停）
    service_suspended_at  timestamptz,
    service_suspended_by  text,
    service_suspended_reason text,
    service_resumed_at    timestamptz,

    -- ★ v0.33 付款人指定（二十二轮用户定）：候选=售前收集的 联系人1/2·干系人·Builder·电工，
    --   财务下拉选定并保存 —— 快照落格（谁/电话/邮箱/公司/title），此后请款/催款/通知/发票抬头都用这个人
    payer_source  text CHECK (payer_source IN
                    ('contact1','contact2','rel','builder','electrician') OR payer_source IS NULL),
    payer_name    text,
    payer_phone   text,
    payer_email   text,
    payer_company text,
    payer_title   text,

    -- ★ v0.32 双注释（售前填 → 对方部门必读；已读回执落 谁/何时，UI 显示 已读✓/未读）
    note_finance         text,
    note_finance_read_by text,
    note_finance_read_at timestamptz,
    note_eng             text,
    note_eng_read_by     text,
    note_eng_read_at     timestamptz,

    -- 当前状态
    -- ★ v0.27：补两个失败态
    --   bid_lost 已流失  = 参与投标/谈判但未中标，或方案发出后无反馈，【未进入收款阶段】
    --   stalled  已烂尾 = 已在施工阶段，因款项未到位/拒付等无法继续，且【尚未进入维护】
    status            text NOT NULL DEFAULT 'engaging' CHECK (status IN
                        ('engaging','quote_signed',
                         'deposit_paid','in_construction','delivered','maintaining',
                         'bid_lost','stalled')),
    -- ★ 状态停留起始：状态一变就重置。没有这个字段就算不出"卡了多久"
    status_since      timestamptz NOT NULL DEFAULT now(),

    -- ★ v0.28 项目标识：所有流程都跟项目走，界面上必须随时看得见"这是哪个项目"
    --   实际工作里没人靠 KX-2026-0142 认项目，大家说的是"Cherrybrook 那家"
    --   自动生成：编号 · 名称或Suburb
    display_label     text GENERATED ALWAYS AS (
        code || ' · ' || COALESCE(NULLIF(btrim(COALESCE(name,'')),''),
                                  NULLIF(btrim(COALESCE(addr_suburb,'')),''),
                                  '未命名')) STORED,

    version           integer NOT NULL DEFAULT 1
);
COMMENT ON COLUMN project.deposit_amount IS '字段级所有权：仅财务可写，A 只读';
COMMENT ON COLUMN project.quote_amount   IS '字段级所有权：将来仅外部报价系统可写';
COMMENT ON COLUMN project.geofence_radius_m IS '考勤围栏半径，工程负责人按项目可调';


-- 家庭成员 / 参建方 / 方案倾向（沿用 v0.1）
CREATE TABLE household_member (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    member_type text NOT NULL CHECK (member_type IN
        ('adult','elder','child','nanny','driver','cleaner','pet','other')),
    age integer CHECK (age IS NULL OR (age BETWEEN 0 AND 130)),
    email text,                                   -- v0.34 选填（录人必带邮箱栏，不强制）
    note text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_hm_project ON household_member(project_id);

CREATE TABLE project_party (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    trade text NOT NULL CHECK (trade IN
        ('designer','builder','electrician','hvac','floor_heating',
         'pool','av_room','turntable','lift','other')),
    trade_other text, company text, contact_name text, phone text,
    email text,                                   -- v0.34 选填（Builder/电工邮箱进付款人候选）
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_pp_project ON project_party(project_id);

CREATE TABLE solution_option (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    wiring text NOT NULL CHECK (wiring IN ('wired','wireless')),
    protocol text NOT NULL CHECK (protocol IN ('knx','cbus','rs485','wifi','zigbee','other')),
    protocol_other text,
    budget numeric(14,2),
    has_knx boolean NOT NULL DEFAULT false,          -- 供 SM2 清单条件项判断
    has_floor_heating boolean NOT NULL DEFAULT false,-- 供 SM2 清单条件项判断
    note text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_so_project ON solution_option(project_id);


-- =====================================================================
--  第二部分：工程人员（含时薪）
-- =====================================================================
CREATE TABLE eng_staff (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name         text NOT NULL,
    role         text,                          -- 工程师/电工对接/项目经理...
    phone        text,
    email        text,                          -- v0.34 选填（录人必带邮箱栏，不强制）

    -- ★ 三种工资制度
    --   monthly  月薪制  ：每月固定，不发加班工资，加班时长累计 → 倒休
    --   hourly   时薪制  ：按付薪时长 × 时薪
    --   contractor 外包  ：固定日薪，去了就是一天；★没有周末/假日/加班概念
    pay_type     text NOT NULL DEFAULT 'hourly'
                   CHECK (pay_type IN ('monthly','hourly','contractor')),
    monthly_salary   numeric(12,2),             -- 月薪制：每月固定金额
    pay_hourly_rate  numeric(10,2),             -- 时薪制：发薪时薪

    -- ★ 外包：固定日薪 + 时薪计算参考时间（工程管理手填）
    daily_rate       numeric(10,2),             -- 外包固定日薪(谈好的价)
    -- ⚠️ 这不是"承诺工作多久"，而是【算成本时薪用的除数】，由工程管理设定
    --    例：日薪 510、参考时间 10 小时 → 成本时薪 51，项目成本按 51 算
    ref_minutes      integer,                   -- 时薪计算参考时间(分钟)，可按天覆盖

    -- ★ 成本时薪：三种人都要有，喂工程成本与利润率，口径全公司统一
    --   月薪制：人工换算填入(月薪 ÷ 月标准工时)
    --   时薪制：等于发薪时薪
    --   外包  ：★系统自动算 = 日薪 ÷ 时薪计算参考时间，不用人填
    cost_hourly_rate numeric(10,2),

    -- ★ 时薪制加班倍数·按人覆盖（工程管理手动设置；NULL = 用全局默认值）
    --   谈的条件不一样的人可以单独设；不设就跟全局走
    ot_rate_weekday  numeric(5,2) CHECK (ot_rate_weekday  IS NULL OR ot_rate_weekday  >= 1),
    ot_rate_saturday numeric(5,2) CHECK (ot_rate_saturday IS NULL OR ot_rate_saturday >= 1),
    ot_rate_sunday   numeric(5,2) CHECK (ot_rate_sunday   IS NULL OR ot_rate_sunday   >= 1),
    ot_rate_holiday  numeric(5,2) CHECK (ot_rate_holiday  IS NULL OR ot_rate_holiday  >= 1),

    -- ★ 入职 / 离职（入职前、离职后不生成日结工资）
    hired_at     date NOT NULL DEFAULT current_date,
    terminated_at date,
    termination_note text,

    active       boolean NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_staff_pay CHECK (
        (pay_type='monthly'    AND monthly_salary  IS NOT NULL) OR
        (pay_type='hourly'     AND pay_hourly_rate IS NOT NULL) OR
        -- ⚠️ NULL 陷阱：必须显式 IS NOT NULL。只写 committed_minutes > 0 的话，
        --    值为 NULL 时整个条件求值为 NULL，CHECK 会当作"没违反"放行
        (pay_type='contractor' AND daily_rate IS NOT NULL
                               AND ref_minutes IS NOT NULL AND ref_minutes > 0)),
    CONSTRAINT ck_staff_dates CHECK (terminated_at IS NULL OR terminated_at >= hired_at)
);
COMMENT ON COLUMN eng_staff.monthly_salary   IS '员工薪酬，敏感字段：权限阶段限制可见范围';
COMMENT ON COLUMN eng_staff.pay_hourly_rate  IS '员工薪酬，敏感字段：权限阶段限制可见范围';
COMMENT ON COLUMN eng_staff.cost_hourly_rate IS '成本口径时薪：月薪制由人工换算填入，供利润率计算';


-- =====================================================================
--  第三部分：SM 模板（每个 SM 填什么 + 出发前清单；工程负责人维护）
-- =====================================================================
CREATE TABLE sm_template (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sm_no        integer NOT NULL CHECK (sm_no BETWEEN 1 AND 4),
    version      integer NOT NULL DEFAULT 1,
    fields_schema jsonb NOT NULL DEFAULT '{}',   -- 该 SM 现场要填哪些项
    checklist    jsonb NOT NULL DEFAULT '[]',    -- 出发前清单项(可含条件项:need_knx/need_floor_heating)
    updated_by   text,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (sm_no, version)
);


-- =====================================================================
--  第四部分：现场会议 SM（SM1~4，顺序硬卡 + 老项目可标不适用）
-- =====================================================================
CREATE TABLE site_meeting (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    sm_no         integer NOT NULL CHECK (sm_no BETWEEN 1 AND 4),
    owner_staff_id uuid REFERENCES eng_staff(id),   -- 分配给谁负责
    content       jsonb NOT NULL DEFAULT '{}',      -- 按模板填的现场记录
    attachments   jsonb NOT NULL DEFAULT '[]',      -- 照片/文件链接数组

    -- 签字（签纸拍照 + 留痕）
    our_sign_url    text, our_sign_at timestamptz, our_sign_staff uuid REFERENCES eng_staff(id),
    elec_sign_url   text, elec_sign_at timestamptz,  -- 电工签字(SM2 单向 / SM3 双向)
    elec_party_id   uuid REFERENCES project_party(id), -- 关联到哪个电工

    -- ★ 派工（工程负责人分配：哪天、给谁、预计多久）
    scheduled_date  date,
    planned_minutes integer,

    -- 完成 / 不适用
    completed_at    timestamptz,                     -- 完成确认(卡点信号)
    na_flag         boolean NOT NULL DEFAULT false,  -- 老项目标记“不适用”
    na_reason       text,
    na_by           text,
    na_at           timestamptz,

    version       integer NOT NULL DEFAULT 1,
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (project_id, sm_no)                       -- 一个项目每个 SM 一场
);
CREATE INDEX idx_sm_project ON site_meeting(project_id);


-- =====================================================================
--  第五部分：出发前清单画勾 job_checklist（★v0.3 改为四类任务共用）
--    清单的规矩四类完全一样（适用项全勾才放行），所以共用一张表；
--    差异在“填什么”，由 job_kind + 模板决定，不需要四张一模一样的表。
--    （原则 8：通用能力抽离复用，不做成某模块专属）
-- =====================================================================
CREATE TABLE job_checklist (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    job_kind      text NOT NULL CHECK (job_kind IN ('sm','install','handover','maintenance')),
    job_id        uuid NOT NULL,                  -- 指向对应任务表的 id（多态，不设 FK）
    item_key      text NOT NULL,
    item_label    text NOT NULL,
    is_conditional boolean NOT NULL DEFAULT false,-- 条件项(如 KNX/地暖)
    applicable    boolean NOT NULL DEFAULT true,  -- 该项目是否适用
    checked       boolean NOT NULL DEFAULT false,
    free_text     text,                           -- “其他物料”手填
    checked_by    uuid REFERENCES eng_staff(id),
    checked_at    timestamptz
);
CREATE INDEX idx_ck_job ON job_checklist(job_kind, job_id);


-- =====================================================================
--  第六部分：通用工时/考勤 work_log
--    SM / 实施 / 交付 / 运维 四类活共用；人工成本唯一来源
--    考勤：入场围栏认证(定位/拍照兜底) + 离场
-- =====================================================================
CREATE TABLE work_log (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    staff_id      uuid NOT NULL REFERENCES eng_staff(id),
    work_type     text NOT NULL CHECK (work_type IN ('sm','execution','handover','maintenance')),
    ref_id        uuid,                            -- 关联具体 SM / 运维单 等

    -- 入场
    checkin_at    timestamptz,
    checkin_lat   numeric(9,6),
    checkin_lng   numeric(9,6),
    checkin_dist_m numeric(8,1),                   -- 距 site 距离(米)
    checkin_method text CHECK (checkin_method IN ('gps','photo')),  -- 定位/拍照兜底
    checkin_photo_url text,                        -- 拍照兜底时的现场照片
    checkin_flagged boolean NOT NULL DEFAULT false,-- 异常(拍照兜底/超界)标记，可追溯

    -- 离场
    checkout_at   timestamptz,
    checkout_lat  numeric(9,6),
    checkout_lng  numeric(9,6),
    checkout_dist_m numeric(8,1),
    left_area_flag boolean NOT NULL DEFAULT false, -- 中途疑似离开围栏(方案甲抽查)

    note          text,
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_wl_project ON work_log(project_id);
CREATE INDEX idx_wl_staff   ON work_log(staff_id);
-- 时长 = checkout_at - checkin_at，视图现算


-- =====================================================================
--  第七部分：付款节点 S1~S4（应收）+ 收款明细（实收，现金/走账/GST）
-- =====================================================================
CREATE TABLE payment_milestone (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,

    -- ★ v0.4：全公司一套应收规矩。合同节点 S1~S4 与 维护单 共用本表
    kind          text NOT NULL DEFAULT 'contract'
                    CHECK (kind IN ('contract','maintenance')),
    stage         text CHECK (stage IN ('S1','S2','S3','S4')),   -- 维护单为 NULL
    case_id       uuid,                                           -- 维护单：指向 maintenance_case(FK 后置)

    ratio_pct     numeric(5,2),                    -- 10/40/40/10；维护单不用
    -- ★ 应收：发出前跟着签约价现算浮动，发出即定格焊死
    amount_due    numeric(14,2),
    gst_amount    numeric(14,2),

    -- ★ Invoice 版本化：改版重开 v2，超期天数从最后一版重算；账龄从第一版算
    invoice_no    text,
    invoice_ver   integer NOT NULL DEFAULT 1,
    invoice_sent_at       timestamptz,             -- 最后一版发出时间(超期起点)
    first_invoice_sent_at timestamptz,             -- 第一版发出时间(账龄起点，改版抹不掉)

    -- ★ 结清：系统算够不够，财务点结清；不足额必须填原因，差额定格
    status        text NOT NULL DEFAULT 'pending' CHECK (status IN
                    ('pending','invoiced','partial','settled')),
    settled_at    timestamptz,
    settled_by    text,
    shortfall_amount numeric(14,2),                -- 批准当时的差额(定格，不随后续收款变)
    settle_reason text,                            -- 不足额结清的原因(留痕)

    note          text,
    version       integer NOT NULL DEFAULT 1,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pm_kind CHECK (
        (kind='contract'    AND stage IS NOT NULL AND case_id IS NULL) OR
        (kind='maintenance' AND stage IS NULL     AND case_id IS NOT NULL))
);
-- 合同节点：一个项目每个 S 阶段只有一条；维护单不限
CREATE UNIQUE INDEX uq_pm_contract_stage ON payment_milestone(project_id, stage)
    WHERE kind='contract';
CREATE INDEX idx_pm_project ON payment_milestone(project_id);

CREATE TABLE payment_receipt (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    milestone_id  uuid NOT NULL REFERENCES payment_milestone(id) ON DELETE CASCADE,
    method        text NOT NULL CHECK (method IN ('bank','cash')),  -- 走账/现金
    amount        numeric(14,2) NOT NULL,
    gst_amount    numeric(14,2) NOT NULL DEFAULT 0, -- 走账计、现金默认0，可改
    received_at   timestamptz,
    handler       text,                            -- 经手人
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_pr_milestone ON payment_receipt(milestone_id);


-- =====================================================================
--  第八部分：变更 variation（SM3 产生，只留痕；金额留 S4 结算）
-- =====================================================================
-- ★ v0.33 催款记录（二十七/二十八轮）：每次催款留痕 —— 渠道/语言/级别/发送人；
--   短信可回 Y 作确认、邮件发出即视为送达 —— 都只是记录，不回不影响任何进展（不做任何门禁前提）
CREATE TABLE payment_remind_log (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    milestone_id  uuid NOT NULL REFERENCES payment_milestone(id) ON DELETE CASCADE,
    remind_at     timestamptz NOT NULL DEFAULT now(),
    channel       text NOT NULL CHECK (channel IN ('sms','email','both')),
    lang          text NOT NULL DEFAULT 'zh' CHECK (lang IN ('zh','en')),
    level         text NOT NULL DEFAULT 'normal' CHECK (level IN ('normal','final')),  -- final=催账和停服页的最终催款
    sent_by       text NOT NULL,                 -- 发送人（弹窗里可改，默认当前登录人）
    sms_replied_at timestamptz,                  -- 短信回 Y 的时间（仅记录）
    note          text
);
CREATE INDEX idx_prl_milestone ON payment_remind_log(milestone_id);

-- ★ 门禁：已烂尾项目不再关联催款（二十七轮用户定 —— 催也没有意义，走拒付停服与法务路径）
CREATE OR REPLACE FUNCTION trg_remind_stalled_gate() RETURNS trigger AS $$
DECLARE st text;
BEGIN
    SELECT p.status INTO st FROM payment_milestone m JOIN project p ON p.id=m.project_id
     WHERE m.id = NEW.milestone_id;
    IF st = 'stalled' THEN
        RAISE EXCEPTION '门禁：该项目已标注「已烂尾」—— 不再关联催款；请走「拒付停服」与法务路径';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER remind_stalled_gate BEFORE INSERT ON payment_remind_log
    FOR EACH ROW EXECUTE FUNCTION trg_remind_stalled_gate();

CREATE TABLE variation (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    -- ★ v0.34 产生时点（2026-08-02 拍板放开）：sm3=SM3 现场；post_sm3=工程追加（SM3 后~交付前）；
    --   unreturned=未退料结算转入（fn_settle_unreturned 系统写，勿删——22 号测试曾抓过掐死它的 CHECK）
    origin        text NOT NULL DEFAULT 'sm3' CHECK (origin IN ('sm3','post_sm3','unreturned')),
    change_type   text NOT NULL CHECK (change_type IN ('add','remove','move')),
    description   text,
    photos        jsonb NOT NULL DEFAULT '[]',      -- 图片(移位在图上标)
    logged_by     uuid REFERENCES eng_staff(id),
    -- ★ v0.34 工程追加三件：预计人工工时(工程管理填，只进成本核算与排产——
    --   不改计费口径：人工仍含在物料售卖价里，不单独向客户计费)
    labor_hours_est numeric(8,1) CHECK (labor_hours_est IS NULL OR labor_hours_est >= 0),
    payer_notified_at    timestamptz,   -- ★追加告知短信发出时刻（拍板配套：登记即自动发）
    payer_sms_replied_at timestamptz,   -- 付款人回 Y 时刻（仅记录，不回不挡任何进展）
    -- 自动知会三方
    notified_design   boolean NOT NULL DEFAULT false,
    notified_procure  boolean NOT NULL DEFAULT false,
    notified_finance  boolean NOT NULL DEFAULT false,
    -- ★ 结算(S4)：由【财务 + 库管】依据工程与 SM 过程记录，在外部手工计算
    --   本系统只读接入 + 手填占位，跟报价系统同一种处理方式
    settle_status text NOT NULL DEFAULT 'pending_s4'
                    CHECK (settle_status IN ('pending_s4','settled_s4')),
    settle_amount numeric(14,2),                    -- 外部算完填回来的金额(SM3 不填)
    settle_source text NOT NULL DEFAULT 'manual'
                    CHECK (settle_source IN ('manual','external_system')),
    settle_ext_ref text,                            -- 外部系统的单号/表格链接
    settle_by     text,                             -- 谁填回来的
    settle_at     timestamptz,                      -- 什么时候填的
    settle_note   text,                             -- 依据说明(算的时候参照了哪些记录)
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_var_project ON variation(project_id);


-- =====================================================================
--  第九部分：采购 procurement（下单/到货/预配/发货 + 成本）
-- =====================================================================
CREATE TABLE procurement (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    supplier      text,
    items         jsonb NOT NULL DEFAULT '[]',      -- 物料明细(占位)
    cost_amount   numeric(14,2),                    -- 采购成本(喂利润率)
    warranty_months integer,                        -- ★ 物料保修月数(各供应商不同，手填)
                                                    --   起算 = 本项目 S2 结清日
    ordered_at    timestamptz,                      -- 下单
    arrived_at    timestamptz,                      -- 到货
    prewired_at   timestamptz,                      -- 工程预配完成(发货前置)
    shipped_at    timestamptz,                      -- 发货
    variation_id  uuid REFERENCES variation(id),    -- 若为变更补采购，关联
    status        text NOT NULL DEFAULT 'draft' CHECK (status IN
                    ('draft','ordered','arrived','prewired','shipped')),
    version       integer NOT NULL DEFAULT 1,
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_proc_project ON procurement(project_id);


-- =====================================================================
--  第十部分：运维 maintenance_case（支线：报价→Invoice→可立即开工→结案）
-- =====================================================================
CREATE TABLE maintenance_case (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    title         text,
    -- ★ v0.11：报修受理留痕（客户什么时候报的、怎么报的、谁接的）
    --   ⚠️ 允许"未知"：记不清就空着。空着时响应时长显示【未知】，
    --      【绝不拿建单时间顶替】——那样响应时长永远是 0，好看但是假的
    reported_at   timestamptz,                     -- 客户报修时间；NULL = 未知
    report_channel text NOT NULL DEFAULT 'unknown'
                    CHECK (report_channel IN ('phone','wechat','email','onsite','other','unknown')),
    taken_by      text,                            -- 谁接的
    report_note   text,                            -- 客户原话/现象描述

    -- ★ v0.10：口头预估（工程管理填）。客户电话里问"大概多少钱"时先记一个数。
    --   ⚠️ 仅供参考，【不参与任何计费】——实际金额以发票(payment_milestone)为准
    estimate_amount numeric(14,2),
    estimated_by    text,
    estimated_at    timestamptz,
    estimate_note   text,
    -- ★ v0.4：发票/收款不再自带，统一走 payment_milestone(kind='maintenance')
    -- ★ 故障归因：由现场 maintenance_job 带回(当着客户面确认)，办公室据此定价
    --   四类统一词表（与 rma_case.damage_cause 一致）
    fault_cause   text CHECK (fault_cause IN
                    ('human','product_defect','wear_out','force_majeure')),
    is_free_warranty boolean NOT NULL DEFAULT false, -- 结案时定格：本单是否免责维保覆盖
    labor_cost    numeric(14,2),                    -- 运维人力成本(也可由 work_log 汇总)
    material_cost numeric(14,2),                    -- 运维物料成本
    started_at    timestamptz,                      -- 可在发 Invoice 后立即开工
    closed_at     timestamptz,                      -- 结案
    -- ★ v0.8：维护单只存在于已交付项目（未交付不予处理），
    --   所以不再需要"成本归属"判定——维护成本一律进长期利润率
    -- ★ v0.9 真实顺序：open(受理) → in_progress(已上门) → invoiced(办公室定价开票) → paid_closed(收款结案)
    status        text NOT NULL DEFAULT 'open' CHECK (status IN
                    ('open','in_progress','invoiced','paid_closed','unpaid_suspended','void')),
    version       integer NOT NULL DEFAULT 1,
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_mc_project ON maintenance_case(project_id);


-- =====================================================================
--  第十一部分：通用通知 notification（邮件先行，短信/双向占位）
-- =====================================================================
CREATE TABLE notification (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid REFERENCES project(id) ON DELETE CASCADE,
    ref_kind      text,                             -- variation/invoice/sm/maintenance...
    ref_id        uuid,
    channel       text NOT NULL CHECK (channel IN ('email','sms','sms_2way')),
    recipient     text NOT NULL,
    subject       text,
    body          text,
    attachments   jsonb NOT NULL DEFAULT '[]',
    status        text NOT NULL DEFAULT 'queued' CHECK (status IN
                    ('queued','sent','delivered','replied_yes','failed')),
    triggered_by  text,
    sent_at       timestamptz,
    replied_at    timestamptz,                      -- 双向确认(将来)
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_notif_project ON notification(project_id);


-- =====================================================================
--  第十二部分：通用交接/通知留痕 handoff_log（谁通知谁）
-- =====================================================================
CREATE TABLE handoff_log (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id    uuid REFERENCES project(id) ON DELETE CASCADE,
    from_party    text,
    to_party      text,
    node          text,                             -- 在哪个业务节点
    message       text,
    at            timestamptz NOT NULL DEFAULT now()
);


-- =====================================================================
--  审计日志
-- =====================================================================
CREATE TABLE audit_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    actor text, action text, table_name text, row_id uuid,
    before jsonb, after jsonb, at timestamptz NOT NULL DEFAULT now()
);


-- =====================================================================
--  触发器
-- =====================================================================

-- v0.35：乐观锁通用件（原 project 专用两只已废除，改由文件末尾 DO 块给全部可改业务表统一挂）
--   trg_row_touch   —— 每次 UPDATE 自动刷 updated_at 并把 version +1
--   trg_row_optlock —— 写操作带 app.expected_version 时比对；对不上直接拒，绝不静默覆盖
CREATE OR REPLACE FUNCTION trg_row_touch() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    NEW.version    := OLD.version + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION trg_row_touch() IS 'v0.35 通用：UPDATE 时刷新 updated_at 并自增 version';

CREATE OR REPLACE FUNCTION trg_row_optlock() RETURNS trigger AS $$
DECLARE ev text := current_setting('app.expected_version', true);
BEGIN
    -- 不设 app.expected_version = 系统内部更新（触发器/结算函数/后台脚本），照常放行
    IF ev IS NOT NULL AND ev <> '' AND ev !~ '^[0-9]+$' THEN
        RAISE EXCEPTION
          '版本号不是数字（收到「%」）—— 前端提交时必须把打开这条记录时拿到的版本号原样带回来，不许自己编',
          ev;
    END IF;
    IF ev IS NOT NULL AND ev <> '' AND OLD.version <> ev::int THEN
        RAISE EXCEPTION
          '并发冲突：这条记录在你打开页面之后已经被人改过（当前是第 % 版，你手上这份是第 % 版）—— 请刷新页面看最新的内容再改，不要直接覆盖别人的修改',
          OLD.version, ev;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION trg_row_optlock() IS
  'v0.35 通用乐观锁：带 app.expected_version 且与当前 version 不符 → 拒绝并给中文原句';

-- project：状态门禁（方案定版才能推进）
CREATE OR REPLACE FUNCTION trg_project_gate() RETURNS trigger AS $$
BEGIN
    IF NEW.status = 'quote_signed' AND NEW.step6_signed_at IS NULL THEN
        RAISE EXCEPTION '门禁：未完成第六步(客户签字)，不能置为"已签署报价"';
    END IF;
    IF NEW.status IN ('in_construction','delivered','maintaining')
       AND NEW.step6_signed_at IS NULL THEN
        RAISE EXCEPTION '门禁：方案未定版(第六步未完成)，不能进入施工/交付/维护';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER project_gate BEFORE INSERT OR UPDATE ON project
    FOR EACH ROW EXECUTE FUNCTION trg_project_gate();

-- ★ SM 顺序门禁：SM(n) 完成需要 SM(n-1) 已完成或已标不适用；老项目可 na_flag 放行
CREATE OR REPLACE FUNCTION trg_sm_order_gate() RETURNS trigger AS $$
DECLARE prev_ok boolean;
BEGIN
    -- 仅在“标记完成”这一刻校验顺序
    IF NEW.completed_at IS NOT NULL AND (OLD.completed_at IS NULL OR TG_OP='INSERT') THEN
        IF NEW.sm_no > 1 THEN
            SELECT (completed_at IS NOT NULL OR na_flag)
              INTO prev_ok
              FROM site_meeting
             WHERE project_id = NEW.project_id AND sm_no = NEW.sm_no - 1;
            IF prev_ok IS NULL THEN
                RAISE EXCEPTION '门禁：SM% 尚未创建，不能先完成 SM%', NEW.sm_no - 1, NEW.sm_no;
            ELSIF prev_ok = false THEN
                RAISE EXCEPTION '门禁：SM% 未完成且未标记不适用，不能完成 SM%(顺序硬卡)', NEW.sm_no - 1, NEW.sm_no;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER sm_order_gate BEFORE INSERT OR UPDATE ON site_meeting
    FOR EACH ROW EXECUTE FUNCTION trg_sm_order_gate();

-- ★ 清单门禁：SM 标记完成时，必须适用项全部勾选
CREATE OR REPLACE FUNCTION trg_sm_checklist_gate() RETURNS trigger AS $$
DECLARE unchecked int;
BEGIN
    IF NEW.completed_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.completed_at IS NULL)
       AND NEW.na_flag = false THEN
        SELECT count(*) INTO unchecked
          FROM job_checklist
         WHERE job_kind='sm' AND job_id = NEW.id AND applicable = true AND checked = false;
        IF unchecked > 0 THEN
            RAISE EXCEPTION '门禁：出发前清单还有 % 项未勾选，不能完成本次 SM', unchecked;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER sm_checklist_gate BEFORE UPDATE ON site_meeting
    FOR EACH ROW EXECUTE FUNCTION trg_sm_checklist_gate();

-- ★ 付款门禁：S2 需 SM3 完成；S3 需 SM4 完成（发 Invoice 时校验）
CREATE OR REPLACE FUNCTION trg_payment_gate() RETURNS trigger AS $$
DECLARE ok boolean;
BEGIN
    IF NEW.status = 'invoiced' AND (TG_OP='INSERT' OR OLD.status <> 'invoiced') THEN
        IF NEW.stage = 'S2' THEN
            SELECT (completed_at IS NOT NULL OR na_flag) INTO ok
              FROM site_meeting WHERE project_id=NEW.project_id AND sm_no=3;
            IF ok IS DISTINCT FROM true THEN
                RAISE EXCEPTION '门禁：SM3 未完成，不能发起 S2 物料款';
            END IF;
        ELSIF NEW.stage = 'S3' THEN
            SELECT (completed_at IS NOT NULL OR na_flag) INTO ok
              FROM site_meeting WHERE project_id=NEW.project_id AND sm_no=4;
            IF ok IS DISTINCT FROM true THEN
                RAISE EXCEPTION '门禁：SM4 未完成，不能发起 S3 人工款';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER payment_gate BEFORE INSERT OR UPDATE ON payment_milestone
    FOR EACH ROW EXECUTE FUNCTION trg_payment_gate();

-- ★ 采购门禁：下单需 S2 已结清；发货需工程预配完成
CREATE OR REPLACE FUNCTION trg_procure_gate() RETURNS trigger AS $$
DECLARE s2_ok boolean;
BEGIN
    IF NEW.status IN ('ordered','arrived','prewired','shipped')
       AND (TG_OP='INSERT' OR OLD.status='draft') THEN
        SELECT (status='settled') INTO s2_ok
          FROM payment_milestone WHERE project_id=NEW.project_id AND stage='S2';
        IF s2_ok IS DISTINCT FROM true THEN
            RAISE EXCEPTION '门禁：S2 物料款未结清，采购不能下单';
        END IF;
    END IF;
    IF NEW.status='shipped' AND NEW.prewired_at IS NULL THEN
        RAISE EXCEPTION '门禁：工程尚未完成预配，采购不能发货';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER procure_gate BEFORE INSERT OR UPDATE ON procurement
    FOR EACH ROW EXECUTE FUNCTION trg_procure_gate();

-- 通用审计（挂 project 与几张关键表）
CREATE OR REPLACE FUNCTION trg_audit() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit_log(actor, action, table_name, row_id, before, after)
    VALUES (current_setting('app.actor', true), TG_OP, TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        CASE WHEN TG_OP='INSERT' THEN NULL ELSE to_jsonb(OLD) END,
        CASE WHEN TG_OP='DELETE' THEN NULL ELSE to_jsonb(NEW) END);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER project_audit AFTER INSERT OR UPDATE OR DELETE ON project
    FOR EACH ROW EXECUTE FUNCTION trg_audit();
CREATE TRIGGER payment_audit AFTER INSERT OR UPDATE OR DELETE ON payment_milestone
    FOR EACH ROW EXECUTE FUNCTION trg_audit();
CREATE TRIGGER variation_audit AFTER INSERT OR UPDATE OR DELETE ON variation
    FOR EACH ROW EXECUTE FUNCTION trg_audit();


-- =====================================================================
--  视图
-- =====================================================================

-- 项目一览（含现算派生）
CREATE OR REPLACE VIEW v_project_overview AS
SELECT p.*,
    (now()::date - p.created_at::date)  AS days_since_created,
    (p.deposit_amount IS NOT NULL)      AS deposit_received,
    (p.step6_signed_at IS NOT NULL)     AS proposal_locked
FROM project p;

-- 每条工时的时长（小时）
CREATE OR REPLACE VIEW v_work_hours AS
SELECT w.*,
    EXTRACT(EPOCH FROM (w.checkout_at - w.checkin_at))/3600.0 AS hours
FROM work_log w
WHERE w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL;

-- 项目实际人工成本（分子）：Σ 工时×时薪
CREATE OR REPLACE VIEW v_project_labor_cost AS
SELECT w.project_id,
    SUM(EXTRACT(EPOCH FROM (w.checkout_at - w.checkin_at))/3600.0 * s.cost_hourly_rate) AS labor_cost,
    SUM(EXTRACT(EPOCH FROM (w.checkout_at - w.checkin_at))/3600.0) AS actual_hours
FROM work_log w JOIN eng_staff s ON s.id = w.staff_id
WHERE w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL
GROUP BY w.project_id;

-- 人工消耗百分比（实际/预测；推进中现算，交付定格另存 project.eng_margin_locked）
CREATE OR REPLACE VIEW v_labor_consumption AS
SELECT p.id AS project_id, p.code,
    p.planned_labor_hours,
    lc.actual_hours,
    CASE WHEN p.planned_labor_hours > 0
         THEN round((lc.actual_hours / p.planned_labor_hours * 100)::numeric, 1)
         ELSE NULL END AS consumption_pct
FROM project p LEFT JOIN v_project_labor_cost lc ON lc.project_id = p.id;


-- #####################################################################
-- ##  v0.3 新增：安装调试 / 技术维护 / 交付 + 每日上报 + 路上时间
-- #####################################################################

-- =====================================================================
--  第十三部分：全局设置 eng_setting（工程管理维护，一处改全公司生效）
-- =====================================================================
CREATE TABLE eng_setting (
    key        text PRIMARY KEY,
    value_num  numeric,
    value_text text,
    note       text,
    -- v0.31 ★按键控制写权限：默认工程管理；个别键开放给其他部门
    --（如加班倍数→财务、订阅年费→运维）。改这一列本身只有决策管理员可以
    write_depts text[] NOT NULL DEFAULT ARRAY['eng_mgmt'],
    updated_by text,
    updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO eng_setting(key, value_num, note) VALUES
 ('overtime_threshold_min', 30,  '超时阈值(分钟)：超过即强制上报问题'),
 ('standard_workday_min',  480,  '标准工作日(分钟)，用于“工时超时”线'),
 ('travel_alert_min',      NULL, '路上时间异常提醒阈值(分钟)，NULL=只呈现不判定'),
 ('lunch_break_min',        30,  '午餐时长(分钟)，无薪。自动扣，不打卡'),
 ('lunch_min_span_min',    300,  '当日首尾超过此长度才扣午餐(短工日不扣)');
INSERT INTO eng_setting(key, value_text, note) VALUES
 ('lunch_anchor_time', '12:00', '午餐锚点：用它判定午休落在哪一段(在场/路上)，决定成本摊给谁');


-- =====================================================================
--  第十四部分：安装项 install_item（项目级“要装什么”，剩余清零的对象）
--    剩余清零 ≠ 必须全做完：取消/挂起/转变更 都算清零，但必须填原因
-- =====================================================================
CREATE TABLE install_item (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id  uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    title       text NOT NULL,                    -- 要装/调什么
    area        text,                             -- 哪间房/哪层
    status      text NOT NULL DEFAULT 'pending' CHECK (status IN
                  ('pending','done','cancelled','suspended','to_variation')),
    reason      text,                             -- 取消/挂起 必填
    blocked_by  text,                             -- 挂起卡在谁那(空调队/缺货/场地)
    variation_id uuid REFERENCES variation(id),   -- 转变更时关联
    done_job_id uuid,                             -- 哪一趟做掉的(install_job)
    updated_by  uuid REFERENCES eng_staff(id),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_item_reason CHECK (
        (status NOT IN ('cancelled','suspended') OR reason IS NOT NULL) AND
        (status <> 'to_variation' OR variation_id IS NOT NULL))
);
CREATE INDEX idx_ii_project ON install_item(project_id, status);


-- =====================================================================
--  第十五部分：安装调试任务 install_job（一趟上门一条；不签字）
--    门禁：必须 SM4 完成(或标不适用)之后才能派
-- =====================================================================
CREATE TABLE install_job (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    staff_id      uuid REFERENCES eng_staff(id),     -- 派给谁
    scheduled_date date,                             -- 派在哪天
    planned_minutes integer,                         -- 计划时长(“计划超时”线的分母)
    content       jsonb NOT NULL DEFAULT '{}',       -- 本趟做了什么(按模板)
    remaining_note text,                             -- 本趟结束时的剩余说明(明细见 install_item)
    attachments   jsonb NOT NULL DEFAULT '[]',
    completed_at  timestamptz,
    version       integer NOT NULL DEFAULT 1,
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_ij_project ON install_job(project_id);
CREATE INDEX idx_ij_sched   ON install_job(staff_id, scheduled_date);
COMMENT ON TABLE install_job IS '安装调试：不需要客户签字（与 SM/交付不同）';


-- =====================================================================
--  第十六部分：交付条件确认 delivery_review
--    工程管理看“工程流水账”(视图)后人肉判断，系统不代替判断，只留痕
-- =====================================================================
CREATE TABLE delivery_review (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    decision      text NOT NULL CHECK (decision IN ('ready','not_ready')),
    reviewed_by   uuid REFERENCES eng_staff(id),
    reviewed_at   timestamptz NOT NULL DEFAULT now(),
    basis_snapshot jsonb NOT NULL DEFAULT '{}',   -- 当时看到的流水账汇总(定格，防翻旧账糊涂)
    note          text
);
CREATE INDEX idx_dr_project ON delivery_review(project_id, reviewed_at DESC);


-- =====================================================================
--  第十七部分：交付任务 handover_job（第四类任务，要上门、客户必须签字）
--    门禁：S4 必须已结清(硬卡，无后门) + 已有 ready 的交付条件确认
-- =====================================================================
CREATE TABLE handover_job (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL UNIQUE REFERENCES project(id) ON DELETE CASCADE,
    staff_id      uuid REFERENCES eng_staff(id),
    scheduled_date date,
    planned_minutes integer,
    content       jsonb NOT NULL DEFAULT '{}',     -- 交了哪些文件/教了哪些功能
    attachments   jsonb NOT NULL DEFAULT '[]',
    client_sign_url  text,                         -- ★ 客户签收(签纸拍照)
    client_sign_name text,
    client_sign_at   timestamptz,
    completed_at  timestamptz,
    version       integer NOT NULL DEFAULT 1,
    created_at    timestamptz NOT NULL DEFAULT now()
);


-- =====================================================================
--  第十八部分：技术维护任务 maintenance_job
--    默认挂维护单；来不及可无单派工，但必须填原因(留痕后门)
-- =====================================================================
CREATE TABLE maintenance_job (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    case_id       uuid REFERENCES maintenance_case(id),  -- 关联维护单(钱单)
    no_case_reason text,                                 -- 无单派工原因
    staff_id      uuid REFERENCES eng_staff(id),
    scheduled_date date,
    planned_minutes integer,
    content       jsonb NOT NULL DEFAULT '{}',           -- 故障现象/处理/换件
    attachments   jsonb NOT NULL DEFAULT '[]',

    -- ★ v0.9：现场结束时，当着客户面确认归因 + 客户签字确认当日服务内容，才可离开
    -- ★ v0.21 统一四类：现场填一次，RMA 直接继承，索赔依据也有了
    --   human=人为损坏 ｜ product_defect=产品缺陷(可向供应商索赔)
    --   wear_out=自然老化 ｜ force_majeure=不可抗力
    fault_cause   text CHECK (fault_cause IN
                    ('human','product_defect','wear_out','force_majeure')),
    service_summary text,                                -- 当日服务内容(客户签的就是这段)
    client_sign_url  text,                               -- 客户签字(签纸拍照)
    client_sign_name text,
    client_sign_at   timestamptz,

    completed_at  timestamptz,
    version       integer NOT NULL DEFAULT 1,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_mj_case CHECK (case_id IS NOT NULL OR no_case_reason IS NOT NULL)
);
CREATE INDEX idx_mj_project ON maintenance_job(project_id);
CREATE INDEX idx_mj_sched   ON maintenance_job(staff_id, scheduled_date);


-- =====================================================================
--  第十九部分：每人每天上报 daily_report + daily_issue
--    ★ 挂“人 + 日期”，不挂项目（一人一天可跑多个项目）
--    两条超时线，任一超阈值即强制上报：
--      计划超时 = 在场时间总和 − 当天派活计划总和
--      工时超时 = 首尾时长(含路上，澳洲规矩付薪) − 标准工作日
--    填写时间不计工时（工时在 work_log 离场时已封口）
-- =====================================================================
CREATE TABLE daily_report (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id      uuid NOT NULL REFERENCES eng_staff(id),
    report_date   date NOT NULL,
    -- 提交时定格落库（之后再补工时也不改这条历史判定）
    planned_minutes  numeric,
    onsite_minutes   numeric,
    span_minutes     numeric,
    lunch_min        numeric,      -- ★ 自动扣除的午餐(无薪)
    paid_minutes     numeric,      -- ★ 付薪时长 = 首尾 − 午餐
    over_plan_min    numeric,
    over_span_min    numeric,
    submitted_at  timestamptz,
    note          text,                            -- 不超时的自愿说明
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (staff_id, report_date)
);

CREATE TABLE daily_issue (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id   uuid NOT NULL REFERENCES daily_report(id) ON DELETE CASCADE,
    issue_type  text NOT NULL CHECK (issue_type IN
                  ('rnd','product','market','standardization','scheduling')),
                  -- 研发 / 产品 / 市场 / 标准化 / 工程安排
    -- ★ v0.29：问题必须落到项目上，除非明确标为公司级
    --   这是项目管理平台——挂起的问题追不回项目，管理人员不知道去处理谁
    project_id  uuid REFERENCES project(id),
    is_company_level boolean NOT NULL DEFAULT false,  -- 明确的公司级问题（如标准化流程）
    CONSTRAINT ck_issue_project CHECK (is_company_level OR project_id IS NOT NULL),
    description text NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_di_report ON daily_issue(report_id);


-- =====================================================================
--  第二十部分：路程预估 travel_estimate（Google 只读镜像，两版都存死）
--    kind='planned' 派活时按【计划出发时间】查 → 用途：派活估时参考
--    kind='actual'  收工后按【实际离场时间】查 → 用途：判断路上异不异常
--    ★ 必须连“查询时用的出发时间”一起存，否则高峰/非高峰会冤枉人
--    ★ avoid_tolls=true（避过路费），motorway 照走
--    ★ 外部依赖，绝不进门禁：查不到就是空，不影响任何流程与发薪
-- =====================================================================
CREATE TABLE travel_estimate (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id      uuid NOT NULL REFERENCES eng_staff(id),
    travel_date   date NOT NULL,
    seq           integer NOT NULL,                -- 当日第几段 traffic slot
    from_project_id uuid REFERENCES project(id),
    to_project_id   uuid REFERENCES project(id),
    kind          text NOT NULL CHECK (kind IN ('planned','actual')),
    depart_at     timestamptz NOT NULL,            -- ★ 查询时用的出发时间
    duration_min  numeric(8,1),
    distance_m    numeric(10,1),
    avoid_tolls   boolean NOT NULL DEFAULT true,
    route         jsonb,                           -- 路线图(polyline/steps)
    provider      text NOT NULL DEFAULT 'google',
    queried_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (staff_id, travel_date, seq, kind)
);


-- =====================================================================
--  v0.3 触发器
-- =====================================================================

-- ★ 门禁：安装必须在 SM4 之后（派工那一刻就卡）
CREATE OR REPLACE FUNCTION trg_install_after_sm4() RETURNS trigger AS $$
DECLARE ok boolean;
BEGIN
    SELECT (completed_at IS NOT NULL OR na_flag) INTO ok
      FROM site_meeting WHERE project_id = NEW.project_id AND sm_no = 4;
    IF ok IS DISTINCT FROM true THEN
        RAISE EXCEPTION '门禁：SM4 未完成(且未标不适用)，不能派安装调试任务';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER install_after_sm4 BEFORE INSERT ON install_job
    FOR EACH ROW EXECUTE FUNCTION trg_install_after_sm4();

-- ★ 通用清单门禁：任务标记完成时，适用项必须全勾（四类共用一个函数）
CREATE OR REPLACE FUNCTION trg_job_checklist_gate() RETURNS trigger AS $$
DECLARE unchecked int; kind text := TG_ARGV[0];
BEGIN
    IF NEW.completed_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.completed_at IS NULL) THEN
        SELECT count(*) INTO unchecked FROM job_checklist
         WHERE job_kind = kind AND job_id = NEW.id AND applicable = true AND checked = false;
        IF unchecked > 0 THEN
            RAISE EXCEPTION '门禁：出发前清单还有 % 项未勾选，不能完成本次任务', unchecked;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER install_ck_gate BEFORE INSERT OR UPDATE ON install_job
    FOR EACH ROW EXECUTE FUNCTION trg_job_checklist_gate('install');
CREATE TRIGGER handover_ck_gate BEFORE INSERT OR UPDATE ON handover_job
    FOR EACH ROW EXECUTE FUNCTION trg_job_checklist_gate('handover');
CREATE TRIGGER maint_ck_gate BEFORE INSERT OR UPDATE ON maintenance_job
    FOR EACH ROW EXECUTE FUNCTION trg_job_checklist_gate('maintenance');

-- ★ 门禁：安装整体完工 = 剩余清零(无 pending) + 负责人确认，两个都要
CREATE OR REPLACE FUNCTION trg_install_complete_gate() RETURNS trigger AS $$
DECLARE pend int;
BEGIN
    IF NEW.install_completed_at IS NOT NULL AND OLD.install_completed_at IS NULL THEN
        IF NEW.install_completed_by IS NULL THEN
            RAISE EXCEPTION '门禁：安装完工必须由工程负责人确认(install_completed_by 不能为空)';
        END IF;
        SELECT count(*) INTO pend FROM install_item
         WHERE project_id = NEW.id AND status = 'pending';
        IF pend > 0 THEN
            RAISE EXCEPTION '门禁：还有 % 项安装内容未清零(未做完/未取消/未挂起/未转变更)，不能确认安装完工', pend;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER install_complete_gate BEFORE UPDATE ON project
    FOR EACH ROW EXECUTE FUNCTION trg_install_complete_gate();

-- ★ 门禁：维护单只能建在【已交付】项目上
--   交付前客户发现的问题，属于安装还没干完 → 走 install_item 剩余项 或 variation 变更，
--   不另开维护单。不给这条路留岔道，否则同一件事有两个入口，账也会算重。
CREATE OR REPLACE FUNCTION trg_mc_after_handover() RETURNS trigger AS $$
DECLARE ho timestamptz; st text;
BEGIN
    SELECT handover_at, status INTO ho, st FROM project WHERE id = NEW.project_id;
    IF ho IS NULL THEN
        RAISE EXCEPTION '门禁：项目尚未交付(当前状态 %)，不予受理维护单。交付前的问题请走安装剩余项或变更登记', st;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER mc_after_handover BEFORE INSERT ON maintenance_case
    FOR EACH ROW EXECUTE FUNCTION trg_mc_after_handover();

-- ★ 同一道门也卡派工：未交付项目不能派技术维护任务
CREATE OR REPLACE FUNCTION trg_mj_after_handover() RETURNS trigger AS $$
DECLARE ho timestamptz;
BEGIN
    SELECT handover_at INTO ho FROM project WHERE id = NEW.project_id;
    IF ho IS NULL THEN
        RAISE EXCEPTION '门禁：项目尚未交付，不能派技术维护任务(交付前的活属于安装调试)';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER mj_after_handover BEFORE INSERT ON maintenance_job
    FOR EACH ROW EXECUTE FUNCTION trg_mj_after_handover();

-- ★ 门禁：交付派工需 ①S4 已结清(硬卡，无后门) ②已有 ready 的交付条件确认
CREATE OR REPLACE FUNCTION trg_handover_gate() RETURNS trigger AS $$
DECLARE s4_ok boolean; rv text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT (status='settled') INTO s4_ok
          FROM payment_milestone WHERE project_id = NEW.project_id AND stage='S4';
        IF s4_ok IS DISTINCT FROM true THEN
            RAISE EXCEPTION '门禁：S4 尾款未结清，不能安排交付';
        END IF;
        SELECT decision INTO rv FROM delivery_review
         WHERE project_id = NEW.project_id ORDER BY reviewed_at DESC LIMIT 1;
        IF rv IS DISTINCT FROM 'ready' THEN
            RAISE EXCEPTION '门禁：工程管理尚未确认满足交付条件，不能安排交付';
        END IF;
    END IF;
    -- 完成交付必须有客户签字
    IF NEW.completed_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.completed_at IS NULL) THEN
        IF NEW.client_sign_url IS NULL OR NEW.client_sign_at IS NULL THEN
            RAISE EXCEPTION '门禁：缺少客户签收，不能完成交付';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER handover_gate BEFORE INSERT OR UPDATE ON handover_job
    FOR EACH ROW EXECUTE FUNCTION trg_handover_gate();

-- 交付完成 → 回写 project.handover_at + status（工程成本/运维成本分界线）
CREATE OR REPLACE FUNCTION trg_handover_done() RETURNS trigger AS $$
BEGIN
    IF NEW.completed_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.completed_at IS NULL) THEN
        UPDATE project SET handover_at = NEW.completed_at, status = 'delivered'
         WHERE id = NEW.project_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER handover_done AFTER INSERT OR UPDATE ON handover_job
    FOR EACH ROW EXECUTE FUNCTION trg_handover_done();

-- ★ 门禁：每日上报——超时(任一条线)且未填问题，不许提交
--    当天全是 SM 时不强制（SM 不报那 5 类问题）
CREATE OR REPLACE FUNCTION trg_daily_report_gate() RETURNS trigger AS $$
DECLARE thr numeric; std numeric; v_lunch numeric; v_lunch_min_span numeric;
        v_onsite numeric; v_span numeric; v_plan numeric; v_paid numeric;
        n_issue int; has_work boolean;
BEGIN
    IF NEW.submitted_at IS NULL OR (TG_OP='UPDATE' AND OLD.submitted_at IS NOT NULL) THEN
        RETURN NEW;
    END IF;

    SELECT value_num INTO thr FROM eng_setting WHERE key='overtime_threshold_min';
    SELECT value_num INTO std FROM eng_setting WHERE key='standard_workday_min';
    SELECT value_num INTO v_lunch FROM eng_setting WHERE key='lunch_break_min';
    SELECT value_num INTO v_lunch_min_span FROM eng_setting WHERE key='lunch_min_span_min';

    -- 在场总和 / 首尾时长（首尾含路上，澳洲规矩：付薪按首尾）
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (checkout_at-checkin_at))/60.0),0),
           COALESCE(EXTRACT(EPOCH FROM (MAX(checkout_at)-MIN(checkin_at)))/60.0,0)
      INTO v_onsite, v_span
      FROM work_log
     WHERE staff_id=NEW.staff_id AND checkin_at::date=NEW.report_date
       AND checkin_at IS NOT NULL AND checkout_at IS NOT NULL;

    -- 当天派活计划总和（四类任务）
    SELECT COALESCE(SUM(m),0) INTO v_plan FROM (
        SELECT planned_minutes m FROM site_meeting    WHERE owner_staff_id=NEW.staff_id AND scheduled_date=NEW.report_date
        UNION ALL SELECT planned_minutes FROM install_job     WHERE staff_id=NEW.staff_id AND scheduled_date=NEW.report_date
        UNION ALL SELECT planned_minutes FROM handover_job    WHERE staff_id=NEW.staff_id AND scheduled_date=NEW.report_date
        UNION ALL SELECT planned_minutes FROM maintenance_job WHERE staff_id=NEW.staff_id AND scheduled_date=NEW.report_date
    ) t;

    -- ★ 午餐：首尾够长就自动扣，不打卡、不可操纵
    IF v_span >= v_lunch_min_span THEN NEW.lunch_min := v_lunch; ELSE NEW.lunch_min := 0; END IF;
    v_paid := v_span - NEW.lunch_min;

    NEW.onsite_minutes  := round(v_onsite,1);
    NEW.span_minutes    := round(v_span,1);
    NEW.paid_minutes    := round(v_paid,1);
    NEW.planned_minutes := v_plan;
    -- 计划超时：比【在场时间】(午餐不在场，本就不含)
    NEW.over_plan_min   := round(v_onsite - v_plan, 1);
    -- 工时超时：比【付薪时长】(已扣午餐，否则天天虚超30分钟把门禁顶爆)
    NEW.over_span_min   := round(v_paid - std, 1);

    -- 当天有没有安装/维护任务（只有这两类才强制上报）
    SELECT EXISTS(SELECT 1 FROM install_job WHERE staff_id=NEW.staff_id AND scheduled_date=NEW.report_date)
        OR EXISTS(SELECT 1 FROM maintenance_job WHERE staff_id=NEW.staff_id AND scheduled_date=NEW.report_date)
      INTO has_work;

    IF has_work AND (NEW.over_plan_min > thr OR NEW.over_span_min > thr) THEN
        SELECT count(*) INTO n_issue FROM daily_issue WHERE report_id = NEW.id;
        IF n_issue = 0 THEN
            RAISE EXCEPTION '门禁：今日超时(计划超 % 分钟 / 工时超 % 分钟)，必须先填写问题上报才能提交',
                GREATEST(NEW.over_plan_min,0), GREATEST(NEW.over_span_min,0);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER daily_report_gate BEFORE INSERT OR UPDATE ON daily_report
    FOR EACH ROW EXECUTE FUNCTION trg_daily_report_gate();

-- 审计扩展
CREATE TRIGGER handover_audit AFTER INSERT OR UPDATE OR DELETE ON handover_job
    FOR EACH ROW EXECUTE FUNCTION trg_audit();
CREATE TRIGGER install_item_audit AFTER INSERT OR UPDATE OR DELETE ON install_item
    FOR EACH ROW EXECUTE FUNCTION trg_audit();


-- =====================================================================
--  v0.3 视图
-- =====================================================================

-- ① 路上时间 traffic time slot：上一站离场 → 下一站入场，自动派生，不落库
CREATE OR REPLACE VIEW v_travel_slot AS
WITH w AS (
    SELECT staff_id, project_id, checkin_at, checkout_at,
           checkin_at::date AS d,
           ROW_NUMBER() OVER (PARTITION BY staff_id, checkin_at::date ORDER BY checkin_at) AS rn
      FROM work_log
     WHERE checkin_at IS NOT NULL AND checkout_at IS NOT NULL
)
SELECT a.staff_id, a.d AS travel_date, a.rn AS seq,
       a.project_id AS from_project_id, b.project_id AS to_project_id,
       a.checkout_at AS depart_at, b.checkin_at AS arrive_at,
       round((EXTRACT(EPOCH FROM (b.checkin_at - a.checkout_at))/60.0)::numeric,1) AS travel_min,
       -- ★ 这段是否跨午餐锚点：提醒工程管理别把吃饭误判成路上异常
       ((a.d + (SELECT value_text FROM eng_setting WHERE key='lunch_anchor_time')::time)
         BETWEEN a.checkout_at AND b.checkin_at) AS crosses_lunch
  FROM w a JOIN w b ON b.staff_id=a.staff_id AND b.d=a.d AND b.rn=a.rn+1;

-- ② 路上时间 vs Google 两版预估（三个数并排，分开“路上慢”与“出发晚”）
CREATE OR REPLACE VIEW v_travel_check AS
SELECT t.*,
       pe.duration_min AS planned_est_min, pe.depart_at AS planned_depart_at,
       ae.duration_min AS actual_est_min,
       round(t.travel_min - ae.duration_min,1) AS vs_actual_est,   -- 路上正不正常
       round(ae.duration_min - pe.duration_min,1) AS vs_planned_est-- 是不是出发晚撞高峰
  FROM v_travel_slot t
  LEFT JOIN travel_estimate pe ON pe.staff_id=t.staff_id AND pe.travel_date=t.travel_date
       AND pe.seq=t.seq AND pe.kind='planned'
  LEFT JOIN travel_estimate ae ON ae.staff_id=t.staff_id AND ae.travel_date=t.travel_date
       AND ae.seq=t.seq AND ae.kind='actual';

-- ③ 每人每天考勤汇总（现算，给上报页和工程管理看板）
CREATE OR REPLACE VIEW v_daily_attendance AS
SELECT w.staff_id, w.checkin_at::date AS work_date,
       round(SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/60.0)::numeric,1) AS onsite_min,
       round((EXTRACT(EPOCH FROM (MAX(w.checkout_at)-MIN(w.checkin_at)))/60.0)::numeric,1) AS span_min,
       round((EXTRACT(EPOCH FROM (MAX(w.checkout_at)-MIN(w.checkin_at)))/60.0
              - SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/60.0))::numeric,1) AS travel_min,
       COUNT(DISTINCT w.project_id) AS project_count,
       CASE WHEN EXTRACT(EPOCH FROM (MAX(w.checkout_at)-MIN(w.checkin_at)))/60.0
                 >= (SELECT value_num FROM eng_setting WHERE key='lunch_min_span_min')
            THEN (SELECT value_num FROM eng_setting WHERE key='lunch_break_min') ELSE 0 END AS lunch_min,
       round((EXTRACT(EPOCH FROM (MAX(w.checkout_at)-MIN(w.checkin_at)))/60.0)::numeric
             - CASE WHEN EXTRACT(EPOCH FROM (MAX(w.checkout_at)-MIN(w.checkin_at)))/60.0
                         >= (SELECT value_num FROM eng_setting WHERE key='lunch_min_span_min')
                    THEN (SELECT value_num FROM eng_setting WHERE key='lunch_break_min') ELSE 0 END,1) AS paid_min
  FROM work_log w
 WHERE w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL
 GROUP BY w.staff_id, w.checkin_at::date;

-- ④ 工程流水账·时间轴维度（交付前工程管理人肉核对用）
CREATE OR REPLACE VIEW v_project_worklog_timeline AS
SELECT w.project_id, p.code AS project_code,
       w.checkin_at::date AS work_date,
       s.name AS staff_name, w.work_type,
       w.checkin_at, w.checkout_at,
       round((EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0)::numeric,2) AS hours,
       w.checkin_method, w.checkin_flagged, w.left_area_flag, w.note
  FROM work_log w
  JOIN project p ON p.id=w.project_id
  LEFT JOIN eng_staff s ON s.id=w.staff_id
 WHERE w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL;

-- ⑤ 工程流水账·人员维度（KPI 考核用：某人在本项目投入多少、干了什么）
CREATE OR REPLACE VIEW v_project_staff_effort AS
SELECT w.project_id, p.code AS project_code, w.staff_id, s.name AS staff_name,
       COUNT(*) AS visit_count,
       MIN(w.checkin_at)::date AS first_day, MAX(w.checkout_at)::date AS last_day,
       round(SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0)::numeric,2) AS total_hours,
       round(SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0*s.cost_hourly_rate)::numeric,2) AS labor_cost,
       SUM(CASE WHEN w.work_type='sm' THEN 1 ELSE 0 END)          AS sm_visits,
       SUM(CASE WHEN w.work_type='execution' THEN 1 ELSE 0 END)   AS install_visits,
       SUM(CASE WHEN w.work_type='handover' THEN 1 ELSE 0 END)    AS handover_visits,
       SUM(CASE WHEN w.work_type='maintenance' THEN 1 ELSE 0 END) AS maint_visits,
       SUM(CASE WHEN w.checkin_flagged THEN 1 ELSE 0 END)         AS flagged_checkins
  FROM work_log w
  JOIN project p ON p.id=w.project_id
  LEFT JOIN eng_staff s ON s.id=w.staff_id
 WHERE w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL
 GROUP BY w.project_id, p.code, w.staff_id, s.name;

-- ⑥ 安装剩余情况（负责人点“完工”前看的那一屏）
CREATE OR REPLACE VIEW v_install_remaining AS
SELECT project_id,
       SUM(CASE WHEN status='pending'      THEN 1 ELSE 0 END) AS pending_cnt,
       SUM(CASE WHEN status='done'         THEN 1 ELSE 0 END) AS done_cnt,
       SUM(CASE WHEN status='cancelled'    THEN 1 ELSE 0 END) AS cancelled_cnt,
       SUM(CASE WHEN status='suspended'    THEN 1 ELSE 0 END) AS suspended_cnt,
       SUM(CASE WHEN status='to_variation' THEN 1 ELSE 0 END) AS to_variation_cnt
  FROM install_item GROUP BY project_id;

-- ⑨ 午餐扣在谁头上（成本口径要跟发薪口径一致，否则项目利润率虚高）
--    锚点落在路上段 → 扣下一站项目；落在某个工地 → 扣该项目；短工日不扣
CREATE VIEW v_daily_lunch AS
WITH cfg AS (
    SELECT (SELECT value_num  FROM eng_setting WHERE key='lunch_break_min')    AS lunch_min,
           (SELECT value_num  FROM eng_setting WHERE key='lunch_min_span_min') AS min_span,
           (SELECT value_text FROM eng_setting WHERE key='lunch_anchor_time')::time AS anchor
), day AS (
    SELECT staff_id, checkin_at::date AS d,
           EXTRACT(EPOCH FROM (MAX(checkout_at)-MIN(checkin_at)))/60.0 AS span_min
      FROM work_log WHERE checkin_at IS NOT NULL AND checkout_at IS NOT NULL
     GROUP BY staff_id, checkin_at::date
)
SELECT d.staff_id, d.d AS work_date, cfg.lunch_min,
       COALESCE(
         (SELECT t.to_project_id FROM v_travel_slot t
           WHERE t.staff_id=d.staff_id AND t.travel_date=d.d
             AND (d.d + cfg.anchor) BETWEEN t.depart_at AND t.arrive_at LIMIT 1),
         (SELECT w.project_id FROM work_log w
           WHERE w.staff_id=d.staff_id AND w.checkin_at::date=d.d
             AND (d.d + cfg.anchor) BETWEEN w.checkin_at AND w.checkout_at LIMIT 1)
       ) AS charged_project_id
  FROM day d CROSS JOIN cfg
 WHERE d.span_min >= cfg.min_span;

-- ⑦ 项目人工成本（★v0.3 修正：路上时间也付薪，摊给下一站项目）
--    列结构变了，先拆掉 v0.2 版本及其下游视图，再重建
DROP VIEW IF EXISTS v_labor_consumption;
DROP VIEW IF EXISTS v_project_labor_cost;
CREATE VIEW v_project_labor_cost AS
WITH onsite AS (
    SELECT w.project_id,
           SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0) AS h,
           SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0*s.cost_hourly_rate) AS c
      FROM work_log w JOIN eng_staff s ON s.id=w.staff_id
     WHERE w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL
     GROUP BY w.project_id
), lunch AS (
    SELECT charged_project_id AS project_id, SUM(lunch_min)/60.0 AS h,
           SUM(lunch_min/60.0*s.cost_hourly_rate) AS c
      FROM v_daily_lunch l JOIN eng_staff s ON s.id=l.staff_id
     WHERE charged_project_id IS NOT NULL GROUP BY charged_project_id
), travel AS (
    SELECT t.to_project_id AS project_id,
           SUM(t.travel_min/60.0) AS h,
           SUM(t.travel_min/60.0*s.cost_hourly_rate) AS c
      FROM v_travel_slot t JOIN eng_staff s ON s.id=t.staff_id
     GROUP BY t.to_project_id
)
SELECT p.id AS project_id,
       round(COALESCE(o.h,0)::numeric,2)               AS onsite_hours,
       round(COALESCE(tr.h,0)::numeric,2)              AS travel_hours,
       round(COALESCE(lu.h,0)::numeric,2)              AS lunch_hours,
       round((COALESCE(o.h,0)+COALESCE(tr.h,0)-COALESCE(lu.h,0))::numeric,2) AS actual_hours,
       round(COALESCE(o.c,0)::numeric,2)               AS onsite_cost,
       round(COALESCE(tr.c,0)::numeric,2)              AS travel_cost,
       round(COALESCE(lu.c,0)::numeric,2)              AS lunch_deduct,
       round((COALESCE(o.c,0)+COALESCE(tr.c,0)-COALESCE(lu.c,0))::numeric,2) AS labor_cost
  FROM project p
  LEFT JOIN onsite o ON o.project_id=p.id
  LEFT JOIN travel tr ON tr.project_id=p.id
  LEFT JOIN lunch lu ON lu.project_id=p.id;


-- ⑧ 人工消耗百分比（重建：分子现在含路上时间）
CREATE VIEW v_labor_consumption AS
SELECT p.id AS project_id, p.code,
       p.planned_labor_hours,
       lc.onsite_hours, lc.travel_hours, lc.actual_hours,
       CASE WHEN p.planned_labor_hours > 0
            THEN round((lc.actual_hours / p.planned_labor_hours * 100)::numeric, 1)
            ELSE NULL END AS consumption_pct
  FROM project p LEFT JOIN v_project_labor_cost lc ON lc.project_id = p.id;

-- 后置外键：project.install_completed_by → eng_staff
ALTER TABLE project ADD CONSTRAINT fk_project_install_by
    FOREIGN KEY (install_completed_by) REFERENCES eng_staff(id);




-- #####################################################################
-- ##  v0.4 新增：财务(应收/实收/结清/超期) + 维保 + 长期利润率
-- #####################################################################

INSERT INTO eng_setting(key, value_num, note) VALUES
 ('overdue_days',        30, '超期天数：Invoice 发出后多少天未结清算超期(只提示，不作废合同)'),
 ('suspend_notice_days', 90, '拒付停服后多少天，提醒停用服务器(市场发声明后执行)');

-- 后置外键：维护应收单 → 维护单
ALTER TABLE payment_milestone
    ADD CONSTRAINT fk_pm_case FOREIGN KEY (case_id) REFERENCES maintenance_case(id);


-- =====================================================================
--  v0.4 触发器
-- =====================================================================

-- ★ 应收定格：发出 Invoice 那一刻，金额焊死
--    发出前 amount_due 为空 → 按 签约价×比例 现算带出(S4 叠加变更)
--    已发出后不许改金额；要改就 invoice_ver +1 重发
CREATE OR REPLACE FUNCTION trg_pm_amount_lock() RETURNS trigger AS $$
DECLARE cp numeric; var_sum numeric;
BEGIN
    IF NEW.invoice_sent_at IS NOT NULL
       AND (TG_OP='INSERT' OR OLD.invoice_sent_at IS NULL OR NEW.invoice_ver > OLD.invoice_ver) THEN
        IF NEW.amount_due IS NULL AND NEW.kind='contract' THEN
            SELECT contract_price INTO cp FROM project WHERE id=NEW.project_id;
            SELECT COALESCE(SUM(settle_amount),0) INTO var_sum
              FROM variation WHERE project_id=NEW.project_id;
            NEW.amount_due := round(cp * NEW.ratio_pct / 100, 2)
                              + CASE WHEN NEW.stage='S4' THEN var_sum ELSE 0 END;
        END IF;
        IF NEW.amount_due IS NULL THEN
            RAISE EXCEPTION '门禁：应收金额为空，不能发出 Invoice';
        END IF;
        IF NEW.first_invoice_sent_at IS NULL THEN
            NEW.first_invoice_sent_at := NEW.invoice_sent_at;   -- 账龄起点，改版不动
        END IF;
        IF NEW.status='pending' THEN NEW.status := 'invoiced'; END IF;
    END IF;

    -- 已发出后改金额，必须同时升版本
    IF TG_OP='UPDATE' AND OLD.invoice_sent_at IS NOT NULL
       AND NEW.amount_due IS DISTINCT FROM OLD.amount_due
       AND NEW.invoice_ver = OLD.invoice_ver THEN
        RAISE EXCEPTION '门禁：Invoice 已发出(客户手上那张写的是 %)，改金额必须 invoice_ver +1 重开新版',
            OLD.amount_due;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER pm_amount_lock BEFORE INSERT OR UPDATE ON payment_milestone
    FOR EACH ROW EXECUTE FUNCTION trg_pm_amount_lock();

-- ★ 结清门禁：足额自动过；不足额可点但必须填原因，差额定格落库
CREATE OR REPLACE FUNCTION trg_pm_settle_gate() RETURNS trigger AS $$
DECLARE got numeric; gap numeric;
BEGIN
    IF NEW.status='settled' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM 'settled') THEN
        SELECT COALESCE(SUM(amount),0) INTO got FROM payment_receipt WHERE milestone_id=NEW.id;
        gap := COALESCE(NEW.amount_due,0) - got;
        IF gap > 0 AND (NEW.settle_reason IS NULL OR btrim(NEW.settle_reason)='') THEN
            RAISE EXCEPTION '门禁：还差 % 未收到，不足额结清必须填写原因(留痕)', gap;
        END IF;
        NEW.shortfall_amount := GREATEST(gap, 0);      -- 批准当时的差额，定格
        IF NEW.settled_at IS NULL THEN NEW.settled_at := now(); END IF;
        IF NEW.settled_by IS NULL THEN
            NEW.settled_by := current_setting('app.actor', true);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER pm_settle_gate BEFORE INSERT OR UPDATE ON payment_milestone
    FOR EACH ROW EXECUTE FUNCTION trg_pm_settle_gate();

-- 收到钱 → 自动置 partial（系统判，不用人点；settled 仍只能财务点）
CREATE OR REPLACE FUNCTION trg_receipt_partial() RETURNS trigger AS $$
BEGIN
    UPDATE payment_milestone SET status='partial'
     WHERE id=NEW.milestone_id AND status IN ('pending','invoiced');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER receipt_partial AFTER INSERT ON payment_receipt
    FOR EACH ROW EXECUTE FUNCTION trg_receipt_partial();

-- ★ 停服门禁：项目被标拒付停服后，不能再派任何新任务(全面停服)
CREATE OR REPLACE FUNCTION trg_service_suspended_gate() RETURNS trigger AS $$
DECLARE sus timestamptz; res timestamptz;
BEGIN
    SELECT service_suspended_at, service_resumed_at INTO sus, res
      FROM project WHERE id=NEW.project_id;
    IF sus IS NOT NULL AND (res IS NULL OR res < sus) THEN
        RAISE EXCEPTION '门禁：该项目因客户拒付已全面停服(停服时间 %)，不能派新任务', sus;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER install_suspended_gate BEFORE INSERT ON install_job
    FOR EACH ROW EXECUTE FUNCTION trg_service_suspended_gate();
CREATE TRIGGER maint_suspended_gate BEFORE INSERT ON maintenance_job
    FOR EACH ROW EXECUTE FUNCTION trg_service_suspended_gate();

-- ★ 维护结案门禁：故障归因未填，不许结案（归因决定收不收费）
CREATE OR REPLACE FUNCTION trg_mc_close_gate() RETURNS trigger AS $$
DECLARE ho timestamptz; fw integer;
BEGIN
    IF NEW.status='paid_closed' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM 'paid_closed') THEN
        IF NEW.fault_cause IS NULL THEN
            RAISE EXCEPTION '门禁：故障归因未填(非人为/人为/不可抗力)，不能结案';
        END IF;
        -- 结案时定格：本单是否属免责维保覆盖
        SELECT handover_at, free_warranty_months INTO ho, fw FROM project WHERE id=NEW.project_id;
        -- 免责维保覆盖 = 非人为(产品缺陷/自然老化) 且 在免责期内
        NEW.is_free_warranty := (NEW.fault_cause IN ('product_defect','wear_out')
                                 AND ho IS NOT NULL
                                 AND NEW.created_at < ho + (fw || ' months')::interval);
        IF NEW.closed_at IS NULL THEN NEW.closed_at := now(); END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER mc_close_gate BEFORE INSERT OR UPDATE ON maintenance_case
    FOR EACH ROW EXECUTE FUNCTION trg_mc_close_gate();

-- ★ 交付完成 → 顺带定格工程利润率（原 trg_handover_done 增强）
CREATE OR REPLACE FUNCTION trg_handover_done() RETURNS trigger AS $$
DECLARE rev numeric; proc numeric; lab numeric; m numeric;
BEGIN
    IF NEW.completed_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.completed_at IS NULL) THEN
        SELECT COALESCE(p.contract_price,0)
             + COALESCE((SELECT SUM(settle_amount) FROM variation WHERE project_id=p.id),0)
          INTO rev FROM project p WHERE p.id=NEW.project_id;
        SELECT COALESCE(SUM(cost_amount),0) INTO proc FROM procurement WHERE project_id=NEW.project_id;
        SELECT COALESCE(labor_cost,0) INTO lab FROM v_project_labor_cost WHERE project_id=NEW.project_id;
        m := CASE WHEN rev > 0 THEN round((rev - proc - lab)/rev*100, 3) ELSE NULL END;
        UPDATE project SET handover_at = NEW.completed_at, status='delivered',
               eng_margin_locked = m, eng_margin_locked_at = NEW.completed_at
         WHERE id = NEW.project_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
--  v0.4 视图
-- =====================================================================

-- ⑩ 应收 vs 实收（现算：已收多少、还差多少；现金/走账分列）
CREATE VIEW v_milestone_settlement AS
SELECT m.id AS milestone_id, m.project_id, m.kind, m.stage, m.case_id,
       m.amount_due, m.status, m.invoice_no, m.invoice_ver,
       COALESCE(r.got,0)                      AS received,
       COALESCE(r.got_bank,0)                 AS received_bank,
       COALESCE(r.got_cash,0)                 AS received_cash,
       COALESCE(r.gst,0)                      AS received_gst,
       round(COALESCE(m.amount_due,0)-COALESCE(r.got,0),2) AS outstanding,
       m.shortfall_amount, m.settle_reason, m.settled_at, m.settled_by
  FROM payment_milestone m
  LEFT JOIN (
     SELECT milestone_id, SUM(amount) got, SUM(gst_amount) gst,
            SUM(CASE WHEN method='bank' THEN amount ELSE 0 END) got_bank,
            SUM(CASE WHEN method='cash' THEN amount ELSE 0 END) got_cash
       FROM payment_receipt GROUP BY milestone_id) r ON r.milestone_id=m.id;

-- ⑪ 超期（不作废合同，只提示催账）：本期超期 + 账龄，两个都显示
CREATE VIEW v_overdue AS
SELECT s.*, p.code AS project_code,
       (now()::date - m.invoice_sent_at::date)       AS overdue_days_current, -- 最后一版起(改版归零)
       (now()::date - m.first_invoice_sent_at::date) AS aging_days,           -- 第一版起(改版抹不掉)
       (SELECT value_num FROM eng_setting WHERE key='overdue_days') AS overdue_threshold,
       ((now()::date - m.invoice_sent_at::date)
         > (SELECT value_num FROM eng_setting WHERE key='overdue_days')) AS is_overdue
  FROM v_milestone_settlement s
  JOIN payment_milestone m ON m.id=s.milestone_id
  JOIN project p ON p.id=s.project_id
 WHERE m.invoice_sent_at IS NOT NULL AND m.status <> 'settled';

-- ⑫ 停服提醒（拒付后 N 天提醒停用服务器；系统只告知，人去执行）
CREATE VIEW v_service_suspension AS
SELECT p.id AS project_id, p.code, p.service_suspended_at, p.service_suspended_reason,
       (now()::date - p.service_suspended_at::date) AS suspended_days,
       ((now()::date - p.service_suspended_at::date)
         >= (SELECT value_num FROM eng_setting WHERE key='suspend_notice_days')) AS server_shutdown_due
  FROM project p
 WHERE p.service_suspended_at IS NOT NULL
   AND (p.service_resumed_at IS NULL OR p.service_resumed_at < p.service_suspended_at);

-- ⑬ 两套维保钟：免责维保(交付起) + 物料保修(S2 结清起，按采购单)
CREATE VIEW v_warranty AS
SELECT p.id AS project_id, p.code,
       p.handover_at,
       p.free_warranty_months,
       (p.handover_at + (p.free_warranty_months || ' months')::interval) AS free_warranty_until,
       (now() < p.handover_at + (p.free_warranty_months || ' months')::interval) AS in_free_warranty,
       s2.settled_at AS s2_settled_at,
       (SELECT MIN(pr.warranty_months) FROM procurement pr WHERE pr.project_id=p.id) AS min_material_months,
       (SELECT MAX(pr.warranty_months) FROM procurement pr WHERE pr.project_id=p.id) AS max_material_months,
       -- ★ 交付当日显示：物料保修还剩多少个月(施工拖越久，烧掉越多)
       CASE WHEN s2.settled_at IS NOT NULL AND p.handover_at IS NOT NULL THEN
         round(((SELECT MIN(pr.warranty_months) FROM procurement pr WHERE pr.project_id=p.id)
               - EXTRACT(EPOCH FROM (p.handover_at - s2.settled_at))/2592000.0)::numeric,1)
       END AS material_months_left_at_handover
  FROM project p
  LEFT JOIN payment_milestone s2
         ON s2.project_id=p.id AND s2.kind='contract' AND s2.stage='S2';

-- ⑭ 各批采购的物料保修到期（在保/过保最终由人判断，系统只摊事实）
CREATE VIEW v_material_warranty AS
SELECT pr.project_id, pr.id AS procurement_id, pr.supplier, pr.warranty_months,
       s2.settled_at AS starts_at,
       (s2.settled_at + (pr.warranty_months || ' months')::interval) AS expires_at,
       (now() < s2.settled_at + (pr.warranty_months || ' months')::interval) AS still_covered
  FROM procurement pr
  JOIN payment_milestone s2 ON s2.project_id=pr.project_id AND s2.kind='contract' AND s2.stage='S2'
 WHERE pr.warranty_months IS NOT NULL AND s2.settled_at IS NOT NULL;

-- ⑮ 长期利润率 = 工程利润(交付定格) + Σ(运维收费 − 运维人力 − 运维物料)
--    免责维保单收入为 0，但成本照记 → 免掉多少钱一目了然
CREATE VIEW v_long_term_margin AS
WITH mrev AS (
    SELECT m.project_id, SUM(COALESCE(r.got,0)) AS maint_revenue
      FROM payment_milestone m
      LEFT JOIN (SELECT milestone_id, SUM(amount) got FROM payment_receipt GROUP BY milestone_id) r
             ON r.milestone_id=m.id
     WHERE m.kind='maintenance' GROUP BY m.project_id
), mcost AS (
    SELECT project_id,
           SUM(COALESCE(labor_cost,0))    AS maint_labor,
           SUM(COALESCE(material_cost,0)) AS maint_material,
           SUM(CASE WHEN is_free_warranty THEN COALESCE(labor_cost,0)+COALESCE(material_cost,0)
                    ELSE 0 END)           AS free_warranty_cost   -- 免责维保共免掉多少
      FROM maintenance_case      -- v0.8：维护单必然是交付后的，无需再过滤成本归属
     GROUP BY project_id
)
SELECT p.id AS project_id, p.code,
       p.contract_price, p.eng_margin_locked,
       round(COALESCE(p.contract_price,0)*COALESCE(p.eng_margin_locked,0)/100,2) AS eng_profit,
       COALESCE(mr.maint_revenue,0)  AS maint_revenue,
       COALESCE(mc.maint_labor,0)    AS maint_labor,
       COALESCE(mc.maint_material,0) AS maint_material,
       COALESCE(mc.free_warranty_cost,0) AS free_warranty_cost,
       round(COALESCE(p.contract_price,0)*COALESCE(p.eng_margin_locked,0)/100
             + COALESCE(mr.maint_revenue,0) - COALESCE(mc.maint_labor,0)
             - COALESCE(mc.maint_material,0), 2) AS long_term_profit
  FROM project p
  LEFT JOIN mrev mr ON mr.project_id=p.id
  LEFT JOIN mcost mc ON mc.project_id=p.id;


-- #####################################################################
-- ##  v0.5 新增：日结工资(当夜0点定格) + 加班与倒休 + 月度工资单
-- #####################################################################

INSERT INTO eng_setting(key, value_num, note) VALUES
 ('payroll_cycle_start_day', 21, '工资周期起日：上月21日 → 本月20日，21日封账即发放'),
 ('ot_rate_weekday',        1.0, '时薪制·平日加班倍数(默认1.0，按 Award/EA 调)'),
 ('ot_rate_saturday',       1.0, '时薪制·周六倍数'),
 ('ot_rate_sunday',         1.0, '时薪制·周日倍数'),
 ('ot_rate_holiday',        1.0, '时薪制·公共假日倍数');
-- v0.31 ★加班倍数由财务手动维护（用户 2026-07-30 定：暂全 1.0，财务可改）
UPDATE eng_setting SET write_depts = ARRAY['eng_mgmt','finance']
 WHERE key IN ('ot_rate_weekday','ot_rate_saturday','ot_rate_sunday','ot_rate_holiday');
-- v0.33 ★超期天数开放给财务共写（催账口径归财务把握；此处在写权限门禁触发器创建之前）
UPDATE eng_setting SET write_depts = ARRAY['eng_mgmt','finance']
 WHERE key='overdue_days';

-- =====================================================================
--  第二十一部分：公共假日 public_holiday（NSW，一年更新一次）
--    加班判定 C：平日超时 + 周末整天 + 公共假日整天
-- =====================================================================
CREATE TABLE public_holiday (
    holiday_date date PRIMARY KEY,
    name         text NOT NULL,
    state        text NOT NULL DEFAULT 'NSW',
    created_at   timestamptz NOT NULL DEFAULT now()
);
-- NSW 2026（12 天，核对自 Fair Work Ombudsman 官方名单）
--  ⚠️ NSW 的 Anzac Day 落在周六【不补假】(补假只有 ACT / WA 有，别被第三方网站误导)
--  ⚠️ 8月第一个周一的 Bank Holiday 只适用银行与部分金融机构，【不是】全民公众假日
--  ⚠️ 本表一年更新一次。2027 起的日期请上线前从 Fair Work 官方名单核对后录入，
--     宁可空着(当普通日算)也不要凭记忆填错——填错会直接算错加班与倒休。
INSERT INTO public_holiday(holiday_date, name) VALUES
 ('2026-01-01','New Year''s Day'),
 ('2026-01-26','Australia Day'),
 ('2026-04-03','Good Friday'),
 ('2026-04-04','Easter Saturday'),      -- NSW 有，不是所有州都有
 ('2026-04-05','Easter Sunday'),
 ('2026-04-06','Easter Monday'),
 ('2026-04-25','Anzac Day'),            -- 周六，NSW 不补假
 ('2026-06-08','King''s Birthday'),
 ('2026-10-05','Labour Day'),
 ('2026-12-25','Christmas Day'),
 ('2026-12-26','Boxing Day'),           -- 周六
 ('2026-12-28','Additional public holiday for Boxing Day');


-- =====================================================================
--  第二十二部分：日结工资 daily_payroll（★当夜 0 点定格，一人一天一条）
--    定格后就是死的：补录只能滚到下个月补发，本条不改
--    行数按实际出工天数走，加班日/周末照样成行
-- =====================================================================
CREATE TABLE daily_payroll (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id     uuid NOT NULL REFERENCES eng_staff(id),
    work_date    date NOT NULL,

    -- 当天性质（决定加班怎么算）
    day_type     text NOT NULL CHECK (day_type IN ('weekday','saturday','sunday','holiday')),

    -- 时长（分钟，全部定格）
    span_min     numeric(8,1),        -- 首尾（澳洲规矩：路上不克扣）
    lunch_min    numeric(8,1),        -- 自动扣的午餐(无薪)
    paid_min     numeric(8,1),        -- 付薪时长 = 首尾 − 午餐
    normal_min   numeric(8,1),        -- 正常工时
    ot_min       numeric(8,1),        -- ★加班分钟：平日超8h部分；周末/假日整天

    -- ★ 制度与费率一并定格（8月加薪，7月的单仍按当时的算）
    pay_type_snap    text NOT NULL,
    pay_rate_snap    numeric(10,2),   -- 时薪制当时的发薪时薪
    cost_rate_snap   numeric(10,2),   -- 当时的成本时薪
    ot_rate_snap     numeric(5,2),    -- 当天适用的加班倍数
    pay_amount       numeric(12,2),   -- 时薪制当日应发；月薪制为 NULL(月固定)

    -- 状态：正常定格 / 未记录挂起 / 补录后放行
    status       text NOT NULL DEFAULT 'locked' CHECK (status IN
                   ('locked','unrecorded_held','released')),
    unrecorded   boolean NOT NULL DEFAULT false,   -- ★KPI 用：这天没记录
    backfilled_by uuid REFERENCES eng_staff(id),   -- 负责人补录
    backfilled_at timestamptz,
    -- ★ v0.34 补录收紧（三十二轮定）：原因类别+详细说明(≥10字)+补录人 缺一不可（trg_dp_backfill_gate）
    backfill_reason_cat text CHECK (backfill_reason_cat IS NULL OR backfill_reason_cat IN
                   ('forgot_punch','gps_issue','device_issue','adhoc_dispatch','other')),
    backfill_note text,

    locked_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (staff_id, work_date)
);
CREATE INDEX idx_dp_staff ON daily_payroll(staff_id, work_date);
COMMENT ON TABLE daily_payroll IS '当夜0点定格，一旦落库不改；补录只影响下月补发';


-- =====================================================================
--  第二十三部分：倒休流水 toil_ledger（只增不改，余额视图现算）
--    月薪制不发加班工资，加班时长累计换倒休
-- =====================================================================
CREATE TABLE toil_ledger (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id     uuid NOT NULL REFERENCES eng_staff(id),
    entry_type   text NOT NULL CHECK (entry_type IN ('accrue','take','adjust')),
    minutes      numeric(8,1) NOT NULL,          -- accrue 为正、take 为负、adjust 可正可负
    ref_payroll_id uuid REFERENCES daily_payroll(id),  -- 由哪天的加班产生
    reason       text,
    created_by   text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_toil_sign CHECK (
        (entry_type='accrue' AND minutes > 0) OR
        (entry_type='take'   AND minutes < 0) OR
        (entry_type='adjust'))
);
CREATE INDEX idx_toil_staff ON toil_ledger(staff_id);


-- =====================================================================
--  第二十四部分：月度工资单 payroll_month
--    周期 = 上月21日 → 本月20日；21日封账即发放
--    ★不再存每日明细——日结已定格，这里只做加总
-- =====================================================================
CREATE TABLE payroll_month (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id     uuid NOT NULL REFERENCES eng_staff(id),
    period_start date NOT NULL,                  -- 上月21日
    period_end   date NOT NULL,                  -- 本月20日
    pay_type_snap text NOT NULL,
    work_days    integer,
    paid_min     numeric(10,1),
    normal_min   numeric(10,1),
    ot_min       numeric(10,1),
    base_amount  numeric(12,2),                  -- 月薪制=月薪；时薪制=正常工时工资
    ot_amount    numeric(12,2),                  -- 时薪制加班工资；月薪制为0(转倒休)
    toil_accrued_min numeric(10,1),              -- 月薪制本期累计的倒休
    backpay_amount numeric(12,2) DEFAULT 0,      -- ★上期补录产生的补发
    total_amount numeric(12,2),
    held_days    integer DEFAULT 0,              -- 本期有几天因未记录被挂起(不计入)
    locked_at    timestamptz NOT NULL DEFAULT now(),
    locked_by    text,
    UNIQUE (staff_id, period_start)
);


-- =====================================================================
--  v0.5 函数与触发器
-- =====================================================================

-- ★ 当夜 0 点定格：由定时任务对每个员工每天调用一次
CREATE OR REPLACE FUNCTION fn_lock_daily_payroll(p_staff uuid, p_date date)
RETURNS uuid AS $$
DECLARE v_span numeric; v_lunch numeric; v_paid numeric;
        v_normal numeric; v_ot numeric; v_daytype text; v_std numeric;
        v_lunch_cfg numeric; v_minspan numeric; v_otrate numeric;
        st eng_staff%ROWTYPE; v_reported boolean; v_id uuid; v_amount numeric;
BEGIN
    SELECT * INTO st FROM eng_staff WHERE id = p_staff;
    SELECT value_num INTO v_std        FROM eng_setting WHERE key='standard_workday_min';
    SELECT value_num INTO v_lunch_cfg  FROM eng_setting WHERE key='lunch_break_min';
    SELECT value_num INTO v_minspan    FROM eng_setting WHERE key='lunch_min_span_min';

    -- 当天性质
    v_daytype := CASE
        WHEN EXISTS(SELECT 1 FROM public_holiday WHERE holiday_date=p_date) THEN 'holiday'
        WHEN EXTRACT(DOW FROM p_date)=6 THEN 'saturday'
        WHEN EXTRACT(DOW FROM p_date)=0 THEN 'sunday'
        ELSE 'weekday' END;
    SELECT value_num INTO v_otrate FROM eng_setting
     WHERE key = 'ot_rate_' || CASE v_daytype WHEN 'weekday' THEN 'weekday'
            WHEN 'saturday' THEN 'saturday' WHEN 'sunday' THEN 'sunday' ELSE 'holiday' END;

    -- 首尾 / 午餐 / 付薪
    SELECT COALESCE(EXTRACT(EPOCH FROM (MAX(checkout_at)-MIN(checkin_at)))/60.0, 0)
      INTO v_span FROM work_log
     WHERE staff_id=p_staff AND checkin_at::date=p_date
       AND checkin_at IS NOT NULL AND checkout_at IS NOT NULL;
    v_lunch := CASE WHEN v_span >= v_minspan THEN v_lunch_cfg ELSE 0 END;
    v_paid  := GREATEST(v_span - v_lunch, 0);

    -- ★加班判定 C：平日超标准工时的部分；周末/公共假日整天
    IF v_daytype='weekday' THEN
        v_ot     := GREATEST(v_paid - v_std, 0);
        v_normal := v_paid - v_ot;
    ELSE
        v_ot     := v_paid;
        v_normal := 0;
    END IF;

    -- 当日是否有记录（有工时 或 有当日上报）
    v_reported := (v_span > 0) OR EXISTS(
        SELECT 1 FROM daily_report WHERE staff_id=p_staff AND report_date=p_date
                                     AND submitted_at IS NOT NULL);

    -- 时薪制当日应发；月薪制为 NULL(每月固定)
    v_amount := CASE WHEN st.pay_type='hourly'
                THEN round((v_normal/60.0*st.pay_hourly_rate)
                         + (v_ot/60.0*st.pay_hourly_rate*COALESCE(v_otrate,1)), 2)
                END;

    INSERT INTO daily_payroll(staff_id, work_date, day_type, span_min, lunch_min, paid_min,
        normal_min, ot_min, pay_type_snap, pay_rate_snap, cost_rate_snap, ot_rate_snap,
        pay_amount, status, unrecorded)
    VALUES (p_staff, p_date, v_daytype, round(v_span,1), v_lunch, round(v_paid,1),
        round(v_normal,1), round(v_ot,1), st.pay_type, st.pay_hourly_rate, st.cost_hourly_rate,
        COALESCE(v_otrate,1), v_amount,
        CASE WHEN v_reported THEN 'locked' ELSE 'unrecorded_held' END,
        NOT v_reported)
    RETURNING id INTO v_id;

    -- 月薪制：加班不发钱，累计倒休（只增不改的流水）
    IF st.pay_type='monthly' AND v_ot > 0 AND v_reported THEN
        INSERT INTO toil_ledger(staff_id, entry_type, minutes, ref_payroll_id, reason, created_by)
        VALUES (p_staff, 'accrue', round(v_ot,1), v_id,
                p_date || ' ' || v_daytype || ' 加班累计', 'system');
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ★ 定格即不可改：日结落库后只允许"补录放行"，其余字段一律不许动
CREATE OR REPLACE FUNCTION trg_daily_payroll_immutable() RETURNS trigger AS $$
BEGIN
    IF NEW.span_min IS DISTINCT FROM OLD.span_min
       OR NEW.paid_min IS DISTINCT FROM OLD.paid_min
       OR NEW.ot_min IS DISTINCT FROM OLD.ot_min
       OR NEW.pay_amount IS DISTINCT FROM OLD.pay_amount
       OR NEW.pay_rate_snap IS DISTINCT FROM OLD.pay_rate_snap THEN
        RAISE EXCEPTION '门禁：日结工资已于 % 定格，不能修改。补录只能滚到下月补发', OLD.locked_at;
    END IF;
    -- 补录放行：必须有负责人 + 说明
    IF NEW.status='released' AND OLD.status='unrecorded_held' THEN
        IF NEW.backfilled_by IS NULL OR NEW.backfill_note IS NULL THEN
            RAISE EXCEPTION '门禁：未记录的工时放行必须由负责人补录并填写说明';
        END IF;
        NEW.backfilled_at := COALESCE(NEW.backfilled_at, now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER daily_payroll_immutable BEFORE UPDATE ON daily_payroll
    FOR EACH ROW EXECUTE FUNCTION trg_daily_payroll_immutable();

-- ★ 月度封账：把已定格的日结加总。挂起未放行的天不计入，滚下月
CREATE OR REPLACE FUNCTION fn_lock_payroll_month(p_staff uuid, p_period_end date)
RETURNS uuid AS $$
DECLARE v_start date; st eng_staff%ROWTYPE; v_id uuid;
        v_days int; v_paid numeric; v_normal numeric; v_ot numeric;
        v_base numeric; v_otamt numeric; v_toil numeric; v_held int; v_back numeric;
BEGIN
    v_start := (p_period_end - interval '1 month' + interval '1 day')::date;
    SELECT * INTO st FROM eng_staff WHERE id=p_staff;

    SELECT count(*) FILTER (WHERE paid_min > 0),
           COALESCE(SUM(paid_min),0), COALESCE(SUM(normal_min),0), COALESCE(SUM(ot_min),0),
           COALESCE(SUM(pay_amount),0)
      INTO v_days, v_paid, v_normal, v_ot, v_otamt
      FROM daily_payroll
     WHERE staff_id=p_staff AND work_date BETWEEN v_start AND p_period_end
       AND status IN ('locked','released');

    SELECT count(*) INTO v_held FROM daily_payroll
     WHERE staff_id=p_staff AND work_date BETWEEN v_start AND p_period_end
       AND status='unrecorded_held';

    -- 上期挂起、本期才补录放行的 → 本期补发
    SELECT COALESCE(SUM(pay_amount),0) INTO v_back FROM daily_payroll
     WHERE staff_id=p_staff AND work_date < v_start
       AND status='released' AND backfilled_at >= v_start;

    -- ★倒休按【出工日】归期，不按记账时间(否则往期加班会串进本期)
    SELECT COALESCE(SUM(t.minutes),0) INTO v_toil
      FROM toil_ledger t JOIN daily_payroll d ON d.id = t.ref_payroll_id
     WHERE t.staff_id=p_staff AND t.entry_type='accrue'
       AND d.work_date BETWEEN v_start AND p_period_end;

    IF st.pay_type='monthly' THEN
        v_base := st.monthly_salary; v_otamt := 0;      -- 加班不发钱，转倒休
    ELSE
        v_base := v_otamt; v_otamt := 0;                -- 时薪制金额已含在日结 pay_amount
        v_toil := 0;
    END IF;

    INSERT INTO payroll_month(staff_id, period_start, period_end, pay_type_snap,
        work_days, paid_min, normal_min, ot_min, base_amount, ot_amount,
        toil_accrued_min, backpay_amount, total_amount, held_days, locked_by)
    VALUES (p_staff, v_start, p_period_end, st.pay_type, v_days, v_paid, v_normal, v_ot,
        v_base, v_otamt, v_toil, v_back, COALESCE(v_base,0)+COALESCE(v_otamt,0)+COALESCE(v_back,0),
        v_held, current_setting('app.actor', true))
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
--  v0.5 视图
-- =====================================================================

-- ⑯ 倒休余额（只增不改的流水现算，谁也抹不掉）
CREATE VIEW v_toil_balance AS
SELECT s.id AS staff_id, s.name, s.pay_type,
       round(COALESCE(SUM(t.minutes),0),1)          AS balance_min,
       round(COALESCE(SUM(t.minutes),0)/60.0,2)     AS balance_hours,
       round(COALESCE(SUM(CASE WHEN t.entry_type='accrue' THEN t.minutes END),0)/60.0,2) AS accrued_hours,
       round(COALESCE(SUM(CASE WHEN t.entry_type='take'   THEN -t.minutes END),0)/60.0,2) AS taken_hours
  FROM eng_staff s LEFT JOIN toil_ledger t ON t.staff_id=s.id
 GROUP BY s.id, s.name, s.pay_type;

-- ⑰ 未记录天数（★KPI 考核用：谁经常不记录）
CREATE VIEW v_unrecorded_days AS
SELECT d.staff_id, s.name,
       count(*) FILTER (WHERE d.status='unrecorded_held') AS still_held,
       count(*) FILTER (WHERE d.unrecorded)               AS total_unrecorded,
       max(d.work_date) FILTER (WHERE d.unrecorded)       AS last_unrecorded_date
  FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id
 WHERE d.unrecorded GROUP BY d.staff_id, s.name;

-- ⑱ 加班汇总（按当天性质分开看：平日超时 vs 周末 vs 公共假日）
CREATE VIEW v_overtime_summary AS
SELECT d.staff_id, s.name, s.pay_type,
       date_trunc('month', d.work_date)::date AS month,
       round(SUM(d.ot_min) FILTER (WHERE d.day_type='weekday')/60.0,2)  AS ot_weekday_h,
       round(SUM(d.ot_min) FILTER (WHERE d.day_type='saturday')/60.0,2) AS ot_saturday_h,
       round(SUM(d.ot_min) FILTER (WHERE d.day_type='sunday')/60.0,2)   AS ot_sunday_h,
       round(SUM(d.ot_min) FILTER (WHERE d.day_type='holiday')/60.0,2)  AS ot_holiday_h,
       round(SUM(d.ot_min)/60.0,2)                                      AS ot_total_h
  FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id
 WHERE d.status IN ('locked','released')
 GROUP BY d.staff_id, s.name, s.pay_type, date_trunc('month', d.work_date);


-- ⑲ 假日表覆盖预警（日历用完了要提醒，否则加班会被当成普通日算错）
CREATE VIEW v_holiday_coverage AS
SELECT state,
       min(holiday_date) AS from_date,
       max(holiday_date) AS to_date,
       count(*)          AS holiday_count,
       (max(holiday_date) < (now()::date + interval '90 days')) AS needs_topup
  FROM public_holiday GROUP BY state;


-- #####################################################################
-- ##  v0.6 新增：外包资源 + 入职/离职 + 离职清算
-- #####################################################################

-- =====================================================================
--  第二十五部分：外包时薪参考时间按天覆盖 staff_daily_commitment
--    默认取 eng_staff.ref_minutes；某天单独谈了别的价/别的参考时间时按天覆盖
--    工程管理填（外包也有 App，也可由工程管理代填）
-- =====================================================================
CREATE TABLE staff_daily_commitment (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id     uuid NOT NULL REFERENCES eng_staff(id),
    work_date    date NOT NULL,
    ref_minutes  integer NOT NULL CHECK (ref_minutes > 0),  -- 当日时薪计算参考时间
    daily_rate_override numeric(10,2),           -- 个别日子谈了别的价
    note         text,
    created_by   text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (staff_id, work_date)
);


-- =====================================================================
--  第二十六部分：离职清算 termination_settlement
--    ★系统只算出"应结多少"，付不付、付多少由人定，但必须留痕
--    倒休结算涉及雇佣法，以雇佣合同与会计/劳资顾问意见为准
-- =====================================================================
CREATE TABLE termination_settlement (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id      uuid NOT NULL UNIQUE REFERENCES eng_staff(id),
    terminated_at date NOT NULL,
    -- 系统算出来的（定格）
    toil_balance_min numeric(10,1),              -- 离职时未休倒休余额
    rate_snap        numeric(10,2),              -- 折算用费率(离职时的成本时薪)
    toil_value       numeric(12,2),              -- 系统算出的应结金额
    -- 人决定的
    paid_amount   numeric(12,2),                 -- 实际结算金额
    decision_note text,                          -- 与应结不符时必填
    decided_by    text,
    settled_at    timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now()
);


-- =====================================================================
--  v0.6 触发器与函数
-- =====================================================================

-- ★ 外包成本时薪自动算：日薪 ÷ 承诺时长（不用人填，填错就算错利润率）
CREATE OR REPLACE FUNCTION trg_staff_cost_rate() RETURNS trigger AS $$
BEGIN
    IF NEW.pay_type='contractor' THEN
        NEW.cost_hourly_rate := round(NEW.daily_rate / (NEW.ref_minutes/60.0), 2);
    ELSIF NEW.pay_type='hourly' AND NEW.cost_hourly_rate IS NULL THEN
        NEW.cost_hourly_rate := NEW.pay_hourly_rate;
    END IF;
    IF NEW.pay_type='monthly' AND NEW.cost_hourly_rate IS NULL THEN
        RAISE EXCEPTION '门禁：月薪制必须人工换算填入成本时薪(月薪÷月标准工时)，否则工程成本算不出来';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER staff_cost_rate BEFORE INSERT OR UPDATE ON eng_staff
    FOR EACH ROW EXECUTE FUNCTION trg_staff_cost_rate();

-- ★ 日结定格增强：入职前/离职后不生成；外包走固定日薪、无周末假日概念
CREATE OR REPLACE FUNCTION fn_lock_daily_payroll(p_staff uuid, p_date date)
RETURNS uuid AS $$
DECLARE v_span numeric; v_lunch numeric; v_paid numeric;
        v_normal numeric; v_ot numeric; v_daytype text; v_std numeric;
        v_lunch_cfg numeric; v_minspan numeric; v_otrate numeric;
        st eng_staff%ROWTYPE; v_reported boolean; v_id uuid; v_amount numeric;
        v_ref integer; v_rate numeric; v_costrate numeric;
BEGIN
    SELECT * INTO st FROM eng_staff WHERE id = p_staff;
    IF st.id IS NULL THEN RAISE EXCEPTION '门禁：人员不存在'; END IF;

    -- ★ 入职前 / 离职后不生成日结
    IF p_date < st.hired_at THEN
        RAISE EXCEPTION '门禁：% 于 % 入职，不能为入职前的 % 生成日结工资',
            st.name, st.hired_at, p_date;
    END IF;
    IF st.terminated_at IS NOT NULL AND p_date > st.terminated_at THEN
        RAISE EXCEPTION '门禁：% 已于 % 离职，不能为离职后的 % 生成日结工资',
            st.name, st.terminated_at, p_date;
    END IF;

    SELECT value_num INTO v_std       FROM eng_setting WHERE key='standard_workday_min';
    SELECT value_num INTO v_lunch_cfg FROM eng_setting WHERE key='lunch_break_min';
    SELECT value_num INTO v_minspan   FROM eng_setting WHERE key='lunch_min_span_min';

    -- 首尾 / 午餐 / 付薪（三种制度共用同一套考勤）
    SELECT COALESCE(EXTRACT(EPOCH FROM (MAX(checkout_at)-MIN(checkin_at)))/60.0, 0)
      INTO v_span FROM work_log
     WHERE staff_id=p_staff AND checkin_at::date=p_date
       AND checkin_at IS NOT NULL AND checkout_at IS NOT NULL;
    v_lunch := CASE WHEN v_span >= v_minspan THEN v_lunch_cfg ELSE 0 END;
    v_paid  := GREATEST(v_span - v_lunch, 0);

    v_reported := (v_span > 0) OR EXISTS(
        SELECT 1 FROM daily_report WHERE staff_id=p_staff AND report_date=p_date
                                     AND submitted_at IS NOT NULL);

    IF st.pay_type = 'contractor' THEN
        -- ★ 外包：没有周末/公共假日/加班概念，一律普通日
        v_daytype := 'weekday'; v_otrate := 1;
        v_normal  := v_paid; v_ot := 0;
        -- 时薪计算参考时间与日薪：优先按天覆盖，否则取默认
        SELECT COALESCE(c.ref_minutes, st.ref_minutes),
               COALESCE(c.daily_rate_override, st.daily_rate)
          INTO v_ref, v_rate
          FROM (SELECT 1) x
          LEFT JOIN staff_daily_commitment c
                 ON c.staff_id=p_staff AND c.work_date=p_date;
        v_ref  := COALESCE(v_ref,  st.ref_minutes);
        v_rate := COALESCE(v_rate, st.daily_rate);
        -- ★ 成本时薪 = 日薪 ÷ 时薪计算参考时间；发薪则是有出工就付整日薪
        v_costrate := round(v_rate / (v_ref/60.0), 2);
        v_amount   := CASE WHEN v_paid > 0 THEN v_rate ELSE 0 END;
    ELSE
        v_daytype := CASE
            WHEN EXISTS(SELECT 1 FROM public_holiday WHERE holiday_date=p_date) THEN 'holiday'
            WHEN EXTRACT(DOW FROM p_date)=6 THEN 'saturday'
            WHEN EXTRACT(DOW FROM p_date)=0 THEN 'sunday'
            ELSE 'weekday' END;
        -- ★ 倍数：先看这个人有没有单独设，没有才用全局默认
        v_otrate := COALESCE(
            CASE v_daytype
              WHEN 'weekday'  THEN st.ot_rate_weekday
              WHEN 'saturday' THEN st.ot_rate_saturday
              WHEN 'sunday'   THEN st.ot_rate_sunday
              ELSE                 st.ot_rate_holiday END,
            (SELECT value_num FROM eng_setting WHERE key = 'ot_rate_' || v_daytype),
            1);
        -- 加班判定 C：平日超标准工时的部分；周末/公共假日整天
        IF v_daytype='weekday' THEN
            v_ot := GREATEST(v_paid - v_std, 0); v_normal := v_paid - v_ot;
        ELSE
            v_ot := v_paid; v_normal := 0;
        END IF;
        v_costrate := st.cost_hourly_rate;
        v_amount := CASE WHEN st.pay_type='hourly'
                    THEN round((v_normal/60.0*st.pay_hourly_rate)
                             + (v_ot/60.0*st.pay_hourly_rate*COALESCE(v_otrate,1)), 2)
                    END;
    END IF;

    INSERT INTO daily_payroll(staff_id, work_date, day_type, span_min, lunch_min, paid_min,
        normal_min, ot_min, pay_type_snap, pay_rate_snap, cost_rate_snap, ot_rate_snap,
        pay_amount, status, unrecorded)
    VALUES (p_staff, p_date, v_daytype, round(v_span,1), v_lunch, round(v_paid,1),
        round(v_normal,1), round(v_ot,1), st.pay_type,
        CASE WHEN st.pay_type='contractor' THEN v_rate ELSE st.pay_hourly_rate END,
        v_costrate, COALESCE(v_otrate,1), v_amount,
        CASE WHEN v_reported THEN 'locked' ELSE 'unrecorded_held' END,
        NOT v_reported)
    RETURNING id INTO v_id;

    -- 月薪制：加班不发钱，累计倒休（外包与时薪制都不进倒休）
    IF st.pay_type='monthly' AND v_ot > 0 AND v_reported THEN
        INSERT INTO toil_ledger(staff_id, entry_type, minutes, ref_payroll_id, reason, created_by)
        VALUES (p_staff, 'accrue', round(v_ot,1), v_id,
                p_date || ' ' || v_daytype || ' 加班累计', 'system');
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ★ 离职清算：系统算出应结，人决定实付；不一致必须填原因
CREATE OR REPLACE FUNCTION fn_prepare_termination(p_staff uuid, p_date date)
RETURNS uuid AS $$
DECLARE st eng_staff%ROWTYPE; v_bal numeric; v_val numeric; v_id uuid;
BEGIN
    SELECT * INTO st FROM eng_staff WHERE id=p_staff;
    SELECT COALESCE(SUM(minutes),0) INTO v_bal FROM toil_ledger WHERE staff_id=p_staff;
    v_val := round(GREATEST(v_bal,0)/60.0 * COALESCE(st.cost_hourly_rate,0), 2);
    INSERT INTO termination_settlement(staff_id, terminated_at, toil_balance_min,
        rate_snap, toil_value)
    VALUES (p_staff, p_date, round(v_bal,1), st.cost_hourly_rate, v_val)
    RETURNING id INTO v_id;
    UPDATE eng_staff SET terminated_at=p_date, active=false WHERE id=p_staff;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_termination_gate() RETURNS trigger AS $$
BEGIN
    IF NEW.settled_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.settled_at IS NULL) THEN
        IF NEW.paid_amount IS NULL THEN
            RAISE EXCEPTION '门禁：离职清算必须填写实际结算金额';
        END IF;
        IF NEW.paid_amount <> NEW.toil_value
           AND (NEW.decision_note IS NULL OR btrim(NEW.decision_note)='') THEN
            RAISE EXCEPTION '门禁：实付 % 与系统应结 % 不一致，必须填写原因(留痕)',
                NEW.paid_amount, NEW.toil_value;
        END IF;
        IF NEW.decided_by IS NULL THEN
            NEW.decided_by := current_setting('app.actor', true);
        END IF;
        -- 清算后把倒休余额冲平（只增不改：加一条冲抵流水，不删旧记录）
        INSERT INTO toil_ledger(staff_id, entry_type, minutes, reason, created_by)
        SELECT NEW.staff_id, 'adjust', -NEW.toil_balance_min,
               '离职清算冲抵：应结 ' || NEW.toil_value || '，实付 ' || NEW.paid_amount,
               COALESCE(NEW.decided_by,'system')
        WHERE NEW.toil_balance_min <> 0;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER termination_gate BEFORE INSERT OR UPDATE ON termination_settlement
    FOR EACH ROW EXECUTE FUNCTION trg_termination_gate();


-- =====================================================================
--  v0.6 视图
-- =====================================================================

-- ⑳ 人力资源一览（三种制度并排，成本时薪口径统一）
CREATE VIEW v_staff_overview AS
SELECT s.id, s.name, s.role, s.pay_type,
       s.hired_at, s.terminated_at, s.active,
       CASE s.pay_type
         WHEN 'monthly'    THEN '月薪 ' || s.monthly_salary
         WHEN 'hourly'     THEN '时薪 ' || s.pay_hourly_rate
         WHEN 'contractor' THEN '日薪 ' || s.daily_rate || ' / 参考 '
                                || round(s.ref_minutes/60.0,1) || ' 小时'
       END AS pay_terms,
       s.cost_hourly_rate,                       -- 三种人统一的成本口径
       (now()::date - s.hired_at)                AS days_since_hired,
       COALESCE(t.balance_hours, 0)              AS toil_balance_hours
  FROM eng_staff s LEFT JOIN v_toil_balance t ON t.staff_id = s.id;


-- ㉑ 外包：实付日薪 vs 摊进项目的成本，差额看得见
--    项目成本 = 成本时薪 × 实际在场时长；实付 = 整日薪
--    参考时间设得比实际在场长 → 摊入 < 实付(项目成本偏低)；反之偏高
CREATE VIEW v_contractor_cost_gap AS
SELECT d.staff_id, s.name, d.work_date,
       d.pay_rate_snap                              AS daily_paid,      -- 当日实付日薪
       d.cost_rate_snap                             AS cost_rate,       -- 当日成本时薪
       round(d.paid_min/60.0, 2)                    AS onsite_hours,
       round(d.paid_min/60.0 * d.cost_rate_snap, 2) AS charged_to_projects,
       round(d.pay_rate_snap - d.paid_min/60.0 * d.cost_rate_snap, 2) AS gap
  FROM daily_payroll d JOIN eng_staff s ON s.id = d.staff_id
 WHERE d.pay_type_snap = 'contractor' AND d.paid_min > 0;


-- #####################################################################
-- ##  v0.7：加班倍数（工程管理手动设置）
-- #####################################################################

-- 全局默认值改成 1.0 以外时，请按你们实际走的 Award / Enterprise Agreement 填
-- 澳洲常见（仅供参考，以你们的协议与劳资顾问意见为准）：
--   平日超时头两小时 1.5 之后 2.0 ｜ 周六 1.5 ｜ 周日 2.0 ｜ 公共假日 2.0
COMMENT ON COLUMN eng_staff.ot_rate_weekday IS
  '时薪制加班倍数·按人覆盖；NULL=跟随 eng_setting 全局默认。仅工程管理可设';

-- eng_setting 主键是 text 不是 uuid，通用审计函数用不了，单写一个
CREATE OR REPLACE FUNCTION trg_audit_kv() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit_log(actor, action, table_name, row_id, before, after)
    VALUES (current_setting('app.actor', true), TG_OP, TG_TABLE_NAME, NULL,
        CASE WHEN TG_OP='INSERT' THEN NULL ELSE to_jsonb(OLD) END,
        CASE WHEN TG_OP='DELETE' THEN NULL ELSE to_jsonb(NEW) END);
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- ★ 全局倍数是"钱的开关"：任何改动都要留痕
CREATE OR REPLACE FUNCTION trg_setting_audit() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    IF NEW.updated_by IS NULL THEN
        NEW.updated_by := current_setting('app.actor', true);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER setting_touch BEFORE UPDATE ON eng_setting
    FOR EACH ROW EXECUTE FUNCTION trg_setting_audit();
CREATE TRIGGER setting_audit AFTER INSERT OR UPDATE OR DELETE ON eng_setting
    FOR EACH ROW EXECUTE FUNCTION trg_audit_kv();

-- ★ 员工加班倍数改动也留痕（改的是钱）
CREATE TRIGGER staff_audit AFTER INSERT OR UPDATE OR DELETE ON eng_staff
    FOR EACH ROW EXECUTE FUNCTION trg_audit();

-- ㉒ 每个人实际生效的加班倍数（覆盖了就显示覆盖值，否则显示全局）
CREATE VIEW v_ot_rate_config AS
SELECT s.id AS staff_id, s.name, s.pay_type,
       COALESCE(s.ot_rate_weekday,  g.weekday)  AS weekday,
       COALESCE(s.ot_rate_saturday, g.saturday) AS saturday,
       COALESCE(s.ot_rate_sunday,   g.sunday)   AS sunday,
       COALESCE(s.ot_rate_holiday,  g.holiday)  AS holiday,
       (s.ot_rate_weekday IS NOT NULL OR s.ot_rate_saturday IS NOT NULL
        OR s.ot_rate_sunday IS NOT NULL OR s.ot_rate_holiday IS NOT NULL) AS has_override
  FROM eng_staff s
  CROSS JOIN (SELECT
      (SELECT value_num FROM eng_setting WHERE key='ot_rate_weekday')  AS weekday,
      (SELECT value_num FROM eng_setting WHERE key='ot_rate_saturday') AS saturday,
      (SELECT value_num FROM eng_setting WHERE key='ot_rate_sunday')   AS sunday,
      (SELECT value_num FROM eng_setting WHERE key='ot_rate_holiday')  AS holiday) g
 WHERE s.pay_type = 'hourly';   -- 月薪制转倒休、外包无加班，倍数只对时薪制有意义


-- #####################################################################
-- ##  v0.9：维护真实流程 —— 先上门 → 现场归因+客户签字 → 办公室定价开票
-- #####################################################################

-- ★ 门禁：维护任务完成，必须①现场归因 ②客户签字确认当日服务内容
--   "确认完才可以离开"——这两样缺一，任务点不了完成
CREATE OR REPLACE FUNCTION trg_mj_complete_gate() RETURNS trigger AS $$
BEGIN
    IF NEW.completed_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.completed_at IS NULL) THEN
        IF NEW.fault_cause IS NULL THEN
            RAISE EXCEPTION '门禁：请当着客户面确认故障归因(非人为/人为/不可抗力)后再结束本次服务';
        END IF;
        IF NEW.service_summary IS NULL OR btrim(NEW.service_summary)='' THEN
            RAISE EXCEPTION '门禁：请填写当日服务内容，客户要签的就是这段';
        END IF;
        IF NEW.client_sign_url IS NULL OR NEW.client_sign_at IS NULL THEN
            RAISE EXCEPTION '门禁：缺少客户签字确认，不能结束本次上门服务';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER mj_complete_gate BEFORE INSERT OR UPDATE ON maintenance_job
    FOR EACH ROW EXECUTE FUNCTION trg_mj_complete_gate();

-- 现场归因带回维护单 + 单据状态推进到"已上门"
CREATE OR REPLACE FUNCTION trg_mj_feedback() RETURNS trigger AS $$
BEGIN
    IF NEW.completed_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.completed_at IS NULL)
       AND NEW.case_id IS NOT NULL THEN
        UPDATE maintenance_case
           SET fault_cause = COALESCE(fault_cause, NEW.fault_cause),
               status = CASE WHEN status='open' THEN 'in_progress' ELSE status END,
               started_at = COALESCE(started_at, NEW.completed_at)
         WHERE id = NEW.case_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER mj_feedback AFTER INSERT OR UPDATE ON maintenance_job
    FOR EACH ROW EXECUTE FUNCTION trg_mj_feedback();

-- ★ 门禁：还没上门就开票 → 拒
--   办公室定价的依据是【工程人员报回来的归因 + 时长】，人没去过就没有依据
CREATE OR REPLACE FUNCTION trg_maint_invoice_gate() RETURNS trigger AS $$
DECLARE done int;
BEGIN
    IF NEW.kind='maintenance' AND NEW.invoice_sent_at IS NOT NULL
       AND (TG_OP='INSERT' OR OLD.invoice_sent_at IS NULL) THEN
        SELECT count(*) INTO done FROM maintenance_job
         WHERE case_id = NEW.case_id AND completed_at IS NOT NULL;
        IF done = 0 THEN
            RAISE EXCEPTION '门禁：本维护单尚无已完成的上门服务，不能开票(定价要靠现场归因与时长)';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER maint_invoice_gate BEFORE INSERT OR UPDATE ON payment_milestone
    FOR EACH ROW EXECUTE FUNCTION trg_maint_invoice_gate();

-- ㉓ 办公室开票依据：现场报回来的归因 + 时长 + 两套维保状态，一屏看全
CREATE VIEW v_maintenance_billing_basis AS
SELECT c.id AS case_id, c.project_id, p.code AS project_code, c.title,
       c.status, c.fault_cause,
       COUNT(j.id) FILTER (WHERE j.completed_at IS NOT NULL) AS visits_done,
       MIN(j.completed_at)  AS first_visit_at,
       MAX(j.completed_at)  AS last_visit_at,
       -- 实际工时（来自打卡，不是人报的）
       -- ★ 按 work_log.ref_id 精确挂到本单的各次上门，不靠日期猜
       COALESCE((SELECT round(SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0)::numeric,2)
                   FROM work_log w
                  WHERE w.work_type='maintenance'
                    AND w.ref_id IN (SELECT id FROM maintenance_job WHERE case_id=c.id)
                    AND w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL), 0) AS labor_hours,
       -- 免责维保：按建单时间算，是否落在免责期内
       (c.created_at < pr.handover_at + (pr.free_warranty_months || ' months')::interval) AS in_free_warranty,
       -- 建议：非人为 且 在免责期内 → 全免开 $0
       (c.fault_cause IN ('product_defect','wear_out')
        AND c.created_at < pr.handover_at + (pr.free_warranty_months || ' months')::interval) AS suggest_free,
       -- 物料是否还在保（各采购单最早到期的那个）
       (SELECT MIN(mw.expires_at) FROM v_material_warranty mw WHERE mw.project_id=c.project_id) AS material_expires_at,
       string_agg(DISTINCT j.service_summary, ' ｜ ') AS service_summaries
  FROM maintenance_case c
  JOIN project p  ON p.id = c.project_id
  JOIN project pr ON pr.id = c.project_id
  LEFT JOIN maintenance_job j ON j.case_id = c.id
 GROUP BY c.id, c.project_id, p.code, c.title, c.status, c.fault_cause,
          pr.handover_at, pr.free_warranty_months, c.created_at;


-- #####################################################################
-- ##  v0.10：维护口头预估（工程管理填，不参与计费）
-- #####################################################################

COMMENT ON COLUMN maintenance_case.estimate_amount IS
  '口头预估：工程管理在客户问"大概多少钱"时先记一个数。不参与计费，实际以发票为准';

-- 填了预估就自动留下是谁、什么时候（预估也是对客户的一句话，要能追溯）
CREATE OR REPLACE FUNCTION trg_mc_estimate() RETURNS trigger AS $$
BEGIN
    IF NEW.estimate_amount IS NOT NULL
       AND (TG_OP='INSERT' OR OLD.estimate_amount IS DISTINCT FROM NEW.estimate_amount) THEN
        NEW.estimated_at := now();
        IF NEW.estimated_by IS NULL THEN
            NEW.estimated_by := current_setting('app.actor', true);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER mc_estimate BEFORE INSERT OR UPDATE ON maintenance_case
    FOR EACH ROW EXECUTE FUNCTION trg_mc_estimate();

-- ㉔ 预估 vs 实际开票：工程管理估得准不准，跑一阵就看得出来
--    估低了客户会不满，估高了单子可能谈不成——这张表是给工程管理自己校准用的
CREATE VIEW v_maintenance_estimate_accuracy AS
SELECT c.id AS case_id, p.code AS project_code, c.title,
       c.estimate_amount, c.estimated_by, c.estimated_at,
       m.amount_due AS invoiced_amount, m.invoice_no,
       (m.amount_due - c.estimate_amount) AS diff,
       CASE WHEN c.estimate_amount > 0
            THEN round((m.amount_due - c.estimate_amount) / c.estimate_amount * 100, 1)
       END AS diff_pct,
       c.fault_cause, c.is_free_warranty
  FROM maintenance_case c
  JOIN project p ON p.id = c.project_id
  LEFT JOIN payment_milestone m
         ON m.case_id = c.id AND m.kind='maintenance' AND m.invoice_sent_at IS NOT NULL
 WHERE c.estimate_amount IS NOT NULL;


-- #####################################################################
-- ##  v0.11：报修受理与响应时长（算不出就是未知，不编）
-- #####################################################################

COMMENT ON COLUMN maintenance_case.reported_at IS
  '客户报修时间。允许 NULL=未知；NULL 时响应时长显示未知，绝不用建单时间顶替';

-- ★ 门禁：报修时间不能晚于建单时间（顺序反了必是填错）
CREATE OR REPLACE FUNCTION trg_mc_reported_at() RETURNS trigger AS $$
BEGIN
    IF NEW.reported_at IS NOT NULL AND NEW.reported_at > NEW.created_at + interval '1 minute' THEN
        RAISE EXCEPTION '门禁：报修时间(%)晚于建单时间(%)，顺序不对，请核对', NEW.reported_at, NEW.created_at;
    END IF;
    -- 填了具体时间却把渠道留成 unknown，多半是漏选
    IF NEW.reported_at IS NOT NULL AND NEW.report_channel='unknown' THEN
        RAISE EXCEPTION '门禁：既然记得报修时间，请一并选择报修渠道(电话/微信/邮件/现场/其他)';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER mc_reported_at BEFORE INSERT OR UPDATE ON maintenance_case
    FOR EACH ROW EXECUTE FUNCTION trg_mc_reported_at();

-- ㉕ 响应时长：报修 → 建单 → 首次上门。任何一段算不出就是 NULL(未知)
CREATE VIEW v_maintenance_response AS
SELECT c.id AS case_id, p.code AS project_code, c.title,
       c.reported_at, c.report_channel, c.taken_by, c.created_at AS case_created_at,
       (SELECT MIN(j.completed_at) FROM maintenance_job j
         WHERE j.case_id=c.id AND j.completed_at IS NOT NULL) AS first_visit_at,
       -- 报修 → 建单（接了电话多久才录进系统）
       CASE WHEN c.reported_at IS NOT NULL
            THEN round((EXTRACT(EPOCH FROM (c.created_at - c.reported_at))/3600.0)::numeric,1) END
         AS intake_hours,
       -- ★ 报修 → 首次上门：客户真正感受到的响应时长
       CASE WHEN c.reported_at IS NOT NULL
            THEN round((EXTRACT(EPOCH FROM (
                   (SELECT MIN(j.completed_at) FROM maintenance_job j
                     WHERE j.case_id=c.id AND j.completed_at IS NOT NULL) - c.reported_at
                 ))/3600.0)::numeric,1) END
         AS response_hours,
       (c.reported_at IS NULL) AS response_unknown   -- ★ 未知，不是 0
  FROM maintenance_case c JOIN project p ON p.id=c.project_id;

-- ㉖ 数据质量：有多少单连报修时间都没记，占比多少
--    ★ 这个比例本身就是管理信号——填得越少，响应时长这个指标越没意义
CREATE VIEW v_response_data_quality AS
SELECT count(*)                                                   AS total_cases,
       count(*) FILTER (WHERE reported_at IS NOT NULL)             AS with_report_time,
       count(*) FILTER (WHERE reported_at IS NULL)                 AS unknown_report_time,
       CASE WHEN count(*) > 0
            THEN round(count(*) FILTER (WHERE reported_at IS NULL)::numeric / count(*) * 100, 1)
       END                                                         AS unknown_pct
  FROM maintenance_case;


-- #####################################################################
-- ##  v0.12：变更估价 —— 外部手工计算，只读接入
-- #####################################################################

COMMENT ON COLUMN variation.settle_amount IS
  '变更结算金额：由财务+库管依据工程与SM过程记录在外部手工计算，填回本字段。系统只如实记录，不代算';

-- ★ 填金额就必须留痕（这笔钱要直接叠进 S4 跟客户结账）
CREATE OR REPLACE FUNCTION trg_variation_settle() RETURNS trigger AS $$
BEGIN
    IF NEW.settle_amount IS NOT NULL
       AND (TG_OP='INSERT' OR OLD.settle_amount IS DISTINCT FROM NEW.settle_amount) THEN
        IF NEW.settle_by IS NULL THEN
            NEW.settle_by := current_setting('app.actor', true);
        END IF;
        IF NEW.settle_by IS NULL OR btrim(NEW.settle_by)='' THEN
            RAISE EXCEPTION '门禁：变更结算金额要直接叠进 S4 跟客户结账，必须记录是谁填的';
        END IF;
        NEW.settle_at := now();
    END IF;
    -- 标记已结算，金额不能为空
    IF NEW.settle_status='settled_s4' AND NEW.settle_amount IS NULL THEN
        RAISE EXCEPTION '门禁：结算金额为空，不能标记为已结算';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER variation_settle BEFORE INSERT OR UPDATE ON variation
    FOR EACH ROW EXECUTE FUNCTION trg_variation_settle();

-- ★ 门禁：S4 Invoice 已发出后，本项目的变更金额不许再改
--   S4 的应收是"发出即定格"的，里面已经含了变更金额。
--   这边再改，发票上的数和系统里的数就永久对不上，而且不会报错。
--   真要改 → 跟改发票金额一样：S4 开 v2 重发。
CREATE OR REPLACE FUNCTION trg_variation_after_s4() RETURNS trigger AS $$
DECLARE s4_sent timestamptz; s4_no text;
BEGIN
    IF TG_OP='UPDATE' AND NEW.settle_amount IS DISTINCT FROM OLD.settle_amount THEN
        SELECT invoice_sent_at, invoice_no INTO s4_sent, s4_no
          FROM payment_milestone
         WHERE project_id=NEW.project_id AND kind='contract' AND stage='S4';
        IF s4_sent IS NOT NULL THEN
            RAISE EXCEPTION '门禁：S4 发票(%)已于 % 发出，其中已含变更金额；要改请 S4 开新版本重发',
                s4_no, s4_sent;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER variation_after_s4 BEFORE UPDATE ON variation
    FOR EACH ROW EXECUTE FUNCTION trg_variation_after_s4();

-- ㉗ 变更结算台账：S4 开票前，财务/库管照着这张表核对
CREATE VIEW v_variation_settlement AS
SELECT v.project_id, p.code AS project_code,
       count(*)                                            AS total_count,
       count(*) FILTER (WHERE v.settle_amount IS NOT NULL)  AS priced_count,
       count(*) FILTER (WHERE v.settle_amount IS NULL)      AS unpriced_count,
       COALESCE(SUM(v.settle_amount),0)                     AS settle_total,
       SUM(CASE WHEN v.change_type='add'    THEN 1 ELSE 0 END) AS add_count,
       SUM(CASE WHEN v.change_type='remove' THEN 1 ELSE 0 END) AS remove_count,
       SUM(CASE WHEN v.change_type='move'   THEN 1 ELSE 0 END) AS move_count,
       -- S4 应收 = 签约价×比例 + 变更合计
       p.contract_price,
       round(COALESCE(p.contract_price,0)*0.10 + COALESCE(SUM(v.settle_amount),0), 2) AS s4_expected,
       (SELECT invoice_sent_at FROM payment_milestone
         WHERE project_id=v.project_id AND kind='contract' AND stage='S4') AS s4_invoiced_at
  FROM variation v JOIN project p ON p.id=v.project_id
 GROUP BY v.project_id, p.code, p.contract_price;


-- #####################################################################
-- ##  v0.13 第一部分：物料主表 + 汇率
-- ##  （采购/入库/出库/提货 见第二部分）
-- #####################################################################

-- =====================================================================
--  第二十七部分：汇率 fx_rate（只增不改，历史可查）
--    系统自动从 Google 抓取；抓不到时人工填并标记来源
--    ★ 不 UPDATE 旧行——改=插新行。这样任何一天用的是什么汇率都查得到
-- =====================================================================
CREATE TABLE fx_rate (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    currency     text NOT NULL CHECK (currency IN ('CNY','USD')),
    rate_to_aud  numeric(12,6) NOT NULL CHECK (rate_to_aud > 0),
    source       text NOT NULL DEFAULT 'google'
                   CHECK (source IN ('google','manual')),
    fetched_at   timestamptz NOT NULL DEFAULT now(),
    note         text,          -- 人工填时说明原因(如"Google 抓取失败，按银行牌价")
    created_by   text
);
CREATE INDEX idx_fx_cur ON fx_rate(currency, fetched_at DESC);
COMMENT ON TABLE fx_rate IS '汇率只增不改：每次抓取/人工填写都插新行，历史汇率永久可查';

-- 当前汇率 = 每种货币最新的一条
CREATE VIEW v_fx_current AS
SELECT DISTINCT ON (currency)
       currency, rate_to_aud, source, fetched_at, note,
       (now()::date - fetched_at::date) AS days_stale,
       -- ★ 超过 3 天没更新就标出来，不静默使用旧值
       ((now()::date - fetched_at::date) > 3) AS is_stale
  FROM fx_rate
 ORDER BY currency, fetched_at DESC;


-- =====================================================================
--  第二十八部分：物料主表 material
--    公司核心参考表：物料信息 + 采购成本 + 利润 + 维保
--    ★ 库存量不在这张表——由出入库结算，视图现算(见第二部分)
-- =====================================================================
CREATE TABLE material (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code         text UNIQUE NOT NULL,            -- M0001

    -- 基本信息
    category     text NOT NULL,                   -- 品类(功能)：面板/开关/传感器/网关...
    protocol     text CHECK (protocol IN
                   ('knx','cbus','zigbee','wifi','rs485','none','other')),
    internal_name text NOT NULL,                  -- 物料名(内部型号)：我们自己的叫法
    supplier_model text,                          -- 型号(供应商型号)：对账用
    supplier     text,                            -- 供应商来源
    spec         text,                            -- 规格/颜色(白/黑；线材可空)
    -- ★ 显示名 = 物料名 + 规格，自动生成。
    --   白面板和黑面板的 internal_name 完全相同，只靠旁边一列小字区分，
    --   报表一扫、截图一发就容易看串。所有对外呈现一律用这个名字。
    display_name text GENERATED ALWAYS AS (
        internal_name || COALESCE(' ('||spec||')', '')) STORED,

    -- ★ 采购分类与备货逻辑
    --   C1 定期备货：国内采购或需提前准备，每半月集中采购，设红线，低于即补货
    --   C2 按需采购：本地采购或极易获取，【严格不设红线】，SM 确认需求后采购
    purchase_class text NOT NULL CHECK (purchase_class IN ('C1','C2')),
    reorder_point  integer,                       -- 库存红线量：仅 C1 填

    -- 采购价（三币种，通常只填一个）
    price_cny    numeric(12,2) CHECK (price_cny IS NULL OR price_cny >= 0),
    price_usd    numeric(12,2) CHECK (price_usd IS NULL OR price_usd >= 0),
    price_aud    numeric(12,2) CHECK (price_aud IS NULL OR price_aud >= 0),
    freight_aud  numeric(12,2) NOT NULL DEFAULT 0, -- 运输成本：涉及 CNY/USD 时手填

    -- ★ 利润率（手动填写）—— 口径为【毛利率】
    --   售卖价 = 采购成本 ÷ (1 − 利润率)；成本 100、45% → 181.82
    --   ⚠️ 必须 < 1：填 1 会除以零，填 >1 会算出负价，且不报错
    margin_pct   numeric(5,4) CHECK (margin_pct IS NULL OR (margin_pct >= 0 AND margin_pct < 0.95)),

    warranty_months integer,                      -- 厂商固定维保期限(月)。注意：与工程变更 variation 无关

    -- ★ 划掉（软删除）：不真删，只在显示上划横线
    --   划掉后不再被任何系统调用（出库/采购/期初全拦），但历史记录一字不动
    active       boolean NOT NULL DEFAULT true,   -- false = 已划掉
    archived_at  timestamptz,
    archived_by  text,
    archive_reason text,
    restored_at  timestamptz,
    restored_by  text,
    note         text,

    -- 更新记录（自动，用于追溯供应商调价与利润率调整）
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    updated_by   text,
    version      integer NOT NULL DEFAULT 1,

    CONSTRAINT ck_material_class CHECK (
        (purchase_class='C1' AND reorder_point IS NOT NULL AND reorder_point >= 0) OR
        (purchase_class='C2' AND reorder_point IS NULL)),
    CONSTRAINT ck_material_price CHECK (
        COALESCE(price_cny,0) + COALESCE(price_usd,0) + COALESCE(price_aud,0) > 0)
);
CREATE INDEX idx_material_cat ON material(category, purchase_class);
COMMENT ON COLUMN material.margin_pct IS '毛利率口径：售卖价 = 成本 ÷ (1−利润率)，非成本加成';
COMMENT ON COLUMN material.reorder_point IS 'C1 专用。C2 严格不设红线，必须为 NULL';
COMMENT ON COLUMN material.warranty_months IS '厂商物料维保期限。与工程变更 variation 无关，勿混用';


-- =====================================================================
--  v0.13 触发器
-- =====================================================================

-- 修改留痕：自动记修改人与时间（追溯调价、调利润率）
CREATE OR REPLACE FUNCTION trg_material_touch() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := now();
    NEW.version := OLD.version + 1;
    IF NEW.updated_by IS NULL OR NEW.updated_by = OLD.updated_by THEN
        NEW.updated_by := COALESCE(current_setting('app.actor', true), NEW.updated_by);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER material_touch BEFORE UPDATE ON material
    FOR EACH ROW EXECUTE FUNCTION trg_material_touch();

CREATE TRIGGER material_audit AFTER INSERT OR UPDATE OR DELETE ON material
    FOR EACH ROW EXECUTE FUNCTION trg_audit();
CREATE TRIGGER fx_audit AFTER INSERT OR UPDATE OR DELETE ON fx_rate
    FOR EACH ROW EXECUTE FUNCTION trg_audit_kv();


-- =====================================================================
--  v0.13 视图
-- =====================================================================

-- ㉘ 物料当前价（★现算不落库：汇率会变，售卖价跟着变）
--    ⚠️ 这是【当前参考价】，不是【已报给客户的价】。
--       报出去那一刻要把当时的售卖价与汇率抄一份定格，之后汇率再变不动老报价。
CREATE VIEW v_material_price AS
SELECT m.id, m.code, m.category, m.protocol, m.internal_name, m.display_name, m.supplier_model,
       m.supplier, m.spec, m.purchase_class, m.reorder_point,
       m.price_cny, m.price_usd, m.price_aud, m.freight_aud, m.margin_pct,
       fc.rate_to_aud AS rate_cny, fu.rate_to_aud AS rate_usd,
       -- 采购价折算 AUD
       round(COALESCE(m.price_cny,0)*COALESCE(fc.rate_to_aud,0)
           + COALESCE(m.price_usd,0)*COALESCE(fu.rate_to_aud,0)
           + COALESCE(m.price_aud,0), 2) AS cost_converted_aud,
       -- 采购成本合计 = 折算 + 运输
       round(COALESCE(m.price_cny,0)*COALESCE(fc.rate_to_aud,0)
           + COALESCE(m.price_usd,0)*COALESCE(fu.rate_to_aud,0)
           + COALESCE(m.price_aud,0) + m.freight_aud, 2) AS cost_total_aud,
       -- ★ 售卖价（毛利率口径）= 成本 ÷ (1 − 利润率)
       CASE WHEN m.margin_pct IS NOT NULL AND m.margin_pct < 1
            THEN round((COALESCE(m.price_cny,0)*COALESCE(fc.rate_to_aud,0)
                      + COALESCE(m.price_usd,0)*COALESCE(fu.rate_to_aud,0)
                      + COALESCE(m.price_aud,0) + m.freight_aud)
                      / (1 - m.margin_pct), 2) END AS sell_price_aud,
       -- 汇率新鲜度：抓取失败时沿用旧值，但必须显示出来，不静默
       GREATEST(COALESCE(fc.days_stale,0), COALESCE(fu.days_stale,0)) AS fx_days_stale,
       (COALESCE(fc.is_stale,false) OR COALESCE(fu.is_stale,false))   AS fx_stale,
       m.warranty_months, m.active, m.updated_by, m.updated_at
  FROM material m
  LEFT JOIN v_fx_current fc ON fc.currency='CNY'
  LEFT JOIN v_fx_current fu ON fu.currency='USD';

-- ㉙ 调价/调利润率历史（从审计日志里挖出来，供追溯）
CREATE VIEW v_material_price_history AS
SELECT a.at, a.actor,
       a.before->>'code'         AS code,
       a.before->>'internal_name' AS internal_name,
       (a.before->>'price_cny')::numeric  AS old_cny,
       (a.after ->>'price_cny')::numeric  AS new_cny,
       (a.before->>'price_usd')::numeric  AS old_usd,
       (a.after ->>'price_usd')::numeric  AS new_usd,
       (a.before->>'price_aud')::numeric  AS old_aud,
       (a.after ->>'price_aud')::numeric  AS new_aud,
       (a.before->>'margin_pct')::numeric AS old_margin,
       (a.after ->>'margin_pct')::numeric AS new_margin
  FROM audit_log a
 WHERE a.table_name='material' AND a.action='UPDATE'
   AND (a.before->>'price_cny'  IS DISTINCT FROM a.after->>'price_cny'
     OR a.before->>'price_usd'  IS DISTINCT FROM a.after->>'price_usd'
     OR a.before->>'price_aud'  IS DISTINCT FROM a.after->>'price_aud'
     OR a.before->>'margin_pct' IS DISTINCT FROM a.after->>'margin_pct');


-- #####################################################################
-- ##  v0.14：采购下单 → 入库 → 出库(落项目) → 提货确认
-- ##  ★ 库存不落库，由流水现算 —— material 表一列不加
-- #####################################################################

-- =====================================================================
--  第二十九部分：采购单 purchase_order（对供应商，管钱）
--    ★ 没有 project_id：买的时候还不知道给哪个项目
--    三种入库方式：集中采购 / 按项目采购 / 临时采购
-- =====================================================================
CREATE TABLE purchase_order (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    po_no        text UNIQUE NOT NULL,             -- PO-2026-0087
    -- ★ opening = 期初移库：系统上线时把仓库现有存货当成一次到货录进来
    --   这样"库存 = Σ入 − Σ出"的公式不用改，期初那批货也留在流水里、来路可查
    source_type  text NOT NULL CHECK (source_type IN
                   ('opening','bulk','project','adhoc')),
    supplier     text,
    ordered_at   timestamptz,                      -- 下单时间点
    expected_at  date,                             -- 预计到货
    arrived_at   timestamptz,                      -- ★实际到货时间：一填即自动转"已入库"
    status       text NOT NULL DEFAULT 'draft' CHECK (status IN
                   ('draft','ordered','partial','arrived','cancelled')),
    -- 按项目采购时可记一下是为哪个项目买的（仅供参考，不代表归属）
    -- ★ 归属只在【出库】产生，此处填了也不影响项目成本
    ref_project_id uuid REFERENCES project(id),
    note         text,
    created_by   text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    version      integer NOT NULL DEFAULT 1
);
CREATE INDEX idx_po_status ON purchase_order(status, ordered_at);
COMMENT ON COLUMN purchase_order.ref_project_id IS
  '按项目采购时的参考项目。★不代表物料归属——归属只在出库产生，此处不影响项目成本';

CREATE TABLE purchase_order_line (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    po_id        uuid NOT NULL REFERENCES purchase_order(id) ON DELETE CASCADE,
    material_id  uuid NOT NULL REFERENCES material(id),
    qty_ordered  numeric(12,2) NOT NULL CHECK (qty_ordered > 0),   -- 已下单数量
    qty_arrived  numeric(12,2) NOT NULL DEFAULT 0 CHECK (qty_arrived >= 0),
    unit_cost_aud numeric(12,2),                   -- 下单当时的单价(定格，折算后 AUD)
    note         text,
    UNIQUE (po_id, material_id),
    CONSTRAINT ck_pol_qty CHECK (qty_arrived <= qty_ordered)
);
CREATE INDEX idx_pol_material ON purchase_order_line(material_id);


-- =====================================================================
--  第三十部分：出库单 stock_out（★这一刻物料才落到具体项目）
--    出库必须同时有：时间 + 项目 + 接收人
-- =====================================================================
CREATE TABLE stock_out (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    out_no        text UNIQUE NOT NULL,            -- OUT-2026-0142-01
    project_id    uuid NOT NULL REFERENCES project(id),   -- ★强关联项目
    released_at   timestamptz NOT NULL DEFAULT now(),     -- 出库/提货具体时间

    -- ★ 提货人：自己的工程人员，或立项时录入的参建方(电工/Builder等)
    --   只能二选一，不能随便手填一个人
    receiver_staff_id uuid REFERENCES eng_staff(id),
    receiver_party_id uuid REFERENCES project_party(id),
    receiver_name  text,                           -- 定格：当时的姓名
    receiver_phone text,                           -- 定格：当时的手机号(短信发这里)

    -- ★ 提货确认：短信双向（notification 里 v0.2 就留好的 sms_2way / replied_yes）
    notification_id uuid REFERENCES notification(id),
    status        text NOT NULL DEFAULT 'released' CHECK (status IN
                    ('released','received','disputed')),
    received_at   timestamptz,
    received_via  text CHECK (received_via IN ('sms_yes','manual')),
    received_note text,

    created_by    text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    version       integer NOT NULL DEFAULT 1,
    CONSTRAINT ck_out_receiver CHECK (
        (receiver_staff_id IS NOT NULL AND receiver_party_id IS NULL) OR
        (receiver_staff_id IS NULL AND receiver_party_id IS NOT NULL))
);
CREATE INDEX idx_out_project ON stock_out(project_id);

CREATE TABLE stock_out_line (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    stock_out_id  uuid NOT NULL REFERENCES stock_out(id) ON DELETE CASCADE,
    material_id   uuid NOT NULL REFERENCES material(id),
    qty           numeric(12,2) NOT NULL CHECK (qty > 0),
    unit_cost_aud numeric(12,2),                   -- ★出库当时的成本单价(定格→项目成本)
    variation_id  uuid REFERENCES variation(id),   -- 若为变更补料，关联
    note          text,
    UNIQUE (stock_out_id, material_id)
);
CREATE INDEX idx_outline_material ON stock_out_line(material_id);


-- =====================================================================
--  v0.14 触发器
-- =====================================================================

-- ★ 到货即自动转"已入库"（部分到货则为 partial）
CREATE OR REPLACE FUNCTION trg_po_arrival() RETURNS trigger AS $$
DECLARE ord numeric; arr numeric;
BEGIN
    SELECT COALESCE(SUM(qty_ordered),0), COALESCE(SUM(qty_arrived),0)
      INTO ord, arr FROM purchase_order_line WHERE po_id = NEW.id;
    IF NEW.arrived_at IS NOT NULL THEN
        NEW.status := CASE WHEN arr >= ord AND ord > 0 THEN 'arrived'
                           WHEN arr > 0 THEN 'partial'
                           ELSE NEW.status END;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER po_arrival BEFORE UPDATE ON purchase_order
    FOR EACH ROW EXECUTE FUNCTION trg_po_arrival();

-- 明细收货 → 回写单头状态
CREATE OR REPLACE FUNCTION trg_pol_arrival() RETURNS trigger AS $$
DECLARE ord numeric; arr numeric;
BEGIN
    SELECT COALESCE(SUM(qty_ordered),0), COALESCE(SUM(qty_arrived),0)
      INTO ord, arr FROM purchase_order_line WHERE po_id = NEW.po_id;
    UPDATE purchase_order
       SET status = CASE WHEN arr >= ord AND ord > 0 THEN 'arrived'
                         WHEN arr > 0 THEN 'partial'
                         ELSE status END,
           arrived_at = CASE WHEN arr >= ord AND ord > 0 THEN COALESCE(arrived_at, now())
                             ELSE arrived_at END
     WHERE id = NEW.po_id AND status <> 'cancelled';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER pol_arrival AFTER INSERT OR UPDATE ON purchase_order_line
    FOR EACH ROW EXECUTE FUNCTION trg_pol_arrival();

-- ★ 门禁：提货人必须是自己人，或【本项目立项时录入的】参建方
--   不能拿别的项目的电工来提这个项目的货
CREATE OR REPLACE FUNCTION trg_out_receiver_gate() RETURNS trigger AS $$
DECLARE pid uuid; nm text; ph text;
BEGIN
    IF NEW.receiver_party_id IS NOT NULL THEN
        SELECT project_id, COALESCE(contact_name, company), phone
          INTO pid, nm, ph FROM project_party WHERE id = NEW.receiver_party_id;
        IF pid IS DISTINCT FROM NEW.project_id THEN
            RAISE EXCEPTION '门禁：该提货人不属于本项目的参建方，不能作为本项目的提货人';
        END IF;
    ELSE
        SELECT name, phone INTO nm, ph FROM eng_staff WHERE id = NEW.receiver_staff_id;
    END IF;
    -- 姓名手机号定格（人员资料以后改了，这张出库单上的仍是当时的）
    NEW.receiver_name  := COALESCE(NEW.receiver_name, nm);
    NEW.receiver_phone := COALESCE(NEW.receiver_phone, ph);
    IF NEW.receiver_phone IS NULL OR btrim(NEW.receiver_phone)='' THEN
        RAISE EXCEPTION '门禁：提货人没有手机号，无法发送提货清单短信';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER out_receiver_gate BEFORE INSERT OR UPDATE ON stock_out
    FOR EACH ROW EXECUTE FUNCTION trg_out_receiver_gate();

-- ★ 门禁：出库数量不能超过当前库存（库存由流水现算，不是列）
CREATE OR REPLACE FUNCTION trg_out_stock_gate() RETURNS trigger AS $$
DECLARE onhand numeric; nm text;
BEGIN
    SELECT COALESCE((SELECT SUM(l.qty_arrived) FROM purchase_order_line l
                      WHERE l.material_id = NEW.material_id), 0)
         - COALESCE((SELECT SUM(o.qty) FROM stock_out_line o
                      WHERE o.material_id = NEW.material_id AND o.id <> NEW.id), 0)
      INTO onhand;
    IF NEW.qty > onhand THEN
        SELECT display_name INTO nm FROM material WHERE id = NEW.material_id;
        RAISE EXCEPTION '门禁：% 当前库存 %，出库 % 不足', nm, onhand, NEW.qty;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER out_stock_gate BEFORE INSERT OR UPDATE ON stock_out_line
    FOR EACH ROW EXECUTE FUNCTION trg_out_stock_gate();

-- ★ 门禁：S2 物料款未结清，不放货给该项目
--   （v0.13 前这道门卡在"采购下单"，但采购是公司级行为，
--     不能因某项目没付钱就不给仓库补面板。v0.14 挪到出库——货真正给出去的时刻）
CREATE OR REPLACE FUNCTION trg_out_s2_gate() RETURNS trigger AS $$
DECLARE s2_ok boolean; pcode text;
BEGIN
    SELECT (status='settled') INTO s2_ok FROM payment_milestone
     WHERE project_id = NEW.project_id AND kind='contract' AND stage='S2';
    IF s2_ok IS DISTINCT FROM true THEN
        SELECT code INTO pcode FROM project WHERE id = NEW.project_id;
        RAISE EXCEPTION '门禁：项目 % 的 S2 物料款未结清，不能出库放货', pcode;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER out_s2_gate BEFORE INSERT ON stock_out
    FOR EACH ROW EXECUTE FUNCTION trg_out_s2_gate();

-- ★ 出库即自动生成提货清单短信（双向确认，回 yes 自动置"已接收"）
--   触发器挂在【明细】上，但短信是【整张出库单一条】：
--   已有短信就更新清单内容，没有才新建。否则加几行明细就发几条短信。
CREATE OR REPLACE FUNCTION trg_out_sms() RETURNS trigger AS $$
DECLARE so stock_out%ROWTYPE; body text; pcode text; nid uuid; full_body text;
BEGIN
    SELECT * INTO so FROM stock_out WHERE id = NEW.stock_out_id;
    SELECT code INTO pcode FROM project WHERE id = so.project_id;

    SELECT string_agg(m.display_name || ' ×' || l.qty::text, E'\n' ORDER BY m.code)
      INTO body FROM stock_out_line l JOIN material m ON m.id = l.material_id
     WHERE l.stock_out_id = so.id;
    IF body IS NULL THEN RETURN NEW; END IF;

    full_body := '【KONNEXT】项目 ' || pcode || ' 提货清单：' || E'\n' || body || E'\n'
              || '收到请回复 yes 确认。' || E'\n'
              || 'Please reply YES to confirm receipt.';

    IF so.notification_id IS NULL THEN
        INSERT INTO notification(project_id, ref_kind, ref_id, channel, recipient,
                                 subject, body, status, triggered_by)
        VALUES (so.project_id, 'stock_out', so.id, 'sms_2way', so.receiver_phone,
                'KONNEXT 提货清单 / Pickup List ' || so.out_no,
                full_body, 'queued', COALESCE(current_setting('app.actor', true),'system'))
        RETURNING id INTO nid;
        UPDATE stock_out SET notification_id = nid WHERE id = so.id;
    ELSE
        -- 已发出的短信不再改动（发出去的话不能改）；还在队列里的才更新清单
        UPDATE notification SET body = full_body
         WHERE id = so.notification_id AND status = 'queued';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER out_sms AFTER INSERT ON stock_out_line
    FOR EACH ROW EXECUTE FUNCTION trg_out_sms();

-- 短信回 yes → 出库单自动置"已接收"
CREATE OR REPLACE FUNCTION trg_sms_reply() RETURNS trigger AS $$
BEGIN
    IF NEW.status='replied_yes' AND OLD.status IS DISTINCT FROM 'replied_yes'
       AND NEW.ref_kind='stock_out' THEN
        UPDATE stock_out
           SET status='received',
               received_at = COALESCE(NEW.replied_at, now()),
               received_via = 'sms_yes'
         WHERE id = NEW.ref_id AND status='released';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER sms_reply AFTER UPDATE ON notification
    FOR EACH ROW EXECUTE FUNCTION trg_sms_reply();


-- =====================================================================
--  v0.14 视图：库存全部现算，不落库
-- =====================================================================

-- ㉚ 物料库存：在途 / 现有 / 是否低于红线
--    ★ 包含已划掉的物料：只要还有存货就必须显示，否则那批货成了账外物资
CREATE VIEW v_material_stock AS
SELECT m.id AS material_id, m.code, m.category, m.internal_name, m.spec,
       m.display_name,                      -- ★对外一律用它，杜绝白/黑看串
       m.purchase_class, m.reorder_point,
       COALESCE(po.ordered,0)  AS qty_ordered_total,   -- 累计已下单
       COALESCE(po.arrived,0)  AS qty_arrived_total,   -- 累计已到货
       COALESCE(po.ordered,0) - COALESCE(po.arrived,0) AS qty_in_transit,  -- ★在途(已下单未到货)
       COALESCE(so.out_qty,0)  AS qty_out_total,       -- 累计已出库
       COALESCE(po.arrived,0) - COALESCE(so.out_qty,0) AS qty_on_hand,     -- ★当前库存
       -- ★ 仅 C1 判红线；C2 严格不设红线，恒为 false
       (m.purchase_class='C1' AND m.reorder_point IS NOT NULL
        AND COALESCE(po.arrived,0) - COALESCE(so.out_qty,0) < m.reorder_point) AS below_reorder,
       m.active
  FROM material m
  LEFT JOIN (SELECT material_id, SUM(qty_ordered) ordered, SUM(qty_arrived) arrived
               FROM purchase_order_line GROUP BY material_id) po ON po.material_id=m.id
  LEFT JOIN (SELECT material_id, SUM(qty) out_qty
               FROM stock_out_line GROUP BY material_id) so ON so.material_id=m.id;

-- ㉛ 补货建议：C1 低于红线的，按半月集中采购一次统一下单
CREATE VIEW v_reorder_alert AS
SELECT code, category, display_name, internal_name, spec, reorder_point,
       qty_on_hand, qty_in_transit,
       (reorder_point - qty_on_hand) AS shortfall,
       (qty_on_hand + qty_in_transit >= reorder_point) AS covered_by_in_transit
  FROM v_material_stock
 WHERE below_reorder AND active;

-- ㉜ 库存流水（入库为正、出库为负；只增不改，可逐笔回溯）
CREATE VIEW v_stock_ledger AS
SELECT l.material_id, m.display_name, m.internal_name, m.spec,
       'in'::text AS direction, po.arrived_at AS at,
       l.qty_arrived AS qty, po.po_no AS ref_no, po.supplier AS counterparty,
       NULL::uuid AS project_id
  FROM purchase_order_line l
  JOIN purchase_order po ON po.id=l.po_id
  JOIN material m ON m.id=l.material_id
 WHERE l.qty_arrived > 0
UNION ALL
SELECT ol.material_id, m.display_name, m.internal_name, m.spec,
       'out', so.released_at, -ol.qty, so.out_no, so.receiver_name, so.project_id
  FROM stock_out_line ol
  JOIN stock_out so ON so.id=ol.stock_out_id
  JOIN material m ON m.id=ol.material_id;

-- ㉝ 项目物料成本（★按出库归集，不按采购单）
--    库存里没发出去的货不会算进任何项目 —— 这是利润率不虚低的关键
CREATE VIEW v_project_material_cost AS
SELECT so.project_id, p.code AS project_code,
       COUNT(DISTINCT so.id)                                   AS out_count,
       round(SUM(ol.qty * COALESCE(ol.unit_cost_aud,0)), 2)     AS material_cost_aud,
       COUNT(*) FILTER (WHERE so.status='released')             AS pending_confirm,
       COUNT(*) FILTER (WHERE so.status='received')             AS confirmed
  FROM stock_out_line ol
  JOIN stock_out so ON so.id=ol.stock_out_id
  JOIN project p ON p.id=so.project_id
 GROUP BY so.project_id, p.code;


-- #####################################################################
-- ##  v0.15：期初库存移库（系统上线时把现有存货录进来）
-- #####################################################################

-- ★ 门禁：一个物料只能做一次期初移库
--   做两遍库存就凭空翻倍，而且不会报错——这是上线时最容易犯又最难发现的错
CREATE OR REPLACE FUNCTION trg_opening_once() RETURNS trigger AS $$
DECLARE cnt int; nm text; st text;
BEGIN
    SELECT source_type INTO st FROM purchase_order WHERE id = NEW.po_id;
    IF st <> 'opening' THEN RETURN NEW; END IF;

    SELECT count(*) INTO cnt
      FROM purchase_order_line l JOIN purchase_order po ON po.id = l.po_id
     WHERE po.source_type = 'opening'
       AND l.material_id = NEW.material_id
       AND l.id <> NEW.id;
    IF cnt > 0 THEN
        SELECT display_name INTO nm FROM material WHERE id = NEW.material_id;
        RAISE EXCEPTION '门禁：物料「%」已经做过期初移库，不能再做第二次(会导致库存凭空翻倍)', nm;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER opening_once BEFORE INSERT OR UPDATE ON purchase_order_line
    FOR EACH ROW EXECUTE FUNCTION trg_opening_once();


-- ★ 期初移库函数：按物料编号一条条录入
--   用法：SELECT fn_opening_stock('M0001', 38, 85.20, '2026-08-01 盘点');
--   到货数直接等于盘点数 → 立即成为当前库存
CREATE OR REPLACE FUNCTION fn_opening_stock(
    p_material_code text,
    p_qty           numeric,
    p_unit_cost_aud numeric DEFAULT NULL,
    p_note          text    DEFAULT NULL
) RETURNS text AS $$
DECLARE v_po uuid; v_mid uuid; v_name text;
BEGIN
    SELECT id, display_name INTO v_mid, v_name FROM material WHERE code = p_material_code;
    IF v_mid IS NULL THEN
        RAISE EXCEPTION '物料编号 % 不存在，请先在物料主表建好再做期初', p_material_code;
    END IF;
    IF p_qty < 0 THEN
        RAISE EXCEPTION '期初数量不能为负数(%)', p_qty;
    END IF;

    -- 全公司共用一张期初单，没有就建
    SELECT id INTO v_po FROM purchase_order WHERE source_type = 'opening' LIMIT 1;
    IF v_po IS NULL THEN
        INSERT INTO purchase_order(po_no, source_type, supplier, ordered_at, arrived_at,
                                   status, note, created_by)
        VALUES ('OPENING-' || to_char(now(),'YYYYMMDD'), 'opening', '期初移库(系统上线)',
                now(), now(), 'arrived',
                '系统上线时的仓库现有存货，按盘点结果一次性录入', 
                COALESCE(current_setting('app.actor', true),'system'))
        RETURNING id INTO v_po;
    END IF;

    INSERT INTO purchase_order_line(po_id, material_id, qty_ordered, qty_arrived,
                                    unit_cost_aud, note)
    VALUES (v_po, v_mid, p_qty, p_qty, p_unit_cost_aud, COALESCE(p_note, '期初移库'));

    RETURN format('已录入期初：%s（%s） 数量 %s', p_material_code, v_name, p_qty);
END;
$$ LANGUAGE plpgsql;


-- ㉞ 期初完成度：哪些物料还没做期初，一眼看清
--    ★ 上线时照这张表逐个核对，做完为止
CREATE VIEW v_opening_status AS
SELECT m.code, m.category, m.display_name, m.internal_name, m.spec, m.purchase_class,
       (op.qty IS NOT NULL) AS opening_done,
       op.qty               AS opening_qty,
       op.unit_cost         AS opening_unit_cost,
       s.qty_on_hand        AS current_on_hand
  FROM material m
  LEFT JOIN (SELECT l.material_id, l.qty_arrived AS qty, l.unit_cost_aud AS unit_cost
               FROM purchase_order_line l JOIN purchase_order po ON po.id = l.po_id
              WHERE po.source_type = 'opening') op ON op.material_id = m.id
  LEFT JOIN v_material_stock s ON s.material_id = m.id
 WHERE m.active;

-- ㉟ 库存来源拆分：期初移库 vs 上线后采购（对账用）
CREATE VIEW v_stock_source_split AS
SELECT m.code, m.display_name, m.internal_name, m.spec,
       COALESCE(SUM(l.qty_arrived) FILTER (WHERE po.source_type='opening'), 0) AS from_opening,
       COALESCE(SUM(l.qty_arrived) FILTER (WHERE po.source_type<>'opening'), 0) AS from_purchase,
       COALESCE(SUM(l.qty_arrived), 0)                                          AS total_in,
       COALESCE((SELECT SUM(o.qty) FROM stock_out_line o WHERE o.material_id=m.id), 0) AS total_out,
       COALESCE(SUM(l.qty_arrived), 0)
         - COALESCE((SELECT SUM(o.qty) FROM stock_out_line o WHERE o.material_id=m.id), 0) AS on_hand
  FROM material m
  LEFT JOIN purchase_order_line l ON l.material_id = m.id
  LEFT JOIN purchase_order po ON po.id = l.po_id
 GROUP BY m.id, m.code, m.internal_name, m.spec;


-- #####################################################################
-- ##  v0.16：物料表项的增 / 划掉 / 恢复 / 彻底删除
-- #####################################################################

-- =====================================================================
--  一、划掉（软删除）：不真删，显示上划横线
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_archive_material(p_code text, p_reason text)
RETURNS text AS $$
DECLARE m material%ROWTYPE; onhand numeric; intransit numeric;
BEGIN
    SELECT * INTO m FROM material WHERE code = p_code;
    IF m.id IS NULL THEN RAISE EXCEPTION '物料编号 % 不存在', p_code; END IF;
    IF NOT m.active THEN RAISE EXCEPTION '物料「%」已经是划掉状态', m.display_name; END IF;
    IF p_reason IS NULL OR btrim(p_reason)='' THEN
        RAISE EXCEPTION '划掉物料必须填写原因（停产/换型号/录错了…），否则以后没人知道为什么';
    END IF;

    SELECT qty_on_hand, qty_in_transit INTO onhand, intransit
      FROM v_material_stock WHERE material_id = m.id;

    UPDATE material
       SET active=false, archived_at=now(),
           archived_by=COALESCE(current_setting('app.actor', true),'unknown'),
           archive_reason=p_reason
     WHERE id = m.id;

    -- ★ 有库存/在途照样能划掉，但要明确告知——那批货不会凭空消失，
    --    库存表里仍然看得到（见 v_material_stock 的说明）
    RETURN format('已划掉：%s（%s）%s', p_code, m.display_name,
      CASE WHEN COALESCE(onhand,0) > 0 OR COALESCE(intransit,0) > 0
           THEN format('  ⚠️ 注意：仍有库存 %s、在途 %s，请先安排出清或退货',
                       COALESCE(onhand,0), COALESCE(intransit,0))
           ELSE '' END);
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
--  二、恢复
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_restore_material(p_code text)
RETURNS text AS $$
DECLARE m material%ROWTYPE;
BEGIN
    SELECT * INTO m FROM material WHERE code = p_code;
    IF m.id IS NULL THEN RAISE EXCEPTION '物料编号 % 不存在', p_code; END IF;
    IF m.active THEN RAISE EXCEPTION '物料「%」本来就是启用状态，无需恢复', m.display_name; END IF;

    UPDATE material
       SET active=true, restored_at=now(),
           restored_by=COALESCE(current_setting('app.actor', true),'unknown')
     WHERE id = m.id;
    -- ★ archived_* 不清空：划掉过这件事本身是历史，恢复了也要留着
    RETURN format('已恢复：%s（%s）', p_code, m.display_name);
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
--  三、彻底删除：★只有从来没被用过的物料才允许
--     有流水还硬删 → 历史单据指向一个不存在的物料，
--     报表不报错，只会悄悄少一块。所以这里必须拦死。
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_delete_material(p_code text)
RETURNS text AS $$
DECLARE m material%ROWTYPE; n_po int; n_out int;
BEGIN
    SELECT * INTO m FROM material WHERE code = p_code;
    IF m.id IS NULL THEN RAISE EXCEPTION '物料编号 % 不存在', p_code; END IF;

    SELECT count(*) INTO n_po  FROM purchase_order_line WHERE material_id = m.id;
    SELECT count(*) INTO n_out FROM stock_out_line      WHERE material_id = m.id;

    IF n_po > 0 OR n_out > 0 THEN
        RAISE EXCEPTION
          '门禁：物料「%」已有 % 条采购/入库记录、% 条出库记录，不能彻底删除。'
          '删了历史单据会指向一个不存在的物料，项目成本会悄悄少一块。请改用「划掉」。',
          m.display_name, n_po, n_out;
    END IF;

    IF m.active THEN
        RAISE EXCEPTION '请先划掉物料「%」，确认无误后再彻底删除（防手滑）', m.display_name;
    END IF;

    DELETE FROM material WHERE id = m.id;   -- 删除动作本身进 audit_log，可追溯
    RETURN format('已彻底删除：%s（%s）—— 该物料从未产生任何流水', p_code, m.display_name);
END;
$$ LANGUAGE plpgsql;

-- =====================================================================
--  四、门禁：划掉的物料不再被任何系统调用
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_material_archived_gate() RETURNS trigger AS $$
DECLARE m material%ROWTYPE; act text;
BEGIN
    SELECT * INTO m FROM material WHERE id = NEW.material_id;
    IF NOT m.active THEN
        act := CASE TG_TABLE_NAME
                 WHEN 'purchase_order_line' THEN '采购下单/入库'
                 WHEN 'stock_out_line'      THEN '出库'
                 ELSE TG_TABLE_NAME END;
        RAISE EXCEPTION '门禁：物料「%」已于 % 被划掉（原因：%），不能再用于%。如需继续使用请先恢复',
            m.display_name, m.archived_at::date, COALESCE(m.archive_reason,'未填'), act;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER pol_archived_gate BEFORE INSERT ON purchase_order_line
    FOR EACH ROW EXECUTE FUNCTION trg_material_archived_gate();
CREATE TRIGGER outline_archived_gate BEFORE INSERT ON stock_out_line
    FOR EACH ROW EXECUTE FUNCTION trg_material_archived_gate();

-- =====================================================================
--  五、视图
-- =====================================================================

-- ㊱ 物料清单（给界面用）：划掉的排在后面并带删除线标记
CREATE VIEW v_material_list AS
SELECT m.id, m.code, m.category, m.protocol, m.display_name, m.internal_name, m.spec,
       m.supplier_model, m.supplier, m.purchase_class, m.reorder_point,
       m.warranty_months,
       m.active,
       (NOT m.active)  AS strikethrough,        -- ★界面据此画横线
       m.archived_at, m.archived_by, m.archive_reason,
       m.restored_at,  m.restored_by,
       s.qty_on_hand, s.qty_in_transit,
       -- 能不能彻底删除：从未产生任何流水才行
       (NOT EXISTS(SELECT 1 FROM purchase_order_line l WHERE l.material_id=m.id)
        AND NOT EXISTS(SELECT 1 FROM stock_out_line o WHERE o.material_id=m.id)) AS can_hard_delete,
       m.updated_by, m.updated_at
  FROM material m
  LEFT JOIN v_material_stock s ON s.material_id = m.id;

-- ㊲ 划掉但仍有库存的物料 —— ★这批货不能从报表里消失，否则成账外物资
CREATE VIEW v_archived_with_stock AS
SELECT code, display_name, archived_at::date AS archived_on, archived_by, archive_reason,
       qty_on_hand, qty_in_transit,
       '已划掉但仍有存货，请安排出清或退货' AS action_needed
  FROM v_material_list
 WHERE NOT active AND (COALESCE(qty_on_hand,0) > 0 OR COALESCE(qty_in_transit,0) > 0);

-- ㊳ 划掉/恢复历史（从审计日志挖，谁划的、什么时候、为什么）
CREATE VIEW v_material_archive_history AS
SELECT a.at, a.actor,
       COALESCE(a.after->>'code', a.before->>'code')                 AS code,
       COALESCE(a.after->>'display_name', a.before->>'display_name') AS display_name,
       CASE
         WHEN a.action='DELETE' THEN '彻底删除'
         WHEN (a.before->>'active')::boolean AND NOT (a.after->>'active')::boolean THEN '划掉'
         WHEN NOT (a.before->>'active')::boolean AND (a.after->>'active')::boolean THEN '恢复'
       END                                                            AS action_cn,
       a.after->>'archive_reason'                                     AS reason
  FROM audit_log a
 WHERE a.table_name='material'
   AND (a.action='DELETE'
        OR (a.action='UPDATE'
            AND (a.before->>'active') IS DISTINCT FROM (a.after->>'active')));


-- #####################################################################
-- ##  v0.17：退库 / 拒收 / 未退料计入 Variation / RMA 坏货
-- #####################################################################

-- =====================================================================
--  第三十一部分：退库单 stock_return
--    ★ 核心原则：出库了没退回的，一律先计入客户 Variation。
--      不是记账偷懒——工地物料流向看不住，靠自查成本高又查不全；
--      变更单发出去，客户自然来对账，异常就浮出来了。客户 argue 即触发追溯。
-- =====================================================================
CREATE TABLE stock_return (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    return_no     text UNIQUE NOT NULL,             -- RET-2026-0142-01
    project_id    uuid NOT NULL REFERENCES project(id),
    stock_out_id  uuid REFERENCES stock_out(id),    -- 对应哪张出库单(可空：跨单退)

    -- 谁退的货（与出库提货人对应）
    returner_staff_id uuid REFERENCES eng_staff(id),
    returner_party_id uuid REFERENCES project_party(id),
    returner_name  text,
    returner_phone text,

    returned_at   timestamptz NOT NULL DEFAULT now(),

    -- ★ 拒收：货不对版等情况我方有权拒收，但必须留痕
    status        text NOT NULL DEFAULT 'accepted' CHECK (status IN ('accepted','rejected')),
    rejected_by   text,
    reject_reason text,
    holder_after  text,                             -- 拒收后货在谁名下(责任仍归对方)

    received_by   text,                             -- 库管收货人
    note          text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ret_returner CHECK (
        (returner_staff_id IS NOT NULL AND returner_party_id IS NULL) OR
        (returner_staff_id IS NULL AND returner_party_id IS NOT NULL)),
    CONSTRAINT ck_ret_reject CHECK (
        status='accepted' OR
        (rejected_by IS NOT NULL AND reject_reason IS NOT NULL AND holder_after IS NOT NULL))
);
CREATE INDEX idx_ret_project ON stock_return(project_id);

CREATE TABLE stock_return_line (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    return_id     uuid NOT NULL REFERENCES stock_return(id) ON DELETE CASCADE,
    material_id   uuid NOT NULL REFERENCES material(id),
    qty           numeric(12,2) NOT NULL CHECK (qty > 0),
    condition     text NOT NULL DEFAULT 'good' CHECK (condition IN ('good','damaged')),
    -- ★ 坏料退回时现场就填损坏原因，RMA 直接继承，不用第二个人再猜一遍
    damage_cause  text CHECK (damage_cause IN
                    ('human','product_defect','wear_out','force_majeure','unknown')),
    -- good  → 回到可用库存
    -- damaged → 不回库存，转 RMA（坏货必须退回仓库才认，否则责任人自担）
    unit_cost_aud numeric(12,2),
    note          text,
    UNIQUE (return_id, material_id, condition)
);
CREATE INDEX idx_retline_material ON stock_return_line(material_id);


-- =====================================================================
--  第三十二部分：RMA 坏货登记 rma_case
-- =====================================================================
CREATE TABLE rma_case (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    rma_no        text UNIQUE NOT NULL,
    project_id    uuid NOT NULL REFERENCES project(id),
    return_line_id uuid REFERENCES stock_return_line(id),  -- 由哪笔退库产生
    material_id   uuid NOT NULL REFERENCES material(id),
    qty           numeric(12,2) NOT NULL CHECK (qty > 0),

    -- 谁退回来的(即谁上报的坏货)
    reporter_staff_id uuid REFERENCES eng_staff(id),
    reporter_party_id uuid REFERENCES project_party(id),
    reporter_name  text,
    returned_at   timestamptz NOT NULL DEFAULT now(),

    -- 包装与配件
    packaging_complete boolean,                    -- 是否带完整包装
    accessories_missing text,                      -- 缺哪些配件

    -- ★ 损坏原因：与 maintenance_job.fault_cause 同一套词表，现场填一次即可继承
    damage_cause  text CHECK (damage_cause IN
                    ('human','product_defect','wear_out','force_majeure','unknown')),
    damage_note   text,

    -- 处置
    disposition   text NOT NULL DEFAULT 'pending' CHECK (disposition IN
                    ('pending','to_supplier','scrapped','purged')),
    -- 在保 → 返供应商，四个跟踪字段防"退回去就不还了"
    supplier_sent_at     timestamptz,
    supplier_received    boolean NOT NULL DEFAULT false,   -- 供应商是否已接货
    supplier_returned    boolean NOT NULL DEFAULT false,   -- 修好是否已返还
    supplier_returned_at timestamptz,
    repair_fee_aud    numeric(12,2) NOT NULL DEFAULT 0,    -- 修理费
    freight_fee_aud   numeric(12,2) NOT NULL DEFAULT 0,    -- 运输费

    -- 过保报废后可清理，但必须记录是谁删的
    purged_by     text,
    purged_at     timestamptz,
    purge_reason  text,

    -- ★ 成本吸收归属：坏货登记当时项目是否已交付，定格
    --   未交付 → 该项目【工程成本】，影响工程利润率
    --   已交付 → 【长期运维成本】，影响长期利润率
    cost_bucket   text NOT NULL CHECK (cost_bucket IN ('engineering','maintenance')),

    note          text,
    created_by    text,
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_rma_project ON rma_case(project_id, disposition);


-- =====================================================================
--  v0.17 触发器
-- =====================================================================

-- ★ 出库给电工/Builder 时，必须同时告知 Builder(无则业主)
--   这不是通知，是【责任凭证】——没有它，业主凭什么认未退料那笔账
CREATE OR REPLACE FUNCTION trg_out_notify_builder() RETURNS trigger AS $$
DECLARE so stock_out%ROWTYPE; pcode text; body text;
        b_name text; b_email text; b_phone text; is_party boolean;
BEGIN
    SELECT * INTO so FROM stock_out WHERE id = NEW.stock_out_id;
    IF so.receiver_party_id IS NULL THEN RETURN NEW; END IF;   -- 自己人提货不用告知
    IF EXISTS(SELECT 1 FROM notification
               WHERE ref_kind='stock_out_builder' AND ref_id=so.id) THEN
        RETURN NEW;                                            -- 一张出库单只告知一次
    END IF;

    SELECT code INTO pcode FROM project WHERE id = so.project_id;
    -- 优先 Builder；没有 Builder 则发给业主
    SELECT COALESCE(contact_name, company), phone INTO b_name, b_phone
      FROM project_party
     WHERE project_id = so.project_id AND trade='builder' LIMIT 1;
    is_party := b_name IS NOT NULL;
    IF NOT is_party THEN
        SELECT o1_name, o1_email, o1_phone INTO b_name, b_email, b_phone
          FROM project WHERE id = so.project_id;
    END IF;

    SELECT string_agg(m.display_name || ' ×' || l.qty::text, E'\n' ORDER BY m.code)
      INTO body FROM stock_return_line l JOIN material m ON m.id=l.material_id WHERE false;
    SELECT string_agg(m.display_name || ' ×' || l.qty::text, E'\n' ORDER BY m.code)
      INTO body FROM stock_out_line l JOIN material m ON m.id=l.material_id
     WHERE l.stock_out_id = so.id;
    IF body IS NULL THEN RETURN NEW; END IF;

    INSERT INTO notification(project_id, ref_kind, ref_id, channel, recipient,
                             subject, body, status, triggered_by)
    VALUES (so.project_id, 'stock_out_builder', so.id, 'email',
            COALESCE(b_email, b_phone, '未登记'),
            '【KONNEXT】物料发放告知 / Material Release Notice ' || so.out_no,
            '致 ' || COALESCE(b_name,'贵方') || '：' || E'\n'
            || '项目 ' || pcode || '，我司已于 ' || to_char(so.released_at,'YYYY-MM-DD HH24:MI')
            || ' 将以下物料交付给 ' || so.receiver_name || '（' || so.receiver_phone || '）：' || E'\n'
            || body || E'\n'
            || '未使用物料请于工程结束前办理退库。' || E'\n'
            || '★ 逾期未退回的物料将计入本项目变更(Variation)结算。' || E'\n'
            || 'Unreturned materials will be charged as project Variation.',
            'queued', COALESCE(current_setting('app.actor', true),'system'));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER out_notify_builder AFTER INSERT ON stock_out_line
    FOR EACH ROW EXECUTE FUNCTION trg_out_notify_builder();

-- ★ 门禁：退库数量不能超过该人在本项目名下未退回的数量
CREATE OR REPLACE FUNCTION trg_return_qty_gate() RETURNS trigger AS $$
DECLARE r stock_return%ROWTYPE; out_qty numeric; ret_qty numeric; nm text;
BEGIN
    SELECT * INTO r FROM stock_return WHERE id = NEW.return_id;
    IF r.status = 'rejected' THEN RETURN NEW; END IF;   -- 拒收不影响库存与名下

    SELECT COALESCE(SUM(ol.qty),0) INTO out_qty
      FROM stock_out_line ol JOIN stock_out so ON so.id = ol.stock_out_id
     WHERE so.project_id = r.project_id AND ol.material_id = NEW.material_id
       AND so.receiver_staff_id IS NOT DISTINCT FROM r.returner_staff_id
       AND so.receiver_party_id IS NOT DISTINCT FROM r.returner_party_id;

    SELECT COALESCE(SUM(rl.qty),0) INTO ret_qty
      FROM stock_return_line rl JOIN stock_return sr ON sr.id = rl.return_id
     WHERE sr.project_id = r.project_id AND rl.material_id = NEW.material_id
       AND sr.status='accepted' AND rl.id <> NEW.id
       AND sr.returner_staff_id IS NOT DISTINCT FROM r.returner_staff_id
       AND sr.returner_party_id IS NOT DISTINCT FROM r.returner_party_id;

    IF NEW.qty > out_qty - ret_qty THEN
        SELECT display_name INTO nm FROM material WHERE id = NEW.material_id;
        RAISE EXCEPTION '门禁：% 名下本项目的「%」只剩 % 未退，不能退 %',
            COALESCE(r.returner_name,'该提货人'), nm, out_qty - ret_qty, NEW.qty;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER return_qty_gate BEFORE INSERT ON stock_return_line
    FOR EACH ROW EXECUTE FUNCTION trg_return_qty_gate();

-- 坏货退回 → 自动开 RMA 单（坏货不退回仓库就不认，责任人自担）
CREATE OR REPLACE FUNCTION trg_return_to_rma() RETURNS trigger AS $$
DECLARE r stock_return%ROWTYPE; ho timestamptz; seq int;
BEGIN
    IF NEW.condition <> 'damaged' THEN RETURN NEW; END IF;
    SELECT * INTO r FROM stock_return WHERE id = NEW.return_id;
    IF r.status = 'rejected' THEN RETURN NEW; END IF;

    SELECT handover_at INTO ho FROM project WHERE id = r.project_id;
    SELECT count(*)+1 INTO seq FROM rma_case WHERE project_id = r.project_id;

    INSERT INTO rma_case(rma_no, project_id, return_line_id, material_id, qty,
        reporter_staff_id, reporter_party_id, reporter_name, returned_at,
        damage_cause, cost_bucket, created_by)
    VALUES ('RMA-' || to_char(now(),'YYYYMMDD') || '-' || lpad(seq::text,3,'0'),
            r.project_id, NEW.id, NEW.material_id, NEW.qty,
            r.returner_staff_id, r.returner_party_id, r.returner_name, r.returned_at,
            COALESCE(NEW.damage_cause,'unknown'),      -- ★继承现场填的，不用再猜
            CASE WHEN ho IS NULL THEN 'engineering' ELSE 'maintenance' END,
            COALESCE(current_setting('app.actor', true),'system'));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER return_to_rma AFTER INSERT ON stock_return_line
    FOR EACH ROW EXECUTE FUNCTION trg_return_to_rma();

-- ★ 门禁：过保报废件清理必须记录操作人与原因
CREATE OR REPLACE FUNCTION trg_rma_purge_gate() RETURNS trigger AS $$
BEGIN
    IF NEW.disposition='purged' AND OLD.disposition IS DISTINCT FROM 'purged' THEN
        IF NEW.purged_by IS NULL THEN
            NEW.purged_by := current_setting('app.actor', true);
        END IF;
        IF NEW.purged_by IS NULL OR NEW.purge_reason IS NULL THEN
            RAISE EXCEPTION '门禁：清理 RMA 报废件必须记录操作人与原因';
        END IF;
        NEW.purged_at := now();
    END IF;
    -- 返供应商必须先发出去才谈接货/返还
    IF NEW.supplier_received AND NEW.supplier_sent_at IS NULL THEN
        RAISE EXCEPTION '门禁：尚未寄出，不能标记供应商已接货';
    END IF;
    IF NEW.supplier_returned AND NOT NEW.supplier_received THEN
        RAISE EXCEPTION '门禁：供应商尚未接货，不能标记已返还';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER rma_purge_gate BEFORE UPDATE ON rma_case
    FOR EACH ROW EXECUTE FUNCTION trg_rma_purge_gate();


-- =====================================================================
--  v0.17 视图
-- =====================================================================

-- ㊴ 物料在谁手里（出库 − 已退回 = 名下未退）
CREATE VIEW v_material_custody AS
SELECT so.project_id, p.code AS project_code,
       COALESCE(so.receiver_name,'(未知)') AS holder,
       so.receiver_phone, ol.material_id, m.display_name,
       SUM(ol.qty) AS qty_out,
       COALESCE((SELECT SUM(rl.qty) FROM stock_return_line rl
                   JOIN stock_return sr ON sr.id=rl.return_id
                  WHERE sr.project_id=so.project_id AND sr.status='accepted'
                    AND rl.material_id=ol.material_id
                    AND sr.returner_staff_id IS NOT DISTINCT FROM so.receiver_staff_id
                    AND sr.returner_party_id IS NOT DISTINCT FROM so.receiver_party_id),0) AS qty_returned,
       SUM(ol.qty) - COALESCE((SELECT SUM(rl.qty) FROM stock_return_line rl
                   JOIN stock_return sr ON sr.id=rl.return_id
                  WHERE sr.project_id=so.project_id AND sr.status='accepted'
                    AND rl.material_id=ol.material_id
                    AND sr.returner_staff_id IS NOT DISTINCT FROM so.receiver_staff_id
                    AND sr.returner_party_id IS NOT DISTINCT FROM so.receiver_party_id),0) AS qty_unreturned,
       (so.receiver_party_id IS NOT NULL) AS is_external
  FROM stock_out_line ol
  JOIN stock_out so ON so.id = ol.stock_out_id
  JOIN project p ON p.id = so.project_id
  JOIN material m ON m.id = ol.material_id
 GROUP BY so.project_id, p.code, so.receiver_name, so.receiver_phone,
          so.receiver_staff_id, so.receiver_party_id, ol.material_id, m.display_name;

-- ㊵ ★ 未退料 → 计入客户 Variation 的核对表（S4 开票前照这张表结算）
CREATE VIEW v_unreturned_to_variation AS
SELECT c.project_id, c.project_code, c.holder, c.is_external,
       c.display_name, c.qty_unreturned,
       mp.sell_price_aud,
       round(c.qty_unreturned * COALESCE(mp.sell_price_aud,0), 2) AS variation_amount,
       (SELECT invoice_sent_at FROM payment_milestone
         WHERE project_id=c.project_id AND kind='contract' AND stage='S4') AS s4_invoiced_at
  FROM v_material_custody c
  LEFT JOIN v_material_price mp ON mp.id = c.material_id
 WHERE c.qty_unreturned > 0;

-- ㊶ RMA 台账：滞留天数 / 保修倒计时（★保修起算 = S2 结清日）
CREATE VIEW v_rma_board AS
SELECT r.rma_no, p.code AS project_code, r.project_id,
       m.display_name, r.qty, r.reporter_name, r.returned_at::date AS returned_on,
       r.packaging_complete, r.accessories_missing, r.damage_cause, r.disposition,
       m.supplier, m.warranty_months,
       s2.settled_at::date                                   AS s2_settled_on,
       (now()::date - r.returned_at::date)                   AS rma_days,      -- RMA 滞留天数
       (now()::date - s2.settled_at::date)                   AS warranty_days_elapsed,
       (s2.settled_at + (m.warranty_months || ' months')::interval)::date AS warranty_until,
       (s2.settled_at IS NOT NULL AND m.warranty_months IS NOT NULL
        AND now() < s2.settled_at + (m.warranty_months || ' months')::interval) AS in_warranty,
       r.supplier_sent_at, r.supplier_received, r.supplier_returned,
       r.repair_fee_aud, r.freight_fee_aud,
       (r.repair_fee_aud + r.freight_fee_aud)                AS rma_cost_aud,
       r.cost_bucket, r.purged_by, r.purged_at
  FROM rma_case r
  JOIN project p ON p.id = r.project_id
  JOIN material m ON m.id = r.material_id
  LEFT JOIN payment_milestone s2
         ON s2.project_id = r.project_id AND s2.kind='contract' AND s2.stage='S2';

-- ㊷ RMA 成本归集：未交付→工程成本；已交付→长期运维成本
CREATE VIEW v_rma_cost AS
SELECT project_id, cost_bucket,
       count(*)                                   AS case_count,
       round(SUM(repair_fee_aud),2)               AS repair_fee_total,
       round(SUM(freight_fee_aud),2)              AS freight_fee_total,
       round(SUM(repair_fee_aud + freight_fee_aud),2) AS rma_cost_total
  FROM rma_case
 GROUP BY project_id, cost_bucket;

-- ㊸ 供应商返修跟踪：防"货退回去就不还了"
CREATE VIEW v_rma_supplier_track AS
SELECT rma_no, project_code, display_name, supplier,
       supplier_sent_at::date AS sent_on,
       supplier_received AS 已接货, supplier_returned AS 已返还,
       CASE WHEN supplier_sent_at IS NOT NULL AND NOT supplier_returned
            THEN (now()::date - supplier_sent_at::date) END AS days_at_supplier,
       repair_fee_aud, freight_fee_aud
  FROM v_rma_board
 WHERE disposition = 'to_supplier';


-- #####################################################################
-- ##  v0.18：盘点（账实不符）+ 修正库存公式（把退库算进去）
-- #####################################################################

-- =====================================================================
--  第三十三部分：盘点 stocktake
--    账实不符不直接改库存，而是记一笔【盘点调整】流水
--    库存公式仍是"进 − 出"，只是多一种流水；差额永久留痕、谁盘谁批都记着
-- =====================================================================
CREATE TABLE stocktake (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    take_no       text UNIQUE NOT NULL,             -- ST-2026-08-01
    scope         text NOT NULL DEFAULT 'partial' CHECK (scope IN ('full','partial')),
    scope_note    text,                             -- 抽盘时说明范围(哪个货架/哪个品类)
    started_at    timestamptz NOT NULL DEFAULT now(),
    counted_by    text,                             -- 谁盘的
    completed_at  timestamptz,
    -- ★ 审批：盘亏就是钱没了，超过阈值必须有人批
    approved_by   text,
    approved_at   timestamptz,
    status        text NOT NULL DEFAULT 'counting' CHECK (status IN
                    ('counting','pending_approval','approved','void')),
    note          text,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE stocktake_line (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    stocktake_id  uuid NOT NULL REFERENCES stocktake(id) ON DELETE CASCADE,
    material_id   uuid NOT NULL REFERENCES material(id),
    -- ★ 系统数【定格】：盘点那一刻系统算出来多少，抄一份存死。
    --   不存的话，事后别人再出入库，"当时差了多少"就永远还原不出来
    system_qty    numeric(12,2) NOT NULL,
    counted_qty   numeric(12,2) NOT NULL CHECK (counted_qty >= 0),
    -- 差额 = 实点 − 系统；负数=盘亏，正数=盘盈
    diff_qty      numeric(12,2) GENERATED ALWAYS AS (counted_qty - system_qty) STORED,
    unit_cost_aud numeric(12,2),                    -- 折算金额用
    reason        text,                             -- ★盘亏必填
    note          text,
    UNIQUE (stocktake_id, material_id)
);
CREATE INDEX idx_stline_material ON stocktake_line(material_id);

INSERT INTO eng_setting(key, value_num, note) VALUES
 ('stocktake_approve_amount_aud', 200,
  '盘亏审批阈值(AUD)：单次盘点亏损金额超过此数，必须有人审批才能生效');


-- =====================================================================
--  v0.18 触发器
-- =====================================================================

-- 盘点行落库时，把当时的系统库存抄一份定格
CREATE OR REPLACE FUNCTION trg_stline_snapshot() RETURNS trigger AS $$
DECLARE st text;
BEGIN
    SELECT status INTO st FROM stocktake WHERE id = NEW.stocktake_id;
    IF st IN ('approved','void') THEN
        RAISE EXCEPTION '门禁：该盘点单已%，不能再改明细',
            CASE st WHEN 'approved' THEN '审批生效' ELSE '作废' END;
    END IF;
    IF TG_OP='INSERT' THEN
        SELECT COALESCE(qty_on_hand,0) INTO NEW.system_qty
          FROM v_material_stock WHERE material_id = NEW.material_id;
        IF NEW.unit_cost_aud IS NULL THEN
            SELECT cost_total_aud INTO NEW.unit_cost_aud
              FROM v_material_price WHERE id = NEW.material_id;
        END IF;
    END IF;
    -- ★ 盘亏必须填原因（盘盈也建议填，但不强制）
    IF NEW.counted_qty < NEW.system_qty
       AND (NEW.reason IS NULL OR btrim(NEW.reason)='') THEN
        RAISE EXCEPTION '门禁：盘亏 % 件必须填写原因（出库漏录/损坏未报/点错/丢失…）',
            NEW.system_qty - NEW.counted_qty;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER stline_snapshot BEFORE INSERT OR UPDATE ON stocktake_line
    FOR EACH ROW EXECUTE FUNCTION trg_stline_snapshot();

-- ★ 审批门禁：盘亏金额超过阈值必须有人批；生效前不影响库存
CREATE OR REPLACE FUNCTION trg_stocktake_approve() RETURNS trigger AS $$
DECLARE loss numeric; thr numeric;
BEGIN
    IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
        SELECT COALESCE(SUM(CASE WHEN diff_qty < 0
                                 THEN -diff_qty * COALESCE(unit_cost_aud,0) ELSE 0 END), 0)
          INTO loss FROM stocktake_line WHERE stocktake_id = NEW.id;
        SELECT value_num INTO thr FROM eng_setting WHERE key='stocktake_approve_amount_aud';

        IF NEW.approved_by IS NULL THEN
            NEW.approved_by := current_setting('app.actor', true);
        END IF;
        IF loss > thr AND (NEW.approved_by IS NULL OR btrim(NEW.approved_by)='') THEN
            RAISE EXCEPTION '门禁：本次盘亏金额 A$%，超过审批线 A$%，必须由主管审批', loss, thr;
        END IF;
        IF NEW.counted_by IS NOT NULL AND NEW.approved_by = NEW.counted_by AND loss > thr THEN
            RAISE EXCEPTION '门禁：盘亏 A$% 超过审批线，盘点人不能自己批自己（%）', loss, NEW.approved_by;
        END IF;
        NEW.approved_at := now();
        NEW.completed_at := COALESCE(NEW.completed_at, now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER stocktake_approve BEFORE UPDATE ON stocktake
    FOR EACH ROW EXECUTE FUNCTION trg_stocktake_approve();

CREATE TRIGGER stocktake_audit AFTER INSERT OR UPDATE OR DELETE ON stocktake
    FOR EACH ROW EXECUTE FUNCTION trg_audit();


-- =====================================================================
--  v0.18 视图：★重建库存公式
--    ⚠️ v0.17 的 bug：加了退库单却没接进库存——退回来的好料在货架上，
--       系统当它不存在。不报错，只是数字悄悄错了。此处一并修正。
--
--    当前库存 = Σ到货 − Σ出库 + Σ退回(好料·未被拒收) + Σ盘点调整(已审批)
--    坏料退回不进可用库存（转 RMA），避免坏货被当好货再发出去
-- =====================================================================
DROP VIEW IF EXISTS v_rma_supplier_track;
DROP VIEW IF EXISTS v_rma_board;
DROP VIEW IF EXISTS v_unreturned_to_variation;
DROP VIEW IF EXISTS v_archived_with_stock;
DROP VIEW IF EXISTS v_material_list;
DROP VIEW IF EXISTS v_opening_status;
DROP VIEW IF EXISTS v_reorder_alert;
DROP VIEW IF EXISTS v_material_stock;

CREATE VIEW v_material_stock AS
SELECT m.id AS material_id, m.code, m.category, m.internal_name, m.spec,
       m.display_name,
       m.purchase_class, m.reorder_point,
       COALESCE(po.ordered,0)  AS qty_ordered_total,
       COALESCE(po.arrived,0)  AS qty_arrived_total,
       COALESCE(po.ordered,0) - COALESCE(po.arrived,0) AS qty_in_transit,
       COALESCE(so.out_qty,0)  AS qty_out_total,
       COALESCE(sr.ret_qty,0)  AS qty_returned_good,     -- ★退回的好料
       COALESCE(adj.adj_qty,0) AS qty_adjusted,          -- ★盘点调整(负=盘亏)
       COALESCE(po.arrived,0) - COALESCE(so.out_qty,0)
         + COALESCE(sr.ret_qty,0) + COALESCE(adj.adj_qty,0) AS qty_on_hand,
       (m.purchase_class='C1' AND m.reorder_point IS NOT NULL
        AND COALESCE(po.arrived,0) - COALESCE(so.out_qty,0)
            + COALESCE(sr.ret_qty,0) + COALESCE(adj.adj_qty,0) < m.reorder_point) AS below_reorder,
       m.active
  FROM material m
  LEFT JOIN (SELECT material_id, SUM(qty_ordered) ordered, SUM(qty_arrived) arrived
               FROM purchase_order_line GROUP BY material_id) po ON po.material_id=m.id
  LEFT JOIN (SELECT material_id, SUM(qty) out_qty
               FROM stock_out_line GROUP BY material_id) so ON so.material_id=m.id
  LEFT JOIN (SELECT rl.material_id, SUM(rl.qty) ret_qty
               FROM stock_return_line rl JOIN stock_return sr2 ON sr2.id=rl.return_id
              WHERE rl.condition='good' AND sr2.status='accepted'
              GROUP BY rl.material_id) sr ON sr.material_id=m.id
  LEFT JOIN (SELECT sl.material_id, SUM(sl.diff_qty) adj_qty
               FROM stocktake_line sl JOIN stocktake st ON st.id=sl.stocktake_id
              WHERE st.status='approved'
              GROUP BY sl.material_id) adj ON adj.material_id=m.id;

CREATE VIEW v_reorder_alert AS
SELECT code, category, display_name, internal_name, spec, reorder_point,
       qty_on_hand, qty_in_transit,
       (reorder_point - qty_on_hand) AS shortfall,
       (qty_on_hand + qty_in_transit >= reorder_point) AS covered_by_in_transit
  FROM v_material_stock
 WHERE below_reorder AND active;

CREATE VIEW v_opening_status AS
SELECT m.code, m.category, m.display_name, m.internal_name, m.spec, m.purchase_class,
       (op.qty IS NOT NULL) AS opening_done,
       op.qty               AS opening_qty,
       op.unit_cost         AS opening_unit_cost,
       s.qty_on_hand        AS current_on_hand
  FROM material m
  LEFT JOIN (SELECT l.material_id, l.qty_arrived AS qty, l.unit_cost_aud AS unit_cost
               FROM purchase_order_line l JOIN purchase_order po ON po.id = l.po_id
              WHERE po.source_type = 'opening') op ON op.material_id = m.id
  LEFT JOIN v_material_stock s ON s.material_id = m.id
 WHERE m.active;

CREATE VIEW v_material_list AS
SELECT m.id, m.code, m.category, m.protocol, m.display_name, m.internal_name, m.spec,
       m.supplier_model, m.supplier, m.purchase_class, m.reorder_point,
       m.warranty_months, m.active,
       (NOT m.active)  AS strikethrough,
       m.archived_at, m.archived_by, m.archive_reason,
       m.restored_at,  m.restored_by,
       s.qty_on_hand, s.qty_in_transit,
       (NOT EXISTS(SELECT 1 FROM purchase_order_line l WHERE l.material_id=m.id)
        AND NOT EXISTS(SELECT 1 FROM stock_out_line o WHERE o.material_id=m.id)) AS can_hard_delete,
       m.updated_by, m.updated_at
  FROM material m
  LEFT JOIN v_material_stock s ON s.material_id = m.id;

CREATE VIEW v_archived_with_stock AS
SELECT code, display_name, archived_at::date AS archived_on, archived_by, archive_reason,
       qty_on_hand, qty_in_transit,
       '已划掉但仍有存货，请安排出清或退货' AS action_needed
  FROM v_material_list
 WHERE NOT active AND (COALESCE(qty_on_hand,0) > 0 OR COALESCE(qty_in_transit,0) > 0);

CREATE VIEW v_unreturned_to_variation AS
SELECT c.project_id, c.project_code, c.holder, c.is_external,
       c.display_name, c.qty_unreturned,
       mp.sell_price_aud,
       round(c.qty_unreturned * COALESCE(mp.sell_price_aud,0), 2) AS variation_amount,
       (SELECT invoice_sent_at FROM payment_milestone
         WHERE project_id=c.project_id AND kind='contract' AND stage='S4') AS s4_invoiced_at
  FROM v_material_custody c
  LEFT JOIN v_material_price mp ON mp.id = c.material_id
 WHERE c.qty_unreturned > 0;

CREATE VIEW v_rma_board AS
SELECT r.rma_no, p.code AS project_code, r.project_id,
       m.display_name, r.qty, r.reporter_name, r.returned_at::date AS returned_on,
       r.packaging_complete, r.accessories_missing, r.damage_cause, r.disposition,
       m.supplier, m.warranty_months,
       s2.settled_at::date AS s2_settled_on,
       (now()::date - r.returned_at::date) AS rma_days,
       (now()::date - s2.settled_at::date) AS warranty_days_elapsed,
       (s2.settled_at + (m.warranty_months || ' months')::interval)::date AS warranty_until,
       (s2.settled_at IS NOT NULL AND m.warranty_months IS NOT NULL
        AND now() < s2.settled_at + (m.warranty_months || ' months')::interval) AS in_warranty,
       r.supplier_sent_at, r.supplier_received, r.supplier_returned,
       r.repair_fee_aud, r.freight_fee_aud,
       (r.repair_fee_aud + r.freight_fee_aud) AS rma_cost_aud,
       r.cost_bucket, r.purged_by, r.purged_at
  FROM rma_case r
  JOIN project p ON p.id = r.project_id
  JOIN material m ON m.id = r.material_id
  LEFT JOIN payment_milestone s2
         ON s2.project_id = r.project_id AND s2.kind='contract' AND s2.stage='S2';

CREATE VIEW v_rma_supplier_track AS
SELECT rma_no, project_code, display_name, supplier,
       supplier_sent_at::date AS sent_on,
       supplier_received AS 已接货, supplier_returned AS 已返还,
       CASE WHEN supplier_sent_at IS NOT NULL AND NOT supplier_returned
            THEN (now()::date - supplier_sent_at::date) END AS days_at_supplier,
       repair_fee_aud, freight_fee_aud
  FROM v_rma_board
 WHERE disposition = 'to_supplier';

-- ㊹ 库存流水（★补上退库与盘点调整；入正出负，可逐笔回溯）
CREATE OR REPLACE VIEW v_stock_ledger AS
SELECT l.material_id, m.display_name, m.internal_name, m.spec,
       'in'::text AS direction, po.arrived_at AS at,
       l.qty_arrived AS qty, po.po_no AS ref_no, po.supplier AS counterparty,
       NULL::uuid AS project_id
  FROM purchase_order_line l
  JOIN purchase_order po ON po.id=l.po_id
  JOIN material m ON m.id=l.material_id
 WHERE l.qty_arrived > 0
UNION ALL
SELECT ol.material_id, m.display_name, m.internal_name, m.spec,
       'out', so.released_at, -ol.qty, so.out_no, so.receiver_name, so.project_id
  FROM stock_out_line ol
  JOIN stock_out so ON so.id=ol.stock_out_id
  JOIN material m ON m.id=ol.material_id
UNION ALL
SELECT rl.material_id, m.display_name, m.internal_name, m.spec,
       'return', sr.returned_at, rl.qty, sr.return_no, sr.returner_name, sr.project_id
  FROM stock_return_line rl
  JOIN stock_return sr ON sr.id=rl.return_id
  JOIN material m ON m.id=rl.material_id
 WHERE rl.condition='good' AND sr.status='accepted'
UNION ALL
SELECT sl.material_id, m.display_name, m.internal_name, m.spec,
       'adjust', st.approved_at, sl.diff_qty, st.take_no,
       COALESCE(st.counted_by,'') || '/' || COALESCE(st.approved_by,''), NULL::uuid
  FROM stocktake_line sl
  JOIN stocktake st ON st.id=sl.stocktake_id
  JOIN material m ON m.id=sl.material_id
 WHERE st.status='approved' AND sl.diff_qty <> 0;

-- ㊺ 盘点结果：账实对比 + 盈亏金额
CREATE VIEW v_stocktake_result AS
SELECT st.take_no, st.scope, st.scope_note, st.status,
       st.counted_by, st.approved_by, st.completed_at::date AS completed_on,
       m.code, m.display_name,
       sl.system_qty AS 账面, sl.counted_qty AS 实点, sl.diff_qty AS 差额,
       round(sl.diff_qty * COALESCE(sl.unit_cost_aud,0), 2) AS diff_amount_aud,
       sl.reason
  FROM stocktake_line sl
  JOIN stocktake st ON st.id = sl.stocktake_id
  JOIN material m ON m.id = sl.material_id;

-- ㊻ 盘点汇总：本次盘亏多少钱、是否超审批线
CREATE VIEW v_stocktake_summary AS
SELECT st.id, st.take_no, st.scope, st.status, st.counted_by, st.approved_by,
       count(*)                                                   AS line_count,
       count(*) FILTER (WHERE sl.diff_qty <> 0)                    AS diff_count,
       count(*) FILTER (WHERE sl.diff_qty < 0)                     AS loss_count,
       count(*) FILTER (WHERE sl.diff_qty > 0)                     AS gain_count,
       round(SUM(CASE WHEN sl.diff_qty < 0
                      THEN -sl.diff_qty * COALESCE(sl.unit_cost_aud,0) ELSE 0 END),2) AS loss_amount_aud,
       round(SUM(CASE WHEN sl.diff_qty > 0
                      THEN sl.diff_qty * COALESCE(sl.unit_cost_aud,0) ELSE 0 END),2)  AS gain_amount_aud,
       (SELECT value_num FROM eng_setting WHERE key='stocktake_approve_amount_aud')   AS approve_threshold,
       (round(SUM(CASE WHEN sl.diff_qty < 0
                      THEN -sl.diff_qty * COALESCE(sl.unit_cost_aud,0) ELSE 0 END),2)
        > (SELECT value_num FROM eng_setting WHERE key='stocktake_approve_amount_aud')) AS needs_approval
  FROM stocktake st LEFT JOIN stocktake_line sl ON sl.stocktake_id = st.id
 GROUP BY st.id, st.take_no, st.scope, st.status, st.counted_by, st.approved_by;


-- #####################################################################
-- ##  v0.19：变更规则修正 + 未退料并入 S4 + S4 结算明细
-- #####################################################################

-- ★ 移位不计费：移位是电工的活（装错位置属整改），不是客户的变更
--   仍然登记留痕、仍然知会设计采购，但【不产生金额、不进 S4】
ALTER TABLE variation ADD COLUMN billable boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN variation.billable IS
  '是否向客户计费。移位=电工整改，不计费；加/减=客户变更，计费。人工不单列——物料售卖价已含安装人工';

UPDATE variation SET billable = false WHERE change_type = 'move';

CREATE OR REPLACE FUNCTION trg_variation_billable() RETURNS trigger AS $$
BEGIN
    IF NEW.change_type = 'move' THEN
        NEW.billable := false;
        IF COALESCE(NEW.settle_amount,0) <> 0 THEN
            RAISE EXCEPTION '门禁：移位属电工整改，不向客户计费，结算金额必须为空或 0';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER variation_billable BEFORE INSERT OR UPDATE ON variation
    FOR EACH ROW EXECUTE FUNCTION trg_variation_billable();

-- ★ S4 应收自动计算：只汇总【可计费】变更
CREATE OR REPLACE FUNCTION trg_pm_amount_lock() RETURNS trigger AS $$
DECLARE cp numeric; var_sum numeric;
BEGIN
    IF NEW.invoice_sent_at IS NOT NULL
       AND (TG_OP='INSERT' OR OLD.invoice_sent_at IS NULL OR NEW.invoice_ver > OLD.invoice_ver) THEN
        IF NEW.amount_due IS NULL AND NEW.kind='contract' THEN
            SELECT contract_price INTO cp FROM project WHERE id=NEW.project_id;
            SELECT COALESCE(SUM(settle_amount),0) INTO var_sum
              FROM variation WHERE project_id=NEW.project_id AND billable;
            NEW.amount_due := round(cp * NEW.ratio_pct / 100, 2)
                              + CASE WHEN NEW.stage='S4' THEN var_sum ELSE 0 END;
        END IF;
        IF NEW.amount_due IS NULL THEN
            RAISE EXCEPTION '门禁：应收金额为空，不能发出 Invoice';
        END IF;
        IF NEW.first_invoice_sent_at IS NULL THEN
            NEW.first_invoice_sent_at := NEW.invoice_sent_at;
        END IF;
        IF NEW.status='pending' THEN NEW.status := 'invoiced'; END IF;
    END IF;
    IF TG_OP='UPDATE' AND OLD.invoice_sent_at IS NOT NULL
       AND NEW.amount_due IS DISTINCT FROM OLD.amount_due
       AND NEW.invoice_ver = OLD.invoice_ver THEN
        RAISE EXCEPTION '门禁：Invoice 已发出(客户手上那张写的是 %)，改金额必须 invoice_ver +1 重开新版',
            OLD.amount_due;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ★ 未退料结算：S4 开票【前】执行，把未退料转成正式变更记录
--   ⚠️ 修的是 v0.17 的洞：未退料原先只是视图，没进 variation 表，
--      导致明细表算 56513.83、发票自动算 54500，差 2013.83 且不报错
CREATE OR REPLACE FUNCTION fn_settle_unreturned(p_project_id uuid)
RETURNS text AS $$
DECLARE r record; n int := 0; total numeric := 0; s4_sent timestamptz;
BEGIN
    SELECT invoice_sent_at INTO s4_sent FROM payment_milestone
     WHERE project_id=p_project_id AND kind='contract' AND stage='S4';
    IF s4_sent IS NOT NULL THEN
        RAISE EXCEPTION '门禁：S4 发票已于 % 发出，不能再追加未退料变更。要追加请 S4 开新版本重发', s4_sent;
    END IF;

    FOR r IN SELECT * FROM v_unreturned_to_variation WHERE project_id = p_project_id LOOP
        IF EXISTS(SELECT 1 FROM variation
                   WHERE project_id=p_project_id AND origin='unreturned'
                     AND description LIKE '%'||r.display_name||'%'||r.holder||'%') THEN
            CONTINUE;   -- 已结算过，不重复计
        END IF;
        INSERT INTO variation(project_id, origin, change_type, description,
            settle_amount, settle_source, settle_status, settle_note, billable,
            settle_by, notified_design, notified_procure, notified_finance)
        VALUES (p_project_id, 'unreturned', 'add',
            r.display_name || ' ×' || r.qty_unreturned || '（' || r.holder || ' 领用未退）',
            r.variation_amount, 'manual', 'settled_s4',
            '出库后未办理退库，按售卖价计入变更；出库当日已告知 Builder', true,
            COALESCE(current_setting('app.actor', true), 'fn_settle_unreturned'),
            true, true, true);
        n := n + 1; total := total + r.variation_amount;
    END LOOP;
    RETURN format('已结算未退料 %s 项，合计 A$%s', n, round(total,2));
END;
$$ LANGUAGE plpgsql;

-- ㊼ S4 结算总表（财务开票前的一张纸）
CREATE VIEW v_s4_settlement AS
WITH base AS (
    SELECT p.id AS project_id, p.code, p.name, p.contract_price,
           COALESCE((SELECT ratio_pct FROM payment_milestone
                      WHERE project_id=p.id AND kind='contract' AND stage='S4'),10) AS s4_ratio
      FROM project p
), var AS (
    SELECT project_id,
           COALESCE(SUM(settle_amount) FILTER (WHERE billable),0)                    AS var_total,
           COALESCE(SUM(settle_amount) FILTER (WHERE billable AND settle_amount>0),0) AS var_add,
           COALESCE(SUM(settle_amount) FILTER (WHERE billable AND settle_amount<0),0) AS var_less,
           count(*)                                                                  AS var_count,
           count(*) FILTER (WHERE NOT billable)                                       AS var_nonbillable,
           count(*) FILTER (WHERE billable AND settle_amount IS NULL)                 AS var_unpriced
      FROM variation GROUP BY project_id
), unset AS (
    -- ★待结算未退料 = 现存未退料金额 − 已转成变更记录的部分
    --   货还在对方手上，未退料视图不会变；结算过的必须扣掉，否则永远提示"需先结算"
    SELECT u.project_id,
           GREATEST(COALESCE(u.amt,0) - COALESCE(v.settled,0), 0) AS pending_unreturned
      FROM (SELECT project_id, SUM(variation_amount) amt
              FROM v_unreturned_to_variation GROUP BY project_id) u
      LEFT JOIN (SELECT project_id, SUM(settle_amount) settled
                   FROM variation WHERE origin='unreturned' GROUP BY project_id) v
             ON v.project_id = u.project_id
), paid AS (
    SELECT m.project_id,
           COALESCE(SUM(r.amount) FILTER (WHERE m.stage IN ('S1','S2','S3')),0) AS prior_received
      FROM payment_milestone m LEFT JOIN payment_receipt r ON r.milestone_id=m.id
     WHERE m.kind='contract' GROUP BY m.project_id
)
SELECT b.project_id, b.code, b.name, b.contract_price,
       round(b.contract_price*b.s4_ratio/100,2)  AS s4_base,
       COALESCE(v.var_add,0)                     AS variation_add,
       COALESCE(v.var_less,0)                    AS variation_less,
       COALESCE(v.var_total,0)                   AS variation_net,
       COALESCE(v.var_unpriced,0)                AS unpriced_count,
       COALESCE(v.var_nonbillable,0)             AS nonbillable_count,
       COALESCE(u.pending_unreturned,0)          AS pending_unreturned,   -- ★还没结算的未退料
       round(b.contract_price*b.s4_ratio/100 + COALESCE(v.var_total,0),2) AS s4_payable,
       COALESCE(p.prior_received,0)              AS prior_received,
       -- ★ 开票前必须先把未退料结算掉，否则发票会少收
       (COALESCE(u.pending_unreturned,0) > 0)    AS need_settle_unreturned
  FROM base b
  LEFT JOIN var v ON v.project_id=b.project_id
  LEFT JOIN unset u ON u.project_id=b.project_id
  LEFT JOIN paid p ON p.project_id=b.project_id;

-- ㊽ S4 逐条明细（对客户列账；每条可追到来源、登记人、计算依据）
CREATE VIEW v_s4_line_items AS
SELECT p.id AS project_id, p.code AS project_code, 1 AS sort_no, true AS billable,
       '合同尾款'::text AS item_type,
       ('S4 尾款（签约价 ' || p.contract_price || ' × ' ||
         COALESCE((SELECT ratio_pct FROM payment_milestone
                    WHERE project_id=p.id AND kind='contract' AND stage='S4'),10) || '%）')::text AS description,
       round(p.contract_price * COALESCE((SELECT ratio_pct FROM payment_milestone
              WHERE project_id=p.id AND kind='contract' AND stage='S4'),10)/100,2) AS amount_aud,
       '签约合同'::text AS source_ref, NULL::timestamptz AS logged_at,
       NULL::text AS logged_by, NULL::text AS basis
  FROM project p
UNION ALL
SELECT v.project_id, p.code, 2, v.billable,
       CASE v.change_type WHEN 'add' THEN
              CASE WHEN v.origin='unreturned' THEN '未退料' ELSE '变更·增加' END
            WHEN 'remove' THEN '变更·减少'
            ELSE '移位（电工整改·不计费）' END,
       v.description, v.settle_amount,
       CASE v.origin WHEN 'sm3' THEN 'SM3 变更登记'
                     WHEN 'unreturned' THEN '出库单 / 退库记录'
                     ELSE v.origin END
         || COALESCE(' / '||v.settle_ext_ref,''),
       v.created_at, COALESCE(s.name, v.settle_by), v.settle_note
  FROM variation v
  JOIN project p ON p.id=v.project_id
  LEFT JOIN eng_staff s ON s.id=v.logged_by;


-- #####################################################################
-- ##  v0.20：文档库（版本化）+ 流程节点调取 + 发放签收
-- #####################################################################

-- =====================================================================
--  第三十四部分：文档 document（逻辑文档，不含内容）
-- =====================================================================
CREATE TABLE document (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_code     text UNIQUE NOT NULL,             -- DOC-SM2-FINISH
    title        text NOT NULL,
    -- 三类性质完全不同的文档
    doc_type     text NOT NULL CHECK (doc_type IN
                   ('internal_guide',   -- 内部作业指引（SM1~4 工程师用，全公司共用）
                    'external_notice',  -- 对外交付（致 Builder/电工，要发出去、要签收）
                    'client_doc')),     -- 客户文档（交付手册、维护说明）
    audience     text NOT NULL CHECK (audience IN
                   ('staff','electrician','builder','client','all')),
    language     text NOT NULL DEFAULT 'zh' CHECK (language IN ('zh','en','bilingual')),
    owner_role   text,                             -- 谁维护这份文档
    active       boolean NOT NULL DEFAULT true,
    note         text,
    created_at   timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================
--  第三十五部分：文档版本 document_version（★只增不改）
--    改一次存一版。已按旧版做过的项目，记录里挂的仍是当时那一版
-- =====================================================================
CREATE TABLE document_version (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id  uuid NOT NULL REFERENCES document(id) ON DELETE CASCADE,
    version_no   integer NOT NULL CHECK (version_no > 0),
    file_url     text NOT NULL,
    file_name    text,
    change_note  text,                             -- 这一版改了什么
    effective_from date NOT NULL DEFAULT current_date,
    published_by text,
    published_at timestamptz NOT NULL DEFAULT now(),
    superseded_at timestamptz,                     -- 被下一版取代的时间
    UNIQUE (document_id, version_no)
);
CREATE INDEX idx_docver_doc ON document_version(document_id, version_no DESC);

-- =====================================================================
--  第三十六部分：流程节点绑定 document_binding
--    "走到这一步该带哪些文档" —— 工程人员打开任务就看得到
-- =====================================================================
CREATE TABLE document_binding (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    node         text NOT NULL CHECK (node IN
                   ('sm1','sm2','sm3','sm4','install','handover','maintenance')),
    document_id  uuid NOT NULL REFERENCES document(id) ON DELETE CASCADE,
    required     boolean NOT NULL DEFAULT true,    -- 必交/必带
    need_ack     boolean NOT NULL DEFAULT false,   -- 是否需要对方签收
    note         text,
    UNIQUE (node, document_id)
);

-- =====================================================================
--  第三十七部分：发放记录 document_issue（★锁定具体版本）
--    电工签的是"我收到了第 2 版"。后来改成第 3 版，他没签过第 3 版——
--    出问题时这个差别要命，所以这里存的是【版本 id】，不是文档 id
-- =====================================================================
CREATE TABLE document_issue (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    node          text NOT NULL,
    version_id    uuid NOT NULL REFERENCES document_version(id),  -- ★定格到版本
    -- 发给谁
    to_staff_id   uuid REFERENCES eng_staff(id),
    to_party_id   uuid REFERENCES project_party(id),
    to_client     boolean NOT NULL DEFAULT false,
    recipient_name text,
    issued_at     timestamptz NOT NULL DEFAULT now(),
    issued_by     text,
    channel       text CHECK (channel IN ('email','sms','onsite','system')),
    notification_id uuid REFERENCES notification(id),
    -- 签收
    acknowledged  boolean NOT NULL DEFAULT false,
    ack_at        timestamptz,
    ack_sign_url  text,                            -- 签纸拍照
    ack_note      text,
    UNIQUE (project_id, node, version_id, to_staff_id, to_party_id, to_client)
);
CREATE INDEX idx_docissue_project ON document_issue(project_id, node);


-- =====================================================================
--  v0.20 触发器
-- =====================================================================

-- 版本只增不改：发新版时自动给上一版盖上"被取代"时间
CREATE OR REPLACE FUNCTION trg_docver_supersede() RETURNS trigger AS $$
BEGIN
    UPDATE document_version
       SET superseded_at = NEW.published_at
     WHERE document_id = NEW.document_id
       AND version_no < NEW.version_no
       AND superseded_at IS NULL;
    IF NEW.published_by IS NULL THEN
        NEW.published_by := current_setting('app.actor', true);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER docver_supersede BEFORE INSERT ON document_version
    FOR EACH ROW EXECUTE FUNCTION trg_docver_supersede();

-- 已发放的版本不许改文件地址（发出去的东西不能偷换）
CREATE OR REPLACE FUNCTION trg_docver_immutable() RETURNS trigger AS $$
BEGIN
    IF NEW.file_url IS DISTINCT FROM OLD.file_url
       AND EXISTS(SELECT 1 FROM document_issue WHERE version_id = OLD.id) THEN
        RAISE EXCEPTION '门禁：该版本已发放给他人，不能改文件。请发布新版本';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER docver_immutable BEFORE UPDATE ON document_version
    FOR EACH ROW EXECUTE FUNCTION trg_docver_immutable();

-- 签收留痕
CREATE OR REPLACE FUNCTION trg_docissue_ack() RETURNS trigger AS $$
BEGIN
    IF NEW.acknowledged AND NOT OLD.acknowledged THEN
        NEW.ack_at := COALESCE(NEW.ack_at, now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER docissue_ack BEFORE UPDATE ON document_issue
    FOR EACH ROW EXECUTE FUNCTION trg_docissue_ack();

-- ★ 门禁：SM 完成时，本节点【必须发放且需签收】的文档必须已签收
--   SM2 交付 Finish 给电工 → 电工签字知悉，这条规矩终于落地
CREATE OR REPLACE FUNCTION trg_sm_doc_gate() RETURNS trigger AS $$
DECLARE missing text; node_key text;
BEGIN
    IF NEW.completed_at IS NULL OR (TG_OP='UPDATE' AND OLD.completed_at IS NOT NULL) THEN
        RETURN NEW;
    END IF;
    IF NEW.na_flag THEN RETURN NEW; END IF;         -- 老项目标不适用则豁免

    node_key := 'sm' || NEW.sm_no;
    SELECT string_agg(d.title, '、') INTO missing
      FROM document_binding b JOIN document d ON d.id = b.document_id
     WHERE b.node = node_key AND b.required AND b.need_ack AND d.active
       AND NOT EXISTS (
           SELECT 1 FROM document_issue i
             JOIN document_version v ON v.id = i.version_id
            WHERE i.project_id = NEW.project_id AND i.node = node_key
              AND v.document_id = d.id AND i.acknowledged);
    IF missing IS NOT NULL THEN
        RAISE EXCEPTION '门禁：以下文档尚未取得对方签收，不能完成 SM%：%', NEW.sm_no, missing;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER sm_doc_gate BEFORE INSERT OR UPDATE ON site_meeting
    FOR EACH ROW EXECUTE FUNCTION trg_sm_doc_gate();

-- ★ 门禁：交付完成时，必交的客户文档必须都已发放
CREATE OR REPLACE FUNCTION trg_handover_doc_gate() RETURNS trigger AS $$
DECLARE missing text;
BEGIN
    IF NEW.completed_at IS NULL OR (TG_OP='UPDATE' AND OLD.completed_at IS NOT NULL) THEN
        RETURN NEW;
    END IF;
    SELECT string_agg(d.title, '、') INTO missing
      FROM document_binding b JOIN document d ON d.id = b.document_id
     WHERE b.node='handover' AND b.required AND d.active
       AND NOT EXISTS (
           SELECT 1 FROM document_issue i
             JOIN document_version v ON v.id = i.version_id
            WHERE i.project_id = NEW.project_id AND i.node='handover'
              AND v.document_id = d.id);
    IF missing IS NOT NULL THEN
        RAISE EXCEPTION '门禁：以下客户文档尚未交付，不能完成交付：%', missing;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER handover_doc_gate BEFORE INSERT OR UPDATE ON handover_job
    FOR EACH ROW EXECUTE FUNCTION trg_handover_doc_gate();


-- =====================================================================
--  v0.20 视图
-- =====================================================================

-- ㊾ 每份文档的当前版本
CREATE VIEW v_document_current AS
SELECT d.id AS document_id, d.doc_code, d.title, d.doc_type, d.audience, d.language,
       d.owner_role, d.active,
       v.id AS version_id, v.version_no, v.file_url, v.file_name,
       v.effective_from, v.published_by, v.published_at, v.change_note,
       (SELECT count(*) FROM document_version x WHERE x.document_id=d.id) AS total_versions
  FROM document d
  LEFT JOIN LATERAL (
       SELECT * FROM document_version dv
        WHERE dv.document_id = d.id AND dv.superseded_at IS NULL
        ORDER BY dv.version_no DESC LIMIT 1) v ON true;

-- ㊿ ★流程中调取：走到这一步该带哪些文档（自动给当前版本）
CREATE VIEW v_node_documents AS
SELECT b.node, d.doc_code, d.title, d.doc_type, d.audience, d.language,
       b.required, b.need_ack,
       c.version_id, c.version_no, c.file_url, c.effective_from,
       b.note
  FROM document_binding b
  JOIN document d ON d.id = b.document_id
  LEFT JOIN v_document_current c ON c.document_id = d.id
 WHERE d.active;

-- 51 项目文档发放台账：发了哪一版给谁、签没签
CREATE VIEW v_document_issue_status AS
SELECT i.project_id, p.code AS project_code, i.node,
       d.doc_code, d.title, v.version_no, v.file_url,
       COALESCE(i.recipient_name,
                (SELECT name FROM eng_staff WHERE id=i.to_staff_id),
                (SELECT COALESCE(contact_name,company) FROM project_party WHERE id=i.to_party_id),
                CASE WHEN i.to_client THEN '客户' END) AS recipient,
       i.channel, i.issued_at, i.issued_by,
       i.acknowledged, i.ack_at, i.ack_sign_url,
       b.required, b.need_ack,
       -- ★ 是否发的是最新版（发完之后文档又改版了，这里会亮出来）
       (v.superseded_at IS NULL) AS is_current_version,
       (SELECT max(version_no) FROM document_version x WHERE x.document_id=d.id) AS latest_version_no
  FROM document_issue i
  JOIN document_version v ON v.id = i.version_id
  JOIN document d ON d.id = v.document_id
  JOIN project p ON p.id = i.project_id
  LEFT JOIN document_binding b ON b.node = i.node AND b.document_id = d.id;

-- 52 节点文档完成度：还差哪些没发、哪些没签收
CREATE VIEW v_node_doc_checklist AS
SELECT p.id AS project_id, p.code AS project_code, b.node,
       d.doc_code, d.title, d.audience, b.required, b.need_ack,
       (i.id IS NOT NULL)                    AS issued,
       COALESCE(i.acknowledged,false)        AS acknowledged,
       i.issued_at, i.ack_at,
       CASE WHEN i.id IS NULL AND b.required THEN '未发放'
            WHEN b.need_ack AND NOT COALESCE(i.acknowledged,false) THEN '待签收'
            ELSE '已完成' END                AS status_cn
  FROM project p
  CROSS JOIN document_binding b
  JOIN document d ON d.id = b.document_id AND d.active
  LEFT JOIN LATERAL (
      SELECT ii.* FROM document_issue ii
        JOIN document_version vv ON vv.id = ii.version_id
       WHERE ii.project_id = p.id AND ii.node = b.node AND vv.document_id = d.id
       ORDER BY ii.issued_at DESC LIMIT 1) i ON true;


-- #####################################################################
-- ##  v0.21：故障归因四类统一词表 + 索赔建议
-- #####################################################################

COMMENT ON COLUMN maintenance_job.fault_cause IS
  '四类统一词表：human 人为 / product_defect 产品缺陷(可索赔) / wear_out 自然老化 / force_majeure 不可抗力。现场当着客户面确认一次，RMA 继承';

-- 维护任务完成 → 归因带回维护单时，一并带到 RMA（若同批坏货已开 RMA）
CREATE OR REPLACE FUNCTION trg_mj_cause_to_rma() RETURNS trigger AS $$
BEGIN
    IF NEW.completed_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.completed_at IS NULL)
       AND NEW.fault_cause IS NOT NULL THEN
        UPDATE rma_case
           SET damage_cause = NEW.fault_cause
         WHERE project_id = NEW.project_id
           AND damage_cause = 'unknown'
           AND returned_at >= NEW.completed_at - interval '7 days';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER mj_cause_to_rma AFTER INSERT OR UPDATE ON maintenance_job
    FOR EACH ROW EXECUTE FUNCTION trg_mj_cause_to_rma();

-- 53 RMA 处置建议：产品缺陷 + 在保 → 找供应商索赔
CREATE VIEW v_rma_action AS
SELECT rma_no, project_code, display_name, supplier,
       damage_cause,
       CASE damage_cause
         WHEN 'human'          THEN '人为损坏'
         WHEN 'product_defect' THEN '产品缺陷'
         WHEN 'wear_out'       THEN '自然老化'
         WHEN 'force_majeure'  THEN '不可抗力'
         ELSE '未判定' END                                   AS cause_cn,
       in_warranty, warranty_until, rma_days, disposition,
       CASE
         WHEN damage_cause = 'unknown'
           THEN '★请先判定损坏原因，否则无法决定处置方式'
         WHEN damage_cause = 'product_defect' AND in_warranty
           THEN '★产品缺陷且在保 —— 返供应商索赔（免费换修）'
         WHEN damage_cause = 'product_defect' AND NOT in_warranty
           THEN '产品缺陷但已过保 —— 可与供应商交涉，否则报废'
         WHEN damage_cause = 'human'
           THEN '人为损坏 —— 由责任人承担，不向供应商索赔'
         WHEN damage_cause = 'wear_out' AND in_warranty
           THEN '自然老化但仍在保 —— 可尝试返供应商'
         WHEN damage_cause = 'wear_out'
           THEN '自然老化且已过保 —— 报废处理'
         WHEN damage_cause = 'force_majeure'
           THEN '不可抗力 —— 走保险或客户自担，不索赔'
       END                                                    AS suggested_action
  FROM v_rma_board;


-- #####################################################################
-- ##  v0.22：账号与权限（三级结构 · 无密码登录）
-- #####################################################################

-- =====================================================================
--  第三十八部分：账号 app_account
--    ★ 三级：1 决策管理员 / 2 部门负责人 / 3 施工人员(含外包)
--    ★ 全系统【无密码】——只用手机短信验证码登录，表里没有密码字段
-- =====================================================================
CREATE TABLE app_account (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    login_name    text UNIQUE NOT NULL,
    full_name     text NOT NULL,

    tier          smallint NOT NULL CHECK (tier IN (1,2,3)),
    is_core_admin boolean NOT NULL DEFAULT false,   -- 核心管理员：可建/删其他管理员

    -- 登录凭据（无密码）
    phone         text NOT NULL,                    -- 短信验证码登录，必填
    email         text,                             -- 管理员双重验证 + 自主找回
    phone_bound_at timestamptz,                     -- 管理员须强制绑定手机

    -- 第三级关联到人（工程人员或外包）
    staff_id      uuid REFERENCES eng_staff(id),
    is_contractor boolean NOT NULL DEFAULT false,   -- 外包：不计等级，但按第三级用

    -- ★ 第三级只用 App，不能进后台
    backend_access boolean NOT NULL DEFAULT true,

    active        boolean NOT NULL DEFAULT true,
    created_by    uuid REFERENCES app_account(id),
    created_at    timestamptz NOT NULL DEFAULT now(),
    deactivated_by uuid REFERENCES app_account(id),
    deactivated_at timestamptz,
    note          text,

    CONSTRAINT ck_acct_core   CHECK (NOT is_core_admin OR tier = 1),
    CONSTRAINT ck_acct_admin_email CHECK (tier <> 1 OR email IS NOT NULL),
    CONSTRAINT ck_acct_tier3  CHECK (tier <> 3 OR backend_access = false),
    CONSTRAINT ck_acct_staff  CHECK (tier <> 3 OR staff_id IS NOT NULL)
);
CREATE UNIQUE INDEX uq_account_phone ON app_account(phone) WHERE active;
COMMENT ON TABLE app_account IS
  '无密码登录：表内不存密码。手机短信验证码登录；管理员额外邮箱+手机双验证。'
  '账号找回：仅 tier1 可自主找回，其余一律由管理员重置';

-- 账号 ↔ 部门（多对多：采购与库管可由同一人兼任，则挂两个部门）
CREATE TABLE account_department (
    account_id  uuid NOT NULL REFERENCES app_account(id) ON DELETE CASCADE,
    department  text NOT NULL CHECK (department IN
                  ('presales','eng_mgmt','procurement','warehouse','finance','maintenance')),
    is_head     boolean NOT NULL DEFAULT true,      -- 是否本部门负责人
    granted_by  uuid REFERENCES app_account(id),
    granted_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, department)
);
COMMENT ON TABLE account_department IS
  '六个部门：售前/工程管理/采购/库管/财务/工程运维。一个账号可同时属于多个部门(兼任)';

-- 登录验证码（无密码机制；一次性、有时效）
CREATE TABLE auth_otp (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id  uuid REFERENCES app_account(id) ON DELETE CASCADE,
    channel     text NOT NULL CHECK (channel IN ('sms','email')),
    sent_to     text NOT NULL,
    code_hash   text NOT NULL,                      -- 只存散列，不存明文验证码
    purpose     text NOT NULL DEFAULT 'login' CHECK (purpose IN ('login','recover','bind')),
    expires_at  timestamptz NOT NULL,
    used_at     timestamptz,
    ip          text,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_otp_acct ON auth_otp(account_id, created_at DESC);

-- 账号重置/找回留痕（谁给谁重置的）
CREATE TABLE account_reset_log (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_id  uuid NOT NULL REFERENCES app_account(id) ON DELETE CASCADE,
    action      text NOT NULL CHECK (action IN ('reset_phone','reset_email','reactivate','self_recover')),
    old_value   text,
    new_value   text,
    performed_by uuid REFERENCES app_account(id),   -- 自主找回时为本人
    reason      text,
    at          timestamptz NOT NULL DEFAULT now()
);

INSERT INTO eng_setting(key, value_num, note) VALUES
 ('max_admin_accounts', 3, '决策管理员账号上限(含核心管理员)'),
 ('otp_valid_minutes', 10, '短信/邮箱验证码有效期(分钟)');


-- =====================================================================
--  v0.22 触发器：三级结构的硬约束
-- =====================================================================

-- ★ 核心管理员唯一
CREATE OR REPLACE FUNCTION trg_core_admin_unique() RETURNS trigger AS $$
DECLARE n int;
BEGIN
    IF NEW.is_core_admin THEN
        SELECT count(*) INTO n FROM app_account
         WHERE is_core_admin AND active AND id <> NEW.id;
        IF n > 0 THEN
            RAISE EXCEPTION '门禁：核心管理员只能有一个，请先移交或停用现有核心管理员';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER core_admin_unique BEFORE INSERT OR UPDATE ON app_account
    FOR EACH ROW EXECUTE FUNCTION trg_core_admin_unique();

-- ★ 建号规则：谁能建谁
--   tier1 只能由【核心管理员】建，且总数不超上限
--   tier2 只能由 tier1 建
--   tier3 只能由【工程管理部门】的 tier2 建（外包也一样，由我们代建）
CREATE OR REPLACE FUNCTION trg_account_create_gate() RETURNS trigger AS $$
DECLARE creator app_account%ROWTYPE; n int; lim numeric; is_engmgmt boolean;
BEGIN
    -- 允许第一个核心管理员自举（系统初始化）
    IF NEW.created_by IS NULL THEN
        IF EXISTS(SELECT 1 FROM app_account) THEN
            RAISE EXCEPTION '门禁：必须指明创建人(created_by)';
        END IF;
        IF NOT (NEW.tier = 1 AND NEW.is_core_admin) THEN
            RAISE EXCEPTION '门禁：系统第一个账号必须是核心管理员';
        END IF;
        RETURN NEW;
    END IF;

    SELECT * INTO creator FROM app_account WHERE id = NEW.created_by;
    IF creator.id IS NULL OR NOT creator.active THEN
        RAISE EXCEPTION '门禁：创建人账号不存在或已停用';
    END IF;

    IF NEW.tier = 1 THEN
        IF NOT creator.is_core_admin THEN
            RAISE EXCEPTION '门禁：只有核心管理员能建立管理员账号（当前操作人：%）', creator.full_name;
        END IF;
        SELECT value_num INTO lim FROM eng_setting WHERE key='max_admin_accounts';
        SELECT count(*) INTO n FROM app_account WHERE tier=1 AND active AND id <> NEW.id;
        IF n + 1 > lim THEN
            RAISE EXCEPTION '门禁：管理员账号已达上限 %，不能再建', lim;
        END IF;
    ELSIF NEW.tier = 2 THEN
        IF creator.tier <> 1 THEN
            RAISE EXCEPTION '门禁：部门账号只能由决策管理员建立';
        END IF;
    ELSIF NEW.tier = 3 THEN
        SELECT EXISTS(SELECT 1 FROM account_department
                       WHERE account_id = creator.id AND department='eng_mgmt')
          INTO is_engmgmt;
        IF creator.tier = 1 THEN
            NULL;   -- 管理员当然也可以建
        ELSIF creator.tier = 2 AND is_engmgmt THEN
            NULL;
        ELSE
            RAISE EXCEPTION '门禁：施工人员账号只能由【工程管理】部门或决策管理员建立';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER account_create_gate BEFORE INSERT ON app_account
    FOR EACH ROW EXECUTE FUNCTION trg_account_create_gate();

-- ★ 删/停用管理员：只有核心管理员能做；核心管理员不能停用自己
CREATE OR REPLACE FUNCTION trg_account_deactivate_gate() RETURNS trigger AS $$
DECLARE actor app_account%ROWTYPE;
BEGIN
    IF OLD.active AND NOT NEW.active THEN
        IF NEW.deactivated_by IS NULL THEN
            RAISE EXCEPTION '门禁：停用账号必须记录操作人';
        END IF;
        SELECT * INTO actor FROM app_account WHERE id = NEW.deactivated_by;
        IF OLD.tier = 1 AND NOT COALESCE(actor.is_core_admin,false) THEN
            RAISE EXCEPTION '门禁：只有核心管理员能停用管理员账号';
        END IF;
        IF OLD.is_core_admin AND NEW.deactivated_by = OLD.id THEN
            RAISE EXCEPTION '门禁：核心管理员不能停用自己，请先把核心权限移交给他人';
        END IF;
        NEW.deactivated_at := COALESCE(NEW.deactivated_at, now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER account_deactivate_gate BEFORE UPDATE ON app_account
    FOR EACH ROW EXECUTE FUNCTION trg_account_deactivate_gate();

-- ★ 部门归属：tier1 不挂部门（全局）；tier3 不挂部门（只上报）；仅 tier2 挂部门
CREATE OR REPLACE FUNCTION trg_account_dept_gate() RETURNS trigger AS $$
DECLARE t smallint; nm text;
BEGIN
    SELECT tier, full_name INTO t, nm FROM app_account WHERE id = NEW.account_id;
    IF t = 1 THEN
        RAISE EXCEPTION '门禁：决策管理员是全局权限，不需要也不应挂具体部门（%）', nm;
    ELSIF t = 3 THEN
        RAISE EXCEPTION '门禁：施工人员只上报信息，不挂部门权限（%）', nm;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER account_dept_gate BEFORE INSERT ON account_department
    FOR EACH ROW EXECUTE FUNCTION trg_account_dept_gate();

-- ★ 账号找回：仅 tier1 可自主找回，其余必须由管理员重置
CREATE OR REPLACE FUNCTION trg_reset_gate() RETURNS trigger AS $$
DECLARE t smallint; actor app_account%ROWTYPE;
BEGIN
    SELECT tier INTO t FROM app_account WHERE id = NEW.account_id;
    IF NEW.action = 'self_recover' THEN
        IF t <> 1 THEN
            RAISE EXCEPTION '门禁：只有决策管理员可自主找回账号，其余账号请联系管理员重置';
        END IF;
    ELSE
        SELECT * INTO actor FROM app_account WHERE id = NEW.performed_by;
        IF actor.id IS NULL OR actor.tier <> 1 THEN
            RAISE EXCEPTION '门禁：重置账号只能由决策管理员执行';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER reset_gate BEFORE INSERT ON account_reset_log
    FOR EACH ROW EXECUTE FUNCTION trg_reset_gate();

CREATE TRIGGER account_audit AFTER INSERT OR UPDATE OR DELETE ON app_account
    FOR EACH ROW EXECUTE FUNCTION trg_audit();


-- =====================================================================
--  v0.22 视图
-- =====================================================================

-- 54 账号总览
CREATE VIEW v_account_overview AS
SELECT a.id, a.login_name, a.full_name, a.tier,
       CASE a.tier WHEN 1 THEN '决策管理员' WHEN 2 THEN '部门负责人' ELSE '施工人员' END AS tier_cn,
       a.is_core_admin, a.is_contractor, a.backend_access, a.active,
       a.phone, a.email, a.phone_bound_at,
       (SELECT string_agg(
           CASE d.department WHEN 'presales' THEN '售前' WHEN 'eng_mgmt' THEN '工程管理'
                            WHEN 'procurement' THEN '采购' WHEN 'warehouse' THEN '库管'
                            WHEN 'finance' THEN '财务' ELSE '工程运维' END, '＋'
           ORDER BY d.department)
          FROM account_department d WHERE d.account_id = a.id)      AS departments,
       (SELECT count(*) FROM account_department d WHERE d.account_id=a.id) AS dept_count,
       c.full_name AS created_by_name, a.created_at,
       s.name AS staff_name, s.pay_type
  FROM app_account a
  LEFT JOIN app_account c ON c.id = a.created_by
  LEFT JOIN eng_staff s ON s.id = a.staff_id;

-- 55 兼任提醒：一个账号同时管采购和库管 → 自查自批风险
CREATE VIEW v_dual_role_alert AS
SELECT a.id, a.login_name, a.full_name,
       '同时负责采购与库管：可自己下单、自己确认到货。建议到货确认与盘点审批交由他人复核'::text AS risk_note
  FROM app_account a
 WHERE a.active AND a.tier = 2
   AND EXISTS(SELECT 1 FROM account_department d WHERE d.account_id=a.id AND d.department='procurement')
   AND EXISTS(SELECT 1 FROM account_department d WHERE d.account_id=a.id AND d.department='warehouse');

-- 56 管理员账号健康检查（上限、绑定、邮箱）
CREATE VIEW v_admin_health AS
SELECT count(*) FILTER (WHERE tier=1 AND active)                       AS admin_count,
       (SELECT value_num FROM eng_setting WHERE key='max_admin_accounts') AS admin_limit,
       count(*) FILTER (WHERE is_core_admin AND active)                AS core_admin_count,
       count(*) FILTER (WHERE tier=1 AND active AND phone_bound_at IS NULL) AS admin_unbound_phone,
       count(*) FILTER (WHERE tier=1 AND active AND email IS NULL)      AS admin_no_email
  FROM app_account;


-- #####################################################################
-- ##  v0.23：部门交接短信通知（通用机制）
-- ##  卡点建好了但"该谁动了"没人通知，流程就在那儿干等着
-- #####################################################################

-- =====================================================================
--  第三十九部分：交接规则 dept_handoff_rule（工程管理/管理员维护）
--    一张表定义"什么事发生了 → 从哪个部门交到哪个部门 → 通知谁"
--    以后加节点只加一行数据，不改代码
-- =====================================================================
CREATE TABLE dept_handoff_rule (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_key    text UNIQUE NOT NULL,             -- 事件标识
    event_label  text NOT NULL,                    -- 中文说明
    from_dept    text CHECK (from_dept IN
                   ('presales','eng_mgmt','procurement','warehouse','finance','maintenance')),
    to_dept      text NOT NULL CHECK (to_dept IN
                   ('presales','eng_mgmt','procurement','warehouse','finance','maintenance','all')),
    action_needed text NOT NULL,                   -- 对方要做什么
    channel      text NOT NULL DEFAULT 'sms' CHECK (channel IN ('sms','email','both')),
    sla_hours    integer,                          -- 多少小时内该响应，超了进催办
    active       boolean NOT NULL DEFAULT true,
    note         text
);

INSERT INTO dept_handoff_rule(event_key,event_label,from_dept,to_dept,action_needed,sla_hours) VALUES
 ('presale_signed',   '售前第六步客户签字',     'presales','finance',    '开 S1 定金 Invoice 并跟进收款', 24),
 ('s1_settled',       'S1 定金已结清',          'finance','eng_mgmt',   '安排 SM1 进场',                 24),
 ('sm3_done',         'SM3 检查布线完成',       'eng_mgmt','finance',   '开 S2 物料款 Invoice',          24),
 ('s2_settled',       'S2 物料款已结清',        'finance','procurement','可以下单采购',                  24),
 ('s2_settled_wh',    'S2 物料款已结清',        'finance','warehouse',  '准备收货与出库',                48),
 ('po_arrived',       '采购到货入库',           'warehouse','eng_mgmt', '安排工程预配',                  48),
 ('stock_released',   '物料已出库',             'warehouse','eng_mgmt', '现场核对收货',                  24),
 ('sm4_done',         'SM4 封板核对完成',       'eng_mgmt','finance',   '开 S3 人工款 Invoice',          24),
 ('install_done',     '安装调试整体完工',       'eng_mgmt','finance',   '准备 S4 尾款（先结算未退料）',  24),
 ('unreturned_ready', '有未退料待结算',         'warehouse','finance',  '结算未退料并计入 S4 变更',      48),
 ('variation_logged', 'SM3 登记了变更',         'eng_mgmt','finance',   '安排变更估价',                  48),
 ('s4_settled',       'S4 尾款已结清',          'finance','eng_mgmt',   '可以安排交付',                  24),
 ('handover_done',    '项目交付完成',           'eng_mgmt','maintenance','接管运维，启动免责维保',       24),
 ('maint_visit_done', '维护上门服务完成',       'maintenance','finance','按现场归因与工时定价开票',      24),
 ('stocktake_pending','盘点待审批',             'warehouse','eng_mgmt', '复核并审批盘亏',                24),
 ('rma_to_supplier',  'RMA 需返供应商',         'warehouse','procurement','联系供应商索赔或换修',        72),
 ('payment_dispute',  '客户拒付·项目停服',      'finance','all',        '全面停服，暂停一切新任务',       4),
 ('reorder_alert',    '库存低于红线',           'warehouse','procurement','纳入下次集中采购',            72);

-- =====================================================================
--  第四十部分：交接实例 dept_handoff（谁交给谁、通知了没、响应了没）
-- =====================================================================
CREATE TABLE dept_handoff (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid REFERENCES project(id) ON DELETE CASCADE,
    event_key     text NOT NULL REFERENCES dept_handoff_rule(event_key),
    ref_kind      text,                            -- 关联单据类型
    ref_id        uuid,
    from_dept     text,
    to_dept       text NOT NULL,
    message       text,
    raised_at     timestamptz NOT NULL DEFAULT now(),
    -- 对方响应（有人点了"已知悉"或实际做了下一步）
    acknowledged_at timestamptz,
    acknowledged_by uuid REFERENCES app_account(id),
    closed_at     timestamptz,                     -- 下一步实际完成
    note          text
);
CREATE INDEX idx_handoff_pending ON dept_handoff(to_dept, acknowledged_at) WHERE closed_at IS NULL;
CREATE INDEX idx_handoff_project ON dept_handoff(project_id);


-- =====================================================================
--  ★ 通用通知函数：一处实现，所有交接点共用
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_notify_dept(
    p_event_key text,
    p_project_id uuid,
    p_ref_kind text DEFAULT NULL,
    p_ref_id uuid DEFAULT NULL,
    p_extra text DEFAULT NULL
) RETURNS uuid AS $$
DECLARE r dept_handoff_rule%ROWTYPE; pcode text; hid uuid;
        body text; acct record; n int := 0;
BEGIN
    SELECT * INTO r FROM dept_handoff_rule WHERE event_key = p_event_key AND active;
    IF r.id IS NULL THEN RETURN NULL; END IF;      -- 规则被停用则静默跳过

    SELECT code INTO pcode FROM project WHERE id = p_project_id;

    body := '【KONNEXT】' || COALESCE('项目 '||pcode||'：', '')
         || r.event_label || E'\n'
         || '→ 请' || CASE r.to_dept
              WHEN 'presales' THEN '售前' WHEN 'eng_mgmt' THEN '工程管理'
              WHEN 'procurement' THEN '采购' WHEN 'warehouse' THEN '库管'
              WHEN 'finance' THEN '财务' WHEN 'maintenance' THEN '运维'
              ELSE '各部门' END
         || '：' || r.action_needed
         || COALESCE(E'\n' || p_extra, '')
         || CASE WHEN r.sla_hours IS NOT NULL
                 THEN E'\n建议 ' || r.sla_hours || ' 小时内处理。' ELSE '' END;

    -- 注：这份 fn_notify_dept 在后面被重定义（按 dept_handoff_rule.default_scope 定 scope），
    --     真正生效的是那一份，改动请改那边
    INSERT INTO dept_handoff(project_id, event_key, ref_kind, ref_id,
                             from_dept, to_dept, message)
    VALUES (p_project_id, p_event_key, p_ref_kind, p_ref_id,
            r.from_dept, r.to_dept, body)
    RETURNING id INTO hid;

    -- 发给目标部门的所有在职账号（全部 = 所有 tier2）
    FOR acct IN
        SELECT a.id, a.phone, a.email, a.full_name
          FROM app_account a
         WHERE a.active AND a.tier = 2
           AND (r.to_dept = 'all'
                OR EXISTS(SELECT 1 FROM account_department d
                           WHERE d.account_id = a.id AND d.department = r.to_dept))
    LOOP
        IF r.channel IN ('sms','both') AND acct.phone IS NOT NULL THEN
            INSERT INTO notification(project_id, ref_kind, ref_id, channel, recipient,
                                     subject, body, status, triggered_by)
            VALUES (p_project_id, 'dept_handoff', hid, 'sms', acct.phone,
                    r.event_label, body, 'queued',
                    COALESCE(current_setting('app.actor', true),'system'));
            n := n + 1;
        END IF;
        IF r.channel IN ('email','both') AND acct.email IS NOT NULL THEN
            INSERT INTO notification(project_id, ref_kind, ref_id, channel, recipient,
                                     subject, body, status, triggered_by)
            VALUES (p_project_id, 'dept_handoff', hid, 'email', acct.email,
                    '【KONNEXT】' || r.event_label, body, 'queued',
                    COALESCE(current_setting('app.actor', true),'system'));
            n := n + 1;
        END IF;
    END LOOP;

    INSERT INTO handoff_log(project_id, from_party, to_party, node, message)
    VALUES (p_project_id, r.from_dept, r.to_dept, p_event_key,
            r.event_label || ' → ' || r.action_needed || '（已通知 ' || n || ' 人）');
    RETURN hid;
END;
$$ LANGUAGE plpgsql;


-- =====================================================================
--  各交接点挂钩（只加新触发器，不改已有门禁逻辑）
-- =====================================================================

-- 售前签字 / 状态推进
CREATE OR REPLACE FUNCTION trg_notify_project() RETURNS trigger AS $$
BEGIN
    IF NEW.step6_signed_at IS NOT NULL
       AND (TG_OP='INSERT' OR OLD.step6_signed_at IS NULL) THEN
        PERFORM fn_notify_dept('presale_signed', NEW.id, 'project', NEW.id, NULL);
    END IF;
    IF NEW.install_completed_at IS NOT NULL
       AND (TG_OP='UPDATE' AND OLD.install_completed_at IS NULL) THEN
        PERFORM fn_notify_dept('install_done', NEW.id, 'project', NEW.id, NULL);
    END IF;
    IF NEW.handover_at IS NOT NULL AND (TG_OP='UPDATE' AND OLD.handover_at IS NULL) THEN
        PERFORM fn_notify_dept('handover_done', NEW.id, 'project', NEW.id,
            '免责维保 ' || NEW.free_warranty_months || ' 个月自今日起算');
    END IF;
    IF NEW.service_suspended_at IS NOT NULL
       AND (TG_OP='UPDATE' AND OLD.service_suspended_at IS NULL) THEN
        PERFORM fn_notify_dept('payment_dispute', NEW.id, 'project', NEW.id,
            '原因：' || COALESCE(NEW.service_suspended_reason,'未填'));
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER notify_project AFTER INSERT OR UPDATE ON project
    FOR EACH ROW EXECUTE FUNCTION trg_notify_project();

-- 付款节点结清
CREATE OR REPLACE FUNCTION trg_notify_payment() RETURNS trigger AS $$
BEGIN
    IF NEW.status='settled' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM 'settled')
       AND NEW.kind='contract' THEN
        IF NEW.stage='S1' THEN
            PERFORM fn_notify_dept('s1_settled', NEW.project_id, 'payment', NEW.id, NULL);
        ELSIF NEW.stage='S2' THEN
            PERFORM fn_notify_dept('s2_settled', NEW.project_id, 'payment', NEW.id, NULL);
            PERFORM fn_notify_dept('s2_settled_wh', NEW.project_id, 'payment', NEW.id, NULL);
        ELSIF NEW.stage='S4' THEN
            PERFORM fn_notify_dept('s4_settled', NEW.project_id, 'payment', NEW.id, NULL);
        END IF;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER notify_payment AFTER INSERT OR UPDATE ON payment_milestone
    FOR EACH ROW EXECUTE FUNCTION trg_notify_payment();

-- SM3 / SM4 完成
CREATE OR REPLACE FUNCTION trg_notify_sm() RETURNS trigger AS $$
BEGIN
    IF NEW.completed_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.completed_at IS NULL) THEN
        IF NEW.sm_no = 3 THEN
            PERFORM fn_notify_dept('sm3_done', NEW.project_id, 'site_meeting', NEW.id, NULL);
        ELSIF NEW.sm_no = 4 THEN
            PERFORM fn_notify_dept('sm4_done', NEW.project_id, 'site_meeting', NEW.id, NULL);
        END IF;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER notify_sm AFTER INSERT OR UPDATE ON site_meeting
    FOR EACH ROW EXECUTE FUNCTION trg_notify_sm();

-- 变更登记
CREATE OR REPLACE FUNCTION trg_notify_variation() RETURNS trigger AS $$
BEGIN
    IF TG_OP='INSERT' AND NEW.origin='sm3' THEN
        PERFORM fn_notify_dept('variation_logged', NEW.project_id, 'variation', NEW.id,
            '类型：' || NEW.change_type || '｜' || COALESCE(NEW.description,''));
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER notify_variation AFTER INSERT ON variation
    FOR EACH ROW EXECUTE FUNCTION trg_notify_variation();

-- 采购到货
CREATE OR REPLACE FUNCTION trg_notify_po() RETURNS trigger AS $$
BEGIN
    IF NEW.status='arrived' AND OLD.status IS DISTINCT FROM 'arrived'
       AND NEW.source_type <> 'opening' THEN
        PERFORM fn_notify_dept('po_arrived', NEW.ref_project_id, 'purchase_order', NEW.id,
            '采购单 ' || NEW.po_no || '（' || COALESCE(NEW.supplier,'') || '）已到货');
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER notify_po AFTER UPDATE ON purchase_order
    FOR EACH ROW EXECUTE FUNCTION trg_notify_po();

-- 出库
CREATE OR REPLACE FUNCTION trg_notify_out() RETURNS trigger AS $$
BEGIN
    PERFORM fn_notify_dept('stock_released', NEW.project_id, 'stock_out', NEW.id,
        '提货人：' || COALESCE(NEW.receiver_name,'') || '｜出库单 ' || NEW.out_no);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER notify_out AFTER INSERT ON stock_out
    FOR EACH ROW EXECUTE FUNCTION trg_notify_out();

-- 盘点待审批
CREATE OR REPLACE FUNCTION trg_notify_stocktake() RETURNS trigger AS $$
BEGIN
    IF NEW.status='pending_approval' AND OLD.status IS DISTINCT FROM 'pending_approval' THEN
        PERFORM fn_notify_dept('stocktake_pending', NULL, 'stocktake', NEW.id,
            '盘点单 ' || NEW.take_no || '，盘点人 ' || COALESCE(NEW.counted_by,''));
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER notify_stocktake AFTER UPDATE ON stocktake
    FOR EACH ROW EXECUTE FUNCTION trg_notify_stocktake();

-- RMA 返供应商
CREATE OR REPLACE FUNCTION trg_notify_rma() RETURNS trigger AS $$
BEGIN
    IF NEW.disposition='to_supplier' AND OLD.disposition IS DISTINCT FROM 'to_supplier' THEN
        PERFORM fn_notify_dept('rma_to_supplier', NEW.project_id, 'rma_case', NEW.id,
            'RMA 单 ' || NEW.rma_no || '，归因 ' || COALESCE(NEW.damage_cause,''));
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER notify_rma AFTER UPDATE ON rma_case
    FOR EACH ROW EXECUTE FUNCTION trg_notify_rma();

-- 维护上门完成
CREATE OR REPLACE FUNCTION trg_notify_maint() RETURNS trigger AS $$
BEGIN
    IF NEW.completed_at IS NOT NULL AND (TG_OP='INSERT' OR OLD.completed_at IS NULL) THEN
        PERFORM fn_notify_dept('maint_visit_done', NEW.project_id, 'maintenance_job', NEW.id,
            '归因：' || COALESCE(NEW.fault_cause,'') || '｜' || COALESCE(NEW.service_summary,''));
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER notify_maint AFTER INSERT OR UPDATE ON maintenance_job
    FOR EACH ROW EXECUTE FUNCTION trg_notify_maint();


-- =====================================================================
--  v0.23 视图
-- =====================================================================

-- 57 ★待办与催办：谁在等谁、等了多久、超没超 SLA
CREATE VIEW v_pending_handoff AS
SELECT h.id, p.code AS project_code, h.event_key, r.event_label,
       CASE h.from_dept WHEN 'presales' THEN '售前' WHEN 'eng_mgmt' THEN '工程管理'
            WHEN 'procurement' THEN '采购' WHEN 'warehouse' THEN '库管'
            WHEN 'finance' THEN '财务' WHEN 'maintenance' THEN '运维' END AS from_dept_cn,
       CASE h.to_dept WHEN 'presales' THEN '售前' WHEN 'eng_mgmt' THEN '工程管理'
            WHEN 'procurement' THEN '采购' WHEN 'warehouse' THEN '库管'
            WHEN 'finance' THEN '财务' WHEN 'maintenance' THEN '运维'
            ELSE '全部门' END                                      AS to_dept_cn,
       r.action_needed, r.sla_hours,
       h.raised_at,
       round(EXTRACT(EPOCH FROM (now() - h.raised_at))/3600.0, 1)  AS waiting_hours,
       h.acknowledged_at, a.full_name AS acknowledged_by_name,
       (h.acknowledged_at IS NULL)                                 AS unacknowledged,
       (r.sla_hours IS NOT NULL AND h.acknowledged_at IS NULL
        AND EXTRACT(EPOCH FROM (now() - h.raised_at))/3600.0 > r.sla_hours) AS overdue,
       (SELECT count(*) FROM notification n
         WHERE n.ref_kind='dept_handoff' AND n.ref_id = h.id)      AS notified_count
  FROM dept_handoff h
  JOIN dept_handoff_rule r ON r.event_key = h.event_key
  LEFT JOIN project p ON p.id = h.project_id
  LEFT JOIN app_account a ON a.id = h.acknowledged_by
 WHERE h.closed_at IS NULL;

-- 58 各部门待办量与超期量（管理层看板）
CREATE VIEW v_dept_workload AS
SELECT to_dept_cn AS 部门,
       count(*)                            AS 待办总数,
       count(*) FILTER (WHERE unacknowledged) AS 未响应,
       count(*) FILTER (WHERE overdue)        AS 已超期,
       round(max(waiting_hours),1)            AS 最久等待小时
  FROM v_pending_handoff
 GROUP BY to_dept_cn;

-- 59 交接通知发放明细（发给谁、发出没）
CREATE VIEW v_handoff_notifications AS
SELECT h.id AS handoff_id, r.event_label, h.to_dept, p.code AS project_code,
       n.channel, n.recipient, n.status, n.sent_at, n.body
  FROM dept_handoff h
  JOIN dept_handoff_rule r ON r.event_key=h.event_key
  LEFT JOIN project p ON p.id=h.project_id
  LEFT JOIN notification n ON n.ref_kind='dept_handoff' AND n.ref_id=h.id;


-- #####################################################################
-- ##  v0.24：行级权限 RLS —— 读全部、写本部门、敏感数字分开管
-- #####################################################################

-- =====================================================================
--  数据库角色（仅供 DBA/运维直连时使用）
--  ★ 应用运行时只用一个数据库用户，登录后 SET app.account_id 指明是谁；
--    权限完全由【账号 + 部门表】决定，不依赖数据库角色。
-- =====================================================================
DO $$
BEGIN
  PERFORM 1;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='konnext_admin')       THEN CREATE ROLE konnext_admin; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='konnext_presales')    THEN CREATE ROLE konnext_presales; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='konnext_eng_mgmt')    THEN CREATE ROLE konnext_eng_mgmt; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='konnext_procurement') THEN CREATE ROLE konnext_procurement; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='konnext_warehouse')   THEN CREATE ROLE konnext_warehouse; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='konnext_finance')     THEN CREATE ROLE konnext_finance; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='konnext_maintenance') THEN CREATE ROLE konnext_maintenance; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='konnext_field')       THEN CREATE ROLE konnext_field; END IF;
END $$;

-- =====================================================================
--  当前登录人（应用层 SET app.account_id）
-- =====================================================================
-- ⚠️ 权限判定函数必须 SECURITY DEFINER：
--    否则 fn_me() 查 app_account → 触发该表 RLS 策略 → 策略又调 fn_me() → 无限递归
CREATE OR REPLACE FUNCTION fn_me() RETURNS app_account AS $$
    SELECT * FROM app_account
     WHERE id = NULLIF(current_setting('app.account_id', true),'')::uuid
       AND active;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ⚠️ 绝不能在 SECURITY DEFINER 函数里用 pg_has_role(current_user,...)：
--    SECURITY DEFINER 里 current_user 会变成函数所有者(postgres)，而它是超级用户，
--    于是每个人都被判成管理员 —— 不报错，只是权限全放开。
--    权限一律以【账号 app.account_id + 部门表】为准。
CREATE OR REPLACE FUNCTION fn_is_admin() RETURNS boolean AS $$
    SELECT COALESCE((SELECT tier = 1 FROM fn_me()), false);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 是否属于某部门（管理员视为属于所有部门）
CREATE OR REPLACE FUNCTION fn_has_dept(p_dept text) RETURNS boolean AS $$
    SELECT fn_is_admin()
        OR EXISTS(SELECT 1 FROM account_department d
                   WHERE d.account_id = (SELECT id FROM fn_me())
                     AND d.department = p_dept);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 第三级：施工人员（只上报，不进后台）
CREATE OR REPLACE FUNCTION fn_is_field() RETURNS boolean AS $$
    SELECT COALESCE((SELECT tier = 3 FROM fn_me()), true);   -- 未登录也当最低权限
$$ LANGUAGE sql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION fn_my_staff_id() RETURNS uuid AS $$
    SELECT staff_id FROM fn_me();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ★ 三类敏感数字，各自谁能看
CREATE OR REPLACE FUNCTION fn_can_see_salary() RETURNS boolean AS $$
    SELECT fn_is_admin() OR fn_has_dept('finance');
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_can_see_margin() RETURNS boolean AS $$
    SELECT fn_is_admin() OR fn_has_dept('finance');
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_can_see_purchase_price() RETURNS boolean AS $$
    SELECT fn_is_admin() OR fn_has_dept('procurement');
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION fn_can_see_salary IS
  '薪酬可见范围：财务+管理层。要放开给工程管理，在此加 OR fn_has_dept(''eng_mgmt'')';


-- =====================================================================
--  第四十一部分：表的写入归属 table_ownership（声明式，也是文档）
-- =====================================================================
CREATE TABLE table_ownership (
    table_name  text PRIMARY KEY,
    write_dept  text[] NOT NULL,      -- 哪些部门可写
    note        text
);
INSERT INTO table_ownership(table_name, write_dept, note) VALUES
 ('project',            ARRAY['presales','finance','eng_mgmt'], '售前建档；财务写定金与状态；工程写交付相关'),
 ('household_member',   ARRAY['presales'],      NULL),
 ('project_party',      ARRAY['presales','eng_mgmt'], 'SM1 采集分包商也写这里'),
 ('solution_option',    ARRAY['presales'],      NULL),
 ('site_meeting',       ARRAY['eng_mgmt'],      NULL),
 ('sm_template',        ARRAY['eng_mgmt'],      NULL),
 ('job_checklist',      ARRAY['eng_mgmt','maintenance'], NULL),
 ('install_item',       ARRAY['eng_mgmt'],      NULL),
 ('install_job',        ARRAY['eng_mgmt'],      NULL),
 ('handover_job',       ARRAY['eng_mgmt'],      NULL),
 ('delivery_review',    ARRAY['eng_mgmt'],      NULL),
 ('variation',          ARRAY['eng_mgmt','finance'], 'SM3 登记归工程；估价金额归财务'),
 ('maintenance_case',   ARRAY['maintenance','finance'], '运维建单；财务定价开票'),
 ('maintenance_job',    ARRAY['maintenance'],   NULL),
 ('payment_milestone',  ARRAY['finance'],       NULL),
 ('payment_receipt',    ARRAY['finance'],       NULL),
 ('payment_remind_log', ARRAY['finance'],       'v0.33 催款记录：财务发出并留痕'),
 ('material',           ARRAY['procurement'],   NULL),
 ('fx_rate',            ARRAY['procurement','finance'], NULL),
 ('purchase_order',     ARRAY['procurement'],   NULL),
 ('purchase_order_line',ARRAY['procurement','warehouse'], '采购下单；库管填到货数'),
 ('stock_out',          ARRAY['warehouse'],     NULL),
 ('stock_out_line',     ARRAY['warehouse'],     NULL),
 ('stock_return',       ARRAY['warehouse'],     NULL),
 ('stock_return_line',  ARRAY['warehouse'],     NULL),
 ('rma_case',           ARRAY['warehouse','procurement'], '库管登记；采购跟供应商索赔'),
 ('stocktake',          ARRAY['warehouse','eng_mgmt'], '库管盘点；工程管理审批（不能自批）'),
 ('stocktake_line',     ARRAY['warehouse'],     NULL),
 ('eng_staff',          ARRAY['eng_mgmt','finance'], '工程管理建人；财务管薪酬字段'),
 ('daily_payroll',      ARRAY['eng_mgmt'],      '★v0.34 补录=工程负责人写、财务只读；定格由系统定时任务落'),
 ('payroll_month',      ARRAY['finance'],       NULL),
 ('toil_ledger',        ARRAY['finance','eng_mgmt'], '加班自动累计；调休由工程管理登记'),
 ('termination_settlement', ARRAY['finance'],   NULL),
 ('document',           ARRAY['eng_mgmt'],      NULL),
 ('document_version',   ARRAY['eng_mgmt'],      NULL),
 ('document_binding',   ARRAY['eng_mgmt'],      NULL),
 ('document_issue',     ARRAY['eng_mgmt','maintenance','warehouse'], '谁发的谁记'),
 ('eng_setting',        ARRAY['eng_mgmt'],      NULL),
 ('public_holiday',     ARRAY['eng_mgmt'],      NULL);

CREATE OR REPLACE FUNCTION fn_can_write(p_table text) RETURNS boolean AS $$
    SELECT fn_is_admin() OR EXISTS(
        SELECT 1 FROM table_ownership o, unnest(o.write_dept) AS d
         WHERE o.table_name = p_table AND fn_has_dept(d));
$$ LANGUAGE sql STABLE SECURITY DEFINER;


-- =====================================================================
--  RLS 策略：读全部、写本部门
--  施工人员(tier3)例外——只能碰跟自己有关的行
-- =====================================================================
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'project','household_member','project_party','solution_option',
    'site_meeting','install_item','install_job','handover_job','delivery_review',
    'variation','maintenance_case','maintenance_job',
    'payment_milestone','payment_receipt','payment_remind_log',
    'material','purchase_order','purchase_order_line',
    'stock_out','stock_out_line','stock_return','stock_return_line',
    'rma_case','stocktake','stocktake_line',
    'document','document_version','document_binding','document_issue']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    -- ★ 读：六个部门全流程互相可见（施工人员不给后台读）
    EXECUTE format($f$
      CREATE POLICY %1$s_read ON %1$I FOR SELECT
        USING (NOT fn_is_field() OR fn_is_admin())$f$, t);
    -- ★ 写：只能写本部门归属的表
    EXECUTE format($f$
      CREATE POLICY %1$s_ins ON %1$I FOR INSERT
        WITH CHECK (fn_can_write(%1$L))$f$, t);
    EXECUTE format($f$
      CREATE POLICY %1$s_upd ON %1$I FOR UPDATE
        USING (fn_can_write(%1$L)) WITH CHECK (fn_can_write(%1$L))$f$, t);
    EXECUTE format($f$
      CREATE POLICY %1$s_del ON %1$I FOR DELETE
        USING (fn_is_admin())$f$, t);
  END LOOP;
END $$;

-- =====================================================================
--  v0.31 ★补缺口：eng_setting / eng_staff 此前只在 table_ownership 登记，
--  没有启用 RLS —— 写权限全靠前端藏按钮，违背「业务逻辑全在数据库」。
--  eng_setting 按 write_depts 逐键判写；eng_staff 套通用模板(eng_mgmt+finance)
-- =====================================================================
ALTER TABLE eng_setting ENABLE ROW LEVEL SECURITY;
CREATE POLICY eng_setting_read ON eng_setting FOR SELECT
    USING (NOT fn_is_field() OR fn_is_admin());
CREATE POLICY eng_setting_ins ON eng_setting FOR INSERT
    WITH CHECK (fn_is_admin());                 -- 新增设置键只有决策管理员
CREATE POLICY eng_setting_upd ON eng_setting FOR UPDATE
    USING (fn_is_admin() OR EXISTS (
        SELECT 1 FROM account_department ad
         WHERE ad.account_id = (fn_me()).id
           AND ad.department = ANY (eng_setting.write_depts)))
    WITH CHECK (fn_is_admin() OR EXISTS (
        SELECT 1 FROM account_department ad
         WHERE ad.account_id = (fn_me()).id
           AND ad.department = ANY (eng_setting.write_depts)));
CREATE POLICY eng_setting_del ON eng_setting FOR DELETE
    USING (fn_is_admin());

-- 门禁：write_depts 本身只有决策管理员能改（防止部门给自己扩权）
CREATE OR REPLACE FUNCTION trg_setting_depts_guard() RETURNS trigger AS $$
BEGIN
    IF NEW.write_depts IS DISTINCT FROM OLD.write_depts AND NOT fn_is_admin() THEN
        RAISE EXCEPTION '门禁：设置项的写权限归属(write_depts)只有决策管理员能改';
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER setting_depts_guard BEFORE UPDATE ON eng_setting
    FOR EACH ROW EXECUTE FUNCTION trg_setting_depts_guard();

ALTER TABLE eng_staff ENABLE ROW LEVEL SECURITY;
CREATE POLICY eng_staff_read ON eng_staff FOR SELECT
    USING (NOT fn_is_field() OR fn_is_admin());
CREATE POLICY eng_staff_ins ON eng_staff FOR INSERT
    WITH CHECK (fn_can_write('eng_staff'));
CREATE POLICY eng_staff_upd ON eng_staff FOR UPDATE
    USING (fn_can_write('eng_staff')) WITH CHECK (fn_can_write('eng_staff'));
CREATE POLICY eng_staff_del ON eng_staff FOR DELETE
    USING (fn_is_admin());

-- ★ 薪酬类：只有财务与管理层能读
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['daily_payroll','payroll_month','toil_ledger','termination_settlement']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format($f$
      CREATE POLICY %1$s_read ON %1$I FOR SELECT
        USING (fn_can_see_salary()
               OR (fn_is_field() AND staff_id = fn_my_staff_id()))$f$, t);
    EXECUTE format($f$
      CREATE POLICY %1$s_write ON %1$I FOR ALL
        USING (fn_can_write(%1$L)) WITH CHECK (fn_can_write(%1$L))$f$, t);
  END LOOP;
END $$;
COMMENT ON TABLE daily_payroll IS
  '当夜0点定格，一旦落库不改。★薪酬敏感：仅财务与管理层可读；施工人员只能看自己那几行';

-- ★ 施工人员：只能看/写跟自己有关的任务与工时
ALTER TABLE work_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY work_log_read ON work_log FOR SELECT
  USING (NOT fn_is_field() OR staff_id = fn_my_staff_id());
CREATE POLICY work_log_ins ON work_log FOR INSERT
  WITH CHECK (fn_is_admin() OR fn_has_dept('eng_mgmt') OR fn_has_dept('maintenance')
              OR (fn_is_field() AND staff_id = fn_my_staff_id()));
CREATE POLICY work_log_upd ON work_log FOR UPDATE
  USING (fn_is_admin() OR fn_has_dept('eng_mgmt')
         OR (fn_is_field() AND staff_id = fn_my_staff_id()));

ALTER TABLE daily_report ENABLE ROW LEVEL SECURITY;
CREATE POLICY daily_report_read ON daily_report FOR SELECT
  USING (NOT fn_is_field() OR staff_id = fn_my_staff_id());
CREATE POLICY daily_report_write ON daily_report FOR ALL
  USING (fn_is_admin() OR fn_has_dept('eng_mgmt')
         OR (fn_is_field() AND staff_id = fn_my_staff_id()))
  WITH CHECK (fn_is_admin() OR fn_has_dept('eng_mgmt')
         OR (fn_is_field() AND staff_id = fn_my_staff_id()));

ALTER TABLE daily_issue ENABLE ROW LEVEL SECURITY;
CREATE POLICY daily_issue_all ON daily_issue FOR ALL
  USING (NOT fn_is_field()
         OR EXISTS(SELECT 1 FROM daily_report r
                    WHERE r.id = report_id AND r.staff_id = fn_my_staff_id()))
  WITH CHECK (NOT fn_is_field()
         OR EXISTS(SELECT 1 FROM daily_report r
                    WHERE r.id = report_id AND r.staff_id = fn_my_staff_id()));

-- ★ 账号表：只有管理员能改；本人可看自己
ALTER TABLE app_account ENABLE ROW LEVEL SECURITY;
CREATE POLICY acct_read ON app_account FOR SELECT
  USING (fn_is_admin() OR NOT fn_is_field() OR id = (SELECT id FROM fn_me()));
CREATE POLICY acct_write ON app_account FOR ALL
  USING (fn_is_admin() OR fn_has_dept('eng_mgmt'))
  WITH CHECK (fn_is_admin() OR fn_has_dept('eng_mgmt'));


-- =====================================================================
--  ★ 敏感字段遮罩视图（RLS 管行，遮罩管列）
-- =====================================================================

-- 60 人员（薪酬字段按权限遮罩）
CREATE VIEW v_staff_masked AS
SELECT s.id, s.name, s.role, s.phone, s.pay_type, s.hired_at, s.terminated_at, s.active,
       CASE WHEN fn_can_see_salary() THEN s.monthly_salary   END AS monthly_salary,
       CASE WHEN fn_can_see_salary() THEN s.pay_hourly_rate  END AS pay_hourly_rate,
       CASE WHEN fn_can_see_salary() THEN s.daily_rate       END AS daily_rate,
       CASE WHEN fn_can_see_salary() THEN s.cost_hourly_rate END AS cost_hourly_rate,
       CASE WHEN fn_can_see_salary() THEN s.ref_minutes      END AS ref_minutes,
       fn_can_see_salary() AS salary_visible
  FROM eng_staff s;

-- 61 物料（采购价与毛利率按权限遮罩；库管仍能看名称与库存）
CREATE VIEW v_material_masked AS
SELECT m.id, m.code, m.category, m.protocol, m.display_name, m.internal_name, m.spec,
       m.supplier_model, m.supplier, m.purchase_class, m.reorder_point,
       m.warranty_months, m.active,
       CASE WHEN fn_can_see_purchase_price() THEN m.price_cny   END AS price_cny,
       CASE WHEN fn_can_see_purchase_price() THEN m.price_usd   END AS price_usd,
       CASE WHEN fn_can_see_purchase_price() THEN m.price_aud   END AS price_aud,
       CASE WHEN fn_can_see_purchase_price() THEN m.freight_aud END AS freight_aud,
       CASE WHEN fn_can_see_purchase_price() THEN m.margin_pct  END AS margin_pct,
       fn_can_see_purchase_price() AS price_visible
  FROM material m;

-- 62 项目（利润率按权限遮罩；业务流水人人可见）
CREATE VIEW v_project_masked AS
SELECT p.id, p.code, p.name, p.status, p.build_stage,
       p.addr_street, p.addr_suburb, p.addr_state,
       p.step1_intro_at, p.step2_design_at, p.step3_review_at, p.step4_draft_at,
       p.step5_revise_at, p.step6_signed_at, p.step7_deposit_at,
       p.install_completed_at, p.handover_at, p.free_warranty_months,
       CASE WHEN fn_can_see_margin() THEN p.contract_price      END AS contract_price,
       CASE WHEN fn_can_see_margin() THEN p.eng_margin_locked   END AS eng_margin_locked,
       CASE WHEN fn_can_see_margin() THEN p.planned_labor_hours END AS planned_labor_hours,
       fn_can_see_margin() AS margin_visible
  FROM project p;

-- 63 我能写哪些表（界面据此显示/隐藏按钮）
CREATE VIEW v_my_permissions AS
SELECT o.table_name, o.write_dept, fn_can_write(o.table_name) AS can_write, o.note
  FROM table_ownership o;

-- 64 权限矩阵（给管理员看的全景）
CREATE VIEW v_permission_matrix AS
SELECT o.table_name,
       ('售前='   || CASE WHEN 'presales'    = ANY(o.write_dept) THEN '写' ELSE '读' END ||
        '｜工程管理=' || CASE WHEN 'eng_mgmt' = ANY(o.write_dept) THEN '写' ELSE '读' END ||
        '｜采购='  || CASE WHEN 'procurement' = ANY(o.write_dept) THEN '写' ELSE '读' END ||
        '｜库管='  || CASE WHEN 'warehouse'   = ANY(o.write_dept) THEN '写' ELSE '读' END ||
        '｜财务='  || CASE WHEN 'finance'     = ANY(o.write_dept) THEN '写' ELSE '读' END ||
        '｜运维='  || CASE WHEN 'maintenance' = ANY(o.write_dept) THEN '写' ELSE '读' END) AS matrix,
       o.note
  FROM table_ownership o ORDER BY o.table_name;


-- #####################################################################
-- ##  v0.25：数字不互相可见 —— 补两个大洞
-- ##   洞①：66 个视图全部按【视图所有者】执行，RLS 整个被绕过
-- ##   洞②：金额只在三个遮罩视图里挡了，其余视图与表本身全敞开
-- #####################################################################

-- =====================================================================
--  洞① 修复：所有视图改为按【查询者】权限执行，RLS 才生效
--  ⚠️ PostgreSQL 视图默认 security_invoker=false（按所有者执行）。
--     只做 RLS 不改这个，等于给所有视图开了后门。PG 15+ 支持此选项。
-- =====================================================================
DO $$
DECLARE v record;
BEGIN
  FOR v IN SELECT c.relname FROM pg_class c
            WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
  LOOP
    EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', v.relname);
  END LOOP;
END $$;

-- =====================================================================
--  洞② 修复：金额分五类，各归各管
-- =====================================================================

-- 客户合同金额：签约价、S1~S4 应收实收、变更金额、维护开票
CREATE OR REPLACE FUNCTION fn_can_see_customer_amount() RETURNS boolean AS $$
    SELECT fn_is_admin() OR fn_has_dept('finance') OR fn_has_dept('presales');
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- 库存成本单价：出入库单价、盘点金额、RMA 费用
CREATE OR REPLACE FUNCTION fn_can_see_stock_cost() RETURNS boolean AS $$
    SELECT fn_is_admin() OR fn_has_dept('finance')
        OR fn_has_dept('procurement') OR fn_has_dept('warehouse');
$$ LANGUAGE sql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fn_can_see_customer_amount IS '客户合同金额：财务+售前+管理层。售前要看是因为签约价是他填的';
COMMENT ON FUNCTION fn_can_see_stock_cost IS '库存成本单价：库管+采购+财务+管理层';

-- 五类金额可见性一览（谁能看什么钱，一张表说清）
CREATE TABLE money_visibility (
    bucket      text PRIMARY KEY,
    bucket_cn   text NOT NULL,
    guard_fn    text NOT NULL,
    visible_to  text NOT NULL,
    examples    text NOT NULL
);
INSERT INTO money_visibility VALUES
 ('salary','薪酬','fn_can_see_salary','财务＋管理层',
  '时薪/月薪/日薪/日结工资/月工资单/倒休余额/离职清算'),
 ('margin','成本与利润率','fn_can_see_margin','财务＋管理层',
  '项目人工成本/物料成本/工程利润率/长期利润率/人工消耗%'),
 ('purchase_price','采购价与毛利率','fn_can_see_purchase_price','采购＋管理层',
  '三币种采购价/运费/毛利率/售卖价/调价历史'),
 ('customer_amount','客户合同金额','fn_can_see_customer_amount','财务＋售前＋管理层',
  '签约价/S1~S4应收实收/变更结算/未退料折算/维护开票/超期账龄'),
 ('stock_cost','库存成本单价','fn_can_see_stock_cost','库管＋采购＋财务＋管理层',
  '出入库单价/盘点盈亏金额/RMA修理费与运费');


-- =====================================================================
--  重建带金额的视图：金额一律按类遮罩，业务流水照旧全可见
-- =====================================================================

-- 采购价与售卖价
CREATE OR REPLACE VIEW v_material_price AS
SELECT m.id, m.code, m.category, m.protocol, m.internal_name, m.display_name, m.supplier_model,
       m.supplier, m.spec, m.purchase_class, m.reorder_point,
       CASE WHEN fn_can_see_purchase_price() THEN m.price_cny END::numeric(12,2) AS price_cny,
       CASE WHEN fn_can_see_purchase_price() THEN m.price_usd END::numeric(12,2) AS price_usd,
       CASE WHEN fn_can_see_purchase_price() THEN m.price_aud END::numeric(12,2) AS price_aud,
       CASE WHEN fn_can_see_purchase_price() THEN m.freight_aud END::numeric(12,2) AS freight_aud,
       CASE WHEN fn_can_see_purchase_price() THEN m.margin_pct END::numeric(5,4) AS margin_pct,
       CASE WHEN fn_can_see_purchase_price() THEN fc.rate_to_aud END::numeric(12,6) AS rate_cny,
       CASE WHEN fn_can_see_purchase_price() THEN fu.rate_to_aud END::numeric(12,6) AS rate_usd,
       CASE WHEN fn_can_see_purchase_price() THEN
         round(COALESCE(m.price_cny,0)*COALESCE(fc.rate_to_aud,0)
             + COALESCE(m.price_usd,0)*COALESCE(fu.rate_to_aud,0)
             + COALESCE(m.price_aud,0), 2) END AS cost_converted_aud,
       CASE WHEN fn_can_see_purchase_price() THEN
         round(COALESCE(m.price_cny,0)*COALESCE(fc.rate_to_aud,0)
             + COALESCE(m.price_usd,0)*COALESCE(fu.rate_to_aud,0)
             + COALESCE(m.price_aud,0) + m.freight_aud, 2) END AS cost_total_aud,
       -- 售卖价：采购或财务/售前都可能要（对客户报价）
       CASE WHEN fn_can_see_purchase_price() OR fn_can_see_customer_amount() THEN
         CASE WHEN m.margin_pct IS NOT NULL AND m.margin_pct < 1
              THEN round((COALESCE(m.price_cny,0)*COALESCE(fc.rate_to_aud,0)
                        + COALESCE(m.price_usd,0)*COALESCE(fu.rate_to_aud,0)
                        + COALESCE(m.price_aud,0) + m.freight_aud)
                        / (1 - m.margin_pct), 2) END END AS sell_price_aud,
       GREATEST(COALESCE(fc.days_stale,0), COALESCE(fu.days_stale,0)) AS fx_days_stale,
       (COALESCE(fc.is_stale,false) OR COALESCE(fu.is_stale,false))   AS fx_stale,
       m.warranty_months, m.active, m.updated_by, m.updated_at
  FROM material m
  LEFT JOIN v_fx_current fc ON fc.currency='CNY'
  LEFT JOIN v_fx_current fu ON fu.currency='USD';

-- 调价历史
CREATE OR REPLACE VIEW v_material_price_history AS
SELECT a.at, a.actor, a.before->>'code' AS code, a.before->>'internal_name' AS internal_name,
       CASE WHEN fn_can_see_purchase_price() THEN (a.before->>'price_cny')::numeric END AS old_cny,
       CASE WHEN fn_can_see_purchase_price() THEN (a.after ->>'price_cny')::numeric END AS new_cny,
       CASE WHEN fn_can_see_purchase_price() THEN (a.before->>'price_usd')::numeric END AS old_usd,
       CASE WHEN fn_can_see_purchase_price() THEN (a.after ->>'price_usd')::numeric END AS new_usd,
       CASE WHEN fn_can_see_purchase_price() THEN (a.before->>'price_aud')::numeric END AS old_aud,
       CASE WHEN fn_can_see_purchase_price() THEN (a.after ->>'price_aud')::numeric END AS new_aud,
       CASE WHEN fn_can_see_purchase_price() THEN (a.before->>'margin_pct')::numeric END AS old_margin,
       CASE WHEN fn_can_see_purchase_price() THEN (a.after ->>'margin_pct')::numeric END AS new_margin
  FROM audit_log a
 WHERE a.table_name='material' AND a.action='UPDATE'
   AND (a.before->>'price_cny'  IS DISTINCT FROM a.after->>'price_cny'
     OR a.before->>'price_usd'  IS DISTINCT FROM a.after->>'price_usd'
     OR a.before->>'price_aud'  IS DISTINCT FROM a.after->>'price_aud'
     OR a.before->>'margin_pct' IS DISTINCT FROM a.after->>'margin_pct');

-- 应收 vs 实收
CREATE OR REPLACE VIEW v_milestone_settlement AS
SELECT m.id AS milestone_id, m.project_id, m.kind, m.stage, m.case_id,
       CASE WHEN fn_can_see_customer_amount() THEN m.amount_due END::numeric(14,2) AS amount_due,
       m.status, m.invoice_no, m.invoice_ver,
       CASE WHEN fn_can_see_customer_amount() THEN COALESCE(r.got,0) END::numeric AS received,
       CASE WHEN fn_can_see_customer_amount() THEN COALESCE(r.got_bank,0) END AS received_bank,
       CASE WHEN fn_can_see_customer_amount() THEN COALESCE(r.got_cash,0) END AS received_cash,
       CASE WHEN fn_can_see_customer_amount() THEN COALESCE(r.gst,0) END      AS received_gst,
       CASE WHEN fn_can_see_customer_amount()
            THEN round(COALESCE(m.amount_due,0)-COALESCE(r.got,0),2) END      AS outstanding,
       CASE WHEN fn_can_see_customer_amount() THEN m.shortfall_amount END::numeric(14,2) AS shortfall_amount,
       m.settle_reason, m.settled_at, m.settled_by
  FROM payment_milestone m
  LEFT JOIN (SELECT milestone_id, SUM(amount) got, SUM(gst_amount) gst,
                    SUM(CASE WHEN method='bank' THEN amount ELSE 0 END) got_bank,
                    SUM(CASE WHEN method='cash' THEN amount ELSE 0 END) got_cash
               FROM payment_receipt GROUP BY milestone_id) r ON r.milestone_id=m.id;

-- 项目人工成本
CREATE OR REPLACE VIEW v_project_labor_cost AS
WITH onsite AS (
    SELECT w.project_id,
           SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0) AS h,
           SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0*s.cost_hourly_rate) AS c
      FROM work_log w JOIN eng_staff s ON s.id=w.staff_id
     WHERE w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL
     GROUP BY w.project_id
), lunch AS (
    SELECT charged_project_id AS project_id, SUM(lunch_min)/60.0 AS h,
           SUM(lunch_min/60.0*s.cost_hourly_rate) AS c
      FROM v_daily_lunch l JOIN eng_staff s ON s.id=l.staff_id
     WHERE charged_project_id IS NOT NULL GROUP BY charged_project_id
), travel AS (
    SELECT t.to_project_id AS project_id, SUM(t.travel_min/60.0) AS h,
           SUM(t.travel_min/60.0*s.cost_hourly_rate) AS c
      FROM v_travel_slot t JOIN eng_staff s ON s.id=t.staff_id
     GROUP BY t.to_project_id
)
SELECT p.id AS project_id,
       round(COALESCE(o.h,0)::numeric,2)  AS onsite_hours,
       round(COALESCE(tr.h,0)::numeric,2) AS travel_hours,
       round(COALESCE(lu.h,0)::numeric,2) AS lunch_hours,
       round((COALESCE(o.h,0)+COALESCE(tr.h,0)-COALESCE(lu.h,0))::numeric,2) AS actual_hours,
       CASE WHEN fn_can_see_margin() THEN round(COALESCE(o.c,0)::numeric,2)  END AS onsite_cost,
       CASE WHEN fn_can_see_margin() THEN round(COALESCE(tr.c,0)::numeric,2) END AS travel_cost,
       CASE WHEN fn_can_see_margin() THEN round(COALESCE(lu.c,0)::numeric,2) END AS lunch_deduct,
       CASE WHEN fn_can_see_margin()
            THEN round((COALESCE(o.c,0)+COALESCE(tr.c,0)-COALESCE(lu.c,0))::numeric,2) END AS labor_cost
  FROM project p
  LEFT JOIN onsite o ON o.project_id=p.id
  LEFT JOIN travel tr ON tr.project_id=p.id
  LEFT JOIN lunch lu ON lu.project_id=p.id;

-- 人员维度流水（工时可见，成本遮罩）
CREATE OR REPLACE VIEW v_project_staff_effort AS
SELECT w.project_id, p.code AS project_code, w.staff_id, s.name AS staff_name,
       COUNT(*) AS visit_count,
       MIN(w.checkin_at)::date AS first_day, MAX(w.checkout_at)::date AS last_day,
       round(SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0)::numeric,2) AS total_hours,
       CASE WHEN fn_can_see_margin() THEN
         round(SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0*s.cost_hourly_rate)::numeric,2)
       END AS labor_cost,
       SUM(CASE WHEN w.work_type='sm' THEN 1 ELSE 0 END)          AS sm_visits,
       SUM(CASE WHEN w.work_type='execution' THEN 1 ELSE 0 END)   AS install_visits,
       SUM(CASE WHEN w.work_type='handover' THEN 1 ELSE 0 END)    AS handover_visits,
       SUM(CASE WHEN w.work_type='maintenance' THEN 1 ELSE 0 END) AS maint_visits,
       SUM(CASE WHEN w.checkin_flagged THEN 1 ELSE 0 END)         AS flagged_checkins
  FROM work_log w
  JOIN project p ON p.id=w.project_id
  LEFT JOIN eng_staff s ON s.id=w.staff_id
 WHERE w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL
 GROUP BY w.project_id, p.code, w.staff_id, s.name;

-- 项目物料成本
CREATE OR REPLACE VIEW v_project_material_cost AS
SELECT so.project_id, p.code AS project_code,
       COUNT(DISTINCT so.id) AS out_count,
       CASE WHEN fn_can_see_margin()
            THEN round(SUM(ol.qty * COALESCE(ol.unit_cost_aud,0)), 2) END AS material_cost_aud,
       COUNT(*) FILTER (WHERE so.status='released') AS pending_confirm,
       COUNT(*) FILTER (WHERE so.status='received') AS confirmed
  FROM stock_out_line ol
  JOIN stock_out so ON so.id=ol.stock_out_id
  JOIN project p ON p.id=so.project_id
 GROUP BY so.project_id, p.code;

-- 未退料折算
CREATE OR REPLACE VIEW v_unreturned_to_variation AS
SELECT c.project_id, c.project_code, c.holder, c.is_external,
       c.display_name, c.qty_unreturned,
       CASE WHEN fn_can_see_customer_amount() THEN mp.sell_price_aud END::numeric AS sell_price_aud,
       CASE WHEN fn_can_see_customer_amount()
            THEN round(c.qty_unreturned * COALESCE(mp.sell_price_aud,0), 2) END AS variation_amount,
       (SELECT invoice_sent_at FROM payment_milestone
         WHERE project_id=c.project_id AND kind='contract' AND stage='S4') AS s4_invoiced_at
  FROM v_material_custody c
  LEFT JOIN v_material_price mp ON mp.id = c.material_id
 WHERE c.qty_unreturned > 0;

-- 盘点结果与汇总
CREATE OR REPLACE VIEW v_stocktake_result AS
SELECT st.take_no, st.scope, st.scope_note, st.status,
       st.counted_by, st.approved_by, st.completed_at::date AS completed_on,
       m.code, m.display_name,
       sl.system_qty AS 账面, sl.counted_qty AS 实点, sl.diff_qty AS 差额,
       CASE WHEN fn_can_see_stock_cost()
            THEN round(sl.diff_qty * COALESCE(sl.unit_cost_aud,0), 2) END AS diff_amount_aud,
       sl.reason
  FROM stocktake_line sl
  JOIN stocktake st ON st.id = sl.stocktake_id
  JOIN material m ON m.id = sl.material_id;

-- RMA 台账（费用遮罩）
CREATE OR REPLACE VIEW v_rma_board AS
SELECT r.rma_no, p.code AS project_code, r.project_id,
       m.display_name, r.qty, r.reporter_name, r.returned_at::date AS returned_on,
       r.packaging_complete, r.accessories_missing, r.damage_cause, r.disposition,
       m.supplier, m.warranty_months,
       s2.settled_at::date AS s2_settled_on,
       (now()::date - r.returned_at::date) AS rma_days,
       (now()::date - s2.settled_at::date) AS warranty_days_elapsed,
       (s2.settled_at + (m.warranty_months || ' months')::interval)::date AS warranty_until,
       (s2.settled_at IS NOT NULL AND m.warranty_months IS NOT NULL
        AND now() < s2.settled_at + (m.warranty_months || ' months')::interval) AS in_warranty,
       r.supplier_sent_at, r.supplier_received, r.supplier_returned,
       CASE WHEN fn_can_see_stock_cost() THEN r.repair_fee_aud END::numeric(12,2) AS repair_fee_aud,
       CASE WHEN fn_can_see_stock_cost() THEN r.freight_fee_aud END::numeric(12,2) AS freight_fee_aud,
       CASE WHEN fn_can_see_stock_cost()
            THEN (r.repair_fee_aud + r.freight_fee_aud) END::numeric AS rma_cost_aud,
       r.cost_bucket, r.purged_by, r.purged_at
  FROM rma_case r
  JOIN project p ON p.id = r.project_id
  JOIN material m ON m.id = r.material_id
  LEFT JOIN payment_milestone s2
         ON s2.project_id = r.project_id AND s2.kind='contract' AND s2.stage='S2';

-- 维护开票依据（工时属成本口径）
CREATE OR REPLACE VIEW v_maintenance_estimate_accuracy AS
SELECT c.id AS case_id, p.code AS project_code, c.title,
       CASE WHEN fn_can_see_customer_amount() THEN c.estimate_amount END::numeric(14,2) AS estimate_amount,
       c.estimated_by, c.estimated_at,
       CASE WHEN fn_can_see_customer_amount() THEN m.amount_due END::numeric(14,2) AS invoiced_amount,
       m.invoice_no,
       CASE WHEN fn_can_see_customer_amount() THEN (m.amount_due - c.estimate_amount) END AS diff,
       CASE WHEN fn_can_see_customer_amount() AND c.estimate_amount > 0
            THEN round((m.amount_due - c.estimate_amount) / c.estimate_amount * 100, 1) END AS diff_pct,
       c.fault_cause, c.is_free_warranty
  FROM maintenance_case c
  JOIN project p ON p.id = c.project_id
  LEFT JOIN payment_milestone m
         ON m.case_id = c.id AND m.kind='maintenance' AND m.invoice_sent_at IS NOT NULL
 WHERE c.estimate_amount IS NOT NULL;

-- 外包实付 vs 摊入（属薪酬）
CREATE OR REPLACE VIEW v_contractor_cost_gap AS
SELECT d.staff_id, s.name, d.work_date,
       CASE WHEN fn_can_see_salary() THEN d.pay_rate_snap END::numeric(10,2) AS daily_paid,
       CASE WHEN fn_can_see_salary() THEN d.cost_rate_snap END::numeric(10,2) AS cost_rate,
       round(d.paid_min/60.0, 2)                               AS onsite_hours,
       CASE WHEN fn_can_see_salary()
            THEN round(d.paid_min/60.0 * d.cost_rate_snap, 2) END AS charged_to_projects,
       CASE WHEN fn_can_see_salary()
            THEN round(d.pay_rate_snap - d.paid_min/60.0 * d.cost_rate_snap, 2) END AS gap
  FROM daily_payroll d JOIN eng_staff s ON s.id = d.staff_id
 WHERE d.pay_type_snap = 'contractor' AND d.paid_min > 0;

-- 65 视图金额守卫对照表（自查：每个带钱的视图由哪个函数看守）
CREATE VIEW v_money_guard_map AS
SELECT * FROM (VALUES
 ('v_material_price',                'purchase_price / customer_amount'),
 ('v_material_price_history',        'purchase_price'),
 ('v_material_masked',               'purchase_price'),
 ('v_milestone_settlement',          'customer_amount'),
 ('v_overdue',                       'customer_amount（继承 v_milestone_settlement）'),
 ('v_s4_settlement',                 'customer_amount'),
 ('v_s4_line_items',                 'customer_amount'),
 ('v_variation_settlement',          'customer_amount'),
 ('v_unreturned_to_variation',       'customer_amount'),
 ('v_maintenance_estimate_accuracy', 'customer_amount'),
 ('v_project_masked',                'margin'),
 ('v_project_labor_cost',            'margin'),
 ('v_labor_consumption',             'margin（继承 v_project_labor_cost）'),
 ('v_project_material_cost',         'margin'),
 ('v_project_staff_effort',          'margin'),
 ('v_long_term_margin',              'margin'),
 ('v_staff_masked',                  'salary'),
 ('v_contractor_cost_gap',           'salary'),
 ('v_overtime_summary',              'salary（仅时长，按薪酬管）'),
 ('v_toil_balance',                  'salary（仅时长，按薪酬管）'),
 ('v_stocktake_result',              'stock_cost'),
 ('v_stocktake_summary',             'stock_cost'),
 ('v_rma_board',                     'stock_cost'),
 ('v_rma_cost',                      'stock_cost'),
 ('v_maintenance_billing_basis',     'margin（工时）')
) AS t(view_name, guarded_by);

-- 继承类：本身不含原始金额，但会带出上游遮罩后的值，需重建以吃到 security_invoker
CREATE OR REPLACE VIEW v_labor_consumption AS
SELECT p.id AS project_id, p.code, 
       CASE WHEN fn_can_see_margin() THEN p.planned_labor_hours END::numeric(10,2) AS planned_labor_hours,
       lc.onsite_hours, lc.travel_hours, lc.actual_hours,
       CASE WHEN fn_can_see_margin() AND p.planned_labor_hours > 0
            THEN round((lc.actual_hours / p.planned_labor_hours * 100)::numeric, 1) END AS consumption_pct
  FROM project p LEFT JOIN v_project_labor_cost lc ON lc.project_id = p.id;

CREATE OR REPLACE VIEW v_long_term_margin AS
WITH mrev AS (
    SELECT m.project_id, SUM(COALESCE(r.got,0)) AS maint_revenue
      FROM payment_milestone m
      LEFT JOIN (SELECT milestone_id, SUM(amount) got FROM payment_receipt GROUP BY milestone_id) r
             ON r.milestone_id=m.id
     WHERE m.kind='maintenance' GROUP BY m.project_id
), mcost AS (
    SELECT project_id,
           SUM(COALESCE(labor_cost,0))    AS maint_labor,
           SUM(COALESCE(material_cost,0)) AS maint_material,
           SUM(CASE WHEN is_free_warranty THEN COALESCE(labor_cost,0)+COALESCE(material_cost,0)
                    ELSE 0 END)           AS free_warranty_cost
      FROM maintenance_case GROUP BY project_id
)
SELECT p.id AS project_id, p.code,
       CASE WHEN fn_can_see_margin() THEN p.contract_price END::numeric(14,2) AS contract_price,
       CASE WHEN fn_can_see_margin() THEN p.eng_margin_locked END::numeric(6,3) AS eng_margin_locked,
       CASE WHEN fn_can_see_margin()
            THEN round(COALESCE(p.contract_price,0)*COALESCE(p.eng_margin_locked,0)/100,2) END AS eng_profit,
       CASE WHEN fn_can_see_margin() THEN COALESCE(mr.maint_revenue,0) END  AS maint_revenue,
       CASE WHEN fn_can_see_margin() THEN COALESCE(mc.maint_labor,0) END    AS maint_labor,
       CASE WHEN fn_can_see_margin() THEN COALESCE(mc.maint_material,0) END AS maint_material,
       CASE WHEN fn_can_see_margin() THEN COALESCE(mc.free_warranty_cost,0) END AS free_warranty_cost,
       CASE WHEN fn_can_see_margin()
            THEN round(COALESCE(p.contract_price,0)*COALESCE(p.eng_margin_locked,0)/100
                     + COALESCE(mr.maint_revenue,0) - COALESCE(mc.maint_labor,0)
                     - COALESCE(mc.maint_material,0), 2) END AS long_term_profit
  FROM project p
  LEFT JOIN mrev mr ON mr.project_id=p.id
  LEFT JOIN mcost mc ON mc.project_id=p.id;

-- 新建的视图也要开 security_invoker
DO $$
DECLARE v record;
BEGIN
  FOR v IN SELECT c.relname FROM pg_class c
            WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
              AND (c.reloptions IS NULL OR NOT ('security_invoker=true' = ANY(c.reloptions)))
  LOOP
    EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', v.relname);
  END LOOP;
END $$;

-- 补齐：S4 结算 / 变更台账 / 超期 / 盘点汇总 / RMA成本 / 维护依据 / 倒休 / 加班
CREATE OR REPLACE VIEW v_s4_settlement AS
WITH base AS (
    SELECT p.id AS project_id, p.code, p.name, p.contract_price,
           COALESCE((SELECT ratio_pct FROM payment_milestone
                      WHERE project_id=p.id AND kind='contract' AND stage='S4'),10) AS s4_ratio
      FROM project p
), var AS (
    SELECT project_id,
           COALESCE(SUM(settle_amount) FILTER (WHERE billable),0)                    AS var_total,
           COALESCE(SUM(settle_amount) FILTER (WHERE billable AND settle_amount>0),0) AS var_add,
           COALESCE(SUM(settle_amount) FILTER (WHERE billable AND settle_amount<0),0) AS var_less,
           count(*)                                                                  AS var_count,
           count(*) FILTER (WHERE NOT billable)                                       AS var_nonbillable,
           count(*) FILTER (WHERE billable AND settle_amount IS NULL)                 AS var_unpriced
      FROM variation GROUP BY project_id
), unset AS (
    SELECT u.project_id,
           GREATEST(COALESCE(u.amt,0) - COALESCE(v.settled,0), 0) AS pending_unreturned
      FROM (SELECT project_id, SUM(qty_unreturned * COALESCE(
                    (SELECT CASE WHEN m.margin_pct IS NOT NULL AND m.margin_pct < 1
                       THEN round((COALESCE(m.price_cny,0)*COALESCE((SELECT rate_to_aud FROM v_fx_current WHERE currency='CNY'),0)
                                 + COALESCE(m.price_usd,0)*COALESCE((SELECT rate_to_aud FROM v_fx_current WHERE currency='USD'),0)
                                 + COALESCE(m.price_aud,0) + m.freight_aud)/(1-m.margin_pct),2) END
                       FROM material m WHERE m.id = c.material_id),0)) AS amt
              FROM v_material_custody c WHERE c.qty_unreturned > 0 GROUP BY project_id) u
      LEFT JOIN (SELECT project_id, SUM(settle_amount) settled
                   FROM variation WHERE origin='unreturned' GROUP BY project_id) v
             ON v.project_id = u.project_id
), paid AS (
    SELECT m.project_id,
           COALESCE(SUM(r.amount) FILTER (WHERE m.stage IN ('S1','S2','S3')),0) AS prior_received
      FROM payment_milestone m LEFT JOIN payment_receipt r ON r.milestone_id=m.id
     WHERE m.kind='contract' GROUP BY m.project_id
)
SELECT b.project_id, b.code, b.name,
       CASE WHEN fn_can_see_customer_amount() THEN b.contract_price END::numeric(14,2) AS contract_price,
       CASE WHEN fn_can_see_customer_amount() THEN round(b.contract_price*b.s4_ratio/100,2) END AS s4_base,
       CASE WHEN fn_can_see_customer_amount() THEN COALESCE(v.var_add,0) END   AS variation_add,
       CASE WHEN fn_can_see_customer_amount() THEN COALESCE(v.var_less,0) END  AS variation_less,
       CASE WHEN fn_can_see_customer_amount() THEN COALESCE(v.var_total,0) END AS variation_net,
       COALESCE(v.var_unpriced,0)     AS unpriced_count,
       COALESCE(v.var_nonbillable,0)  AS nonbillable_count,
       CASE WHEN fn_can_see_customer_amount() THEN COALESCE(u.pending_unreturned,0) END AS pending_unreturned,
       CASE WHEN fn_can_see_customer_amount()
            THEN round(b.contract_price*b.s4_ratio/100 + COALESCE(v.var_total,0),2) END AS s4_payable,
       CASE WHEN fn_can_see_customer_amount() THEN COALESCE(p.prior_received,0) END AS prior_received,
       (COALESCE(u.pending_unreturned,0) > 0) AS need_settle_unreturned
  FROM base b
  LEFT JOIN var v ON v.project_id=b.project_id
  LEFT JOIN unset u ON u.project_id=b.project_id
  LEFT JOIN paid p ON p.project_id=b.project_id;

CREATE OR REPLACE VIEW v_s4_line_items AS
SELECT p.id AS project_id, p.code AS project_code, 1 AS sort_no, true AS billable,
       '合同尾款'::text AS item_type,
       ('S4 尾款（签约价 ' || CASE WHEN fn_can_see_customer_amount()
              THEN p.contract_price::text ELSE '***' END || ' × ' ||
         COALESCE((SELECT ratio_pct FROM payment_milestone
                    WHERE project_id=p.id AND kind='contract' AND stage='S4'),10) || '%）')::text AS description,
       CASE WHEN fn_can_see_customer_amount() THEN
         round(p.contract_price * COALESCE((SELECT ratio_pct FROM payment_milestone
              WHERE project_id=p.id AND kind='contract' AND stage='S4'),10)/100,2) END AS amount_aud,
       '签约合同'::text AS source_ref, NULL::timestamptz AS logged_at,
       NULL::text AS logged_by, NULL::text AS basis
  FROM project p
UNION ALL
SELECT v.project_id, p.code, 2, v.billable,
       CASE v.change_type WHEN 'add' THEN
              CASE WHEN v.origin='unreturned' THEN '未退料' ELSE '变更·增加' END
            WHEN 'remove' THEN '变更·减少'
            ELSE '移位（电工整改·不计费）' END,
       v.description,
       CASE WHEN fn_can_see_customer_amount() THEN v.settle_amount END,
       CASE v.origin WHEN 'sm3' THEN 'SM3 变更登记'
                     WHEN 'unreturned' THEN '出库单 / 退库记录'
                     ELSE v.origin END || COALESCE(' / '||v.settle_ext_ref,''),
       v.created_at, COALESCE(s.name, v.settle_by), v.settle_note
  FROM variation v
  JOIN project p ON p.id=v.project_id
  LEFT JOIN eng_staff s ON s.id=v.logged_by;

CREATE OR REPLACE VIEW v_variation_settlement AS
SELECT v.project_id, p.code AS project_code,
       count(*) AS total_count,
       count(*) FILTER (WHERE v.settle_amount IS NOT NULL) AS priced_count,
       count(*) FILTER (WHERE v.settle_amount IS NULL)     AS unpriced_count,
       CASE WHEN fn_can_see_customer_amount() THEN COALESCE(SUM(v.settle_amount),0) END AS settle_total,
       SUM(CASE WHEN v.change_type='add'    THEN 1 ELSE 0 END) AS add_count,
       SUM(CASE WHEN v.change_type='remove' THEN 1 ELSE 0 END) AS remove_count,
       SUM(CASE WHEN v.change_type='move'   THEN 1 ELSE 0 END) AS move_count,
       CASE WHEN fn_can_see_customer_amount() THEN p.contract_price END::numeric(14,2) AS contract_price,
       CASE WHEN fn_can_see_customer_amount()
            THEN round(COALESCE(p.contract_price,0)*0.10 + COALESCE(SUM(v.settle_amount),0), 2) END AS s4_expected,
       (SELECT invoice_sent_at FROM payment_milestone
         WHERE project_id=v.project_id AND kind='contract' AND stage='S4') AS s4_invoiced_at
  FROM variation v JOIN project p ON p.id=v.project_id
 GROUP BY v.project_id, p.code, p.contract_price;

CREATE OR REPLACE VIEW v_stocktake_summary AS
SELECT st.id, st.take_no, st.scope, st.status, st.counted_by, st.approved_by,
       count(*) AS line_count,
       count(*) FILTER (WHERE sl.diff_qty <> 0) AS diff_count,
       count(*) FILTER (WHERE sl.diff_qty < 0)  AS loss_count,
       count(*) FILTER (WHERE sl.diff_qty > 0)  AS gain_count,
       CASE WHEN fn_can_see_stock_cost() THEN
         round(SUM(CASE WHEN sl.diff_qty < 0
                        THEN -sl.diff_qty * COALESCE(sl.unit_cost_aud,0) ELSE 0 END),2) END AS loss_amount_aud,
       CASE WHEN fn_can_see_stock_cost() THEN
         round(SUM(CASE WHEN sl.diff_qty > 0
                        THEN sl.diff_qty * COALESCE(sl.unit_cost_aud,0) ELSE 0 END),2) END AS gain_amount_aud,
       (SELECT value_num FROM eng_setting WHERE key='stocktake_approve_amount_aud') AS approve_threshold,
       (round(SUM(CASE WHEN sl.diff_qty < 0
                      THEN -sl.diff_qty * COALESCE(sl.unit_cost_aud,0) ELSE 0 END),2)
        > (SELECT value_num FROM eng_setting WHERE key='stocktake_approve_amount_aud')) AS needs_approval
  FROM stocktake st LEFT JOIN stocktake_line sl ON sl.stocktake_id = st.id
 GROUP BY st.id, st.take_no, st.scope, st.status, st.counted_by, st.approved_by;

CREATE OR REPLACE VIEW v_rma_cost AS
SELECT project_id, cost_bucket, count(*) AS case_count,
       CASE WHEN fn_can_see_stock_cost() THEN round(SUM(repair_fee_aud),2) END  AS repair_fee_total,
       CASE WHEN fn_can_see_stock_cost() THEN round(SUM(freight_fee_aud),2) END AS freight_fee_total,
       CASE WHEN fn_can_see_stock_cost()
            THEN round(SUM(repair_fee_aud + freight_fee_aud),2) END             AS rma_cost_total
  FROM rma_case GROUP BY project_id, cost_bucket;

CREATE OR REPLACE VIEW v_toil_balance AS
SELECT s.id AS staff_id, s.name, s.pay_type,
       CASE WHEN fn_can_see_salary() THEN round(COALESCE(SUM(t.minutes),0),1) END AS balance_min,
       CASE WHEN fn_can_see_salary() THEN round(COALESCE(SUM(t.minutes),0)/60.0,2) END AS balance_hours,
       CASE WHEN fn_can_see_salary() THEN
         round(COALESCE(SUM(CASE WHEN t.entry_type='accrue' THEN t.minutes END),0)/60.0,2) END AS accrued_hours,
       CASE WHEN fn_can_see_salary() THEN
         round(COALESCE(SUM(CASE WHEN t.entry_type='take' THEN -t.minutes END),0)/60.0,2) END AS taken_hours
  FROM eng_staff s LEFT JOIN toil_ledger t ON t.staff_id=s.id
 GROUP BY s.id, s.name, s.pay_type;

CREATE OR REPLACE VIEW v_overtime_summary AS
SELECT d.staff_id, s.name, s.pay_type,
       date_trunc('month', d.work_date)::date AS month,
       CASE WHEN fn_can_see_salary() THEN round(SUM(d.ot_min) FILTER (WHERE d.day_type='weekday')/60.0,2) END  AS ot_weekday_h,
       CASE WHEN fn_can_see_salary() THEN round(SUM(d.ot_min) FILTER (WHERE d.day_type='saturday')/60.0,2) END AS ot_saturday_h,
       CASE WHEN fn_can_see_salary() THEN round(SUM(d.ot_min) FILTER (WHERE d.day_type='sunday')/60.0,2) END   AS ot_sunday_h,
       CASE WHEN fn_can_see_salary() THEN round(SUM(d.ot_min) FILTER (WHERE d.day_type='holiday')/60.0,2) END  AS ot_holiday_h,
       CASE WHEN fn_can_see_salary() THEN round(SUM(d.ot_min)/60.0,2) END                                     AS ot_total_h
  FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id
 WHERE d.status IN ('locked','released')
 GROUP BY d.staff_id, s.name, s.pay_type, date_trunc('month', d.work_date);

DO $$
DECLARE v record;
BEGIN
  FOR v IN SELECT c.relname FROM pg_class c
            WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
              AND (c.reloptions IS NULL OR NOT ('security_invoker=true' = ANY(c.reloptions)))
  LOOP EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', v.relname); END LOOP;
END $$;


-- #####################################################################
-- ##  v0.26：不变量断言
-- ##
-- ##  门禁测试问的是"该拦的拦住了吗"；断言问的是"没被拦住的，算对了吗"。
-- ##  这一路真正危险的四个 bug（退库不进库存、未退料不进发票、
-- ##  视图绕过 RLS、SECURITY DEFINER 提权）门禁测试一个都没抓到——
-- ##  全是"不报错、只是数字错了"，全靠有人恰好去看那一眼。
-- ##  断言就是把"该有人看那一眼"变成自动的。
-- ##
-- ##  用法：SELECT * FROM fn_run_assertions();        -- 全跑一遍
-- ##        SELECT * FROM fn_assertion_detail('代码'); -- 看是哪几行违规
-- #####################################################################

CREATE TABLE assertion_def (
    code      text PRIMARY KEY,
    label     text NOT NULL,
    severity  text NOT NULL CHECK (severity IN ('critical','high','medium')),
    query     text NOT NULL,      -- 返回【违规行】的 SELECT；返回空 = 通过
    hint      text,               -- 违规了怎么查
    active    boolean NOT NULL DEFAULT true
);
COMMENT ON TABLE assertion_def IS '声明式断言：加一条断言只加一行数据，不改代码';

INSERT INTO assertion_def(code,label,severity,query,hint) VALUES

-- ══════════ 库存 ══════════
('INV-STOCK-01','库存不得为负','critical',
 $q$SELECT code, display_name, qty_on_hand FROM v_material_stock WHERE qty_on_hand < 0$q$,
 '出库/退库/盘点某处算错，或出库门禁被绕过'),
('INV-STOCK-02','到货数不得超过下单数','critical',
 $q$SELECT l.id, m.display_name, l.qty_ordered, l.qty_arrived
      FROM purchase_order_line l JOIN material m ON m.id=l.material_id
     WHERE l.qty_arrived > l.qty_ordered$q$,
 '虚假入库，或收货录错'),
('INV-STOCK-03','退库不得超过该人名下未退量','critical',
 $q$SELECT project_code, holder, display_name, qty_unreturned
      FROM v_material_custody WHERE qty_unreturned < 0$q$,
 '重复退库，或退库门禁被绕过'),
('INV-STOCK-04','每个物料最多一次期初移库','critical',
 $q$SELECT m.code, m.display_name, count(*) AS opening_rows
      FROM purchase_order_line l
      JOIN purchase_order po ON po.id=l.po_id
      JOIN material m ON m.id=l.material_id
     WHERE po.source_type='opening'
     GROUP BY m.code, m.display_name HAVING count(*)>1$q$,
 '期初做了两遍 → 库存凭空翻倍'),
('INV-STOCK-05','出库必须有提货人手机号','high',
 $q$SELECT out_no, project_id, receiver_name FROM stock_out
     WHERE receiver_phone IS NULL OR btrim(receiver_phone)=''$q$,
 '发不出提货清单短信'),
('INV-STOCK-06','C1 必须有红线，C2 必须没有','high',
 $q$SELECT code, display_name, purchase_class, reorder_point FROM material
     WHERE (purchase_class='C2' AND reorder_point IS NOT NULL)
        OR (purchase_class='C1' AND reorder_point IS NULL)$q$,
 'C2 严格不设红线'),
('INV-STOCK-07','已划掉的物料不得再有新出库','high',
 $q$SELECT m.code, m.display_name, so.out_no, so.released_at
      FROM material m
      JOIN stock_out_line ol ON ol.material_id=m.id
      JOIN stock_out so ON so.id=ol.stock_out_id
     WHERE NOT m.active AND m.archived_at IS NOT NULL AND so.released_at > m.archived_at$q$,
 '划掉门禁被绕过'),

-- ══════════ 财务 ══════════
('INV-FIN-01','S4 首版发票金额 = 签约价×比例 + Σ可计费变更','critical',
 $q$SELECT m.invoice_no, m.amount_due AS 发票金额,
          round(p.contract_price*m.ratio_pct/100,2)
        + COALESCE((SELECT SUM(v.settle_amount) FROM variation v
                     WHERE v.project_id=p.id AND v.billable),0) AS 应为
      FROM payment_milestone m JOIN project p ON p.id=m.project_id
     WHERE m.kind='contract' AND m.stage='S4' AND m.invoice_sent_at IS NOT NULL
       AND m.invoice_ver = 1
       AND m.amount_due <> round(p.contract_price*m.ratio_pct/100,2)
         + COALESCE((SELECT SUM(v.settle_amount) FROM variation v
                      WHERE v.project_id=p.id AND v.billable),0)$q$,
 '变更漏估、未退料没结算，或发票金额被人工改过却没升版本'),
('INV-FIN-02','已结清：Σ收款 + 批准差额 ≥ 应收','critical',
 $q$SELECT m.id, m.kind, m.stage, m.amount_due,
          COALESCE((SELECT SUM(amount) FROM payment_receipt WHERE milestone_id=m.id),0) AS 已收,
          m.shortfall_amount AS 批准差额
      FROM payment_milestone m
     WHERE m.status='settled'
       AND COALESCE((SELECT SUM(amount) FROM payment_receipt WHERE milestone_id=m.id),0)
         + COALESCE(m.shortfall_amount,0) < COALESCE(m.amount_due,0) - 0.005$q$,
 '钱没收够却标了结清，且没登记差额'),
('INV-FIN-03','移位变更不得有金额','critical',
 $q$SELECT id, description, settle_amount FROM variation
     WHERE change_type='move' AND COALESCE(settle_amount,0) <> 0$q$,
 '移位属电工整改，不向客户计费'),
('INV-FIN-04','标记已结算的变更必须有金额','high',
 $q$SELECT id, description FROM variation
     WHERE settle_status='settled_s4' AND settle_amount IS NULL AND billable$q$,
 NULL),
('INV-FIN-05','维护单只能存在于已交付项目','critical',
 $q$SELECT c.id, c.title, p.code, p.status FROM maintenance_case c
      JOIN project p ON p.id=c.project_id WHERE p.handover_at IS NULL$q$,
 '交付前的问题应走安装剩余项或变更'),
('INV-FIN-06','应收单 kind 与 stage/case_id 必须匹配','high',
 $q$SELECT id, kind, stage, case_id FROM payment_milestone
     WHERE (kind='contract'    AND (stage IS NULL     OR case_id IS NOT NULL))
        OR (kind='maintenance' AND (stage IS NOT NULL OR case_id IS NULL))$q$,
 NULL),
('INV-FIN-07','已交付项目必须定格工程利润率','high',
 $q$SELECT code, handover_at FROM project
     WHERE handover_at IS NOT NULL AND eng_margin_locked IS NULL$q$,
 '交付触发器没跑到，或利润率算不出来（签约价为空？）'),
('INV-FIN-08','现金收款默认不计 GST','medium',
 $q$SELECT id, milestone_id, amount, gst_amount FROM payment_receipt
     WHERE method='cash' AND gst_amount > 0$q$,
 '现金按约定不计 GST；如确需计，请确认税务处理'),
('INV-FIN-09','变更金额填了必须留下是谁填的','high',
 $q$SELECT id, description FROM variation
     WHERE settle_amount IS NOT NULL AND (settle_by IS NULL OR settle_at IS NULL)$q$,
 '这笔钱直接叠进 S4 跟客户结账，必须可追溯'),

-- ══════════ 工资 ══════════
('INV-PAY-01','付薪时长 = 首尾 − 午餐','critical',
 $q$SELECT d.id, s.name, d.work_date, d.span_min, d.lunch_min, d.paid_min
      FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id
     WHERE round(d.paid_min,1) <> round(d.span_min - d.lunch_min,1)$q$,
 '日结定格算错'),
('INV-PAY-02','正常工时 + 加班 = 付薪时长','critical',
 $q$SELECT d.id, s.name, d.work_date, d.normal_min, d.ot_min, d.paid_min
      FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id
     WHERE round(d.normal_min + d.ot_min,1) <> round(d.paid_min,1)$q$,
 NULL),
('INV-PAY-03','周末与公共假日整天算加班','high',
 $q$SELECT d.id, s.name, d.work_date, d.day_type, d.ot_min, d.paid_min
      FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id
     WHERE d.day_type <> 'weekday' AND d.pay_type_snap <> 'contractor'
       AND round(d.ot_min,1) <> round(d.paid_min,1)$q$,
 NULL),
('INV-PAY-04','外包没有加班概念','high',
 $q$SELECT d.id, s.name, d.work_date, d.ot_min FROM daily_payroll d
      JOIN eng_staff s ON s.id=d.staff_id
     WHERE d.pay_type_snap='contractor' AND d.ot_min <> 0$q$,
 NULL),
('INV-PAY-05','入职前与离职后不得有日结','critical',
 $q$SELECT d.id, s.name, d.work_date, s.hired_at, s.terminated_at
      FROM daily_payroll d JOIN eng_staff s ON s.id=d.staff_id
     WHERE d.work_date < s.hired_at
        OR (s.terminated_at IS NOT NULL AND d.work_date > s.terminated_at)$q$,
 NULL),
('INV-PAY-06','倒休只对月薪制累计','high',
 $q$SELECT t.id, s.name, s.pay_type FROM toil_ledger t
      JOIN eng_staff s ON s.id=t.staff_id
     WHERE t.entry_type='accrue' AND s.pay_type <> 'monthly'$q$,
 '时薪制加班按倍数付钱，外包无加班，都不该进倒休'),
('INV-PAY-07','离场时间必须晚于入场','critical',
 $q$SELECT id, staff_id, checkin_at, checkout_at FROM work_log
     WHERE checkin_at IS NOT NULL AND checkout_at IS NOT NULL
       AND checkout_at <= checkin_at$q$,
 NULL),
('INV-PAY-08','所有人员必须有成本时薪','critical',
 $q$SELECT id, name, pay_type FROM eng_staff WHERE cost_hourly_rate IS NULL$q$,
 '否则项目人工成本算不出来，利润率静默偏低'),

-- ══════════ 权限与安全 ══════════
('INV-SEC-01','所有视图必须 security_invoker=true','critical',
 $q$SELECT relname FROM pg_class
     WHERE relkind='v' AND relnamespace='public'::regnamespace
       AND (reloptions IS NULL OR NOT ('security_invoker=true' = ANY(reloptions)))$q$,
 '否则视图按所有者权限执行，RLS 与金额遮罩整个被绕过'),
('INV-SEC-02','第三级账号不得有后台权限','critical',
 $q$SELECT login_name, full_name FROM app_account WHERE tier=3 AND backend_access$q$,
 NULL),
('INV-SEC-03','核心管理员必须恰好一个','critical',
 $q$SELECT count(*) AS core_admin_count FROM app_account
     WHERE is_core_admin AND active HAVING count(*) <> 1$q$,
 NULL),
('INV-SEC-04','管理员数量不得超上限','high',
 $q$SELECT count(*) AS admin_count FROM app_account WHERE tier=1 AND active
     HAVING count(*) > (SELECT value_num FROM eng_setting WHERE key='max_admin_accounts')$q$,
 NULL),
('INV-SEC-05','管理员与施工人员不得挂部门','high',
 $q$SELECT a.login_name, a.tier, d.department FROM app_account a
      JOIN account_department d ON d.account_id=a.id WHERE a.tier IN (1,3)$q$,
 NULL),
('INV-SEC-06','每个在职部门账号至少属于一个部门','high',
 $q$SELECT login_name, full_name FROM app_account a
     WHERE a.tier=2 AND a.active
       AND NOT EXISTS(SELECT 1 FROM account_department d WHERE d.account_id=a.id)$q$,
 '否则这个账号什么都写不了'),
('INV-SEC-07','关键表必须开启 RLS','critical',
 $q$SELECT relname FROM pg_class
     WHERE relkind='r' AND relnamespace='public'::regnamespace
       AND relname IN ('project','payment_milestone','payment_receipt','material',
                       'stock_out','stock_out_line','daily_payroll','payroll_month',
                       'app_account','work_log')
       AND NOT relrowsecurity$q$,
 NULL),
('INV-SEC-08','管理员必须有邮箱（自主找回用）','high',
 $q$SELECT login_name, full_name FROM app_account
     WHERE tier=1 AND active AND email IS NULL$q$,
 NULL),
-- ★2026-08-04 全面回归发现：INV-SEC-07 只查 10 张手列的「关键表」，
--   而实际有 20 张表压根没开 RLS，断言却一路全绿 —— 正是 CLAUDE.md 说的
--   「手列清单一定会漏且不报错」。视图有 security_invoker 自动补齐，表没有，所以这里自动扫全库。
('INV-SEC-09','所有表必须开启 RLS（自动扫全库，不许手列清单）','high',
 $q$SELECT relname FROM pg_class
     WHERE relkind='r' AND relnamespace='public'::regnamespace
       AND NOT relrowsecurity
     ORDER BY relname$q$,
 '降权角色 konnext_app 对这些表有完整 DML —— 没有 RLS 就等于谁登录都能读写全部。'
 'auth_otp（别人的验证码）· audit_log（留痕可被删改）· account_department（改部门＝提权）最要紧'),

-- ══════════ 流程 ══════════
('INV-FLOW-01','SM 顺序：完成的 SM(n) 其前序必须完成或标不适用','critical',
 $q$SELECT p.code, s.sm_no FROM site_meeting s JOIN project p ON p.id=s.project_id
     WHERE s.completed_at IS NOT NULL AND s.sm_no > 1
       AND NOT EXISTS(SELECT 1 FROM site_meeting q
                       WHERE q.project_id=s.project_id AND q.sm_no=s.sm_no-1
                         AND (q.completed_at IS NOT NULL OR q.na_flag))$q$,
 NULL),
('INV-FLOW-02','交付完成必须有客户签收','critical',
 $q$SELECT h.id, p.code FROM handover_job h JOIN project p ON p.id=h.project_id
     WHERE h.completed_at IS NOT NULL
       AND (h.client_sign_url IS NULL OR h.client_sign_at IS NULL)$q$,
 NULL),
('INV-FLOW-03','维护上门完成必须有归因+服务内容+客户签字','critical',
 $q$SELECT j.id, p.code FROM maintenance_job j JOIN project p ON p.id=j.project_id
     WHERE j.completed_at IS NOT NULL
       AND (j.fault_cause IS NULL OR j.client_sign_url IS NULL
            OR j.service_summary IS NULL OR btrim(j.service_summary)='')$q$,
 NULL),
('INV-FLOW-04','安装任务必须在 SM4 完成之后','critical',
 $q$SELECT j.id, p.code FROM install_job j JOIN project p ON p.id=j.project_id
     WHERE NOT EXISTS(SELECT 1 FROM site_meeting s
                       WHERE s.project_id=j.project_id AND s.sm_no=4
                         AND (s.completed_at IS NOT NULL OR s.na_flag))$q$,
 NULL),
('INV-FLOW-05','安装完工时剩余必须清零','critical',
 $q$SELECT p.code, count(*) AS pending FROM project p
      JOIN install_item i ON i.project_id=p.id
     WHERE p.install_completed_at IS NOT NULL AND i.status='pending'
     GROUP BY p.code$q$,
 NULL),
('INV-FLOW-06','RMA 已返还必须先已接货','high',
 $q$SELECT rma_no FROM rma_case WHERE supplier_returned AND NOT supplier_received$q$,
 NULL),
('INV-FLOW-07','免责维保覆盖判定必须与归因一致','high',
 $q$SELECT c.id, c.title, c.fault_cause, p.handover_at FROM maintenance_case c
      JOIN project p ON p.id=c.project_id
     WHERE c.is_free_warranty
       AND (c.fault_cause NOT IN ('product_defect','wear_out') OR p.handover_at IS NULL)$q$,
 '人为损坏/不可抗力不该被判为免责覆盖'),
('INV-FLOW-08','已审批的盘点单必须有审批人与时间','high',
 $q$SELECT take_no FROM stocktake
     WHERE status='approved' AND (approved_by IS NULL OR approved_at IS NULL)$q$,
 NULL),
('INV-FLOW-09','超过审批线的盘亏，盘点人不得自批','critical',
 $q$SELECT st.take_no, st.counted_by, st.approved_by FROM stocktake st
     WHERE st.status='approved' AND st.counted_by = st.approved_by
       AND COALESCE((SELECT SUM(CASE WHEN sl.diff_qty<0
                     THEN -sl.diff_qty*COALESCE(sl.unit_cost_aud,0) ELSE 0 END)
                     FROM stocktake_line sl WHERE sl.stocktake_id=st.id),0)
         > (SELECT value_num FROM eng_setting WHERE key='stocktake_approve_amount_aud')$q$,
 NULL),
('INV-DOC-01','已发放的文档版本必须有文件地址','high',
 $q$SELECT i.id, d.doc_code, v.version_no FROM document_issue i
      JOIN document_version v ON v.id=i.version_id
      JOIN document d ON d.id=v.document_id
     WHERE v.file_url IS NULL OR btrim(v.file_url)=''$q$,
 NULL),
('INV-CAL-01','公共假日日历剩余不足 90 天','medium',
 $q$SELECT state, to_date AS 覆盖到 FROM v_holiday_coverage WHERE needs_topup$q$,
 '日历用完后加班会被当普通日算错，请从 Fair Work 官方名单补录'),
('INV-FX-01','汇率超过 3 天未更新','medium',
 $q$SELECT currency, fetched_at, days_stale FROM v_fx_current WHERE is_stale$q$,
 '售卖价会按旧汇率算'),
('INV-HANDOFF-01','有交接事项超过 SLA 未响应','medium',
 $q$SELECT project_code, event_key, to_dept_cn, waiting_hours, sla_hours
      FROM v_pending_handoff WHERE overdue$q$,
 '有人在等，流程停着');


-- =====================================================================
--  运行器
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_run_assertions(p_severity text DEFAULT NULL)
RETURNS TABLE(code text, severity text, label text, violations bigint, status text, hint text)
AS $$
DECLARE a record; n bigint;
BEGIN
    -- ⚠️ 必须用表别名限定：OUT 参数 code/severity/label 与表列同名，不限定会歧义报错
    FOR a IN SELECT d.* FROM assertion_def d
              WHERE d.active AND (p_severity IS NULL OR d.severity = p_severity)
              ORDER BY CASE d.severity WHEN 'critical' THEN 1 WHEN 'high' THEN 2 ELSE 3 END, d.code
    LOOP
        BEGIN
            EXECUTE format('SELECT count(*) FROM (%s) _t', a.query) INTO n;
        EXCEPTION WHEN OTHERS THEN
            code := a.code; severity := a.severity; label := a.label;
            violations := -1; status := '⚠ 断言本身出错: ' || SQLERRM; hint := a.hint;
            RETURN NEXT; CONTINUE;
        END;
        code := a.code; severity := a.severity; label := a.label; violations := n;
        status := CASE WHEN n = 0 THEN '✓ 通过' ELSE '✗ 违规 ' || n || ' 处' END;
        hint := CASE WHEN n = 0 THEN NULL ELSE a.hint END;
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 某条断言到底是哪几行违规
CREATE OR REPLACE FUNCTION fn_assertion_detail(p_code text)
RETURNS SETOF jsonb AS $$
DECLARE q text;
BEGIN
    SELECT d.query INTO q FROM assertion_def d WHERE d.code = p_code;
    IF q IS NULL THEN RAISE EXCEPTION '断言 % 不存在', p_code; END IF;
    RETURN QUERY EXECUTE format('SELECT to_jsonb(_t) FROM (%s) _t', q);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 一句话总结（上线/发版前看这个）
CREATE OR REPLACE FUNCTION fn_assertion_summary()
RETURNS TABLE(总数 bigint, 通过 bigint, 违规 bigint,
              严重违规 bigint, 高危违规 bigint, 提醒 bigint, 结论 text)
AS $$
    WITH r AS (SELECT * FROM fn_run_assertions())
    SELECT count(*),
           count(*) FILTER (WHERE violations = 0),
           count(*) FILTER (WHERE violations > 0),
           count(*) FILTER (WHERE violations > 0 AND severity='critical'),
           count(*) FILTER (WHERE violations > 0 AND severity='high'),
           count(*) FILTER (WHERE violations > 0 AND severity='medium'),
           CASE WHEN count(*) FILTER (WHERE violations > 0 AND severity='critical') > 0
                  THEN '⛔ 有严重违规，不可上线/发版'
                WHEN count(*) FILTER (WHERE violations > 0 AND severity='high') > 0
                  THEN '⚠ 有高危违规，需修复后再发'
                WHEN count(*) FILTER (WHERE violations > 0) > 0
                  THEN '△ 仅有提醒项，可发版但请安排处理'
                ELSE '✓ 全部通过' END
      FROM r;
$$ LANGUAGE sql SECURITY DEFINER;


-- #####################################################################
-- ##  v0.27：业主订阅（归运维） + 已流失/已烂尾 + 停留天数 + 利润率口径收紧
-- #####################################################################

-- =====================================================================
--  第四十二部分：业主订阅 subscription（★归【运维】部门，交付时发生）
--    五档：1~4 为订阅档，★第 5 档 = 不订阅
--    各档包含什么线下服务，系统不管
--    ★ 订阅收支【不计入利润率】——它是独立的经常性收入
-- =====================================================================
CREATE TABLE subscription (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL UNIQUE REFERENCES project(id) ON DELETE CASCADE,

    tier          smallint NOT NULL CHECK (tier BETWEEN 1 AND 5),  -- 5 = 不订阅
    annual_fee    numeric(12,2),                  -- 年费（运维填）
    currency      text NOT NULL DEFAULT 'AUD',

    signed_at     date,                           -- 交付时签的订阅协议日期
    period_start  date,                           -- 本期起
    period_end    date,                           -- 本期止（到期看这个）
    auto_renew    boolean NOT NULL DEFAULT true,

    cancelled_at  date,                           -- 退订日；退订后历史已收仍留着
    cancel_reason text,

    note          text,
    created_by    text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_by    text,
    updated_at    timestamptz NOT NULL DEFAULT now(),

    -- 第 5 档=不订阅：不该有年费与期间
    CONSTRAINT ck_sub_tier5 CHECK (
        tier <> 5 OR (COALESCE(annual_fee,0) = 0 AND period_start IS NULL AND period_end IS NULL)),
    CONSTRAINT ck_sub_tier14 CHECK (
        tier = 5 OR (annual_fee IS NOT NULL AND annual_fee > 0)),
    CONSTRAINT ck_sub_period CHECK (period_end IS NULL OR period_start IS NULL OR period_end > period_start)
);
COMMENT ON TABLE subscription IS
  '业主订阅：交付时签，归运维部门维护。第5档=不订阅。★订阅收支不计入利润率';

-- 订阅收款走同一套应收规矩（kind 加一种）
ALTER TABLE payment_milestone DROP CONSTRAINT IF EXISTS payment_milestone_kind_check;
ALTER TABLE payment_milestone ADD CONSTRAINT payment_milestone_kind_check
    CHECK (kind IN ('contract','maintenance','subscription'));
ALTER TABLE payment_milestone DROP CONSTRAINT IF EXISTS ck_pm_kind;
ALTER TABLE payment_milestone ADD CONSTRAINT ck_pm_kind CHECK (
    (kind='contract'     AND stage IS NOT NULL AND case_id IS NULL) OR
    (kind='maintenance'  AND stage IS NULL     AND case_id IS NOT NULL) OR
    (kind='subscription' AND stage IS NULL     AND case_id IS NULL));

-- 订阅状态阈值
INSERT INTO eng_setting(key, value_num, note) VALUES
 ('subscription_due_soon_days', 30, '订阅到期前多少天标记「即将到期」(黄)');

-- v0.31 ★订阅五档年费标准（用户 2026-07-30 定：做成运维手动填写的设置）
-- 初始 NULL=尚未定价，界面显示「未填」；第 5 档=不订阅，无年费键
INSERT INTO eng_setting(key, value_num, note, write_depts) VALUES
 ('sub_tier1_fee', NULL, '订阅第1档 年费(AUD)，运维维护', ARRAY['maintenance']),
 ('sub_tier2_fee', NULL, '订阅第2档 年费(AUD)，运维维护', ARRAY['maintenance']),
 ('sub_tier3_fee', NULL, '订阅第3档 年费(AUD)，运维维护', ARRAY['maintenance']),
 ('sub_tier4_fee', NULL, '订阅第4档 年费(AUD)，运维维护', ARRAY['maintenance']);

-- 状态停留阈值（卡住天数）——一状态一行，工程管理维护
CREATE TABLE status_stall_threshold (
    status      text PRIMARY KEY,
    stall_days  integer,                          -- NULL = 终态，不设阈值
    note        text
);
INSERT INTO status_stall_threshold(status, stall_days, note) VALUES
 ('engaging',        45,   '接洽当中'),
 ('quote_signed',    14,   '已签署报价 → 该收 S1 定金了'),
 ('deposit_paid',    21,   '定金已收 → 该安排 SM1 进场了'),
 ('in_construction', 120,  '施工中'),
 ('delivered',       30,   '已交付 → 该转运维/签订阅了'),
 ('maintaining',     NULL, '维护中：长期状态，不设阈值'),
 ('bid_lost',        NULL, '已流失（流失=流标，原名留标）：终态'),
 ('stalled',         NULL, '已烂尾：终态（但会单独列在风险看板）');


-- =====================================================================
--  v0.27 触发器
-- =====================================================================

-- ★ 状态一变就重置停留起始
CREATE OR REPLACE FUNCTION trg_project_status_since() RETURNS trigger AS $$
BEGIN
    IF TG_OP='UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
        NEW.status_since := now();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER project_status_since BEFORE UPDATE ON project
    FOR EACH ROW EXECUTE FUNCTION trg_project_status_since();

-- ★ 门禁：已流失 与 已烂尾 的定义边界
CREATE OR REPLACE FUNCTION trg_project_terminal_gate() RETURNS trigger AS $$
DECLARE settled_cnt int;
BEGIN
    -- 已流失：未进入收款阶段。有任何一笔合同款已结清就不叫已流失
    IF NEW.status = 'bid_lost' THEN
        SELECT count(*) INTO settled_cnt FROM payment_milestone
         WHERE project_id = NEW.id AND kind='contract' AND status='settled';
        IF settled_cnt > 0 THEN
            RAISE EXCEPTION '门禁：本项目已有 % 笔合同款结清，已进入收款阶段，不能置为「已流失」。'
                            '若是施工中断请用「已烂尾」', settled_cnt;
        END IF;
    END IF;
    -- 已烂尾：已在施工阶段且尚未进入维护。已交付就不存在烂尾
    IF NEW.status = 'stalled' THEN
        IF NEW.handover_at IS NOT NULL THEN
            RAISE EXCEPTION '门禁：本项目已于 % 交付，已进入维护阶段，不存在烂尾', NEW.handover_at::date;
        END IF;
        IF NEW.step6_signed_at IS NULL THEN
            RAISE EXCEPTION '门禁：本项目尚未签约进入施工，谈不上烂尾。未中标请用「已流失」';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER project_terminal_gate BEFORE INSERT OR UPDATE ON project
    FOR EACH ROW EXECUTE FUNCTION trg_project_terminal_gate();

-- ★ 门禁：订阅只能在【已交付】项目上建（交付过程中签）
CREATE OR REPLACE FUNCTION trg_subscription_gate() RETURNS trigger AS $$
DECLARE ho timestamptz; st text;
BEGIN
    SELECT handover_at, status INTO ho, st FROM project WHERE id = NEW.project_id;
    IF ho IS NULL THEN
        RAISE EXCEPTION '门禁：项目尚未交付(当前状态 %)，订阅在交付过程中签署，此时不能建立', st;
    END IF;
    IF NEW.signed_at IS NULL THEN NEW.signed_at := ho::date; END IF;
    -- 1~4 档：期间没填就按签约日起算一年
    IF NEW.tier <> 5 THEN
        IF NEW.period_start IS NULL THEN NEW.period_start := NEW.signed_at; END IF;
        IF NEW.period_end IS NULL THEN NEW.period_end := NEW.period_start + interval '1 year'; END IF;
    END IF;
    NEW.updated_at := now();
    IF NEW.updated_by IS NULL THEN
        NEW.updated_by := current_setting('app.actor', true);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER subscription_gate BEFORE INSERT OR UPDATE ON subscription
    FOR EACH ROW EXECUTE FUNCTION trg_subscription_gate();

CREATE TRIGGER subscription_audit AFTER INSERT OR UPDATE OR DELETE ON subscription
    FOR EACH ROW EXECUTE FUNCTION trg_audit();

-- 订阅归运维部门可写
INSERT INTO table_ownership(table_name, write_dept, note) VALUES
 ('subscription', ARRAY['maintenance'], '业主订阅归运维部门；交付时签，年费与档位由运维填'),
 ('status_stall_threshold', ARRAY['eng_mgmt'], '各状态卡住天数阈值');

-- 订阅表纳入 RLS：读全部、写运维
ALTER TABLE subscription ENABLE ROW LEVEL SECURITY;
CREATE POLICY subscription_read ON subscription FOR SELECT
  USING (NOT fn_is_field() OR fn_is_admin());
CREATE POLICY subscription_write ON subscription FOR ALL
  USING (fn_can_write('subscription')) WITH CHECK (fn_can_write('subscription'));


-- =====================================================================
--  v0.27 视图
-- =====================================================================

-- 66 ★订阅状态（四色）
--    绿 生效中 ｜ 黄 即将到期 ｜ 红 已逾期 ｜ 灰 未订阅/已退订
CREATE VIEW v_subscription_status AS
SELECT s.id, s.project_id, p.code AS project_code, p.name AS project_name,
       p.o1_name AS owner_name,
       s.tier,
       CASE s.tier WHEN 5 THEN '第5档·不订阅' ELSE '第'||s.tier||'档' END AS tier_cn,
       CASE WHEN fn_can_see_customer_amount() THEN s.annual_fee END::numeric(12,2) AS annual_fee,
       s.signed_at, s.period_start, s.period_end, s.auto_renew, s.cancelled_at,
       (s.period_end - now()::date) AS days_to_expiry,
       -- ★ 四种状态 + 四种颜色（前端直接用 color_token）
       CASE
         WHEN s.cancelled_at IS NOT NULL THEN 'cancelled'
         WHEN s.tier = 5                 THEN 'none'
         WHEN s.period_end < now()::date THEN 'overdue'
         WHEN s.period_end - now()::date
              <= (SELECT value_num FROM eng_setting WHERE key='subscription_due_soon_days')
                                         THEN 'due_soon'
         ELSE 'active' END                                          AS sub_status,
       CASE
         WHEN s.cancelled_at IS NOT NULL THEN '已退订'
         WHEN s.tier = 5                 THEN '未订阅'
         WHEN s.period_end < now()::date THEN '已逾期'
         WHEN s.period_end - now()::date
              <= (SELECT value_num FROM eng_setting WHERE key='subscription_due_soon_days')
                                         THEN '即将到期'
         ELSE '生效中' END                                          AS sub_status_cn,
       CASE
         WHEN s.cancelled_at IS NOT NULL THEN 'grey'
         WHEN s.tier = 5                 THEN 'grey'
         WHEN s.period_end < now()::date THEN 'red'
         WHEN s.period_end - now()::date
              <= (SELECT value_num FROM eng_setting WHERE key='subscription_due_soon_days')
                                         THEN 'amber'
         ELSE 'green' END                                           AS color_token,
       -- 累计已收（含已退订的历史已收）
       CASE WHEN fn_can_see_customer_amount() THEN
         COALESCE((SELECT SUM(r.amount) FROM payment_milestone m
                     JOIN payment_receipt r ON r.milestone_id=m.id
                    WHERE m.project_id=s.project_id AND m.kind='subscription'),0)
       END::numeric AS paid_total,
       s.updated_by, s.updated_at
  FROM subscription s JOIN project p ON p.id = s.project_id;

-- 67 订阅汇总（公司级：活跃数 / 年化 / 累计已收，按档拆分）
CREATE VIEW v_subscription_rollup AS
SELECT tier, tier_cn,
       count(*)                                                    AS sub_count,
       count(*) FILTER (WHERE sub_status IN ('active','due_soon'))  AS active_count,
       count(*) FILTER (WHERE sub_status='overdue')                 AS overdue_count,
       count(*) FILTER (WHERE sub_status='cancelled')               AS cancelled_count,
       CASE WHEN fn_can_see_customer_amount() THEN
         SUM(annual_fee) FILTER (WHERE sub_status IN ('active','due_soon')) END AS annualised_fee,
       CASE WHEN fn_can_see_customer_amount() THEN
         round(SUM(annual_fee) FILTER (WHERE sub_status IN ('active','due_soon'))/12.0,2) END AS monthly_run_rate,
       CASE WHEN fn_can_see_customer_amount() THEN SUM(paid_total) END AS paid_total_all_time
  FROM v_subscription_status
 GROUP BY tier, tier_cn;

-- v0.31 ★五档年费标准（配置在 eng_setting，运维维护，订阅签署时做默认值）
-- 标准价目是对外报价档位、非某客户合同额，且运维要维护它 —— 故不做金额遮罩
CREATE VIEW v_subscription_fee_standard AS
SELECT t.tier, t.label,
       CASE WHEN t.tier = 5 THEN NULL ELSE s.value_num END AS annual_fee_standard,
       (t.tier < 5 AND s.value_num IS NULL)                AS not_priced,   -- 未填提醒
       s.updated_by, s.updated_at
  FROM (VALUES (1,'sub_tier1_fee','第1档'),
               (2,'sub_tier2_fee','第2档'),
               (3,'sub_tier3_fee','第3档'),
               (4,'sub_tier4_fee','第4档'),
               (5,NULL,           '第5档·不订阅')) AS t(tier, key, label)
  LEFT JOIN eng_setting s ON s.key = t.key;

-- 68 ★状态停留（卡住天数）
CREATE VIEW v_project_stall AS
SELECT p.id AS project_id, p.code, p.name, p.status,
       CASE p.status
         WHEN 'engaging' THEN '接洽当中'
         WHEN 'quote_signed' THEN '已签署报价' WHEN 'deposit_paid' THEN '定金已收取'
         WHEN 'in_construction' THEN '施工中' WHEN 'delivered' THEN '项目交付'
         WHEN 'maintaining' THEN '项目维护中'
         WHEN 'bid_lost' THEN '已流失' WHEN 'stalled' THEN '已烂尾' END AS status_cn,
       p.status_since,
       (now()::date - p.status_since::date)              AS days_in_status,
       t.stall_days                                       AS threshold_days,
       (t.stall_days IS NOT NULL
        AND (now()::date - p.status_since::date) > t.stall_days) AS is_stalled,
       CASE WHEN t.stall_days IS NULL THEN NULL
            ELSE (now()::date - p.status_since::date) - t.stall_days END AS days_overdue,
       t.note AS threshold_note
  FROM project p
  LEFT JOIN status_stall_threshold t ON t.status = p.status;

-- 69 ★项目利润率（v0.27 口径收紧）
--    利润 = 合同额 − 材料 − 人工 + 维护净额
--    ⚠️ 订阅收支【不计入】——订阅是独立的经常性收入，另看 v_subscription_rollup
CREATE VIEW v_project_margin AS
WITH mat AS (
    SELECT so.project_id, SUM(ol.qty * COALESCE(ol.unit_cost_aud,0)) AS material_cost
      FROM stock_out_line ol JOIN stock_out so ON so.id=ol.stock_out_id
     GROUP BY so.project_id
), lab AS (
    SELECT w.project_id,
           SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0*s.cost_hourly_rate) AS labor_cost
      FROM work_log w JOIN eng_staff s ON s.id=w.staff_id
     WHERE w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL
     GROUP BY w.project_id
), mnt AS (
    SELECT c.project_id,
           COALESCE(SUM(rv.got),0)                                        AS maint_revenue,
           SUM(COALESCE(c.labor_cost,0) + COALESCE(c.material_cost,0))     AS maint_cost,
           SUM(CASE WHEN c.is_free_warranty
                    THEN COALESCE(c.labor_cost,0)+COALESCE(c.material_cost,0) ELSE 0 END) AS free_warranty_cost
      FROM maintenance_case c
      LEFT JOIN (SELECT m.case_id, SUM(r.amount) got
                   FROM payment_milestone m JOIN payment_receipt r ON r.milestone_id=m.id
                  WHERE m.kind='maintenance' GROUP BY m.case_id) rv ON rv.case_id=c.id
     GROUP BY c.project_id
)
SELECT p.id AS project_id, p.code, p.name, p.status,
       CASE WHEN fn_can_see_margin() THEN p.contract_price END::numeric(14,2) AS contract_value,
       CASE WHEN fn_can_see_margin() THEN round(COALESCE(mat.material_cost,0),2) END AS material_cost,
       CASE WHEN fn_can_see_margin() THEN round(COALESCE(lab.labor_cost,0),2)    END AS labor_cost,
       CASE WHEN fn_can_see_margin() THEN round(COALESCE(mnt.maint_revenue,0),2) END AS maint_revenue,
       CASE WHEN fn_can_see_margin() THEN round(COALESCE(mnt.maint_cost,0),2)    END AS maint_cost,
       CASE WHEN fn_can_see_margin()
            THEN round(COALESCE(mnt.maint_revenue,0)-COALESCE(mnt.maint_cost,0),2) END AS maint_net,
       CASE WHEN fn_can_see_margin() THEN round(COALESCE(mnt.free_warranty_cost,0),2) END AS free_warranty_cost,
       -- 利润 = 合同额 − 材料 − 人工 + 维护净额
       CASE WHEN fn_can_see_margin() THEN
         round(COALESCE(p.contract_price,0) - COALESCE(mat.material_cost,0)
             - COALESCE(lab.labor_cost,0)
             + COALESCE(mnt.maint_revenue,0) - COALESCE(mnt.maint_cost,0), 2) END AS profit,
       CASE WHEN fn_can_see_margin() AND COALESCE(p.contract_price,0) > 0 THEN
         round((COALESCE(p.contract_price,0) - COALESCE(mat.material_cost,0)
              - COALESCE(lab.labor_cost,0)
              + COALESCE(mnt.maint_revenue,0) - COALESCE(mnt.maint_cost,0))
              / p.contract_price * 100, 1) END AS margin_pct,
       -- 四档配色（红线 45% / 绿线 55%，与看板一致）
       CASE WHEN NOT fn_can_see_margin() OR COALESCE(p.contract_price,0) = 0 THEN NULL
            WHEN (COALESCE(p.contract_price,0) - COALESCE(mat.material_cost,0)
                - COALESCE(lab.labor_cost,0) + COALESCE(mnt.maint_revenue,0)
                - COALESCE(mnt.maint_cost,0)) < 0 THEN 'loss'
            WHEN (COALESCE(p.contract_price,0) - COALESCE(mat.material_cost,0)
                - COALESCE(lab.labor_cost,0) + COALESCE(mnt.maint_revenue,0)
                - COALESCE(mnt.maint_cost,0)) / p.contract_price >= 0.55 THEN 'healthy'
            WHEN (COALESCE(p.contract_price,0) - COALESCE(mat.material_cost,0)
                - COALESCE(lab.labor_cost,0) + COALESCE(mnt.maint_revenue,0)
                - COALESCE(mnt.maint_cost,0)) / p.contract_price >= 0.45 THEN 'warning'
            ELSE 'breach' END AS margin_band,
       -- 维护成本是否还含预估（含 → 利润率还会变）
       EXISTS(SELECT 1 FROM maintenance_case c2
               WHERE c2.project_id=p.id AND c2.status NOT IN ('paid_closed','void')) AS maint_provisional,
       p.eng_margin_locked, p.eng_margin_locked_at
  FROM project p
  LEFT JOIN mat ON mat.project_id=p.id
  LEFT JOIN lab ON lab.project_id=p.id
  LEFT JOIN mnt ON mnt.project_id=p.id;

COMMENT ON VIEW v_project_margin IS
  '利润 = 合同额 − 材料 − 人工 + 维护净额；★订阅收支不计入。四档：loss/breach/warning/healthy';

-- 70 风险看板（已流失 / 已烂尾 / 卡住 / 订阅逾期，一屏）
CREATE VIEW v_risk_board AS
SELECT p.code, p.name, p.status, st.status_cn,
       st.days_in_status, st.threshold_days, st.is_stalled, st.days_overdue,
       CASE WHEN p.status='bid_lost' THEN '已流失'
            WHEN p.status='stalled'  THEN '已烂尾'
            WHEN st.is_stalled       THEN '状态停留超阈值'
            ELSE NULL END                                   AS risk_type,
       sub.sub_status_cn                                     AS subscription_status,
       sub.color_token                                       AS subscription_color,
       CASE WHEN fn_can_see_margin() THEN m.margin_pct END   AS margin_pct,
       CASE WHEN fn_can_see_margin() THEN m.margin_band END  AS margin_band
  FROM project p
  LEFT JOIN v_project_stall st ON st.project_id=p.id
  LEFT JOIN v_subscription_status sub ON sub.project_id=p.id
  LEFT JOIN v_project_margin m ON m.project_id=p.id
 WHERE p.status IN ('bid_lost','stalled')
    OR st.is_stalled
    OR sub.sub_status = 'overdue';

DO $$
DECLARE v record;
BEGIN
  FOR v IN SELECT c.relname FROM pg_class c
            WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
              AND (c.reloptions IS NULL OR NOT ('security_invoker=true' = ANY(c.reloptions)))
  LOOP EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', v.relname); END LOOP;
END $$;

-- =====================================================================
--  v0.27 新增断言
-- =====================================================================
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES
('INV-SUB-01','订阅只能建在已交付项目上','critical',
 $q$SELECT s.id, p.code, p.status FROM subscription s
      JOIN project p ON p.id=s.project_id WHERE p.handover_at IS NULL$q$,
 '订阅在交付过程中签署'),
('INV-SUB-02','第5档(不订阅)不得有年费与期间','high',
 $q$SELECT s.id, p.code, s.annual_fee, s.period_start FROM subscription s
      JOIN project p ON p.id=s.project_id
     WHERE s.tier=5 AND (COALESCE(s.annual_fee,0)<>0 OR s.period_start IS NOT NULL)$q$,
 NULL),
('INV-SUB-03','1~4档必须有年费','high',
 $q$SELECT s.id, p.code, s.tier FROM subscription s JOIN project p ON p.id=s.project_id
     WHERE s.tier<>5 AND (s.annual_fee IS NULL OR s.annual_fee<=0)$q$,
 NULL),
('INV-SUB-04','订阅收款必须挂 kind=subscription','high',
 $q$SELECT id, kind, stage, case_id FROM payment_milestone
     WHERE kind='subscription' AND (stage IS NOT NULL OR case_id IS NOT NULL)$q$,
 '否则会被算进合同款或维护款，污染利润率'),
('INV-STATUS-01','已流失项目不得有已结清的合同款','critical',
 $q$SELECT p.code, count(*) AS settled FROM project p
      JOIN payment_milestone m ON m.project_id=p.id
     WHERE p.status='bid_lost' AND m.kind='contract' AND m.status='settled'
     GROUP BY p.code$q$,
 '已进入收款阶段的不叫已流失；施工中断请用「已烂尾」'),
('INV-STATUS-02','已烂尾项目不得已交付','critical',
 $q$SELECT code, handover_at FROM project WHERE status='stalled' AND handover_at IS NOT NULL$q$,
 '一旦进入维护阶段就不存在烂尾'),
('INV-STATUS-03','已烂尾项目必须已签约进入施工','high',
 $q$SELECT code FROM project WHERE status='stalled' AND step6_signed_at IS NULL$q$,
 '未中标请用「已流失」'),
('INV-STATUS-04','状态停留起始不得晚于当前时间','high',
 $q$SELECT code, status, status_since FROM project WHERE status_since > now()$q$,
 NULL),
('INV-STATUS-05','每个非终态都应配停留阈值','medium',
 $q$SELECT DISTINCT p.status FROM project p
     WHERE p.status NOT IN ('maintaining','bid_lost','stalled')
       AND NOT EXISTS(SELECT 1 FROM status_stall_threshold t
                       WHERE t.status=p.status AND t.stall_days IS NOT NULL)$q$,
 '没阈值就算不出卡住'),
('INV-MARGIN-01','订阅收支不得计入利润率','critical',
 $q$SELECT p.code FROM project p
     WHERE EXISTS(SELECT 1 FROM payment_milestone m WHERE m.project_id=p.id AND m.kind='subscription')
       AND (SELECT count(*) FROM pg_matviews WHERE false) > 0$q$,
 '本断言由 v_project_margin 定义保证：维护收入仅取 kind=maintenance。若改动该视图务必复查');

-- =====================================================================
--  修正：未开工 / 已流失 / 已烂尾 项目的利润率
--  ⚠️ 原公式对未发生成本的项目算出 (合同额−0−0)/合同额 = 100%，
--     于是【已烂尾项目显示"利润率 100% healthy"】——荒谬且会误导决策。
--  处理：
--   · 未开工(无材料无人工) → 利润率【不显示】，档位 not_started
--   · 已流失(未中标)         → 不显示，档位 bid_lost
--   · 已烂尾               → 收入基数换成【实收合同款】而非合同额，
--                            因为烂尾意味着钱收不全，按合同额算是自欺
-- =====================================================================
DROP VIEW IF EXISTS v_risk_board;
DROP VIEW IF EXISTS v_project_margin;
CREATE VIEW v_project_margin AS
WITH mat AS (
    SELECT so.project_id, SUM(ol.qty * COALESCE(ol.unit_cost_aud,0)) AS material_cost
      FROM stock_out_line ol JOIN stock_out so ON so.id=ol.stock_out_id
     GROUP BY so.project_id
), lab AS (
    SELECT w.project_id,
           SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/3600.0*s.cost_hourly_rate) AS labor_cost
      FROM work_log w JOIN eng_staff s ON s.id=w.staff_id
     WHERE w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL
     GROUP BY w.project_id
), mnt AS (
    SELECT c.project_id,
           COALESCE(SUM(rv.got),0) AS maint_revenue,
           SUM(COALESCE(c.labor_cost,0) + COALESCE(c.material_cost,0)) AS maint_cost,
           SUM(CASE WHEN c.is_free_warranty
                    THEN COALESCE(c.labor_cost,0)+COALESCE(c.material_cost,0) ELSE 0 END) AS free_warranty_cost
      FROM maintenance_case c
      LEFT JOIN (SELECT m.case_id, SUM(r.amount) got
                   FROM payment_milestone m JOIN payment_receipt r ON r.milestone_id=m.id
                  WHERE m.kind='maintenance' GROUP BY m.case_id) rv ON rv.case_id=c.id
     GROUP BY c.project_id
), rcv AS (   -- 已收合同款（烂尾项目的收入基数）
    SELECT m.project_id, SUM(r.amount) AS contract_received
      FROM payment_milestone m JOIN payment_receipt r ON r.milestone_id=m.id
     WHERE m.kind='contract' GROUP BY m.project_id
), calc AS (
    SELECT p.id, p.code, p.name, p.status,
           p.contract_price, p.eng_margin_locked, p.eng_margin_locked_at,
           COALESCE(mat.material_cost,0) AS material_cost,
           COALESCE(lab.labor_cost,0)    AS labor_cost,
           COALESCE(mnt.maint_revenue,0) AS maint_revenue,
           COALESCE(mnt.maint_cost,0)    AS maint_cost,
           COALESCE(mnt.free_warranty_cost,0) AS free_warranty_cost,
           COALESCE(rcv.contract_received,0)  AS contract_received,
           -- ★收入基数：烂尾按实收，其余按合同额
           CASE WHEN p.status='stalled' THEN COALESCE(rcv.contract_received,0)
                ELSE COALESCE(p.contract_price,0) END AS revenue_basis,
           -- ★是否已开工（发生过材料或人工成本）
           (COALESCE(mat.material_cost,0) > 0 OR COALESCE(lab.labor_cost,0) > 0) AS cost_started
      FROM project p
      LEFT JOIN mat ON mat.project_id=p.id
      LEFT JOIN lab ON lab.project_id=p.id
      LEFT JOIN mnt ON mnt.project_id=p.id
      LEFT JOIN rcv ON rcv.project_id=p.id
)
SELECT c.id AS project_id, c.code, c.name, c.status,
       CASE WHEN fn_can_see_margin() THEN c.contract_price END::numeric(14,2) AS contract_value,
       CASE WHEN fn_can_see_margin() THEN round(c.revenue_basis,2) END AS revenue_basis,
       CASE WHEN fn_can_see_margin() THEN round(c.material_cost,2) END AS material_cost,
       CASE WHEN fn_can_see_margin() THEN round(c.labor_cost,2)    END AS labor_cost,
       CASE WHEN fn_can_see_margin() THEN round(c.maint_revenue,2) END AS maint_revenue,
       CASE WHEN fn_can_see_margin() THEN round(c.maint_cost,2)    END AS maint_cost,
       CASE WHEN fn_can_see_margin() THEN round(c.maint_revenue-c.maint_cost,2) END AS maint_net,
       CASE WHEN fn_can_see_margin() THEN round(c.free_warranty_cost,2) END AS free_warranty_cost,
       -- 利润：只在"已开工 且 非已流失"时才算
       CASE WHEN fn_can_see_margin() AND c.cost_started AND c.status <> 'bid_lost'
            THEN round(c.revenue_basis - c.material_cost - c.labor_cost
                     + c.maint_revenue - c.maint_cost, 2) END AS profit,
       CASE WHEN fn_can_see_margin() AND c.cost_started AND c.status <> 'bid_lost'
                 AND c.revenue_basis > 0
            THEN round((c.revenue_basis - c.material_cost - c.labor_cost
                      + c.maint_revenue - c.maint_cost) / c.revenue_basis * 100, 1) END AS margin_pct,
       -- 六档：not_started / bid_lost / loss / breach / warning / healthy
       CASE
         WHEN NOT fn_can_see_margin()          THEN NULL
         WHEN c.status = 'bid_lost'            THEN 'bid_lost'
         WHEN NOT c.cost_started               THEN 'not_started'
         WHEN c.revenue_basis <= 0             THEN 'loss'
         WHEN (c.revenue_basis - c.material_cost - c.labor_cost
             + c.maint_revenue - c.maint_cost) < 0 THEN 'loss'
         WHEN (c.revenue_basis - c.material_cost - c.labor_cost
             + c.maint_revenue - c.maint_cost) / c.revenue_basis >= 0.55 THEN 'healthy'
         WHEN (c.revenue_basis - c.material_cost - c.labor_cost
             + c.maint_revenue - c.maint_cost) / c.revenue_basis >= 0.45 THEN 'warning'
         ELSE 'breach' END AS margin_band,
       CASE
         WHEN c.status = 'bid_lost'  THEN '已流失·无利润率'
         WHEN NOT c.cost_started     THEN '未开工·尚无成本'
         WHEN c.status = 'stalled'   THEN '★已烂尾·按实收计'
         ELSE NULL END AS margin_note,
       EXISTS(SELECT 1 FROM maintenance_case c2
               WHERE c2.project_id=c.id AND c2.status NOT IN ('paid_closed','void')) AS maint_provisional,
       c.eng_margin_locked, c.eng_margin_locked_at
  FROM calc c;

CREATE VIEW v_risk_board AS
SELECT p.code, p.name, p.status, st.status_cn,
       st.days_in_status, st.threshold_days, st.is_stalled, st.days_overdue,
       CASE WHEN p.status='bid_lost' THEN '已流失'
            WHEN p.status='stalled'  THEN '已烂尾'
            WHEN st.is_stalled       THEN '状态停留超阈值'
            ELSE NULL END AS risk_type,
       sub.sub_status_cn  AS subscription_status,
       sub.color_token    AS subscription_color,
       CASE WHEN fn_can_see_margin() THEN m.margin_pct END  AS margin_pct,
       CASE WHEN fn_can_see_margin() THEN m.margin_band END AS margin_band,
       m.margin_note
  FROM project p
  LEFT JOIN v_project_stall st ON st.project_id=p.id
  LEFT JOIN v_subscription_status sub ON sub.project_id=p.id
  LEFT JOIN v_project_margin m ON m.project_id=p.id
 WHERE p.status IN ('bid_lost','stalled') OR st.is_stalled OR sub.sub_status='overdue';

INSERT INTO assertion_def(code,label,severity,query,hint) VALUES
('INV-MARGIN-02','已流失/未开工项目不得显示利润率','high',
 $q$SELECT code, status, margin_pct, margin_band FROM v_project_margin
     WHERE margin_pct IS NOT NULL
       AND (status='bid_lost' OR margin_band='not_started')$q$,
 '没花钱的项目算出 100% 会误导决策'),
('INV-MARGIN-03','已烂尾项目的收入基数必须是实收而非合同额','high',
 $q$SELECT m.code, m.revenue_basis, m.contract_value FROM v_project_margin m
     WHERE m.status='stalled' AND m.revenue_basis IS NOT NULL
       AND m.contract_value IS NOT NULL AND m.revenue_basis = m.contract_value
       AND m.contract_value > 0
       AND COALESCE((SELECT SUM(r.amount) FROM payment_milestone pm
                       JOIN payment_receipt r ON r.milestone_id=pm.id
                      WHERE pm.project_id=m.project_id AND pm.kind='contract'),0) <> m.contract_value$q$,
 '烂尾意味着钱收不全，按合同额算利润率是自欺');

DO $$
DECLARE v record;
BEGIN
  FOR v IN SELECT c.relname FROM pg_class c
            WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
              AND (c.reloptions IS NULL OR NOT ('security_invoker=true' = ANY(c.reloptions)))
  LOOP EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', v.relname); END LOOP;
END $$;


-- #####################################################################
-- ##  v0.28：项目标识贯穿全系统
-- ##  问题：所有流程都跟项目走，但大部分视图只带 code 和 name，不带地址。
-- ##        界面上就看不出"这是哪个项目、在哪儿"。
-- ##        实际工作里没人靠 KX-2026-0142 认项目，大家说的是"Cherrybrook 那家"。
-- #####################################################################

-- ★ 项目标识规范视图：任何界面要显示项目，join 这个
CREATE VIEW v_project_label AS
SELECT p.id AS project_id, p.code, p.name, p.display_label,
       p.addr_street, p.addr_suburb, p.addr_state,
       COALESCE(NULLIF(btrim(COALESCE(p.addr_street,'')),'') || ', ', '')
         || COALESCE(p.addr_suburb,'')
         || COALESCE(' ' || p.addr_state, '')                       AS addr_full,
       p.o1_name AS owner_name, p.o1_phone AS owner_phone,
       p.status, p.status_since, p.geo_lat, p.geo_lng,
       (SELECT COALESCE(pp.contact_name, pp.company) FROM project_party pp
         WHERE pp.project_id=p.id AND pp.trade='builder' LIMIT 1)   AS builder_name,
       (SELECT COALESCE(pp.contact_name, pp.company) FROM project_party pp
         WHERE pp.project_id=p.id AND pp.trade='electrician' LIMIT 1) AS electrician_name
  FROM project p;
COMMENT ON VIEW v_project_label IS
  '项目标识规范视图。界面上任何地方显示项目，一律 join 这里取 display_label + addr_suburb';

-- ★ 把项目标识补进【所有】带项目列的视图 —— 自动扫，不用手列清单
--   每一个部门都要管全公司的项目，每个部门的视图都必须看得见【编号 + 地址】
--   声明式：以后新增视图只要带 project_id/project_code，重跑本块就自动包进来
DO $$
DECLARE r record; def text; pid_col text; join_on text; n int := 0;
BEGIN
  FOR r IN
    SELECT v.table_name AS vname,
           (SELECT c.column_name FROM information_schema.columns c
             WHERE c.table_schema='public' AND c.table_name=v.table_name
               AND c.column_name='project_id' LIMIT 1) AS by_id,
           (SELECT c.column_name FROM information_schema.columns c
             WHERE c.table_schema='public' AND c.table_name=v.table_name
               AND c.column_name IN ('project_code','code') LIMIT 1) AS by_code
      FROM information_schema.views v
     WHERE v.table_schema='public'
       AND v.table_name <> 'v_project_label'          -- 标识来源本身不包
       AND NOT EXISTS(SELECT 1 FROM information_schema.columns c
                       WHERE c.table_schema='public' AND c.table_name=v.table_name
                         AND c.column_name='pj_label')  -- 已包过的跳过
       AND EXISTS(SELECT 1 FROM information_schema.columns c
                   WHERE c.table_schema='public' AND c.table_name=v.table_name
                     AND c.column_name IN ('project_id','project_code'))
     ORDER BY v.table_name
  LOOP
    IF r.by_id IS NOT NULL THEN
      pid_col := r.by_id; join_on := 'lb.project_id = _v.'||quote_ident(pid_col);
    ELSE
      pid_col := r.by_code; join_on := 'lb.code = _v.'||quote_ident(pid_col);
    END IF;
    def := rtrim(rtrim(pg_get_viewdef(r.vname::regclass, true)), ';');
    BEGIN
      EXECUTE format(
        'CREATE OR REPLACE VIEW %I AS SELECT _v.*, '
        'lb.display_label AS pj_label, lb.code AS pj_code, '
        'lb.addr_suburb AS pj_suburb, lb.addr_full AS pj_addr, '
        'lb.owner_name AS pj_owner '
        'FROM (%s) _v LEFT JOIN v_project_label lb ON %s', r.vname, def, join_on);
      n := n + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '★ 视图 % 未能自动追加项目标识：%', r.vname, SQLERRM;
    END;
  END LOOP;
  RAISE NOTICE '已为 % 个视图追加项目标识（pj_code / pj_label / pj_suburb / pj_addr / pj_owner）', n;
END $$;

-- ★ 项目总目录：每个部门的「项目列表」页都用这一个
--   六个部门都能看到全公司项目（读全部），金额按各自权限遮罩
CREATE VIEW v_project_directory AS
SELECT lb.project_id, lb.code, lb.display_label, lb.name,
       lb.addr_street, lb.addr_suburb, lb.addr_state, lb.addr_full,
       lb.owner_name, lb.owner_phone, lb.builder_name, lb.electrician_name,
       lb.status, st.status_cn, st.days_in_status, st.threshold_days, st.is_stalled,
       p.build_stage, p.created_at::date AS created_on,
       p.step6_signed_at::date  AS signed_on,
       p.install_completed_at::date AS install_done_on,
       p.handover_at::date      AS handover_on,
       p.free_warranty_months,
       -- 钱：按各自权限遮罩
       CASE WHEN fn_can_see_customer_amount() THEN p.contract_price END::numeric(14,2) AS contract_price,
       CASE WHEN fn_can_see_customer_amount() THEN
         COALESCE((SELECT SUM(r.amount) FROM payment_milestone m
                     JOIN payment_receipt r ON r.milestone_id=m.id
                    WHERE m.project_id=p.id AND m.kind='contract'),0) END AS contract_received,
       CASE WHEN fn_can_see_margin() THEN mg.margin_pct END AS margin_pct,
       CASE WHEN fn_can_see_margin() THEN mg.margin_band END AS margin_band,
       -- 各部门自己关心的进度（不含金额，人人可见）
       (SELECT count(*) FROM site_meeting sm
         WHERE sm.project_id=p.id AND (sm.completed_at IS NOT NULL OR sm.na_flag)) AS sm_done,
       (SELECT count(*) FROM install_item ii
         WHERE ii.project_id=p.id AND ii.status='pending')            AS install_pending,
       (SELECT count(*) FROM maintenance_case mc
         WHERE mc.project_id=p.id AND mc.status NOT IN ('paid_closed','void')) AS maint_open,
       sub.sub_status_cn AS subscription_status,
       sub.color_token   AS subscription_color,
       (SELECT count(*) FROM v_pending_handoff h WHERE h.project_code=p.code) AS pending_handoffs
  FROM v_project_label lb
  JOIN project p ON p.id = lb.project_id
  LEFT JOIN v_project_stall st ON st.project_id = p.id
  LEFT JOIN v_project_margin mg ON mg.project_id = p.id
  LEFT JOIN v_subscription_status sub ON sub.project_id = p.id;
COMMENT ON VIEW v_project_directory IS
  '项目总目录：六个部门的「项目列表」页共用。读全部（每个部门都管全公司项目），金额按各自权限遮罩';

DO $$
DECLARE v record;
BEGIN
  FOR v IN SELECT c.relname FROM pg_class c
            WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
              AND (c.reloptions IS NULL OR NOT ('security_invoker=true' = ANY(c.reloptions)))
  LOOP EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', v.relname); END LOOP;
END $$;

-- 断言：关键视图必须带得出项目标识
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES
('INV-UI-01','★所有带项目列的视图都必须带出项目标识（编号+地址）','high',
 $q$SELECT v.table_name FROM information_schema.views v
     WHERE v.table_schema='public'
       AND v.table_name NOT IN ('v_project_label','v_project_directory')
       AND EXISTS(SELECT 1 FROM information_schema.columns c
                   WHERE c.table_schema='public' AND c.table_name=v.table_name
                     AND c.column_name IN ('project_id','project_code'))
       AND NOT EXISTS(SELECT 1 FROM information_schema.columns c
                       WHERE c.table_schema='public' AND c.table_name=v.table_name
                         AND c.column_name='pj_label')$q$,
 '每个部门都管全公司项目，每个视图都必须看得见【编号+地址】。'
 '新增视图后重跑 DDL 末尾那个 DO 块即可自动补上'),
('INV-UI-02','项目必须有可读标识（编号+名称或Suburb）','medium',
 $q$SELECT code, name, addr_suburb FROM project
     WHERE COALESCE(NULLIF(btrim(COALESCE(name,'')),''),
                    NULLIF(btrim(COALESCE(addr_suburb,'')),'')) IS NULL$q$,
 '项目名和 Suburb 都空 → 界面上只能显示编号，同事认不出是哪家');


-- #####################################################################
-- ##  v0.29：挂起的事必须追得回项目
-- ##  「脱离了项目，那些挂起的任务，管理人员哪里知道是哪个项目的」
-- ##
-- ##  三类处理：
-- ##   A 真公司级（盘点/采购单/汇率/假日/账号）→ 界面明确标「公司级」，不留空白
-- ##   B 跨项目（每日上报/日结/倒休）→ 视图带出【当天涉及哪些项目】
-- ##   C 本该有项目却可空（问题上报）→ 加约束，非公司级必须填
-- #####################################################################

-- ★ 某人某天涉及哪些项目（打卡 + 四类任务派工，合并去重）
CREATE VIEW v_daily_projects AS
WITH src AS (
    SELECT w.staff_id, w.checkin_at::date AS work_date, w.project_id, 'worklog'::text AS src
      FROM work_log w WHERE w.checkin_at IS NOT NULL
    UNION
    SELECT sm.owner_staff_id, sm.scheduled_date, sm.project_id, 'sm'
      FROM site_meeting sm WHERE sm.scheduled_date IS NOT NULL AND sm.owner_staff_id IS NOT NULL
    UNION
    SELECT j.staff_id, j.scheduled_date, j.project_id, 'install'
      FROM install_job j WHERE j.scheduled_date IS NOT NULL AND j.staff_id IS NOT NULL
    UNION
    SELECT h.staff_id, h.scheduled_date, h.project_id, 'handover'
      FROM handover_job h WHERE h.scheduled_date IS NOT NULL AND h.staff_id IS NOT NULL
    UNION
    SELECT m.staff_id, m.scheduled_date, m.project_id, 'maintenance'
      FROM maintenance_job m WHERE m.scheduled_date IS NOT NULL AND m.staff_id IS NOT NULL
)
SELECT s.staff_id, st.name AS staff_name, s.work_date,
       count(DISTINCT s.project_id)                          AS project_count,
       string_agg(DISTINCT lb.code, ' / ' ORDER BY lb.code)  AS project_codes,
       string_agg(DISTINCT lb.addr_suburb, ' / ')             AS project_suburbs,
       string_agg(DISTINCT lb.display_label, E'\n' ORDER BY lb.display_label) AS project_labels,
       array_agg(DISTINCT s.project_id)                      AS project_ids
  FROM src s
  JOIN v_project_label lb ON lb.project_id = s.project_id
  LEFT JOIN eng_staff st ON st.id = s.staff_id
 GROUP BY s.staff_id, st.name, s.work_date;
COMMENT ON VIEW v_daily_projects IS
  '某人某天涉及哪些项目。每日上报与日结工资挂"人+日期"（一天跨多项目），靠这个视图追回项目';

-- ★ 日结工资带出当天项目 —— 未记录挂起时，管理人员据此知道该去哪个项目补录
CREATE VIEW v_daily_payroll_detail AS
SELECT d.id, d.staff_id, s.name AS staff_name, d.work_date, d.day_type,
       d.span_min, d.lunch_min, d.paid_min, d.normal_min, d.ot_min,
       d.pay_type_snap, d.status, d.unrecorded,
       d.backfilled_by, d.backfilled_at, d.backfill_note,
       CASE WHEN fn_can_see_salary() THEN d.pay_amount END::numeric(12,2) AS pay_amount,
       CASE WHEN fn_can_see_salary() THEN d.pay_rate_snap END::numeric(10,2) AS pay_rate_snap,
       -- ★ 那天在哪些项目（挂起补录时唯一的线索）
       COALESCE(dp.project_count,0)                        AS project_count,
       COALESCE(dp.project_codes,'（无派工记录）')          AS project_codes,
       dp.project_suburbs, dp.project_labels,
       CASE WHEN d.status='unrecorded_held' AND COALESCE(dp.project_count,0)=0
            THEN '★无从追溯：当天既无打卡也无派工，需人工确认'
            WHEN d.status='unrecorded_held'
            THEN '待负责人补录 · 当天派工：' || dp.project_codes
            ELSE NULL END                                   AS backfill_hint
  FROM daily_payroll d
  JOIN eng_staff s ON s.id = d.staff_id
  LEFT JOIN v_daily_projects dp ON dp.staff_id=d.staff_id AND dp.work_date=d.work_date;

-- ★ 每日上报带出当天项目
CREATE VIEW v_daily_report_detail AS
SELECT r.id, r.staff_id, s.name AS staff_name, r.report_date,
       r.planned_minutes, r.onsite_minutes, r.span_minutes, r.lunch_min, r.paid_minutes,
       r.over_plan_min, r.over_span_min, r.submitted_at, r.note,
       COALESCE(dp.project_count,0)               AS project_count,
       COALESCE(dp.project_codes,'（无派工）')     AS project_codes,
       dp.project_suburbs,
       (SELECT count(*) FROM daily_issue i WHERE i.report_id=r.id)  AS issue_count,
       (SELECT count(*) FROM daily_issue i WHERE i.report_id=r.id
         AND i.is_company_level)                                    AS company_issue_count
  FROM daily_report r
  JOIN eng_staff s ON s.id = r.staff_id
  LEFT JOIN v_daily_projects dp ON dp.staff_id=r.staff_id AND dp.work_date=r.report_date;

-- ★ 问题上报明细：项目 or 明确的公司级，绝不留空白
CREATE VIEW v_daily_issue_detail AS
SELECT i.id, i.report_id, r.staff_id, s.name AS staff_name, r.report_date,
       i.issue_type,
       CASE i.issue_type WHEN 'rnd' THEN '研发问题' WHEN 'product' THEN '产品问题'
            WHEN 'market' THEN '市场问题' WHEN 'standardization' THEN '标准化问题'
            ELSE '工程安排问题' END                           AS issue_type_cn,
       i.description, i.is_company_level,
       i.project_id,
       COALESCE(lb.code, '公司级')                            AS pj_code,
       COALESCE(lb.display_label, '★ 公司级问题（不属于单个项目）') AS pj_label,
       lb.addr_suburb AS pj_suburb, lb.addr_full AS pj_addr,
       i.created_at
  FROM daily_issue i
  JOIN daily_report r ON r.id = i.report_id
  JOIN eng_staff s ON s.id = r.staff_id
  LEFT JOIN v_project_label lb ON lb.project_id = i.project_id;

-- ★ 倒休来源：哪天的加班、那天在哪些项目
CREATE VIEW v_toil_detail AS
SELECT t.id, t.staff_id, s.name AS staff_name, t.entry_type, t.minutes,
       round(t.minutes/60.0,2) AS hours, t.reason, t.created_by, t.created_at,
       d.work_date AS source_work_date, d.day_type AS source_day_type,
       COALESCE(dp.project_codes, CASE WHEN d.id IS NULL THEN '（人工调整）' ELSE '（无派工）' END)
                                                    AS source_project_codes,
       dp.project_suburbs AS source_project_suburbs,
       dp.project_count   AS source_project_count
  FROM toil_ledger t
  JOIN eng_staff s ON s.id = t.staff_id
  LEFT JOIN daily_payroll d ON d.id = t.ref_payroll_id
  LEFT JOIN v_daily_projects dp ON dp.staff_id=t.staff_id AND dp.work_date=d.work_date;

-- ★★ 悬而未决总表：所有挂起/待处理的事，每行都能说清是哪个项目（或明确公司级）
--     管理人员打开这一张表就够了
CREATE VIEW v_open_tasks AS
-- ① 部门交接未响应
SELECT 'handoff'::text                         AS kind,
       '部门交接待响应'::text                   AS kind_cn,
       h.event_label                            AS title,
       h.action_needed                          AS action,
       h.to_dept_cn                             AS owner,
       COALESCE(h.pj_code,'公司级')             AS pj_code,
       COALESCE(h.pj_label,'★ 公司级事项')      AS pj_label,
       h.pj_suburb, h.pj_addr,
       h.raised_at                              AS since,
       h.waiting_hours::numeric                 AS waiting_hours,
       h.overdue                                AS overdue,
       CASE WHEN h.overdue THEN 'red' ELSE 'amber' END AS color_token
  FROM v_pending_handoff h
UNION ALL
-- ② 日结工资未记录挂起（★这就是"挂起的任务不知道哪个项目"最典型的一处）
SELECT 'payroll_held', '日结未记录·挂起不发',
       d.staff_name || ' · ' || d.work_date,
       COALESCE(d.backfill_hint,'待负责人补录'),
       '工程管理',
       CASE WHEN d.project_count=0 THEN '无从追溯' ELSE split_part(d.project_codes,' / ',1) END,
       CASE WHEN d.project_count=0 THEN '★ 当天既无打卡也无派工'
            WHEN d.project_count=1 THEN d.project_labels
            ELSE '跨 '||d.project_count||' 个项目：'||d.project_codes END,
       d.project_suburbs, NULL,
       d.work_date::timestamptz,
       (now()::date - d.work_date) * 24.0,
       (now()::date - d.work_date) > 7,
       CASE WHEN d.project_count=0 THEN 'red' ELSE 'amber' END
  FROM v_daily_payroll_detail d
 WHERE d.status='unrecorded_held'
UNION ALL
-- ③ 待估价变更（S4 开票前必须估完）
SELECT 'variation', '变更待估价',
       v.change_type || '｜' || COALESCE(v.description,''),
       '外部算完后填回结算金额', '财务',
       lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
       v.created_at,
       EXTRACT(EPOCH FROM (now()-v.created_at))/3600.0,
       (now() - v.created_at) > interval '48 hours',
       CASE WHEN (now()-v.created_at) > interval '48 hours' THEN 'red' ELSE 'amber' END
  FROM variation v JOIN v_project_label lb ON lb.project_id=v.project_id
 WHERE v.billable AND v.settle_amount IS NULL
UNION ALL
-- ④ 安装剩余项未清零
SELECT 'install_pending', '安装剩余待处理',
       i.title || COALESCE('（'||i.area||'）',''), '做完 / 取消 / 挂起 / 转变更', '工程管理',
       lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
       i.created_at,
       EXTRACT(EPOCH FROM (now()-i.created_at))/3600.0,
       (now() - i.created_at) > interval '30 days', 'amber'
  FROM install_item i JOIN v_project_label lb ON lb.project_id=i.project_id
 WHERE i.status='pending'
UNION ALL
-- ⑤ 出库已发未确认收货
SELECT 'stock_unconfirmed', '出库待提货人确认',
       so.out_no || ' · ' || COALESCE(so.receiver_name,''), '短信回 YES 或人工确认', '库管',
       lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
       so.released_at,
       EXTRACT(EPOCH FROM (now()-so.released_at))/3600.0,
       (now() - so.released_at) > interval '72 hours',
       CASE WHEN (now()-so.released_at) > interval '72 hours' THEN 'red' ELSE 'amber' END
  FROM stock_out so JOIN v_project_label lb ON lb.project_id=so.project_id
 WHERE so.status='released'
UNION ALL
-- ⑥ 未退料待结算（S4 开票前）
SELECT 'unreturned', '未退料待结算',
       u.display_name || ' ×' || u.qty_unreturned || '（' || u.holder || '）',
       '结算并计入 S4 变更', '财务',
       lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
       now(), 0, false, 'amber'
  FROM v_unreturned_to_variation u JOIN v_project_label lb ON lb.project_id=u.project_id
UNION ALL
-- ⑦ 维护单未结案
SELECT 'maint_open', '维护单未结案',
       c.title, CASE WHEN c.fault_cause IS NULL THEN '★需补填故障归因才能结案'
                     ELSE '按归因与工时定价开票' END, '运维／财务',
       lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
       c.created_at,
       EXTRACT(EPOCH FROM (now()-c.created_at))/3600.0,
       (now() - c.created_at) > interval '14 days',
       CASE WHEN c.fault_cause IS NULL THEN 'red' ELSE 'amber' END
  FROM maintenance_case c JOIN v_project_label lb ON lb.project_id=c.project_id
 WHERE c.status NOT IN ('paid_closed','void')
UNION ALL
-- ⑧ RMA 在供应商处未返还
SELECT 'rma_at_supplier', 'RMA 在供应商处未返还',
       r.rma_no || ' · ' || r.display_name, '催供应商换修返还', '采购',
       r.pj_code, r.pj_label, r.pj_suburb, r.pj_addr,
       r.supplier_sent_at,
       EXTRACT(EPOCH FROM (now()-r.supplier_sent_at))/3600.0,
       (now() - r.supplier_sent_at) > interval '30 days', 'amber'
  FROM v_rma_board r
 WHERE r.disposition='to_supplier' AND NOT r.supplier_returned AND r.supplier_sent_at IS NOT NULL
UNION ALL
-- ⑨ 盘点待审批（真公司级）
SELECT 'stocktake', '盘点待审批',
       st.take_no || COALESCE('（'||st.scope_note||'）',''), '复核并审批盘亏', '工程管理',
       '公司级', '★ 公司级事项（全仓/抽仓盘点）', NULL, NULL,
       st.started_at,
       EXTRACT(EPOCH FROM (now()-st.started_at))/3600.0,
       (now() - st.started_at) > interval '24 hours', 'amber'
  FROM stocktake st WHERE st.status='pending_approval'
UNION ALL
-- ⑩ 问题上报（明确区分项目级与公司级）
SELECT 'issue', '问题上报待处理',
       i.issue_type_cn || '｜' || left(i.description, 40), '按类型分派处理', '工程管理',
       i.pj_code, i.pj_label, i.pj_suburb, i.pj_addr,
       i.created_at,
       EXTRACT(EPOCH FROM (now()-i.created_at))/3600.0,
       (now() - i.created_at) > interval '7 days', 'amber'
  FROM v_daily_issue_detail i;
COMMENT ON VIEW v_open_tasks IS
  '悬而未决总表：所有挂起/待处理的事。★每行必须能说清是哪个项目，或明确标「公司级」，不留空白';

-- 部门交接与通知的「公司级」显示：自动追加块已给它们加了 pj_*，
-- 为空即表示公司级事项；界面上用 COALESCE(pj_label,'★ 公司级事项') 呈现，
-- 不再重定义视图（避免与自动追加的列顺序冲突）。v_open_tasks 里已按此处理。

DO $$
DECLARE v record;
BEGIN
  FOR v IN SELECT c.relname FROM pg_class c
            WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
              AND (c.reloptions IS NULL OR NOT ('security_invoker=true' = ANY(c.reloptions)))
  LOOP EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', v.relname); END LOOP;
END $$;

-- 新增断言
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES
('INV-UI-03','问题上报必须落到项目，或明确标为公司级','high',
 $q$SELECT i.id, i.issue_type, left(i.description,40) AS description
      FROM daily_issue i
     WHERE NOT i.is_company_level AND i.project_id IS NULL$q$,
 '挂起的问题追不回项目，管理人员不知道去处理谁'),
('INV-UI-04','挂起的日结工资必须能追出当天派工项目','medium',
 $q$SELECT d.staff_name, d.work_date FROM v_daily_payroll_detail d
     WHERE d.status='unrecorded_held' AND d.project_count = 0$q$,
 '当天既无打卡也无派工 → 负责人补录时无从下手，需人工确认那天到底去了哪'),
('INV-UI-05','悬而未决总表每行都必须有项目标识或明确公司级','high',
 $q$SELECT kind, title FROM v_open_tasks
     WHERE (pj_code IS NULL AND scope='project')     -- 声称属于项目却没编号
        OR scope IS NULL$q$,
 '这是项目管理平台，挂起的事不能不知道属于哪个项目。'
 '公司级/无从追溯不算违规，但必须明确标记（由 INV-PJ-08 守前三列非空）');


-- #####################################################################
-- ##  v0.30：项目归属三态规范（全系统贯彻）
-- ##
-- ##  规则：系统内所有【流水／报告／报表／通知／任务／成本／收款／付款／
-- ##        报销／收入／支出／利润】必须有具体项目，例外只有两种：
-- ##          · company     公司级（明确标记）
-- ##          · untraceable 无从追溯（明确标记）
-- ##        ★ 两种例外都必须【明确标记】，绝不许靠留空糊过去。
-- #####################################################################

-- ═══════ 一、三态类型与统一约束 ═══════
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_type WHERE typname='project_scope') THEN
    CREATE TYPE project_scope AS ENUM ('project','company','untraceable');
  END IF;
END $$;
COMMENT ON TYPE project_scope IS
  'project=属于具体项目（必须填 project_id）｜company=公司级｜untraceable=无从追溯（需人工确认）';

-- ★ 归属登记表：每张表属于哪一类，既是权威依据也是文档
CREATE TABLE project_scope_registry (
    table_name   text PRIMARY KEY,
    kind         text NOT NULL CHECK (kind IN
                   ('project_required','project_or_scope','via_parent','cross_project',
                    'company_level','person_level','config')),
    kind_cn      text NOT NULL,
    trace_path   text,          -- 怎么追回项目
    note         text
);
INSERT INTO project_scope_registry(table_name,kind,kind_cn,trace_path,note) VALUES
-- 项目必填
('project_party','project_required','项目必填','project_id',NULL),
('payment_remind_log','project_required','项目必填','milestone_id→payment_milestone.project_id','v0.33 催款记录：经收款节点追到项目'),
('household_member','project_required','项目必填','project_id',NULL),
('solution_option','project_required','项目必填','project_id',NULL),
('site_meeting','project_required','项目必填','project_id',NULL),
('install_item','project_required','项目必填','project_id',NULL),
('install_job','project_required','项目必填','project_id',NULL),
('handover_job','project_required','项目必填','project_id',NULL),
('delivery_review','project_required','项目必填','project_id',NULL),
('variation','project_required','项目必填','project_id','变更＝收入'),
('maintenance_case','project_required','项目必填','project_id','维护收入与成本'),
('maintenance_job','project_required','项目必填','project_id',NULL),
('subscription','project_required','项目必填','project_id','订阅收入（不计入利润率）'),
('payment_milestone','project_required','项目必填','project_id','★收款/付款/开票'),
('stock_out','project_required','项目必填','project_id','★物料成本落项目的时刻'),
('stock_return','project_required','项目必填','project_id',NULL),
('rma_case','project_required','项目必填','project_id','★RMA 修理费与运费'),
('work_log','project_required','项目必填','project_id','★人工成本'),
('document_issue','project_required','项目必填','project_id',NULL),
('procurement','project_required','项目必填','project_id','旧表，保留'),
-- 项目 or 明确标记
('daily_issue','project_or_scope','项目 或 明确公司级','project_id / is_company_level','问题上报'),
('dept_handoff','project_or_scope','项目 或 明确公司级','project_id / scope','部门交接'),
('notification','project_or_scope','项目 或 明确公司级','project_id / scope','★所有通知'),
('handoff_log','project_or_scope','项目 或 明确公司级','project_id / scope',NULL),
('expense_claim','project_or_scope','项目 或 明确公司级','project_id / scope','★报销'),
-- 经父表可追
('payment_receipt','via_parent','经父表可追','milestone_id → payment_milestone.project_id','★收款明细'),
('stock_out_line','via_parent','经父表可追','stock_out_id → stock_out.project_id','★物料成本明细'),
('stock_return_line','via_parent','经父表可追','return_id → stock_return.project_id',NULL),
('job_checklist','via_parent','经父表可追','job_id → 各任务表.project_id',NULL),
('purchase_order_line','via_parent','经父表可追','—（采购单本身公司级）','入库不落项目'),
('stocktake_line','via_parent','经父表可追','—（盘点公司级）',NULL),

-- 跨项目（一人一天多项目）
('work_log','cross_project','跨项目','project_id 必填，按天汇总跨多项目',NULL),
('daily_report','cross_project','跨项目·可追','v_daily_projects（当天派工+打卡）','每日上报'),
('daily_payroll','cross_project','跨项目·可追','v_daily_projects','★日结工资=人工成本'),
('payroll_month','cross_project','跨项目·可追','v_payroll_month_projects（周期内各项目工时占比）','★月工资单'),
('toil_ledger','cross_project','跨项目·可追','ref_payroll_id → 当天项目','倒休'),
('travel_estimate','cross_project','跨项目·可追','from_project_id / to_project_id','路程成本摊下一站'),
-- 公司级
('purchase_order','company_level','公司级','—','买货时还不知给哪个项目'),
('stocktake','company_level','公司级','—','全仓/抽仓盘点'),
('material','company_level','公司级','—','物料主数据'),
('fx_rate','company_level','公司级','—','汇率'),
('termination_settlement','company_level','公司级·人员','staff_id','离职清算'),
-- 人员级
('eng_staff','person_level','人员级','—',NULL),
('staff_daily_commitment','person_level','人员级','—','外包参考时间'),
('app_account','person_level','人员级','—',NULL),
('account_department','person_level','人员级','—',NULL),
('account_reset_log','person_level','人员级','—',NULL),
('auth_otp','person_level','人员级','—',NULL),
-- 配置与主数据
('project','config','项目主表','—',NULL),
('eng_setting','config','配置','—',NULL),
('public_holiday','config','配置','—',NULL),
('sm_template','config','配置','—',NULL),
('document','config','配置','—',NULL),
('document_version','config','配置','—',NULL),
('document_binding','config','配置','—',NULL),
('dept_handoff_rule','config','配置','—',NULL),
('status_stall_threshold','config','配置','—',NULL),
('table_ownership','config','配置','—',NULL),
('money_visibility','config','配置','—',NULL),
('project_scope_registry','config','配置','—','本表'),
('assertion_def','config','配置','—',NULL),
('audit_log','config','审计','row_id',NULL)
ON CONFLICT (table_name) DO NOTHING;


-- ═══════ 二、三态化：通知 / 交接 / 留痕 不许留空 ═══════
ALTER TABLE notification  ADD COLUMN scope project_scope NOT NULL DEFAULT 'project';
ALTER TABLE dept_handoff  ADD COLUMN scope project_scope NOT NULL DEFAULT 'project';
ALTER TABLE handoff_log   ADD COLUMN scope project_scope NOT NULL DEFAULT 'project';
ALTER TABLE notification  ADD COLUMN scope_reason text;
ALTER TABLE dept_handoff  ADD COLUMN scope_reason text;
ALTER TABLE handoff_log   ADD COLUMN scope_reason text;

-- 已有数据：没项目的一律标公司级（历史数据兜底）
UPDATE notification SET scope='company' WHERE project_id IS NULL;
UPDATE dept_handoff SET scope='company' WHERE project_id IS NULL;
UPDATE handoff_log  SET scope='company' WHERE project_id IS NULL;

ALTER TABLE notification ADD CONSTRAINT ck_notif_scope CHECK (
    (scope='project' AND project_id IS NOT NULL) OR
    (scope <> 'project' AND scope_reason IS NOT NULL) OR
    (scope = 'company'));
ALTER TABLE dept_handoff ADD CONSTRAINT ck_handoff_scope CHECK (
    (scope='project' AND project_id IS NOT NULL) OR scope <> 'project');
ALTER TABLE handoff_log ADD CONSTRAINT ck_hlog_scope CHECK (
    (scope='project' AND project_id IS NOT NULL) OR scope <> 'project');

-- 写入时自动定态：有项目=project；无项目必须显式给 scope，否则拒
CREATE OR REPLACE FUNCTION trg_scope_autoset() RETURNS trigger AS $$
BEGIN
    IF NEW.project_id IS NOT NULL THEN
        NEW.scope := 'project';
    ELSIF NEW.scope = 'project' THEN
        RAISE EXCEPTION '门禁：% 没有项目，必须明确标为 company(公司级) 或 untraceable(无从追溯)，'
                        '不能留空。这是项目管理平台 —— 挂起的事必须说得清属于哪个项目', TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER notif_scope BEFORE INSERT OR UPDATE ON notification
    FOR EACH ROW EXECUTE FUNCTION trg_scope_autoset();
CREATE TRIGGER handoff_scope BEFORE INSERT OR UPDATE ON dept_handoff
    FOR EACH ROW EXECUTE FUNCTION trg_scope_autoset();
CREATE TRIGGER hlog_scope BEFORE INSERT OR UPDATE ON handoff_log
    FOR EACH ROW EXECUTE FUNCTION trg_scope_autoset();

-- 交接规则表标明哪些事件天然是公司级
ALTER TABLE dept_handoff_rule ADD COLUMN default_scope project_scope NOT NULL DEFAULT 'project';
UPDATE dept_handoff_rule SET default_scope='company'
 WHERE event_key IN ('stocktake_pending','reorder_alert',
 -- ★v0.36 修（30 号回归撞出来的真 bug）：集中采购到货天然没有项目
 --   （物料是在【出库】那一刻才落到项目上的）。原来 po_arrived 是 'project'，
 --   于是集中采购一标到货就被项目归属三态门禁拒掉 —— 整条集中采购流程走不通。
                      'po_arrived');

-- fn_notify_dept 按规则定态
CREATE OR REPLACE FUNCTION fn_notify_dept(
    p_event_key text, p_project_id uuid,
    p_ref_kind text DEFAULT NULL, p_ref_id uuid DEFAULT NULL, p_extra text DEFAULT NULL
) RETURNS uuid AS $$
DECLARE r dept_handoff_rule%ROWTYPE; pcode text; hid uuid;
        body text; acct record; n int := 0; sc project_scope;
BEGIN
    SELECT * INTO r FROM dept_handoff_rule WHERE event_key = p_event_key AND active;
    IF r.id IS NULL THEN RETURN NULL; END IF;
    sc := CASE WHEN p_project_id IS NOT NULL THEN 'project'::project_scope
               ELSE r.default_scope END;
    -- 规则说这事必须挂项目，调用方却没给 —— 与其让通用门禁报一句看不懂的话，不如在这儿说清楚
    IF p_project_id IS NULL AND sc = 'project' THEN
        RAISE EXCEPTION '门禁：交接事件「%」按规则必须挂具体项目，但调用时没有项目。'
                        '如果这类事件本来就可能没有项目（如集中采购），'
                        '请在 dept_handoff_rule 里把它的 default_scope 改成 company', r.event_label;
    END IF;
    SELECT code INTO pcode FROM project WHERE id = p_project_id;

    body := '【KONNEXT】'
         || COALESCE('项目 '||pcode||'：', CASE WHEN sc='company' THEN '公司级：' ELSE '' END)
         || r.event_label || E'\n'
         || '→ 请' || CASE r.to_dept
              WHEN 'presales' THEN '售前' WHEN 'eng_mgmt' THEN '工程管理'
              WHEN 'procurement' THEN '采购' WHEN 'warehouse' THEN '库管'
              WHEN 'finance' THEN '财务' WHEN 'maintenance' THEN '运维'
              ELSE '各部门' END
         || '：' || r.action_needed
         || COALESCE(E'\n' || p_extra, '')
         || CASE WHEN r.sla_hours IS NOT NULL
                 THEN E'\n建议 ' || r.sla_hours || ' 小时内处理。' ELSE '' END;

    INSERT INTO dept_handoff(project_id, event_key, ref_kind, ref_id,
                             from_dept, to_dept, message, scope)
    VALUES (p_project_id, p_event_key, p_ref_kind, p_ref_id,
            r.from_dept, r.to_dept, body, sc)
    RETURNING id INTO hid;

    FOR acct IN
        SELECT a.id, a.phone, a.email, a.full_name FROM app_account a
         WHERE a.active AND a.tier = 2
           AND (r.to_dept='all' OR EXISTS(SELECT 1 FROM account_department d
                           WHERE d.account_id=a.id AND d.department=r.to_dept))
    LOOP
        IF r.channel IN ('sms','both') AND acct.phone IS NOT NULL THEN
            INSERT INTO notification(project_id, ref_kind, ref_id, channel, recipient,
                                     subject, body, status, triggered_by, scope, scope_reason)
            VALUES (p_project_id,'dept_handoff',hid,'sms',acct.phone,r.event_label,body,'queued',
                    COALESCE(current_setting('app.actor',true),'system'), sc,
                    CASE WHEN sc<>'project' THEN '交接事件「'||r.event_label||'」天然为公司级' END);
            n := n+1;
        END IF;
        IF r.channel IN ('email','both') AND acct.email IS NOT NULL THEN
            INSERT INTO notification(project_id, ref_kind, ref_id, channel, recipient,
                                     subject, body, status, triggered_by, scope, scope_reason)
            VALUES (p_project_id,'dept_handoff',hid,'email','【KONNEXT】'||r.event_label,
                    r.event_label,body,'queued',
                    COALESCE(current_setting('app.actor',true),'system'), sc,
                    CASE WHEN sc<>'project' THEN '交接事件「'||r.event_label||'」天然为公司级' END);
            n := n+1;
        END IF;
    END LOOP;

    INSERT INTO handoff_log(project_id, from_party, to_party, node, message, scope, scope_reason)
    VALUES (p_project_id, r.from_dept, r.to_dept, p_event_key,
            r.event_label || ' → ' || r.action_needed || '（已通知 ' || n || ' 人）', sc,
            CASE WHEN sc<>'project' THEN '公司级交接事件' END);
    RETURN hid;
END;
$$ LANGUAGE plpgsql;


-- ═══════ 三、报销 expense_claim（★契约原先完全没有） ═══════
CREATE TABLE expense_claim (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    claim_no      text UNIQUE NOT NULL,
    claimant_staff_id uuid NOT NULL REFERENCES eng_staff(id),
    -- ★ 项目归属三态
    project_id    uuid REFERENCES project(id),
    scope         project_scope NOT NULL DEFAULT 'project',
    scope_reason  text,                        -- 公司级/无从追溯时必填原因
    claim_date    date NOT NULL DEFAULT current_date,
    -- ★ v0.34 三类正名（材料补购/工具采购/交通递送）——餐费办公等其他费用不走本系统
    category      text NOT NULL CHECK (category IN ('material','tool','transport')),
    amount_aud    numeric(12,2) NOT NULL CHECK (amount_aud > 0),
    gst_amount    numeric(12,2) NOT NULL DEFAULT 0,
    receipt_url   text,                        -- 收据照片
    description   text,
    -- ★ v0.34 付款不走本系统：无「已付」状态、无付款列——审批与留档为止，怎么付钱线下自行安排
    status        text NOT NULL DEFAULT 'draft' CHECK (status IN
                    ('draft','submitted','approved','rejected')),
    submitted_at  timestamptz,
    approved_by   uuid REFERENCES app_account(id),
    approved_at   timestamptz,
    reject_reason text,
    note          text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_claim_scope CHECK (
        (scope='project' AND project_id IS NOT NULL) OR
        (scope <> 'project' AND scope_reason IS NOT NULL)),
    CONSTRAINT ck_claim_reject CHECK (status <> 'rejected' OR reject_reason IS NOT NULL)
);
CREATE INDEX idx_claim_project ON expense_claim(project_id);
CREATE INDEX idx_claim_staff ON expense_claim(claimant_staff_id, claim_date);
COMMENT ON TABLE expense_claim IS
  '报销：★必须落到项目，或明确标为公司级/无从追溯并填原因。已批准的报销进项目成本；付款不走本系统（v0.34 无已付状态）';

CREATE OR REPLACE FUNCTION trg_claim_gate() RETURNS trigger AS $$
DECLARE acct app_account%ROWTYPE; my_staff uuid;
BEGIN
    IF NEW.project_id IS NOT NULL THEN NEW.scope := 'project'; END IF;
    IF NEW.project_id IS NULL AND NEW.scope='project' THEN
        RAISE EXCEPTION '门禁：报销必须落到具体项目；确实无法归属的请标为公司级或无从追溯并填写原因';
    END IF;
    -- 提交
    IF NEW.status='submitted' AND (TG_OP='INSERT' OR OLD.status IS DISTINCT FROM 'submitted') THEN
        IF NEW.receipt_url IS NULL THEN
            RAISE EXCEPTION '门禁：报销必须上传收据照片';
        END IF;
        NEW.submitted_at := COALESCE(NEW.submitted_at, now());
    END IF;
    -- 审批：不能自己批自己
    IF NEW.status IN ('approved','rejected') AND OLD.status IS DISTINCT FROM NEW.status THEN
        IF NEW.approved_by IS NULL THEN
            RAISE EXCEPTION '门禁：审批报销必须记录审批人';
        END IF;
        SELECT * INTO acct FROM app_account WHERE id = NEW.approved_by;
        IF acct.staff_id IS NOT NULL AND acct.staff_id = NEW.claimant_staff_id THEN
            RAISE EXCEPTION '门禁：不能自己审批自己的报销（%）', acct.full_name;
        END IF;
        NEW.approved_at := COALESCE(NEW.approved_at, now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER claim_gate BEFORE INSERT OR UPDATE ON expense_claim
    FOR EACH ROW EXECUTE FUNCTION trg_claim_gate();
CREATE TRIGGER claim_audit AFTER INSERT OR UPDATE OR DELETE ON expense_claim
    FOR EACH ROW EXECUTE FUNCTION trg_audit();

INSERT INTO table_ownership(table_name, write_dept, note) VALUES
 ('expense_claim', ARRAY['finance','eng_mgmt'], '员工提报由工程管理代录；审批与付款归财务'),
 ('project_scope_registry', ARRAY['eng_mgmt'], '项目归属登记表')
ON CONFLICT (table_name) DO NOTHING;

ALTER TABLE expense_claim ENABLE ROW LEVEL SECURITY;
CREATE POLICY claim_read ON expense_claim FOR SELECT
  USING (fn_can_see_margin() OR fn_is_admin()
         OR (fn_is_field() AND claimant_staff_id = fn_my_staff_id())
         OR (NOT fn_is_field() AND false));
CREATE POLICY claim_write ON expense_claim FOR ALL
  USING (fn_can_write('expense_claim')
         OR (fn_is_field() AND claimant_staff_id = fn_my_staff_id()))
  WITH CHECK (fn_can_write('expense_claim')
         OR (fn_is_field() AND claimant_staff_id = fn_my_staff_id()));


-- ═══════ 四、月工资单与路程：补上项目追溯 ═══════
-- 月工资单按周期内各项目的工时占比拆分（人工成本落项目的依据）
CREATE VIEW v_payroll_month_projects AS
WITH span AS (
    SELECT m.id AS payroll_month_id, m.staff_id, m.period_start, m.period_end,
           m.paid_min, m.total_amount
      FROM payroll_month m
), hrs AS (
    SELECT s.payroll_month_id, s.staff_id, w.project_id,
           SUM(EXTRACT(EPOCH FROM (w.checkout_at-w.checkin_at))/60.0) AS mins
      FROM span s
      JOIN work_log w ON w.staff_id=s.staff_id
       AND w.checkin_at::date BETWEEN s.period_start AND s.period_end
       AND w.checkin_at IS NOT NULL AND w.checkout_at IS NOT NULL
     GROUP BY s.payroll_month_id, s.staff_id, w.project_id
)
SELECT h.payroll_month_id, h.staff_id, st.name AS staff_name,
       s.period_start, s.period_end,
       lb.project_id, lb.code AS pj_code, lb.display_label AS pj_label,
       lb.addr_suburb AS pj_suburb, lb.addr_full AS pj_addr,
       round(h.mins,1) AS minutes_on_project,
       round(h.mins / NULLIF(SUM(h.mins) OVER (PARTITION BY h.payroll_month_id),0) * 100, 1) AS share_pct,
       CASE WHEN fn_can_see_salary() THEN
         round(COALESCE(s.total_amount,0)
             * h.mins / NULLIF(SUM(h.mins) OVER (PARTITION BY h.payroll_month_id),0), 2)
       END AS allocated_amount
  FROM hrs h
  JOIN span s ON s.payroll_month_id=h.payroll_month_id
  JOIN v_project_label lb ON lb.project_id=h.project_id
  LEFT JOIN eng_staff st ON st.id=h.staff_id;
COMMENT ON VIEW v_payroll_month_projects IS
  '月工资单拆到项目：按周期内各项目工时占比分摊。月工资单本身跨项目，靠这个追回';

-- 路程预估带出项目标识（from/to 两头）
CREATE VIEW v_travel_estimate_detail AS
SELECT t.id, t.staff_id, s.name AS staff_name, t.travel_date, t.seq, t.kind,
       t.depart_at, t.duration_min, t.distance_m, t.avoid_tolls, t.provider, t.queried_at,
       f.code AS from_pj_code, f.display_label AS from_pj_label, f.addr_suburb AS from_pj_suburb,
       o.code AS to_pj_code,   o.display_label AS to_pj_label,   o.addr_suburb AS to_pj_suburb,
       -- ★路上成本摊给下一站 → 项目归属看 to_project
       o.project_id AS pj_id, o.code AS pj_code, o.display_label AS pj_label,
       o.addr_suburb AS pj_suburb, o.addr_full AS pj_addr
  FROM travel_estimate t
  LEFT JOIN eng_staff s ON s.id=t.staff_id
  LEFT JOIN v_project_label f ON f.project_id=t.from_project_id
  LEFT JOIN v_project_label o ON o.project_id=t.to_project_id;


-- ═══════ 五、报销进项目成本 + 利润率纳入 ═══════
CREATE VIEW v_project_expense AS
SELECT c.project_id, lb.code AS pj_code, lb.display_label AS pj_label,
       lb.addr_suburb AS pj_suburb, lb.addr_full AS pj_addr,
       count(*)                                            AS claim_count,
       CASE WHEN fn_can_see_margin() THEN round(SUM(c.amount_aud),2) END AS expense_total,
       CASE WHEN fn_can_see_margin() THEN
         round(SUM(c.amount_aud) FILTER (WHERE c.status='approved'),2) END AS expense_approved,
       CASE WHEN fn_can_see_margin() THEN
         round(SUM(c.amount_aud) FILTER (WHERE c.status IN ('submitted','approved')),2) END AS expense_pending
  FROM expense_claim c
  JOIN v_project_label lb ON lb.project_id=c.project_id
 WHERE c.status IN ('submitted','approved') AND c.scope='project'
 GROUP BY c.project_id, lb.code, lb.display_label, lb.addr_suburb, lb.addr_full;

-- 公司级报销（不摊项目，单列）
CREATE VIEW v_company_expense AS
SELECT c.scope, c.scope_reason, c.category, count(*) AS claim_count,
       CASE WHEN fn_can_see_margin() THEN round(SUM(c.amount_aud),2) END AS expense_total
  FROM expense_claim c
 WHERE c.scope <> 'project' AND c.status IN ('submitted','approved')
 GROUP BY c.scope, c.scope_reason, c.category;


-- ═══════ 六、待办：★项目编号 + 项目地址放最前 ═══════
DROP VIEW IF EXISTS v_open_tasks;
CREATE VIEW v_open_tasks AS
WITH raw AS (
  SELECT 'handoff'::text AS kind, '部门交接待响应'::text AS kind_cn,
         h.pj_code, h.pj_label, h.pj_suburb, h.pj_addr,
         h.event_label AS title, h.action_needed AS action, h.to_dept_cn AS owner,
         h.raised_at AS since, h.waiting_hours::numeric AS waiting_hours, h.overdue,
         CASE WHEN hh.scope='project' THEN 'project'
              WHEN hh.scope='company' THEN 'company' ELSE 'untraceable' END::text AS scope
    FROM v_pending_handoff h
    JOIN dept_handoff hh ON hh.id = h.id
  UNION ALL
  SELECT 'payroll_held','日结未记录·挂起不发',
         CASE WHEN d.project_count=0 THEN NULL ELSE split_part(d.project_codes,' / ',1) END,
         CASE WHEN d.project_count=1 THEN d.project_labels
              WHEN d.project_count>1 THEN '跨 '||d.project_count||' 个项目：'||d.project_codes
              ELSE NULL END,
         d.project_suburbs, NULL,
         d.staff_name || ' · ' || d.work_date,
         COALESCE(d.backfill_hint,'待负责人补录'), '工程管理',
         d.work_date::timestamptz, (now()::date - d.work_date)*24.0,
         (now()::date - d.work_date) > 7,
         CASE WHEN d.project_count=0 THEN 'untraceable' ELSE 'project' END
    FROM v_daily_payroll_detail d WHERE d.status='unrecorded_held'
  UNION ALL
  SELECT 'variation','变更待估价', lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
         v.change_type||'｜'||COALESCE(v.description,''), '外部算完后填回结算金额','财务',
         v.created_at, EXTRACT(EPOCH FROM (now()-v.created_at))/3600.0,
         (now()-v.created_at) > interval '48 hours', 'project'
    FROM variation v JOIN v_project_label lb ON lb.project_id=v.project_id
   WHERE v.billable AND v.settle_amount IS NULL
  UNION ALL
  SELECT 'install_pending','安装剩余待处理', lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
         i.title||COALESCE('（'||i.area||'）',''), '做完 / 取消 / 挂起 / 转变更','工程管理',
         i.created_at, EXTRACT(EPOCH FROM (now()-i.created_at))/3600.0,
         (now()-i.created_at) > interval '30 days', 'project'
    FROM install_item i JOIN v_project_label lb ON lb.project_id=i.project_id
   WHERE i.status='pending'
  UNION ALL
  SELECT 'stock_unconfirmed','出库待提货人确认', lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
         so.out_no||' · '||COALESCE(so.receiver_name,''), '短信回 YES 或人工确认','库管',
         so.released_at, EXTRACT(EPOCH FROM (now()-so.released_at))/3600.0,
         (now()-so.released_at) > interval '72 hours', 'project'
    FROM stock_out so JOIN v_project_label lb ON lb.project_id=so.project_id
   WHERE so.status='released'
  UNION ALL
  SELECT 'unreturned','未退料待结算', lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
         u.display_name||' ×'||u.qty_unreturned||'（'||u.holder||'）',
         '结算并计入 S4 变更','财务', now(), 0, false, 'project'
    FROM v_unreturned_to_variation u JOIN v_project_label lb ON lb.project_id=u.project_id
  UNION ALL
  SELECT 'maint_open','维护单未结案', lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
         c.title, CASE WHEN c.fault_cause IS NULL THEN '★需补填故障归因才能结案'
                       ELSE '按归因与工时定价开票' END, '运维／财务',
         c.created_at, EXTRACT(EPOCH FROM (now()-c.created_at))/3600.0,
         (now()-c.created_at) > interval '14 days', 'project'
    FROM maintenance_case c JOIN v_project_label lb ON lb.project_id=c.project_id
   WHERE c.status NOT IN ('paid_closed','void')
  UNION ALL
  SELECT 'rma_at_supplier','RMA 在供应商处未返还', r.pj_code, r.pj_label, r.pj_suburb, r.pj_addr,
         r.rma_no||' · '||r.display_name, '催供应商换修返还','采购',
         r.supplier_sent_at, EXTRACT(EPOCH FROM (now()-r.supplier_sent_at))/3600.0,
         (now()-r.supplier_sent_at) > interval '30 days', 'project'
    FROM v_rma_board r
   WHERE r.disposition='to_supplier' AND NOT r.supplier_returned AND r.supplier_sent_at IS NOT NULL
  UNION ALL
  SELECT 'stocktake','盘点待审批', NULL, NULL, NULL, NULL,
         st.take_no||COALESCE('（'||st.scope_note||'）',''), '复核并审批盘亏','工程管理',
         st.started_at, EXTRACT(EPOCH FROM (now()-st.started_at))/3600.0,
         (now()-st.started_at) > interval '24 hours', 'company'
    FROM stocktake st WHERE st.status='pending_approval'
  UNION ALL
  SELECT 'issue','问题上报待处理', i.pj_code, i.pj_label, i.pj_suburb, i.pj_addr,
         i.issue_type_cn||'｜'||left(i.description,40), '按类型分派处理','工程管理',
         i.created_at, EXTRACT(EPOCH FROM (now()-i.created_at))/3600.0,
         (now()-i.created_at) > interval '7 days',
         CASE WHEN i.is_company_level THEN 'company' ELSE 'project' END
    FROM v_daily_issue_detail i
  UNION ALL
  SELECT 'expense','报销待审批',
         lb.code, lb.display_label, lb.addr_suburb, lb.addr_full,
         c.claim_no||' · '||s.name||' · '||c.category, '审批（不能自己批自己）','财务',
         c.submitted_at, EXTRACT(EPOCH FROM (now()-c.submitted_at))/3600.0,
         (now()-c.submitted_at) > interval '72 hours',
         c.scope::text
    FROM expense_claim c
    LEFT JOIN v_project_label lb ON lb.project_id=c.project_id
    LEFT JOIN eng_staff s ON s.id=c.claimant_staff_id
   WHERE c.status='submitted'
)
-- ★ 项目编号与项目地址放最前两列
SELECT COALESCE(r.pj_code,
         CASE r.scope WHEN 'company' THEN '公司级' ELSE '★无从追溯' END)      AS 项目编号,
       COALESCE(r.pj_addr, r.pj_suburb,
         CASE r.scope WHEN 'company' THEN '（公司级事项·不属于单个项目）'
                      ELSE '★（无从追溯·需人工确认）' END)                    AS 项目地址,
       COALESCE(r.pj_label,
         CASE r.scope WHEN 'company' THEN '公司级事项' ELSE '★无从追溯' END)   AS 项目标识,
       r.scope, r.kind, r.kind_cn, r.title, r.action, r.owner,
       r.since, round(r.waiting_hours,1) AS waiting_hours, r.overdue,
       r.pj_code, r.pj_label, r.pj_suburb, r.pj_addr,
       CASE WHEN r.scope='untraceable' THEN 'red'
            WHEN r.overdue THEN 'red' WHEN r.scope='company' THEN 'grey'
            ELSE 'amber' END AS color_token
  FROM raw r;
COMMENT ON VIEW v_open_tasks IS
  '悬而未决总表。★前三列固定为 项目编号／项目地址／项目标识；'
  '无项目者显示「公司级」或「★无从追溯」，绝不留空';

-- #####################################################################
-- ##  v0.32：售前 UI 样板定稿对齐（2026-08-01 · 决策记录 §14）
-- #####################################################################

-- 售前设置三键（write_depts=售前，改动走 eng_setting 既有 RLS 与留痕）
INSERT INTO eng_setting(key, value_num, note, write_depts) VALUES
 ('pre_stage_remind_days', 3,
  '售前 6+1 前六步停留提醒阈值(天)：任一步停留满该天数起每天提醒一次，直到推进或流失。售前设置页自改',
  ARRAY['presales']);
INSERT INTO eng_setting(key, value_text, note, write_depts) VALUES
 ('pre_contact_roles',
  '["决策人","共同决策","介绍人","设计师","项目管理","亲属代理","其他"]',
  '联系人/关系人角色下拉选项(JSON数组)。售前设置页维护；删除选项不影响已填历史数据',
  ARRAY['presales']),
 ('pre_party_trades',
  '["设计师","Builder","电工","空调","地暖","泳池","影音室","转盘","电梯","其他"]',
  '参建方工种下拉选项(JSON数组)。售前设置页维护；删除选项不影响已填历史数据',
  ARRAY['presales']),
 -- v0.32b（二十轮）：立项建筑相关四类下拉同样设置化，替代原字段硬 CHECK
 ('pre_house_types',
  '["House","Duplex","Townhouse","Apartment","商铺","Villa","Granny Flat","空地","仓库"]',
  '房屋类型下拉选项(JSON数组)。售前设置页维护', ARRAY['presales']),
 ('pre_build_stages',
  '["DA","CC","拆除","地基","地下室","结构","Rough-in","翻新","其他"]',
  '施工阶段下拉选项(JSON数组)。售前设置页维护；build_stage 仍必填', ARRAY['presales']),
 ('pre_floor_uses',
  '["无","双砖","轻钢","木结构","混凝土","砖木","其他"]',
  '楼层用途下拉选项(JSON数组)。售前设置页维护', ARRAY['presales']),
 ('pre_roof_types',
  '["瓦顶","平顶","露台","其他"]',
  '屋顶类型下拉选项(JSON数组)。售前设置页维护', ARRAY['presales']);

-- v0.33 财务设置键（财务设置页维护；改动进审计）
INSERT INTO eng_setting(key, value_num, note, write_depts) VALUES
 ('gst_bank_pct',        10, 'GST 默认率%·走账（登记收款自动带出，每笔可手改；报税以会计为准）', ARRAY['finance']),
 ('gst_cash_pct',         0, 'GST 默认率%·现金（同上）', ARRAY['finance']),
 ('suspend_server_days', 90, '拒付停服后多少天提醒停用服务器（声明由市场发、人去执行）', ARRAY['finance']);
-- v0.33 催款模版 12 键（常规/最终 × 中/英 × 短信/邮件标题/邮件正文；花括号变量由应用层渲染）
-- ★对外催款不含项目昵称（用户定）——一律用完整地址 {项目地址} 标识项目
INSERT INTO eng_setting(key, value_text, note, write_depts) VALUES
 ('remind_tpl_normal_zh_sms','【KONNEXT】{付款人}您好，您位于 {项目地址} 的项目 {节点} {节点名}尚有 {还差金额} 未到账（Invoice {Invoice号} · {Invoice日期} 开出）。请您安排支付，如已付款请回 Y。—— 第 {催款次数} 次提醒','常规催款·中文·短信', ARRAY['finance']),
 ('remind_tpl_normal_zh_email_title','【KONNEXT 付款提醒】{项目编号} · {节点} {节点名} · 还差 {还差金额}（第 {催款次数} 次）','常规催款·中文·邮件标题', ARRAY['finance']),
 ('remind_tpl_normal_zh_email','{付款人}您好：您位于 {项目地址} 的项目，{节点} {节点名}应收 {应收金额}，已收 {已收金额}，尚有 {还差金额} 未到账。Invoice：{Invoice号}（{Invoice日期} 开出 · {版本}）。请您近期安排支付；如已付款请忽略本邮件并告知我们。本邮件发出即视为送达，无需回复。KONNEXT 财务部 · {联系电话}','常规催款·中文·邮件正文', ARRAY['finance']),
 ('remind_tpl_normal_en_sms','KONNEXT: Dear {付款人}, invoice {Invoice号} ({Invoice日期}) for the {节点} {节点名} of your project at {项目地址} has an outstanding balance of {还差金额}. Please arrange payment at your earliest convenience. Reply Y once paid. - Reminder #{催款次数}','常规催款·英文·短信', ARRAY['finance']),
 ('remind_tpl_normal_en_email_title','KONNEXT Payment Reminder - {项目编号} · {节点} {节点名} · {还差金额} outstanding (#{催款次数})','常规催款·英文·邮件标题', ARRAY['finance']),
 ('remind_tpl_normal_en_email','Dear {付款人}, this is a friendly reminder that invoice {Invoice号} ({Invoice日期} · {版本}) for the {节点} {节点名} of your project at {项目地址} shows an outstanding balance of {还差金额} (invoiced {应收金额}, received {已收金额}). Please arrange payment at your earliest convenience. If you have already paid, kindly disregard this email. This email is deemed delivered upon sending; no reply is required. KONNEXT Accounts · {联系电话}','常规催款·英文·邮件正文', ARRAY['finance']),
 ('remind_tpl_final_zh_sms','【KONNEXT · 最终催款】{付款人}您好，您位于 {项目地址} 的项目 {节点} {节点名} {还差金额} 已超期 {超期天数} 天（第 {催款次数} 次通知）。请于 7 日内付清，逾期将按合同暂停本项目全部服务。付款后请回 Y。','最终催款·中文·短信', ARRAY['finance']),
 ('remind_tpl_final_zh_email_title','【KONNEXT 最终催款函】{项目编号} · 超期 {超期天数} 天 · 请于 7 日内处理','最终催款·中文·邮件标题', ARRAY['finance']),
 ('remind_tpl_final_zh_email','{付款人}您好：这是关于您位于 {项目地址} 的项目 {节点} {节点名}的最终催款通知（第 {催款次数} 次）。应收 {应收金额} · 已收 {已收金额} · 未付 {还差金额}，自 Invoice {Invoice号}（{Invoice日期}）发出已超期 {超期天数} 天。请于 7 日内付清。逾期未付，我们将按合同约定暂停本项目全部服务，由此产生的工期与费用影响由业主承担。本邮件发出即视为送达。KONNEXT 财务部 · {联系电话}','最终催款·中文·邮件正文', ARRAY['finance']),
 ('remind_tpl_final_en_sms','KONNEXT FINAL NOTICE: Dear {付款人}, {还差金额} for the {节点} {节点名} of your project at {项目地址} is {超期天数} days overdue (notice #{催款次数}). Please settle within 7 days, otherwise all services for this project will be suspended per contract. Reply Y once paid.','最终催款·英文·短信', ARRAY['finance']),
 ('remind_tpl_final_en_email_title','KONNEXT FINAL NOTICE - {项目编号} · {超期天数} days overdue · action required within 7 days','最终催款·英文·邮件标题', ARRAY['finance']),
 ('remind_tpl_final_en_email','Dear {付款人}, this is the final notice (#{催款次数}) regarding the {节点} {节点名} of your project at {项目地址}. Invoiced {应收金额} · received {已收金额} · outstanding {还差金额}, now {超期天数} days overdue since invoice {Invoice号} ({Invoice日期}). Please settle within 7 days. Failing this, all services for this project will be suspended in accordance with the contract, and any resulting delays and costs will be borne by the owner. This email is deemed delivered upon sending. KONNEXT Accounts · {联系电话}','最终催款·英文·邮件正文', ARRAY['finance']);

-- 86 售前管道（售前大表与内生提醒的数据源 —— 当前勾/停留/提醒全现算，金额按守卫遮罩）
CREATE VIEW v_presales_pipeline AS
SELECT p.id, p.code, p.display_label,
       p.created_at::date                            AS opened_on,   -- 立项时间：编号后的标配列
       p.name, p.addr_street, p.addr_suburb, p.addr_state,
       s.current_step,
       CASE WHEN p.status='bid_lost' THEN '已流失'
            ELSE (ARRAY['接洽中','设计中','报价中','修订中','待签约','已签约'])[s.current_step]
       END                                           AS stage_cn,
       (p.status='bid_lost')                         AS lost,
       p.step1_intro_at, p.step2_design_at, p.step3_review_at,
       p.step4_draft_at, p.step5_revise_at, p.step6_signed_at,
       s.last_tick_at,
       CASE WHEN p.status='bid_lost' OR s.current_step>=6 THEN NULL
            ELSE (now()::date - s.last_tick_at::date) END AS stay_days,   -- 现算不落库
       th.threshold_days                             AS remind_threshold_days,
       (p.status<>'bid_lost' AND s.current_step<6
        AND (now()::date - s.last_tick_at::date) >= th.threshold_days)    AS remind,
       p.quote_ext_id,                               -- 报价单号（待签约时填）
       CASE WHEN fn_can_see_customer_amount() THEN p.est_quote_low   END AS est_quote_low,
       CASE WHEN fn_can_see_customer_amount() THEN p.est_quote_high  END AS est_quote_high,
       CASE WHEN fn_can_see_customer_amount() THEN p.contract_price  END AS contract_price,
       CASE WHEN fn_can_see_customer_amount() THEN p.deposit_amount  END AS deposit_amount,
       p.deposit_paid_at,
       CASE WHEN fn_can_see_margin() THEN p.planned_labor_hours END AS planned_labor_hours,
       p.note_finance, p.note_finance_read_by, p.note_finance_read_at,
       p.note_eng,     p.note_eng_read_by,     p.note_eng_read_at,
       fn_can_see_customer_amount()                  AS amount_visible
  FROM project p
  CROSS JOIN LATERAL (SELECT
       CASE WHEN p.step6_signed_at IS NOT NULL THEN 6
            WHEN p.step5_revise_at IS NOT NULL THEN 5
            WHEN p.step4_draft_at  IS NOT NULL THEN 4
            WHEN p.step3_review_at IS NOT NULL THEN 3
            WHEN p.step2_design_at IS NOT NULL THEN 2
            ELSE 1 END AS current_step,
       COALESCE(p.step6_signed_at, p.step5_revise_at, p.step4_draft_at,
                p.step3_review_at, p.step2_design_at, p.step1_intro_at,
                p.created_at)      AS last_tick_at) s
  CROSS JOIN LATERAL (SELECT (SELECT value_num FROM eng_setting
                               WHERE key='pre_stage_remind_days') AS threshold_days) th;
COMMENT ON VIEW v_presales_pipeline IS
  '售前大表数据源（UI 契约 §14）。当前状态=最后一个勾；停留/提醒现算不落库；'
  '第⑦勾已流失=status bid_lost；金额列按 fn_can_see_customer_amount 遮罩（NULL→界面显 — —，不显 0）';

-- 每天提醒的通知生成：后端定时任务每天调用一次，取到的每行发一条提醒
-- · 一项目一条 = 同一通知不累积（视图现算，天然去重）
-- · 已知悉后状态一改 current_step 就变，这里自然重新出现 —— 与待办中心「状态一变重新提醒」一致
-- · 排序 = 超期最久置顶（待办中心同款）
CREATE OR REPLACE FUNCTION fn_presales_reminders_today()
RETURNS TABLE(project_id uuid, code text, display_label text,
              stage_cn text, stay_days integer, threshold_days numeric) AS $$
  SELECT id, code, display_label, stage_cn, stay_days, remind_threshold_days
    FROM v_presales_pipeline
   WHERE remind
   ORDER BY stay_days DESC;
$$ LANGUAGE sql STABLE;

DO $$
DECLARE v record;
BEGIN
  FOR v IN SELECT c.relname FROM pg_class c
            WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
              AND (c.reloptions IS NULL OR NOT ('security_invoker=true' = ANY(c.reloptions)))
  LOOP EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', v.relname); END LOOP;
END $$;

-- ═══════ 七、断言：全面守住"必须有项目，例外须明确标记" ═══════
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES
('INV-PJ-01','★通知必须有项目，或明确标为公司级/无从追溯','critical',
 $q$SELECT id, ref_kind, channel, recipient, subject FROM notification
     WHERE scope='project' AND project_id IS NULL$q$,
 '系统内所有通知都要有具体项目，例外必须明确标记'),
('INV-PJ-02','★部门交接必须有项目，或明确标为公司级','critical',
 $q$SELECT id, event_key, to_dept FROM dept_handoff
     WHERE scope='project' AND project_id IS NULL$q$, NULL),
('INV-PJ-03','★交接留痕必须有项目，或明确标为公司级','high',
 $q$SELECT id, node, from_party, to_party FROM handoff_log
     WHERE scope='project' AND project_id IS NULL$q$, NULL),
('INV-PJ-04','★报销必须有项目，或明确标为公司级/无从追溯并填原因','critical',
 $q$SELECT claim_no, category, amount_aud FROM expense_claim
     WHERE (scope='project' AND project_id IS NULL)
        OR (scope <> 'project' AND scope_reason IS NULL)$q$,
 '报销是成本，成本必须落项目'),
('INV-PJ-05','★收款明细必须能追回项目','critical',
 $q$SELECT r.id, r.amount FROM payment_receipt r
     LEFT JOIN payment_milestone m ON m.id=r.milestone_id
     WHERE m.project_id IS NULL$q$,
 '经 milestone_id → payment_milestone.project_id 追溯'),
('INV-PJ-06','★物料成本明细必须能追回项目','critical',
 $q$SELECT ol.id FROM stock_out_line ol
     LEFT JOIN stock_out so ON so.id=ol.stock_out_id
     WHERE so.project_id IS NULL$q$, NULL),
('INV-PJ-07','★所有承载金额的表都必须登记项目归属','high',
 $q$SELECT t.table_name FROM information_schema.tables t
     WHERE t.table_schema='public' AND t.table_type='BASE TABLE'
       AND EXISTS(SELECT 1 FROM information_schema.columns c
                   WHERE c.table_schema='public' AND c.table_name=t.table_name
                     AND (c.column_name LIKE '%amount%' OR c.column_name LIKE '%_cost%'
                          OR c.column_name LIKE '%price%' OR c.column_name LIKE '%_fee%'
                          OR c.column_name LIKE '%rate%'))
       AND NOT EXISTS(SELECT 1 FROM project_scope_registry r WHERE r.table_name=t.table_name)$q$,
 '在 project_scope_registry 里登记它属于哪一类，并写清怎么追回项目'),
('INV-PJ-08','★悬而未决总表：前三列必须是项目编号/地址/标识且不为空','critical',
 $q$SELECT kind, title FROM v_open_tasks
     WHERE 项目编号 IS NULL OR btrim(项目编号)=''
        OR 项目地址 IS NULL OR btrim(项目地址)=''$q$,
 '待办必须以项目编号与项目地址开头'),
('INV-PJ-09','★无从追溯的事项必须能被单独列出来处理','high',
 $q$SELECT 项目编号, kind_cn, title FROM v_open_tasks
     WHERE scope='untraceable' AND 项目地址 NOT LIKE '%无从追溯%'$q$,
 '无从追溯不是留空，是明确标记 + 提示人工确认'),
('INV-PJ-10','★项目归属登记表必须覆盖所有业务表','medium',
 $q$SELECT t.table_name FROM information_schema.tables t
     WHERE t.table_schema='public' AND t.table_type='BASE TABLE'
       AND t.table_name NOT LIKE 'pg_%'
       AND NOT EXISTS(SELECT 1 FROM project_scope_registry r WHERE r.table_name=t.table_name)$q$,
 '新增表必须在 project_scope_registry 里说明归属，否则没人知道它的流水属于哪个项目');

-- 登记表反向校验：不许登记不存在的表（曾误登记 expense_claim_line）
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES
('INV-PJ-11','项目归属登记表不得登记不存在的表','medium',
 $q$SELECT r.table_name FROM project_scope_registry r
     WHERE NOT EXISTS(SELECT 1 FROM information_schema.tables t
                       WHERE t.table_schema='public' AND t.table_type='BASE TABLE'
                         AND t.table_name=r.table_name)$q$,
 '登记了不存在的表 → 看着像有归属，实际那张表不存在');


-- =====================================================================
--  ★ v0.34 追加对象（2026-08-02 财务定稿清欠账 + 工程追加变更拍板）
--    注意：leave_request 建在薪酬 RLS 循环之前无法实现（本段在循环之后），
--    故其 RLS 在本段内单独补挂——策略口径与循环完全一致
-- =====================================================================

-- ── ④ 倒休休假单：财务发起 → 员工短信回 Y 自动扣减；不回复财务可强制扣减（留痕） ──
CREATE TABLE leave_request (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id     uuid NOT NULL REFERENCES eng_staff(id),
    from_ts      timestamptz NOT NULL,
    to_ts        timestamptz NOT NULL,
    minutes      numeric(8,1) NOT NULL CHECK (minutes > 0),   -- 扣减时长（发起时按区间算出落格）
    status       text NOT NULL DEFAULT 'sms_sent' CHECK (status IN
                   ('sms_sent','confirmed','forced_deducted','cancelled')),
    sms_replied_at timestamptz,          -- 员工回 Y 时刻（仅记录）
    decided_by   text,                   -- 强制扣减操作人（红字留痕；confirmed 可空）
    decided_at   timestamptz,
    toil_entry_id uuid REFERENCES toil_ledger(id),  -- 扣减落到哪条倒休流水
    created_by   text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_leave_span CHECK (to_ts > from_ts)
);
CREATE INDEX idx_leave_staff ON leave_request(staff_id);
COMMENT ON TABLE leave_request IS
  'v0.34 倒休休假单：财务发起→短信回 Y 自动扣减；不回复可强制扣减（decided_by 留痕）；倒休不能透支';

CREATE OR REPLACE FUNCTION trg_leave_deduct() RETURNS trigger AS $$
DECLARE v_id uuid; v_name text;
BEGIN
    IF NEW.status IN ('confirmed','forced_deducted') AND OLD.status = 'sms_sent' THEN
        IF NEW.status='forced_deducted' AND NEW.decided_by IS NULL THEN
            RAISE EXCEPTION '门禁：强制扣减必须记录操作人（红字留痕）';
        END IF;
        SELECT name INTO v_name FROM eng_staff WHERE id=NEW.staff_id;
        INSERT INTO toil_ledger(staff_id, entry_type, minutes, reason, created_by)
        VALUES (NEW.staff_id, 'take', -NEW.minutes,
                '休假 '||to_char(NEW.from_ts,'YYYY/MM/DD HH24:MI')||' → '||to_char(NEW.to_ts,'YYYY/MM/DD HH24:MI')||
                CASE WHEN NEW.status='forced_deducted' THEN '（员工未回复 · 财务强制扣减）'
                     ELSE '（员工回 Y 确认）' END,
                COALESCE(NEW.decided_by, v_name))
        RETURNING id INTO v_id;
        NEW.toil_entry_id := v_id;
        NEW.decided_at := COALESCE(NEW.decided_at, now());
    ELSIF TG_OP='UPDATE' AND OLD.status IN ('confirmed','forced_deducted')
          AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION '门禁：休假单已扣减，不能重复扣或改状态——扣错走 toil_ledger adjust 调整并留痕';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER leave_deduct BEFORE UPDATE ON leave_request
    FOR EACH ROW EXECUTE FUNCTION trg_leave_deduct();

-- 薪酬口径 RLS（与上方薪酬循环一致：仅财务/管理层可读，本人可看自己；写按 table_ownership）
ALTER TABLE leave_request ENABLE ROW LEVEL SECURITY;
CREATE POLICY leave_request_read ON leave_request FOR SELECT
  USING (fn_can_see_salary() OR (fn_is_field() AND staff_id = fn_my_staff_id()));
CREATE POLICY leave_request_write ON leave_request FOR ALL
  USING (fn_can_write('leave_request')) WITH CHECK (fn_can_write('leave_request'));

-- ── ④-2 倒休不能透支（挂在流水上：休假单之外直插扣减同样被拦，防绕过） ──
CREATE OR REPLACE FUNCTION trg_toil_no_overdraft() RETURNS trigger AS $$
DECLARE v_bal numeric; v_name text;
BEGIN
    IF NEW.minutes < 0 THEN
        SELECT COALESCE(SUM(minutes),0) INTO v_bal FROM toil_ledger WHERE staff_id=NEW.staff_id;
        IF v_bal + NEW.minutes < 0 THEN
            SELECT name INTO v_name FROM eng_staff WHERE id=NEW.staff_id;
            RAISE EXCEPTION '门禁：倒休不能透支——% 余额 % 小时，本次要扣 % 小时',
                v_name, round(v_bal/60.0,2), round(-NEW.minutes/60.0,2);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER toil_no_overdraft BEFORE INSERT ON toil_ledger
    FOR EACH ROW EXECUTE FUNCTION trg_toil_no_overdraft();

-- ── ③-2 挂起补录门禁：只有挂起才能补；类别+详说(≥10字)+补录人缺一不可；补录进下月补发 ──
CREATE OR REPLACE FUNCTION trg_dp_backfill_gate() RETURNS trigger AS $$
BEGIN
    IF NEW.status='released' AND OLD.status IS DISTINCT FROM 'released' THEN
        IF OLD.status <> 'unrecorded_held' THEN
            RAISE EXCEPTION '门禁：只有挂起（无记录）的日结才能补录放行——已定格的日结不可改';
        END IF;
        IF NEW.backfilled_by IS NULL THEN
            RAISE EXCEPTION '门禁：补录必须记录补录人（工程负责人）';
        END IF;
        IF NEW.backfill_reason_cat IS NULL THEN
            RAISE EXCEPTION '门禁：补录必须选择原因类别——挂起与补录都永久进 KPI';
        END IF;
        IF length(regexp_replace(COALESCE(NEW.backfill_note,''),'\s','','g')) < 10 THEN
            RAISE EXCEPTION '门禁：补录详细说明不能少于 10 字——写清楚那天实际发生了什么（进 KPI）';
        END IF;
        NEW.backfilled_at := COALESCE(NEW.backfilled_at, now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER dp_backfill_gate BEFORE UPDATE ON daily_payroll
    FOR EACH ROW EXECUTE FUNCTION trg_dp_backfill_gate();

-- ── ① 工程追加变更门禁：post_sm3 需 SM3 完成且项目在施工中（交付前）；来源不可改；登记即记告知 ──
CREATE OR REPLACE FUNCTION trg_var_origin_gate() RETURNS trigger AS $$
DECLARE ok boolean; v_status text;
BEGIN
    IF TG_OP='UPDATE' AND OLD.origin IS DISTINCT FROM NEW.origin THEN
        RAISE EXCEPTION '门禁：变更来源（SM3 现场 / 工程追加）登记后不可改';
    END IF;
    IF TG_OP='INSERT' AND NEW.origin='post_sm3' THEN
        SELECT (completed_at IS NOT NULL OR na_flag) INTO ok
          FROM site_meeting WHERE project_id=NEW.project_id AND sm_no=3;
        IF ok IS DISTINCT FROM true THEN
            RAISE EXCEPTION '门禁：SM3 未完成，不能登记工程追加变更——SM3 之前的变更请在 SM3 现场登记';
        END IF;
        SELECT status INTO v_status FROM project WHERE id=NEW.project_id;
        IF v_status <> 'in_construction' THEN
            RAISE EXCEPTION '门禁：工程追加变更只能在项目交付之前登记（当前状态 %）——交付后的改动走维护线', v_status;
        END IF;
        -- ★拍板配套：登记即给付款人发告知短信（外部通道），发出时刻落格；回 Y 仅记录
        NEW.payer_notified_at := COALESCE(NEW.payer_notified_at, now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER var_origin_gate BEFORE INSERT OR UPDATE ON variation
    FOR EACH ROW EXECUTE FUNCTION trg_var_origin_gate();

-- ── ⑤ 待办三动作留痕（十九轮定）：已知悉/处理/搁置，只增不改；RLS 限本人行 ──
CREATE TABLE todo_action_log (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id  uuid NOT NULL REFERENCES app_account(id),
    todo_key    text NOT NULL,            -- 条目稳定标识（部门/事件/项目拼合，应用层生成）
    project_id  uuid REFERENCES project(id),
    action      text NOT NULL CHECK (action IN ('ack','handle','hold')),
    acted_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_todo_act ON todo_action_log(account_id, todo_key);
COMMENT ON TABLE todo_action_log IS
  'v0.34 待办三动作留痕：ack=已知悉停通知（条目状态一变自动失效重启）/ handle=处理 / hold=搁置——只增不改';
ALTER TABLE todo_action_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY todo_act_read ON todo_action_log FOR SELECT
  USING (fn_is_admin() OR account_id = (SELECT id FROM fn_me()));
CREATE POLICY todo_act_write ON todo_action_log FOR INSERT
  WITH CHECK (account_id = (SELECT id FROM fn_me()));

-- ── 新表三件配套（v0.31 教训：只登记不设防=裸奔；v0.33 教训：只建表不登记=断言违规） ──
INSERT INTO table_ownership(table_name, write_dept, note) VALUES
 ('leave_request',  ARRAY['finance'], 'v0.34 休假单：财务发起 / 确认 / 强制扣减'),
 ('todo_action_log',ARRAY['presales','eng_mgmt','procurement','warehouse','finance','maintenance'],
                    'v0.34 各部门各点各的（RLS 再限本人行）')
ON CONFLICT (table_name) DO NOTHING;
INSERT INTO project_scope_registry(table_name,kind,kind_cn,trace_path,note) VALUES
 ('leave_request','person_level','人员级','staff_id','v0.34 倒休休假单'),
 ('todo_action_log','person_level','人员级','account_id · project_id 可选','v0.34 待办三动作留痕');

-- ── ⑦ 断言 +2（73 → 75） ──
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES
('INV-TOIL-01','倒休余额不得为负','critical',
 $q$SELECT s.name, round(COALESCE(SUM(t.minutes),0)/60.0,2) AS balance_hours
      FROM eng_staff s JOIN toil_ledger t ON t.staff_id=s.id
     GROUP BY s.id, s.name HAVING COALESCE(SUM(t.minutes),0) < 0$q$,
 '休假扣减超过累计倒休——透支门禁被绕过，或 adjust 录错'),
('INV-EXP-01','已批准报销必须有收据','critical',
 $q$SELECT claim_no, amount_aud FROM expense_claim WHERE status='approved' AND receipt_url IS NULL$q$,
 '收据门禁被绕过——审批必须凭图，批准后收据可下载存档');


-- =====================================================================
--  v0.36 ★补 RLS —— 2026-08-04 全面回归查出：20 张表一条策略都没有，
--  而降权角色 konnext_app 对它们有完整 SELECT/INSERT/UPDATE/DELETE。
--  最要紧的三张：
--    auth_otp            能读到别人的短信验证码 → 无密码登录，等于可被盗号
--    audit_log           留痕可被改、可被删 → 留痕就失去意义
--    account_department  改自己的部门归属 ＝ 提权
--  为什么以前一路全绿：INV-SEC-07 只 WHERE relname IN (…) 手列了 10 张表。
--  「能自动扫全库的地方绝不手列清单——手列一定会漏且不报错」，
--  已加 INV-SEC-09 自动扫全库；本段就是把它扫出来的洞补上。
-- =====================================================================

-- ── ① auth_otp：谁都不许碰 ────────────────────────────────────────────
--    开 RLS 且【不建任何策略】＝ 对 konnext_app 一律拒绝。
--    表 owner 不受 RLS 限制，所以 /api/auth/*（登录前查号、写验证码，走 owner 连接）照常工作。
--    再显式 REVOKE 一道：策略是行级，权限是表级，两道都关才叫纵深。
ALTER TABLE auth_otp ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON auth_otp FROM PUBLIC;
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'konnext_app') THEN
        EXECUTE 'REVOKE ALL ON auth_otp FROM konnext_app';
    END IF;
END $$;
COMMENT ON TABLE auth_otp IS
  '★验证码：只由 /api/auth/* 的 owner 连接读写。已开 RLS 且不建任何策略 —— 降权角色一律拒绝。'
  '任何业务代码都不该出现 auth_otp 这个词';

-- ── ② 只增不改的留痕表：连决策管理员也不能改删 ───────────────────────
--    故意【不建 UPDATE / DELETE 策略】—— 能改的留痕不叫留痕。
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['audit_log','handoff_log'] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format($f$
          CREATE POLICY %1$s_read ON %1$I FOR SELECT
            USING (NOT fn_is_field() OR fn_is_admin())$f$, t);
        EXECUTE format($f$
          CREATE POLICY %1$s_ins ON %1$I FOR INSERT
            WITH CHECK ((fn_me()).id IS NOT NULL)$f$, t);
    END LOOP;
END $$;
COMMENT ON TABLE audit_log IS
  '全公司留痕。★只增不改：没有 UPDATE/DELETE 策略，决策管理员也只能看';

-- 账号重置留痕：涉及别人的手机号邮箱，只有管理员与本人能看；同样只增不改
ALTER TABLE account_reset_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY account_reset_log_read ON account_reset_log FOR SELECT
    USING (fn_is_admin() OR account_id = (fn_me()).id);
CREATE POLICY account_reset_log_ins ON account_reset_log FOR INSERT
    WITH CHECK (fn_is_admin() OR account_id = (fn_me()).id);

-- ── ③ 元数据 / 权限 / 全局配置：只有决策管理员能写 ────────────────────
--    account_department 放这里是重点：能改它就能给自己加部门 ＝ 提权。
--    assertion_def 同理：能删它就能把系统自检关掉，而且不会报错。
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['account_department','assertion_def','money_visibility',
                             'project_scope_registry','table_ownership',
                             'status_stall_threshold','dept_handoff_rule'] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format($f$
          CREATE POLICY %1$s_read ON %1$I FOR SELECT
            USING (NOT fn_is_field() OR fn_is_admin())$f$, t);
        EXECUTE format($f$
          CREATE POLICY %1$s_write ON %1$I FOR ALL
            USING (fn_is_admin()) WITH CHECK (fn_is_admin())$f$, t);
    END LOOP;
END $$;
COMMENT ON TABLE account_department IS
  '账号的部门归属。★只有决策管理员能写 —— 能改这张表就等于能给自己提权';
COMMENT ON TABLE assertion_def IS
  '不变量断言的定义。★只有决策管理员能写 —— 能删这里就能把系统自检悄悄关掉';

-- ── ④ 业务表：先补 table_ownership 登记，再套「读全部、写本部门」通用模板 ──
INSERT INTO table_ownership(table_name, write_dept, note) VALUES
 ('procurement',            ARRAY['procurement','warehouse'], 'v0.36：采购下单；库管填到货'),
 ('travel_estimate',        ARRAY['eng_mgmt'],                'v0.36：路程预估定格，工程管理写'),
 ('staff_daily_commitment', ARRAY['finance','eng_mgmt'],      'v0.36：当日参考时长，财务定薪 / 工程排班'),
 ('dept_handoff',           ARRAY['presales','eng_mgmt','procurement','warehouse','finance','maintenance'],
                                                              'v0.36：跨部门交接，谁收到谁确认'),
 ('notification',           ARRAY['presales','eng_mgmt','procurement','warehouse','finance','maintenance'],
                                                              'v0.36：跨部门动作都会发通知')
ON CONFLICT (table_name) DO NOTHING;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['fx_rate','job_checklist','public_holiday','sm_template',
                             'procurement','travel_estimate','dept_handoff','notification'] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format($f$
          CREATE POLICY %1$s_read ON %1$I FOR SELECT
            USING (NOT fn_is_field() OR fn_is_admin())$f$, t);
        EXECUTE format($f$
          CREATE POLICY %1$s_ins ON %1$I FOR INSERT
            WITH CHECK (fn_can_write(%1$L))$f$, t);
        EXECUTE format($f$
          CREATE POLICY %1$s_upd ON %1$I FOR UPDATE
            USING (fn_can_write(%1$L)) WITH CHECK (fn_can_write(%1$L))$f$, t);
        EXECUTE format($f$
          CREATE POLICY %1$s_del ON %1$I FOR DELETE
            USING (fn_is_admin())$f$, t);
    END LOOP;
END $$;

-- 当日参考时长带着日薪覆盖价 → 属薪酬敏感，读要按薪酬口径限
ALTER TABLE staff_daily_commitment ENABLE ROW LEVEL SECURITY;
CREATE POLICY staff_daily_commitment_read ON staff_daily_commitment FOR SELECT
    USING (fn_can_see_salary() OR fn_has_dept('eng_mgmt')
           OR (fn_is_field() AND staff_id = fn_my_staff_id()));
CREATE POLICY staff_daily_commitment_write ON staff_daily_commitment FOR ALL
    USING (fn_can_write('staff_daily_commitment'))
    WITH CHECK (fn_can_write('staff_daily_commitment'));

-- ── ⑤ INV-SEC-07 不再是唯一防线：把它的手列清单换成「全库自动扫」──
--    原来那条只查 10 张表，20 张漏网的一次都没被提过。
UPDATE assertion_def
   SET label = '关键表必须开启 RLS（已并入 INV-SEC-09 自动扫全库）',
       query = $q$SELECT relname FROM pg_class
                   WHERE relkind='r' AND relnamespace='public'::regnamespace
                     AND relname IN ('project','payment_milestone','payment_receipt','material',
                                     'stock_out','stock_out_line','daily_payroll','payroll_month',
                                     'app_account','work_log','auth_otp','audit_log','account_department')
                     AND NOT relrowsecurity$q$,
       hint  = '手列清单一定会漏 —— 真正兜底的是 INV-SEC-09（自动扫全库）'
 WHERE code = 'INV-SEC-07';


-- =====================================================================
--  v0.36 ② 采购与库管落库 —— 把 2026-08-04 五十七~六十一轮 UI 定下来的口径写进契约
--
--  只补【真的没有】的：契约里 stock_out / stock_return / stocktake / v_material_stock
--  / v_material_custody / v_stock_ledger 早就有了，不重复造。缺的是这七件：
--    ① supplier 表          —— 原来供应商只是一串 text，删不掉也管不住
--    ② material_price_log   —— 调价「为什么」没地方存（audit_log 推导不出原因）
--    ③ 采购单定格汇率+原因  —— 落地成本＝(单价+运费)×【下单那一刻】的汇率
--    ④ purchase_req         —— ★要不要采购的指令由库管下达，采购不能自己决定
--    ⑤ rma 四态跟踪         —— 已退回 → 对方已收 → 已发货 → 已接收
--    ⑥ goods_receipt_diff   —— 到货点数对不上，按实收入库、差额交采购（不许抹平）
--    ⑦ 阈值与选项           —— 并入既有的 eng_setting 键值表，不新建设置表
-- =====================================================================

-- ── ① 供应商（用户：采购里非常重要的是供应商信息）───────────────────
CREATE TABLE supplier (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name         text UNIQUE NOT NULL,
    contact      text,
    phone        text,
    email        text,
    currency     text NOT NULL DEFAULT 'AUD' CHECK (currency IN ('AUD','USD','CNY')),
    -- ★交期不许填 0：填 0 → ETA 全算成下单当天 → 从此没有任何一单「超期」，
    --   准时率永远 100%，而且不会报错
    lead_days    integer NOT NULL CHECK (lead_days > 0),
    terms        text,                              -- 结算条件：月结 30 / 预付 30% …
    address      text,
    -- ★备注存的是经验：「春节前后要提前两周下单」这种话不写下来，
    --   就只在一个人脑子里，他一休假就断了
    note         text,
    active       boolean NOT NULL DEFAULT true,
    created_by   text,
    created_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE supplier IS
  '供应商。★删除受引用保护：被物料挂过 / 开过采购单 / 报过退换的删不掉，只能停用（active=false）——'
  '真删了历史就成孤儿：物料查不到供应商、采购单查不到是谁家的货，而且不会报错';

-- 物料与采购单挂上供应商（原来的 text 列保留，老数据照旧可读）
ALTER TABLE material       ADD COLUMN IF NOT EXISTS supplier_id uuid REFERENCES supplier(id);
ALTER TABLE purchase_order ADD COLUMN IF NOT EXISTS supplier_id uuid REFERENCES supplier(id);

CREATE OR REPLACE FUNCTION trg_supplier_guard() RETURNS trigger AS $$
DECLARE n_mat int; n_po int; n_rma int; n_open int;
BEGIN
    IF TG_OP = 'DELETE' THEN
        SELECT count(*) INTO n_mat FROM material       WHERE supplier_id = OLD.id;
        SELECT count(*) INTO n_po  FROM purchase_order WHERE supplier_id = OLD.id;
        SELECT count(*) INTO n_rma FROM rma_case r JOIN material m ON m.id = r.material_id
          WHERE m.supplier_id = OLD.id;
        IF n_mat + n_po + n_rma > 0 THEN
            RAISE EXCEPTION '门禁：供应商「%」删不掉 —— 还被 % 种物料、% 张采购单、% 条退换引用着。'
                            '删了这些记录就成孤儿（采购单查不到是谁家的货）。不想再用它请改「停用」，'
                            '停用的不出现在新下单与新建物料的选项里，历史照旧可查',
                            OLD.name, n_mat, n_po, n_rma;
        END IF;
        RETURN OLD;
    END IF;
    -- 停用门禁：还有在途未到的单，停了就没人盯着催货
    IF TG_OP = 'UPDATE' AND OLD.active AND NOT NEW.active THEN
        SELECT count(*) INTO n_open FROM purchase_order
         WHERE supplier_id = NEW.id AND arrived_at IS NULL AND status NOT IN ('cancelled','draft');
        IF n_open > 0 THEN
            RAISE EXCEPTION '门禁：供应商「%」还有 % 张在途未到的采购单 —— 停用了就没人盯着催货了。'
                            '先把货收完或取消采购单，再停用', NEW.name, n_open;
        END IF;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER supplier_guard BEFORE UPDATE OR DELETE ON supplier
    FOR EACH ROW EXECUTE FUNCTION trg_supplier_guard();

-- ── ② 调价流水：★「为什么」是必填，而且只增不改 ────────────────────
CREATE TABLE material_price_log (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    material_id  uuid NOT NULL REFERENCES material(id) ON DELETE CASCADE,
    currency     text NOT NULL CHECK (currency IN ('AUD','USD','CNY')),
    price_from   numeric(12,2) NOT NULL CHECK (price_from >= 0),
    price_to     numeric(12,2) NOT NULL CHECK (price_to  >  0),
    -- ★同价不许记：没改就别记一笔，调价历史要干净
    CONSTRAINT ck_price_changed CHECK (price_to <> price_from),
    -- ★原因必填 ≥4 字：采购价直接决定毛利率。三个月后有人问「这个料怎么贵了 5 块」，
    --   没有原因就只能猜
    reason       text NOT NULL CHECK (length(btrim(reason)) >= 4),
    changed_by   text NOT NULL,
    changed_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_price_log_mat ON material_price_log(material_id, changed_at DESC);
COMMENT ON TABLE material_price_log IS
  '调价流水，只增不改（没有 UPDATE/DELETE 策略）。'
  '★「距今多久没调过」比「调了多少」更危险：供应商早涨了而我们还按老价算成本，毛利率是假的且不报错';

-- ── ③ 采购单：下单即定格汇率 + 采购原因 + 催货留痕 ──────────────────
ALTER TABLE purchase_order ADD COLUMN IF NOT EXISTS currency  text
    CHECK (currency IN ('AUD','USD','CNY'));
-- ★定格：以后汇率再涨再跌这单不动。否则上月买的东西这月成本自己变，账永远对不上
ALTER TABLE purchase_order ADD COLUMN IF NOT EXISTS fx_rate_frozen numeric(12,6)
    CHECK (fx_rate_frozen > 0);
ALTER TABLE purchase_order ADD COLUMN IF NOT EXISTS reason text;   -- 为什么买（下拉，见 ⑦）

CREATE TABLE purchase_order_chase (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    po_id        uuid NOT NULL REFERENCES purchase_order(id) ON DELETE CASCADE,
    chased_at    timestamptz NOT NULL DEFAULT now(),
    chased_by    text NOT NULL,
    old_eta      date,
    new_eta      date,          -- ★只有对方给了新日期才填；没给就留空，ETA 不动
    note         text
);
COMMENT ON TABLE purchase_order_chase IS
  '催货留痕。★不许随手改 ETA：改了超期天数永远归零，再也看不出哪家总拖 —— 供应商准时率就是这么算的';

CREATE OR REPLACE FUNCTION trg_po_freeze_guard() RETURNS trigger AS $$
BEGIN
    -- 汇率一旦定格就不许改（改了历史成本会跟着变）
    IF OLD.fx_rate_frozen IS NOT NULL
       AND NEW.fx_rate_frozen IS DISTINCT FROM OLD.fx_rate_frozen THEN
        RAISE EXCEPTION '门禁：采购单 % 的汇率在下单那一刻已定格（%），不能再改 —— '
                        '改了这单的落地成本就跟着变，上月买的东西这月成本自己变，账永远对不上',
                        OLD.po_no, OLD.fx_rate_frozen;
    END IF;
    -- 已到货的单不许再改预计到货（准时率靠这个数算）
    IF OLD.arrived_at IS NOT NULL AND NEW.expected_at IS DISTINCT FROM OLD.expected_at THEN
        RAISE EXCEPTION '门禁：采购单 % 已于 % 到货，预计到货日不能再改 —— '
                        '准时率＝到货日 ≤ 预计到货，改了这个数就废了',
                        OLD.po_no, to_char(OLD.arrived_at,'YYYY-MM-DD');
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER po_freeze_guard BEFORE UPDATE ON purchase_order
    FOR EACH ROW EXECUTE FUNCTION trg_po_freeze_guard();

-- ── ④ 采购需求：★指令由库管下达，采购不能自己决定 ──────────────────
CREATE TABLE purchase_req (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    req_no       text UNIQUE NOT NULL,
    -- ★来源只有两个，都是"别人给的指令"。故意没有 'procurement' 这一档：
    --   warehouse_restock = C1 常备件低于红线（系统现算的补货建议）
    --   project_demand    = 项目 S2 物料款结清后，库管按方案 BOM 提的料
    source       text NOT NULL CHECK (source IN ('warehouse_restock','project_demand')),
    project_id   uuid REFERENCES project(id),      -- 补货是公司级，可空
    material_id  uuid NOT NULL REFERENCES material(id),
    qty          numeric(12,2) NOT NULL CHECK (qty > 0),
    why          text NOT NULL,                    -- 为什么要这批货
    status       text NOT NULL DEFAULT 'pending' CHECK (status IN
                   ('pending','ordered','returned','cancelled')),
    po_id        uuid REFERENCES purchase_order(id),
    -- ★退回库管：采购不能删需求，只能退回并写清楚为什么
    returned_reason text,
    qty_changed_reason text,                       -- 改了库管要的数量也必须写原因
    raised_by    text NOT NULL,
    raised_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_req_project CHECK (source <> 'project_demand' OR project_id IS NOT NULL),
    CONSTRAINT ck_req_returned CHECK (status <> 'returned'
                                      OR length(btrim(COALESCE(returned_reason,''))) >= 4)
);
COMMENT ON TABLE purchase_req IS
  '采购需求。★用户 2026-08-04 定：要不要采购的指令一定由库管下达给采购，采购不能自己决定。'
  '所以 source 只有 warehouse_restock / project_demand 两档，采购只能「退回库管」并写明原因';

-- ── ⑤ RMA 退换：四步跟踪（用户 2026-08-04 定：这页不是要钱，是跟货）─────
ALTER TABLE rma_case ADD COLUMN IF NOT EXISTS track_status text
    NOT NULL DEFAULT 'returned'
    CHECK (track_status IN ('returned','supplier_received','supplier_shipped','received_back'));
ALTER TABLE rma_case ADD COLUMN IF NOT EXISTS received_qty numeric(12,2)
    CHECK (received_qty >= 0);
ALTER TABLE rma_case ADD COLUMN IF NOT EXISTS received_back_at timestamptz;
ALTER TABLE rma_case ADD COLUMN IF NOT EXISTS wh_inbound_at    timestamptz;  -- 库管点数上架
COMMENT ON COLUMN rma_case.track_status IS
  '四步：returned 已退回 → supplier_received 对方已收 → supplier_shipped 已发货 → received_back 已接收。'
  '★只能一步一步往前，不许跳级、不许回退；中间两步在等对方，超期要定期短信催';

CREATE TABLE rma_track (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rma_id       uuid NOT NULL REFERENCES rma_case(id) ON DELETE CASCADE,
    to_status    text NOT NULL CHECK (to_status IN
                   ('returned','supplier_received','supplier_shipped','received_back')),
    -- ★凭据必填 ≥4 字：口头的「对方说收到了」三个月后翻不出来
    evidence     text NOT NULL CHECK (length(btrim(evidence)) >= 4),
    moved_by     text NOT NULL,
    moved_at     timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE rma_chase (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rma_id       uuid NOT NULL REFERENCES rma_case(id) ON DELETE CASCADE,
    at_status    text NOT NULL,                    -- 在哪一步催的
    ask          text NOT NULL,                    -- 问的是什么（是否收到 / 是否已发 / 单号）
    channel      text NOT NULL DEFAULT 'sms' CHECK (channel IN ('sms','email','both')),
    chased_by    text NOT NULL,
    chased_at    timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION trg_rma_track_guard() RETURNS trigger AS $$
DECLARE ord int; old_ord int; q numeric;
BEGIN
    ord     := array_position(ARRAY['returned','supplier_received','supplier_shipped','received_back'],
                              NEW.track_status);
    old_ord := array_position(ARRAY['returned','supplier_received','supplier_shipped','received_back'],
                              OLD.track_status);
    IF ord IS DISTINCT FROM old_ord THEN
        IF ord < old_ord THEN
            RAISE EXCEPTION '门禁：退换单 % 的状态只能往前推，不能退回去 —— 记错了请新开一条并写明原因',
                            OLD.rma_no;
        END IF;
        IF ord > old_ord + 1 THEN
            RAISE EXCEPTION '门禁：退换单 % 不能跳级 —— 一步一步来（已退回 → 对方已收 → 已发货 → 已接收），'
                            '中间那步没有凭据，将来对方说没收到就说不清了', OLD.rma_no;
        END IF;
        -- 每一步都要有凭据（同事务里先写 rma_track 再改状态，或反过来都行）
        IF NOT EXISTS (SELECT 1 FROM rma_track t
                        WHERE t.rma_id = NEW.id AND t.to_status = NEW.track_status) THEN
            RAISE EXCEPTION '门禁：退换单 % 推进到「%」必须同时写下凭据（对方邮件 / 快递签收 / 发货单号，≥4 字）',
                            OLD.rma_no, NEW.track_status;
        END IF;
    END IF;
    -- 已接收：必须填实收数量，且不能比寄回去的还多
    IF NEW.track_status = 'received_back' THEN
        IF NEW.received_qty IS NULL THEN
            RAISE EXCEPTION '门禁：退换单 % 标「已接收」必须填实际收到数量 —— 少收了要留痕，别自己抹平',
                            OLD.rma_no;
        END IF;
        IF NEW.received_qty > NEW.qty THEN
            RAISE EXCEPTION '门禁：退换单 % 收到 % 件，比寄回去的 % 件还多 —— 数错了还是串单了？先查清楚',
                            OLD.rma_no, NEW.received_qty, NEW.qty;
        END IF;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER rma_track_guard BEFORE UPDATE ON rma_case
    FOR EACH ROW EXECUTE FUNCTION trg_rma_track_guard();

-- ── ⑥ 到货差异：★按实收入库，差额交采购，库管不许抹平 ───────────────
CREATE TABLE goods_receipt_diff (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    diff_no      text UNIQUE NOT NULL,
    po_line_id   uuid NOT NULL REFERENCES purchase_order_line(id) ON DELETE CASCADE,
    qty_ordered  numeric(12,2) NOT NULL CHECK (qty_ordered > 0),
    qty_received numeric(12,2) NOT NULL CHECK (qty_received >= 0),
    kind         text GENERATED ALWAYS AS (
                   CASE WHEN qty_received < qty_ordered THEN 'short'
                        WHEN qty_received > qty_ordered THEN 'over'
                        ELSE 'match' END) STORED,
    -- ★原因必填 ≥4 字：差多少、什么原因、有没有拍照，写清楚才好找供应商
    reason       text NOT NULL CHECK (length(btrim(reason)) >= 4),
    status       text NOT NULL DEFAULT 'notified' CHECK (status IN ('notified','closed')),
    closed_note  text,
    closed_at    timestamptz,
    raised_by    text NOT NULL,
    raised_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_grd_diff   CHECK (qty_received <> qty_ordered),   -- 没差异就别开单
    CONSTRAINT ck_grd_closed CHECK (status <> 'closed'
                                    OR length(btrim(COALESCE(closed_note,''))) >= 4)
);
COMMENT ON TABLE goods_receipt_diff IS
  '到货点数对不上就开一条，交采购去跟供应商。★库管不许把数字改成"刚好"——'
  '抹平了这批货从此查不出去哪了，而且永远不会报错';

-- ── ⑦ 阈值与选项：并入既有的 eng_setting，不新建设置表（架构不要过载）──
INSERT INTO eng_setting(key, value_num, note, write_depts) VALUES
 ('proc_eta_warn_days',   3,  '到货预警：还剩几天到就提醒', ARRAY['procurement']),
 ('proc_fx_stale_days',   7,  '汇率过期提醒：多少天没更新（拿旧汇率算成本没人敢信）', ARRAY['procurement']),
 ('proc_req_sla_hours',  72,  '需求 SLA：库管提了多久还没下单算超时', ARRAY['procurement']),
 ('proc_rma_chase_days',  5,  '退换催确认：一个状态停多久没动静就提醒去催', ARRAY['procurement']),
 ('wh_ack_hours',        72,  '提货回执超时：出库单多久没回 YES 算异常（没回执＝没人认领这批货）', ARRAY['warehouse']),
 ('wh_count_diff_pct',    2,  '盘点差异提醒：差异超过这个百分比单独标出来', ARRAY['warehouse'])
ON CONFLICT (key) DO NOTHING;
INSERT INTO eng_setting(key, value_text, note, write_depts) VALUES
 ('proc_reasons',
  '["集中采购 · 常备件补货","项目采购 · 按方案 BOM","项目采购 · 现场变更追加","急件补料","样品/测试","其他"]',
  '采购原因下拉：三个月后你得说得清当初为什么买', ARRAY['procurement'])
ON CONFLICT (key) DO NOTHING;

-- ── 登记：写入归属 + 项目归属（不登记会被 INV-PJ-10 抓）────────────────
INSERT INTO table_ownership(table_name, write_dept, note) VALUES
 ('supplier',            ARRAY['procurement'], 'v0.36：采购建立/修改/停用，删除受引用保护'),
 ('material_price_log',  ARRAY['procurement'], 'v0.36：调价流水，只增不改'),
 ('purchase_order_chase',ARRAY['procurement'], 'v0.36：催货留痕'),
 ('purchase_req',        ARRAY['warehouse','procurement'],
   'v0.36：★库管下指令；采购只能退回并写原因，不能自己新建'),
 ('rma_track',           ARRAY['procurement'], 'v0.36：退换四步推进留痕'),
 ('rma_chase',           ARRAY['procurement'], 'v0.36：退换催确认留痕'),
 ('goods_receipt_diff',  ARRAY['warehouse','procurement'],
   'v0.36：库管开单，采购跟供应商，最后库管来销')
ON CONFLICT (table_name) DO NOTHING;

INSERT INTO project_scope_registry(table_name, kind, kind_cn, trace_path, note) VALUES
 ('supplier',            'company_level','公司级','—','供应商不属于任何单个项目'),
 ('material_price_log',  'company_level','公司级','—','调价是全公司口径'),
 ('purchase_order_chase','via_parent','随父单','purchase_order.ref_project_id',NULL),
 ('purchase_req',        'project_or_scope','项目或公司级','project_id 为空＝集中补货',
   '★补货是公司级，项目提料必须有项目'),
 ('rma_track',           'via_parent','随父单','rma_case.project_id',NULL),
 ('rma_chase',           'via_parent','随父单','rma_case.project_id',NULL),
 ('goods_receipt_diff',  'via_parent','随父单','purchase_order_line → purchase_order.ref_project_id',
   '集中采购的差异不属于任何项目')
ON CONFLICT (table_name) DO NOTHING;

-- ── RLS：新表一律「读全部、写本部门」；两张只增不改的留痕表不给 UPDATE/DELETE ──
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['supplier','purchase_order_chase','purchase_req',
                             'rma_chase','goods_receipt_diff'] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format($f$CREATE POLICY %1$s_read ON %1$I FOR SELECT
            USING (NOT fn_is_field() OR fn_is_admin())$f$, t);
        EXECUTE format($f$CREATE POLICY %1$s_ins ON %1$I FOR INSERT
            WITH CHECK (fn_can_write(%1$L))$f$, t);
        EXECUTE format($f$CREATE POLICY %1$s_upd ON %1$I FOR UPDATE
            USING (fn_can_write(%1$L)) WITH CHECK (fn_can_write(%1$L))$f$, t);
        EXECUTE format($f$CREATE POLICY %1$s_del ON %1$I FOR DELETE
            USING (fn_is_admin())$f$, t);
    END LOOP;
    -- 只增不改：调价流水与退换推进留痕，改了就失去意义
    FOREACH t IN ARRAY ARRAY['material_price_log','rma_track'] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format($f$CREATE POLICY %1$s_read ON %1$I FOR SELECT
            USING (NOT fn_is_field() OR fn_is_admin())$f$, t);
        EXECUTE format($f$CREATE POLICY %1$s_ins ON %1$I FOR INSERT
            WITH CHECK (fn_can_write(%1$L))$f$, t);
    END LOOP;
END $$;

-- ── 视图：采购与库管两条线各自的"看板数据源"（只查视图，不查基表）──────
CREATE VIEW v_supplier_perf AS
SELECT s.id, s.name, s.contact, s.phone, s.email, s.currency, s.lead_days, s.terms,
       s.note, s.active,
       (SELECT count(*) FROM material m       WHERE m.supplier_id = s.id AND m.active) AS mat_n,
       (SELECT count(*) FROM purchase_order p WHERE p.supplier_id = s.id
                                                AND p.arrived_at IS NULL
                                                AND p.status NOT IN ('cancelled','draft')) AS on_way_n,
       -- 准时率现算：到货日 ≤ 预计到货就算准时
       (SELECT count(*) FROM purchase_order p WHERE p.supplier_id = s.id AND p.arrived_at IS NOT NULL) AS done_n,
       (SELECT count(*) FROM purchase_order p WHERE p.supplier_id = s.id AND p.arrived_at IS NOT NULL
                                                AND p.arrived_at::date <= p.expected_at) AS ontime_n
  FROM supplier s;
COMMENT ON VIEW v_supplier_perf IS '供应商台账 + 准时率现算（到货日 ≤ 预计到货）';

CREATE VIEW v_material_price_trend AS
-- ★每个物料一行：最近一次调的是什么、涨还是跌、多久没动了 —— 看整体在往哪走。
--   「距今」越大越危险：供应商早涨了而我们还按老价算成本，毛利率是假的且不报错
SELECT m.id AS material_id, m.code, m.display_name, m.active,
       s.name AS supplier_name,
       CASE WHEN fn_can_see_purchase_price() THEN m.price_aud END AS price_now_aud,
       l.changed_at AS last_at,
       CASE WHEN fn_can_see_purchase_price() THEN l.price_from END AS last_from,
       CASE WHEN fn_can_see_purchase_price() THEN l.price_to   END AS last_to,
       CASE WHEN fn_can_see_purchase_price() AND l.price_from > 0
            THEN round((l.price_to - l.price_from) / l.price_from * 100, 1) END AS last_pct,
       CASE WHEN l.changed_at IS NOT NULL
            THEN (current_date - l.changed_at::date) END AS days_since,
       (SELECT count(*) FROM material_price_log x WHERE x.material_id = m.id) AS change_n,
       l.reason AS last_reason, l.changed_by AS last_by
  FROM material m
  LEFT JOIN supplier s ON s.id = m.supplier_id
  LEFT JOIN LATERAL (SELECT * FROM material_price_log p
                      WHERE p.material_id = m.id ORDER BY p.changed_at DESC LIMIT 1) l ON true;

CREATE VIEW v_rma_tracking AS
SELECT r.id, r.rma_no, r.project_id, r.material_id, m.display_name, r.qty,
       r.track_status, r.received_qty, r.received_back_at, r.wh_inbound_at,
       s.name AS supplier_name,
       (SELECT max(moved_at) FROM rma_track t WHERE t.rma_id = r.id) AS last_move_at,
       (SELECT count(*)      FROM rma_chase c WHERE c.rma_id = r.id) AS chase_n,
       (SELECT max(chased_at)FROM rma_chase c WHERE c.rma_id = r.id) AS last_chase_at,
       -- 这一步停了多久（推进或催问，取最近的一次）
       (current_date - GREATEST(
          COALESCE((SELECT max(moved_at)  FROM rma_track t WHERE t.rma_id = r.id), r.returned_at),
          COALESCE((SELECT max(chased_at) FROM rma_chase c WHERE c.rma_id = r.id), r.returned_at)
        )::date) AS stuck_days
  FROM rma_case r
  JOIN material m ON m.id = r.material_id
  LEFT JOIN supplier s ON s.id = m.supplier_id;
COMMENT ON VIEW v_rma_tracking IS
  '退换四步跟踪。stuck_days 超过 proc_rma_chase_days 就该催 —— 不催，货就在海上飘着没人问';

CREATE VIEW v_purchase_req_open AS
SELECT q.id, q.req_no, q.source, q.project_id, q.material_id, m.display_name,
       q.qty, q.why, q.status, q.raised_by, q.raised_at,
       round(EXTRACT(epoch FROM (now() - q.raised_at)) / 3600) AS waiting_hours
  FROM purchase_req q JOIN material m ON m.id = q.material_id
 WHERE q.status = 'pending';
COMMENT ON VIEW v_purchase_req_open IS
  '待下单需求。★两个来源都是库管给的指令，采购是执行者不是需求方';

-- ── 新增视图的两条硬规矩：security_invoker + 项目标识 ────────────────
--    以前这两件事是 DDL 中段两个 DO 块干的，新视图写在它们后面就漏掉了
--    （这一轮我自己就漏了 4 个，被 INV-SEC-01 与 INV-UI-01 当场抓出来）。
--    收成一个函数：以后任何一轮加完视图，末尾调一次就行，不必记住去哪儿重跑。
CREATE OR REPLACE FUNCTION fn_apply_view_conventions() RETURNS void AS $conv$
DECLARE vw record; r record; def text; join_on text; pid_col text; n1 int := 0; n2 int := 0;
BEGIN
    -- ① 视图默认按【视图所有者】执行 → RLS 整个被绕过。必须逐个设 security_invoker
    FOR vw IN SELECT c.relname FROM pg_class c
              WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
                AND (c.reloptions IS NULL OR NOT ('security_invoker=true' = ANY(c.reloptions)))
    LOOP
        EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', vw.relname);
        n1 := n1 + 1;
    END LOOP;
    -- ② 带项目列的视图必须带得出【编号 + 地址】——每个部门都管全公司项目
    FOR r IN
        SELECT v.table_name AS vname,
               (SELECT c.column_name FROM information_schema.columns c
                 WHERE c.table_schema='public' AND c.table_name=v.table_name
                   AND c.column_name='project_id' LIMIT 1) AS by_id,
               (SELECT c.column_name FROM information_schema.columns c
                 WHERE c.table_schema='public' AND c.table_name=v.table_name
                   AND c.column_name IN ('project_code','code') LIMIT 1) AS by_code
          FROM information_schema.views v
         WHERE v.table_schema='public'
           AND v.table_name <> 'v_project_label'
           AND NOT EXISTS(SELECT 1 FROM information_schema.columns c
                           WHERE c.table_schema='public' AND c.table_name=v.table_name
                             AND c.column_name='pj_label')
           AND EXISTS(SELECT 1 FROM information_schema.columns c
                       WHERE c.table_schema='public' AND c.table_name=v.table_name
                         AND c.column_name IN ('project_id','project_code'))
         ORDER BY v.table_name
    LOOP
        IF r.by_id IS NOT NULL THEN
            pid_col := r.by_id; join_on := 'lb.project_id = _v.'||quote_ident(pid_col);
        ELSE
            pid_col := r.by_code; join_on := 'lb.code = _v.'||quote_ident(pid_col);
        END IF;
        def := rtrim(rtrim(pg_get_viewdef(r.vname::regclass, true)), ';');
        BEGIN
            EXECUTE format(
              'CREATE OR REPLACE VIEW %I AS SELECT _v.*, '
              'lb.display_label AS pj_label, lb.code AS pj_code, '
              'lb.addr_suburb AS pj_suburb, lb.addr_full AS pj_addr, '
              'lb.owner_name AS pj_owner '
              'FROM (%s) _v LEFT JOIN v_project_label lb ON %s', r.vname, def, join_on);
            n2 := n2 + 1;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE '★ 视图 % 未能自动追加项目标识：%', r.vname, SQLERRM;
        END;
    END LOOP;
    -- 包装之后可能又多出没设 invoker 的视图，再扫一遍
    FOR vw IN SELECT c.relname FROM pg_class c
              WHERE c.relkind='v' AND c.relnamespace='public'::regnamespace
                AND (c.reloptions IS NULL OR NOT ('security_invoker=true' = ANY(c.reloptions)))
    LOOP EXECUTE format('ALTER VIEW %I SET (security_invoker = true)', vw.relname); END LOOP;
    RAISE NOTICE 'v0.36 视图规矩：补 security_invoker % 个 · 补项目标识 % 个', n1, n2;
END $conv$ LANGUAGE plpgsql;
COMMENT ON FUNCTION fn_apply_view_conventions IS
  '★新增视图之后调一次。两件事：security_invoker=true（不设＝RLS 被整个绕过）'
  '与 pj_label 项目标识（编号+地址）。手工去记「重跑 DDL 中段那个 DO 块」一定会漏';

SELECT fn_apply_view_conventions();

-- ── 断言 +4（77 → 81）────────────────────────────────────────────────
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES
('INV-PC-01','调价流水必须写原因且新旧价不同','critical',
 $q$SELECT id, material_id FROM material_price_log
     WHERE length(btrim(COALESCE(reason,''))) < 4 OR price_to = price_from$q$,
 '原因门禁被绕过——三个月后没人说得清这个料为什么贵了'),
('INV-PC-02','采购需求的来源只能是库管补货或项目提料','critical',
 $q$SELECT req_no, source FROM purchase_req
     WHERE source NOT IN ('warehouse_restock','project_demand')$q$,
 '★要不要采购的指令由库管下达，采购不能自己决定'),
('INV-PC-03','已到货的采购单必须有定格汇率（外币单）','high',
 $q$SELECT po_no, currency FROM purchase_order
     WHERE arrived_at IS NOT NULL AND currency IS NOT NULL AND currency <> 'AUD'
       AND fx_rate_frozen IS NULL$q$,
 '没定格汇率 → 落地成本会随今天的汇率浮动，上月买的东西这月成本自己变'),
('INV-WH-01','标了已接收的退换必须有实收数量且不超过寄回数','critical',
 $q$SELECT rma_no, qty, received_qty FROM rma_case
     WHERE track_status = 'received_back'
       AND (received_qty IS NULL OR received_qty > qty)$q$,
 '实收多于寄回＝数错或串单；实收为空＝少收被悄悄抹平了');


-- =====================================================================
--  v0.35 ①②：乐观锁推广到全部「可改业务表」
--  规则（自动扫全库，不手列清单——手列一定会漏且不报错）：
--    凡是带 UPDATE / ALL 策略的表 = 有人能改它 = 必须能挡住陈旧覆盖。
--  只读表（audit_log / notification / fx_rate / 各种登记表…）不挂，省得白加列。
-- =====================================================================
DO $lock$
DECLARE t text; n int := 0;
BEGIN
    FOR t IN
        SELECT c.relname
          FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
         WHERE ns.nspname = 'public' AND c.relkind = 'r'
           AND EXISTS (SELECT 1 FROM pg_policies p
                        WHERE p.schemaname = 'public' AND p.tablename = c.relname
                          AND p.cmd IN ('UPDATE','ALL'))
         ORDER BY 1
    LOOP
        EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1', t);
        EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()', t);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_optlock', t);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_touch',   t);
        -- 触发器按名字顺序跑：_optlock 先比对旧版本，_touch 后自增（o < t）
        EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION trg_row_optlock()',
                       t || '_optlock', t);
        EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION trg_row_touch()',
                       t || '_touch', t);
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'v0.35 乐观锁已挂到 % 张可改业务表', n;
END
$lock$;

-- project 专用的两只函数已被通用件取代（触发器上面刚重建过，这里可以安全删）
DROP FUNCTION IF EXISTS trg_project_touch();
DROP FUNCTION IF EXISTS trg_project_optlock();

-- ── v0.35 ③ 断言 +1（75 → 76）──
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES
('INV-CC-01','可改的表必须挂乐观锁','critical',
 $q$SELECT c.relname AS table_name
      FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
     WHERE ns.nspname='public' AND c.relkind='r'
       AND EXISTS (SELECT 1 FROM pg_policies p
                    WHERE p.schemaname='public' AND p.tablename=c.relname
                      AND p.cmd IN ('UPDATE','ALL'))
       AND NOT EXISTS (SELECT 1 FROM pg_trigger tg
                        WHERE tg.tgrelid=c.oid AND NOT tg.tgisinternal
                          AND tg.tgname = c.relname || '_optlock')$q$,
 '新增了能改的表却没挂乐观锁——两个人同时改会静默覆盖，不报错只是数字悄悄错了');


-- #####################################################################
-- ##  v0.37 ①：项目物料账 —— 四段链条落库（决策记录 §23）
-- ##
-- ##  ①报价原始单（采购上传 Excel，版本化只读）
-- ##    → ②现场在 App 改（★不能删行，只能把数量调 0）
-- ##    → ③工程管理审「变量」（只看改了什么，不看整表）
-- ##    → ④库管先看现货（备料＝占住不扣库存）→ 采购只买差额
-- ##
-- ##  ★这一段推翻了 v0.36 的一条口径：项目料的提单人从【库管】改成【工程人员】。
-- ##    方案和现场情况工程人员最清楚，库管管的是仓库不是项目。
-- ##    库管补货那一档不变（C1 常备件低于红线，系统现算）。
-- ##
-- ##  ★全段最重要的一条设计：项目料的需求【只存一份】。
-- ##    六十三轮踩过的坑 —— purchase_req 里存一份库管提的需求行，物料账那边又
-- ##    按「应采 − 已下单」现算一遍，同一件事两个数字，迟早对不上而且不会报错。
-- ##    现在只留现算这一份（v_project_bom），purchase_req 只承接库管补货与
-- ##    运维缺料这类【不在项目物料账里】的需求。
-- #####################################################################

-- =====================================================================
--  第四十四部分：报价原始单 quote_bom / quote_bom_line
--    外部报价系统出 Excel → 采购上传 → 基线、只读、版本化
-- =====================================================================
CREATE TABLE quote_bom (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id   uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    -- ★版本号必填、不覆盖旧版：客户问「我那版报价里明明有 10 个面板」时，
    --   得能把当初那一版原样翻出来
    ver_no       text NOT NULL CHECK (length(btrim(ver_no)) >= 1),
    source_file  text,                                -- Excel 文件名/链接
    is_current   boolean NOT NULL DEFAULT true,       -- 当前版本，一个项目只能有一个
    uploaded_by  text NOT NULL,
    uploaded_at  timestamptz NOT NULL DEFAULT now(),
    note         text,
    UNIQUE (project_id, ver_no)
);
-- 一个项目只能有一个当前版本（部分唯一索引兜底，触发器负责自动让位）
CREATE UNIQUE INDEX uq_quote_bom_current ON quote_bom(project_id) WHERE is_current;
COMMENT ON TABLE quote_bom IS
  '报价原始单（基线）。★只读且版本化：传新版不覆盖旧版。'
  '物料账的「原始」一列全部取自当前版本 —— 它是后面所有增减的参照系';

CREATE TABLE quote_bom_line (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bom_id       uuid NOT NULL REFERENCES quote_bom(id) ON DELETE CASCADE,
    line_no      integer NOT NULL CHECK (line_no > 0),
    -- ★认不上的编码：material_id 留空＝挂起。能认的先导入，认不上的卡住下一步 ——
    --   不用为一个编码重传整张表，也不会漏（工程那边会显示「还缺 N 个料没建档」）
    material_id  uuid REFERENCES material(id),
    raw_code     text NOT NULL,                       -- Excel 里的原始编码（原样留着）
    raw_name     text,
    -- ★允许 0：报价里本来有、后来不要了的行，数量调 0 而不是删行
    qty          numeric(12,2) NOT NULL CHECK (qty >= 0),
    note         text,
    UNIQUE (bom_id, line_no)
);
CREATE INDEX idx_qbl_mat ON quote_bom_line(material_id);
COMMENT ON COLUMN quote_bom_line.material_id IS
  '认不上的编码留空＝挂起。★挂起的存在就是为了卡住工程那一步 —— '
  '不卡住的话，现场改了半天最后发现少几个料，前面的活白干';

-- 新版本上传 → 旧版本自动让位（不删，只是不再是 current）
CREATE OR REPLACE FUNCTION trg_quote_bom_current() RETURNS trigger AS $$
BEGIN
    IF NEW.is_current THEN
        UPDATE quote_bom SET is_current = false
         WHERE project_id = NEW.project_id AND id <> NEW.id AND is_current;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER quote_bom_current BEFORE INSERT OR UPDATE ON quote_bom
    FOR EACH ROW EXECUTE FUNCTION trg_quote_bom_current();

-- ★原始单只读：行永远不删，数量也不许改。要改就走变更单（bom_change）。
--   唯一允许的一种改动：把挂起的行补上 material_id（编码后来建档了）。
--   为什么这条这么硬：删了行，「报价里本来有、后来不要了」这件事就消失了，
--   客户回头问「我付的钱里那 10 个面板呢」没人答得上来。
CREATE OR REPLACE FUNCTION trg_quote_bom_line_readonly() RETURNS trigger AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION '门禁：报价原始单的行不能删 —— 报价里本来有、后来不要了的，'
                        '请走变更单把数量调 0。删了行，客户回头问「我付的钱里那些面板呢」就没人答得上来';
    END IF;
    IF NEW.qty IS DISTINCT FROM OLD.qty
       OR NEW.raw_code IS DISTINCT FROM OLD.raw_code
       OR NEW.bom_id  IS DISTINCT FROM OLD.bom_id THEN
        RAISE EXCEPTION '门禁：报价原始单是基线，只读 —— 要调数量请开一张变更单（工程审完才算数）。'
                        '这里一改，后面所有「原始 → 现在」的对比就全失去参照';
    END IF;
    -- 挂起的行补建档：只许从空补成有，不许改成别的料
    IF OLD.material_id IS NOT NULL AND NEW.material_id IS DISTINCT FROM OLD.material_id THEN
        RAISE EXCEPTION '门禁：这一行已经认到物料了，不能改挂到别的物料上 —— '
                        '认错了请传新版报价单，别在基线上改';
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER quote_bom_line_readonly BEFORE UPDATE OR DELETE ON quote_bom_line
    FOR EACH ROW EXECUTE FUNCTION trg_quote_bom_line_readonly();


-- =====================================================================
--  第四十五部分：现场变更 bom_change / bom_change_line
--    现场工程人员在 App 上改 → 暂存 → 提交 → 工程管理负责人审「变量」
-- =====================================================================

-- ★阶段现算，不定格：SM2 完成之前可增可减，之后只能增。
--   为什么不定格 —— 录入那天 SM2 还没完成（可以减），提交之后 SM2 完成了，
--   审批那一刻就该拦。定格成一个值，这道门就会在错误的时点放行。
CREATE OR REPLACE FUNCTION fn_bom_phase(p_project uuid) RETURNS text AS $$
    SELECT CASE WHEN EXISTS (SELECT 1 FROM site_meeting
                              WHERE project_id = p_project AND sm_no = 2
                                AND (completed_at IS NOT NULL OR na_flag))
                THEN 'build' ELSE 'sm2' END;
$$ LANGUAGE sql STABLE;
COMMENT ON FUNCTION fn_bom_phase IS
  'SM2 完成（或标不适用）之前＝sm2 可增可减；之后＝build 只能增。'
  '★现算不定格：施工都开始了还往下减，已经发到工地的料就对不上账，而且不会报错';

CREATE TABLE bom_change (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    change_no     text UNIQUE NOT NULL,
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    bom_id        uuid NOT NULL REFERENCES quote_bom(id),   -- 基于哪一版报价单改的
    -- ★暂存：改到一半锁屏、明天再打开都还在；确认无误再提交，半成品不会跑到审批那儿
    status        text NOT NULL DEFAULT 'draft' CHECK (status IN
                    ('draft','pending','approved','returned')),
    raised_phase  text CHECK (raised_phase IN ('sm2','build')),  -- 提交那一刻的阶段（只留痕）
    raise_note    text,                                   -- 提单理由（工程管理审的就是这句 + 变量）
    raised_by     text NOT NULL,                          -- 现场工程人员（显示名）
    -- ★三级账号（施工人员）只有 App —— RLS 靠这一列认「这是我提的单」
    raised_staff_id uuid REFERENCES eng_staff(id),
    raised_at     timestamptz,                            -- 提交时间（暂存时为空）
    reviewed_by   text,
    reviewed_at   timestamptz,
    -- ★退回原因必填 ≥4 字：只写「不行」，现场不知道该怎么改
    return_reason text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_bc_returned CHECK (status <> 'returned'
                                     OR length(btrim(COALESCE(return_reason,''))) >= 4),
    CONSTRAINT ck_bc_raised   CHECK (status = 'draft' OR raised_at IS NOT NULL),
    CONSTRAINT ck_bc_reviewed CHECK (status NOT IN ('approved','returned')
                                     OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);
CREATE INDEX idx_bc_project ON bom_change(project_id, status);
COMMENT ON TABLE bom_change IS
  '现场物料变更单。★工程管理只审「变量」不看整表 —— 报价单几十上百行，'
  '让负责人逐行核对，实际结果一定是直接点批准，那这道审批就等于不存在';

CREATE TABLE bom_change_line (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    change_id     uuid NOT NULL REFERENCES bom_change(id) ON DELETE CASCADE,
    material_id   uuid NOT NULL REFERENCES material(id),
    -- adjust=报价单里本来就有的料，改数量；additional=报价单里没有的料，加进来
    kind          text NOT NULL CHECK (kind IN ('adjust','additional')),
    qty_from      numeric(12,2) CHECK (qty_from IS NULL OR qty_from >= 0),  -- 改之前是几（留痕）
    -- ★允许 0：换货＝老的减到 0 ＋ Additional 加新的，两个动作都留痕
    qty_to        numeric(12,2) NOT NULL CHECK (qty_to >= 0),
    -- ★Additional 必须写为什么：工程管理只看变量，没理由没法判断
    reason        text,
    UNIQUE (change_id, material_id),          -- ★同一个料不许在一张单里加两遍
    CONSTRAINT ck_bcl_additional CHECK (kind <> 'additional'
                                        OR length(btrim(COALESCE(reason,''))) >= 4)
);
CREATE INDEX idx_bcl_mat ON bom_change_line(material_id);
COMMENT ON TABLE bom_change_line IS
  '变更的每一行。★口径：qty_to 就是这个料【改完之后的应采数】（不是增量）。'
  'adjust 与 additional 统一成这一个口径 —— 增量口径下多张单叠加，谁也算不清最后到底该买几个';

-- ── 行级门禁 ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_bom_change_line_gate() RETURNS trigger AS $$
DECLARE bc bom_change%ROWTYPE; ph text; nm text; in_quote numeric; pcode text;
BEGIN
    SELECT * INTO bc FROM bom_change WHERE id = NEW.change_id;
    SELECT display_name INTO nm FROM material WHERE id = NEW.material_id;
    SELECT code INTO pcode FROM project WHERE id = bc.project_id;
    -- 这个料在当前报价单里有没有、原始几个
    SELECT SUM(l.qty) INTO in_quote
      FROM quote_bom_line l WHERE l.bom_id = bc.bom_id AND l.material_id = NEW.material_id;

    -- ① Additional 不许加报价单里本来就有的料
    --    同一个料摆成两行，采购看到的应采数就错了（而且两行各自看着都对）
    IF NEW.kind = 'additional' AND in_quote IS NOT NULL THEN
        RAISE EXCEPTION '门禁：「%」报价单里本来就有（原始 % 个）—— 请直接改它的数量，'
                        '不要在 Additional 里再加一遍。同一个料摆成两行，采购看到的应采数就错了',
                        nm, in_quote;
    END IF;
    -- ② adjust 只能改报价单里有的料
    IF NEW.kind = 'adjust' AND in_quote IS NULL THEN
        RAISE EXCEPTION '门禁：「%」不在这一版报价单里，改不了它的数量 —— 要加请用 Additional（并写清为什么）', nm;
    END IF;
    -- ③ ★施工中只能增：SM2 之后往下减，已经发到工地甚至装上去的料立刻对不上账，而且不会报错
    ph := fn_bom_phase(bc.project_id);
    IF ph = 'build' AND NEW.qty_to < COALESCE(NEW.qty_from, in_quote, 0) THEN
        RAISE EXCEPTION '门禁：项目 % 的 SM2 已完成，进入施工阶段 —— 「%」只能增不能减'
                        '（原 % → 想改成 %）。料可能已经发到工地甚至装上去了，'
                        '这时候往下减，出库单和物料账立刻对不上。要减请走工程追加/退料流程',
                        pcode, nm, COALESCE(NEW.qty_from, in_quote, 0), NEW.qty_to;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER bom_change_line_gate BEFORE INSERT OR UPDATE ON bom_change_line
    FOR EACH ROW EXECUTE FUNCTION trg_bom_change_line_gate();

-- ── 单据流转门禁：提交 / 批准 / 退回 ────────────────────────────────
CREATE OR REPLACE FUNCTION trg_bom_change_flow() RETURNS trigger AS $$
DECLARE n_pending int; n_line int; ph text; bad text; pcode text;
BEGIN
    SELECT code INTO pcode FROM project WHERE id = NEW.project_id;

    -- 提交（draft → pending）
    IF OLD.status = 'draft' AND NEW.status = 'pending' THEN
        SELECT count(*) INTO n_line FROM bom_change_line WHERE change_id = NEW.id;
        IF n_line = 0 THEN
            RAISE EXCEPTION '门禁：变更单 % 一行变量都没有，提交了工程管理也不知道要审什么', NEW.change_no;
        END IF;
        -- ★这张报价单还有物料没建档就不许提交
        SELECT count(*) INTO n_pending FROM quote_bom_line
         WHERE bom_id = NEW.bom_id AND material_id IS NULL;
        IF n_pending > 0 THEN
            RAISE EXCEPTION '门禁：项目 % 的报价单还有 % 个物料没建档（编码认不上）—— 先找采购建档再提交。'
                            '不然改了半天，最后发现少了几个料，前面的活白干',
                            pcode, n_pending;
        END IF;
        NEW.raised_phase := fn_bom_phase(NEW.project_id);
        NEW.raised_at    := COALESCE(NEW.raised_at, now());
    END IF;

    -- 批准（pending → approved）
    IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
        IF OLD.status <> 'pending' THEN
            RAISE EXCEPTION '门禁：变更单 % 还没提交（当前「%」），批不了 —— 暂存的是半成品',
                            NEW.change_no, OLD.status;
        END IF;
        -- ★SM2 之后带减量的单批不了：只能退回让现场重提一张只增的
        ph := fn_bom_phase(NEW.project_id);
        IF ph = 'build' THEN
            SELECT string_agg(m.display_name || '（' || COALESCE(l.qty_from,0) || '→' || l.qty_to || '）', '、')
              INTO bad
              FROM bom_change_line l JOIN material m ON m.id = l.material_id
             WHERE l.change_id = NEW.id AND l.qty_to < COALESCE(l.qty_from, 0);
            IF bad IS NOT NULL THEN
                RAISE EXCEPTION '门禁：项目 % 的 SM2 已完成，这张单里带减量的行批不了：% —— '
                                '请退回让现场重提一张只增的。施工都开始了还往下减，'
                                '已经发到工地的料就对不上账', pcode, bad;
            END IF;
        END IF;
    END IF;

    -- 已批准的单不许再改（改了物料账会跟着变，而且没人知道）
    IF OLD.status = 'approved' AND NEW.status <> 'approved' THEN
        RAISE EXCEPTION '门禁：变更单 % 已批准并进了项目物料账，不能再改状态 —— '
                        '要撤请新开一张反向变更单，留痕比抹掉干净', NEW.change_no;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER bom_change_flow BEFORE UPDATE ON bom_change
    FOR EACH ROW EXECUTE FUNCTION trg_bom_change_flow();

-- 已批准的单，行也锁死（否则绕过流转门禁改数量）
CREATE OR REPLACE FUNCTION trg_bom_change_line_lock() RETURNS trigger AS $$
DECLARE st text; no_ text;
BEGIN
    SELECT status, change_no INTO st, no_ FROM bom_change
     WHERE id = COALESCE(NEW.change_id, OLD.change_id);
    IF st IN ('approved','pending') THEN
        RAISE EXCEPTION '门禁：变更单 % 已「%」，明细不能再动 —— '
                        '暂存（draft）阶段随便改，提交之后要改请先退回',
                        no_, CASE st WHEN 'approved' THEN '批准' ELSE '提交待审' END;
    END IF;
    RETURN COALESCE(NEW, OLD);
END $$ LANGUAGE plpgsql;
CREATE TRIGGER bom_change_line_lock BEFORE UPDATE OR DELETE ON bom_change_line
    FOR EACH ROW EXECUTE FUNCTION trg_bom_change_line_lock();


-- =====================================================================
--  第四十六部分：库管备料 bom_reserve
--    ★这一步的全部意义：让采购别再去买。仓库明明有货还下单，钱就白花了，而且没人会发现
-- =====================================================================
CREATE TABLE bom_reserve (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id   uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    material_id  uuid NOT NULL REFERENCES material(id),
    qty          numeric(12,2) NOT NULL CHECK (qty > 0),
    note         text,
    reserved_by  text NOT NULL,
    reserved_at  timestamptz NOT NULL DEFAULT now(),
    -- 出库之后（或撤销）释放；释放了就不再占着现货
    released_at  timestamptz,
    release_note text
);
CREATE INDEX idx_reserve_open ON bom_reserve(project_id, material_id) WHERE released_at IS NULL;
COMMENT ON TABLE bom_reserve IS
  '库管备料：从现货里拨给项目。★只是占住，不扣库存 —— 真正扣是在【出库】那一刻'
  '（要 S2 结清、要提货人签收）。备料就扣的话，货还在架子上账面却没了，盘点永远对不上';

-- ★备料门禁：不能多拨 · 现货不够不许先占后补
CREATE OR REPLACE FUNCTION trg_bom_reserve_gate() RETURNS trigger AS $$
DECLARE nm text; pcode text; onhand numeric; other_res numeric; free_qty numeric;
        need numeric; ordered numeric; mine numeric;
BEGIN
    -- 释放、或减少占量：只会让现货更宽松，不必检查。
    -- （出库后系统会自动来销备料 —— 那一刻库存已经扣了，再按「现货够不够」查一遍
    --   一定拦得住合法的销账，把正常出库卡死）
    IF TG_OP = 'UPDATE'
       AND ((OLD.released_at IS NULL AND NEW.released_at IS NOT NULL) OR NEW.qty <= OLD.qty) THEN
        RETURN NEW;
    END IF;

    SELECT display_name INTO nm FROM material WHERE id = NEW.material_id;
    SELECT code INTO pcode FROM project WHERE id = NEW.project_id;

    -- ① 现货够不够（现货 − 别人已备）
    SELECT COALESCE(qty_on_hand,0) INTO onhand FROM v_material_stock WHERE material_id = NEW.material_id;
    SELECT COALESCE(SUM(qty),0) INTO other_res FROM bom_reserve
     WHERE material_id = NEW.material_id AND released_at IS NULL AND id <> NEW.id;
    free_qty := COALESCE(onhand,0) - other_res;
    IF NEW.qty > free_qty THEN
        RAISE EXCEPTION '门禁：「%」现货只剩 %（库存 % − 别的项目已备 %），备 % 不够 —— '
                        '★现货不够不许先占后补：占了采购就不买，到时候两头都没有',
                        nm, free_qty, COALESCE(onhand,0), other_res, NEW.qty;
    END IF;

    -- ② 不能比「还要的」多（应采 − 已下单 − 本项目其他已备）
    SELECT COALESCE(qty_required,0), COALESCE(qty_ordered,0)
      INTO need, ordered
      FROM v_project_bom WHERE project_id = NEW.project_id AND material_id = NEW.material_id;
    SELECT COALESCE(SUM(qty),0) INTO mine FROM bom_reserve
     WHERE project_id = NEW.project_id AND material_id = NEW.material_id
       AND released_at IS NULL AND id <> NEW.id;
    IF NEW.qty > GREATEST(COALESCE(need,0) - COALESCE(ordered,0) - mine, 0) THEN
        RAISE EXCEPTION '门禁：项目 % 的「%」还需要 %（应采 % − 已下单 % − 已备 %），备 % 就多了 —— '
                        '多备的货占着别的项目要用的现货，而且账面上看不出来',
                        pcode, nm,
                        GREATEST(COALESCE(need,0) - COALESCE(ordered,0) - mine, 0),
                        COALESCE(need,0), COALESCE(ordered,0), mine, NEW.qty;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
-- 触发器在 v_project_bom 建好之后再挂（函数里引用了它）


-- =====================================================================
--  第四十七部分：出货单 mat_req / mat_req_line（从派工排班来）
--    ★入口在排班：谁去提、什么时候提，只有排班这一刻才知道。
--      排完人再单独跑一趟别的页面提料，十次有八次会忘 —— 然后人到了工地
--      才发现没货，白跑一趟，而且系统不会报错。
-- =====================================================================
CREATE TABLE mat_req (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    req_no        text UNIQUE NOT NULL,
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    job_kind      text NOT NULL CHECK (job_kind IN ('install','sm','maintenance')),
    need_by       date,                              -- 哪天要用（＝派工那天）
    for_staff_id  uuid REFERENCES eng_staff(id),     -- 派给谁（＝去提货的人）
    -- ★SM2 预提线材窄通道（§23.八·3）：SM2 那天我方人员要带线材去现场，
    --   可那时 S2 物料款根本还没开（S2 要 SM3 完成才解锁），照原门禁一定被拦，工地就停在那儿。
    --   四道锁：①只我方人员 ②只线材 ③用途必填 ≥4 字 ④照样定格单价、进未退料台账、按 S4 结
    is_sm2_cable  boolean NOT NULL DEFAULT false,
    purpose       text,
    status        text NOT NULL DEFAULT 'raised' CHECK (status IN
                    ('raised','short','ready','released','cancelled')),
    -- 缺货：工程去问采购拿 lead time 填回来，库管和现场同一句话都看得到
    lead_time_note text,
    stock_out_id  uuid REFERENCES stock_out(id),     -- 真出库之后回填
    raised_by     text NOT NULL,
    raised_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_mr_sm2 CHECK (NOT is_sm2_cable
                                OR length(btrim(COALESCE(purpose,''))) >= 4),
    -- ★缺货必须写清交期：不写就只是「缺货」两个字，工程既不知道要等多久，也没法改排班
    CONSTRAINT ck_mr_short CHECK (status <> 'short'
                                  OR length(btrim(COALESCE(lead_time_note,''))) >= 4),
    CONSTRAINT ck_mr_released CHECK (status <> 'released' OR stock_out_id IS NOT NULL)
);
CREATE INDEX idx_mr_project ON mat_req(project_id, status);
COMMENT ON TABLE mat_req IS
  '出货单：排班时勾「去仓库办提货」自动生成，交库管核对库存。'
  '★够→安排出货（开出库单那一刻才真正扣库存）；不够→同时提醒采购（去买）和工程（别派人白跑）';

CREATE TABLE mat_req_line (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    req_id        uuid NOT NULL REFERENCES mat_req(id) ON DELETE CASCADE,
    material_id   uuid NOT NULL REFERENCES material(id),
    qty           numeric(12,2) NOT NULL CHECK (qty > 0),
    note          text,
    UNIQUE (req_id, material_id)
);

-- ★SM2 预提窄通道：只我方人员、只线材。第三方一律不走这条通道
CREATE OR REPLACE FUNCTION fn_is_cable_material(p_material uuid) RETURNS boolean AS $$
    SELECT EXISTS (
      SELECT 1 FROM material m
       WHERE m.id = p_material
         AND lower(btrim(m.category)) IN (
             SELECT lower(btrim(t.v)) FROM jsonb_array_elements_text(
               COALESCE((SELECT value_text FROM eng_setting WHERE key='wh_cable_categories')::jsonb,
                        '["cable"]'::jsonb)) AS t(v)));
$$ LANGUAGE sql STABLE;
COMMENT ON FUNCTION fn_is_cable_material IS
  '这个料算不算「线材」。品类名单在 eng_setting.wh_cable_categories 里，库管可改 —— '
  '★写死在代码里，以后加一个品类就要改 DDL，实际结果是没人改，窄通道悄悄失效';

CREATE OR REPLACE FUNCTION trg_mat_req_line_gate() RETURNS trigger AS $$
DECLARE mr mat_req%ROWTYPE; nm text;
BEGIN
    SELECT * INTO mr FROM mat_req WHERE id = NEW.req_id;
    IF mr.is_sm2_cable THEN
        SELECT display_name INTO nm FROM material WHERE id = NEW.material_id;
        IF NOT fn_is_cable_material(NEW.material_id) THEN
            RAISE EXCEPTION '门禁：SM2 预提只能提线材，「%」不是 —— '
                            '面板模块这些钱的大头照旧要等 S2 物料款结清。'
                            '这条窄通道只为了让 SM2 那天工地不停在那儿，不是绕开 S2 的口子', nm;
        END IF;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER mat_req_line_gate BEFORE INSERT OR UPDATE ON mat_req_line
    FOR EACH ROW EXECUTE FUNCTION trg_mat_req_line_gate();

CREATE OR REPLACE FUNCTION trg_mat_req_gate() RETURNS trigger AS $$
DECLARE nm text;
BEGIN
    IF NEW.is_sm2_cable THEN
        -- ★只我方人员：第三方（Builder/电工/其他工种）一律不走这条通道
        IF NEW.for_staff_id IS NULL THEN
            RAISE EXCEPTION '门禁：SM2 预提线材只能由我方人员去提 —— 出货单上必须写明是谁。'
                            '第三方（Builder/电工/其他工种）一律等 S2 物料款结清';
        END IF;
        IF NEW.job_kind <> 'sm' THEN
            RAISE EXCEPTION '门禁：SM2 预提线材只能挂在 Site Meeting 的排班上（当前「%」）', NEW.job_kind;
        END IF;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER mat_req_gate BEFORE INSERT OR UPDATE ON mat_req
    FOR EACH ROW EXECUTE FUNCTION trg_mat_req_gate();


-- =====================================================================
--  ★ v_project_bom：项目物料账 —— 一个项目一本账，全部现算
--    原始（当前版本报价单）
--    → 变更（已批准的，取每个料最近一条：qty_to 就是改完之后的应采数）
--    = 应采  −已下单 −库管已备 = ★还要买
--    ★买多了 = 已下单 + 已备 − 应采（工程后来减了量，这批货已经花了钱）
-- =====================================================================
CREATE VIEW v_project_bom AS
WITH cur AS (   -- 每个项目的当前版本报价单
    SELECT id AS bom_id, project_id, ver_no FROM quote_bom WHERE is_current
), orig AS (    -- 原始：只算认到物料的行（挂起的行还没有 material_id，进不了账）
    SELECT c.project_id, l.material_id, SUM(l.qty) AS qty_orig
      FROM cur c JOIN quote_bom_line l ON l.bom_id = c.bom_id
     WHERE l.material_id IS NOT NULL
     GROUP BY c.project_id, l.material_id
), chg AS (     -- 变更：每个 (项目,物料) 取最近一条【已批准】的（后面的覆盖前面的）
    SELECT DISTINCT ON (b.project_id, l.material_id)
           b.project_id, l.material_id, l.qty_to, l.kind, b.change_no, b.reviewed_at
      FROM bom_change b JOIN bom_change_line l ON l.change_id = b.id
     WHERE b.status = 'approved'
     ORDER BY b.project_id, l.material_id, b.reviewed_at DESC, b.change_no DESC
), pend AS (    -- ★待审的不算进应采 —— 审完才算数，否则采购会照着还没批的数去下单
    SELECT b.project_id, l.material_id, SUM(l.qty_to) AS qty_pending, count(*) AS pending_n
      FROM bom_change b JOIN bom_change_line l ON l.change_id = b.id
     WHERE b.status = 'pending'
     GROUP BY b.project_id, l.material_id
), ord AS (     -- 已下单：为这个项目开的采购单
    SELECT po.ref_project_id AS project_id, pl.material_id, SUM(pl.qty_ordered) AS qty_ordered
      FROM purchase_order po JOIN purchase_order_line pl ON pl.po_id = po.id
     WHERE po.ref_project_id IS NOT NULL AND po.status <> 'cancelled'
     GROUP BY po.ref_project_id, pl.material_id
), res AS (     -- 库管已备（未释放）
    SELECT project_id, material_id, SUM(qty) AS qty_reserved
      FROM bom_reserve WHERE released_at IS NULL
     GROUP BY project_id, material_id
), outq AS (    -- 已出库（这个项目实际拿走的）
    SELECT so.project_id, ol.material_id, SUM(ol.qty) AS qty_out
      FROM stock_out so JOIN stock_out_line ol ON ol.stock_out_id = so.id
     GROUP BY so.project_id, ol.material_id
), base AS (
    SELECT c.project_id, k.material_id
      FROM cur c
      CROSS JOIN LATERAL (
        SELECT material_id FROM orig WHERE project_id = c.project_id
        UNION SELECT material_id FROM chg  WHERE project_id = c.project_id
        UNION SELECT material_id FROM ord  WHERE project_id = c.project_id
        UNION SELECT material_id FROM res  WHERE project_id = c.project_id
        UNION SELECT material_id FROM outq WHERE project_id = c.project_id
      ) k
)
SELECT b.project_id, b.material_id,
       m.code AS material_code, m.display_name, m.category, m.purchase_class,
       cur.ver_no AS bom_ver,
       COALESCE(o.qty_orig, 0)                                   AS qty_orig,
       ch.qty_to                                                 AS qty_changed_to,
       ch.change_no                                              AS last_change_no,
       COALESCE(p.qty_pending, 0)                                AS qty_pending,
       COALESCE(p.pending_n, 0)                                  AS pending_n,
       -- ★应采：有已批变更就以变更后的数为准，否则就是原始数
       COALESCE(ch.qty_to, o.qty_orig, 0)                        AS qty_required,
       COALESCE(od.qty_ordered, 0)                               AS qty_ordered,
       COALESCE(r.qty_reserved, 0)                               AS qty_reserved,
       COALESCE(oq.qty_out, 0)                                   AS qty_out,
       -- ★还要买 ＝ 应采 − 已下单 − 已备
       GREATEST(COALESCE(ch.qty_to, o.qty_orig, 0)
                - COALESCE(od.qty_ordered, 0) - COALESCE(r.qty_reserved, 0), 0) AS qty_gap,
       -- ★买多了 ＝ 已下单 + 已备 − 应采（>0 就该标红：这笔钱已经花了）
       GREATEST(COALESCE(od.qty_ordered, 0) + COALESCE(r.qty_reserved, 0)
                - COALESCE(ch.qty_to, o.qty_orig, 0), 0)         AS qty_over,
       -- 仓库现在能顶多少（现货 − 全部项目已备）
       GREATEST(COALESCE(st.qty_on_hand, 0)
                - COALESCE((SELECT SUM(qty) FROM bom_reserve
                             WHERE material_id = b.material_id AND released_at IS NULL), 0), 0)
                                                                 AS qty_free_stock
  FROM base b
  JOIN material m ON m.id = b.material_id
  JOIN cur              ON cur.project_id = b.project_id
  LEFT JOIN orig o      ON o.project_id  = b.project_id AND o.material_id  = b.material_id
  LEFT JOIN chg  ch     ON ch.project_id = b.project_id AND ch.material_id = b.material_id
  LEFT JOIN pend p      ON p.project_id  = b.project_id AND p.material_id  = b.material_id
  LEFT JOIN ord  od     ON od.project_id = b.project_id AND od.material_id = b.material_id
  LEFT JOIN res  r      ON r.project_id  = b.project_id AND r.material_id  = b.material_id
  LEFT JOIN outq oq     ON oq.project_id = b.project_id AND oq.material_id = b.material_id
  LEFT JOIN v_material_stock st ON st.material_id = b.material_id;
COMMENT ON VIEW v_project_bom IS
  '★项目物料账（全部现算，一个数都不落库）。项目料的需求【只有这一份】—— '
  '六十三轮踩过的坑：purchase_req 存一份、这里再算一份，同一件事两个数字，'
  '迟早对不上而且不会报错。qty_over>0 ＝ 买多了，整行标红：工程后来减了量，'
  '那批货的钱已经花出去了，不标出来就悄悄留在项目成本里，谁也不会发现';

-- 备料门禁引用了 v_project_bom，视图建好之后再挂触发器
CREATE TRIGGER bom_reserve_gate BEFORE INSERT OR UPDATE ON bom_reserve
    FOR EACH ROW EXECUTE FUNCTION trg_bom_reserve_gate();

-- 项目层面的一句话：现在卡在哪
CREATE VIEW v_project_bom_summary AS
SELECT b.project_id,
       max(b.bom_ver)                       AS bom_ver,
       count(*)                             AS line_n,
       SUM(b.qty_required)                  AS required_total,
       SUM(b.qty_ordered)                   AS ordered_total,
       SUM(b.qty_reserved)                  AS reserved_total,
       SUM(b.qty_gap)                       AS gap_total,
       SUM(b.qty_over)                      AS over_total,
       SUM(b.pending_n)                     AS pending_line_n,
       (SELECT count(*) FROM quote_bom q JOIN quote_bom_line l ON l.bom_id = q.id
         WHERE q.project_id = b.project_id AND q.is_current AND l.material_id IS NULL)
                                            AS unmapped_n,
       CASE
         WHEN (SELECT count(*) FROM quote_bom q JOIN quote_bom_line l ON l.bom_id = q.id
                WHERE q.project_id = b.project_id AND q.is_current AND l.material_id IS NULL) > 0
              THEN '★有物料没建档，现场改不了也提不了'
         WHEN SUM(b.pending_n) > 0 THEN '等工程管理审变更'
         WHEN SUM(b.qty_over)  > 0 THEN '★买多了，要处理（退供应商或转公司备货）'
         WHEN SUM(b.qty_gap)   > 0 THEN '等采购下单'
         ELSE '齐了'
       END                                  AS stuck_where
  FROM v_project_bom b
 GROUP BY b.project_id;
COMMENT ON VIEW v_project_bom_summary IS
  '采购「采购需求」页的项目总览层：哪些项目现在有采购的事 + ★「现在卡在哪」一句话';

-- 待审变更的「变量」清单 —— 工程管理审批页的数据源（★只摆变量，不摆整表）
CREATE VIEW v_bom_change_pending AS
SELECT b.id AS change_id, b.change_no, b.project_id, b.status,
       b.raise_note, b.raised_by, b.raised_at,
       fn_bom_phase(b.project_id)                       AS phase_now,
       (current_date - b.raised_at::date)               AS waiting_days,
       (SELECT count(*) FROM bom_change_line l WHERE l.change_id = b.id) AS line_n,
       -- ★会不会被门禁拦：SM2 之后带减量的批不了
       EXISTS (SELECT 1 FROM bom_change_line l
                WHERE l.change_id = b.id AND l.qty_to < COALESCE(l.qty_from, 0))
         AND fn_bom_phase(b.project_id) = 'build'       AS blocked_by_gate,
       (SELECT string_agg(m.display_name || ' ' || COALESCE(l.qty_from,0) || '→' || l.qty_to
                          || CASE WHEN l.kind='additional' THEN '（新加：'||COALESCE(l.reason,'')||'）' ELSE '' END,
                          E'\n' ORDER BY m.code)
          FROM bom_change_line l JOIN material m ON m.id = l.material_id
         WHERE l.change_id = b.id)                      AS delta_text
  FROM bom_change b
 WHERE b.status = 'pending';
COMMENT ON VIEW v_bom_change_pending IS
  '工程管理「物料变更审批」页：★这页只摆变量，不摆整表。'
  '报价单几十上百行，让负责人逐行核对，实际结果一定是直接点批准，那这道审批就等于不存在。'
  'blocked_by_gate=true 的按钮要直接禁用并说明为什么（SM2 之后带减量的批不了）';


-- #####################################################################
-- ##  v0.37 ②：采购需求来源重写 —— ★推翻 v0.36 的「项目料由库管下达」
-- #####################################################################
--  v0.36 落的规矩是「要不要采购的指令一定由库管下达」。采购负责人试用后指出：
--  项目采购应该由【项目工程人员】提单（SM2 后），Variation 也由项目负责人提单，
--  工程审完再到采购。老板 2026-08-05 拍板采纳 —— 方案和现场情况工程人员最清楚，
--  库管管的是仓库不是项目。库管补货那一档不变（C1 低于红线，系统现算）。

ALTER TABLE purchase_req DROP CONSTRAINT IF EXISTS purchase_req_source_check;
ALTER TABLE purchase_req DROP CONSTRAINT IF EXISTS ck_req_project;

-- 老数据迁移：project_demand 是 v0.36 的口径，按新口径它就是「报价原始单」这一段
UPDATE purchase_req SET source = 'quote' WHERE source = 'project_demand';

ALTER TABLE purchase_req ADD CONSTRAINT purchase_req_source_check CHECK (source IN (
    'quote',              -- ①报价原始单（工程人员按方案提）
    'sm2_change',         -- ②SM2 现场变更（工程人员在 App 改，工程管理审完）
    'build_add',          -- ③施工新增（SM2 之后只能增）
    'warehouse_restock',  -- ④库管补货：C1 常备件低于红线，系统现算 —— ★这一档不变
    'maintenance'         -- ⑤运维缺料：维护料不在报价物料账里，只有它单独进采购需求（§23.九）
));
-- 只有库管补货是公司级；其余四档都必须落到项目
ALTER TABLE purchase_req ADD CONSTRAINT ck_req_project
    CHECK (source = 'warehouse_restock' OR project_id IS NOT NULL);

COMMENT ON TABLE purchase_req IS
  '采购需求。★v0.37 推翻 v0.36：项目料的提单人＝【工程人员】（SM2 后），不再是库管。'
  '库管只保留 C1 补货那一档。★施工项目料的「还要买」由 v_project_bom 现算，不在这张表里重复存一份 —— '
  '六十三轮踩过的坑：同一件事两个数字，迟早对不上而且不会报错';
COMMENT ON COLUMN purchase_req.source IS
  'quote 报价原始单 / sm2_change SM2 变更 / build_add 施工新增（三档＝工程人员提）'
  ' / warehouse_restock 库管补货（系统现算）/ maintenance 运维缺料（维护料不在项目物料账里）';

UPDATE table_ownership
   SET write_dept = ARRAY['eng_mgmt','warehouse','procurement','maintenance'],
       note = 'v0.37：★项目料由工程人员提单（推翻 v0.36 的库管下达）；'
              '库管只提 C1 补货、运维只提维护缺料；采购不能自己新建，只能退回并写原因'
 WHERE table_name = 'purchase_req';

UPDATE assertion_def
   SET label = '采购需求的来源必须是五档之一（项目料由工程人员提）',
       query = $q$SELECT req_no, source FROM purchase_req
                   WHERE source NOT IN ('quote','sm2_change','build_add',
                                        'warehouse_restock','maintenance')$q$,
       hint  = '★v0.37 口径：项目料的提单人是工程人员（方案和现场他最清楚），'
               '库管只管 C1 补货，采购永远只是执行者 —— 采购不能自己决定要不要买'
 WHERE code = 'INV-PC-02';


-- #####################################################################
-- ##  v0.37 ③：提货人两类 · 通知来提货 · SM2 预提线材窄通道（§23.八~九）
-- #####################################################################

-- =====================================================================
--  澳洲手机号：归一 + 校验
--  ★为什么要在「填的那一刻」就卡住：号码错了系统【不会报错】——
--    短信照发，只是永远发不到；Twilio 的失败回执是异步的，界面上根本看不见。
--    等到「货堆在仓库没人来拉」「客户说从没收到催款短信」才发现，已经晚了。
--  ★为什么必须归一：同一个人被记成 0412345678 / +61412345678 / 0412 345 678
--    三份，去重就永远对不上 —— 而这也不会报错。
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_norm_au_mobile(p text) RETURNS text AS $$
DECLARE d text;
BEGIN
    IF p IS NULL OR btrim(p) = '' THEN RETURN NULL; END IF;
    d := regexp_replace(p, '[^0-9]', '', 'g');
    -- 剥各种国家码写法，统一还原成 9 位本地号（4xxxxxxxx）
    IF length(d) = 13 AND left(d,4) = '0061' THEN d := substr(d,5);  END IF;
    IF length(d) = 12 AND left(d,3) = '610'  THEN d := substr(d,4);  END IF;  -- +61 0412…
    IF length(d) = 11 AND left(d,2) = '61'   THEN d := substr(d,3);  END IF;
    IF length(d) = 10 AND left(d,1) = '0'    THEN d := substr(d,2);  END IF;
    -- ★只认手机号（04 开头）：座机收不到短信，填了就是永远收不到
    IF d ~ '^4[0-9]{8}$' THEN
        RETURN '+61 ' || substr(d,1,3) || ' ' || substr(d,4,3) || ' ' || substr(d,7,3);
    END IF;
    RETURN NULL;
END $$ LANGUAGE plpgsql IMMUTABLE;
COMMENT ON FUNCTION fn_norm_au_mobile IS
  '澳洲手机号归一成 +61 4xx xxx xxx。不是澳洲手机号（含座机、境外号）一律返回 NULL。'
  '★供应商可以用境外号（催货走邮件和电话，不发短信），所以供应商那条线不用这个函数';

CREATE OR REPLACE FUNCTION fn_is_au_mobile(p text) RETURNS boolean AS $$
    SELECT fn_norm_au_mobile(p) IS NOT NULL;
$$ LANGUAGE sql IMMUTABLE;

-- =====================================================================
--  提货人 party_pickup：Builder / 电工立项时就录了，★其他工种谁来拉货就现加一个
--  （库管在「项目出库状态」里加）。我方人员走 eng_staff，不进这张表。
-- =====================================================================
CREATE TABLE party_pickup (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    -- 第三方·工地：Builder / 电工 / 其他工种（泥水、木工、防水…）
    trade         text NOT NULL,
    company       text,
    contact_name  text NOT NULL,
    -- ★必须是澳洲手机号：要发中英双语提货短信，没号码等于没通知
    phone         text NOT NULL CHECK (fn_is_au_mobile(phone)),
    -- 语言：第三方多半不看中文，发中文等于没发 → 默认双语
    lang          text NOT NULL DEFAULT 'both' CHECK (lang IN ('zh','en','both')),
    party_id      uuid REFERENCES project_party(id),   -- 从立项参建方带过来的话挂上
    note          text,
    active        boolean NOT NULL DEFAULT true,
    created_by    text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    -- ★同一个项目同一个号不许录两个人：短信回 Y 分不清是谁回的
    UNIQUE (project_id, phone)
);
CREATE INDEX idx_pp_pickup ON party_pickup(project_id) WHERE active;
COMMENT ON TABLE party_pickup IS
  '第三方提货人（Builder / 电工 / 其他工种）。★手机号必填且必须是澳洲手机号 —— '
  '没号码就不许通知也不许出库：短信发不出去等于没发，而系统不会报错，'
  '货就一直堆在仓库没人来拉';

-- 手机号一律归一（同一个人三种写法，去重永远对不上）
CREATE OR REPLACE FUNCTION trg_norm_pickup_phone() RETURNS trigger AS $$
BEGIN
    NEW.phone := COALESCE(fn_norm_au_mobile(NEW.phone), NEW.phone);
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER norm_pickup_phone BEFORE INSERT OR UPDATE ON party_pickup
    FOR EACH ROW EXECUTE FUNCTION trg_norm_pickup_phone();

-- =====================================================================
--  wh_call「通知来提货」—— ★与出库后的「催提货确认」是两回事，别混
--    · 通知来提货：出库【之前】，货备齐了叫人来拉。库管主动、手工发
--    · 催提货确认：出库【之后】，清单已发出，等提货人回 YES 认领
--    中间隔着「开出库单」那一下 —— ★那一刻才真正扣库存
--  ★为什么不做自动定时催（用户明确要手工）：什么时候叫人来拉，取决于工地进度
--    和车什么时候有空，系统不知道，库管知道。自动发只会变成没人看的短信。
-- =====================================================================
CREATE TABLE wh_call (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id     uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    -- 两类提货人，二选一（我方＝eng_staff，第三方＝party_pickup）
    staff_id       uuid REFERENCES eng_staff(id),
    pickup_id      uuid REFERENCES party_pickup(id),
    -- 定格：发出去那一刻的姓名与号码（人后来换号了，也得知道当初通知的是谁）
    to_name        text NOT NULL,
    to_phone       text NOT NULL CHECK (fn_is_au_mobile(to_phone)),
    lang           text NOT NULL CHECK (lang IN ('zh','en','both')),
    -- 定格：仓库地址与营业时间原样写进短信；设置里改了只影响之后发出的
    wh_address     text NOT NULL,
    wh_hours       text NOT NULL,
    body           text,
    called_by      text NOT NULL,
    called_at      timestamptz NOT NULL DEFAULT now(),
    -- 开了出库单就不再算「已通知、人还没来提」
    stock_out_id   uuid REFERENCES stock_out(id),
    CONSTRAINT ck_call_who CHECK (
        (staff_id IS NOT NULL AND pickup_id IS NULL) OR
        (staff_id IS NULL AND pickup_id IS NOT NULL)),
    -- 第三方发中英双语（他们多半不看中文）
    CONSTRAINT ck_call_lang CHECK (pickup_id IS NULL OR lang <> 'zh')
);
CREATE INDEX idx_whcall_open ON wh_call(project_id) WHERE stock_out_id IS NULL;
COMMENT ON TABLE wh_call IS
  '「通知来提货」（出库之前，库管手工发）。★与出库后的「催提货确认」分开记 —— '
  '混在一起就分不清「叫了人没来」和「货给了没回执」，这是两个完全不同的问题';

CREATE OR REPLACE FUNCTION trg_norm_call_phone() RETURNS trigger AS $$
BEGIN
    NEW.to_phone := COALESCE(fn_norm_au_mobile(NEW.to_phone), NEW.to_phone);
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER norm_call_phone BEFORE INSERT OR UPDATE ON wh_call
    FOR EACH ROW EXECUTE FUNCTION trg_norm_call_phone();

-- =====================================================================
--  出库：★没手机号不许出库 + SM2 预提线材窄通道
-- =====================================================================
ALTER TABLE stock_out ADD COLUMN IF NOT EXISTS receiver_pickup_id uuid REFERENCES party_pickup(id);
ALTER TABLE stock_out ADD COLUMN IF NOT EXISTS mat_req_id uuid REFERENCES mat_req(id);
-- ★SM2 预提线材：四道锁齐了才放行 S2 门禁
ALTER TABLE stock_out ADD COLUMN IF NOT EXISTS sm2_cable_release boolean NOT NULL DEFAULT false;
ALTER TABLE stock_out ADD COLUMN IF NOT EXISTS sm2_purpose text;
COMMENT ON COLUMN stock_out.sm2_cable_release IS
  '★SM2 预提线材通道（老板拍板的例外）。SM2 那天我方人员要带线材去现场，'
  '可那时 S2 物料款还没开（S2 要 SM3 完成才解锁），照原门禁一定被拦，工地就停在那儿。'
  '四道锁：只我方人员 · 只线材 · 用途必填 ≥4 字 · 照样定格单价+进未退料台账+按 S4 结算 —— 一分钱不会丢';

-- ★没手机号不许出库（三类提货人一视同仁）
CREATE OR REPLACE FUNCTION trg_out_phone_gate() RETURNS trigger AS $$
DECLARE ph text; who text;
BEGIN
    IF NEW.receiver_staff_id IS NOT NULL THEN
        SELECT phone, name INTO ph, who FROM eng_staff WHERE id = NEW.receiver_staff_id;
    ELSIF NEW.receiver_pickup_id IS NOT NULL THEN
        SELECT phone, contact_name INTO ph, who FROM party_pickup WHERE id = NEW.receiver_pickup_id;
    ELSIF NEW.receiver_party_id IS NOT NULL THEN
        SELECT phone, contact_name INTO ph, who FROM project_party WHERE id = NEW.receiver_party_id;
    END IF;
    ph := COALESCE(NEW.receiver_phone, ph);
    IF NOT fn_is_au_mobile(ph) THEN
        RAISE EXCEPTION '门禁：提货人「%」没有可用的澳洲手机号（现在是「%」）—— 不许开出库单。'
                        '提货清单和催回执全靠短信，号码不对就永远发不到，'
                        '而系统不会报错，货只会一直堆在仓库没人来拉。请先补号码（+61 4xx xxx xxx）',
                        COALESCE(who,'未知'), COALESCE(ph,'空');
    END IF;
    NEW.receiver_phone := fn_norm_au_mobile(ph);
    NEW.receiver_name  := COALESCE(NEW.receiver_name, who);
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER out_phone_gate BEFORE INSERT ON stock_out
    FOR EACH ROW EXECUTE FUNCTION trg_out_phone_gate();

-- 二选一约束放宽到三选一（新增 receiver_pickup_id）
ALTER TABLE stock_out DROP CONSTRAINT IF EXISTS ck_out_receiver;
ALTER TABLE stock_out ADD CONSTRAINT ck_out_receiver CHECK (
    (receiver_staff_id  IS NOT NULL)::int +
    (receiver_party_id  IS NOT NULL)::int +
    (receiver_pickup_id IS NOT NULL)::int = 1);

-- ★S2 门禁重写：SM2 预提线材放行，其余【照旧卡死】
CREATE OR REPLACE FUNCTION trg_out_s2_gate() RETURNS trigger AS $$
DECLARE s2_ok boolean; pcode text; sm2_done boolean;
BEGIN
    SELECT code INTO pcode FROM project WHERE id = NEW.project_id;

    IF NEW.sm2_cable_release THEN
        -- ★四道锁之一二三（第四道「照样定格单价、进未退料台账、按 S4 结」走既有机制，
        --   不需要在这里额外处理 —— 这条通道走的就是普通出库那一套账）
        IF NEW.receiver_staff_id IS NULL THEN
            RAISE EXCEPTION '门禁：项目 % 的 SM2 预提线材只能由我方人员提 —— '
                            '第三方（Builder/电工/其他工种）一律等 S2 物料款结清。'
                            '这条窄通道只为了让 SM2 那天工地不停在那儿，不是绕开 S2 的口子', pcode;
        END IF;
        IF length(btrim(COALESCE(NEW.sm2_purpose,''))) < 4 THEN
            RAISE EXCEPTION '门禁：SM2 预提线材必须写清用途（≥4 字）—— '
                            '这批货绕过了 S2 物料款那道门，用途写不清楚，S4 结算时就说不明白这笔钱';
        END IF;
        -- 线材由明细触发器逐行卡（trg_out_sm2_cable_gate）
        RETURN NEW;
    END IF;

    SELECT (status='settled') INTO s2_ok FROM payment_milestone
     WHERE project_id = NEW.project_id AND kind='contract' AND stage='S2';
    IF s2_ok IS DISTINCT FROM true THEN
        RAISE EXCEPTION '门禁：项目 % 的 S2 物料款未结清，不能出库放货', pcode;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

-- ★第二道锁：只线材。挂在明细上逐行卡
CREATE OR REPLACE FUNCTION trg_out_sm2_cable_gate() RETURNS trigger AS $$
DECLARE so stock_out%ROWTYPE; nm text;
BEGIN
    SELECT * INTO so FROM stock_out WHERE id = NEW.stock_out_id;
    IF so.sm2_cable_release AND NOT fn_is_cable_material(NEW.material_id) THEN
        SELECT display_name INTO nm FROM material WHERE id = NEW.material_id;
        RAISE EXCEPTION '门禁：SM2 预提只能提线材，「%」不是 —— '
                        '面板模块这些钱的大头照旧要等 S2 物料款结清', nm;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER out_sm2_cable_gate BEFORE INSERT OR UPDATE ON stock_out_line
    FOR EACH ROW EXECUTE FUNCTION trg_out_sm2_cable_gate();

-- 出库之后：把对应的备料释放掉
-- ★为什么必须释放：出库那一刻库存已经真扣了，备料要是还占着，
--   「仓库能顶多少」就被同一批货扣了两遍 —— 采购看到的现货凭空少一截，
--   于是去买本来不用买的东西，而且不会报错。
CREATE OR REPLACE FUNCTION trg_out_release_reserve() RETURNS trigger AS $$
DECLARE pid uuid; remain numeric; r record;
BEGIN
    SELECT project_id INTO pid FROM stock_out WHERE id = NEW.stock_out_id;
    remain := NEW.qty;
    -- 先进先出：销到覆盖本次出库量为止；最后一条不够整销的按剩余量拆分
    FOR r IN SELECT * FROM bom_reserve
              WHERE project_id = pid AND material_id = NEW.material_id AND released_at IS NULL
              ORDER BY reserved_at, id
    LOOP
        EXIT WHEN remain <= 0;
        IF r.qty <= remain THEN
            UPDATE bom_reserve SET released_at = now(),
                   release_note = COALESCE(release_note || ' ', '') || '（已出库）'
             WHERE id = r.id;
            remain := remain - r.qty;
        ELSE
            -- 只出了一部分：把这条的占量减掉已出的，剩下的继续占着
            -- （不另起一条 —— 备料条的 qty 本来就是「现在还占着多少」）
            UPDATE bom_reserve
               SET qty = r.qty - remain,
                   note = COALESCE(note || ' ', '') || '（出库 ' || remain || ' 后余量）'
             WHERE id = r.id;
            remain := 0;
        END IF;
    END LOOP;
    RETURN NULL;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER out_release_reserve AFTER INSERT ON stock_out_line
    FOR EACH ROW EXECUTE FUNCTION trg_out_release_reserve();

-- ── 视图：库管「项目出库状态」的八个状态页签 ──────────────────────
--    ★六十七轮用户纠正：「点选哪个状态，就看到哪个状态的东西」，
--      不是从头到尾罗列六块表、同一个项目还在好几块里重复出现。
--      这里给出唯一的分类口径 —— 一个项目只落在一类里。
CREATE VIEW v_wh_project_state AS
SELECT p.id AS project_id, p.code AS project_code,
       s2.status AS s2_status,
       COALESCE(bs.gap_total,0)      AS gap_total,
       COALESCE(bs.over_total,0)     AS over_total,
       (SELECT count(*) FROM mat_req r
         WHERE r.project_id = p.id AND r.status IN ('raised','short'))        AS open_req_n,
       (SELECT count(*) FROM mat_req r
         WHERE r.project_id = p.id AND r.status = 'short')                    AS short_req_n,
       (SELECT count(*) FROM wh_call c
         WHERE c.project_id = p.id AND c.stock_out_id IS NULL)                AS called_not_come_n,
       (SELECT count(*) FROM stock_out o
         WHERE o.project_id = p.id AND o.status = 'released')                 AS no_ack_n,
       (SELECT count(*) FROM party_pickup k
         WHERE k.project_id = p.id AND k.active AND NOT fn_is_au_mobile(k.phone)) AS no_phone_n,
       -- ★一个项目只落一类（从上往下第一个命中的）—— 不这么定，过两轮又会堆回去
       CASE
         WHEN s2.status IS DISTINCT FROM 'settled'                        THEN '等S2'
         WHEN (SELECT count(*) FROM party_pickup k
                WHERE k.project_id = p.id AND k.active
                  AND NOT fn_is_au_mobile(k.phone)) > 0                   THEN '提货人缺号码'
         WHEN (SELECT count(*) FROM mat_req r
                WHERE r.project_id = p.id AND r.status = 'short') > 0     THEN '缺货等采购'
         WHEN (SELECT count(*) FROM mat_req r
                WHERE r.project_id = p.id AND r.status = 'raised') > 0    THEN '工程提的出货单'
         WHEN COALESCE(bs.gap_total,0) > 0                                THEN '待备料'
         WHEN (SELECT count(*) FROM wh_call c
                WHERE c.project_id = p.id AND c.stock_out_id IS NULL) > 0 THEN '叫了没来提'
         WHEN (SELECT count(*) FROM stock_out o
                WHERE o.project_id = p.id AND o.status = 'released') > 0  THEN '提货没回执'
         ELSE '可以出库'
       END AS state_tab
  FROM project p
  LEFT JOIN payment_milestone s2
         ON s2.project_id = p.id AND s2.kind='contract' AND s2.stage='S2'
  LEFT JOIN v_project_bom_summary bs ON bs.project_id = p.id
 WHERE p.status NOT IN ('bid_lost','stalled');
COMMENT ON VIEW v_wh_project_state IS
  '库管「项目出库状态」八个状态页签的唯一分类口径。'
  '★一个项目只落一类 —— 六十七轮用户当场提的问题就是同一个项目在三块表里重复出现，'
  '断言 INV-WH-03 钉住这条';

-- 已通知、还没给他开出库单的（超过 wh_call_days 天标红，可「再催」）
CREATE VIEW v_wh_call_open AS
SELECT c.id, c.project_id, c.to_name, c.to_phone, c.lang,
       c.called_by, c.called_at,
       (current_date - c.called_at::date) AS waited_days,
       (current_date - c.called_at::date)
         > COALESCE((SELECT value_num FROM eng_setting WHERE key='wh_call_days'), 3) AS overdue
  FROM wh_call c
 WHERE c.stock_out_id IS NULL;
COMMENT ON VIEW v_wh_call_open IS
  '已通知、人还没来提。★这是「叫了没来」，不是「货给了没回执」—— 中间隔着开出库单那一下';


-- #####################################################################
-- ##  v0.37 ④：部门试用反馈落库（决策记录 §九·补四、补五）
-- ##  运维 M1 / M3 / M4 / M5 · 工程 E5 / E6
-- #####################################################################

-- =====================================================================
--  M1 报修时间拆成两个（2026-08-10 用户：「"报修时间"不存在说不清」）
--
--  用户这句话点出的不是措辞，是【把两件事揉成了一件】：
--    报修时间     = 客户什么时候告诉我们的 —— ★永远知道（就是接到电话那一刻）→ SLA 的起点
--    问题出现时间 = 问题什么时候开始的     —— 客户经常说不清（"好几天了"）→ 看客户拖了多久才报
--
--  ★原来的做法藏着一个洞：只有一个「报修时间」，还允许留空。客户说不清开始时间 → 留空
--    → 这一单就不参与响应时长统计。于是【真正响应慢的单最容易从统计里漏掉，报表永远好看】。
--    这正是本项目第二个核心担心：不报错、只是数字悄悄错了。
-- =====================================================================
ALTER TABLE maintenance_case ADD COLUMN IF NOT EXISTS issue_since timestamptz;
COMMENT ON COLUMN maintenance_case.issue_since IS
  '问题首次出现时间。★允许 NULL＝客户说不清（"好几天了"）—— 说不清的是【这个】，'
  '不是报修时间。填了就能算出「客户拖了 N 天才报」';

UPDATE maintenance_case SET reported_at = created_at WHERE reported_at IS NULL;
ALTER TABLE maintenance_case ALTER COLUMN reported_at SET NOT NULL;
-- ★「必填、默认现在」——接到电话那一刻就建单，默认值就是准确值。
--   没有默认值的必填＝每个建单入口都得记得填，忘一次就报错，最后有人会去把约束摘掉。
--   有了默认值，「留空」这种状态在结构上就不存在了 —— 洞是这么堵死的，不是靠人自觉。
ALTER TABLE maintenance_case ALTER COLUMN reported_at SET DEFAULT now();
COMMENT ON COLUMN maintenance_case.reported_at IS
  '★客户报修时间，必填（v0.37 起）。就是接到电话那一刻 —— 这个永远知道。'
  '★不许再留空：留空那一单就退出响应时长统计，于是真正响应慢的最容易漏掉，报表永远好看。'
  '客户说不清的是【问题首次出现时间 issue_since】，那个才可以空';

-- =====================================================================
--  M3 维护单分级 P0~P3 + 各档 SLA（★超本档自动进待办 —— 不自动推，分级就只是个好看的标签）
--  M4 研发排查（远程排查工时进成本 + 状态 + ★上门前门禁）
--  M5 完结交财务（三样齐才能点，处理情况 ≥10 字，财务照着往发票上写）
-- =====================================================================
ALTER TABLE maintenance_case ADD COLUMN IF NOT EXISTS pri text NOT NULL DEFAULT 'P2'
    CHECK (pri IN ('P0','P1','P2','P3'));
COMMENT ON COLUMN maintenance_case.pri IS
  'P0 全屋失控 / P1 主要功能不可用 / P2 单点故障 / P3 体验问题。'
  '各档 SLA 见 eng_setting.mt_sla_p0..p3（运维可改）。★超本档自动进待办';

-- 研发排查：远程先查，查不出再派人
ALTER TABLE maintenance_case ADD COLUMN IF NOT EXISTS rd_conclusion  text;
ALTER TABLE maintenance_case ADD COLUMN IF NOT EXISTS rd_by          text;
ALTER TABLE maintenance_case ADD COLUMN IF NOT EXISTS rd_at          timestamptz;
ALTER TABLE maintenance_case ADD COLUMN IF NOT EXISTS rd_skip_reason text;
COMMENT ON COLUMN maintenance_case.rd_conclusion IS
  '远程排查结论。★派人上门之前必须先有它，或者明确标「无需排查」并写原因（rd_skip_reason）——'
  '靠自觉的话忙起来一定直接派人，白跑一趟没人会报错';

-- 完结交财务：运维管事不管钱，到此为止
ALTER TABLE maintenance_case ADD COLUMN IF NOT EXISTS finish_note text;
ALTER TABLE maintenance_case ADD COLUMN IF NOT EXISTS finished_by text;
ALTER TABLE maintenance_case ADD COLUMN IF NOT EXISTS finished_at timestamptz;
COMMENT ON COLUMN maintenance_case.finish_note IS
  '完结交财务时填的处理情况（≥10 字，财务照着往发票上写）。'
  '★运维到此为止，不再跟踪开票收款 —— 定价开票收款全在财务';

-- 状态加一档：研发排查中
ALTER TABLE maintenance_case DROP CONSTRAINT IF EXISTS maintenance_case_status_check;
ALTER TABLE maintenance_case ADD CONSTRAINT maintenance_case_status_check CHECK (status IN
    ('open','rd','in_progress','invoiced','paid_closed','unpaid_suspended','void'));

CREATE OR REPLACE FUNCTION trg_mc_reported_at() RETURNS trigger AS $$
BEGIN
    IF NEW.reported_at > NEW.created_at + interval '1 minute' THEN
        RAISE EXCEPTION '门禁：报修时间(%)晚于建单时间(%)，顺序不对，请核对', NEW.reported_at, NEW.created_at;
    END IF;
    IF NEW.report_channel = 'unknown' THEN
        RAISE EXCEPTION '门禁：请选择报修渠道(电话/微信/邮件/现场/其他)——'
                        '客户是怎么找过来的，接电话那一刻就知道';
    END IF;
    -- ★问题总得先出现，客户才会报
    IF NEW.issue_since IS NOT NULL AND NEW.issue_since > NEW.reported_at THEN
        RAISE EXCEPTION '门禁：问题首次出现时间(%)晚于报修时间(%)——'
                        '问题总得先出现，客户才会打电话。填反了吧？',
                        NEW.issue_since, NEW.reported_at;
    END IF;
    -- ★完结交财务：处理情况 ≥10 字（财务照着这段往发票上写，写「已修好」他没法定价）
    IF NEW.finished_at IS NOT NULL AND length(btrim(COALESCE(NEW.finish_note,''))) < 10 THEN
        RAISE EXCEPTION '门禁：完结交财务必须写清处理情况（≥10 字）——'
                        '财务照着这段往发票上写，只写「已修好」他没法定价，只能回头再问一遍';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ★M4 门禁：派人上门之前必须先有排查结论（或明确标「无需排查」并写原因）
CREATE OR REPLACE FUNCTION trg_mj_rd_gate() RETURNS trigger AS $$
DECLARE mc maintenance_case%ROWTYPE;
BEGIN
    IF NEW.case_id IS NULL THEN RETURN NEW; END IF;      -- 无单派工另有 no_case_reason 把关
    SELECT * INTO mc FROM maintenance_case WHERE id = NEW.case_id;
    IF length(btrim(COALESCE(mc.rd_conclusion,''))) >= 4
       OR length(btrim(COALESCE(mc.rd_skip_reason,''))) >= 4 THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION '门禁：这一单还没有远程排查结论，不能派人上门 —— '
                    '要么先做远程排查并写下结论，要么明确标「无需排查」并写清为什么（≥4 字）。'
                    '★靠自觉的话忙起来一定直接派人，人到了现场才发现是个远程五分钟能解决的事，'
                    '白跑一趟没人会报错';
END $$ LANGUAGE plpgsql;
CREATE TRIGGER mj_rd_gate BEFORE INSERT ON maintenance_job
    FOR EACH ROW EXECUTE FUNCTION trg_mj_rd_gate();

-- ★远程排查的工时也要进成本（原来这段时间完全没人记）
ALTER TABLE work_log DROP CONSTRAINT IF EXISTS work_log_work_type_check;
ALTER TABLE work_log ADD CONSTRAINT work_log_work_type_check CHECK (work_type IN
    ('sm','execution','handover','maintenance','remote_diag'));
COMMENT ON COLUMN work_log.work_type IS
  'sm / execution / handover / maintenance / remote_diag（v0.37 新增：远程排查）。'
  '★远程排查也是工时也是成本 —— 原来研发在电脑前查两小时，这两小时谁也没记，'
  '项目成本就少算了两小时，而且不会报错';

-- SLA 四档 + 运维设置键
INSERT INTO eng_setting(key, value_num, note, write_depts) VALUES
 ('mt_sla_p0',  4, 'P0 全屋失控：多少小时内必须响应（超了自动进待办）', ARRAY['maintenance']),
 ('mt_sla_p1',  8, 'P1 主要功能不可用：响应 SLA（小时）',               ARRAY['maintenance']),
 ('mt_sla_p2', 24, 'P2 单点故障：响应 SLA（小时）',                     ARRAY['maintenance']),
 ('mt_sla_p3', 72, 'P3 体验问题：响应 SLA（小时）',                     ARRAY['maintenance'])
ON CONFLICT (key) DO NOTHING;

-- ㉕ 响应时长重算：★每一单都参与 SLA（reported_at 现在必填）
--    ★顺带堵住一个新暴露的缺陷：报修时间如果比上门时间还晚，原来会算出一个【负的小时数】。
--      负数会被平均进 SLA 报表，把真实的响应慢冲掉，而且不报错。
-- 不加 CASCADE：真有别的视图依赖它就当场报错，不要悄悄删掉（那才是最难查的）
DROP VIEW IF EXISTS v_maintenance_response;
CREATE VIEW v_maintenance_response AS
WITH v AS (
  SELECT c.id AS case_id, c.project_id, p.code AS project_code, c.title, c.pri,
         c.reported_at, c.issue_since, c.report_channel, c.taken_by,
         c.created_at AS case_created_at,
         (SELECT MIN(j.completed_at) FROM maintenance_job j
           WHERE j.case_id = c.id AND j.completed_at IS NOT NULL) AS first_visit_at,
         COALESCE((SELECT value_num FROM eng_setting
                    WHERE key = 'mt_sla_' || lower(c.pri)), 24) AS sla_hours
    FROM maintenance_case c JOIN project p ON p.id = c.project_id
)
SELECT v.*,
       round((EXTRACT(EPOCH FROM (v.case_created_at - v.reported_at))/3600.0)::numeric,1)
         AS intake_hours,
       -- 客户拖了多久才报（填了出现时间才算得出）
       CASE WHEN v.issue_since IS NOT NULL
            THEN round((EXTRACT(EPOCH FROM (v.reported_at - v.issue_since))/86400.0)::numeric,1) END
         AS waited_days_before_report,
       -- ★响应时长：一律按报修时间算，每一单都参与
       CASE WHEN v.first_visit_at IS NOT NULL AND v.first_visit_at >= v.reported_at
            THEN round((EXTRACT(EPOCH FROM (v.first_visit_at - v.reported_at))/3600.0)::numeric,1) END
         AS response_hours,
       -- ★时间对不上（报修晚于上门）：当场标出来并退出统计，不许让负数混进平均值
       (v.first_visit_at IS NOT NULL AND v.first_visit_at < v.reported_at) AS time_inconsistent,
       CASE WHEN v.first_visit_at IS NOT NULL AND v.first_visit_at >= v.reported_at
            THEN (EXTRACT(EPOCH FROM (v.first_visit_at - v.reported_at))/3600.0) > v.sla_hours END
         AS sla_breached
  FROM v;
COMMENT ON VIEW v_maintenance_response IS
  '响应时长（v0.37 重算）。★每一单都参与 SLA —— 原来允许报修时间留空，'
  '那一单就退出统计，真正响应慢的最容易漏掉。'
  'time_inconsistent=true 的单退出统计并标红：报修晚于上门，负数会把真实的响应慢冲掉';

DROP VIEW IF EXISTS v_response_data_quality;
CREATE VIEW v_response_data_quality AS
SELECT count(*)                                                  AS total_cases,
       count(*) FILTER (WHERE issue_since IS NOT NULL)           AS with_issue_since,
       count(*) FILTER (WHERE issue_since IS NULL)               AS unknown_issue_since,
       CASE WHEN count(*) > 0
            THEN round(count(*) FILTER (WHERE issue_since IS NULL)::numeric / count(*) * 100, 1)
       END                                                       AS unknown_pct
  FROM maintenance_case;
COMMENT ON VIEW v_response_data_quality IS
  '★v0.37 起统计的是【问题首次出现时间】的未知率 —— 报修时间已改必填，不会再未知。'
  '这个比例只影响「客户拖了多久才报」这个分析，不影响 SLA';

-- 超 SLA 的单（★自动进待办的数据源）
CREATE VIEW v_mt_sla_breach AS
SELECT case_id, project_id, project_code, title, pri, sla_hours,
       reported_at, first_visit_at, response_hours,
       CASE WHEN first_visit_at IS NULL
            THEN round((EXTRACT(EPOCH FROM (now() - reported_at))/3600.0)::numeric,1)
            ELSE response_hours END AS elapsed_hours
  FROM v_maintenance_response
 WHERE NOT COALESCE(time_inconsistent,false)
   AND (COALESCE(sla_breached,false)
        OR (first_visit_at IS NULL
            AND EXTRACT(EPOCH FROM (now() - reported_at))/3600.0 > sla_hours));
COMMENT ON VIEW v_mt_sla_breach IS
  '超本档 SLA 的维护单 → 自动进待办。★不自动推，分级就只是个好看的标签';


-- =====================================================================
--  E6 项目分级 A/B/C（2026-08-10 用户）
--  ★不写原因的分级，过两个月谁也说不清凭什么是 A，最后就变成人人都是 A
--  分级只影响【排序与提醒】，不改任何门禁
-- =====================================================================
ALTER TABLE project ADD COLUMN IF NOT EXISTS pj_level text
    CHECK (pj_level IS NULL OR pj_level IN ('A','B','C'));
ALTER TABLE project ADD COLUMN IF NOT EXISTS pj_level_reason text;
ALTER TABLE project ADD COLUMN IF NOT EXISTS pj_level_by     text;
ALTER TABLE project ADD COLUMN IF NOT EXISTS pj_level_at     timestamptz;
ALTER TABLE project DROP CONSTRAINT IF EXISTS ck_pj_level_reason;
ALTER TABLE project ADD CONSTRAINT ck_pj_level_reason
    CHECK (pj_level IS NULL OR length(btrim(COALESCE(pj_level_reason,''))) >= 6);
COMMENT ON COLUMN project.pj_level IS
  'A 优先 / B 正常 / C 可后置。★原因必填 ≥6 字 —— 不写原因的分级，'
  '过两个月谁也说不清凭什么是 A，最后就变成人人都是 A。'
  '★只影响排序与提醒（干不过来时先干 A），不改任何门禁';

-- =====================================================================
--  E5 项目备忘（带日期的事）
--  「Builder 说砌墙 08/20 完」「业主 08/28 回澳洲」这类话现在全在各人脑子和微信里，
--  ★忘了不会有任何提示。
-- =====================================================================
CREATE TABLE project_note (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    uuid NOT NULL REFERENCES project(id) ON DELETE CASCADE,
    -- ★内容 ≥6 字：「跟进」两个字，过两周自己也想不起来要跟进什么
    body          text NOT NULL CHECK (length(btrim(body)) >= 6),
    -- ★跟进日期必填：没日期就不会提醒＝等于没记
    follow_up_on  date NOT NULL,
    created_by    text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    done_at       timestamptz,
    done_by       text
);
CREATE INDEX idx_pjnote_open ON project_note(project_id, follow_up_on) WHERE done_at IS NULL;
COMMENT ON TABLE project_note IS
  '项目备忘。★跟进日期必填 —— 没日期就不会提醒，等于没记，还不如记在微信里。'
  '★一个项目多条时，取【最近的那条】当「下次跟进」（用户明确要求），'
  '项目列表那一列也是它；到期前 eng_note_remind_days 天进待办';

-- ★取最近的那条当「下次跟进」
CREATE VIEW v_project_next_follow AS
SELECT DISTINCT ON (n.project_id)
       n.project_id, n.id AS note_id, n.body, n.follow_up_on, n.created_by, n.created_at,
       (n.follow_up_on - current_date) AS days_left,
       (n.follow_up_on - current_date)
         <= COALESCE((SELECT value_num FROM eng_setting WHERE key='eng_note_remind_days'), 3)
                                       AS due_soon
  FROM project_note n
 WHERE n.done_at IS NULL
 ORDER BY n.project_id, n.follow_up_on, n.created_at DESC;
COMMENT ON VIEW v_project_next_follow IS
  '每个项目的「下次跟进」＝未完成备忘里日期最近的那一条（用户 2026-08-10 明确要求）';

INSERT INTO eng_setting(key, value_num, note, write_depts) VALUES
 ('eng_note_remind_days', 3, '项目备忘：到期前几天进待办', ARRAY['eng_mgmt'])
ON CONFLICT (key) DO NOTHING;

-- 库管设置：仓库地址与营业时间【原样写进提货短信】，改了只影响之后发出的
INSERT INTO eng_setting(key, value_num, note, write_depts) VALUES
 ('wh_call_days', 3, '通知来提货：叫了几天还没来，标红可再催', ARRAY['warehouse'])
ON CONFLICT (key) DO NOTHING;
INSERT INTO eng_setting(key, value_text, note, write_depts) VALUES
 ('wh_address', 'Unit 3, 12 Chaplin Dr, Lane Cove NSW 2066',
  '仓库地址：★原样写进提货短信（中英双语那条也用它）', ARRAY['warehouse']),
 ('wh_hours',   'Mon–Fri 8:00–16:30（周末与公众假日不办提货）',
  '仓库营业时间：★原样写进提货短信 —— 不写清楚，人下班后跑来白跑一趟', ARRAY['warehouse']),
 ('wh_cable_categories', '["cable","线材"]',
  '哪些品类算「线材」：只有它们能走 SM2 预提窄通道。'
  '★写死在代码里，以后加一个品类就要改 DDL，实际结果是没人改，窄通道悄悄失效',
  ARRAY['warehouse'])
ON CONFLICT (key) DO NOTHING;


-- #####################################################################
-- ##  v0.37 ⑤：登记 · RLS · 乐观锁 · 断言 · 收尾
-- ##  （v0.31 教训：只登记不设防＝裸奔；v0.33 教训：只建表不登记＝断言违规）
-- #####################################################################

-- ── 写入归属 ─────────────────────────────────────────────────────────
INSERT INTO table_ownership(table_name, write_dept, note) VALUES
 ('quote_bom',       ARRAY['procurement'],
   'v0.37：采购上传报价原始单（版本化）。★只读基线，谁也不能改行'),
 ('quote_bom_line',  ARRAY['procurement'],
   'v0.37：原始单明细。唯一允许的改动是给挂起的行补 material_id（编码后来建档了）'),
 ('bom_change',      ARRAY['eng_mgmt'],
   'v0.37：★现场工程人员提单、工程管理负责人审（推翻 v0.36 的库管下达）'),
 ('bom_change_line', ARRAY['eng_mgmt'],       'v0.37：变更明细＝工程管理审的「变量」'),
 ('bom_reserve',     ARRAY['warehouse'],      'v0.37：库管备料，★占住不扣库存'),
 ('mat_req',         ARRAY['eng_mgmt','warehouse'],
   'v0.37：工程排班时生成出货单，库管核对库存后改状态'),
 ('mat_req_line',    ARRAY['eng_mgmt','warehouse'], 'v0.37：出货单明细'),
 ('party_pickup',    ARRAY['warehouse'],
   'v0.37：第三方提货人（其他工种谁来拉货就现加一个）'),
 ('wh_call',         ARRAY['warehouse'],      'v0.37：通知来提货（库管主动、手工发）'),
 ('project_note',    ARRAY['eng_mgmt'],       'v0.37：项目备忘，带跟进日期')
ON CONFLICT (table_name) DO NOTHING;

-- ── 项目归属（不登记会被 INV-PJ-10 抓）───────────────────────────────
INSERT INTO project_scope_registry(table_name, kind, kind_cn, trace_path, note) VALUES
 ('quote_bom',      'project_required','项目必填','project_id','报价单一定属于某个项目'),
 ('quote_bom_line', 'via_parent','随父单','quote_bom.project_id',NULL),
 ('bom_change',     'project_required','项目必填','project_id',NULL),
 ('bom_change_line','via_parent','随父单','bom_change.project_id',NULL),
 ('bom_reserve',    'project_required','项目必填','project_id','★备的就是给这个项目的货'),
 ('mat_req',        'project_required','项目必填','project_id','出货单一定属于某个项目'),
 ('mat_req_line',   'via_parent','随父单','mat_req.project_id',NULL),
 ('party_pickup',   'project_required','项目必填','project_id','提货人是给这个项目拉货的'),
 ('wh_call',        'project_required','项目必填','project_id',NULL),
 ('project_note',   'project_required','项目必填','project_id','备忘一定是某个项目的事')
ON CONFLICT (table_name) DO NOTHING;

-- ── RLS：读全部、写本部门；两张只读/只增的另行处理 ────────────────────
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['quote_bom','quote_bom_line','bom_change','bom_change_line',
                             'bom_reserve','mat_req','mat_req_line','party_pickup',
                             'project_note'] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format($f$CREATE POLICY %1$s_read ON %1$I FOR SELECT
            USING (NOT fn_is_field() OR fn_is_admin())$f$, t);
        EXECUTE format($f$CREATE POLICY %1$s_ins ON %1$I FOR INSERT
            WITH CHECK (fn_can_write(%1$L))$f$, t);
        EXECUTE format($f$CREATE POLICY %1$s_upd ON %1$I FOR UPDATE
            USING (fn_can_write(%1$L)) WITH CHECK (fn_can_write(%1$L))$f$, t);
        EXECUTE format($f$CREATE POLICY %1$s_del ON %1$I FOR DELETE
            USING (fn_is_admin())$f$, t);
    END LOOP;
END $$;

-- 通知来提货：只增不改 —— 「我明明通知过他」这件事被改掉，扯皮时就没有依据了
ALTER TABLE wh_call ENABLE ROW LEVEL SECURITY;
CREATE POLICY wh_call_read ON wh_call FOR SELECT
    USING (NOT fn_is_field() OR fn_is_admin());
CREATE POLICY wh_call_ins  ON wh_call FOR INSERT
    WITH CHECK (fn_can_write('wh_call'));
-- 唯一允许的改动：开了出库单之后回填 stock_out_id（系统自己写）
CREATE POLICY wh_call_upd  ON wh_call FOR UPDATE
    USING (fn_can_write('wh_call')) WITH CHECK (fn_can_write('wh_call'));

-- ★施工人员（三级账号）只有 App：物料变更就是他们在现场提的，
--   得让他们读写【自己那张】单（口径与 work_log / daily_report 完全一致）。
--   已提交/已批准的行由 trg_bom_change_line_lock 锁死，改不动。
DROP POLICY IF EXISTS bom_change_read ON bom_change;
CREATE POLICY bom_change_read ON bom_change FOR SELECT
    USING (NOT fn_is_field() OR fn_is_admin() OR raised_staff_id = fn_my_staff_id());
DROP POLICY IF EXISTS bom_change_ins ON bom_change;
CREATE POLICY bom_change_ins ON bom_change FOR INSERT
    WITH CHECK (fn_can_write('bom_change')
                OR (fn_is_field() AND raised_staff_id = fn_my_staff_id()));
DROP POLICY IF EXISTS bom_change_upd ON bom_change;
CREATE POLICY bom_change_upd ON bom_change FOR UPDATE
    USING (fn_can_write('bom_change')
           OR (fn_is_field() AND raised_staff_id = fn_my_staff_id()))
    WITH CHECK (fn_can_write('bom_change')
                OR (fn_is_field() AND raised_staff_id = fn_my_staff_id()));

DROP POLICY IF EXISTS bom_change_line_read ON bom_change_line;
CREATE POLICY bom_change_line_read ON bom_change_line FOR SELECT
    USING (NOT fn_is_field() OR fn_is_admin()
           OR EXISTS (SELECT 1 FROM bom_change b
                       WHERE b.id = change_id AND b.raised_staff_id = fn_my_staff_id()));
DROP POLICY IF EXISTS bom_change_line_ins ON bom_change_line;
CREATE POLICY bom_change_line_ins ON bom_change_line FOR INSERT
    WITH CHECK (fn_can_write('bom_change_line')
                OR (fn_is_field() AND EXISTS (SELECT 1 FROM bom_change b
                     WHERE b.id = change_id AND b.raised_staff_id = fn_my_staff_id())));
DROP POLICY IF EXISTS bom_change_line_upd ON bom_change_line;
CREATE POLICY bom_change_line_upd ON bom_change_line FOR UPDATE
    USING (fn_can_write('bom_change_line')
           OR (fn_is_field() AND EXISTS (SELECT 1 FROM bom_change b
                WHERE b.id = change_id AND b.raised_staff_id = fn_my_staff_id())))
    WITH CHECK (fn_can_write('bom_change_line')
                OR (fn_is_field() AND EXISTS (SELECT 1 FROM bom_change b
                     WHERE b.id = change_id AND b.raised_staff_id = fn_my_staff_id())));


-- =====================================================================
--  ★ fn_apply_optlock()：v0.35 那个末尾 DO 块收成函数
--    与 fn_apply_view_conventions() 配成一对 —— 以后任何一轮加完表/视图，
--    末尾各调一次即可，不必记住「回去重跑 DDL 末尾那个块」。
--    v0.36 就是靠 fn_apply_view_conventions 才没漏掉 4 个视图；
--    乐观锁这边一直还是靠人记，这一版补齐。
-- =====================================================================
CREATE OR REPLACE FUNCTION fn_apply_optlock() RETURNS void AS $lock$
DECLARE t text; n int := 0;
BEGIN
    FOR t IN
        SELECT c.relname
          FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
         WHERE ns.nspname = 'public' AND c.relkind = 'r'
           AND EXISTS (SELECT 1 FROM pg_policies p
                        WHERE p.schemaname = 'public' AND p.tablename = c.relname
                          AND p.cmd IN ('UPDATE','ALL'))
         ORDER BY 1
    LOOP
        EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1', t);
        EXECUTE format('ALTER TABLE %I ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()', t);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_optlock', t);
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I', t || '_touch',   t);
        -- 触发器按名字顺序跑：_optlock 先比对旧版本，_touch 后自增（o < t）
        EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION trg_row_optlock()',
                       t || '_optlock', t);
        EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION trg_row_touch()',
                       t || '_touch', t);
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'v0.37 乐观锁已挂到 % 张可改业务表', n;
END $lock$ LANGUAGE plpgsql;
COMMENT ON FUNCTION fn_apply_optlock IS
  '★新增可改的表之后调一次。自动扫全库：凡是带 UPDATE/ALL 策略的表＝有人能改它＝'
  '必须能挡住陈旧覆盖。手列清单一定会漏，而漏了不报错 —— 两个人同时改会静默覆盖';

SELECT fn_apply_optlock();


-- =====================================================================
--  断言 +9（81 → 90）
--  门禁问的是「该拦的拦住了吗」；断言问的是「没被拦住的，算对了吗」。
-- =====================================================================
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES

('INV-BOM-01','一个项目只能有一个当前版本报价单','critical',
 $q$SELECT p.code, count(*) AS current_n
      FROM quote_bom q JOIN project p ON p.id = q.project_id
     WHERE q.is_current
     GROUP BY p.code HAVING count(*) > 1$q$,
 '两张 current → 物料账的「原始」一列直接翻倍，应采、还要买跟着全错，而且不会报错'),

('INV-BOM-02','已批准/已退回的变更单必须有审批人和时间','high',
 $q$SELECT change_no, status FROM bom_change
     WHERE status IN ('approved','returned')
       AND (reviewed_by IS NULL OR reviewed_at IS NULL)$q$,
 '没有审批人就是绕过流程直接写进去的 —— 现场按它备料下单，出了事没人认账'),

('INV-BOM-03','★待审/已批的变更必须挂在当前版本报价单上','critical',
 $q$SELECT b.change_no, b.status FROM bom_change b
     JOIN quote_bom q ON q.id = b.bom_id
     WHERE b.status IN ('pending','approved') AND NOT q.is_current$q$,
 '报价单传了新版，旧版上的变更还挂着 → 物料账拿旧基线算，数字悄悄错了。'
 '传新版之前必须先把在途的变更单处理完'),

('INV-BOM-04','★库管备料不许超过现货','critical',
 $q$SELECT m.code, m.display_name,
           COALESCE(s.qty_on_hand,0) AS on_hand, r.reserved
      FROM (SELECT material_id, SUM(qty) AS reserved FROM bom_reserve
             WHERE released_at IS NULL GROUP BY material_id) r
      JOIN material m ON m.id = r.material_id
      LEFT JOIN v_material_stock s ON s.material_id = r.material_id
     WHERE r.reserved > COALESCE(s.qty_on_hand,0)$q$,
 '★备的比库里有的还多＝先占后补：采购看见「已备」就不买了，到时候两头都没有。'
 '写入时门禁查过一次，但后来盘亏/别的项目出库都会让现货变少——所以必须现算全库再查一遍'),

('INV-BOM-05','项目物料账不许出现负数','high',
 $q$SELECT project_id, material_code, qty_required, qty_gap, qty_over
      FROM v_project_bom
     WHERE qty_required < 0 OR qty_gap < 0 OR qty_over < 0$q$,
 '应采/还要买/买多了出现负数 = 口径被改坏了。负数会顺着汇总一路传下去，'
 '在总数里互相抵消，看着「刚好」，实际两头都错'),

('INV-WH-02','★出库单的提货人必须有澳洲手机号','critical',
 $q$SELECT out_no, receiver_name, receiver_phone FROM stock_out
     WHERE NOT fn_is_au_mobile(receiver_phone)$q$,
 '提货清单和催回执全靠短信。号码不对就永远发不到，而系统不会报错 —— '
 '货只会一直堆在仓库没人来拉，或者给了人却永远等不到回执'),

('INV-WH-03','★一个项目只能落在一个出库状态页签里','high',
 $q$SELECT project_id, count(*) FROM v_wh_project_state
     GROUP BY project_id HAVING count(*) > 1$q$,
 '六十七轮用户当场提的问题：同一个项目在三块表里重复出现，页面就乱了。'
 '这条钉住「过两轮又会堆回去」'),

('INV-MT-01','★派了人上门的维护单必须先有排查结论','high',
 $q$SELECT c.id, c.title FROM maintenance_case c
     WHERE EXISTS (SELECT 1 FROM maintenance_job j WHERE j.case_id = c.id)
       AND length(btrim(COALESCE(c.rd_conclusion,'')))  < 4
       AND length(btrim(COALESCE(c.rd_skip_reason,''))) < 4$q$,
 '★靠自觉的话忙起来一定直接派人，人到了现场才发现是个远程五分钟能解决的事，'
 '白跑一趟没人会报错。建单时门禁拦过一次，结论后来被清空也要抓得住'),

('INV-MT-02','★响应时长不许出现负数','high',
 $q$SELECT case_id, title, reported_at, first_visit_at, response_hours
      FROM v_maintenance_response WHERE response_hours < 0$q$,
 '报修时间比上门时间还晚就会算出负数，负数被平均进 SLA 报表会把真实的响应慢冲掉，'
 '而且不报错。时间对不上的单必须标出来并退出统计，不是算成负数');


-- ── 收尾：视图规矩（security_invoker + 项目标识）────────────────────
--    ★这一步不能省：视图默认按【视图所有者】执行，不设 security_invoker
--      等于 RLS 被整个绕过
SELECT fn_apply_view_conventions();


-- #####################################################################
-- ##  v0.38：派工排班表（欠账表第 1 条 · 决策记录 §16 四十一~四十四轮）
-- ##
-- ##  ★为什么必须和 work_log 分开：
-- ##    work_log 是【打卡】—— 实际发生了什么，工人在现场按的。
-- ##    eng_schedule 是【排班】—— 计划要发生什么，工程管理提前排的。
-- ##    只有打卡，就永远看不出「派了工没去」；两张表分开，
-- ##    「计划 vs 实际」才对得上（§16 五十轮的工程流水账靠的就是这个对比）。
-- #####################################################################

-- =====================================================================
--  第四十八部分：排班任务类型 sched_task_type
--    六类内建【不可删】—— 与工时/倒休算法绑死，删一个算法就悄悄少一支
--    自建类型：默认计工时 + 合理时长 4 小时（§16 五十二轮）
-- =====================================================================
CREATE TABLE sched_task_type (
    code         text PRIMARY KEY,
    label        text NOT NULL,
    -- 内建的删不掉（算法认这几个 code）
    builtin      boolean NOT NULL DEFAULT false,
    -- 计不计工时：倒休是【把攒下的余额用掉】，不是干活，所以不计
    counts_hours boolean NOT NULL DEFAULT true,
    -- ★合理时长：工程管理定义，跟客户解释工期的依据。★只提示不拦
    --   （现场千差万别，拦死了只会逼人乱填一个数糊弄过去）
    std_minutes  integer NOT NULL DEFAULT 240 CHECK (std_minutes > 0),
    color        text,
    active       boolean NOT NULL DEFAULT true,
    sort_no      integer NOT NULL DEFAULT 99,
    created_at   timestamptz NOT NULL DEFAULT now()
);
INSERT INTO sched_task_type(code,label,builtin,counts_hours,std_minutes,color,sort_no) VALUES
 ('sm',          'Site Meeting', true, true,  180, '#2563eb', 1),
 ('install',     '安装',         true, true,  480, '#047857', 2),
 ('handover',    '交付',         true, true,  240, '#0f766e', 3),
 ('maintenance', '维护',         true, true,  120, '#7c3aed', 4),
 ('remote_diag', '远程排查',     true, true,   60, '#b45309', 5),
 ('toil',        '倒休',         true, false, 480, '#64748b', 6);
COMMENT ON TABLE sched_task_type IS
  '排班任务类型。★六类内建不可删（与工时/倒休算法绑死）；'
  '★被排班用过的也删不掉 —— 删了历史排班就成孤儿，那几天的工时归到哪一类没人说得清。'
  'std_minutes ＝ 合理时长，重点是 SM 与交付（跟客户解释工期的依据），★只提示不拦';
COMMENT ON COLUMN sched_task_type.counts_hours IS
  '倒休＝把攒下的余额用掉，不是干活，所以 false —— 它不进工时也不进项目成本';

CREATE OR REPLACE FUNCTION trg_task_type_guard() RETURNS trigger AS $$
DECLARE n int;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.builtin THEN
            RAISE EXCEPTION '门禁：「%」是内建任务类型，删不掉 —— 工时与倒休的算法认的就是这几个类型，'
                            '删一个算法就悄悄少一支，而且不会报错。不想用请改「停用」', OLD.label;
        END IF;
        SELECT count(*) INTO n FROM eng_schedule WHERE task_type = OLD.code;
        IF n > 0 THEN
            RAISE EXCEPTION '门禁：任务类型「%」已经被 % 条排班用过，删不掉 —— '
                            '删了那些排班就成孤儿，那几天的工时归到哪一类没人说得清。请改「停用」，'
                            '停用的不再出现在新排班的选项里，历史照旧可查', OLD.label, n;
        END IF;
        RETURN OLD;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.builtin AND NEW.code IS DISTINCT FROM OLD.code THEN
        RAISE EXCEPTION '门禁：内建任务类型的代码不能改（%→%）—— 算法是按代码认的', OLD.code, NEW.code;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

-- =====================================================================
--  第四十九部分：派工排班 eng_schedule
--    周视图（周一~周日 × 人）；一天一人可排 2~4 段；★全浮窗录入，不做拖拽
--    （拖拽不留痕；浮窗每次保存都进操作日志）
-- =====================================================================
CREATE TABLE eng_schedule (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id      uuid NOT NULL REFERENCES eng_staff(id),
    work_date     date NOT NULL,
    -- ★起止时间：从 00:00 起的分钟数，15 分钟一档，05:00(300)~23:45(1425)
    --   开始时间【不固定】：上午没活就休息、10 点才进场，一直干到晚上都行
    start_min     integer NOT NULL CHECK (start_min BETWEEN 300 AND 1425 AND start_min % 15 = 0),
    end_min       integer NOT NULL CHECK (end_min   BETWEEN 315 AND 1440 AND end_min   % 15 = 0),
    -- ★时长＝区间自动算，不手填（手填就会出现「起止 8:00–16:30 但时长写 4 小时」这种对不上的行）
    minutes       integer GENERATED ALWAYS AS (end_min - start_min) STORED,

    task_type     text NOT NULL REFERENCES sched_task_type(code),
    -- ★任务必须关联项目（倒休除外 —— 休假不是工作）
    project_id    uuid REFERENCES project(id),
    ref_id        uuid,                    -- 具体单据：SM / 维护单 / 安装 / 交付
    content       text,                    -- 工作内容（多行）

    -- ★剩余工作：自动生成，不手填。来源＝该项目最近一次每日上报里留下的剩余
    --   落库存的是【快照】—— 排班那一刻带出来的是什么，日后就是什么，
    --   上报后来被改了也不动这条（否则回头看不出当初是照着什么排的）
    remaining_snap text,
    remaining_src  text,                   -- 来源：谁 · 哪天

    -- 提料（§23.九）：安装勾「去仓库办提货」· SM 勾「带线材」· 维护填「这次带什么」
    need_pickup   boolean NOT NULL DEFAULT false,
    pickup_note   text,
    mat_req_id    uuid REFERENCES mat_req(id),

    -- ★红点/绿点：短信发出＝红点，本人回 Y＝绿点。
    --   ★不论回不回，日程都【已经】同步到本人 App —— 确认只是回执，不是生效条件
    notified_at   timestamptz,
    confirmed_at  timestamptz,
    -- 取消：被取消的人要回 Yes（取消待确认清单盯着）
    cancelled_at  timestamptz,
    cancel_reason text,
    cancel_ack_at timestamptz,
    -- 锁定＝已下发（按天 / 整周）。要改先解锁，解锁留痕
    locked_at     timestamptz,
    locked_by     text,

    created_by    text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_sch_span    CHECK (end_min > start_min),
    -- ★休假不是工作：倒休不挂项目；其余一律必须有项目
    CONSTRAINT ck_sch_project CHECK ((task_type = 'toil') = (project_id IS NULL)),
    CONSTRAINT ck_sch_cancel  CHECK (cancelled_at IS NULL
                                     OR length(btrim(COALESCE(cancel_reason,''))) >= 2)
);
CREATE INDEX idx_sch_week    ON eng_schedule(work_date, staff_id);
CREATE INDEX idx_sch_project ON eng_schedule(project_id, work_date);
COMMENT ON TABLE eng_schedule IS
  '派工排班（计划）。★与 work_log（打卡＝实际）是两张表 —— '
  '只有打卡就永远看不出「派了工没去」，两张对起来才是工程流水账那一列「计划 vs 实际」。'
  '★录入一律走浮窗不做拖拽：拖拽不留痕，浮窗每次保存都进操作日志';
COMMENT ON COLUMN eng_schedule.minutes IS
  '★时长＝区间自动算。手填的话迟早出现「起止 8:00–16:30、时长写 4 小时」这种对不上的行，而且不报错';
COMMENT ON COLUMN eng_schedule.confirmed_at IS
  '本人短信回 Y 的时间（绿点）。★日程不论回不回都已同步到 App —— 这只是回执，不是生效条件';

-- ★倒休余额（真实值，专供门禁用）
--   为什么不能直接查 v_toil_balance：那张视图的 balance_min 裹着【薪酬遮罩】
--   （fn_can_see_salary），而排班的人是工程管理 —— 他没有薪酬可见性，
--   查出来永远是 NULL。COALESCE 成 0 之后，任何一条倒休都会被判成"余额不够"，
--   门禁从"防透支"变成"全拦死"，而且不报错、只是没人能排倒休了。
--   反过来，回归测试里没有身份，遮罩同样返回 NULL —— 两个方向都会错。
--   ★门禁是系统级判断，不该受"谁在看"影响：这里直接读台账，绕开遮罩。
--   （遮罩仍然管着"谁能看见这个数字"—— v_toil_balance 一个字没改）
CREATE OR REPLACE FUNCTION fn_toil_balance_min(p_staff uuid) RETURNS numeric AS $$
    SELECT COALESCE(SUM(minutes),0) FROM toil_ledger WHERE staff_id = p_staff;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
COMMENT ON FUNCTION fn_toil_balance_min IS
  '倒休余额真实值，★只给门禁用。v_toil_balance 带薪酬遮罩，'
  '排班的人（工程管理）查出来是 NULL —— 门禁不能建立在"谁在看"上面';

-- ── 门禁：排班表最要紧的八条 ────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_sched_gate() RETURNS trigger AS $$
DECLARE ov record; bal numeric; other_toil numeric; nm text; tt sched_task_type%ROWTYPE;
        last_m record; pcode text; substantive boolean; mins integer;
BEGIN
    SELECT name INTO nm FROM eng_staff WHERE id = NEW.staff_id;
    SELECT * INTO tt FROM sched_task_type WHERE code = NEW.task_type;
    -- ★这里绝对不能用 NEW.minutes：它是 GENERATED 列，BEFORE 触发器里【还没算出来】，
    --   取到的是 NULL。而 NULL > 0 求值为 NULL，IF 不成立 —— 门禁静默放行，一声不吭。
    --   （v0.38 实测踩到：8 小时倒休在余额只有 6 小时时直接进了库，回归里那条"应拦"
    --     根本没拦住，是靠断言 INV-SCH-04 现算全库才发现的。）
    mins := NEW.end_min - NEW.start_min;

    -- ① ★不许给过去的日期排班
    --    事后补一条计划，「计划 vs 实际」就永远相等 —— 那个对比是用来发现
    --    「派了工没去」「去了没派工」的，补出来的计划让它彻底失效，而且不会报错
    IF TG_OP = 'INSERT' AND NEW.work_date < current_date THEN
        RAISE EXCEPTION '门禁：不能给过去的日期（%）排班 —— 排班是【计划】，事后补一条，'
                        '「计划 vs 实际」就永远对得上，再也看不出「派了工没去」。'
                        '过去的活要补记，请走「每日工时管理」的补录',
                        to_char(NEW.work_date,'YYYY-MM-DD');
    END IF;

    IF TG_OP = 'UPDATE' THEN
        -- 哪些算「改实质内容」（改回执、确认、取消回执不算）
        substantive := (NEW.staff_id   IS DISTINCT FROM OLD.staff_id
                     OR NEW.work_date  IS DISTINCT FROM OLD.work_date
                     OR NEW.start_min  IS DISTINCT FROM OLD.start_min
                     OR NEW.end_min    IS DISTINCT FROM OLD.end_min
                     OR NEW.task_type  IS DISTINCT FROM OLD.task_type
                     OR NEW.project_id IS DISTINCT FROM OLD.project_id
                     OR NEW.content    IS DISTINCT FROM OLD.content);
        -- ② ★过去的排班不许改（历史就是历史）
        IF substantive AND OLD.work_date < current_date THEN
            RAISE EXCEPTION '门禁：% 的排班已经是过去的事了，改不了 —— '
                            '只能改此刻之后的安排。记错了请在「每日工时管理」里补录说明',
                            to_char(OLD.work_date,'YYYY-MM-DD');
        END IF;
        -- ③ ★锁定＝已下发，要改先解锁（解锁留痕）
        IF substantive AND OLD.locked_at IS NOT NULL AND NEW.locked_at IS NOT NULL THEN
            RAISE EXCEPTION '门禁：% % 的排班已锁定（已下发给本人），要改请先解锁 —— '
                            '锁了还能改，工人手机上的日程和这里就对不上了',
                            nm, to_char(OLD.work_date,'YYYY-MM-DD');
        END IF;
    END IF;

    IF NEW.cancelled_at IS NOT NULL THEN RETURN NEW; END IF;   -- 取消掉的不再占时间、不再校验

    -- ④ ★同一人同一天两段不许重叠 —— 一个人不能同时在两个工地
    SELECT s.start_min, s.end_min, t.label INTO ov
      FROM eng_schedule s JOIN sched_task_type t ON t.code = s.task_type
     WHERE s.staff_id = NEW.staff_id AND s.work_date = NEW.work_date
       AND s.id <> NEW.id AND s.cancelled_at IS NULL
       AND NEW.start_min < s.end_min AND NEW.end_min > s.start_min
     LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION '门禁：% 在 % 已经排了「%」%–%，和这次的 %–% 撞上了 —— '
                        '一个人不能同时在两个工地',
                        nm, to_char(NEW.work_date,'MM-DD'), ov.label,
                        to_char((ov.start_min||' minutes')::interval,'HH24:MI'),
                        to_char((ov.end_min  ||' minutes')::interval,'HH24:MI'),
                        to_char((NEW.start_min||' minutes')::interval,'HH24:MI'),
                        to_char((NEW.end_min  ||' minutes')::interval,'HH24:MI');
    END IF;

    -- ⑤ ★倒休余额不足直接拦（含同期其他已排的倒休）
    IF NEW.task_type = 'toil' THEN
        bal := fn_toil_balance_min(NEW.staff_id);
        SELECT COALESCE(SUM(minutes),0) INTO other_toil FROM eng_schedule
         WHERE staff_id = NEW.staff_id AND task_type = 'toil' AND cancelled_at IS NULL
           AND id <> NEW.id AND work_date >= current_date;
        IF mins > bal - other_toil THEN
            RAISE EXCEPTION '门禁：% 的倒休余额只剩 % 分钟（共 % − 已排未休 %），'
                            '这次要休 % 分钟，不够 —— 倒休不能透支',
                            nm, (bal - other_toil), bal, other_toil, mins;
        END IF;
    END IF;

    -- ⑥ ★维护：上次上门没填剩余工作，这次派不了工
    --    上一次没做完又没写，下一个人到了现场根本不知道该接着干什么 —— 白跑一趟没人会报错
    IF NEW.task_type = 'maintenance' AND NEW.project_id IS NOT NULL THEN
        SELECT s.work_date, st.name INTO last_m
          FROM eng_schedule s JOIN eng_staff st ON st.id = s.staff_id
         WHERE s.project_id = NEW.project_id AND s.task_type = 'maintenance'
           AND s.cancelled_at IS NULL AND s.work_date < current_date AND s.id <> NEW.id
           AND NOT EXISTS (
               SELECT 1 FROM daily_report_line l JOIN daily_report r ON r.id = l.report_id
                WHERE r.staff_id = s.staff_id AND r.report_date = s.work_date
                  AND l.project_id = s.project_id AND l.remaining IS NOT NULL)
         ORDER BY s.work_date DESC LIMIT 1;
        IF FOUND THEN
            SELECT code INTO pcode FROM project WHERE id = NEW.project_id;
            RAISE EXCEPTION '门禁：项目 % 上一次维护（% · %）没填剩余工作，这次派不了工 —— '
                            '请先让上次上门的人在「每日上报」补填剩余工作。'
                            '上次没做完又没写，下一个人到了现场根本不知道该接着干什么',
                            pcode, to_char(last_m.work_date,'MM-DD'), last_m.name;
        END IF;
    END IF;

    RETURN NEW;
END $$ LANGUAGE plpgsql;

-- ⑦ ★过去的排班不许删
CREATE OR REPLACE FUNCTION trg_sched_del_guard() RETURNS trigger AS $$
BEGIN
    IF OLD.work_date < current_date THEN
        RAISE EXCEPTION '门禁：% 的排班已经是过去的事了，删不掉 —— '
                        '删了「计划 vs 实际」那一列就少了一半，看着像「本来就没派人」。'
                        '排错了请标「取消」并写原因，留痕比抹掉干净',
                        to_char(OLD.work_date,'YYYY-MM-DD');
    END IF;
    RETURN OLD;
END $$ LANGUAGE plpgsql;

-- =====================================================================
--  第五十部分：每日上报【分段】daily_report_line
--    原 daily_report 只挂「人 + 日期」——一人一天可跑多个项目，
--    那张表答不出「今天在哪个项目做了什么、还剩什么」。
--    ★没有这张表，排班的「剩余工作自动带出」与「维护没填剩余就拦派工」都落不了。
-- =====================================================================
CREATE TABLE daily_report_line (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id    uuid NOT NULL REFERENCES daily_report(id) ON DELETE CASCADE,
    project_id   uuid REFERENCES project(id),
    is_company_level boolean NOT NULL DEFAULT false,
    sched_id     uuid REFERENCES eng_schedule(id),      -- 对应哪条排班（对得上才算「照计划做了」）
    -- 今天做了什么（工人自己写；★排班表不记这个，只记剩余——单维度锁定人员内容）
    did_what     text NOT NULL CHECK (length(btrim(did_what)) >= 2),
    -- ★还剩什么没做：SM 阶段不存在（留空）；施工/交付要写；维护可空但会卡下次派工
    remaining    text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_drl_project CHECK (is_company_level OR project_id IS NOT NULL)
);
CREATE INDEX idx_drl_project ON daily_report_line(project_id, created_at DESC);
COMMENT ON TABLE daily_report_line IS
  '每日上报分段（一人一天可跑多个项目，一段一个项目）。'
  '★remaining 留空 ≠ 没剩下 —— 维护那条线上，留空会在下次派工时被门禁拦住，'
  '逼上次上门的人回来补填。「上次没做完又没写」是白跑一趟最常见的原因';
COMMENT ON COLUMN daily_report_line.remaining IS
  '还剩什么没做。SM 阶段不存在此项；维护真没剩就写「无」——'
  '★写「无」和留空是两回事：写「无」＝确认过了，留空＝没人问过';

-- ★剩余工作自动带出（排班浮窗上是只读的，这里是它的唯一来源）
CREATE OR REPLACE FUNCTION fn_last_remaining(p_project uuid)
RETURNS TABLE(remaining text, src text) AS $$
    SELECT l.remaining,
           st.name || ' · ' || to_char(r.report_date,'MM-DD')
      FROM daily_report_line l
      JOIN daily_report r  ON r.id = l.report_id
      JOIN eng_staff   st  ON st.id = r.staff_id
     WHERE l.project_id = p_project AND l.remaining IS NOT NULL
     ORDER BY r.report_date DESC, l.created_at DESC
     LIMIT 1;
$$ LANGUAGE sql STABLE;
COMMENT ON FUNCTION fn_last_remaining IS
  '★排班浮窗「剩余工作」的唯一来源：该项目最近一次每日上报里留下的剩余。'
  '四十三轮口径变更 —— 从手填改成自动生成，手填的话现场那个人写的和排班的人写的对不上，'
  '而且两个都看着挺合理';

-- 排班时把剩余工作【快照】进去（日后上报被改也不动这条 —— 否则回头看不出当初照着什么排的）
CREATE OR REPLACE FUNCTION trg_sched_fill_remaining() RETURNS trigger AS $$
DECLARE r record;
BEGIN
    -- SM 阶段不存在剩余工作；倒休更不用说
    IF NEW.task_type IN ('sm','toil') THEN
        NEW.remaining_snap := NULL; NEW.remaining_src := NULL;
        RETURN NEW;
    END IF;
    IF NEW.remaining_snap IS NULL AND NEW.project_id IS NOT NULL THEN
        SELECT * INTO r FROM fn_last_remaining(NEW.project_id);
        IF FOUND THEN
            NEW.remaining_snap := r.remaining;
            NEW.remaining_src  := r.src;
        ELSE
            NEW.remaining_snap := '（第一次进场，没有上次的剩余）';
        END IF;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;

-- 触发器按名字顺序：fill_remaining（f）先补默认值，gate（g）再校验
CREATE TRIGGER sched_fill_remaining BEFORE INSERT ON eng_schedule
    FOR EACH ROW EXECUTE FUNCTION trg_sched_fill_remaining();
CREATE TRIGGER sched_gate BEFORE INSERT OR UPDATE ON eng_schedule
    FOR EACH ROW EXECUTE FUNCTION trg_sched_gate();
CREATE TRIGGER sched_del_guard BEFORE DELETE ON eng_schedule
    FOR EACH ROW EXECUTE FUNCTION trg_sched_del_guard();
CREATE TRIGGER task_type_guard BEFORE UPDATE OR DELETE ON sched_task_type
    FOR EACH ROW EXECUTE FUNCTION trg_task_type_guard();

-- ★出货单必须和排班是同一个项目（排班挂 A 项目、出货单挂 B 项目，货就发错了，而且不报错）
CREATE OR REPLACE FUNCTION trg_sched_matreq_gate() RETURNS trigger AS $$
DECLARE mr_pj uuid; a text; b text;
BEGIN
    IF NEW.mat_req_id IS NULL THEN RETURN NEW; END IF;
    SELECT project_id INTO mr_pj FROM mat_req WHERE id = NEW.mat_req_id;
    IF mr_pj IS DISTINCT FROM NEW.project_id THEN
        SELECT code INTO a FROM project WHERE id = NEW.project_id;
        SELECT code INTO b FROM project WHERE id = mr_pj;
        RAISE EXCEPTION '门禁：这条排班是项目 % 的，挂的出货单却是项目 % 的 —— '
                        '货会发错工地，而且两张单各自看着都对', COALESCE(a,'（无）'), COALESCE(b,'（无）');
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER sched_matreq_gate BEFORE INSERT OR UPDATE ON eng_schedule
    FOR EACH ROW EXECUTE FUNCTION trg_sched_matreq_gate();

-- ★运维作废维护单 → 连带取消对应排班并留痕（§18）
--   不连带的话，工程那边的人还照着排班去现场，到了才发现单子早作废了
CREATE OR REPLACE FUNCTION trg_mc_void_cancels_sched() RETURNS trigger AS $$
DECLARE n int;
BEGIN
    IF NEW.status = 'void' AND OLD.status IS DISTINCT FROM 'void' THEN
        UPDATE eng_schedule
           SET cancelled_at = now(),
               cancel_reason = '运维作废了维护单「' || COALESCE(NEW.title,'') || '」'
         WHERE task_type = 'maintenance' AND ref_id = NEW.id
           AND cancelled_at IS NULL AND work_date >= current_date;
        GET DIAGNOSTICS n = ROW_COUNT;
        IF n > 0 THEN
            RAISE NOTICE '维护单作废：连带取消了 % 条排班（需短信 + App 通知本人）', n;
        END IF;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER mc_void_cancels_sched AFTER UPDATE ON maintenance_case
    FOR EACH ROW EXECUTE FUNCTION trg_mc_void_cancels_sched();

-- ── 设置键：合理时长的偏差提示线（★只提示不拦）────────────────────
INSERT INTO eng_setting(key, value_num, note, write_depts) VALUES
 ('sched_over_pct',  30, '排班时长超合理时长多少 % 给提示（★只提示不拦——现场千差万别，'
                         '拦死了只会逼人乱填一个数糊弄过去）', ARRAY['eng_mgmt']),
 ('sched_under_pct', 60, '排班时长不足合理时长多少 % 给提示', ARRAY['eng_mgmt']),
 ('sched_remind_dow', 5, '周几提醒排下周（1=周一…5=周五）', ARRAY['eng_mgmt'])
ON CONFLICT (key) DO NOTHING;

-- ── 视图 ─────────────────────────────────────────────────────────────
CREATE VIEW v_sched_week AS
SELECT s.id, s.staff_id, st.name AS staff_name, s.work_date,
       to_char(s.work_date,'ID')::int              AS dow,
       s.start_min, s.end_min, s.minutes,
       to_char((s.start_min||' minutes')::interval,'HH24:MI') || '–' ||
       to_char((s.end_min  ||' minutes')::interval,'HH24:MI') AS time_range,
       -- ≥60 分钟按小时显示（90 分 → 1.5h）
       CASE WHEN s.minutes >= 60 THEN round(s.minutes/60.0,2)::text || 'h'
            ELSE s.minutes::text || 'm' END        AS dur_label,
       s.task_type, t.label AS task_label, t.color, t.counts_hours,
       s.project_id, s.ref_id, s.content, s.remaining_snap, s.remaining_src,
       s.need_pickup, s.pickup_note, s.mat_req_id,
       s.notified_at, s.confirmed_at, s.cancelled_at, s.cancel_reason, s.cancel_ack_at,
       s.locked_at, s.created_by, s.created_at,
       -- 红点 / 绿点
       CASE WHEN s.cancelled_at IS NOT NULL      THEN 'cancelled'
            WHEN s.confirmed_at IS NOT NULL      THEN 'green'
            WHEN s.notified_at  IS NOT NULL      THEN 'red'
            ELSE 'unsent' END                     AS confirm_dot,
       -- ★合理时长偏差：只提示不拦
       t.std_minutes,
       round((s.minutes - t.std_minutes) * 100.0 / t.std_minutes, 0) AS dev_pct,
       CASE
         WHEN s.minutes > t.std_minutes * (1 + COALESCE(
                (SELECT value_num FROM eng_setting WHERE key='sched_over_pct'),30)/100.0)
              THEN '比合理时长长很多'
         WHEN s.minutes < t.std_minutes * COALESCE(
                (SELECT value_num FROM eng_setting WHERE key='sched_under_pct'),60)/100.0
              THEN '比合理时长短很多'
         ELSE NULL END                            AS dev_hint,
       (s.work_date < current_date)               AS is_past
  FROM eng_schedule s
  JOIN eng_staff st       ON st.id = s.staff_id
  JOIN sched_task_type t  ON t.code = s.task_type;
COMMENT ON VIEW v_sched_week IS
  '周视图数据源（周一~周日 × 人）。confirm_dot：红点＝短信发了没回，绿点＝本人回了 Y。'
  '★日程不论回不回都已同步到 App —— 红点只说明「回执没到」，不是「他不知道」。'
  'dev_hint 是合理时长偏差，★只提示不拦';

-- 确认状态清单（可重发短信）+ 取消待确认
CREATE VIEW v_sched_confirm AS
SELECT s.id, s.staff_id, st.name AS staff_name, st.phone, s.work_date, s.project_id,
       s.task_type, t.label AS task_label,
       to_char((s.start_min||' minutes')::interval,'HH24:MI') || '–' ||
       to_char((s.end_min  ||' minutes')::interval,'HH24:MI') AS time_range,
       s.notified_at, s.confirmed_at, s.cancelled_at, s.cancel_ack_at,
       CASE WHEN s.cancelled_at IS NOT NULL AND s.cancel_ack_at IS NULL THEN '取消待确认'
            WHEN s.notified_at IS NULL                                  THEN '还没通知'
            WHEN s.confirmed_at IS NULL                                 THEN '发了没回'
            ELSE '已确认' END                                            AS state,
       round(EXTRACT(epoch FROM (now() - s.notified_at))/3600)          AS waiting_hours
  FROM eng_schedule s
  JOIN eng_staff st      ON st.id = s.staff_id
  JOIN sched_task_type t ON t.code = s.task_type
 WHERE s.work_date >= current_date
   AND (s.confirmed_at IS NULL OR (s.cancelled_at IS NOT NULL AND s.cancel_ack_at IS NULL));
COMMENT ON VIEW v_sched_confirm IS
  '确认状态清单：谁的排班还没回执、谁被取消了还没回 Yes。★被取消的人一定要回 Yes ——'
  '不回就当他没看见，人还是会去现场';

-- 某人某天的路线：按开始时间排 A/B/C/D 站点
CREATE VIEW v_sched_route AS
SELECT s.staff_id, st.name AS staff_name, s.work_date, s.project_id,
       chr(64 + row_number() OVER (PARTITION BY s.staff_id, s.work_date
                                   ORDER BY s.start_min)::int) AS stop_no,
       to_char((s.start_min||' minutes')::interval,'HH24:MI')  AS start_at,
       t.label AS task_label, p.addr_street, p.addr_suburb, p.geo_lat, p.geo_lng
  FROM eng_schedule s
  JOIN eng_staff st      ON st.id = s.staff_id
  JOIN sched_task_type t ON t.code = s.task_type
  LEFT JOIN project p    ON p.id = s.project_id
 WHERE s.cancelled_at IS NULL AND s.project_id IS NOT NULL;
COMMENT ON VIEW v_sched_route IS
  '点人名看当天路线：按派工顺序标 A/B/C/D。正式系统接 Google 地图（与路程预估共用 API Key）';

-- ★项目历史排班（E2 用户就是为这个提的）：过去与将来一起列
CREATE VIEW v_project_schedule AS
SELECT s.project_id, s.work_date, st.name AS staff_name, s.task_type,
       t.label AS task_label,
       to_char((s.start_min||' minutes')::interval,'HH24:MI') || '–' ||
       to_char((s.end_min  ||' minutes')::interval,'HH24:MI') AS time_range,
       s.minutes, s.content, s.remaining_snap,
       s.cancelled_at, s.confirmed_at,
       (s.work_date < current_date)                          AS is_past,
       -- ★计划 vs 实际：过去派了工却没打卡＝红字；未来的不算异常
       CASE WHEN s.work_date >= current_date THEN '已排期 · 还没到'
            WHEN s.cancelled_at IS NOT NULL  THEN '已取消'
            WHEN EXISTS (SELECT 1 FROM work_log w
                          WHERE w.staff_id = s.staff_id AND w.project_id = s.project_id
                            AND w.checkin_at::date = s.work_date) THEN '已打卡'
            ELSE '★派了工没打卡' END                          AS actual_state
  FROM eng_schedule s
  JOIN eng_staff st      ON st.id = s.staff_id
  JOIN sched_task_type t ON t.code = s.task_type;
COMMENT ON VIEW v_project_schedule IS
  '项目详情页的「历史排班」：过去与将来一起列。'
  '★actual_state 就是工程流水账那一列「计划 vs 实际」—— 没有排班表的时候这一列算不出来';

-- 周五提醒排下周：下周有几个人一条都没排
CREATE VIEW v_sched_next_week_gap AS
WITH nx AS (SELECT (date_trunc('week', current_date) + interval '7 days')::date AS d0)
SELECT st.id AS staff_id, st.name,
       (SELECT d0 FROM nx)                       AS week_start,
       (SELECT count(*) FROM eng_schedule s
         WHERE s.staff_id = st.id AND s.cancelled_at IS NULL
           AND s.work_date >= (SELECT d0 FROM nx)
           AND s.work_date <  (SELECT d0 FROM nx) + 7) AS task_n
  FROM eng_staff st
 WHERE st.terminated_at IS NULL AND st.active;
COMMENT ON VIEW v_sched_next_week_gap IS
  '周五顶部橙条的数据源：下周谁一条都没排。★同一条提醒不累积（每小时一次，锁定整周即停）';

-- ── 登记：写入归属 + 项目归属（v0.31/v0.33 两次教训：只建表不登记＝断言违规）──
INSERT INTO table_ownership(table_name, write_dept, note) VALUES
 ('sched_task_type',   ARRAY['eng_mgmt'],
   'v0.38：排班任务类型（工程设置页）。六类内建不可删，用过的也删不掉'),
 ('eng_schedule',      ARRAY['eng_mgmt'],
   'v0.38：★派工排班由工程管理排；维护上门也在这里排（运维不另做一套）'),
 ('daily_report_line', ARRAY['eng_mgmt'],
   'v0.38：每日上报分段。★施工人员在 App 上写自己那几段（RLS 再限本人行）')
ON CONFLICT (table_name) DO NOTHING;

INSERT INTO project_scope_registry(table_name, kind, kind_cn, trace_path, note) VALUES
 ('sched_task_type',  'config','配置','—','排班任务类型是全公司口径'),
 ('eng_schedule',     'project_or_scope','项目或公司级','project_id 为空＝倒休',
   '★倒休不属于任何项目（休假不是工作）；其余一律必须有项目'),
 ('daily_report_line','project_or_scope','项目或公司级','project_id · is_company_level',
   '一人一天可跑多个项目，一段一个项目')
ON CONFLICT (table_name) DO NOTHING;

-- ── RLS ──────────────────────────────────────────────────────────────
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['sched_task_type','eng_schedule'] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format($f$CREATE POLICY %1$s_ins ON %1$I FOR INSERT
            WITH CHECK (fn_can_write(%1$L))$f$, t);
        EXECUTE format($f$CREATE POLICY %1$s_upd ON %1$I FOR UPDATE
            USING (fn_can_write(%1$L)) WITH CHECK (fn_can_write(%1$L))$f$, t);
        EXECUTE format($f$CREATE POLICY %1$s_del ON %1$I FOR DELETE
            USING (fn_is_admin())$f$, t);
    END LOOP;
END $$;
CREATE POLICY sched_task_type_read ON sched_task_type FOR SELECT USING (true);
-- ★施工人员（三级账号）只有 App：看得见【自己的】排班，别人的看不见
CREATE POLICY eng_schedule_read ON eng_schedule FOR SELECT
    USING (NOT fn_is_field() OR fn_is_admin() OR staff_id = fn_my_staff_id());

-- 每日上报分段：口径与 daily_report 完全一致（本人写自己的）
ALTER TABLE daily_report_line ENABLE ROW LEVEL SECURITY;
CREATE POLICY daily_report_line_read ON daily_report_line FOR SELECT
    USING (NOT fn_is_field() OR fn_is_admin()
           OR EXISTS (SELECT 1 FROM daily_report r
                       WHERE r.id = report_id AND r.staff_id = fn_my_staff_id()));
CREATE POLICY daily_report_line_write ON daily_report_line FOR ALL
    USING (fn_can_write('daily_report_line')
           OR (fn_is_field() AND EXISTS (SELECT 1 FROM daily_report r
                WHERE r.id = report_id AND r.staff_id = fn_my_staff_id())))
    WITH CHECK (fn_can_write('daily_report_line')
           OR (fn_is_field() AND EXISTS (SELECT 1 FROM daily_report r
                WHERE r.id = report_id AND r.staff_id = fn_my_staff_id())));

-- ── 乐观锁 + 视图规矩：两个函数各调一次（v0.37 起配成一对）────────────
SELECT fn_apply_optlock();

-- ── 断言 +5（90 → 95）────────────────────────────────────────────────
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES

('INV-SCH-01','★同一人同一天两段排班不许时间重叠','critical',
 $q$SELECT st.name, a.work_date, a.start_min, a.end_min, b.start_min, b.end_min
      FROM eng_schedule a JOIN eng_schedule b
        ON b.staff_id = a.staff_id AND b.work_date = a.work_date AND b.id > a.id
      JOIN eng_staff st ON st.id = a.staff_id
     WHERE a.cancelled_at IS NULL AND b.cancelled_at IS NULL
       AND a.start_min < b.end_min AND a.end_min > b.start_min$q$,
 '一个人不能同时在两个工地。重叠了两边都以为他会去，结果他只到了一处，另一处白等一天'),

('INV-SCH-02','非倒休的排班必须关联项目','critical',
 $q$SELECT id, work_date, task_type FROM eng_schedule
     WHERE task_type <> 'toil' AND project_id IS NULL$q$,
 '排班不挂项目，这段工时就进不了任何项目成本 —— 人干了活，成本凭空消失，而且不报错'),

('INV-SCH-03','排班的起止必须 15 分钟对齐且截止晚于开始','high',
 $q$SELECT id, work_date, start_min, end_min FROM eng_schedule
     WHERE start_min % 15 <> 0 OR end_min % 15 <> 0 OR end_min <= start_min$q$,
 '出现 16:20 这种时间，工时统计和路线预估就都对不齐了'),

('INV-SCH-04','★倒休排班不许超过倒休余额','critical',
 -- ★用 fn_toil_balance_min 而不是 v_toil_balance：后者裹着薪酬遮罩，
 --   断言跑起来同样没有身份，balance_min 会是 NULL → COALESCE 成 0 →
 --   每一条倒休排班都被报成"透支"。断言要是这么写，等于天天喊狼来了，
 --   最后没人再看它 —— 比不写还糟
 $q$SELECT st.name, fn_toil_balance_min(x.staff_id) AS balance_min, x.planned
      FROM (SELECT staff_id, SUM(minutes) AS planned FROM eng_schedule
             WHERE task_type='toil' AND cancelled_at IS NULL AND work_date >= current_date
             GROUP BY staff_id) x
      JOIN eng_staff st ON st.id = x.staff_id
     WHERE x.planned > fn_toil_balance_min(x.staff_id)$q$,
 '倒休透支＝公司白发了工资，而且要等到年底对账才可能发现。'
 '写入时门禁查过一次，但余额会因为离职清算、强制扣减变少 —— 所以必须现算全库再查一遍'),

('INV-SCH-05','★排班挂的出货单必须是同一个项目','critical',
 $q$SELECT s.id, s.work_date, s.project_id, m.project_id AS req_project
      FROM eng_schedule s JOIN mat_req m ON m.id = s.mat_req_id
     WHERE m.project_id IS DISTINCT FROM s.project_id$q$,
 '排班挂 A 项目、出货单挂 B 项目 → 货发错工地。两张单各自看着都对，只有对起来才看得出');

-- ── 收尾：视图规矩（security_invoker + 项目标识）────────────────────
SELECT fn_apply_view_conventions();

-- #####################################################################
-- ##  v0.39：部门授权 —— ★最高管理者默认对别的部门【只读】
-- ##
-- ##  用户 2026-08-10 提出：最高管理者是唯一一个能写所有部门的角色，
-- ##  所以他是【唯一可能和别人撞车的人】。乐观锁的做法是「撞了才报错」，
-- ##  这一版改成【根本不让它撞】—— 默认只能看，部门负责人点了「休假授权」才能动。
-- ##
-- ##  顺带解决另一件事：出了问题说得清是谁动的。
-- ##  「为什么这单是陈总改的？」——「小林 8/12 授权到 8/20，日志里有。」
-- ##
-- ##  ★「本职操作」与「代部门操作」的划分是【天然的】，不手列清单：
-- ##    表在 table_ownership 里有部门归属  → 管理员写它＝代那个部门干活 → 要授权
-- ##    表没有部门归属（决策看板 / 账号权限 / 断言定义 / 全局参数）→ 本职 → 照旧
-- ##  （手列一定会漏，而漏掉的那张表会一直敞着，还不报错 —— 全项目一贯的教训）
-- #####################################################################

-- =====================================================================
--  第五十一部分：部门授权 dept_delegation
-- =====================================================================
CREATE TABLE dept_delegation (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    department   text NOT NULL CHECK (department IN
                   ('presales','eng_mgmt','procurement','warehouse','finance','maintenance')),
    -- 两种来源，责任完全不同：
    --   leave    = 部门负责人自己点的「休假授权」——他知情、他同意
    --   takeover = 最高管理者强制接管 —— 他联系不上，出口在这儿，但要写清为什么 + 通知本人
    kind         text NOT NULL CHECK (kind IN ('leave','takeover')),
    granted_by   uuid NOT NULL REFERENCES app_account(id),
    granted_at   timestamptz NOT NULL DEFAULT now(),
    -- ★到期日必填：只能手动解除的话，休假回来忘了收回，这道门就白设了
    until_date   date NOT NULL,
    -- ★强制接管必须写原因 ≥10 字：这是事后唯一能复盘的东西
    reason       text,
    -- 强制接管必须通知本人（短信 + App），不通知就是偷偷摸摸
    notified_at  timestamptz,
    -- 提前解除（休假回来早了 / 接管结束）
    revoked_at   timestamptz,
    revoked_by   uuid REFERENCES app_account(id),
    revoke_note  text,
    CONSTRAINT ck_deleg_reason CHECK (kind <> 'takeover'
                                      OR length(btrim(COALESCE(reason,''))) >= 10)
);
-- ★同一个部门同时只能有一条生效的授权 ——
--   两条并存时，解除了一条还剩一条，人以为收回了实际没有，而且不会报错
CREATE UNIQUE INDEX uq_deleg_active ON dept_delegation(department)
    WHERE revoked_at IS NULL;
CREATE INDEX idx_deleg_until ON dept_delegation(until_date) WHERE revoked_at IS NULL;
COMMENT ON TABLE dept_delegation IS
  '部门授权。★最高管理者默认只能【看】别的部门，不能【动】—— '
  '他是唯一能写所有部门的角色，也就是唯一可能和别人撞车的人。'
  '休假授权＝部门负责人自己点；强制接管＝联系不上时的出口（写原因+通知本人+日志标红）';
COMMENT ON COLUMN dept_delegation.until_date IS
  '★授权到哪天（必填）。到期自动失效 —— 只靠手动解除的话，休假回来忘了收回，这道门就白设了';

-- ── 门禁 ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_deleg_gate() RETURNS trigger AS $$
DECLARE me_tier int; is_head_of boolean; dept_cn text;
BEGIN
    dept_cn := CASE NEW.department
                 WHEN 'presales' THEN '售前'    WHEN 'eng_mgmt'   THEN '工程管理'
                 WHEN 'procurement' THEN '采购' WHEN 'warehouse'  THEN '库管'
                 WHEN 'finance' THEN '财务'     WHEN 'maintenance' THEN '运维' END;

    IF TG_OP = 'INSERT' THEN
        -- ① 到期日不能是过去
        IF NEW.until_date < current_date THEN
            RAISE EXCEPTION '门禁：授权到期日（%）已经过去了 —— 填了等于没授权',
                            to_char(NEW.until_date,'YYYY-MM-DD');
        END IF;
        -- ② 到期日不能太远：休假不会休三个月。填错一个年份，这道门就永远敞着了
        IF NEW.until_date > current_date + 90 THEN
            RAISE EXCEPTION '门禁：授权到 % —— 超过 90 天了，是不是填错了？'
                            '真要长期交接，请走「停用账号 + 重新指派部门负责人」，'
                            '别用休假授权把门长期敞着',
                            to_char(NEW.until_date,'YYYY-MM-DD');
        END IF;

        SELECT tier INTO me_tier FROM app_account WHERE id = NEW.granted_by;

        IF NEW.kind = 'leave' THEN
            -- ③ 休假授权只能由【本部门负责人】自己点
            SELECT EXISTS(SELECT 1 FROM account_department
                           WHERE account_id = NEW.granted_by
                             AND department = NEW.department AND is_head)
              INTO is_head_of;
            IF NOT is_head_of THEN
                RAISE EXCEPTION '门禁：「休假授权」只能由 % 部门的负责人本人点 —— '
                                '别人替他点，就等于绕过了这道授权。'
                                '联系不上他请走「强制接管」（要写原因，本人会收到短信）', dept_cn;
            END IF;
        ELSE
            -- ④ 强制接管只能由决策管理员点
            IF me_tier IS DISTINCT FROM 1 THEN
                RAISE EXCEPTION '门禁：只有决策管理员能强制接管部门';
            END IF;
        END IF;
    END IF;

    -- ⑤ 生效中的授权，关键字段不许改（要改就解除了重开一条，留痕比改干净）
    IF TG_OP = 'UPDATE' AND OLD.revoked_at IS NULL THEN
        IF NEW.department IS DISTINCT FROM OLD.department
           OR NEW.kind IS DISTINCT FROM OLD.kind
           OR NEW.granted_by IS DISTINCT FROM OLD.granted_by THEN
            RAISE EXCEPTION '门禁：生效中的授权不能改部门/类型/发起人 —— '
                            '请先解除，再开一条新的。改掉就看不出当初是谁授权给谁的了';
        END IF;
        -- 延期也要守住 90 天上限
        IF NEW.until_date > current_date + 90 THEN
            RAISE EXCEPTION '门禁：延到 % 超过 90 天了 —— 长期交接请走重新指派部门负责人',
                            to_char(NEW.until_date,'YYYY-MM-DD');
        END IF;
    END IF;
    RETURN NEW;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER deleg_gate BEFORE INSERT OR UPDATE ON dept_delegation
    FOR EACH ROW EXECUTE FUNCTION trg_deleg_gate();

-- ★强制接管必须通知本人：登记即发（应用层发短信，这里把「发了没有」钉死）
CREATE OR REPLACE FUNCTION trg_deleg_notify() RETURNS trigger AS $$
DECLARE head_phone text; head_name text; dept_cn text; admin_name text;
BEGIN
    IF NEW.kind <> 'takeover' THEN RETURN NULL; END IF;
    dept_cn := CASE NEW.department
                 WHEN 'presales' THEN '售前'    WHEN 'eng_mgmt'   THEN '工程管理'
                 WHEN 'procurement' THEN '采购' WHEN 'warehouse'  THEN '库管'
                 WHEN 'finance' THEN '财务'     WHEN 'maintenance' THEN '运维' END;
    SELECT a.phone, a.full_name INTO head_phone, head_name
      FROM account_department d JOIN app_account a ON a.id = d.account_id
     WHERE d.department = NEW.department AND d.is_head AND a.active LIMIT 1;
    SELECT full_name INTO admin_name FROM app_account WHERE id = NEW.granted_by;

    IF head_phone IS NOT NULL THEN
        INSERT INTO notification(channel, recipient, subject, body,
                                 ref_kind, ref_id, scope, triggered_by)
        VALUES ('sms', head_phone,
                '你负责的部门已被强制接管',
                COALESCE(head_name,'') || '，你负责的【' || dept_cn || '】已于 ' ||
                to_char(NEW.granted_at,'MM-DD HH24:MI') || ' 由 ' || COALESCE(admin_name,'管理员') ||
                ' 强制接管，至 ' || to_char(NEW.until_date,'MM-DD') || '。原因：' ||
                COALESCE(NEW.reason,'') || E'\n如非预期请立刻联系。',
                'dept_delegation', NEW.id, 'company', COALESCE(admin_name,'管理员'));
        UPDATE dept_delegation SET notified_at = now() WHERE id = NEW.id;
    END IF;
    RETURN NULL;
END $$ LANGUAGE plpgsql;
CREATE TRIGGER deleg_notify AFTER INSERT ON dept_delegation
    FOR EACH ROW EXECUTE FUNCTION trg_deleg_notify();

-- =====================================================================
--  ★ 写权限重写：管理员那一支加授权检查
-- =====================================================================

-- 「真的挂在这个部门下」—— 不含管理员的万能通行。
-- ★fn_has_dept() 里第一句就是 fn_is_admin()，管理员对任何部门都返回 true；
--   用它判断「是不是本部门的人」，管理员永远混在里面，这道授权门就形同虚设。
CREATE OR REPLACE FUNCTION fn_in_dept(p_dept text) RETURNS boolean AS $$
    SELECT EXISTS(SELECT 1 FROM account_department d
                   WHERE d.account_id = (SELECT id FROM fn_me())
                     AND d.department = p_dept);
$$ LANGUAGE sql STABLE SECURITY DEFINER;
COMMENT ON FUNCTION fn_in_dept IS
  '★真的挂在这个部门下（不含管理员万能通行）。fn_has_dept 对管理员永远 true，'
  '判断「是不是本部门的人」必须用这个';

-- 某部门当前有没有生效的授权
CREATE OR REPLACE FUNCTION fn_dept_delegated(p_dept text) RETURNS boolean AS $$
    SELECT EXISTS(SELECT 1 FROM dept_delegation
                   WHERE department = p_dept
                     AND revoked_at IS NULL
                     AND until_date >= current_date);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ★管理员能不能写这张表
CREATE OR REPLACE FUNCTION fn_admin_may_write(p_table text) RETURNS boolean AS $$
    SELECT
      -- ① 没有部门归属的表 ＝ 管理员本职（决策看板 / 账号权限 / 断言定义 / 登记表…）
      --    这个划分是天然的，不用手列清单 —— 手列一定会漏，漏的那张会一直敞着且不报错
      NOT EXISTS(SELECT 1 FROM table_ownership o
                  WHERE o.table_name = p_table
                    AND COALESCE(array_length(o.write_dept,1),0) > 0)
      -- ② 有部门归属：该表所属的【任一】部门授权了就行
      --    共写表（如 purchase_req 挂 4 个部门）要求全部授权的话，它就永远写不了
      OR EXISTS(SELECT 1 FROM table_ownership o, unnest(o.write_dept) AS d
                 WHERE o.table_name = p_table AND fn_dept_delegated(d));
$$ LANGUAGE sql STABLE SECURITY DEFINER;
COMMENT ON FUNCTION fn_admin_may_write IS
  '★最高管理者默认对别的部门只读。本职操作（没有部门归属的表）照旧；'
  '代部门操作要等那个部门授权（休假授权或强制接管）';

CREATE OR REPLACE FUNCTION fn_can_write(p_table text) RETURNS boolean AS $$
    -- ① 本部门的人：照旧（用 fn_in_dept，不用 fn_has_dept——后者对管理员永远 true）
    SELECT EXISTS(SELECT 1 FROM table_ownership o, unnest(o.write_dept) AS d
                   WHERE o.table_name = p_table AND fn_in_dept(d))
    -- ② 管理员：本职照旧，代部门要授权
        OR (fn_is_admin() AND fn_admin_may_write(p_table));
$$ LANGUAGE sql STABLE SECURITY DEFINER;
COMMENT ON FUNCTION fn_can_write IS
  '★v0.39 起：管理员不再无条件放行。他写【有部门归属】的表＝代那个部门干活，'
  '要么那个部门点了休假授权，要么他强制接管（写原因+通知本人）。'
  '决策页那些没有部门归属的表不受影响';

-- ★删除比修改更危险，同样要授权（自动扫全库，不手列）
CREATE OR REPLACE FUNCTION fn_can_delete(p_table text) RETURNS boolean AS $$
    SELECT fn_is_admin() AND fn_admin_may_write(p_table);
$$ LANGUAGE sql STABLE SECURITY DEFINER;

DO $del$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT tablename, policyname FROM pg_policies
              WHERE schemaname = 'public' AND cmd = 'DELETE'
                AND qual = 'fn_is_admin()'
    LOOP
        EXECUTE format('DROP POLICY %I ON %I', r.policyname, r.tablename);
        EXECUTE format('CREATE POLICY %I ON %I FOR DELETE USING (fn_can_delete(%L))',
                       r.policyname, r.tablename, r.tablename);
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'v0.39 删除策略改为要授权：% 条', n;
END $del$;

-- ── 登记 + RLS ───────────────────────────────────────────────────────
-- ★故意【不登记 write_dept】：授权表本身是决策级的，不属于任何部门 ——
--   要是给它挂上部门，就会出现「部门负责人自己给自己授权」的循环
INSERT INTO table_ownership(table_name, write_dept, note) VALUES
 ('dept_delegation', ARRAY[]::text[],
  'v0.39：部门授权。★不挂部门归属 —— 挂了就成了「自己给自己授权」的循环')
ON CONFLICT (table_name) DO NOTHING;
INSERT INTO project_scope_registry(table_name, kind, kind_cn, trace_path, note) VALUES
 ('dept_delegation','company_level','公司级','—','授权是公司级的事，不属于任何项目')
ON CONFLICT (table_name) DO NOTHING;

ALTER TABLE dept_delegation ENABLE ROW LEVEL SECURITY;
-- 谁都看得见（授权状态是公开的：大家要知道现在这个部门归谁管）
CREATE POLICY dept_delegation_read ON dept_delegation FOR SELECT
    USING (NOT fn_is_field() OR fn_is_admin());
-- 部门负责人点自己部门的休假授权；管理员点强制接管
CREATE POLICY dept_delegation_ins ON dept_delegation FOR INSERT
    WITH CHECK (fn_is_admin() OR fn_in_dept(department));
CREATE POLICY dept_delegation_upd ON dept_delegation FOR UPDATE
    USING (fn_is_admin() OR fn_in_dept(department))
    WITH CHECK (fn_is_admin() OR fn_in_dept(department));
-- ★没有 DELETE 策略：授权记录只增不删 —— 能删的授权记录，等于没有记录

-- 现在谁管着哪个部门（页顶那条横幅的数据源）
CREATE VIEW v_dept_delegation AS
SELECT d.department,
       CASE d.department
         WHEN 'presales' THEN '售前'    WHEN 'eng_mgmt'   THEN '工程管理'
         WHEN 'procurement' THEN '采购' WHEN 'warehouse'  THEN '库管'
         WHEN 'finance' THEN '财务'     WHEN 'maintenance' THEN '运维' END AS dept_cn,
       d.kind,
       CASE d.kind WHEN 'leave' THEN '休假授权' ELSE '★强制接管' END AS kind_cn,
       g.full_name AS granted_by_name, d.granted_at, d.until_date,
       (d.until_date - current_date)          AS days_left,
       d.reason, d.notified_at,
       (SELECT a.full_name FROM account_department ad
          JOIN app_account a ON a.id = ad.account_id
         WHERE ad.department = d.department AND ad.is_head AND a.active LIMIT 1) AS head_name
  FROM dept_delegation d
  LEFT JOIN app_account g ON g.id = d.granted_by
 WHERE d.revoked_at IS NULL AND d.until_date >= current_date;
COMMENT ON VIEW v_dept_delegation IS
  '当前生效的部门授权 —— 部门页顶那条横幅（「本部门已授权给陈总，至 08-20 · 解除」）的数据源';

SELECT fn_apply_optlock();

-- ── 断言 +3（95 → 98）────────────────────────────────────────────────
INSERT INTO assertion_def(code,label,severity,query,hint) VALUES

('INV-DEL-01','★强制接管必须写原因并通知到本人','critical',
 $q$SELECT id, department, granted_at FROM dept_delegation
     WHERE kind = 'takeover'
       AND (length(btrim(COALESCE(reason,''))) < 10 OR notified_at IS NULL)$q$,
 '强制接管是绕过部门负责人本人的操作。不写原因＝事后无法复盘；不通知本人＝偷偷摸摸接管，'
 '这两样缺一，这个出口就会变成后门'),

('INV-DEL-02','休假授权必须由本部门负责人本人发起','critical',
 $q$SELECT d.id, d.department FROM dept_delegation d
     WHERE d.kind = 'leave' AND d.revoked_at IS NULL
       AND NOT EXISTS(SELECT 1 FROM account_department ad
                       WHERE ad.account_id = d.granted_by
                         AND ad.department = d.department AND ad.is_head)$q$,
 '别人替他点了休假授权 → 等于绕过了这道授权。联系不上本人应该走强制接管（要写原因+通知）'),

('INV-DEL-03','一个部门同时只能有一条生效的授权','high',
 $q$SELECT department, count(*) FROM dept_delegation
     WHERE revoked_at IS NULL AND until_date >= current_date
     GROUP BY department HAVING count(*) > 1$q$,
 '两条并存时，解除了一条还剩一条 —— 人以为收回了，实际门还开着，而且不会报错');

SELECT fn_apply_view_conventions();
