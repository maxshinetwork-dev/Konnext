/** 邮箱验证码通道（管理员双重验证）：console | resend */
import { devStoreEmailCode } from "./devstore";

export async function sendEmail(to: string, subject: string, body: string, code?: string): Promise<void> {
  const t = process.env.EMAIL_TRANSPORT ?? "console";
  if (t === "resend") {
    const key = process.env.RESEND_API_KEY;
    if (!key) throw new Error("缺 RESEND_API_KEY");
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: "KONNEXT <noreply@konnext.com.au>",
        to: [to],
        subject,
        text: body,
      }),
    });
    if (!res.ok) throw new Error(`Resend 发送失败 HTTP ${res.status}`);
    return;
  }
  if (code) devStoreEmailCode(to, code);
  console.log(`[email:console] → ${to}｜${subject}｜${body}`);
}
