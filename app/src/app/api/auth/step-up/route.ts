import { resendSmsOtp, verifyOtp, OTP_FAIL_MSG } from "@/lib/otp";
import { getSession, assertCsrf, requireSession, STEPUP_MS } from "@/lib/session";
import { toResponse } from "@/lib/errors";

export const dynamic = "force-dynamic";

/**
 * 不可逆操作的二次验证（★用户 2026-08-03 定）。
 *
 * 为什么要这一步：定格类操作（SM 完成 / 确认交付 / 文档发放 / 标记请款 / 拒付停服）
 * 一点下去就回不来了。你没关的那台电脑万一被同事碰到，随手一点就是既成事实，
 * 而且日志会记成你本人做的。多问一次短信码，就把「随手」挡在门外。
 *
 * POST {action:'request'} → 往你自己手机补发一条码
 * POST {action:'verify', code} → 验过之后 5 分钟内的不可逆操作免再验
 */
export async function POST(req: Request): Promise<Response> {
  try {
    assertCsrf(req);
    const { accountId } = await requireSession();
    const body = (await req.json()) as { action?: string; code?: string };
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "local";

    if (body.action === "request") {
      await resendSmsOtp(accountId, ip);
      return Response.json({ ok: true, sent: "sms" });
    }

    if (body.action === "verify") {
      const ok = await verifyOtp(accountId, "sms", String(body.code ?? ""));
      if (!ok) return Response.json({ error: OTP_FAIL_MSG }, { status: 401 });
      const s = await getSession();
      s.stepUpAt = Date.now();
      s.seen = Date.now();
      await s.save();
      return Response.json({ ok: true, validForMs: STEPUP_MS });
    }

    return Response.json({ error: "action 必须是 request 或 verify" }, { status: 400 });
  } catch (e) {
    return toResponse(e);
  }
}
