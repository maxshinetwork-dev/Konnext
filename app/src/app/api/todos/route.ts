import { requireSession } from "@/lib/session";
import { withAccount } from "@/lib/db";
import { toResponse } from "@/lib/errors";

export const dynamic = "force-dynamic";

/** 待办中心（全局抽屉唯一数据源）：v_pending_handoff，超期在上 */
export async function GET(): Promise<Response> {
  try {
    const { accountId } = await requireSession();
    const rows = await withAccount(accountId, async (q) =>
      (
        await q.query(
          `SELECT * FROM v_pending_handoff
            ORDER BY overdue DESC, waiting_hours DESC`,
        )
      ).rows,
    );
    return Response.json(rows);
  } catch (e) {
    return toResponse(e);
  }
}
