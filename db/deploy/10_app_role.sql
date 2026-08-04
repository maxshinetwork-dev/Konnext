-- =====================================================================
--  konnext_app：应用层降权角色（每个库都要跑一次，本地与 Supabase 同样）
--
--  为什么必须有它：契约没有 FORCE ROW LEVEL SECURITY，表 owner 连接
--  会静默绕过全部 RLS 策略（不报错、数字不设防）。应用的每个业务请求
--  都要在事务内 SET LOCAL ROLE konnext_app，让 132+ 条策略真正生效。
--  只有 /api/auth/*（登录前查号、写验证码）白名单走 owner。
-- =====================================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='konnext_app') THEN
    CREATE ROLE konnext_app NOLOGIN;
  END IF;
END $$;

-- 允许连接用户切换到它（Supabase 上 owner 是 postgres；本地是建库用户）
GRANT konnext_app TO CURRENT_USER;

GRANT USAGE ON SCHEMA public TO konnext_app;
-- 行级权限由 RLS 决定；表级先放开（视图全是 security_invoker，
-- 调用者必须直接持有基表权限，再由策略按行过滤）
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO konnext_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO konnext_app;
-- 契约里新建表/序列时自动带上（以 owner 身份跑契约后再跑本脚本则无需）
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO konnext_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO konnext_app;

-- ★v0.36：验证码表连表级权限都收回（上面那句 GRANT ON ALL TABLES 会把它也放开）。
--   auth_otp 只由 /api/auth/*（登录前查号、写验证码）以 owner 身份读写。
--   为什么要单独一刀：契约里它已经开了 RLS 且不建任何策略（行级全拒），
--   这里再收表级权限——两道都关才叫纵深。任何业务代码都不该出现 auth_otp 这个词。
REVOKE ALL ON auth_otp FROM konnext_app;
