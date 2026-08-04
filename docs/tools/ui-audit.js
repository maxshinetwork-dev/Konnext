const { chromium } = require('playwright');
(async()=>{
  const browser = await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const page = await browser.newPage({viewport:{width:1440,height:900}});
  const errs=[];
  page.on('console',m=>{ if(m.type()==='error') errs.push('console: '+m.text()); });
  page.on('pageerror',e=>errs.push('pageerror: '+e.message));
  await page.goto('file:///home/user/Konnext/docs/KONNEXT_UI原型.html');
  await page.evaluate(()=>{ SEC.stepAt = Date.now() + 3600000; });
  const roles=['admin','presales','finance','warehouse','maintenance','eng'];
  const seen=new Set(); const thin=[]; const ph=[]; const noHelp=[];
  let n=0;
  for(const r of roles){
    await page.evaluate(w=>loginAs(w),r);
    const info=await page.evaluate(()=>({depts:WHO[me].depts,tier:WHO[me].tier}));
    const tabs=[...info.depts]; if(info.tier===1) tabs.push('decision');
    for(const t of tabs){
      const pgs=await page.evaluate(tb=>DEPT[tb].pages,t);
      for(const p of pgs){
        const key=t+'/'+p; n++;
        if(seen.has(key)) continue; seen.add(key);
        const d=await page.evaluate(a=>{ go(a[0],a[1]);
          const h=document.getElementById('main').innerHTML;
          const k=a[0]+'/'+a[1];
          return {len:h.length, ph:h.includes('原型未展开此页'),
                  tables:(h.match(/<table/g)||[]).length,
                  help:!!(HELP[k]&&(HELP[k].ops||(HELP[k].notes&&HELP[k].notes.length)))};
        },[t,p]);
        if(d.ph) ph.push(key);
        else if(d.len<1500) thin.push(key+' ('+d.len+'字符)');
        if(!d.help) noHelp.push(key);
      }
    }
  }
  console.log('角色×页面渲染次数:', n, '｜ 去重后页面数:', seen.size);
  console.log('\n【占位符页（没内容）】', ph.length?ph.join(', '):'无 ✓');
  console.log('\n【内容偏薄的页 <1500字符】', thin.length?thin.join(', '):'无 ✓');
  console.log('\n【没有帮助内容的页】', noHelp.length, noHelp.length?'→ '+noHelp.join(', '):'✓');
  console.log('\n【运行时报错】', errs.length?errs.join('\n'):'0 ✓');
  await browser.close();
})();
