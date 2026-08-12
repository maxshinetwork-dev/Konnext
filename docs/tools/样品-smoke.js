/* 本地样品版的回归：★照【拿不到链接、只能双击文件】的同事的用法走。
   用法：node docs/tools/样品-smoke.js <样品目录>

   ★这里只验一件事，但它是同事能不能开始试用的全部：
     打开文件，【不点任何别的东西】，能不能一下就进去。
     以前的回归都是先 click('获取验证码') 再点身份 —— 测试自己把门打开了，
     所以门锁着也照样绿。这次的断言明确禁止那一步。 */
const { chromium } = require('playwright');
const DIR = process.argv[2];
if (!DIR) { console.error('要给样品目录'); process.exit(2); }

const ROLES = [['陈总', 'decision'], ['小林', 'presales'], ['王姐', 'fin'],
               ['老张', 'proc'], ['小周', 'mt'], ['陈工', 'eng']];

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const fails = [], errs = [];
  const ok = (c, l) => { if (!c) fails.push(l); };
  const newPage = async (file, vp) => {
    const p = await b.newPage({ viewport: vp });
    p.on('pageerror', e => errs.push('[' + file + '] ' + e.message));
    p.on('console', m => { if (m.type() === 'error') errs.push('[' + file + '] ' + m.text()); });
    await p.goto('file://' + DIR + '/' + file);
    await p.waitForTimeout(500);
    return p;
  };

  // ── 办公端样品：六个身份，每个都要能一键进 ──
  const F1 = 'KONNEXT_办公管理平台_样品.html';
  {
    const p = await newPage(F1, { width: 1440, height: 900 });
    const shown = await p.locator('.demo-pick button').count();
    ok(shown === 6, '办公端：一打开就该看见 6 个身份按钮，实际看见 ' + shown +
      ' —— 同事会卡在登录页');
    await p.close();
  }
  for (const [who, dept] of ROLES) {
    const p = await newPage(F1, { width: 1440, height: 900 });
    // ★故意不点「获取验证码」：同事不该需要先猜出那一步
    const btn = p.locator('.demo-pick button', { hasText: who });
    if (!await btn.isVisible()) { fails.push('办公端：' + who + ' 一打开看不见'); await p.close(); continue; }
    await btn.click();
    await p.waitForTimeout(600);
    const st = await p.evaluate(() => ({
      inApp: getComputedStyle(document.getElementById('app')).display !== 'none',
      tab: typeof tab === 'undefined' ? null : tab,
      pages: document.querySelectorAll('.side-item').length,
    }));
    ok(st.inApp, '办公端：' + who + ' 点了进不去');
    ok(st.tab === dept, '办公端：' + who + ' 应落在 ' + dept + '，实际 ' + st.tab);
    ok(st.pages > 0, '办公端：' + who + ' 进去了但左栏是空的');
    await p.close();
  }

  // ── 施工端样品：一键进今日任务 ──
  const F2 = 'KONNEXT_施工端App_样品.html';
  {
    const p = await newPage(F2, { width: 430, height: 900 });
    const btn = p.locator('button', { hasText: '直接进入' });
    ok(await btn.isVisible(), '施工端：一打开就该有「直接进入」按钮');
    await btn.click();
    await p.waitForTimeout(400);
    const st = await p.evaluate(() => ({
      today: document.getElementById('s-today').classList.contains('on'),
      cards: [...document.querySelectorAll('#today-list .card')].map(e => e.dataset.addr),
    }));
    ok(st.today, '施工端：点了没进今日任务');
    ok(st.cards.length === 3, '施工端：今日任务应 3 个地址框，实际 ' + st.cards.length);
    ok(new Set(st.cards).size === st.cards.length, '施工端：同一地址出现在多个框里');
    await p.close();
  }

  console.log('运行时报错: ' + errs.length);
  errs.slice(0, 8).forEach(e => console.log('  ! ' + e));
  console.log('断言失败: ' + fails.length);
  fails.forEach(f => console.log('  ✗ ' + f));
  console.log(errs.length || fails.length ? '★ 有问题，别发' : '★ 样品冒烟全部通过（六身份 + App 均可一键进入）');
  await b.close();
  process.exit(errs.length || fails.length ? 1 : 0);
})();
