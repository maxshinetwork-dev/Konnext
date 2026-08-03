import { getIronSession, type IronSession, type SessionOptions } from "iron-session";
import { cookies } from "next/headers";
import { AuthError } from "./errors";

/**
 * 会话：无状态加密 Cookie（iron-session）。
 * 只信 accountId —— tier/部门每个请求都从库里现取（停用账号下一请求即失效，
 * 吊销由数据库兜底）。中间登录态（短信已过、等邮箱码）也放这里，stage 区分。
 */
export type SessionData = {
  stage?: "sms_sent" | "email_pending" | "full";
  accountId?: string;
  /** 已通过的验证方式 */
  amr?: ("sms" | "email")[];
  /** 兼任者选的视角（只影响默认落地页，不影响权限） */
  view?: string;
  /** 登录尝试计数（防爆破验证码） */
  attempts?: number;
  iat?: number;
  /** 最后一次活动时间（毫秒）—— 空闲超过 IDLE_MS 自动锁屏，见下 */
  seen?: number;
  /** 最近一次二次验证通过时间（毫秒）—— 不可逆操作要求 STEPUP_MS 内验过 */
  stepUpAt?: number;
};

/**
 * ★ 空闲自动锁屏 30 分钟（用户 2026-08-03 定）
 *
 * 真实场景：部门管理员在办公室电脑打开页面没关，回家用另一台改了东西；
 * 同事碰了办公室那台 —— 那台还挂着他的登录态，屏幕上是旧数据。
 * 纯阅读不会出事（读不写库），出事的是「同事在旧页面上点一下」：
 * 旧快照覆盖新数据，而且日志会记成管理员本人做的。
 * 空闲 30 分钟就锁屏，是挡住这件事成本最低的一道。
 *
 * 会话本身是 7 天滑动，这里叠一层「多久没动就要重新验」。
 */
export const IDLE_MS = 30 * 60 * 1000;
/** 二次验证有效期：验过之后 5 分钟内的不可逆操作免再验（连着办几件事不用验几次） */
export const STEPUP_MS = 5 * 60 * 1000;
/** 前端据此弹锁屏（要重新发短信码），不要当成普通 401 跳登录页丢掉未存内容 */
export const IDLE_MSG =
  "已经 30 分钟没有操作，为安全起见页面已锁定 —— 请重新用短信验证码解锁再继续（这样别人碰到你没关的电脑也动不了）";
export const STEPUP_MSG =
  "这一步会定格、发出去或者改不回来，请先用短信验证码确认一次是你本人在操作";

const isProd = process.env.NODE_ENV === "production";

function options(): SessionOptions {
  const secret = process.env.SESSION_SECRET;
  if (!secret || secret.length < 32) {
    throw new Error("SESSION_SECRET 缺失或太短（>=32 字节，openssl rand -base64 48）");
  }
  return {
    // __Host- 前缀要求 Secure，本地 http 开发下退回普通名
    cookieName: isProd ? "__Host-konnext" : "konnext_session",
    password: secret,
    ttl: 7 * 24 * 3600, // 7 天滑动
    cookieOptions: {
      httpOnly: true,
      secure: isProd,
      sameSite: "lax",
      path: "/",
    },
  };
}

export async function getSession(): Promise<IronSession<SessionData>> {
  return getIronSession<SessionData>(await cookies(), options());
}

/**
 * 业务 API 的守门员：必须是完整会话（短信/邮箱全过），且没有空闲超过 30 分钟。
 * 每次通过都会把 seen 往前推（超过 1 分钟才写 cookie，省得每个请求都 Set-Cookie）。
 */
export async function requireSession(): Promise<{ accountId: string; view?: string }> {
  const s = await getSession();
  if (s.stage !== "full" || !s.accountId) {
    throw new AuthError("未登录或登录未完成，请先登录");
  }
  const now = Date.now();
  const seen = s.seen ?? now;
  if (now - seen > IDLE_MS) {
    // 不销毁会话：锁屏而已，解锁后回到原来那一页，未存的内容不至于白填
    s.stage = "sms_sent";
    s.stepUpAt = undefined;
    await s.save();
    throw new AuthError(IDLE_MSG, 401);
  }
  if (now - seen > 60_000) {
    s.seen = now;
    await s.save();
  }
  return { accountId: s.accountId, view: s.view };
}

/**
 * 不可逆操作的守门员（★用户 2026-08-03 定）：
 * SM 完成定格 / 确认交付（利润率定格）/ 文档发放 / 标记请款 / 拒付停服 这一类，
 * 要求 STEPUP_MS 内做过一次短信二次验证 —— 「同事随手一点」过不去这一关。
 */
export async function requireStepUp(): Promise<void> {
  const s = await getSession();
  const at = s.stepUpAt ?? 0;
  if (Date.now() - at > STEPUP_MS) {
    throw new AuthError(STEPUP_MSG, 403);
  }
}

/** 写操作的 CSRF 双保险：SameSite=Lax 之外再验一个自定义头 */
export function assertCsrf(req: Request): void {
  if (req.headers.get("x-requested-with") !== "konnext") {
    throw new AuthError("请求缺少防伪标头", 403);
  }
}
