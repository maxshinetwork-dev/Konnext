import { getSession, assertCsrf } from "@/lib/session";
import { toResponse } from "@/lib/errors";

export const dynamic = "force-dynamic";

export async function POST(req: Request): Promise<Response> {
  try {
    assertCsrf(req);
    const s = await getSession();
    s.destroy();
    return Response.json({ ok: true });
  } catch (e) {
    return toResponse(e);
  }
}
