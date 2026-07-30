/** 门禁/乐观锁报错：契约里的完整中文句，必须原样给到前端（HTTP 409） */
export class GateError extends Error {
  readonly kind = "gate" as const;
}

/** 认证/权限类：401 未登录、403 无权 */
export class AuthError extends Error {
  constructor(
    message: string,
    readonly status: 401 | 403 = 401,
  ) {
    super(message);
  }
}

/** 限速：429 */
export class RateLimitError extends Error {}

/** 统一出口：路由 catch 里调它，绝不出现「操作失败，请重试」 */
export function toResponse(e: unknown): Response {
  if (e instanceof GateError) {
    return Response.json({ error: e.message }, { status: 409 });
  }
  if (e instanceof AuthError) {
    return Response.json({ error: e.message }, { status: e.status });
  }
  if (e instanceof RateLimitError) {
    return Response.json({ error: e.message }, { status: 429 });
  }
  console.error("[konnext] 系统错误：", e);
  return Response.json({ error: "系统错误，请联系管理员" }, { status: 500 });
}
