import { verifyOtp, voidActiveCode, OTP_FAIL_MSG } from "@/lib/otp";
import { getSession, assertCsrf } from "@/lib/session";
import { toResponse } from "@/lib/errors";

export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<Response> {
  try {
    assertCsrf(req);
    const { code } = (await req.json()) as { code?: string };
    const s = await getSession();
    if (s.stage !== "email_pending" || !s.accountId) {
      return Response.json({ error: "请先完成短信验证" }, { status: 400 });
    }
    const ok = await verifyOtp(s.accountId, "email", String(code ?? ""));
    if (!ok) {
      s.attempts = (s.attempts ?? 0) + 1;
      if (s.attempts >= 5) {
        await voidActiveCode(s.accountId, "email");
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
    s.amr = ["sms", "email"];
    s.attempts = 0;
    await s.save();
    return Response.json({ ok: true, next: "done" });
  } catch (e) {
    return toResponse(e);
  }
}
