import { requireSession, assertCsrf } from "@/lib/session";
import { withAccount } from "@/lib/db";
import { toResponse } from "@/lib/errors";

export const dynamic = "force-dynamic";

/** 「已知悉」：回写 dept_handoff.acknowledged_at/by（操作者=会话账号） */
export async function POST(
  req: Request,
  ctx: { params: Promise<{ id: string }> },
): Promise<Response> {
  try {
    assertCsrf(req);
    const { accountId } = await requireSession();
    const { id } = await ctx.params;
    const row = await withAccount(accountId, async (q) => {
      const r = await q.query(
        `UPDATE dept_handoff
            SET acknowledged_at = now(), acknowledged_by = $2
          WHERE id = $1 AND acknowledged_at IS NULL
          RETURNING id, acknowledged_at`,
        [id, accountId],
      );
      return r.rows[0] ?? null;
    });
    if (!row) {
      return Response.json({ error: "该待办不存在或已被确认" }, { status: 404 });
    }
    return Response.json({ ok: true, ...row });
  } catch (e) {
    return toResponse(e);
  }
}
