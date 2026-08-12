#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把「办公管理平台原型」和「施工端 App 演示」合成一个可双击打开的 HTML。

用法：python3 docs/tools/生成单文件合集.py [输出路径]

★为什么用 iframe 而不是直接首尾相接：
  两份原型各有各的一整套 CSS 和全局函数，而且重名的不少 ——
  .card / .btn / .note / .hint / .pill / .row / .tabs / .mono 两边都有且长得不一样，
  say() / pick() 两边也都有。拼在一个文档里，后加载的那套会把前一套悄悄改掉：
  不报错，只是布局和行为错了 —— 正是最难发现的那类问题。
  塞进 iframe 各自是独立文档，样式和脚本互不串门。

★内容用 <script type="text/html"> 装着，打开哪个才灌进哪个 iframe（srcdoc）：
  灌过一次就不再灌，切回来时登录状态、填过的内容都还在。
  这种 script 块里唯一有意义的结束标记是 </script，所以嵌进去之前把它拆开，
  取出来时再拼回来。
"""
import sys, os, re

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # …/docs
PARTS = [
    ('ui',  '🏢 办公管理平台', os.path.join(BASE, 'KONNEXT_UI原型.html')),
    ('app', '📱 施工端 App',   os.path.join(BASE, 'KONNEXT_施工端App演示.html')),
]
DST = sys.argv[1] if len(sys.argv) > 1 else 'KONNEXT_原型合集_双击打开.html'

SHELL_HEAD = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>KONNEXT 原型合集 · 办公管理平台 + 施工端 App</title>
<style>
*{box-sizing:border-box}
html,body{margin:0;height:100%;overflow:hidden}
body{display:flex;flex-direction:column;background:#f5f7fa;color:#1f2933;
  font:13px/1.6 -apple-system,"PingFang SC","Microsoft YaHei","Noto Sans CJK SC",system-ui,sans-serif}
header{display:flex;align-items:center;gap:16px;padding:0 16px;height:46px;flex:0 0 46px;
  background:#fff;border-bottom:1px solid #d8e0e8}
.brand{font-size:15px;font-weight:600;letter-spacing:.04em;white-space:nowrap}
.brand span{color:#2563eb}
nav{display:flex;gap:2px}
nav button{border:0;background:none;padding:6px 14px;border-radius:6px;font:inherit;
  color:#5f6b76;cursor:pointer;white-space:nowrap}
nav button:hover{background:#eef2f6;color:#1f2933}
nav button.on{background:#eef2f6;color:#2563eb;font-weight:600}
.tip{margin-left:auto;font-size:11.5px;color:#5f6b76;white-space:nowrap;overflow:hidden;
  text-overflow:ellipsis}
main{flex:1;min-height:0;position:relative}
iframe{position:absolute;inset:0;width:100%;height:100%;border:0;background:#f5f7fa}
iframe[hidden]{display:none}
@media(max-width:640px){.tip{display:none}}
</style>
</head>
<body>
<header>
  <div class="brand">KON<span>NEXT</span> 原型</div>
  <nav id="nav"></nav>
  <div class="tip">离线单文件 · 不联网也能用 · 演示数据全是假的，随便点</div>
</header>
<main id="main"></main>
<noscript><p style="padding:20px">这份原型需要 JavaScript —— 请用 Chrome / Edge / Safari 打开。</p></noscript>
"""

SHELL_TAIL = """<script>
/* 取出来时把拆开的结束标记拼回去（嵌进去时拆的） */
function unesc(s){ return s.split('<\\\\/script').join('<'+'/script'); }
var loaded = {};
function show(k){
  PARTS.forEach(function(p){
    document.getElementById('f-'+p[0]).hidden = (p[0] !== k);
    document.getElementById('t-'+p[0]).className = (p[0] === k) ? 'on' : '';
  });
  if(!loaded[k]){                      /* ★只灌一次：切回来时登录状态和填过的内容都还在 */
    loaded[k] = true;
    document.getElementById('f-'+k).srcdoc =
      unesc(document.getElementById('src-'+k).textContent);
  }
}
PARTS.forEach(function(p){
  var b=document.createElement('button'); b.id='t-'+p[0]; b.textContent=p[1];
  b.onclick=function(){ show(p[0]); }; document.getElementById('nav').appendChild(b);
  var f=document.createElement('iframe'); f.id='f-'+p[0]; f.hidden=true;
  f.title=p[1]; document.getElementById('main').appendChild(f);
});
show(PARTS[0][0]);
</script>
</body>
</html>
"""


def main():
    out = [SHELL_HEAD]
    # 先声明有哪几块，壳脚本靠它建标签页和 iframe
    out.append('<script>var PARTS=[%s];</script>\n' %
               ','.join('["%s","%s"]' % (k, t) for k, t, _ in PARTS))

    for key, title, path in PARTS:
        with open(path, encoding='utf-8') as fh:
            html = fh.read()
        # 这种 script 块里唯一有意义的结束标记就是 </script，拆开它
        payload = html.replace('</script', '<\\/script')
        assert '</script' not in payload, '%s：还有没拆开的结束标记' % title
        assert len(payload) > 10000, '%s：内容太短，是不是读错文件了' % title
        out.append('<script type="text/html" id="src-%s">%s</script>\n' % (key, payload))
        print('  装入 %-16s %7d 字符  ← %s' % (title, len(html), os.path.basename(path)))

    out.append(SHELL_TAIL)
    doc = ''.join(out)

    # ★出门前自己检一遍：照浏览器的读法把每一块再取出来，必须和原文件一模一样。
    #   浏览器读 <script> 里的内容只认一个结束标记 —— 第一个 </script。
    #   要是哪块没拆干净，它会在半路断掉：文件照样打得开，只是那一块残缺 —— 不报错。
    #   所以这里不数标签个数（原文里本来就带着 <script> 开头标记，数了会误报），
    #   而是取出来跟原文比对。
    for key, title, path in PARTS:
        head = '<script type="text/html" id="src-%s">' % key
        start = doc.index(head) + len(head)
        got = doc[start: doc.index('</script>', start)].replace('<\\/script', '</script')
        want = open(path, encoding='utf-8').read()
        assert got == want, '%s：取出来的内容和原文对不上（少了 %d 字符）' % (
            title, len(want) - len(got))

    with open(DST, 'w', encoding='utf-8') as fh:
        fh.write(doc)
    print('✓ 已生成 %s（%.1f MB）' % (DST, os.path.getsize(DST) / 1048576))


if __name__ == '__main__':
    main()
