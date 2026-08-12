/* 单文件合集的回归：照同事的用法走一遍 —— 双击打开（file://），切标签，两边都点一下。
   用法：node docs/tools/合集-smoke.js [合集文件路径]
   ★重点验三件事：
     ① 两块内容真的都渲染出来了（srcdoc 在 file:// 下没被挡）
     ② 两块的样式互不串门（同名 class 在两个文档里各是各的）
     ③ 切来切去不丢状态（登录完切走再切回来，还是登录着的） */
const { chromium } = require('playwright');
const FILE = process.argv[2] ||
  '/tmp/claude-0/-home-user-Konnext/79bb5524-3e27-53e0-ab85-4550be6905d7/scratchpad/KONNEXT_原型合集_双击打开.html';

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  const errs = [];
  p.on('pageerror', e => errs.push('[页面] ' + e.message));
  p.on('console', m => { if (m.type() === 'error') errs.push('[控制台] ' + m.text()); });

  const fails = [];
  const ok = (c, l) => { if (!c) fails.push(l); };

  await p.goto('file://' + FILE);
  await p.waitForTimeout(900);

  // ── ① 外壳 ──
  const tabs = await p.$$eval('#nav button', bs => bs.map(x => x.textContent.trim()));
  ok(tabs.length === 2, '外壳：应该有两个标签，实际 ' + tabs.length);
  ok(tabs.some(t => t.includes('办公管理平台')), '外壳：缺「办公管理平台」标签');
  ok(tabs.some(t => t.includes('施工端 App')), '外壳：缺「施工端 App」标签');

  // ── ② 办公端：默认就该显示出来 ──
  const ui = p.frameLocator('#f-ui');
  ok(await ui.locator('.login-card').isVisible(), '办公端：登录卡没渲染出来（srcdoc 被挡？）');
  // 演示身份在第二步（先要「获取验证码」），不是一进来就摆在那儿
  await ui.locator('button', { hasText: '获取验证码' }).click();
  await p.waitForTimeout(300);
  const roles = await ui.locator('.demo-pick button').allTextContents();
  ok(roles.length === 6, '办公端：演示身份应该 6 个，实际 ' + roles.length);

  // 真的登进去，别只看登录页
  await ui.locator('.demo-pick button', { hasText: '陈总' }).click();
  await p.waitForTimeout(600);
  ok(await ui.locator('#app').isVisible(), '办公端：点了陈总没进主界面');
  const deptTabs = await ui.locator('#tabs .tab').count();
  ok(deptTabs >= 6, '办公端：顶部部门标签应 ≥6，实际 ' + deptTabs);

  // ── ③ 切到施工端 App ──
  await p.click('#t-app');
  await p.waitForTimeout(900);
  ok(await p.locator('#f-app').isVisible(), '切换：App 的 iframe 没显示');
  ok(await p.locator('#f-ui').isHidden(), '切换：办公端应该藏起来');

  const app = p.frameLocator('#f-app');
  ok(await app.locator('.phone').isVisible(), '施工端：手机框没渲染出来');
  await app.locator('button', { hasText: '获取验证码' }).click();
  await app.locator('button', { hasText: '进入（演示）' }).click();
  await p.waitForTimeout(400);

  // ★一个地址＝一个框：三个地址三个框，同一地址不许出现在两个框里
  const cards = await app.locator('#today-list .card').evaluateAll(
    els => els.map(e => e.dataset.addr));
  ok(cards.length === 3, '施工端：今日任务应合并成 3 个框，实际 ' + cards.length);
  ok(new Set(cards).size === cards.length,
    '施工端：同一个地址出现在多个框里 → ' + cards.join(' / '));

  // ── ④ 样式没串门：两边同名 class 各是各的 ──
  //    .card 办公端是白底，施工端手机屏里也是白底但圆角不同；
  //    真正能一句话说清的是 body 背景 —— 两份原型定的不是一个色。
  const uiBg = await ui.locator('body').evaluate(e => getComputedStyle(e).backgroundColor);
  const appBg = await app.locator('body').evaluate(e => getComputedStyle(e).backgroundColor);
  ok(uiBg !== appBg, '样式串门了：两边 body 背景色变成一样的（' + uiBg + '）');

  // ── ⑤ 切回来不丢状态 ──
  await p.click('#t-ui');
  await p.waitForTimeout(500);
  ok(await ui.locator('#app').isVisible(), '★切回办公端掉登录了 —— 同事填一半切走就白填');
  ok(await ui.locator('#login').isHidden(), '★切回办公端又回到登录页了');

  console.log('标签数: ' + tabs.length);
  console.log('运行时报错: ' + errs.length);
  errs.slice(0, 10).forEach(e => console.log('  ! ' + e));
  console.log('断言失败: ' + fails.length);
  fails.forEach(f => console.log('  ✗ ' + f));
  console.log(errs.length || fails.length ? '★ 有问题，别发' : '★ 合集冒烟全部通过');
  await b.close();
  process.exit(errs.length || fails.length ? 1 : 0);
})();
