import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // pg 走 Node runtime；serverExternalPackages 防止打包器折腾原生依赖
  serverExternalPackages: ["pg"],
};

export default nextConfig;
