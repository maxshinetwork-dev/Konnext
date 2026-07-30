/** dev 模式明文码暂存（仅内存，供 /api/dev/otp 查询；生产被保险丝挡死）
 *  ★挂 globalThis：Next.js dev 下每条路由是独立模块实例，模块级 Map 不共享 */
type CodeHit = { code: string; at: number };
declare global {
  var __konnextDevEmailCodes: Map<string, CodeHit> | undefined;
  var __konnextDevSmsCodes: Map<string, CodeHit> | undefined;
}
const emailCodes = (globalThis.__konnextDevEmailCodes ??= new Map<string, CodeHit>());
const smsCodes = (globalThis.__konnextDevSmsCodes ??= new Map<string, CodeHit>());

export function devStoreEmailCode(to: string, code: string): void {
  emailCodes.set(to, { code, at: Date.now() });
}
export function devPeekEmailCode(to: string): CodeHit | undefined {
  return emailCodes.get(to);
}
export function devStoreSmsCode(to: string, code: string): void {
  smsCodes.set(to, { code, at: Date.now() });
}
export function devPeekSmsCode(to: string): CodeHit | undefined {
  return smsCodes.get(to);
}
