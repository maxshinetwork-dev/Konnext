#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从两份原型生成【本地样品版】—— 给只能本地打开、拿不到链接的同事试用。

用法：python3 docs/tools/生成本地样品.py [输出目录]

★要解决的问题：原型的登录是「手机号 + 短信验证码」。
  样品里没有 Twilio，短信永远不会到 —— 同事打开就卡在门口，
  而且他不会知道是没接短信还是文件坏了，只会回你一句「登录不了」。
  演示身份按钮本来藏在「获取验证码」后面一步，等于藏在他进不去的门后面。

★改法：把身份选择提到最前面，一打开就能点进去；
  原来的短信登录留在下面并写明「样品里不发短信」——
  它是正式版的样子，同事该看见，只是不能挡着路。

★只改样品副本，两份原型本体一个字都不动。
"""
import sys, os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # …/docs
OUT = sys.argv[1] if len(sys.argv) > 1 else '.'

ROLES = [('admin', '陈总 · 核心管理员'), ('presales', '小林 · 售前'),
         ('finance', '王姐 · 财务'), ('warehouse', '老张 · 采购＋库管'),
         ('maintenance', '小周 · 运维'), ('eng', '陈工 · 工程管理')]

# ── 办公端：把身份选择插到登录卡最上面 ──────────────────────────
UI_ANCHOR = """    <div id="step-phone">
      <div class="field">
        <label>手机号</label>"""

UI_PATCH = """    <div class="note" style="margin:0 0 18px;border-left-color:#047857;
      background:rgba(4,120,87,.08);color:#1f2933;font-size:13px;line-height:1.8">
      <b style="font-size:14px">▶ 试用样品 · 选一个身份直接进</b><br>
      <span style="color:#5f6b76">六个部门看到的界面不一样 ——
      点你自己那个角色，看到的就是你以后每天用的那一套。</span>
      <div class="demo-pick" style="margin-top:10px">
%s
      </div>
    </div>

    <div id="step-phone">
      <div class="field">
        <label>手机号 <span style="color:#5f6b76">（正式版的登录方式 ·
          样品里不发短信，验证码已预填，点「登录」也能进）</span></label>""" % (
    '\n'.join('        <button class="btn" onclick="loginAs(\'%s\')">%s</button>' % r
              for r in ROLES))

# ── 施工端 App：同样把「进去」提到最前面 ──────────────────────
APP_ANCHOR = """      <input type="text" value="0455 002 331" readonly style="text-align:center;font-size:16px" aria-label="手机号">
      <button class="btn" onclick="document.getElementById('otp').style.display='block'">获取验证码</button>"""

APP_PATCH = """      <button class="btn ok" style="margin-bottom:22px" onclick="appGo('today')">▶ 试用样品 · 直接进入</button>
      <p class="hint" style="margin:0 0 22px">底部四个标签都能切，勾选、打卡、签字都能试</p>
      <div style="border-top:1px solid var(--border);padding-top:18px">
        <p class="hint" style="margin:0 0 8px">正式版这样登录（样品里不发短信）</p>
        <input type="text" value="0455 002 331" readonly style="text-align:center;font-size:16px" aria-label="手机号">
        <button class="btn sec" onclick="document.getElementById('otp').style.display='block'">获取验证码</button>
      </div>"""

# 身份选择已经提到最前面了，第二步里那份重复的要拿掉 ——
# 同一个页面上两排一模一样的身份按钮，同事只会愣住：这两排有什么区别？
UI_DUP_ANCHOR = """      <div class="note">
        <b>原型演示：直接选一个身份进入</b>，看同一套界面在不同权限下的差别
        <div class="demo-pick">
%s
        </div>
      </div>""" % '\n'.join(
    '          <button class="btn" onclick="loginAs(\'%s\')">%s</button>' % r for r in ROLES)

UI_DUP_PATCH = """      <div class="note">
        样品里验证码不校验，点「登录」就进（进去是王姐·财务）——
        要换身份用上面那排，或者进去之后用右上角的下拉切。
      </div>"""

JOBS = [
    ('KONNEXT_办公管理平台_样品.html', 'KONNEXT_UI原型.html',
     [(UI_ANCHOR, UI_PATCH), (UI_DUP_ANCHOR, UI_DUP_PATCH)]),
    ('KONNEXT_施工端App_样品.html', 'KONNEXT_施工端App演示.html',
     [(APP_ANCHOR, APP_PATCH)]),
]


def main():
    for dst, src, patches in JOBS:
        path = os.path.join(BASE, src)
        out = open(path, encoding='utf-8').read()
        for anchor, patch in patches:
            # 锚点必须唯一：原型改版后锚点若失效，这里当场报错，
            # 而不是悄悄生成一份「登录还是进不去」的样品
            n = out.count(anchor)
            assert n == 1, '%s：锚点命中 %d 次（应为 1），原型登录段落改过了？\n%s' % (
                src, n, anchor[:80])
            out = out.replace(anchor, patch, 1)
        # 样品里身份按钮只许有一排
        assert out.count('class="demo-pick"') <= 1, '%s：身份按钮出现了不止一排' % src
        full = os.path.join(OUT, dst)
        open(full, 'w', encoding='utf-8').write(out)
        print('  ✓ %-34s %7.1f KB' % (dst, os.path.getsize(full) / 1024))


if __name__ == '__main__':
    main()
