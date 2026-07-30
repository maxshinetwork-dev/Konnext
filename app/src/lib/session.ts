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
};

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

/** 业务 API 的守门员：必须是完整会话（短信/邮箱全过） */
export async function requireSession(): Promise<{ accountId: string; view?: string }> {
  const s = await getSession();
  if (s.stage !== "full" || !s.accountId) {
    throw new AuthError("未登录或登录未完成，请先登录");
  }
  return { accountId: s.accountId, view: s.view };
}

/** 写操作的 CSRF 双保险：SameSite=Lax 之外再验一个自定义头 */
export function assertCsrf(req: Request): void {
  if (req.headers.get("x-requested-with") !== "konnext") {
    throw new AuthError("请求缺少防伪标头", 403);
  }
}
