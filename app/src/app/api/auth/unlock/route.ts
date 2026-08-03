import { resendSmsOtp, verifyOtp, voidActiveCode, OTP_FAIL_MSG } from "@/lib/otp";
import { getSession, assertCsrf } from "@/lib/session";
import { toResponse } from "@/lib/errors";

export const dynamic = "force-dynamic";

/**
 * 空闲 30 分钟锁屏后的解锁（★用户 2026-08-03 定）。
 *
 * 锁屏不销毁会话——只是把 stage 退回 sms_sent，解锁后还在原来那一页，
 * 没存的内容不至于白填。解锁只要短信码：账号是谁服务器已经知道，不必再输手机号。
 *
 * POST {action:'request'} → 往登记的手机补发验证码
 * POST {action:'verify', code} → 验过就解锁，重新计 30 分钟
 */
export async function POST(req: Request): Promise<Response> {
  try {
    assertCsrf(req);
    const s = await getSession();
    if (!s.accountId) {
      return Response.json({ error: "会话已失效，请重新登录" }, { status: 401 });
    }
    const body = (await req.json()) as { action?: string; code?: string };
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "local";

    if (body.action === "request") {
      await resendSmsOtp(s.accountId, ip);
      return Response.json({ ok: true, sent: "sms" });
    }

    if (body.action === "verify") {
      const ok = await verifyOtp(s.accountId, "sms", String(body.code ?? ""));
      if (!ok) {
        s.attempts = (s.attempts ?? 0) + 1;
        if (s.attempts >= 5) {
          await voidActiveCode(s.accountId, "sms");
          s.destroy();
          return Response.json(
            { error: "错误次数过多，验证码已作废，请重新登录" },
            { status: 401 },
          );
        }
        await s.save();
        return Response.json({ error: OTP_FAIL_MSG }, { status: 401 });
      }
      s.stage = "full";
      s.seen = Date.now();
      s.attempts = 0;
      await s.save();
      return Response.json({ ok: true });
    }

    return Response.json({ error: "action 必须是 request 或 verify" }, { status: 400 });
  } catch (e) {
    return toResponse(e);
  }
}
