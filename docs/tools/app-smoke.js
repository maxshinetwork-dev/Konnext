const { chromium } = require('playwright');
(async()=>{
  const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const p=await b.newPage({viewport:{width:430,height:900}});
  const errs=[]; p.on('pageerror',e=>errs.push(e.message));
  p.on('console',m=>{if(m.type()==='error')errs.push(m.text())});
  await p.goto('file:///home/user/Konnext/docs/KONNEXT_施工端App演示.html');
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
