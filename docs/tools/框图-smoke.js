const { chromium } = require('playwright');
const F=process.argv[2]||'/home/user/Konnext/docs/KONNEXT_八条主线框图.html';
(async()=>{
 const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
 const fails=[],errs=[]; const ok=(c,l)=>{if(!c)fails.push(l)};
 for(const theme of ['light','dark']){
  const p=await b.newPage({viewport:{width:1500,height:1000},colorScheme:theme});
  p.on('pageerror',e=>errs.push('['+theme+'] '+e.message));
  p.on('console',m=>{if(m.type()==='error')errs.push('['+theme+'] '+m.text())});
  await p.goto('file://'+F); await p.waitForTimeout(600);

  const c=await p.evaluate(()=>({
    lanes:document.querySelectorAll('.lane').length,
    humans:document.querySelectorAll('.n-human').length,
    agents:document.querySelectorAll('.lanes .n-read,.lanes .n-draft,.lanes .n-write').length,
    hos:document.querySelectorAll('.ho').length,
    chips:document.querySelectorAll('.dbgrid .chip').length,
    noVerify:[...document.querySelectorAll('.node:not(.lgd)')].filter(n=>/n-(read|draft|write)/.test(n.className))
             .filter(n=>!n.querySelector('.vb')).map(n=>n.textContent),
  }));
  ok(c.lanes===7,theme+' 泳道应 7 条，实际 '+c.lanes);
  ok(c.hos===6,theme+' 交接点应 6 个，实际 '+c.hos);
  ok(c.chips===84,theme+' 库层应 84 张表，实际 '+c.chips);
  ok(c.noVerify.length===0,theme+' ★有 Agent 没标检查者（违反铁律①）: '+c.noVerify.join(','));

  // 对比度：正文颜色不能和背景撞
  const con=await p.evaluate(()=>{
    const g=e=>getComputedStyle(e);
    return {body:g(document.body).backgroundColor,ink:g(document.body).color,
            panel:g(document.querySelector('.lane')).backgroundColor};
  });
  ok(con.body!=='rgba(0, 0, 0, 0)',theme+' body 背景透明 —— 会借用宿主底色');
  ok(con.body!==con.ink,theme+' 文字和背景同色');

  // 悬停：提示浮窗 + 库层点亮
  const n=p.locator('.lanes .n-read').first();
  await n.hover(); await p.waitForTimeout(250);
  const hov=await p.evaluate(()=>({
    tip:getComputedStyle(document.getElementById('tip')).display,
    txt:document.getElementById('tip').innerText.slice(0,40),
    lit:document.querySelectorAll('.chip.lit').length,
  }));
  ok(hov.tip==='block',theme+' 悬停没出提示浮窗');
  ok(/谁验它|干什么/.test(await p.evaluate(()=>document.getElementById('tip').innerText)),
     theme+' 提示里没有「干什么/谁验它」');
  ok(hov.lit>0,theme+' ★悬停后库层没有表亮起来（表名对不上就会这样，而且不报错）');

  await p.locator('.legend .node').first().hover(); await p.waitForTimeout(200);
  ok(await p.evaluate(()=>getComputedStyle(document.getElementById('tip')).display)==='none',
     theme+' 图例样例不该弹提示浮窗');

  // ★标签不许被裁掉：源码写了不等于看得见
  const clipped=await p.evaluate(()=>{
    const bad=[];
    document.querySelectorAll('.gapcap').forEach(c=>{
      const r=c.getBoundingClientRect(), tr=c.closest('.track').getBoundingClientRect();
      const node=c.parentElement.querySelector('.node').getBoundingClientRect();
      if(r.top < tr.top) bad.push('被track裁掉');
      if(r.bottom > node.top+1) bad.push('压在节点上');
    });
    return bad;
  });
  ok(clipped.length===0,theme+' ★「Agent 段」标签有问题: '+clipped.join(','));

  // 交接点：高亮两条线
  await p.locator('.ho').first().hover(); await p.waitForTimeout(250);
  const ho=await p.evaluate(()=>({lit:document.querySelectorAll('.lane.lit').length,
                                  dim:document.querySelectorAll('.lane.dim').length}));
  ok(ho.lit===2,theme+' 交接点应高亮 2 条线，实际 '+ho.lit);
  ok(ho.dim===5,theme+' 其余 5 条应压暗，实际 '+ho.dim);

  // 不许横向滚动
  const ov=await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+2);
  ok(!ov,theme+' 页面横向溢出了');

  if(theme==='light') await p.screenshot({path:'flow_light.png',fullPage:false});
  else { await p.screenshot({path:'flow_dark.png',fullPage:false}); }
  await p.close();
 }
 console.log('运行时报错: '+errs.length); errs.slice(0,6).forEach(e=>console.log('  ! '+e));
 console.log('断言失败: '+fails.length); fails.forEach(f=>console.log('  ✗ '+f));
 console.log(errs.length||fails.length?'★ 有问题':'★ 框图冒烟全部通过（明暗两套主题）');
 await b.close(); process.exit(errs.length||fails.length?1:0);
})();
