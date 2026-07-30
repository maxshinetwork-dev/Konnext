/**
 * 短信通道：twilio(真发) | console(打日志) | fixed(固定码 000000)。
 * 三种模式下 auth_otp 的写入/过期/作废逻辑一字不差 —— 切 Twilio 只改环境变量。
 *
 * ★生产保险丝：production 配了 console/fixed 或 dev 查码端点 → 模块加载即 throw，
 *   登录整体不可用（显性事故立刻被发现），宁可报错不要静默放行。
 */

export type SmsTransport = "twilio" | "console" | "fixed";

export function transport(): SmsTransport {
  const t = process.env.OTP_TRANSPORT ?? "console";
  if (t !== "twilio" && t !== "console" && t !== "fixed") {
    throw new Error(`OTP_TRANSPORT 非法值：${t}`);
  }
  return t;
}

export function assertProdSafety(): void {
  // 构建阶段只收集元数据、不对外服务 —— 保险丝只在运行时起爆
  if (process.env.NEXT_PHASE === "phase-production-build") return;
  const prod =
    process.env.VERCEL_ENV === "production" ||
    (process.env.NODE_ENV === "production" && !process.env.VERCEL_ENV);
  if (!prod) return;
  if (transport() !== "twilio") {
    throw new Error("保险丝：生产环境 OTP_TRANSPORT 必须为 twilio（当前配置会泄漏验证码）");
  }
  if (process.env.ALLOW_DEV_OTP_ENDPOINT === "true") {
    throw new Error("保险丝：生产环境不得开启 ALLOW_DEV_OTP_ENDPOINT");
  }
}
assertProdSafety();

/** dev 便利：console/fixed 模式把最新明文码留在内存里，供 /api/dev/otp 查询（库里永远只有散列） */
import { devStoreSmsCode, devPeekSmsCode } from "./devstore";
export const devPeekCode = devPeekSmsCode;

export async function sendSms(to: string, body: string, code?: string): Promise<void> {
  const t = transport();
  if (t === "twilio") {
    const sid = process.env.TWILIO_ACCOUNT_SID;
    const token = process.env.TWILIO_AUTH_TOKEN;
    const from = process.env.TWILIO_FROM_NUMBER;
    if (!sid || !token || !from) throw new Error("Twilio 环境变量不全（SID/TOKEN/FROM）");
    const res = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
      {
        method: "POST",
        headers: {
          Authorization: "Basic " + Buffer.from(`${sid}:${token}`).toString("base64"),
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({ To: to, From: from, Body: body }),
      },
    );
    if (!res.ok) {
      const detail = await res.text().catch(() => "");
      throw new Error(`Twilio 发送失败 HTTP ${res.status}：${detail.slice(0, 300)}`);
    }
    return;
  }
  if (code) devStoreSmsCode(to, code);
  console.log(`[sms:${t}] → ${to}：${body}`);
}
