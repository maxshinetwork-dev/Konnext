const { chromium } = require('playwright');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const p=await b.newPage({viewport:{width:430,height:900}});
  const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  p.on('console',m=>{if(m.type()==='error')errs.push(m.text())});
  await p.goto(process.argv[2]?('file://'+process.argv[2]):'file:///home/user/Konnext/docs/KONNEXT_施工端App演示.html');
  const fails=[];
  const ok=(c,l)=>{ if(!c) fails.push(l); };
  const screens=['today','punch','install','report','sm','exp','mt','mat','me'];
  const second=['install','sm','exp','mt','mat'];        // 从「今日」点进来的二级屏
  const main  =['today','punch','report','me'];          // 底部 tab 的四个主屏
  for(const s of screens){
    const r=await p.evaluate(id=>{
      appGo(id);
      const el=document.getElementById('s-'+id);
      const top=el.querySelector('.top');
      const back=top&&top.querySelector('.back');
      const tabs=[...el.querySelectorAll('.tabs button')];
      return {shown:el.classList.contains('on'),
              hasBack:!!back,
              backIsFirst:!!(back&&top.firstElementChild===back),
              backGoesToday:!!(back&&/appGo\('today'\)/.test(back.getAttribute('onclick')||'')),
              tabN:tabs.length,
              onTabs:tabs.filter(t=>t.classList.contains('on')).map(t=>t.textContent.trim())};
    },s);
    ok(r.shown, s+'：切不过去');
    ok(r.tabN===4, s+'：底部四个 tab 不全');
    if(second.includes(s)){
      ok(r.hasBack, '★'+s+'：左上角没有返回箭头（用户 2026-08-12 提的就是这个）');
      ok(r.backIsFirst, s+'：返回箭头不在最左边');
      ok(r.backGoesToday, s+'：返回箭头没回到今日任务');
      ok(r.onTabs.length===0, s+'：二级屏不该有 tab 高亮（当前不在那个 tab 上）—— 现在亮着 '+r.onTabs);
    }
    if(main.includes(s)){
      ok(!r.hasBack, s+'：主屏不该有返回箭头（底部 tab 就是导航）');
      ok(r.onTabs.length===1, s+'：主屏应恰好有一个 tab 高亮，现在是 '+r.onTabs.length);
    }
  }
  /* ★项目归属三态（CLAUDE.md 五条硬规则之②）：
     凡是提到某个项目的卡片，必须带【项目编号】—— 工地上「王宅」「周宅」重名是常事，
     只写昵称迟早发错货、记错工时。用户 2026-08-12 抓到的就是这个：
     「今日任务」的提货卡只写了出库单号 OUT-0188-07，一个项目字样都没有。 */
  const NICK='林宅|陈宅|罗宅|王宅|周宅|吴宅|刘宅|张宅|李宅|黄宅|赵宅';
  for(const s of screens){
    const bad=await p.evaluate(([id,nick])=>{
      appGo(id);
      const re=new RegExp(nick);
      return [...document.querySelectorAll('#s-'+id+' .card')]
        .filter(c=>re.test(c.textContent) && !/KX-\d{4}-\d{4}/.test(c.textContent))
        .map(c=>c.textContent.replace(/\s+/g,' ').trim().slice(0,34));
    },[s,NICK]);
    ok(bad.length===0, '★'+s+'：有卡片提到了项目却没写项目编号 —— '+bad.join(' ｜ '));
  }
  /* 提货相关的卡还要带地址（货要送到哪儿，光有编号不够） */
  const noAddr=await p.evaluate(()=>{
    appGo('today');
    return [...document.querySelectorAll('#s-today .card')]
      .filter(c=>/提货/.test(c.textContent) && !/📍/.test(c.textContent))
      .map(c=>c.textContent.replace(/\s+/g,' ').trim().slice(0,30));
  });
  ok(noAddr.length===0, '★提货卡没写地址（人要去哪儿提？）—— '+noAddr.join(' ｜ '));

  /* ★一个地址 = 一个框（用户 2026-08-12：「不要单独一个框图，地址一样的都在一个框图里」）
     同一个地址被拆成两个框，工人会以为要跑两趟 —— 提货单单独立框就是这个毛病。
     所以这里不数框、不认标题，只认【地址】：合并没做到，地址就会重复出现。 */
  const grp=await p.evaluate(()=>{
    appGo('today');
    const cards=[...document.querySelectorAll('#s-today .card')];
    const seen={}, dup=[];
    cards.forEach(c=>{ const a=c.dataset.addr; if(!a) return;
      if(seen[a]) dup.push(a); else seen[a]=1; });
    return {dup,
      // 带地址却没走分组渲染的卡 = 手写插进来的，它不会参与合并
      raw:cards.filter(c=>/📍/.test(c.textContent)&&!c.dataset.addr)
               .map(c=>c.textContent.replace(/\s+/g,' ').trim().slice(0,30)),
      n:cards.filter(c=>c.dataset.addr).length};
  });
  ok(grp.dup.length===0, '★同一个地址被拆成了两个框 —— '+grp.dup.join(' ｜ '));
  ok(grp.raw.length===0, '★今日任务里有带地址的卡没走分组渲染（手写的卡不会参与合并）—— '+grp.raw.join(' ｜ '));
  ok(grp.n>=3, '今日任务的地址框太少（'+grp.n+'），演示数据是不是丢了');

  // 真点一次箭头，看是不是真回得去
  await p.evaluate(()=>appGo('mat'));
  await p.click('#s-mat .top .back');
  ok(await p.evaluate(()=>document.getElementById('s-today').classList.contains('on')),
     '★点了返回箭头没回到今日任务');
  console.log(`屏数: ${screens.length}`);
  console.log(`运行时报错: ${errs.length}`); errs.forEach(e=>console.log('  '+e));
  console.log(`断言失败: ${fails.length}`); fails.forEach(f=>console.log('  ✗ '+f));
  console.log(errs.length===0&&fails.length===0?'★ App 冒烟全部通过':'★ 有失败项');
  await b.close(); process.exit(errs.length||fails.length?1:0);
})();
