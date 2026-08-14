/* Flow 台账的回归。用法：node docs/tools/台账-smoke.js [文件路径]
   ★最要紧的一条：每个 Agent 都必须挂「验·X」徽章。
   铁律①说没有检查者的 Agent 不许上线 —— 那这条就得机器来数，
   靠眼睛扫一百多个节点，漏一个不会有任何提示。 */
const { chromium } = require('playwright');
const path = require('path');
const F = process.argv[2] || '/home/user/Konnext/docs/KONNEXT_Flow台账.html';

(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const fails = [], errs = [];
  const ok = (c, l) => { if (!c) fails.push(l); };

  for (const theme of ['light', 'dark']) {
    const p = await b.newPage({ viewport: { width: 1560, height: 1000 }, colorScheme: theme });
    p.on('pageerror', e => errs.push('[' + theme + '] ' + e.message));
    p.on('console', m => { if (m.type() === 'error') errs.push('[' + theme + '] ' + m.text()); });
    await p.goto('file://' + F);
    await p.waitForTimeout(600);

    const s = await p.evaluate(() => {
      const cards = [...document.querySelectorAll('.fc')];
      const bad = { noIn: [], noOut: [], noAgent: [], noVerify: [], noTable: [] };
      cards.forEach(c => {
        const id = c.querySelector('.fc-id').textContent;
        const humans = c.querySelectorAll('.chain .d-human');
        const ags = c.querySelectorAll('.chain .d-read,.chain .d-draft,.chain .d-write');
        if (humans.length < 2) (humans.length ? bad.noOut : bad.noIn).push(id);
        if (!ags.length) bad.noAgent.push(id);
        ags.forEach(a => { if (!a.querySelector('.vb')) bad.noVerify.push(id + '/' + a.textContent); });
        if (!c.querySelectorAll('.fc-tbl .tb').length) bad.noTable.push(id);
      });
      return {
        cards: cards.length,
        agents: document.querySelectorAll('.chain .d-read,.chain .d-draft,.chain .d-write').length,
        lines: document.querySelectorAll('.sec').length,
        loadRows: document.querySelectorAll('#loadtable tbody tr').length,
        tallies: document.querySelectorAll('.tally div').length,
        bad,
      };
    });

    ok(s.cards === 39, theme + ' Flow 卡应 39 张，实际 ' + s.cards);
    ok(s.lines === 8, theme + ' 主线分区应 8 个，实际 ' + s.lines);
    ok(s.tallies === 6, theme + ' 顶部统计应 6 项，实际 ' + s.tallies);
    ok(s.loadRows > 0, theme + ' 负荷表没渲染出来');
    ok(s.bad.noIn.length === 0, theme + ' ★缺人工入口: ' + s.bad.noIn.join(','));
    ok(s.bad.noOut.length === 0, theme + ' ★缺人工出口（没有人 check 就不是闭环）: ' + s.bad.noOut.join(','));
    ok(s.bad.noAgent.length === 0, theme + ' ★没有 Agent 的 Flow: ' + s.bad.noAgent.join(','));
    ok(s.bad.noVerify.length === 0, theme + ' ★有 Agent 没标检查者（违反铁律①）: ' + s.bad.noVerify.join(' | '));
    ok(s.bad.noTable.length === 0, theme + ' ★没标调用库的 Flow: ' + s.bad.noTable.join(','));

    // 主题：背景不能透明，文字不能和背景同色
    const col = await p.evaluate(() => {
      const g = getComputedStyle(document.body);
      return { bg: g.backgroundColor, ink: g.color };
    });
    ok(col.bg !== 'rgba(0, 0, 0, 0)', theme + ' body 背景透明 —— 会借用宿主底色');
    ok(col.bg !== col.ink, theme + ' 文字与背景同色');

    // 悬停出详情
    await p.locator('.chain .d-read').first().hover();
    await p.waitForTimeout(250);
    const tt = await p.evaluate(() => ({
      disp: getComputedStyle(document.getElementById('tip')).display,
      txt: document.getElementById('tip').innerText,
    }));
    ok(tt.disp === 'block', theme + ' 悬停没出提示');
    ok(/输入/.test(tt.txt) && /输出/.test(tt.txt) && /谁验它/.test(tt.txt),
      theme + ' 提示缺「输入/输出/谁验它」');

    // 过滤：点运维只剩运维
    await p.locator('#bar button', { hasText: '运维' }).click();
    await p.waitForTimeout(250);
    const vis = await p.evaluate(() =>
      [...document.querySelectorAll('.fc')].filter(c => c.offsetParent !== null)
        .map(c => c.querySelector('.fc-id').textContent));
    ok(vis.length > 0 && vis.every(v => v.startsWith('MT-')),
      theme + ' 过滤失灵，仍显示: ' + vis.slice(0, 5).join(','));
    await p.locator('#bar button', { hasText: '全部' }).click();
    await p.waitForTimeout(200);

    const ov = await p.evaluate(() => document.documentElement.scrollWidth > innerWidth + 2);
    ok(!ov, theme + ' 页面横向溢出');

    await p.screenshot({ path: path.join(__dirname, 'shot_台账_' + theme + '.png') });
    await p.close();
  }

  console.log('运行时报错: ' + errs.length); errs.slice(0, 6).forEach(e => console.log('  ! ' + e));
  console.log('断言失败: ' + fails.length); fails.forEach(f => console.log('  ✗ ' + f));
  console.log(errs.length || fails.length ? '★ 有问题' : '★ 台账冒烟全部通过（明暗两套主题）');
  await b.close();
  process.exit(errs.length || fails.length ? 1 : 0);
})();
