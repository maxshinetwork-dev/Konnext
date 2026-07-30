// RLS 冒烟测试：证明「策略真的在咬」。每次部署后必跑（预发/生产同样）。
// 防的是最危险的静默失效：owner 连接绕过全部 RLS 而不报错。
import pg from "pg";

const url = process.env.DATABASE_URL;
if (!url) { console.error("缺 DATABASE_URL"); process.exit(1); }
const pool = new pg.Pool({ connectionString: url, max: 2 });

const fails = [];
const ok = (cond, label) => { if (!cond) fails.push(label); console.log(`${cond ? "✓" : "✗"} ${label}`); };

async function asRole(accountId, sql, params) {
  const c = await pool.connect();
  try {
    await c.query("BEGIN");
    await c.query("SET LOCAL ROLE konnext_app");
    await c.query("SELECT set_config('app.account_id', $1, true)", [accountId]);
    const r = await c.query(sql, params);
    await c.query("COMMIT");
    return r;
  } catch (e) {
    await c.query("ROLLBACK").catch(() => {});
    throw e;
  } finally { c.release(); }
}

try {
  // 0) konnext_app 角色必须存在
  const role = await pool.query("SELECT 1 FROM pg_roles WHERE rolname='konnext_app'");
  ok(role.rowCount === 1, "konnext_app 角色存在（db/deploy/10_app_role.sql 已跑）");

  // 1) 空身份 → project 0 行（RLS 在咬）
  const anon = await asRole("", "SELECT count(*)::int AS n FROM project");
  ok(anon.rows[0].n === 0, `空身份查 project = 0 行（实际 ${anon.rows[0].n}）`);

  // 2) 空身份 → eng_setting 0 行（v0_31 补的 RLS 在咬）
  const anonSet = await asRole("", "SELECT count(*)::int AS n FROM eng_setting");
  ok(anonSet.rows[0].n === 0, `空身份查 eng_setting = 0 行（实际 ${anonSet.rows[0].n}）`);

  // 3) owner 直连（不降权）→ 能看全部：说明降权是必须动作
  const owner = await pool.query("SELECT count(*)::int AS n FROM eng_setting");
  ok(owner.rows[0].n > 0, `owner 不降权可见 eng_setting（${owner.rows[0].n} 行）——业务代码必须走 withAccount`);

  // 4) 有核心管理员时：以其身份能读（策略放行正确方向）
  const admin = await pool.query(
    "SELECT id FROM app_account WHERE is_core_admin AND active LIMIT 1",
  );
  if (admin.rowCount === 1) {
    const seen = await asRole(admin.rows[0].id, "SELECT count(*)::int AS n FROM eng_setting");
    ok(seen.rows[0].n > 0, `核心管理员可读 eng_setting（${seen.rows[0].n} 行）`);
  } else {
    console.log("· 跳过管理员正向读（库里还没自举核心管理员）");
  }
} catch (e) {
  fails.push(`执行异常：${e.message}`);
  console.error(e);
} finally {
  await pool.end();
}

console.log("────────────");
if (fails.length) { console.error(`✗ RLS 冒烟失败 ${fails.length} 项`); process.exit(1); }
console.log("★ RLS 冒烟全部通过");
