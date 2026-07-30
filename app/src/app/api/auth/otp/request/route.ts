import { requestSmsOtp, requestEmailOtp } from "@/lib/otp";
import { getSession, assertCsrf } from "@/lib/session";
import { toResponse, RateLimitError } from "@/lib/errors";

export const dynamic = "force-dynamic";

const MIN_MS = 400; // 等时延防号码枚举：存在与否耗时一致

export async function POST(req: Request): Promise<Response> {
  const t0 = Date.now();
  try {
    assertCsrf(req);
    const { phone } = (await req.json()) as { phone?: string };
    if (typeof phone !== "string" || !phone.trim()) {
      return Response.json({ error: "请输入手机号" }, { status: 400 });
    }
    const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "local";
    const acct = await requestSmsOtp(phone, ip);

    const s = await getSession();
    if (acct) {
      s.stage = "sms_sent";
      s.accountId = acct.id;
      s.amr = [];
      s.attempts = 0;
      s.iat = Date.now();
      await s.save();
      // 管理员的邮箱码在短信过了之后才发（见 verify 路由）
      void requestEmailOtp; // （占位说明：此处不发）
    }
    await pad(t0);
    // 无论号码是否存在，同一句响应
    return Response.json({ ok: true, message: "验证码已发出（如该号码已开通账号）" });
  } catch (e) {
    await pad(t0);
    if (e instanceof RateLimitError) return toResponse(e);
    // 内部错误也不暴露号码是否存在
    return toResponse(e);
  }
}

async function pad(t0: number): Promise<void> {
  const left = MIN_MS - (Date.now() - t0);
  if (left > 0) await new Promise((r) => setTimeout(r, left));
}
