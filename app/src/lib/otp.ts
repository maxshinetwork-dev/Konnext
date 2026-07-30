import { createHmac, timingSafeEqual, randomInt } from "node:crypto";
import { withAuthDb, type Querier } from "./db";
import { AuthError, RateLimitError } from "./errors";
import { sendSms, transport } from "./sender/sms";
import { sendEmail } from "./sender/email";

/** 统一报错文案（UI 清单 A1：不区分「号码不存在」，防枚举员工号码） */
export const OTP_FAIL_MSG = "手机号或验证码不正确";

type Channel = "sms" | "email";

export type AccountLite = {
  id: string;
  full_name: string;
  tier: number;
  backend_access: boolean;
  email: string | null;
  phone: string;
  departments: string[];
};

/** 04xx / 614xx / +614xx → +614xxxxxxxx；非澳洲手机号返回 null */
export function normalizePhone(raw: string): string | null {
  const d = raw.replace(/[^\d+]/g, "");
  let n = d;
  if (n.startsWith("+")) n = n.slice(1);
  if (n.startsWith("0")) n = "61" + n.slice(1);
  if (!n.startsWith("61")) n = "61" + n;
  return /^614\d{8}$/.test(n) ? "+" + n : null;
}

function pepper(): string {
  const p = process.env.OTP_PEPPER;
  if (!p || p.length < 32) throw new Error("OTP_PEPPER 缺失或太短（>=32 字节）");
  return p;
}

export function hashCode(code: string): string {
  return createHmac("sha256", pepper()).update(code).digest("hex");
}

function genCode(): string {
  // fixed 模式固定 000000：预发演示用，行为与真发完全一致（照常散列落库）
  return transport() === "fixed" ? "000000" : String(randomInt(0, 1_000_000)).padStart(6, "0");
}

async function otpValidMinutes(q: Querier): Promise<number> {
  const r = await q.query<{ value_num: string | null }>(
    "SELECT value_num FROM eng_setting WHERE key='otp_valid_minutes'",
  );
  return Number(r.rows[0]?.value_num ?? 10);
}

/** 三层限速，全用 auth_otp 自身统计（未知号码也插 account_id=NULL 行参与 IP 计数） */
async function rateLimit(q: Querier, accountId: string | null, channel: Channel, ip: string) {
  if (accountId) {
    const again = await q.query<{ n: string }>(
      `SELECT count(*) AS n FROM auth_otp
        WHERE account_id=$1 AND channel=$2 AND purpose='login'
          AND created_at > now() - interval '60 seconds'`,
      [accountId, channel],
    );
    if (Number(again.rows[0]?.n ?? 0) > 0) throw new RateLimitError("发送太频繁，请 60 秒后再试");
    const hour = await q.query<{ n: string }>(
      `SELECT count(*) AS n FROM auth_otp
        WHERE account_id=$1 AND purpose='login' AND created_at > now() - interval '1 hour'`,
      [accountId],
    );
    if (Number(hour.rows[0]?.n ?? 0) >= 5) throw new RateLimitError("本小时发送次数已用完，请稍后再试");
  }
  const byIp = await q.query<{ n: string }>(
    `SELECT count(*) AS n FROM auth_otp
      WHERE ip=$1 AND created_at > now() - interval '1 hour'`,
    [ip],
  );
  if (Number(byIp.rows[0]?.n ?? 0) >= 10) throw new RateLimitError("发送太频繁，请稍后再试");
}

async function issue(
  q: Querier,
  acct: { id: string; sendTo: string },
  channel: Channel,
  ip: string,
): Promise<void> {
  await rateLimit(q, acct.id, channel, ip);
  const code = genCode();
  const mins = await otpValidMinutes(q);
  // 旧的未用码先作废（同账号同渠道只有最新一条有效）
  await q.query(
    `UPDATE auth_otp SET used_at=now()
      WHERE account_id=$1 AND channel=$2 AND purpose='login' AND used_at IS NULL`,
    [acct.id, channel],
  );
  await q.query(
    `INSERT INTO auth_otp(account_id, channel, sent_to, code_hash, purpose, expires_at, ip)
     VALUES ($1,$2,$3,$4,'login', now() + make_interval(mins => $5), $6)`,
    [acct.id, channel, acct.sendTo, hashCode(code), mins, ip],
  );
  if (channel === "sms") {
    await sendSms(acct.sendTo, `【KONNEXT】登录验证码 ${code}，${mins} 分钟内有效。请勿转发。`, code);
  } else {
    await sendEmail(acct.sendTo, "KONNEXT 管理员登录验证", `验证码 ${code}，${mins} 分钟内有效。`, code);
  }
}

/** 按手机号找活跃账号（带部门），查不到返回 null（外层做防枚举统一响应） */
export async function findAccountByPhone(q: Querier, phone: string): Promise<AccountLite | null> {
  const r = await q.query<AccountLite & { departments: string[] | null }>(
    `SELECT a.id, a.full_name, a.tier, a.backend_access, a.email, a.phone,
            COALESCE(array_agg(ad.department) FILTER (WHERE ad.department IS NOT NULL), '{}') AS departments
       FROM app_account a
       LEFT JOIN account_department ad ON ad.account_id = a.id
      WHERE a.phone = $1 AND a.active
      GROUP BY a.id`,
    [phone],
  );
  const row = r.rows[0];
  return row ? { ...row, departments: row.departments ?? [] } : null;
}

/** 请求短信码。无论号码是否存在都同样返回（等时延由外层统一 sleep 保证） */
export async function requestSmsOtp(phoneRaw: string, ip: string): Promise<AccountLite | null> {
  const phone = normalizePhone(phoneRaw);
  if (!phone) return null;
  return withAuthDb(async (q) => {
    const acct = await findAccountByPhone(q, phone);
    if (!acct) {
      // 未知号码也记一行参与 IP 限速（account_id 为 NULL）
      await rateLimit(q, null, "sms", ip);
      await q.query(
        `INSERT INTO auth_otp(account_id, channel, sent_to, code_hash, purpose, expires_at, ip)
         VALUES (NULL,'sms',$1,'unknown-number','login', now(), $2)`,
        [phone, ip],
      );
      return null;
    }
    await issue(q, { id: acct.id, sendTo: acct.phone }, "sms", ip);
    return acct;
  });
}

/** 管理员第二步：发邮箱码 */
export async function requestEmailOtp(accountId: string, ip: string): Promise<void> {
  await withAuthDb(async (q) => {
    const r = await q.query<{ email: string | null }>(
      "SELECT email FROM app_account WHERE id=$1 AND active",
      [accountId],
    );
    const email = r.rows[0]?.email;
    if (!email) throw new AuthError("管理员账号缺少邮箱，请联系核心管理员", 403);
    await issue(q, { id: accountId, sendTo: email }, "email", ip);
  });
}

/** 校验：取该账号该渠道最新一条，比散列 + 过期 + 用过即失效 */
export async function verifyOtp(
  accountId: string,
  channel: Channel,
  code: string,
): Promise<boolean> {
  if (!/^\d{6}$/.test(code)) return false;
  return withAuthDb(async (q) => {
    const r = await q.query<{ id: string; code_hash: string; ok: boolean }>(
      `SELECT id, code_hash, (used_at IS NULL AND expires_at > now()) AS ok
         FROM auth_otp
        WHERE account_id=$1 AND channel=$2 AND purpose='login'
        ORDER BY created_at DESC LIMIT 1`,
      [accountId, channel],
    );
    const row = r.rows[0];
    if (!row || !row.ok) return false;
    const a = Buffer.from(row.code_hash, "utf8");
    const b = Buffer.from(hashCode(code), "utf8");
    if (a.length !== b.length || !timingSafeEqual(a, b)) return false;
    await q.query("UPDATE auth_otp SET used_at=now() WHERE id=$1", [row.id]);
    return true;
  });
}

/** 错满 5 次：作废当前未用码 */
export async function voidActiveCode(accountId: string, channel: Channel): Promise<void> {
  await withAuthDb((q) =>
    q.query(
      `UPDATE auth_otp SET used_at=now()
        WHERE account_id=$1 AND channel=$2 AND purpose='login' AND used_at IS NULL`,
      [accountId, channel],
    ),
  );
}
