import { devPeekCode } from "@/lib/sender/sms";
import { devPeekEmailCode } from "@/lib/sender/devstore";
import { normalizePhone } from "@/lib/otp";

export const dynamic = "force-dynamic";

/** 仅预发：查最新验证码（生产被 assertProdSafety 保险丝挡死，这里再拦一道） */
export async function GET(req: Request): Promise<Response> {
  if (process.env.ALLOW_DEV_OTP_ENDPOINT !== "true") {
    return Response.json({ error: "not found" }, { status: 404 });
  }
  const url = new URL(req.url);
  const phoneRaw = url.searchParams.get("phone");
  const email = url.searchParams.get("email");
  if (phoneRaw) {
    const phone = normalizePhone(phoneRaw);
    const hit = phone ? devPeekCode(phone) : undefined;
    return Response.json(hit ?? { error: "该号码暂无验证码记录" });
  }
  if (email) {
    return Response.json(devPeekEmailCode(email) ?? { error: "该邮箱暂无验证码记录" });
  }
  return Response.json({ error: "带上 ?phone= 或 ?email=" }, { status: 400 });
}
