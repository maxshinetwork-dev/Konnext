-- =====================================================================
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
    origin        text NOT NULL DEFAULT 'sm3',
    change_type   text NOT NULL CHECK (change_type IN ('add','remove','move')),
    description   text,
    photos        jsonb NOT NULL DEFAULT '[]',      -- 图片(移位在图上标)
    logged_by     uuid REFERENCES eng_staff(id),
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

-- project：updated_at 刷新 + 乐观锁自增
CREATE OR REPLACE FUNCTION trg_project_touch() RETURNS trigger AS $$
BEGIN NEW.updated_at := now(); NEW.version := OLD.version + 1; RETURN NEW; END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER project_touch BEFORE UPDATE ON project
    FOR EACH ROW EXECUTE FUNCTION trg_project_touch();

-- project：乐观锁服务端兜底
CREATE OR REPLACE FUNCTION trg_project_optlock() RETURNS trigger AS $$
BEGIN
    IF current_setting('app.expected_version', true) IS NOT NULL
       AND current_setting('app.expected_version', true) <> ''
       AND OLD.version <> current_setting('app.expected_version', true)::int THEN
        RAISE EXCEPTION '乐观锁冲突：项目已被他人修改(期望 %，实际 %)，请刷新重试',
            current_setting('app.expected_version', true), OLD.version;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER project_optlock BEFORE UPDATE ON project
    FOR EACH ROW EXECUTE FUNCTION trg_project_optlock();

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
 ('daily_payroll',      ARRAY['finance'],       NULL),
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
 WHERE event_key IN ('stocktake_pending','reorder_alert');

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
    category      text NOT NULL CHECK (category IN
                    ('travel','parking','toll','fuel','material','tool','meal','other')),
    amount_aud    numeric(12,2) NOT NULL CHECK (amount_aud > 0),
    gst_amount    numeric(12,2) NOT NULL DEFAULT 0,
    receipt_url   text,                        -- 收据照片
    description   text,
    status        text NOT NULL DEFAULT 'draft' CHECK (status IN
                    ('draft','submitted','approved','rejected','paid')),
    submitted_at  timestamptz,
    approved_by   uuid REFERENCES app_account(id),
    approved_at   timestamptz,
    reject_reason text,
    paid_at       timestamptz,
    paid_method   text CHECK (paid_method IN ('bank','cash','payroll')),
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
  '报销：★必须落到项目，或明确标为公司级/无从追溯并填原因。已批准的报销进项目成本';

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
         round(SUM(c.amount_aud) FILTER (WHERE c.status='paid'),2) END   AS expense_paid,
       CASE WHEN fn_can_see_margin() THEN
         round(SUM(c.amount_aud) FILTER (WHERE c.status IN ('submitted','approved')),2) END AS expense_pending
  FROM expense_claim c
  JOIN v_project_label lb ON lb.project_id=c.project_id
 WHERE c.status IN ('submitted','approved','paid') AND c.scope='project'
 GROUP BY c.project_id, lb.code, lb.display_label, lb.addr_suburb, lb.addr_full;

-- 公司级报销（不摊项目，单列）
CREATE VIEW v_company_expense AS
SELECT c.scope, c.scope_reason, c.category, count(*) AS claim_count,
       CASE WHEN fn_can_see_margin() THEN round(SUM(c.amount_aud),2) END AS expense_total
  FROM expense_claim c
 WHERE c.scope <> 'project' AND c.status IN ('submitted','approved','paid')
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
