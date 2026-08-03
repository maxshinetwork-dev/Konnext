import { verifyOtp, voidActiveCode, requestEmailOtp, OTP_FAIL_MSG } from "@/lib/otp";
import { getSession, assertCsrf } from "@/lib/session";
import { toResponse } from "@/lib/errors";
import { withAuthDb } from "@/lib/db";

export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<Response> {
  try {
    assertCsrf(req);
    const { code } = (await req.json()) as { code?: string };
    const s = await getSession();
    if (s.stage !== "sms_sent" || !s.accountId) {
      return Response.json({ error: "请先获取验证码" }, { status: 400 });
    }
    const ok = await verifyOtp(s.accountId, "sms", String(code ?? ""));
    if (!ok) {
      s.attempts = (s.attempts ?? 0) + 1;
      if (s.attempts >= 5) {
        await voidActiveCode(s.accountId, "sms");
        s.destroy();
        return Response.json(
          { error: "错误次数过多，验证码已作废，请重新获取" },
          { status: 401 },
        );
      }
      await s.save();
      return Response.json({ error: OTP_FAIL_MSG }, { status: 401 });
    }

    // 短信通过：查 tier 决定下一步
    const acct = await withAuthDb(async (q) => {
      const r = await q.query<{ tier: number; backend_access: boolean }>(
        "SELECT tier, backend_access FROM app_account WHERE id=$1 AND active",
        [s.accountId],
      );
      return r.rows[0] ?? null;
    });
    if (!acct) {
      s.destroy();
      return Response.json({ error: OTP_FAIL_MSG }, { status: 401 });
    }
    if (!acct.backend_access) {
      // 已证明持有该手机，明确提示（无枚举问题）
      s.destroy();
      return Response.json(
        { error: "该账号仅限施工 App 使用，不能进入后台" },
        { status: 403 },
      );
    }
    if (acct.tier === 1) {
      // 管理员：再走邮箱二验
      const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "local";
      await requestEmailOtp(s.accountId, ip);
      s.stage = "email_pending";
      s.amr = ["sms"];
      s.attempts = 0;
      await s.save();
      return Response.json({ ok: true, next: "email" });
    }
    s.stage = "full";
    s.amr = ["sms"];
    s.attempts = 0;
    s.seen = Date.now();          // 空闲 30 分钟锁屏的起点
    await s.save();
    return Response.json({ ok: true, next: "done" });
  } catch (e) {
    return toResponse(e);
  }
}
