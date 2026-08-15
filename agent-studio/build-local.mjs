/* ──────────────────────────────────────────────────────────────
   把 docs/原型_v1.html 包成可以双击打开的完整 HTML

     node build-local.mjs

   两个文件的区别只有外壳：
     docs/原型_v1.html   片段格式，发布成在线 Artifact 用（不带 <html> 外壳）
     Agent编排台.html     完整文档，本地双击打开用
   页面内容、样式、脚本完全同一份，只在这里改外壳。
   ────────────────────────────────────────────────────────────── */
import { readFileSync, writeFileSync } from 'node:fs';

const SRC = new URL('./docs/原型_v1.html', import.meta.url);
const OUT = new URL('./Agent编排台.html', import.meta.url);

const src = readFileSync(SRC, 'utf8');

/* 第一个 <div 之前是 <title> 和 <style>，放进 <head>；其余放进 <body> */
const cut = src.indexOf('<div id="login">');
if (cut < 0) throw new Error('没找到 <div id="login">，源文件结构变了');
const head = src.slice(0, cut).trimEnd();
const body = src.slice(cut).trimEnd();

const favicon = 'data:image/svg+xml,' + encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">' +
  '<rect width="64" height="64" rx="14" fill="#0A0E15"/>' +
  '<circle cx="20" cy="22" r="7" fill="#2DD4BF"/>' +
  '<circle cx="44" cy="22" r="7" fill="#FBBF24"/>' +
  '<circle cx="32" cy="44" r="7" fill="#7C8CFF"/>' +
  '<path d="M20 22 32 44 44 22" stroke="#3A4B66" stroke-width="3" fill="none"/>' +
  '</svg>');

writeFileSync(OUT, `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="dark">
<link rel="icon" href="${favicon}">
${head}
</head>
<body>
${body}
</body>
</html>
`);

console.log('已生成 Agent编排台.html');
