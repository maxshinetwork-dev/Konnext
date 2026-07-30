import { Pool, type PoolClient, DatabaseError } from "pg";
import { GateError } from "./errors";

/**
 * 数据访问层 —— 本文件是全应用唯一允许触碰数据库的地方。
 *
 * 铁律（见 CLAUDE.md「绝对不能做的事」与部署方案）：
 * 1. 业务请求一律走 withAccount()：事务内 SET LOCAL ROLE konnext_app 降权
 *    （owner 连接会静默绕过全部 RLS），再 set_config 注入身份。
 * 2. 身份注入必须是事务级（set_config(..., true)）——Supabase 事务池
 *    (Supavisor 6543) 会吞会话级 SET，轻则丢身份重则串号。
 * 3. 只查视图、只调函数；门禁报错(P0001)原样透传，不包装。
 */

declare global {
  // 开发模式热重载不重复建池
  var __konnextPool: Pool | undefined;
}

function makePool(): Pool {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("缺 DATABASE_URL 环境变量（见 .env.example）");
  return new Pool({
    connectionString: url,
    max: 5, // Vercel 每实例小池；连接数大头交给 Supavisor
    idleTimeoutMillis: 30_000,
    // 禁用具名 prepared statement 由调用侧保证：不传 name 即匿名语句
  });
}

export const pool: Pool = global.__konnextPool ?? (global.__konnextPool = makePool());

export type Querier = {
  query<T = Record<string, unknown>>(
    sql: string,
    params?: unknown[],
  ): Promise<{ rows: T[]; rowCount: number | null }>;
};

function wrap(c: PoolClient): Querier {
  return {
    async query(sql, params) {
      const r = await c.query(sql, params as unknown[] | undefined);
      return { rows: r.rows, rowCount: r.rowCount };
    },
  };
}

/** 把 PG 错误翻译成应用错误：P0001(门禁/乐观锁) → 原句透传 */
function translate(e: unknown): unknown {
  if (e instanceof DatabaseError && e.code === "P0001") {
    return new GateError(e.message);
  }
  return e;
}

/**
 * 业务请求入口：降权 + 注入身份 + 单事务。
 * accountId 必须来自服务器验证过的会话 cookie —— 绝不接受请求体里的身份。
 */
export async function withAccount<T>(
  accountId: string,
  fn: (q: Querier) => Promise<T>,
): Promise<T> {
  const c = await pool.connect();
  try {
    await c.query("BEGIN");
    await c.query("SET LOCAL ROLE konnext_app");
    await c.query("SELECT set_config('app.account_id', $1, true)", [accountId]);
    await c.query("SELECT set_config('app.actor', $1, true)", [accountId]);
    const out = await fn(wrap(c));
    await c.query("COMMIT");
    return out;
  } catch (e) {
    await c.query("ROLLBACK").catch(() => {});
    throw translate(e);
  } finally {
    c.release();
  }
}

/**
 * 认证面专用（不降权、无身份）：登录前查号、写 auth_otp。
 * ★只允许 src/lib/otp.ts 与 /api/auth/* 使用 —— 语句面积小且固定。
 */
export async function withAuthDb<T>(fn: (q: Querier) => Promise<T>): Promise<T> {
  const c = await pool.connect();
  try {
    await c.query("BEGIN");
    const out = await fn(wrap(c));
    await c.query("COMMIT");
    return out;
  } catch (e) {
    await c.query("ROLLBACK").catch(() => {});
    throw translate(e);
  } finally {
    c.release();
  }
}
