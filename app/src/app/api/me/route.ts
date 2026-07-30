import { requireSession } from "@/lib/session";
import { withAccount } from "@/lib/db";
import { toResponse } from "@/lib/errors";

export const dynamic = "force-dynamic";

/** 全局壳的数据源：我是谁、有哪些页标、各页标待办角标、能写哪些表 */
export async function GET(): Promise<Response> {
  try {
    const { accountId, view } = await requireSession();
    const data = await withAccount(accountId, async (q) => {
      const me = (
        await q.query(
          `SELECT id, login_name, full_name, tier, is_core_admin
             FROM app_account WHERE id = $1`,
          [accountId],
        )
      ).rows[0];
      const depts = (
        await q.query<{ department: string }>(
          "SELECT department FROM account_department WHERE account_id = $1",
          [accountId],
        )
      ).rows.map((r) => r.department);
      // v_dept_workload 是中文列名（契约如此）——必须双引号
      const workload = (
        await q.query<Record<string, unknown>>(
          `SELECT "部门" AS dept_cn, "待办总数" AS total, "已超期" AS overdue
             FROM v_dept_workload`,
        )
      ).rows;
      const permissions = (
        await q.query(
          "SELECT table_name, can_write FROM v_my_permissions",
        )
      ).rows;
      return { me, depts, workload, permissions };
    });
    return Response.json({ ...data, view: view ?? null });
  } catch (e) {
    return toResponse(e);
  }
}
