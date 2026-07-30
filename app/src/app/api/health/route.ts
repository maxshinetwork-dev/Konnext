import { pool } from "@/lib/db";
import { toResponse } from "@/lib/errors";

export const dynamic = "force-dynamic";

export async function GET(): Promise<Response> {
  try {
    const r = await pool.query("SELECT 1 AS ok");
    return Response.json({ ok: r.rows[0]?.ok === 1, ts: new Date().toISOString() });
  } catch (e) {
    return toResponse(e);
  }
}
