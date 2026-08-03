const { chromium } = require('playwright');
(async()=>{
  const browser = await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const page = await browser.newPage({viewport:{width:1440,height:900}});
  const errors=[];
  page.on('console',m=>{ if(m.type()==='error') errors.push('console: '+m.text()); });
  page.on('pageerror',e=>errors.push('pageerror: '+e.message));
  await page.goto('file:///home/user/Konnext/docs/KONNEXT_UI原型.html');

  const fails=[];
  const ok=(cond,label)=>{ if(!cond) fails.push(label); };

  // 1) 全角色 × 全页面渲染
  let rendered=0;
  const roles=['admin','presales','finance','warehouse','maintenance','eng'];
  for(const r of roles){
    await page.evaluate(w=>loginAs(w),r);
    const info=await page.evaluate(()=>({depts:WHO[me].depts,tier:WHO[me].tier}));
    const tabs=[...info.depts]; if(info.tier===1) tabs.push('decision');
    for(const t of tabs){
      const pgs=await page.evaluate(tb=>DEPT[tb].pages,t);
      for(const p of pgs){ await page.evaluate(a=>go(a[0],a[1]),[t,p]); rendered++; }
    }
  }

  // 2) 总览：无待办副本，有卡点表
  await page.evaluate(()=>loginAs('finance'));
  await page.evaluate(()=>go('fin','财务节点'));
  let html=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(html.includes('卡点与异常'),'财务节点缺「卡点与异常」');
  ok(!html.includes('我的待办'),'财务节点仍有「我的待办」副本');
  ok(html.includes('变更待估价 3 条'),'财务节点缺指定示例卡点');
  ok(html.includes('<th>立项时间</th>'),'财务节点卡点表缺「立项时间」列（编号后标配）');
  ok(html.includes('S1~S4 节点分布')&&html.includes('A$188,000'),'财务节点缺节点分布/应收未收现算');
  await page.screenshot({path:__dirname+'/shot_总览.png',fullPage:false});

  // 3) 项目列表：全公司一份 + 筛选
  await page.evaluate(()=>go('fin','项目列表'));
  html=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(html.includes('全公司一份'),'项目列表缺「全公司一份」标识');
  ok(html.includes('<th>立项时间</th>')&&html.includes('2025/11/02'),
     '公司项目列表缺「立项时间」列或日期未显示');
  let n=await page.evaluate(()=>{pjFilter='已流失';renderAll();
    return document.querySelectorAll('#main tbody tr').length;});
  ok(n===1,`筛选「已流失」应 1 行，实际 ${n}`);
  ok(html.includes('施工中'),'项目列表缺「施工中」筛选（财务线三项目）');
  n=await page.evaluate(()=>{pjFilter=null;renderAll();
    return document.querySelectorAll('#main tbody tr').length;});
  ok(n===9,`财务默认「财务相关」应 9 行（不含接洽中/已流失），实际 ${n}`);
  n=await page.evaluate(()=>{pjFilter='全部';renderAll();
    const x=document.querySelectorAll('#main tbody tr').length;pjFilter=null;return x;});
  ok(n===11,`财务点「全部」应 11 行（读全部原则），实际 ${n}`);
  await page.screenshot({path:__dirname+'/shot_项目列表.png'});
  // 运维默认筛选 = 项目维护中
  await page.evaluate(()=>loginAs('maintenance'));
  await page.evaluate(()=>go('mt','项目列表'));
  n=await page.evaluate(()=>document.querySelectorAll('#main tbody tr').length);
  ok(n===2,`运维默认「项目维护中」应 2 行，实际 ${n}`);

  // 4) 悬而未决：升级看板，10 行
  await page.evaluate(()=>loginAs('admin'));
  await page.evaluate(()=>go('decision','悬而未决'));
  html=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(html.includes('升级看板'),'悬而未决缺「升级看板」');
  n=await page.evaluate(()=>document.querySelectorAll('#main tbody tr').length);
  ok(n===10,`升级看板应 10 行，实际 ${n}`);
  await page.screenshot({path:__dirname+'/shot_悬而未决.png'});

  // 5) 操作说明收进帮助弹层（用户定：主页面不上屏）
  await page.evaluate(()=>loginAs('finance'));
  await page.evaluate(()=>go('fin','尾款结算S4与Var'));
  html=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(!html.includes('本页操作'),'S4 页面不应内嵌「本页操作」（应收进帮助）');
  const hh=await page.evaluate(()=>{helpOpen();return document.getElementById('helpbody').innerHTML;});
  ok(hh.includes('本页操作')&&hh.includes('标记 S4 已请款'),'帮助弹层缺 S4 操作表');
  await page.screenshot({path:__dirname+'/shot_帮助.png'});
  await page.evaluate(()=>helpClose());
  await page.screenshot({path:__dirname+'/shot_S4结算.png'});

  // 5.5) 售前大表（二轮反馈版：6+1 勾 · 默认四大项 · 列组开关 · 注释）
  await page.evaluate(()=>loginAs('presales'));
  await page.evaluate(()=>go('presales','项目列表'));
  let bhtml=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(bhtml.includes('6+1'),'售前大表缺 6+1 状态组');
  ok(bhtml.includes('已流失'),'售前大表缺「已流失」');
  ok(bhtml.includes('停留'),'售前大表缺「停留」列');
  ok(bhtml.includes('<th class="c1b">立项时间</th>')&&bhtml.includes('2026/07/27'),
     '售前大表缺冻结「立项时间」列或日期未显示');
  ok(bhtml.includes('预测报价'),'售前大表缺「预测报价」');
  ok(bhtml.includes('报价单号'),'签约组缺「报价单号」（应默认可见）');
  ok(bhtml.includes('待签约时填'),'缺「待签约时填」时点提示');
  ok(!bhtml.includes('讲解前填'),'「报价金额」列应已删除');
  ok(bhtml.includes('定金（财务写）'),'签约组缺只读「定金」列');
  ok(bhtml.includes('修改 →'),'缺子表「修改 →」入口');
  ok(!bhtml.includes('<th>佣金类型</th>'),'默认视图不应显示佣金明细列（应收在列组开关里）');
  await page.screenshot({path:__dirname+'/shot_售前大表.png'});
  bhtml=await page.evaluate(()=>{Object.keys(bigCols).forEach(k=>bigCols[k]=true);renderAll();
    return document.getElementById('main').innerHTML;});
  ok(bhtml.includes('<th>佣金类型</th>'),'列组开关未显出佣金明细');
  ok(bhtml.includes('财务注释')&&bhtml.includes('工程注释'),'缺 财务/工程注释 两列');
  ok(bhtml.includes('参建方（工种 · 联系人）')&&bhtml.includes('楼层 · 屋顶')&&bhtml.includes('成员构成'),
     '子表直读列缺失（参建方/楼层/成员）');
  await page.screenshot({path:__dirname+'/shot_售前大表_全列.png'});
  await page.evaluate(()=>{Object.keys(bigCols).forEach(k=>bigCols[k]=false);renderAll();});
  await page.evaluate(()=>wizOpen());
  const wizVisible=await page.evaluate(()=>document.getElementById('wizbox').classList.contains('open'));
  ok(wizVisible,'立项引导弹层未打开');
  const wiz3=await page.evaluate(()=>{wizN=3;wizPaint();return document.getElementById('wizs3').innerHTML;});
  ok(wiz3.includes('参建方')&&wiz3.includes('家庭成员'),'引导第3步缺 家庭成员/参建方');
  const wiz5=await page.evaluate(()=>{wizN=5;wizPaint();return document.getElementById('wizs5').innerHTML;});
  ok(wiz5.includes('方案倾向')&&wiz5.includes('预测报价'),'引导第5步缺 方案倾向/预测报价');
  await page.screenshot({path:__dirname+'/shot_立项引导.png'});
  await page.evaluate(()=>wizClose());
  await page.evaluate(()=>detOpen('KX-2026-0142','王宅'));
  const detVisible=await page.evaluate(()=>document.getElementById('detbox').classList.contains('open'));
  ok(detVisible,'「修改」抽屉未打开');
  const dhtml=await page.evaluate(()=>document.getElementById('detbox').innerHTML);
  ok(dhtml.includes('参建方')&&dhtml.includes('方案倾向')&&dhtml.includes('楼层结构'),'修改抽屉缺子表段落');
  const nDel=(dhtml.match(/class="delx"/g)||[]).length;
  ok(nDel>=6,`修改抽屉删除按钮应≥6（成员4+参建方2），实际 ${nDel}`);
  const nInp=(dhtml.match(/<input/g)||[]).length+(dhtml.match(/<select/g)||[]).length;
  ok(nInp>=25,`修改抽屉可编辑控件应≥25，实际 ${nInp}`);
  const delWorks=await page.evaluate(()=>{const n0=detFam.length;detFamDel(0);
    const n1=detFam.length;detFamAdd();return n0-n1;});
  ok(delWorks===1,'修改抽屉删除成员未生效');
  const addWorks=await page.evaluate(()=>{const n0=detParties.length;detPartyAdd();
    const n1=detParties.length;detPartyDel(n1-1);return n1-n0;});
  ok(addWorks===1,'修改抽屉添加参建方未生效');
  await page.screenshot({path:__dirname+'/shot_修改抽屉.png'});
  await page.evaluate(()=>detClose());
  // 注释大框：多行 textarea + 悬浮全文
  ok(bhtml.includes('<textarea')&&bhtml.includes('notepop'),'注释列缺多行大框/悬浮全文');
  // 状态勾可点选 + 反选回退 + 停留清零
  const tickSeq=await page.evaluate(()=>{const p=BIGPD.find(x=>x.code==='KX-2026-0210');
    const s0=p.step; preTick('KX-2026-0210',1); const s1=p.step;
    preTick('KX-2026-0210',1); const s2=p.step; return [s0,s1,s2].join(',');});
  ok(tickSeq==='1,2,1','状态勾 前进/反选回退 失效');
  const stayReset=await page.evaluate(()=>{preTick('KX-2026-0210',1);
    const p=BIGPD.find(x=>x.code==='KX-2026-0210'); const s=p.stay;
    preTick('KX-2026-0210',1); return s;});
  ok(stayReset===0,'点选后「停留」应清零重新计时');
  const lostSeq=await page.evaluate(()=>{const p=BIGPD.find(x=>x.code==='KX-2026-0210');
    preLost('KX-2026-0210'); const a=p.lost; preLost('KX-2026-0210'); const b=p.lost;
    return a+','+b;});
  ok(lostSeq==='true,false','第⑦勾 流失/取消流失 反选失效');
  const signGuard=await page.evaluate(()=>{const p=BIGPD.find(x=>x.code==='KX-2026-0142');
    preLost('KX-2026-0142'); return p.lost;});
  ok(signGuard===false,'已签约项目不应能勾流失');
  // 5.6) 售前设置页 + 内生提醒
  await page.evaluate(()=>go('presales','设置'));
  let shtml=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(shtml.includes('停留提醒阈值')&&shtml.includes('每天一次'),'售前设置页缺阈值/频率');
  ok(shtml.includes('下拉选项管理')&&shtml.includes('工种选项'),'售前设置页缺下拉选项管理');
  const hasNewRole=await page.evaluate(()=>{roleOpts.push('物业经理');bigCols.contact=true;
    go('presales','项目列表');const hit=document.getElementById('main').innerHTML.includes('物业经理');
    roleOpts.pop();bigCols.contact=false;renderAll();return hit;});
  ok(hasNewRole,'设置里新增的角色未出现在大表角色下拉');
  const drawerFrom=await page.evaluate(()=>{renderAll();
    return document.getElementById('drawer-body').textContent;});
  ok(drawerFrom.includes('售前流程'),'售前待办应来自「售前流程」（内生提醒）');
  ok(!drawerFrom.includes('市场'),'售前待办不应再有外部来源');
  await page.screenshot({path:__dirname+'/shot_售前设置.png'});
  const nOrange=await page.evaluate(()=>{preRemindDays=7;go('presales','项目列表');
    const n=document.querySelectorAll('#main td span[style*="warning"]').length;
    preRemindDays=3;renderAll();return n;});
  ok(nOrange===2,`阈值改 7 天后应只剩 2 行橙色（9/12 天），实际 ${nOrange}`);
  // 5.7) 实时搜索（编号/昵称/地址，逐字刷新）
  const nWu=await page.evaluate(()=>{go('presales','项目列表');bigQ='吴';renderAll();
    return document.querySelectorAll('#main .bigtable tbody tr').length;});
  ok(nWu===1,`大表搜「吴」应 1 行，实际 ${nWu}`);
  const nCode=await page.evaluate(()=>{bigQ='0198';renderAll();
    return document.querySelectorAll('#main .bigtable tbody tr').length;});
  ok(nCode===1,`大表搜「0198」应 1 行，实际 ${nCode}`);
  const nAddr=await page.evaluate(()=>{bigQ='beecroft';renderAll();
    const n=document.querySelectorAll('#main .bigtable tbody tr').length;bigQ='';renderAll();return n;});
  ok(nAddr===1,`大表按地址搜「beecroft」应 1 行，实际 ${nAddr}`);
  const nPj=await page.evaluate(()=>{go('fin','项目列表');pjFilter='全部';pjQ='Beecroft';renderAll();
    const n=document.querySelectorAll('#main tbody tr').length;pjQ='';pjFilter=null;renderAll();return n;});
  ok(nPj===1,`项目列表搜「Beecroft」应 1 行，实际 ${nPj}`);
  // 5.8) 项目状态表：扇形 + 堆叠柱 + 状态过滤
  await page.evaluate(()=>go('presales','项目状态表'));
  let sthtml=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok((sthtml.match(/<path /g)||[]).length>=4,'扇形图切片缺失');
  ok(sthtml.includes('已签约')&&sthtml.includes('已流标')&&sthtml.includes('待签约(在途)'),'柱状图三段标签缺失');
  const nSt=await page.evaluate(()=>{stFilter='待签约';renderAll();
    const n=document.querySelectorAll('#main .bigtable tbody tr').length;stFilter='全部';renderAll();return n;});
  ok(nSt===1,`状态过滤「待签约」应 1 行，实际 ${nSt}`);
  // 十七轮起：图表全按演示项目真实数据现算（9 立项 = 3 签约 + 1 流失 + 5 在途）
  const yearOk=await page.evaluate(()=>{statPeriod='year';renderAll();
    const h=document.getElementById('main').innerHTML;
    const hit=h.includes('立项 14 个')&&h.includes('已签约 8')&&h.includes('已流标 1');
    statPeriod='month';renderAll();return hit;});
  ok(yearOk,'「年」档去向柱应真算出 14/8/1（含财务线与安装调试演示项目）');
  // 近 12 个月逐月柱（滚动窗口：首=11个月前，末=当月）
  sthtml=await page.evaluate(()=>document.getElementById('main').innerHTML);
  const mlab=await page.evaluate(()=>{const n=new Date();
    const f=off=>{const d=new Date(n.getFullYear(),n.getMonth()+off,1);
      return String(d.getFullYear()).slice(2)+'-'+String(d.getMonth()+1).padStart(2,'0');};
    return {first:f(-11),last:f(0)};});
  ok(sthtml.includes(mlab.first)&&sthtml.includes(mlab.last),
     `12个月图缺首/末月份标签（应 ${mlab.first} ~ ${mlab.last}）`);
  ok((sthtml.match(/<rect /g)||[]).length>=8,'12个月成交图柱段数量不足');
  ok(sthtml.includes('近 12 个月'),'缺「近 12 个月」面板');
  ok(!sthtml.includes('市场增长'),'「新立项数量（市场增长）」图应已删除（十八轮用户定）');
  ok(sthtml.includes('每月立项项目成交图')&&sthtml.includes('柱顶数字 = 当月新立项数'),
     '成交图标题/柱顶数字说明缺失');
  ok(sthtml.includes('26-05 待签约(在途) 2 个')&&sthtml.includes('25-11 已签约 1 个')
     &&sthtml.includes('26-04 已流标 1 个'),'成交图月桶数值与演示数据不符');
  // 成交图口径（用户例）：26-05 立的项流失 → 红段回填 26-05，不动当月柱
  const cohortChk=await page.evaluate(()=>{
    preLost('KX-2026-0186');                              // 周宅 立项 2026/05/12
    const h=document.getElementById('main').innerHTML;
    const n=new Date(), cur=String(n.getFullYear()).slice(2)+'-'+String(n.getMonth()+1).padStart(2,'0');
    const may=h.includes('26-05 已流标 1 个');
    const curClean=!h.includes(cur+' 已流标');
    preLost('KX-2026-0186');                              // 反选还原
    const h2=document.getElementById('main').innerHTML;
    return {may,curClean,restored:h2.includes('26-05 待签约(在途) 2 个')};});
  ok(cohortChk.may,'流失未回填到立项月份 26-05 的柱');
  ok(cohortChk.curClean,'流失误记到当前月柱（应记立项月）');
  ok(cohortChk.restored,'取消流失后 26-05 月桶未还原');
  // 立项引导真加行 + 图表 +1 联动
  const wizAdd=await page.evaluate(()=>{
    const n0=BIGPD.length;
    go('presales','项目列表'); wizOpen(); wizN=5; wizPaint(); wizNext();   // 空表单直接完成
    const n1=BIGPD.length, first=BIGPD[0].code, step=BIGPD[0].step, opd=BIGPD[0].opened;
    go('presales','项目状态表');
    const html=document.getElementById('main').innerHTML;
    const n=new Date(), cur=String(n.getFullYear()).slice(2)+'-'+String(n.getMonth()+1).padStart(2,'0');
    const grew=html.includes(cur+' 待签约(在途) 1 个');                     // 成交图当月柱 0→1（新档在途）
    const pie6=html.includes('共 6 个');                                    // 在途 5→6
    BIGPD.shift(); renderAll();                                             // 还原演示数据
    return JSON.stringify({added:n1-n0,first,step,opd,grew,pie6});});
  const wa=JSON.parse(wizAdd);
  ok(wa.added===1&&wa.first==='KX-2026-0211'&&wa.step===1,'立项完成未真加行/编号或状态不对');
  ok(/^\d{4}\/\d{2}\/\d{2}$/.test(wa.opd),`向导建档「立项时间」应落当天日期，实际 ${wa.opd}`);
  ok(wa.grew,'新立项后成交图当月柱未 +1');
  ok(wa.pie6,'新立项后扇形在途总数未 +1');
  await page.screenshot({path:__dirname+'/shot_项目状态表.png'});
  await page.evaluate(()=>loginAs('finance'));

  // 6) 待办抽屉仍是唯一待办处
  await page.evaluate(()=>toggleDrawer());
  const drawerN=await page.evaluate(()=>document.querySelectorAll('#drawer-body .todo').length);
  ok(drawerN>0,'待办抽屉为空');
  await page.waitForTimeout(350);
  await page.screenshot({path:__dirname+'/shot_待办抽屉.png'});

  // 6.5) 待办中心 十九轮：三动作 + 超期最久置顶 + 年月日小时自动单位 + 不累积说明
  let dh=await page.evaluate(()=>document.getElementById('drawer-body').innerHTML);
  ok(dh.includes('已知悉')&&dh.includes('>处理<')&&dh.includes('>搁置<'),'待办缺三动作按钮');
  ok(dh.includes('超期 7 个月'),'超期未用年月日自动单位（张宅应显 7 个月）');
  ok(!/超期 \d+h/.test(dh),'仍有纯小时超期显示');
  ok(dh.includes('超期最久置顶')&&dh.includes('不累积'),'待办缺排序/不累积说明');
  const sortChk=await page.evaluate(()=>{const a=myTodos().map(t=>t.h-t.sla);
    return JSON.stringify({ok:a.every((v,i)=>!i||a[i-1]>=v),a});});
  const sc=JSON.parse(sortChk);
  ok(sc.ok,`待办应按超期时长降序：${sc.a}`);
  const ackChk=await page.evaluate(()=>{const n0=myTodos().length; const id=myTodos()[0].id;
    todoAck(id); const n1=myTodos().length; delete todoState[id]; renderAll(); return n0-n1;});
  ok(ackChk===1,'已知悉未停止通知（应从列表消失）');
  const holdChk=await page.evaluate(()=>{const n0=myTodos().length; const id=myTodos()[0].id;
    todoHold(id); const n1=myTodos().length;
    const kept=document.getElementById('drawer-body').innerHTML.includes('已搁置');
    todoHold(id); return JSON.stringify({same:n0===n1,kept});});
  const hc=JSON.parse(holdChk);
  ok(hc.same&&hc.kept,'搁置应保留通知并标「已搁置」');
  const goChk=await page.evaluate(()=>{const t=TODOS.find(x=>x.ev.includes('SM3 检查布线'));
    todoGo(t.id); return JSON.stringify({tab,page,pjCode:PROJECTS[pj].code});});
  const gc=JSON.parse(goChk);
  ok(gc.tab==='fin'&&gc.page==='项目收款S1-S3'&&gc.pjCode==='KX-2026-0142','「处理」未切到项目对应页面');
  const goPre=await page.evaluate(()=>{loginAs('presales');
    const t=allTodos().find(x=>x.ev.includes('黄宅'));
    todoGo(t.id); const rows=document.querySelectorAll('#main .bigtable tbody tr').length;
    const r=JSON.stringify({tab,page,q:bigQ,rows}); bigQ=''; renderAll(); return r;});
  const gp=JSON.parse(goPre);
  ok(gp.tab==='presales'&&gp.page==='项目列表'&&gp.q==='KX-2026-0201'&&gp.rows===1,
     '售前「处理」未过滤到该项目');
  // 售前 SLA/条目跟设置阈值现算（用户纠错：3 天改 4 天要立即生效）
  const slaChk=await page.evaluate(()=>{
    BIGPD.find(x=>x.code==='KX-2026-0210').stay=3;   // 还原 5.5 点勾测试清零的停留（清零→提醒消失本身是设计行为）
    renderAll();
    const n3=myTodos().length, s3=myTodos()[0].sla;
    preRemindDays=4; renderAll();
    const n4=myTodos().length, s4=myTodos()[0].sla;
    const shown=document.getElementById('drawer-body').innerHTML.includes('SLA 4 天');
    preRemindDays=3; renderAll();
    return JSON.stringify({n3,s3,n4,s4,shown});});
  const sl=JSON.parse(slaChk);
  ok(sl.n3===4&&sl.s3===72,`阈值3天应4条/SLA72h，实际 ${sl.n3}/${sl.s3}`);
  ok(sl.n4===3&&sl.s4===96&&sl.shown,
     `阈值改4天应3条(吴宅3天退出)/SLA 显示4天，实际 ${sl.n4}/${sl.s4}/${sl.shown}`);
  // 已知悉后状态改变 → 通知重新启动（用户定）
  const reactChk=await page.evaluate(()=>{
    const id='pre-KX-2026-0198';                        // 郑宅 · 报价中 · 停留6天
    todoAck(id);
    const gone=!myTodos().some(t=>t.id===id);
    preTick('KX-2026-0198',2);                          // 反选回退一步 = 状态改变（停留清零）
    const p=BIGPD.find(x=>x.code==='KX-2026-0198');
    p.stay=6; renderAll();                              // 模拟又停留到阈值
    const back=myTodos().some(t=>t.id===id);
    preTick('KX-2026-0198',2); p.stay=6; renderAll();   // 还原：回到第3步、停留6天
    return JSON.stringify({gone,back});});
  const rc=JSON.parse(reactChk);
  ok(rc.gone,'已知悉未停止通知');
  ok(rc.back,'状态改变后通知未重新启动');
  await page.evaluate(()=>{loginAs('finance');toggleDrawer();});
  await page.waitForTimeout(350);
  await page.screenshot({path:__dirname+'/shot_待办三动作.png'});
  await page.evaluate(()=>toggleDrawer());

  // 6.6) 操作日志（二十轮：六部门通用 · 真记录）
  await page.evaluate(()=>loginAs('presales'));
  await page.evaluate(()=>go('presales','操作日志'));
  let lg=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(lg.includes('<th>时间</th>')&&lg.includes('<th>项目编号</th>')&&lg.includes('<th>立项时间</th>')
     &&lg.includes('<th>操作人</th>')&&lg.includes('<th>操作</th>')&&lg.includes('<th>改了什么</th>'),
     '日志表头六列缺失');
  ok(lg.includes('写入定金')&&lg.includes('已读工程注释'),'售前日志缺跨部门确认条目');
  ok(!lg.includes('S2 到账下单'),'售前日志不应含纯采购条目');
  const liveLog=await page.evaluate(()=>{
    const n0=OPLOG.length; preTick('KX-2026-0210',1); preTick('KX-2026-0210',1);
    return JSON.stringify({added:OPLOG.length-n0,
      acts:OPLOG.slice(0,2).map(r=>r.action).join(','),pj:OPLOG[0].pj});});
  const lv=JSON.parse(liveLog);
  ok(lv.added===2&&lv.acts==='勾状态回退,勾状态推进'&&lv.pj==='KX-2026-0210','点勾未真记录进日志');
  const editLog=await page.evaluate(()=>{preEdit('KX-2026-0198','qno','Q-2026-0198','报价单号');
    const r={a:OPLOG[0].action,d:OPLOG[0].detail};
    preEdit('KX-2026-0198','qno','','报价单号');
    return JSON.stringify(r);});
  const el=JSON.parse(editLog);
  ok(el.a==='修改报价单号'&&el.d.includes('（空） → 「Q-2026-0198」'),'行内直改未留 前值→后值');
  const lgq=await page.evaluate(()=>{go('presales','操作日志');logQ='定金';renderAll();
    const n=document.querySelectorAll('#main tbody tr').length; logQ='';renderAll(); return n;});
  ok(lgq===3,`日志搜「定金」应 3 行（三十六轮种子+2），实际 ${lgq}`);
  const lgDept=await page.evaluate(()=>{logDeptF='财务';renderAll();
    const n=document.querySelectorAll('#main tbody tr').length; logDeptF='全部';renderAll(); return n;});
  ok(lgDept===2,`按「财务」筛应 2 行，实际 ${lgDept}`);
  await page.screenshot({path:__dirname+'/shot_操作日志.png'});
  const finLog=await page.evaluate(()=>{loginAs('finance');go('fin','操作日志');
    const h=document.getElementById('main').innerHTML;
    return h.includes('SM3 检查布线完成')&&h.includes('维护单开票')&&!h.includes('完成立项建档');});
  ok(finLog,'财务日志应含相关跨部门条目、不含纯售前条目');
  // 建筑选项设置化：设置里加的选项立即出现在立项引导第4步
  const bOpt=await page.evaluate(()=>{loginAs('presales');houseTypeOpts.push('农庄');
    go('presales','项目列表');
    const hit=document.getElementById('main').innerHTML.includes('农庄');
    houseTypeOpts.pop(); go('presales','设置');
    const st=document.getElementById('main').innerHTML;
    return JSON.stringify({hit,set:st.includes('房屋类型选项')&&st.includes('屋顶选项')
      &&st.includes('楼层用途选项')&&st.includes('施工阶段选项')});});
  const bo=JSON.parse(bOpt);
  ok(bo.hit,'设置新增房屋类型未出现在立项引导');
  ok(bo.set,'设置页缺建筑四类选项管理');
  await page.screenshot({path:__dirname+'/shot_建筑选项.png'});

  // 6.7) 财务线（二十一轮：收款S1-S3 / S4与Var / 催账停服 / 运维支持 / 报销 / 工资 / 设置）
  await page.evaluate(()=>loginAs('finance'));
  await page.evaluate(()=>go('fin','项目收款S1-S3'));
  let fh=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(fh.includes('A$48,000')&&fh.includes('部分到账'),'0203 S1 应收 10% 自动算/部分到账缺失');
  ok(fh.includes('已请款·超期'),'0160 S2 超期状态缺失');
  ok(fh.includes('门禁：SM4 未完成'),'S3 请款按钮未按 SM4 门禁禁用（悬停原句）');
  ok((fh.match(/<path |<circle /g)||[]).length>=3&&fh.includes('已收 / 未收'),'收款页缺饼图/柱图');
  ok(fh.includes('外部财务系统'),'缺「真账在外部系统」定位说明');
  const reqChk=await page.evaluate(()=>{
    const f=finOf('KX-2026-0170'); finReq('KX-2026-0170',2);           // SM4 已完成 → S3 可请款
    const r={inv:!!f.ms[2].inv,log:OPLOG[0].action,frozen:document.getElementById('main').innerHTML.includes('🔒 '+f.ms[2].inv)};
    f.ms[2].inv=undefined; f.ms[2].ver=0; f.ms[2].firstInv=undefined; NOTIF.shift(); renderAll();
    return JSON.stringify(r);});
  const rq=JSON.parse(reqChk);
  ok(rq.inv&&rq.log==='标记 S3 已请款'&&rq.frozen,'标记请款未定格/未入日志');
  const settleChk=await page.evaluate(()=>{
    const f=finOf('KX-2026-0203'), m=f.ms[0];
    finSettle('KX-2026-0203',0);                       // 不足额 → uiPrompt 弹层，未结清
    const blocked=!m.settled&&document.getElementById('uibox').style.display==='block';
    document.getElementById('uiinput').value='客户申请减免尾差'; uiOk();
    const gapOk=m.settled&&m.gapWhy==='客户申请减免尾差'&&m.gap>0;
    m.settled=false; m.settledAt=undefined; m.gap=undefined; m.gapWhy=undefined;
    m.recv.push({amt:28000,how:'走账',gst:2800,at:'2026/08/01',by:'王姐'});
    finSettle('KX-2026-0203',0);                       // 足额 → 直接结清
    const done=m.settled&&OPLOG.some(r=>r.action==='S1 点结清');
    m.recv.pop(); m.settled=false; m.settledAt=undefined; renderAll();
    return JSON.stringify({blocked,gapOk,done});});
  const sc2=JSON.parse(settleChk);
  ok(sc2.blocked,'不足额结清未弹原因输入层');
  ok(sc2.gapOk,'填原因后差额定格结清未生效');
  ok(sc2.done,'足额点结清未生效/未入日志');
  // S4 与 Var：门禁 → 估价 → 未退料 → 请款定格
  const s4Chk=await page.evaluate(()=>{
    const f=finOf('KX-2026-0142');
    finS4Req('KX-2026-0142'); const g1=!f.ms[3].inv;                    // 3 条待估价 → 拦
    f.vars.forEach(v=>{if(v.billable&&v.amt==null){v.amt=v.sys;v.by='王姐';v.at='2026/08/01';v.note='测试依据';}});
    finS4Req('KX-2026-0142'); const g2=!f.ms[3].inv;                    // 未退料未结算 → 拦
    finSettleUnret('KX-2026-0142');
    finS4Req('KX-2026-0142');
    go('fin','尾款结算S4与Var');
    const h=document.getElementById('main').innerHTML;
    const r={g1,g2,inv:!!f.ms[3].inv,total:h.includes('A$60,963.83'),lock:h.includes('v1 定格')};
    // 还原
    f.ms[3].inv=undefined; f.ms[3].ver=0; f.ms[3].firstInv=undefined;
    f.vars=f.vars.filter(v=>v.src!=='未退料'); f.unret=2013.83;
    f.vars.forEach(v=>{if([4,5,6].includes(v.id)){v.amt=null;v.by=undefined;v.at=undefined;v.note=undefined;}});
    renderAll(); return JSON.stringify(r);});
  const s4=JSON.parse(s4Chk);
  ok(s4.g1&&s4.g2,'S4 请款门禁（待估价/未退料）未拦');
  ok(s4.inv&&s4.total,'S4 组合应收 60,963.83（尾款+变更含工程追加+未退料）未算对/未定格');
  // 工程追加变更（工程负责人提案演示）：来源标/工时列/传库管
  const engVar=await page.evaluate(()=>{go('fin','尾款结算S4与Var');s4Open['KX-2026-0142']=true;renderAll();
    const h=document.getElementById('main').innerHTML;s4Open['KX-2026-0142']=false;
    return h.includes('工程追加')&&h.includes('工时(工程填)')&&h.includes('6h')&&h.includes('已传库管');});
  ok(engVar,'工程追加变更缺来源标/工时列/传库管标注');
  // 移位不计费 + 改价必须依据
  const varChk=await page.evaluate(()=>{
    const f=finOf('KX-2026-0142'); const v=f.vars.find(x=>!x.billable);
    finVarSave('KX-2026-0142',v.id);                                    // 移位 → alert 拒
    return v.amt===0;});
  ok(varChk,'移位变更填金额未被拒');
  // 催账停服页
  await page.evaluate(()=>go('fin','催账和停服'));
  fh=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(fh.includes('账龄')&&fh.includes('改版抹不掉')&&fh.includes('拒付停服'),'催账页缺账龄双口径/停服入口');
  ok(/天<\/b>/.test(fh),'0160 超期天数未标红');
  const susChk=await page.evaluate(()=>{finSuspend('KX-2026-0160');
    const pend=!finOf('KX-2026-0160').susp&&document.getElementById('uibox').style.display==='block';
    uiOk();
    const did=finOf('KX-2026-0160').susp===true;
    const f=finOf('KX-2026-0160'); f.susp=false; f.suspAt=undefined; renderAll();
    return JSON.stringify({pend,did});});
  const sk2=JSON.parse(susChk);
  ok(sk2.pend,'停服未经确认就生效（应先弹确认层）');
  ok(sk2.did,'确认后停服未生效');
  // 运维支持：定价开票
  const mtChk=await page.evaluate(()=>{go('fin','运维财务支持');
    document.getElementById('mt-amt-MT-0180-03').value='400';
    mtPrice('MT-0180-03');
    const c=MCASES.find(x=>x.id==='MT-0180-03');
    const r={st:c.st,amt:c.amt,log:OPLOG[0].action};
    c.st='待定价'; c.amt=null; c.inv=undefined; c.paid=undefined; renderAll();
    return JSON.stringify(r);});
  const mc=JSON.parse(mtChk);
  ok(mc.st==='已开票'&&mc.amt===400&&mc.log==='维护单定价开票','维护定价开票流程未生效');
  // 二十五轮：成本核算（人工=工时×成本时薪现算 · 物料=出库台账归集）
  const mtCostChk=await page.evaluate(()=>{go('fin','运维财务支持');
    const h=document.getElementById('main').innerHTML;
    return JSON.stringify({
      lab:h.includes('A$69.80')&&h.includes('在场1.5h+路上0.5h'),
      pts:h.includes('A$68.40')&&h.includes('出库单 OUT-0180-12'),
      tot:h.includes('A$138.20'),ref:h.includes('成本参考'),
      free:h.includes('免单 · 成本计入维保成本'),
      card:h.includes('本月维护成本')});});
  const mk=JSON.parse(mtCostChk);
  ok(mk.lab,'人工成本未按 工时×成本时薪 现算展示');
  ok(mk.pts,'物料成本未从出库台账归集展示');
  ok(mk.tot&&mk.ref,'成本合计/定价参考缺失');
  ok(mk.free&&mk.card,'免单成本口径/月度成本卡缺失');
  // 项目报销：自批拦截 + 批准入成本 + 图表
  const expChk=await page.evaluate(()=>{go('fin','项目报销');
    const h=document.getElementById('main').innerHTML;
    expOk('EX-068');                                                    // 王姐批自己 → 拦
    const self=EXP.find(e=>e.id==='EX-068').st==='待审批';
    expOk('EX-071');
    const e=EXP.find(x=>x.id==='EX-071'); const okd=e.st==='已批准';
    e.st='待审批'; e.by=undefined; renderAll();
    return JSON.stringify({self,okd,chart:h.includes('占成本')&&h.includes('类别分布'),
      untr:h.includes('★ 无从追溯')});});
  const ec=JSON.parse(expChk);
  ok(ec.self,'自己审批自己的报销未被拦');
  ok(ec.okd,'批准报销未生效');
  ok(ec.chart&&ec.untr,'报销页缺图表/无从追溯红牌');
  // 二十四轮：类别只剩三种 + 项目地址列 + S4 未退料指路
  const exp24=await page.evaluate(()=>{go('fin','项目报销');
    const h=document.getElementById('main').innerHTML;
    return JSON.stringify({no:!h.includes('>餐费<')&&!h.includes('>办公<'),
      cat:h.includes('材料补购 · 交通递送 · 工具采购')&&h.includes('<td>工具采购</td>')&&!h.includes('<td>工具</td>'),
      addr:h.includes('项目 · 地址')&&h.includes('11 Bond St, Mosman NSW')});});
  const e24=JSON.parse(exp24);
  ok(e24.no&&e24.cat,'报销类别未正名为 材料补购/交通递送/工具采购');
  ok(e24.addr,'报销表缺项目昵称+完整地址列');
  // 6.12) 三十四轮：收据=图片链接（预览弹层/弹层内批准/下载本地）· 付款不走本系统
  const w34=await page.evaluate(()=>{go('fin','项目报销');
    const h=document.getElementById('main').innerHTML;
    const link=h.includes('📷 查看')&&h.includes('download="EX-070-收据.svg"');
    const pay=h.includes('付款不走本系统');
    expImg('EX-071');
    const box=document.getElementById('imgbox');
    const open=box.style.display==='block'&&box.innerHTML.includes('data:image/svg')
      &&box.innerHTML.includes('⬇ 下载到本地')&&box.innerHTML.includes('expImgOk');
    imgClose();
    expImg('EX-070');
    const open2=box.innerHTML.includes('已批准')&&!box.innerHTML.includes('expImgOk');
    imgClose();
    expImg('EX-071'); expImgOk('EX-071');
    const e=EXP.find(x=>x.id==='EX-071');
    const okd=e.st==='已批准'&&document.getElementById('imgbox').style.display==='none';
    e.st='待审批'; e.by=undefined; renderAll();
    return JSON.stringify({link,pay,open,open2,okd});});
  const r34=JSON.parse(w34);
  ok(r34.link,'收据列缺 📷 查看链接/已批准行缺下载快捷链接');
  ok(r34.pay,'页面未写明「付款不走本系统」口径');
  ok(r34.open,'收据预览弹层缺图/下载/批准入口');
  ok(r34.open2,'已批准单的弹层不该再有批准按钮');
  ok(r34.okd,'弹层内批准未生效/弹层未关闭');
  const s424=await page.evaluate(()=>{go('fin','尾款结算S4与Var');
    const h=document.getElementById('main').innerHTML;
    return h.includes('未退料 ⓘ')&&h.includes('结算未退料')&&h.includes('未退料（库管未填写）')&&h.includes('财务不手填');});
  ok(s424,'S4 未退料来源/指路说明缺失');
  // 工资 + 成本利润率 + 设置
  await page.evaluate(()=>go('fin','工资数据'));
  fh=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(fh.includes('真正发工资在外部系统')&&fh.includes('🔒 已定格')&&fh.includes('挂起 · 无记录'),'工资页三要素缺失');
  await page.evaluate(()=>go('fin','成本与利润率'));
  fh=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(fh.includes('−237.6%')&&fh.includes('不显示')&&fh.includes('实收'),'利润率三处特殊处理缺失');
  const setChk=await page.evaluate(()=>{
    finSetVal('otRates.weekday','平日超时',0.5);                         // <1 → 拦
    const low=finSet.otRates.weekday===1;
    finSetVal('overdueDays','超期天数',45);
    const chg=finSet.overdueDays===45&&OPLOG[0].action==='修改财务设置';
    finSet.overdueDays=30; renderAll();
    return JSON.stringify({low,chg});});
  const st2=JSON.parse(setChk);
  ok(st2.low,'加班倍数低于 1 未被拦');
  ok(st2.chg,'财务设置改动未生效/未入日志');
  // 6.10) 三十一轮：工资数据=数据平台（项目人力消耗/日结周期视图/倒休休假）+ 设置人员管理 + 售前邮箱
  const w31a=await page.evaluate(()=>{go('fin','工资数据');
    const h=document.getElementById('main').innerHTML;
    return JSON.stringify({
      plat:h.includes('项目人力消耗')&&h.includes('售前预计人工')&&h.includes('交付前人工成本')&&h.includes('维护已消耗人工'),
      scope:h.includes('林宅')&&h.includes('王宅')&&h.includes('陈宅')&&h.includes('刘宅')&&!h.includes('张宅'),
      over:h.includes('超预计'),
      trio:h.includes('11 Bond St, Mosman NSW'),
      grow:hrAgg('KX-2026-0188').T.bh>=426});});
  const a31=JSON.parse(w31a);
  ok(a31.plat,'人力消耗表四列（预计/交付耗/成本/维护耗）缺失');
  ok(a31.scope,'人力消耗范围应=施工中/交付/维护中（张宅烂尾不该出现）');
  ok(a31.over,'超预计未标红提示（0142 演示）');
  ok(a31.trio,'人力消耗表缺三件套（昵称+完整地址）');
  ok(a31.grow,'0188 交付已消耗应≥定格基数 426h（日结逐日续算失效）');
  const w31b=await page.evaluate(()=>{hrOpen['KX-2026-0188']=true;renderAll();
    const h=document.getElementById('main').innerHTML;hrOpen['KX-2026-0188']=false;renderAll();
    return JSON.stringify({stage:h.includes('阶段时薪：07/31 前 A$40 · 08/01 起 A$42'),
      ppl:h.includes('阿强')&&h.includes('老李')&&h.includes('Tony')&&h.includes('人成本（阶段时薪累计）')});});
  const b31=JSON.parse(w31b);
  ok(b31.stage,'每人明细缺阶段时薪说明（调薪只影响之后的天）');
  ok(b31.ppl,'每人明细人员/人成本列缺失');
  const w31c=await page.evaluate(()=>{const d=document.getElementById('dayrecent').innerHTML;
    return JSON.stringify({noCode:!d.includes('KX-2026'),addr:d.includes('罗宅')&&d.includes('Springdale'),
      hang:d.includes('挂起 · 无记录')&&d.includes('每日工时管理')&&!d.includes('>补录</button>'),
      lock:d.includes('🔒 已定格')});});
  const c31=JSON.parse(w31c);
  ok(c31.noCode&&c31.addr,'日结近况项目列应为 昵称+完整地址（不用编号）');
  ok(c31.hang,'财务侧挂起行应只显示状态+每日工时管理指路（不能有补录按钮）');
  ok(c31.lock,'日结近况缺已定格标');
  const w31d=await page.evaluate(()=>{payGridOpen=true;renderAll();
    const g=document.getElementById('paygrid');
    const mainH=document.getElementById('main').innerHTML;
    const heads=g?g.querySelectorAll('thead th').length:0;
    const rows=g?g.querySelectorAll('tbody tr').length:0;
    payGridOpen=false;renderAll();
    return JSON.stringify({exists:!!g,heads,rows,roll:mainH.includes('每月 21 号自动滚动'),tot:mainH.includes('周期合计')});});
  const d31=JSON.parse(w31d);
  ok(d31.exists&&d31.heads>=3&&d31.rows===4,`周期视图网格应 4 人行+日期列，实际 ${d31.rows} 行 ${d31.heads} 列`);
  ok(d31.roll&&d31.tot,'周期视图缺 21 号滚动说明/周期合计');
  const w31e=await page.evaluate(()=>{
    leaveOpen('小陈');
    document.getElementById('lv-from').value='2026-08-05T09:00';
    document.getElementById('lv-to').value='2026-08-05T17:00';
    const calc=lvCalc()===8;
    leaveConfirm();
    const pend=LEAVES[0]&&LEAVES[0].st==='待回复'&&LEAVES[0].hrs===8;
    const noti=NOTIF[0].what.includes('倒休休假确认')&&NOTIF[0].to[0].how==='短信'&&NOTIF[0].to[0].ok===false;
    leaveOpen('老李');
    document.getElementById('lv-from').value='2026-08-06T09:00';
    document.getElementById('lv-to').value='2026-08-06T17:00';
    const n0=LEAVES.length; leaveConfirm(); leaveClose();
    const overdraft=LEAVES.length===n0;
    leaveYes(0);
    const bal=toilBal('小陈')===4.5&&LEAVES[0].st==='已确认';
    leaveOpen('老李');
    document.getElementById('lv-from').value='2026-08-07T09:00';
    document.getElementById('lv-to').value='2026-08-07T12:00';
    leaveConfirm();
    leaveForce(0); uiOk();
    const forced=LEAVES[0].st==='强制扣减'&&toilBal('老李')===1&&TOIL[TOIL.length-1].forced===true;
    const red=document.getElementById('main').innerHTML.includes('强制扣减（员工未回复）');
    const logOk=OPLOG[0].action==='倒休强制扣减';
    LEAVES.length=0; TOIL.length=3; NOTIF.shift(); NOTIF.shift(); renderAll();
    const restore=toilBal('小陈')===12.5&&toilBal('老李')===4;
    return JSON.stringify({calc,pend,noti,overdraft,bal,forced,red,logOk,restore});});
  const e31=JSON.parse(w31e);
  ok(e31.calc,'休假弹窗 从→至 时长换算错误（8h）');
  ok(e31.pend&&e31.noti,'休假确认未生成待回复单/未发员工短信');
  ok(e31.overdraft,'倒休透支未被拦（老李余额 4h 扣 8h 应拒）');
  ok(e31.bal,'员工回 Y 未自动扣减（小陈 12.5−8=4.5）');
  ok(e31.forced,'强制扣减未生效（老李 4−3=1 · forced 留痕）');
  ok(e31.red,'强制扣减未用红字显示');
  ok(e31.logOk,'强制扣减未进操作日志');
  ok(e31.restore,'休假测试后演示态未还原');
  const w31f=await page.evaluate(()=>{go('fin','设置');
    const h0=document.getElementById('main').innerHTML;
    const has=h0.includes('工资发放人员')&&h0.includes('停用');
    const n0=STAFF.length;
    document.getElementById('stf-name').value='测试工';
    document.getElementById('stf-cost').value='';
    finStaffAdd();
    const gate=STAFF.length===n0;
    document.getElementById('stf-name').value='测试工';
    document.getElementById('stf-cost').value='45';
    document.getElementById('stf-base').value='A$45/h';
    finStaffAdd();
    const added=STAFF.length===n0+1&&STAFF[n0].name==='测试工'&&OPLOG[0].action==='添加工资人员';
    finStaffToggle(n0); uiOk();
    const off=STAFF[n0].active===false;
    const dim=document.getElementById('main').innerHTML.includes('已停用');
    STAFF.splice(n0,1); renderAll();
    return JSON.stringify({has,gate,added,off,dim,restore:STAFF.length===n0});});
  const f31=JSON.parse(w31f);
  ok(f31.has,'设置页缺「工资发放人员」管理面板');
  ok(f31.gate,'成本时薪不填建人未被拒（门禁）');
  ok(f31.added,'添加人员未生效/未进日志');
  ok(f31.off&&f31.dim,'停用留痕未生效（应标已停用置灰）');
  ok(f31.restore,'人员测试后未还原');
  const w31g=await page.evaluate(()=>{
    loginAs('presales'); go('presales','项目列表');
    const h=document.getElementById('main').innerHTML;
    const wiz=(h.match(/邮箱（选填）/g)||[]).length>=2;
    detOpen('KX-2026-0142','王宅');
    const dh=document.getElementById('detbody').innerHTML;
    const dr=(dh.match(/邮箱（选填）/g)||[]).length>=2&&dh.includes('mike@buildco.com.au');
    detClose(); loginAs('finance');
    const ppl=finPeople('KX-2026-0203');
    const b=ppl.find(p=>p.src==='Builder');
    return JSON.stringify({wiz,dr,cand:!!(b&&b.email&&b.phone)});});
  const g31=JSON.parse(w31g);
  ok(g31.wiz,'立项引导第3步缺邮箱（选填）栏（家庭成员/参建方）');
  ok(g31.dr,'修改抽屉缺邮箱列/参建方邮箱种子');
  ok(g31.cand,'付款人候选 Builder 未带电话邮箱（售前参建方采集）');
  // 6.11) 三十二轮：挂起补录 —— 入口在工程端「每日上报」，财务只读显示，补录进下月工时
  const w32=await page.evaluate(()=>{
    go('fin','工资数据');
    bfOpen('小陈','07/29','2026/07/29');                       // 财务兜底门禁：弹窗不开
    const finBlocked=!document.getElementById('bf-note');
    go('fin','财务节点');
    const finNoStuck=!document.getElementById('main').innerHTML.includes('日结挂起');
    const engTodo=TODOS.some(x=>x.dept==='eng'&&x.ev.includes('日结挂起')&&x.act.includes('每日工时管理'));
    loginAs('eng'); go('eng','总览');
    const engStuck=document.getElementById('main').innerHTML.includes('日结挂起 2 天');   // 三十九轮起由 engStuckRows 现算派生
    go('eng','每日工时管理');
    const eh=document.getElementById('main').innerHTML;
    const engPage=eh.includes('挂起待补录')&&eh.includes('07/29')&&eh.includes('07/30')
      &&document.querySelectorAll('#engbf tbody tr').length===2;
    bfOpen('小陈','07/29','2026/07/29');
    const opened=!!document.getElementById('bf-note');
    document.getElementById('bf-pj').value='KX-2026-0203';   // 五十轮：下拉改可搜可筛，先选好项目
    document.getElementById('bf-h').value='8';
    document.getElementById('bf-cat').value='';
    document.getElementById('bf-note').value='x';
    const n0=Object.keys(BACKFILL).length;
    bfConfirm('小陈','07/29','2026/07/29');                    // 类别空 → 拒
    const gCat=Object.keys(BACKFILL).length===n0;
    document.getElementById('bf-cat').value='忘打卡';
    bfConfirm('小陈','07/29','2026/07/29');                    // 说明<10字 → 拒
    const gNote=Object.keys(BACKFILL).length===n0;
    document.getElementById('bf-note').value='早上直接去了罗宅现场布线，忘记在 App 打卡，负责人核实确有出工';
    const bh0=hrAgg('KX-2026-0203').T.bh;
    bfConfirm('小陈','07/29','2026/07/29');                    // → 成功定格
    const done=!!BACKFILL['小陈|07/29'];
    const grow=hrAgg('KX-2026-0203').T.bh-bh0===8;
    const eh2=document.getElementById('main').innerHTML;
    const engDone=eh2.includes('已补录（本周期）')&&eh2.includes('忘打卡')
      &&document.querySelectorAll('#engbf tbody tr').length===1;
    const log=OPLOG[0].action==='补录日结'&&OPLOG[0].detail.includes('忘打卡');
    const noti=NOTIF[0].what.includes('日结补录');
    loginAs('finance'); go('fin','工资数据');
    const fh2=document.getElementById('main').innerHTML;
    const finShow=fh2.includes('已补录 · 滚下月补发')&&fh2.includes('忘打卡：')
      &&fh2.includes('挂起 · 无记录');                          // 07/30 仍挂
    payGridOpen=true; renderAll();
    const gh=document.getElementById('paygrid').innerHTML;
    const mark=gh.includes('°')&&gh.includes('挂 1 天');
    payGridOpen=false;
    delete BACKFILL['小陈|07/29']; NOTIF.shift(); renderAll();
    const restore=document.getElementById('main').innerHTML.split('挂起 · 无记录').length-1===2;
    return JSON.stringify({finBlocked,finNoStuck,engTodo,engStuck,engPage,opened,
      gCat,gNote,done,grow,engDone,log,noti,finShow,mark,restore});});
  const r32=JSON.parse(w32);
  ok(r32.finBlocked,'财务点补录未被拦（应指路 工程管理→每日工时管理）');
  ok(r32.finNoStuck,'财务节点卡点表不该再列日结挂起（财务只看不办）');
  ok(r32.engTodo&&r32.engStuck,'工程负责人缺提醒（待办条目/总览卡点指路每日工时管理）');
  ok(r32.engPage,'工程每日工时管理页缺挂起待补录表（应 2 行）');
  ok(r32.opened,'工程身份打开补录弹窗失败');
  ok(r32.gCat,'原因类别空未被拒');
  ok(r32.gNote,'详细说明<10字未被拒');
  ok(r32.done&&r32.grow,'补录未定格/未续进人力消耗（0203 应 +8h）');
  ok(r32.engDone,'工程端已补录列表未更新（应剩 1 行挂起）');
  ok(r32.log&&r32.noti,'补录未留操作日志/未通知财务');
  ok(r32.finShow,'财务侧未显示已补录琥珀标（悬停原因）/07-30 应仍挂');
  ok(r32.mark,'周期网格缺补录角标°/剩余挂天数未更新');
  ok(r32.restore,'补录测试后演示态未还原（应恢复 2 行挂起）');
  // 6.8) 二十二轮：付款人全息+下拉换人 · 昵称/完整地址 · 财务节点分布过滤
  await page.evaluate(()=>go('fin','项目收款S1-S3'));
  fh=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(fh.includes('payer-KX-2026-0203')&&fh.includes('联系人1'),'付款人缺下拉/来源标');
  ok(fh.includes('<b>罗宅</b>')&&fh.includes('3 Springdale Rd, Killara NSW'),'昵称/完整地址未按定稿口径');
  ok(!fh.includes('<b>Killara 罗宅</b>'),'昵称位置仍显示混合全称');
  const payChk=await page.evaluate(()=>{
    const sel=document.getElementById('payer-KX-2026-0188');
    const i=[...sel.options].findIndex(o=>o.text.includes('Builder'));
    sel.value=String(i); finSetPayer('KX-2026-0188');
    const f=finOf('KX-2026-0188');
    const h1=document.getElementById('main').innerHTML;
    go('fin','尾款结算S4与Var');
    const h2=document.getElementById('main').innerHTML;
    const r={name:f.payer,co:f.payerCo,src:f.payerSrc,
      s13:h1.includes('NorthBuild'),s4:h2.includes('NorthBuild'),
      log:OPLOG[0].action==='设置付款人'&&OPLOG[0].detail.includes('林先生（联系人1） → Sam（Builder）')};
    f.payer='林先生'; f.payerPh='0400 771 220'; f.payerEm='lin@x.com';
    f.payerCo=''; f.payerTi='业主'; f.payerSrc='联系人1'; renderAll();
    return JSON.stringify(r);});
  const pk=JSON.parse(payChk);
  ok(pk.name==='Sam'&&pk.co==='NorthBuild'&&pk.src==='Builder','换付款人未存全息信息');
  ok(pk.s13&&pk.s4,'换付款人后未全线生效（S1-3 与 S4 都要显示）');
  ok(pk.log,'设置付款人未留 前→后 日志');
  const nodeChk=await page.evaluate(()=>{go('fin','财务节点');
    const n0=document.querySelectorAll('#nodetbl tbody tr').length;
    nodeF='S1 请款中'; renderAll();
    const n1=document.querySelectorAll('#nodetbl tbody tr').length;
    const one=document.getElementById('main').innerHTML.includes('<b class="mono">KX-2026-0203</b>');
    nodeF='全部'; renderAll();
    return JSON.stringify({n0,n1,one});});
  const nk=JSON.parse(nodeChk);
  ok(nk.n0===5&&nk.n1===1&&nk.one,`节点分布过滤失效（全部应5行/S1请款中应1行，实际 ${nk.n0}/${nk.n1}）`);
  // 二十九轮：去处理 → 直接过滤出该项目（不要全列出来让人找）
  const goChk29=await page.evaluate(()=>{go('fin','财务节点');
    goPj('fin','项目收款S1-S3','KX-2026-0203');
    const a={page,rows:document.querySelectorAll('#main .bigtable tbody tr').length,
      q:document.getElementById('finq')?document.getElementById('finq').value:finQ};
    goPj('fin','尾款结算S4与Var','KX-2026-0142');
    const h4=document.getElementById('main').innerHTML;
    const b={page,q:finQ,only:h4.includes('KX-2026-0142')&&!h4.includes('KX-2026-0188')&&!h4.includes('KX-2026-0203')};
    goPj('fin','催账和停服','KX-2026-0160');
    const c={page,rows:document.querySelectorAll('#main table:not(#nodetbl) tbody tr').length};
    const cOk=document.getElementById('main').innerHTML.includes('KX-2026-0160')
      &&!document.getElementById('main').innerHTML.includes('MT-0121-11');
    go('fin','催账和停服');
    const cAll=document.querySelectorAll('#main table tbody tr').length;
    return JSON.stringify({a,b,c:{...c,cOk},cAll});});
  const g29=JSON.parse(goChk29);
  ok(g29.a.page==='项目收款S1-S3'&&g29.a.rows===1&&g29.a.q==='KX-2026-0203',
     `收款页去处理应过滤到 0203 单行，实际 ${g29.a.rows} 行`);
  ok(g29.b.page==='尾款结算S4与Var'&&g29.b.only,'S4 去处理应只剩 0142（不得出现其他项目）');
  ok(g29.c.cOk,'催账去处理应只剩 0160（维护单 0121 应被滤掉）');
  ok(g29.cAll>=3,'清空过滤后催账页应恢复全部单据');
  // 三十轮 bug 修复：过滤进来后点「全部」要真的显示全部（真实点击复现）
  await page.evaluate(()=>{goPj('fin','项目收款S1-S3','KX-2026-0203');});
  let nAll=await page.evaluate(()=>document.querySelectorAll('#main .bigtable tbody tr').length);
  ok(nAll===1,`过滤进来应 1 行，实际 ${nAll}`);
  await page.click('#main button:text-is("全部")');
  nAll=await page.evaluate(()=>({r:document.querySelectorAll('#main .bigtable tbody tr').length,q:finQ}));
  ok(nAll.r===5&&nAll.q==='',`点「全部」应清搜索显示 5 行，实际 ${nAll.r} 行 q='${nAll.q}'`);
  await page.evaluate(()=>{go('fin','项目列表');pjQ='0142';renderAll();});
  await page.click('#main button:text-is("全部")');
  nAll=await page.evaluate(()=>document.querySelectorAll('#main tbody tr').length);
  ok(nAll===11,`项目列表点「全部」应清搜索显示 11 行，实际 ${nAll}`);
  await page.evaluate(()=>{loginAs('presales');go('presales','项目状态表');bigQ='0186';renderAll();});
  await page.click('#main button:text-is("全部")');
  nAll=await page.evaluate(()=>{const n=document.querySelectorAll('#main .bigtable tbody tr').length;
    loginAs('finance');return n;});
  ok(nAll===7,`售前状态表点「全部」应清搜索显示 7 行，实际 ${nAll}`);
  const cmChk=await page.evaluate(()=>{go('fin','成本与利润率');
    return document.getElementById('main').innerHTML.includes('<b>张宅</b>');});
  ok(cmChk,'成本利润率页昵称未按口径');
  // 6.13) 三十五轮：项目分布地图（经纬度落位 · 利润率四档色点 · 点选弹窗）
  const w35=await page.evaluate(()=>{go('fin','成本与利润率');
    const h=document.getElementById('main').innerHTML;
    const svg=document.getElementById('pmap');
    const dots=svg?svg.querySelectorAll('circle[style]').length:0;   // 项目色点（带 cursor 样式）
    const colors=h.includes('fill="#dc2626"')&&h.includes('fill="#047857"')&&h.includes('fill="#b45309"');
    const legend=!!document.getElementById('maplegend');
    mapPick('KX-2026-0142');
    const h2=document.getElementById('pmap').innerHTML;
    const bubble=h2.includes('王宅')&&h2.includes('8 Franklin Rd, Cherrybrook NSW')&&h2.includes('59.1%');
    mapPick('KX-2026-0142');                            // 再点=关闭
    const closed=!document.getElementById('pmap').innerHTML.includes('8 Franklin Rd, Cherrybrook NSW');
    const gnote=document.getElementById('main').innerHTML.includes('Google 地图');
    return JSON.stringify({dots,colors,legend,bubble,closed,gnote});});
  const r35=JSON.parse(w35);
  ok(r35.dots===9,`分布图应 9 个项目色点，实际 ${r35.dots}`);
  ok(r35.colors,'色点未按利润率四档配色（缺红/绿/橙）');
  ok(r35.legend,'缺利润率颜色图例');
  ok(r35.bubble,'点选弹窗缺 昵称/完整地址/利润率');
  ok(r35.closed,'再点一次未关闭弹窗');
  ok(r35.gnote,'缺「正式系统接 Google 地图」说明');
  // 6.14) 三十六轮：操作日志上下游种子 + 九页「这页怎么用」帮助 + 去「？」
  const w36=await page.evaluate(()=>{
    go('fin','操作日志');
    const lh=document.getElementById('main').innerHTML;
    const updown=lh.includes('勾「已签约」')&&lh.includes('未退料计提')
      &&lh.includes('维护上门完成')&&lh.includes('出库计入项目成本')&&lh.includes('SM3 检查布线完成');
    const pages=['财务节点','项目收款S1-S3','尾款结算S4与Var','运维财务支持','催账和停服','工资数据','项目报销','成本与利润率','设置'];
    const helpAll=pages.every(p=>{go('fin',p);
      const h=HELP['fin/'+p]; return h&&JSON.stringify(h.notes||h).includes('这页怎么用');});
    const side=document.getElementById('side').innerHTML;
    const noQ=!side.includes('？ 帮助')&&side.includes('>帮助（本页说明）<');
    const noQ2=!document.getElementById('main').innerHTML.includes('「？ 帮助」');
    return JSON.stringify({updown,helpAll,noQ,noQ2});});
  const r36=JSON.parse(w36);
  ok(r36.updown,'财务操作日志缺上下游事件（签约/未退料/维护完成/出库/SM3）');
  ok(r36.helpAll,'九个财务页面的帮助缺「这页怎么用」总结');
  ok(r36.noQ&&r36.noQ2,'「？」未去干净（左栏按钮或页内引用）');
  // 7) 四十五轮：Site Meeting 总表+过滤+详细 · 现场记录浮窗 · 排期=派工（带日期）· App 提交完成
  const w45=await page.evaluate(()=>{
    loginAs('eng'); smF='全部'; smQ=''; smDetail=null; go('eng','Site Meeting');
    const h=document.getElementById('main').innerHTML;
    const tblRows=document.querySelectorAll('#smtbl tbody tr').length;      // 7 个进工程线的项目
    const cols=document.querySelectorAll('#smtbl thead th').length;         // 编号/立项/项目/阶段/SM1-4/门禁/详细=10
    const statuses=h.includes('🔒')&&h.includes('已排期')&&h.includes('未排期')&&h.includes('不适用');
    const gate=h.includes('S2 卡住')&&h.includes('S3 已解锁');
    // 过滤：一次一个项目
    smF='KX-2026-0203'; renderAll();
    const one=document.querySelectorAll('#smtbl tbody tr').length===1;
    const autoDetail=smDetail===null;                                       // 下拉才自动设；这里直接改变量
    smF='全部'; smDetail='KX-2026-0203'; renderAll();
    const detail=document.getElementById('main').innerHTML.includes('罗宅 · 四场会详细')
      &&document.getElementById('main').innerHTML.includes('SM1 进场');
    // 现场记录浮窗（已完成场次）
    smRecOpen('KX-2026-0188',3);
    const rp=document.getElementById('rpbox').innerHTML;
    const recOk=document.getElementById('rpbox').style.display==='block'
      &&rp.includes('现场记录')&&rp.includes('逐路验线')&&rp.includes('data:image/svg')
      &&rp.includes('到场打卡')&&rp.includes('围栏外打卡');
    schRepClose();
    // 排期＝派工（带日期、参会人多选、写进排班表）
    const n0=SCH.length;
    smSchedO('KX-2026-0203',2);
    const opened=!!document.getElementById('sm-d');
    const hasDate=document.getElementById('sm-d').type==='date';
    const noPjPicker=!document.getElementById('sm-pj');                      // 项目不用再选
    const d=new Date(); d.setDate(d.getDate()+14);
    const ds=ymdS(d);
    document.getElementById('sm-d').value=ds.replace(/\//g,'-');
    document.getElementById('sm-st').value='09:00';
    document.getElementById('sm-et').value='12:00';
    [...document.querySelectorAll('.sm-who')].forEach(c=>{c.checked=(c.value==='陈工'||c.value==='阿强');});
    smSchedSave();
    const made=SCH.filter(x=>x.d===ds&&x.type==='Site Meeting'&&x.pj==='KX-2026-0203');
    const schedOk=made.length===2&&made[0].st==='09:00'&&made[0].et==='12:00'&&made.every(x=>x.ack===false);
    const smSched=SMD['KX-2026-0203'].sm[1].sched===ds+' 09:00';
    const logOk=OPLOG[0].action==='SM2 排期'&&OPLOG[0].detail.includes('写进派工排班表');
    // App 提交完成 → 定格 + 解锁财务
    const f=finOf('KX-2026-0203');
    smAppDone('KX-2026-0203',3);                                            // SM2 未完成 → 顺序门禁拦
    const seq=!SMD['KX-2026-0203'].sm[2].done;
    smAppDone('KX-2026-0203',2); uiOk();
    const sm2=!!SMD['KX-2026-0203'].sm[1].done;
    smAppDone('KX-2026-0203',3); uiOk();
    const sm3=!!SMD['KX-2026-0203'].sm[2].done&&f.sm3===true;
    const appMark=SMD['KX-2026-0203'].sm[2].by.includes('App 提交')
      &&SMD['KX-2026-0203'].sm[2].elecSign.includes('App 现场签字');
    loginAs('finance'); go('fin','项目收款S1-S3');
    const finOk=!document.getElementById('main').innerHTML.includes('SM3 未完成，不能发起 S2');
    // 还原
    loginAs('eng');
    SMD['KX-2026-0203'].sm[1]={sched:'2026/08/05 09:00',chk:[1,1,1]};
    SMD['KX-2026-0203'].sm[2]={chk:[0,0,0]};
    f.sm3=false; SCH.splice(n0,2); OPLOG.splice(0,3); NOTIF.splice(0,3);
    smF='全部'; smDetail=null; renderAll(); loginAs('finance');
    return JSON.stringify({tblRows,cols,statuses,gate,one,detail,recOk,opened,hasDate,noPjPicker,
      schedOk,smSched,logOk,seq,sm2,sm3,appMark,finOk});});
  const r45=JSON.parse(w45);
  ok(r45.tblRows===9&&r45.cols===10,`SM 总表行列不对（${r45.tblRows} 行 / ${r45.cols} 列）`);
  ok(r45.statuses,'SM 总表四种状态未齐（完成/已排期/未排期/不适用）');
  ok(r45.gate,'SM 总表缺下游门禁列');
  ok(r45.one,'项目过滤未生效（一次只筛一个）');
  ok(r45.detail,'点详细未展开该项目四张卡');
  ok(r45.recOk,'现场记录浮窗缺记录/照片/打卡');
  ok(r45.opened&&r45.hasDate&&r45.noPjPicker,'排期浮窗缺日期字段/不该再选项目');
  ok(r45.schedOk&&r45.smSched,'排期未按参会人写进排班表/未回写 SM 排期');
  ok(r45.logOk,'排期未留痕（写进派工排班表）');
  ok(r45.seq,'顺序门禁失效（SM2 未完成竟能完成 SM3）');
  ok(r45.sm2&&r45.sm3&&r45.appMark,'App 提交完成未定格/未标注 App 来源');
  ok(r45.finOk,'SM3 完成未解锁财务 S2');
  // 三十八轮：入场离场=每人×每天×每任务——SM 每场会显示到场打卡（App 采集，这页只展示）
  const w38=await page.evaluate(()=>{
    loginAs('eng'); smF='全部'; smDetail='KX-2026-0188'; go('eng','Site Meeting');
    const h=document.getElementById('main').innerHTML;
    smRecOpen('KX-2026-0188',3);
    const rp=document.getElementById('rpbox').innerHTML; schRepClose();
    smDetail=null; renderAll(); loginAs('finance');
    return JSON.stringify({
      att:h.includes('到场打卡（每人 · 本场任务 · App 采集）')&&h.includes('Leo(电工) 09:45–11:30')
        &&rp.includes('入场 – 离场'),
      flag:h.includes('围栏外打卡·已确认')&&rp.includes('围栏外打卡'),
      layer:JSON.stringify(HELP['eng/Site Meeting']||{}).includes('入场离场是底层通用动作'),
      collect:h.includes('排期后参会人各自在 App 打卡')});});
  const r38=JSON.parse(w38);
  ok(r38.att,'SM 已完成卡缺到场打卡记录（每人·本场任务）');
  ok(r38.flag,'围栏外异常标记未显示');
  ok(r38.layer&&r38.collect,'帮助/未完成卡缺「入场离场=通用层，采集在 App」说明');
  // 三十九轮：工程总览重做（双计数+停留超阈值 · 派工按小时 · 挂起 · 超期交接 · 卡点汇总）
  const w39=await page.evaluate(()=>{
    loginAs('eng'); go('eng','总览');
    const h=document.getElementById('main').innerHTML;
    const five=h.includes('在建项目')&&h.includes('维护项目')&&h.includes('今日派工')
      &&h.includes('未记录工时')&&h.includes('超期交接');
    const noRenci=!h.includes('人次')||h.includes('人次没有意义');   // 卡片不得再用人次
    const hours=h.includes('38 h');                                  // 今日派工=小时合计
    const bOver=h.includes('1 个停留超 120 天'), mOver=h.includes('1 个停留超 90 天');
    // 卡片点开明细
    engPick('build');
    const bd=document.getElementById('main').innerHTML;
    const bdOk=bd.includes('在建项目 · 状态停留')&&bd.includes('赵宅')&&bd.includes('超 ');
    engPick('dispatch');
    const dd=document.getElementById('main').innerHTML;
    const ddOk=dd.includes('今日派工明细')&&dd.includes('10 h')&&dd.includes('38 h')&&dd.includes('外包');
    engPick('handoff');
    const hd=document.getElementById('main').innerHTML;
    const hdOk=hd.includes('交接审批')&&hd.includes('HO-0142-07')&&hd.includes('确认接收')&&hd.includes('催办');
    const n0=HANDOFF.filter(x=>!x.ack).length;
    hoAck('HO-0142-07');
    const ackOk=HANDOFF.find(x=>x.id==='HO-0142-07').ack&&OPLOG[0].action==='确认接收交接'
      &&HANDOFF.filter(x=>!x.ack).length===n0-1;
    const cardAfter=document.getElementById('main').innerHTML.includes('超期交接');
    engPick('handoff');                                              // 收起
    const stuck=document.querySelectorAll('#engstuck tbody tr').length;
    const sh=document.getElementById('main').innerHTML;
    const stuckMix=sh.includes('在建停留')&&sh.includes('维护停留')&&sh.includes('日结挂起')
      &&sh.includes('交接未确认')&&sh.includes('安装剩余');
    // 还原
    const hh=HANDOFF.find(x=>x.id==='HO-0142-07'); hh.ack=false; hh.ackAt=undefined; hh.ackBy=undefined;
    OPLOG.shift(); engCard=null; loginAs('finance');
    return JSON.stringify({five,noRenci,hours,bOver,mOver,bdOk,ddOk,hdOk,ackOk,cardAfter,stuck,stuckMix});});
  const r39=JSON.parse(w39);
  ok(r39.five,'工程总览五块卡片不全');
  ok(r39.noRenci,'今日派工仍在用「人次」');
  ok(r39.hours,'今日派工未按小时合计（应 38 h）');
  ok(r39.bOver&&r39.mOver,'在建/维护停留超阈值计数未显示');
  ok(r39.bdOk,'点开在建停留明细失败（应含赵宅+超阈值）');
  ok(r39.ddOk,'点开今日派工明细失败（应含外包 10h 与合计 38h）');
  ok(r39.hdOk,'点开交接审批明细失败（确认/催办按钮）');
  ok(r39.ackOk,'确认接收交接未生效/未留痕');
  ok(r39.stuck>=5&&r39.stuckMix,`卡点表未汇总全部异常（实际 ${r39.stuck} 行）`);
  // 四十轮：工程设置阈值统一可调 + 工程项目列表（六态/阶段列/隐藏金额/负责人指定）
  const w40=await page.evaluate(()=>{
    loginAs('eng'); go('eng','设置');
    const sh=document.getElementById('main').innerHTML;
    const setOk=sh.includes('在建项目（施工中）停留天数')&&sh.includes('维护项目（项目维护中）停留天数')
      &&sh.includes('交接确认 SLA')&&sh.includes('打卡围栏半径');
    engSetVal('maintStallDays','维护停留天数',300);   // 刘宅停留 205 天 → 阈值 300 后不再超
    go('eng','总览');
    const mNo=document.getElementById('main').innerHTML.includes('无停留超阈值')
      &&engStay('maint').every(x=>!x.over);
    const logOk=OPLOG[0].action==='修改工程设置';
    engSetVal('maintStallDays','维护停留天数',90); OPLOG.shift(); OPLOG.shift();
    go('eng','项目列表');
    const h=document.getElementById('main').innerHTML;
    const six=['全部','Site Meeting 阶段','施工中','项目交付','项目维护','已停服'].every(s=>h.includes('>'+s));
    const noMoney=!h.includes('合同额')&&!h.includes('已收')&&!h.includes('利润率');
    const scope=h.includes('罗宅')&&h.includes('张宅')&&!h.includes('黄宅')&&!h.includes('李宅');
    const stageCol=h.includes('工程进度（当前阶段）')&&h.includes('SM 1/4 已完成')&&h.includes('SM1~4 已过');
    const susp=h.includes('已停服')&&h.includes('款项未到位');
    const rows0=document.querySelectorAll('#engpj tbody tr').length;
    engPjF='Site Meeting 阶段'; renderAll();
    const smRows=document.querySelectorAll('#engpj tbody tr').length;
    engPjF='已停服'; renderAll();
    const spRows=document.querySelectorAll('#engpj tbody tr').length;
    const spOnly=document.getElementById('main').innerHTML.includes('张宅');
    engPjF='全部'; renderAll();
    // 负责人指定：候选下拉 + 保存定为标注 + 留痕通知
    engLeadToggle('KX-2026-0203');
    const box=document.getElementById('el-b-KX-2026-0203');
    const hasCand=!!box&&[...box.options].some(o=>o.text.includes('MetroCon'));
    box.value='Ken · MetroCon';
    document.getElementById('el-e-KX-2026-0203').value='Leo · VoltPro';
    engLeadSave('KX-2026-0203');
    const L=ENG_LEAD['KX-2026-0203'];
    const saved=L&&L.fixed&&L.builder==='Ken · MetroCon'&&L.elec==='Leo · VoltPro';
    const pin=document.getElementById('main').innerHTML.includes('📌')&&document.getElementById('main').innerHTML.includes('工程指定 · 陈工');
    const lg=OPLOG[0].action==='指定项目负责人'&&OPLOG[0].detail.includes('Builder Mike · BuildCo → Ken · MetroCon');
    const nt=NOTIF[0].what.includes('工程指定负责人');
    delete ENG_LEAD['KX-2026-0203']; OPLOG.shift(); NOTIF.shift(); engLeadOpen=null; renderAll();
    loginAs('finance');
    return JSON.stringify({setOk,mNo,logOk,six,noMoney,scope,stageCol,susp,rows0,smRows,spRows,spOnly,hasCand,saved,pin,lg,nt});});
  const r40=JSON.parse(w40);
  ok(r40.setOk,'工程设置缺四个阈值字段');
  ok(r40.mNo&&r40.logOk,'改阈值未即时生效/未留痕');
  ok(r40.six,'工程项目列表六态筛选不全');
  ok(r40.noMoney,'工程项目列表仍显示金额列（应全部隐藏）');
  ok(r40.scope,'工程列表范围错（应只含进了工程线的项目）');
  ok(r40.stageCol,'工程进度列未显示当前阶段明细');
  ok(r40.susp,'「已停服」态未显示（取代已流失/已烂尾）');
  ok(r40.rows0===9&&r40.smRows===2&&r40.spRows===1&&r40.spOnly,
     `阶段筛选计数错（全部 ${r40.rows0}/应9 · SM阶段 ${r40.smRows}/应2 · 已停服 ${r40.spRows}/应1）`);
  ok(r40.hasCand,'负责人候选下拉未带售前采集值');
  ok(r40.saved&&r40.pin,'指定负责人未保存/未固定为📌标注');
  ok(r40.lg&&r40.nt,'指定负责人未留前后痕/未通知下游');
  // 四十一轮：派工排班（周视图 · 五类 · 15分钟 · 门禁 · 锁定 · 取消回Yes · 剩余工作 · 上报记录）
  const w41=await page.evaluate(()=>{
    loginAs('eng'); schOff=0; go('eng','派工排班');
    const h=document.getElementById('main').innerHTML;
    const grid=!!document.getElementById('schgrid');
    const types=['Site Meeting','安装','交付','维护','倒休'].every(k=>h.includes('>'+k+'<'));
    const rows=document.querySelectorAll('#schgrid tbody tr').length;      // 4 名在职
    const cols=document.querySelectorAll('#schgrid thead th').length;      // 人员+7天+合计=9
    const hasPop=h.includes('剩余工作：')&&h.includes('class="pop"');
    const wk=h.includes('本周合计');
    // 门禁①：过去的日子不能排
    const days=weekDays(0).map(d=>ymdS(d));
    const past=days.find(d=>d<todayS());
    let g1=true; if(past){ schAdd('阿强',past); g1=!document.getElementById('sc-st'); }
    // 正常新增（未来日）：必须选项目
    const fut=weekDays(1).map(d=>ymdS(d))[2];
    schAdd('阿强',fut);
    const opened=!!document.getElementById('sc-st');
    document.getElementById('sc-t').value='安装'; schPjToggle();
    document.getElementById('sc-pj').value='';
    document.getElementById('sc-st').value='09:00';
    document.getElementById('sc-et').value='10:30';   // 90 分
    const n0=SCH.length; schSave();
    const g2=SCH.length===n0;                                            // 无项目 → 拦
    document.getElementById('sc-pj').value='KX-2026-0188';
    document.getElementById('sc-note').value='花园廊架灯控';
    document.getElementById('sc-rem').value='灯带未接线';
    schSave();
    const L=SCH[SCH.length-1];
    const added=SCH.length===n0+1&&L.min===90&&L.st==='09:00'&&L.et==='10:30'&&L.pj==='KX-2026-0188';
    const notiAdd=NOTIF[0].what.includes('新排工')&&NOTIF[0].to[0].how==='App 通知';
    const logAdd=OPLOG[0].action==='新增排班';
    // 倒休余额门禁：老李余额 4h，排 8h → 拦
    schAdd('老李',fut);
    document.getElementById('sc-t').value='倒休'; schPjToggle();
    document.getElementById('sc-st').value='09:00';
    document.getElementById('sc-et').value='17:00';   // 8h 倒休 > 余额
    const n1=SCH.length; schSave();
    const g3=SCH.length===n1; schClose();
    // 时长换算
    const lab=minLab(90)==='1.5 h（1h30m）'&&minLab(45)==='45 分';
    // 删除 → 取消待确认 + 回 Yes
    const tid=SCH[SCH.length-1].id;
    schEdit(tid); schDel(tid); uiOk();
    const delOk=!SCH.some(s=>s.id===tid)&&SCH_CANCEL.length>0&&SCH_CANCEL[0].ack===false;
    const notiDel=NOTIF[0].what.includes('排班取消')&&NOTIF[0].to[0].how==='短信 + App';
    schCancelAck(0);
    const ackOk=SCH_CANCEL[0].ack===true&&OPLOG[0].action==='取消排班已确认';
    // 锁定：整周锁 → 不能改
    schOff=1; renderAll(); schLockWeek();
    const wkLocked=!!SCH_WEEK[ymdS(weekDays(1)[0])];
    schAdd('阿强',fut);
    const g4=!document.getElementById('sc-st');
    schLockWeek();                                                        // 解锁还原
    // 项目上报记录
    schRepOpen('KX-2026-0188');
    const rp=document.getElementById('rpbox').innerHTML;
    const repOk=document.getElementById('rpbox').style.display==='block'
      &&rp.includes('此前工程上报记录')&&rp.includes('SM3 检查布线完成');
    schRepClose();
    // 还原演示态
    SCH_CANCEL.length=0; OPLOG.splice(0,3); NOTIF.splice(0,2); schOff=0; renderAll();
    loginAs('finance');
    return JSON.stringify({grid,types,rows,cols,hasPop,wk,g1,opened,g2,added,notiAdd,logAdd,g3,lab,delOk,notiDel,ackOk,wkLocked,g4,repOk});});
  const r41=JSON.parse(w41);
  ok(r41.grid&&r41.rows===4&&r41.cols===9,`排班周视图网格不对（行 ${r41.rows}/应4 · 列 ${r41.cols}/应9）`);
  ok(r41.types,'五类任务图例不全');
  ok(r41.hasPop&&r41.wk,'缺悬停浮窗（剩余工作）或本周合计列');
  ok(r41.g1,'过去日期竟可排班（应门禁拦）');
  ok(r41.opened,'未来日期打不开排班弹层');
  ok(r41.g2,'无项目任务未被拦（不允许无项目关联的工作）');
  ok(r41.added,'新增任务失败/15 分钟对齐失效（95→90）');
  ok(r41.notiAdd&&r41.logAdd,'新排工未通知本人/未留痕');
  ok(r41.g3,'倒休余额不足未被拦');
  ok(r41.lab,'时长换算错（90→1.5h · 45→45 分）');
  ok(r41.delOk&&r41.notiDel,'取消任务未进待确认/未发短信+App');
  ok(r41.ackOk,'取消回 Yes 未确认留痕');
  ok(r41.wkLocked&&r41.g4,'整周锁定后仍可改（应拦）');
  ok(r41.repOk,'项目上报记录弹层缺失');
  // 四十二轮：红绿点确认 · 点人名看当天路线 · 合理时长 · 全浮窗录入；+ 工程总览「去处理」直达过滤
  const w42=await page.evaluate(()=>{
    loginAs('eng'); schOff=0; go('eng','派工排班');
    const h=document.getElementById('main').innerHTML;
    const dots=h.includes('等本人回 Y')&&h.includes('日程已同步到本人 App');
    const ackTbl=!!document.getElementById('schack');
    const routeLink=h.includes('schRouteOpen(');
    // 路线弹层：A/B/C/D
    const days=weekDays(0).map(d=>ymdS(d));
    const wed=days[2];
    schRouteOpen('阿强',wed);
    const rt=document.getElementById('rtbox').innerHTML;
    const routeOk=document.getElementById('rtbox').style.display==='block'&&rt.includes('当天站点与路线')&&rt.includes('Google 地图');
    schRouteClose();
    schRouteOpen('陈工',wed);
    const rt2=document.getElementById('rtbox').innerHTML;
    const abOk=rt2.includes('>A<');
    schRouteClose();
    // 红点 → 回 Y 变绿
    const red=SCH.find(x=>!x.ack);
    const before=red?red.ack:null;
    if(red) schAckYes(red.id);
    const green=red?red.ack===true&&OPLOG[0].action==='排班确认回执':false;
    // 合理时长：设置里改 → 派工弹层提示跟着变
    go('eng','设置');
    const normUI=document.getElementById('main').innerHTML.includes('合理时长参考');
    engNormVal('Site Meeting',240);
    const normOk=SCH_NORM['Site Meeting']===240&&OPLOG[0].action==='修改合理时长';
    engNormVal('Site Meeting',180); OPLOG.splice(0,2);
    // 工程总览「去处理」→ 只显示该项目（bug 修复验证）
    go('eng','总览');
    goPj('eng','项目列表','KX-2026-0170');
    const one=document.querySelectorAll('#engpj tbody tr').length===1
      &&document.getElementById('main').innerHTML.includes('赵宅')&&engPjQ==='KX-2026-0170';
    engPjF='施工中'; engPjQ=''; renderAll();       // 点任一筛选 → 恢复该筛选完整内容
    const back=document.querySelectorAll('#engpj tbody tr').length===3;   // 施工中：赵宅/周宅/吴宅
    engPjF='全部'; renderAll();
    const all=document.querySelectorAll('#engpj tbody tr').length===9;
    if(red&&before===false){ red.ack=false; red.ackAt=undefined; }
    renderAll(); loginAs('finance');
    return JSON.stringify({dots,ackTbl,routeLink,routeOk,abOk,green,normUI,normOk,one,back,all});});
  const r42=JSON.parse(w42);
  ok(r42.dots&&r42.ackTbl,'红绿点/日程确认状态清单缺失');
  ok(r42.routeLink&&r42.routeOk&&r42.abOk,'点人名看当天路线（A/B/C/D + Google 说明）缺失');
  ok(r42.green,'回 Y 未把红点变绿/未留痕');
  ok(r42.normUI&&r42.normOk,'合理时长未可在设置定义/未留痕');
  ok(r42.one,'工程总览「去处理」未直达只显示该项目（三十九轮 bug）');
  ok(r42.back&&r42.all,'点筛选 chip 未恢复该筛选完整内容');
  // 四十三轮：排班弹层四修（倒休精简 · 项目可搜 · 内容多行 · 剩余工作自动生成）
  const w43=await page.evaluate(()=>{
    loginAs('eng'); schOff=1; go('eng','派工排班');
    const fut=weekDays(1).map(d=>ymdS(d))[3];
    schAdd('小陈',fut);
    // 倒休：不该有项目/内容/剩余
    document.getElementById('sc-t').value='倒休'; schPjToggle();
    const toilOk=document.getElementById('sc-pjwrap').style.display==='none'
      &&document.getElementById('sc-notewrap').style.display==='none'
      &&document.getElementById('sc-remwrap').style.display==='none';
    // 安装：项目可搜 + 剩余自动带出上次上报
    document.getElementById('sc-t').value='安装'; schPjToggle();
    const n0=document.getElementById('sc-pj').options.length;
    document.getElementById('sc-pjq').value='mosman'; schPjFilter();
    const n1=document.getElementById('sc-pj').options.length;
    const filtered=n0>n1&&n1===1&&document.getElementById('sc-pj').value==='KX-2026-0188';
    const remAuto=document.getElementById('sc-rem').textContent.includes('二楼走廊感应器对码未完')
      &&document.getElementById('sc-remsrc').textContent.includes('阿强 08/01');
    const multi=document.getElementById('sc-note').tagName==='TEXTAREA';
    // SM：无剩余工作
    document.getElementById('sc-t').value='Site Meeting'; schPjToggle();
    const smNo=document.getElementById('sc-rem').textContent.includes('SM 阶段不存在剩余工作');
    // 维护：第一次 → 无；有上次剩余 → 自动带；上次没填 → 门禁拦
    document.getElementById('sc-t').value='维护'; schPjToggle();
    document.getElementById('sc-pjq').value='王宅'; schPjFilter();
    const mtCarry=document.getElementById('sc-rem').textContent.includes('主卧面板偶发失联');
    document.getElementById('sc-pjq').value='刘宅'; schPjFilter();
    const mtGap=document.getElementById('sc-rem').textContent.includes('没有留下剩余工作记录');
    document.getElementById('sc-st').value='09:00';
    document.getElementById('sc-et').value='11:00';
    const c0=SCH.length; schSave();
    const mtBlocked=SCH.length===c0;                      // 上次没填 → 拦
    document.getElementById('sc-pjq').value='王宅'; schPjFilter();
    schSave();
    const saved=SCH.length===c0+1&&SCH[SCH.length-1].remain.includes('主卧面板偶发失联');
    // 倒休保存不带内容/剩余
    schAdd('小陈',fut);                                   // 小陈倒休余额 12.5h（老李 4h 本周已排满）
    document.getElementById('sc-t').value='倒休'; schPjToggle();
    document.getElementById('sc-st').value='13:00';
    document.getElementById('sc-et').value='15:00'; schSave();
    const tl=SCH[SCH.length-1];
    const toilSaved=tl.type==='倒休'&&tl.pj===''&&tl.note===''&&tl.remain==='';
    SCH.splice(c0,2); OPLOG.splice(0,2); NOTIF.splice(0,2); schOff=0; renderAll(); loginAs('finance');
    return JSON.stringify({toilOk,filtered,remAuto,multi,smNo,mtCarry,mtGap,mtBlocked,saved,toilSaved});});
  const r43=JSON.parse(w43);
  ok(r43.toilOk,'倒休仍显示项目/工作内容/剩余工作（应只填时长）');
  ok(r43.filtered,'关联项目不支持搜索过滤');
  ok(r43.multi,'工作内容仍是单行输入（应多行大框）');
  ok(r43.remAuto,'剩余工作未自动带出上次每日上报的剩余');
  ok(r43.smNo,'SM 阶段未标明「不存在剩余工作」');
  ok(r43.mtCarry,'维护未带出上次维护的剩余');
  ok(r43.mtGap&&r43.mtBlocked,'上次维护没填剩余时未提示/未拦下派工');
  ok(r43.saved,'保存后剩余工作未写入任务');
  ok(r43.toilSaved,'倒休任务保存时不该带项目/内容/剩余');
  // 四十四轮：每段活有起止时间（开始灵活/截止 15 分钟档）· 时长自动算 · 同人当天不许重叠
  const w44=await page.evaluate(()=>{
    loginAs('eng'); schOff=0; go('eng','派工排班');
    const h=document.getElementById('main').innerHTML;
    const shown=h.includes('10:00–19:45')&&h.includes('07:30–16:00');       // 格子显示起止
    const late=SCH.find(x=>x.st==='10:00'&&x.et==='19:45');                 // 用户举例：上午休息 10 点开工
    const lateOk=!!late&&late.min===585;
    const fut=weekDays(1).map(d=>ymdS(d))[4];
    schAdd('阿强',fut);
    const slots=[...document.getElementById('sc-et').options].map(o=>o.value);
    const grid15=slots.includes('16:15')&&slots.includes('16:30')&&!slots.includes('16:20');
    document.getElementById('sc-t').value='安装'; schPjToggle();
    document.getElementById('sc-pjq').value='mosman'; schPjFilter();
    document.getElementById('sc-st').value='10:00';
    document.getElementById('sc-et').value='09:00'; schMinPrev();           // 倒挂
    const badPrev=document.getElementById('sc-prev').textContent.includes('截止时间必须晚于开始时间');
    const n0=SCH.length; schSave();
    const g1=SCH.length===n0;
    document.getElementById('sc-et').value='18:45'; schMinPrev();
    const prevOk=document.getElementById('sc-prev').textContent.includes('8.75 h');
    schSave();
    const saved=SCH.length===n0+1&&SCH[SCH.length-1].min===525;
    // 重叠门禁：同一人同一天再排 14:00–16:00（落在 10:00–18:45 内）
    schAdd('阿强',fut);
    document.getElementById('sc-t').value='安装'; schPjToggle();
    document.getElementById('sc-pjq').value='mosman'; schPjFilter();
    document.getElementById('sc-st').value='14:00';
    document.getElementById('sc-et').value='16:00';
    const n1=SCH.length; schSave();
    const g2=SCH.length===n1;
    // 不重叠可排：19:00–20:00
    document.getElementById('sc-st').value='19:00';
    document.getElementById('sc-et').value='20:00'; schSave();
    const g3=SCH.length===n1+1;
    SCH.splice(n0,2); OPLOG.splice(0,2); NOTIF.splice(0,2); schOff=0; renderAll(); loginAs('finance');
    return JSON.stringify({shown,lateOk,grid15,badPrev,g1,prevOk,saved,g2,g3});});
  const r44=JSON.parse(w44);
  ok(r44.shown,'格子未显示起止时间');
  ok(r44.lateOk,'上午休息 10 点开工的实况未落进演示（10:00–19:45 = 9.75h）');
  ok(r44.grid15,'截止时间不是 15 分钟一档');
  ok(r44.badPrev&&r44.g1,'截止早于开始未提示/未拦');
  ok(r44.prevOk&&r44.saved,'起止时长自动算错（10:00–18:45 应 8.75h）');
  ok(r44.g2,'同一人当天时间重叠未被拦');
  ok(r44.g3,'不重叠的第二段应能排进去');
  // 四十六~四十七轮：安装调试页（只列 SM4~交付前 · 工时占比四档 · 资源分配→排班 · 两张环形图）
  const w46=await page.evaluate(()=>{
    loginAs('eng'); go('eng','安装调试');
    const h=document.getElementById('main').innerHTML;
    const rows=document.querySelectorAll('#insttbl tbody tr').length;
    // 四十八轮起：施工已结束的项目转入「交付」页，不再留在安装调试（吴宅已进交付流程）
    const onlyInst=h.includes('赵宅')&&h.includes('周宅')
      &&!h.includes('吴宅')&&!h.includes('林宅')&&!h.includes('王宅');
    const cols=h.includes('剩余工作量')&&h.includes('已投入工时')&&h.includes('预计总工时')&&h.includes('工时占比');
    const pcts=h.includes('66%')&&h.includes('95%');
    const bands=h.includes('充裕')&&h.includes('接近超支 · 预警');
    const negLeft=h.includes('13 h')&&h.includes('102 h');   // 周宅余 13h · 赵宅余 102h
    const remainAuto=h.includes('地暖联动剩 3 处未调')&&h.includes('来源：老李 08/01 的每日上报');
    // 两张环形图（四十七轮）
    const two=h.includes('项目状态分布')&&h.includes('合计工时对比')&&!h.includes('class="cards"');
    const svgs=document.querySelectorAll('#main svg').length>=2;
    const tips=(h.match(/<title>/g)||[]).length>=4;
    const legend=(h.includes('充裕 &lt;70%')||h.includes('充裕 <70%'))
      &&h.includes('已投入工时')&&h.includes('剩余预算工时');
    const center=h.includes('79.5%');   // (198+247)/(300+260)
    // 改预警线 → 档位与图例跟着变
    engSetVal('hourWarnPct','工时预警阈值%',97);
    const h2=document.getElementById('main').innerHTML;
    const rebanded=h2.includes('正常 70~97%')&&engSet.hourWarnPct===97;
    engSetVal('hourWarnPct','工时预警阈值%',90); OPLOG.splice(0,2);
    // 资源分配 → 写进排班表
    const n0=SCH.length;
    instO('KX-2026-0195');
    const opened=!!document.getElementById('in-d');
    const preFill=document.getElementById('in-note').value.includes('地暖联动剩 3 处未调');
    const d=new Date(); d.setDate(d.getDate()+3); const ds=ymdS(d);
    document.getElementById('in-d').value=ds.replace(/\//g,'-');
    document.getElementById('in-st').value='08:00';
    document.getElementById('in-et').value='16:30';
    [...document.querySelectorAll('.in-who')].forEach(c=>{c.checked=(c.value==='阿强'||c.value==='老李');});
    instSave();
    const made=SCH.filter(x=>x.d===ds&&x.type==='安装'&&x.pj==='KX-2026-0195');
    const schedOk=made.length===2&&made[0].st==='08:00'&&made[0].et==='16:30'
      &&made.every(x=>x.ack===false)&&made[0].remain.includes('地暖联动剩 3 处未调');
    const logOk=OPLOG[0].action==='资源分配（安装调试）'&&OPLOG[0].detail.includes('工时占比');
    const notiOk=NOTIF[0].what.includes('安装派工');
    SCH.splice(n0,2); OPLOG.shift(); NOTIF.shift(); renderAll(); loginAs('finance');
    return JSON.stringify({rows,onlyInst,cols,pcts,bands,negLeft,remainAuto,two,svgs,tips,legend,center,
      rebanded,opened,preFill,schedOk,logOk,notiOk});});
  const r46=JSON.parse(w46);
  ok(r46.rows===2&&r46.onlyInst,`安装调试应只列 SM4 后~交付前、且未进交付流程的项目（实际 ${r46.rows} 行）`);
  ok(r46.cols,'缺 剩余工作量/已投入/预计总/工时占比 四列');
  ok(r46.pcts,'工时占比算错（应 66% / 95%）');
  ok(r46.bands,'档位配色未体现（充裕 / 接近超支预警）');
  ok(r46.negLeft,'剩余工时列算错（周宅 13h · 赵宅 102h）');
  ok(r46.remainAuto,'剩余工作量未自动带出上次每日上报');
  ok(r46.two&&r46.svgs,'四张卡未换成两张环形图');
  ok(r46.tips,'环形图扇区缺悬停明细（<title>）');
  ok(r46.legend&&r46.center,'环形图图例/中心数字缺失（四档 · 已投入/剩余预算 · 79.5%）');
  ok(r46.rebanded,'改预警线后档位未重算');
  ok(r46.opened&&r46.preFill,'资源分配浮窗未开/未按剩余工作预填内容');
  ok(r46.schedOk,'资源分配未按人写进派工排班表（带剩余工作）');
  ok(r46.logOk&&r46.notiOk,'资源分配未留痕/未通知本人');
  // 四十八轮：交付页（待交付判定 · 客户联络 · 交付排班 · 工时对比 · 运维条款 · 确认交付）
  const w48=await page.evaluate(()=>{
    loginAs('eng'); go('eng','交付');
    const h=document.getElementById('main').innerHTML;
    const rows=document.querySelectorAll('#delivtbl tbody tr').length;   // 陈宅（可交付）+ 吴宅（等S4）
    const pre=h.includes('✓ 施工已结束')&&h.includes('S4 未结清 —— 钱没到位不能约交付')&&h.includes('✓ S4 已结清');
    const contact=h.includes('已联系')&&h.includes('未联系')&&h.includes('发交付预约');
    const hours=h.includes('5.5 h')&&h.includes('超标')&&h.includes('当天人工已进项目成本');
    const mt=h.includes('✓ 已签署')&&h.includes('确认已签署');
    // 客户联络弹窗：选联系人 + 渠道 + 内容可改
    delivNotifyOpen('KX-2026-0199');
    const box=document.getElementById('smbox').innerHTML;
    const notifyOk=document.getElementById('smbox').style.display==='block'
      &&box.includes('交付预约通知')&&box.includes('只发短信')&&box.includes('短信 + 邮件')
      &&!!document.getElementById('dlv-sms')&&document.getElementById('dlv-sms').value.includes('交付验收');
    delivNotifySend();
    const sent=DELIV['KX-2026-0199'].contacted===true&&OPLOG[0].action==='发出交付预约通知'
      &&NOTIF[0].what.includes('交付预约通知');
    // 交付排班 → 写进排班表
    const n0=SCH.length;
    delivSchedOpen('KX-2026-0199');
    const d=new Date(); d.setDate(d.getDate()+5); const ds=ymdS(d);
    document.getElementById('dl-d').value=ds.replace(/\//g,'-');
    document.getElementById('dl-st').value='09:00';
    document.getElementById('dl-et').value='13:00';
    [...document.querySelectorAll('.dl-who')].forEach(c=>{c.checked=(c.value==='陈工'||c.value==='小陈');});
    delivSchedSave();
    const made=SCH.filter(x=>x.d===ds&&x.type==='交付'&&x.pj==='KX-2026-0199');
    const schedOk=made.length===2&&DELIV['KX-2026-0199'].sched===ds+' 09:00–13:00'
      &&OPLOG[0].detail.includes('当天人工自动进项目成本');
    // 门禁：运维条款未签 → 不让确认交付
    delivDone('KX-2026-0199');
    const g1=!DELIV['KX-2026-0199'].delivered;
    delivMtSign('KX-2026-0199'); uiOk();
    const signed=DELIV['KX-2026-0199'].mtSigned===true&&OPLOG[0].action==='确认运维条款已签署';
    delivDone('KX-2026-0199');                                            // 实际工时未回 → 仍拦
    const g2=!DELIV['KX-2026-0199'].delivered;
    // 陈宅：条款已签 + 工时已回 → 可确认交付（利润率定格 + 转状态）
    delivDone('KX-2026-0180'); uiOk();
    const doneOk=DELIV['KX-2026-0180'].delivered===true
      &&(PROJECTS.find(p=>p.code==='KX-2026-0180')||{}).status==='项目交付'
      &&OPLOG[0].detail.includes('利润率交付当天定格');
    // 还原
    DELIV['KX-2026-0180'].delivered=false;
    Object.assign(DELIV['KX-2026-0199'],{contacted:false,contactAt:undefined,contactBy:undefined,
      contactCh:undefined,sched:null,schedWho:undefined,mtSigned:false,mtBy:undefined,mtAt:undefined});
    SCH.splice(n0,2); OPLOG.splice(0,5); NOTIF.splice(0,4); renderAll(); loginAs('finance');
    return JSON.stringify({rows,pre,contact,hours,mt,notifyOk,sent,schedOk,g1,signed,g2,doneOk});});
  const r48=JSON.parse(w48);
  ok(r48.rows===2,`交付页应 2 行（可交付 + 等 S4 结清），实际 ${r48.rows}`);
  ok(r48.pre,'前置条件列未体现 施工结束 / S4 结清（含钱没到位的原句）');
  ok(r48.contact,'客户联络列缺 已联系/未联系/发交付预约');
  ok(r48.hours,'工时对比缺 实际/超标/当天人工进成本');
  ok(r48.mt,'运维条款列缺 已签署/确认按钮');
  ok(r48.notifyOk,'交付预约弹窗缺 联系人选择/渠道/可改内容');
  ok(r48.sent,'发通知未记「已联系」/未留痕通知');
  ok(r48.schedOk,'交付排班未写进派工排班表/未留痕当天人工进成本');
  ok(r48.g1,'运维条款未签竟能确认交付（应拦）');
  ok(r48.signed,'确认运维条款签署未置位留痕');
  ok(r48.g2,'实际工时未回竟能确认交付（应拦）');
  ok(r48.doneOk,'确认交付未定格利润率/未转状态');
  const plChk=await page.evaluate(()=>{go('fin','项目列表');pjFilter=null;renderAll();
    const h=document.getElementById('main').innerHTML;pjFilter=null;
    return h.includes('<b>王宅</b>');});
  ok(plChk,'公司项目列表粗体未改客户昵称');
  // 售前财务注释 → S1 行内 + S1 待办（二十二轮）
  await page.evaluate(()=>go('fin','项目收款S1-S3'));
  fh=await page.evaluate(()=>document.getElementById('main').innerHTML);
  ok(fh.includes('售前注释')&&fh.includes('Luo Holdings'),'S1 行内缺售前财务注释');
  const noteChk=await page.evaluate(()=>{
    const td=allTodos().find(x=>x.id==='fin-s1-KX-2026-0203');
    const r1=!!td&&td.act.includes('售前注释')&&td.act.includes('Luo Holdings');
    finNoteRead('KX-2026-0203');
    const f=finOf('KX-2026-0203');
    const read=f.noteFr==='read'&&OPLOG[0].action==='已读财务注释';
    const badge=document.getElementById('main').innerHTML.includes('已读 ✓');
    f.noteFr='unread'; renderAll();
    return JSON.stringify({r1,read,badge});});
  const nc2=JSON.parse(noteChk);
  ok(nc2.r1,'S1 待办内容未附售前注释');
  ok(nc2.read&&nc2.badge,'标已读未落回执/未变角标');
  // 二十六轮：编号+立项时间的表 → 三件套（+昵称+完整地址）全覆盖
  const trioChk=await page.evaluate(()=>{
    const grab=()=>document.getElementById('main').innerHTML;
    go('fin','操作日志'); const a=grab().includes('项目 · 地址')&&grab().includes('8 Franklin Rd, Cherrybrook NSW');
    go('fin','催账和停服'); const b=grab().includes('<b>张宅</b>')&&grab().includes('31 Blaxland Rd, Ryde NSW');
    go('fin','运维财务支持'); const c=grab().includes('<b>陈宅</b>')&&grab().includes('22 Rosamond St, Hornsby NSW');
    go('fin','财务节点'); const d=grab().includes('项目 · 地址')&&grab().includes('<b>王宅</b>');
    return JSON.stringify({a,b,c,d});});
  const tc=JSON.parse(trioChk);
  ok(tc.a,'操作日志缺昵称+完整地址');
  ok(tc.b,'催账和停服缺昵称+完整地址');
  // 二十七/二十八轮：催款分级 + 双语无昵称模版 + 弹窗发送 + 烂尾不催款
  const rm27=await page.evaluate(()=>{go('fin','催账和停服');
    const h=document.getElementById('main').innerHTML;
    const f=finOf('KX-2026-0160'), m=f.ms[1];
    const sms=tplRender(REMIND_TPL.final.zh.sms,f,m,'zh');
    const en=tplRender(REMIND_TPL.final.en.sms,f,m,'en');
    finRemindOpen('KX-2026-0160',1,'final');           // 烂尾 → toast 拦，弹窗不开
    const stalledBlock=m.remind.length===2&&document.getElementById('rmbox').style.display!=='block';
    return JSON.stringify({
      lvl:h.includes('最终催款')&&h.includes('烂尾 · 不催款'),
      hint:h.includes('「设置」'),
      render:!sms.includes('张宅')&&sms.includes('31 Blaxland Rd')&&/超期 \d+ 天/.test(sms)&&sms.includes('第 3 次'),
      renderEn:en.includes('Materials Payment')&&/\d+ days overdue/.test(en)&&!en.includes('张宅'),
      stalledBlock});});
  const r27=JSON.parse(rm27);
  ok(r27.lvl,'催账页缺最终催款按钮/烂尾不催款标');
  ok(r27.hint,'催账页缺模版指路（设置）');
  ok(r27.render,'中文模版渲染不对（应无昵称、含完整地址/超期/次数）');
  ok(r27.renderEn,'英文模版渲染不对（节点英文名/超期/无昵称）');
  ok(r27.stalledBlock,'烂尾项目催款未被拦截');
  // 催款弹窗全流程：渠道/语言/发送人/可改/发送/未回复照样再催
  const rmFlow=await page.evaluate(()=>{go('fin','项目收款S1-S3');
    const f=finOf('KX-2026-0203'), m=f.ms[0], n0=m.remind.length;
    finRemindOpen('KX-2026-0203',0);
    const boxOpen=document.getElementById('rmbox').style.display==='block';
    const h=document.getElementById('rmbox').innerHTML;
    const hasAll=h.includes('只发短信')&&h.includes('English')&&h.includes('rm-sender')
      &&h.includes('不回也不影响任何进展')&&h.includes('发出即视为送达');
    const noNick=!h.includes('罗宅');
    RMD.lang='en'; remindPaint();
    const enBox=document.getElementById('rm-sms').value.includes('Reply Y once paid');
    RMD.lang='zh'; remindPaint();
    finRemindSend();
    const sent1=m.remind.length===n0+1&&m.remind[m.remind.length-1].how==='短信+邮件';
    finRemindOpen('KX-2026-0203',0); finRemindSend();  // 收件人没回 Y 照样可再催
    const sent2=m.remind.length===n0+2;
    const logOk=OPLOG[0].detail.includes('署名')&&OPLOG[0].detail.includes('发件');
    m.remind.splice(n0); NOTIF.splice(0,3); renderAll();
    return JSON.stringify({boxOpen,hasAll,noNick,enBox,sent1,sent2,logOk});});
  const rf=JSON.parse(rmFlow);
  ok(rf.boxOpen&&rf.hasAll,'催款弹窗缺渠道/语言/署名/回执说明');
  ok(rf.noNick,'催款弹窗内容出现了项目昵称（对外应只用地址）');
  ok(rf.enBox,'英文模版切换未生效');
  ok(rf.sent1&&rf.sent2,'弹窗发送未生效/未回复被当作再催前提');
  ok(rf.logOk,'催款日志缺署名/发件身份');
  const tplSave=await page.evaluate(()=>{tplTab='normal';tplLang='zh';go('fin','设置');
    const h=document.getElementById('main').innerHTML;
    const ui=h.includes('催款模版')&&h.includes('{付款人}')&&h.includes('实时预览')&&h.includes('English');
    const bak=REMIND_TPL.normal.zh.sms;
    document.getElementById('tpl-sms').value='测试模版 {付款人}';
    finTplSave();
    const okSave=REMIND_TPL.normal.zh.sms==='测试模版 {付款人}'&&OPLOG[0].action==='保存催款模版';
    REMIND_TPL.normal.zh.sms=bak; renderAll(); return JSON.stringify({ui,okSave});});
  const ts2=JSON.parse(tplSave);
  ok(ts2.ui,'设置页缺催款模版编辑器（双级双语/变量/预览）');
  ok(ts2.okSave,'保存模版未生效/未留痕');
  const s4rm=await page.evaluate(()=>{go('fin','项目收款S1-S3');
    const h1=document.getElementById('main').innerHTML;
    return h1.includes('>催款<')&&!h1.includes('最终催款');});
  ok(s4rm,'S1-3 页应为常规催款（不该出现最终催款）');
  ok(tc.c,'运维财务支持缺昵称+完整地址');
  ok(tc.d,'财务节点卡点表缺昵称+完整地址');
  await page.evaluate(()=>{go('fin','项目收款S1-S3');FINOPEN['KX-2026-0203']=true;renderAll();});
  await page.screenshot({path:__dirname+'/shot_收款S1S3.png'});
  await page.evaluate(()=>{FINOPEN['KX-2026-0203']=false;go('fin','尾款结算S4与Var');s4Open['KX-2026-0142']=true;renderAll();});
  await page.screenshot({path:__dirname+'/shot_S4与Var.png'});
  await page.evaluate(()=>{s4Open['KX-2026-0142']=false;renderAll();});

  // ═══ 四十九轮：发送人身份统一（决策页设置 · 全站发信带身份）═══
  const snd=await page.evaluate(()=>{ const R={};
    loginAs('admin'); go('decision','全局参数');
    const h=document.getElementById('main').innerHTML;
    R.panel=h.includes('发送人身份')&&h.includes(SENDER.sms.num)
      &&h.includes('accounts@konnext.com.au')&&h.includes('info@konnext.com.au')
      &&h.includes('admin@konnext.com.au');
    R.warn=h.includes('字母发送者 ID')&&h.includes('Twilio');
    R.map=h.includes('财务 → accounts@konnext.com.au')&&h.includes('售前 → info@konnext.com.au')
      &&h.includes('工程管理 → admin@konnext.com.au');
    R.mailOf=['presales','proc','wh','mt'].every(d=>mailId(d).addr==='info@konnext.com.au')
      &&mailId('fin').addr==='accounts@konnext.com.au'&&mailId('eng').addr==='admin@konnext.com.au';
    const n0=SENDER.sms.num, e0=SENDER.mail.eng.addr, L0=OPLOG.length;
    senderSms('abc');                      R.g1=SENDER.sms.num===n0&&OPLOG.length===L0;
    senderMail('fin','accounts');          R.g2=SENDER.mail.fin.addr==='accounts@konnext.com.au'&&OPLOG.length===L0;
    senderSms('+61 400 111 222');
    R.set1=SENDER.sms.num==='+61 400 111 222'&&OPLOG[0].action==='修改发送人身份';
    senderMail('eng','ops@konnext.com.au');
    R.set2=SENDER.mail.eng.addr==='ops@konnext.com.au'&&OPLOG[0].detail.includes('工程管理邮件身份');
    SENDER.sms.num=n0; SENDER.mail.eng.addr=e0; OPLOG.splice(0,OPLOG.length-L0);
    loginAs('finance'); senderSms('+61 499 999 999');   // 二级账号改不了
    R.g3=SENDER.sms.num===n0&&OPLOG.length===L0;
    return JSON.stringify(R);});
  const S49=JSON.parse(snd);
  ok(S49.panel,'全局参数缺发送人身份面板（短信号码 + 三个邮箱身份）');
  ok(S49.warn,'发送人身份面板缺 Twilio/字母发送者 ID 的警告');
  ok(S49.map,'发送人身份面板缺 部门 → 邮箱身份 映射');
  ok(S49.mailOf,'部门→邮箱身份映射不对（财务 accounts / 工程 admin / 其余 info）');
  ok(S49.g1,'号码乱填竟被保存（应拦且不留痕）');
  ok(S49.g2,'邮箱乱填竟被保存（应拦且不留痕）');
  ok(S49.set1&&S49.set2,'改发送人身份未生效/未留痕');
  ok(S49.g3,'非决策管理员竟能改发送人身份（应拦）');
  const snd2=await page.evaluate(()=>{ const R={};
    loginAs('finance'); go('fin','项目收款S1-S3');
    const f=finOf('KX-2026-0203'), m=f.ms[0], n0=m.remind.length, L0=OPLOG.length, NF=NOTIF.length;
    finRemindOpen('KX-2026-0203',0);
    let h=document.getElementById('rmbox').innerHTML;
    R.bar=h.includes('发件身份')&&h.includes('accounts@konnext.com.au')&&h.includes(SENDER.sms.num);
    R.sign=h.includes('署名（经办人）');
    RMD.channel='sms'; remindPaint();
    h=document.getElementById('rmbox').innerHTML;
    R.smsOnly=h.includes('发件身份')&&!h.includes('accounts@konnext.com.au');
    RMD.channel='both'; remindPaint(); finRemindSend();
    R.log=OPLOG[0].detail.includes('署名')&&OPLOG[0].detail.includes('发件 短信 '+SENDER.sms.num)
      &&OPLOG[0].detail.includes('accounts@konnext.com.au');
    R.notif=(NOTIF[0].from||'').includes('accounts@konnext.com.au')&&(NOTIF[0].from||'').includes(SENDER.sms.num);
    m.remind.splice(n0); NOTIF.splice(0,NOTIF.length-NF); OPLOG.splice(0,OPLOG.length-L0); renderAll();
    go('fin','设置');
    R.setHint=document.getElementById('main').innerHTML.includes('发件身份不在这里改');
    return JSON.stringify(R);});
  const S49b=JSON.parse(snd2);
  ok(S49b.bar,'催款弹窗缺发件身份横幅（公司号码 + accounts@）');
  ok(S49b.sign,'催款弹窗「发送人」未更名「署名（经办人）」');
  ok(S49b.smsOnly,'只发短信时不应出现邮件发件地址');
  ok(S49b.log,'催款日志缺发件身份（署名 + 短信号 + 邮箱）');
  ok(S49b.notif,'通知记录未定格发件身份');
  ok(S49b.setHint,'财务设置页未写明发件身份在决策页改');
  const snd3=await page.evaluate(()=>{ const R={};
    loginAs('eng'); go('eng','交付');
    delivNotifyOpen('KX-2026-0180');
    let h=document.getElementById('smbox').innerHTML;
    R.smsOnly=h.includes('发件身份')&&h.includes(SENDER.sms.num)&&!h.includes('@konnext.com.au');
    DLV.ch='both'; delivNotifyPaint();
    h=document.getElementById('smbox').innerHTML;
    R.deliv=h.includes('发件身份')&&h.includes('admin@konnext.com.au')&&h.includes(SENDER.sms.num);
    R.dsign=h.includes('署名（经办人');
    R.noFin=!h.includes('accounts@konnext.com.au');
    delivNotifyClose();
    go('eng','派工排班'); schSeed();
    const fut=weekDays(1).map(d=>ymdS(d))[2];
    schAdd('阿强',fut);
    h=document.getElementById('schbox').innerHTML;
    R.sch=h.includes('发件身份')&&h.includes(SENDER.sms.num)&&!h.includes('@konnext.com.au');
    schClose(); renderAll();
    return JSON.stringify(R);});
  const S49c=JSON.parse(snd3);
  ok(S49c.smsOnly,'交付预约只发短信时应只显示公司号码');
  ok(S49c.deliv,'交付预约弹窗缺发件身份（公司号码 + admin@）');
  ok(S49c.dsign,'交付预约弹窗「发送人」未更名「署名（经办人）」');
  ok(S49c.noFin,'交付预约弹窗错用了财务发件地址');
  ok(S49c.sch,'排班浮窗缺发件身份（员工短信同样走公司统一号码）');
  await page.evaluate(()=>{loginAs('admin');go('decision','全局参数');});
  await page.screenshot({path:__dirname+'/shot_发送人身份.png'});

  // ═══ 五十轮：工程流水账 · 每日工时管理（改名/搜索/原因类别）· 人员与外包删除 ═══
  const lg50=await page.evaluate(()=>{ const R={};
    loginAs('eng');
    R.noStaffPage=!DEPT.eng.pages.includes('人员与外包');
    R.renamed=DEPT.eng.pages.includes('每日工时管理')&&!DEPT.eng.pages.includes('每日上报');
    pj=PROJECTS.findIndex(p=>p.code==='KX-2026-0180'); go('eng','工程流水账');
    let h=document.getElementById('main').innerHTML;
    R.full=h.includes('SM1 进场 完成定格')&&h.includes('SM4 封板核对 完成定格')
      &&h.includes('确认交付')&&h.includes('运维条款签署确认');
    R.hdr=h.includes('入场天数')&&h.includes('累计人工工时')&&h.includes('派了工没打卡');
    R.io=h.includes('09:05–14:35');
    R.flag=h.includes('围栏外打卡·已确认');
    R.gate=h.includes('解锁财务：S2 物料款可开票')&&h.includes('解锁财务：S3 人工款可开票');
    pj=PROJECTS.findIndex(p=>p.code==='KX-2026-0203'); renderAll();
    h=document.getElementById('main').innerHTML;
    R.miss=h.includes('没打卡')&&h.includes('日结挂起');
    R.rep=h.includes('每日上报 · 陈工')||h.includes('每日上报 · 小陈');
    engLgBad=true; renderAll();
    const bad=document.querySelectorAll('#main tbody tr').length;
    engLgBad=false; engLgF='Site Meeting'; renderAll();
    const smOnly=[...document.querySelectorAll('#main tbody tr')].every(t=>t.innerHTML.includes('Site Meeting'));
    engLgF='全部'; renderAll();
    R.filter=(bad===2)&&smOnly;
    pj=PROJECTS.findIndex(p=>p.code==='KX-2026-0201'); renderAll();
    R.empty=document.getElementById('main').innerHTML.includes('还没有工程流水');
    pj=0; renderAll();
    return JSON.stringify(R);});
  const R50=JSON.parse(lg50);
  ok(R50.noStaffPage,'「人员与外包」应已删除（工程人员由财务建立）');
  ok(R50.renamed,'「每日上报」应已更名「每日工时管理」');
  ok(R50.full,'工程流水账缺 SM1~SM4 完成定格 / 运维条款 / 确认交付');
  ok(R50.hdr,'工程流水账缺头部三算（入场天数/累计工时/派了工没打卡）');
  ok(R50.io,'工程流水账缺实际打卡区间（交付当天 09:05–14:35）');
  ok(R50.flag,'工程流水账未标围栏外打卡异常');
  ok(R50.gate,'工程流水账缺 SM3/SM4 解锁财务的下游事件');
  ok(R50.miss,'派了工没打卡的日子未标红（罗宅 07/29–30）');
  ok(R50.rep,'工程流水账未带出当天每日上报原文');
  ok(R50.filter,'阶段过滤 / 只看异常 不生效（罗宅异常应 2 天）');
  ok(R50.empty,'没进工程线的项目应显示空态说明');
  const wt=await page.evaluate(()=>{ const R={}; const l0=OPLOG.length;
    loginAs('eng'); go('eng','每日工时管理');
    let h=document.getElementById('main').innerHTML;
    R.title=h.includes('每日工时管理')&&h.includes('人员名单与薪酬由财务建立与维护');
    bfOpen('小陈','07/29','2026/07/29');
    R.search=!!document.getElementById('bf-pjq');
    document.getElementById('bf-pjq').value='Springdale'; bfPjFilter();
    R.auto=document.getElementById('bf-pj').value==='KX-2026-0203';
    document.getElementById('bf-pjq').value=''; bfPjFilter();
    document.getElementById('bf-pj').value='';
    document.getElementById('bf-h').value='8';
    document.getElementById('bf-cat').value='忘打卡';
    document.getElementById('bf-note').value='早上直接去了现场布线，忘记在 App 打卡，负责人已核实确有出工';
    const n0=Object.keys(BACKFILL).length;
    bfConfirm('小陈','07/29','2026/07/29');
    R.gPj=Object.keys(BACKFILL).length===n0;
    bfClose();
    go('eng','设置');
    h=document.getElementById('main').innerHTML;
    R.catPanel=h.includes('补录原因类别')&&h.includes('忘打卡')&&h.includes('兜底项 · 不可删');
    const c0=BF_CATS.length;
    document.getElementById('bfcat-new').value='忘打卡'; bfCatAdd();
    R.gDup=BF_CATS.length===c0;
    document.getElementById('bfcat-new').value='天气停工'; bfCatAdd();
    R.add=BF_CATS.includes('天气停工')&&OPLOG[0].action==='新增补录原因类别';
    bfCatDel(BF_CATS.indexOf('其他'));
    R.gOther=BF_CATS.includes('其他');
    BACKFILL['冒烟|01/01']={pj:'company',h:1,cat:'天气停工',note:'x',by:'x',at:'x'};
    bfCatDel(BF_CATS.indexOf('天气停工'));
    R.gUsed=BF_CATS.includes('天气停工');
    delete BACKFILL['冒烟|01/01'];
    bfCatDel(BF_CATS.indexOf('天气停工')); uiOk();
    R.del=!BF_CATS.includes('天气停工')&&OPLOG[0].action==='删除补录原因类别';
    OPLOG.splice(0,OPLOG.length-l0); renderAll();
    return JSON.stringify(R);});
  const R50b=JSON.parse(wt);
  ok(R50b.title,'每日工时管理页标题/人员归属说明缺失');
  ok(R50b.search,'补录弹窗项目下拉缺搜索框');
  ok(R50b.auto,'补录搜索筛到唯一项目未自动选中');
  ok(R50b.gPj,'补录没选项目竟能提交（应拦：不允许无项目归属的工时）');
  ok(R50b.catPanel,'工程设置缺补录原因类别面板');
  ok(R50b.gDup,'重复原因类别未拦');
  ok(R50b.add,'新增原因类别未生效/未留痕');
  ok(R50b.gOther,'「其他」兜底类别竟被删掉（应拦）');
  ok(R50b.gUsed,'已被用过的原因类别竟能删（应拦）');
  ok(R50b.del,'删除原因类别未生效/未留痕');
  await page.evaluate(()=>{loginAs('eng');pj=PROJECTS.findIndex(p=>p.code==='KX-2026-0180');go('eng','工程流水账');});
  await page.screenshot({path:__dirname+'/shot_工程流水账.png'});
  await page.evaluate(()=>{pj=0;renderAll();});

  // ═══ 五十一轮：文档库（树 / 版本 / 链接 / 邮件转发 / 门禁）═══
  const dc=await page.evaluate(()=>{ const R={}; const l0=OPLOG.length;
    loginAs('eng'); docDir='p88a'; docQ=''; go('eng','文档库');
    let h=document.getElementById('main').innerHTML;
    R.tree=h.includes('项目文档')&&h.includes('技术文档（现场 App 查阅）')&&h.includes('KNX');
    R.list=h.includes('布线图（KNX 主回路）')&&h.includes('v3')&&h.includes('已发放')
      &&h.includes('docs.konnext.com.au/d/d-101');
    docQ='弱电箱'; renderAll();                          // 全库搜（跨文件夹）
    R.search=document.getElementById('main').innerHTML.includes('弱电箱整理与标签规范')
      &&document.getElementById('main').innerHTML.includes('技术文档（现场 App 查阅） / 通用施工规范');
    docQ=''; renderAll();
    // 版本历史：旧版保留 · 已发放锁定
    docHistOpen('D-101');
    h=document.getElementById('dcbox').innerHTML;
    R.hist=h.includes('v3')&&h.includes('v2')&&h.includes('v1')&&h.includes('当前')&&h.includes('锁定');
    docVerDel('D-101',3);                                 // 已发放 → 拦
    R.gSent=DOCS.find(d=>d.id==='D-101').vs.length===3;
    docClose();
    // 传新版本：必须写改了什么
    docVerOpen('D-101');
    document.getElementById('dc-note').value='短';
    docVerSave();                                         // 没选文件 → 拦
    const v0=DOCS.find(d=>d.id==='D-101').vs.length;
    docPick(); docVerSave();                              // 说明<5字 → 拦
    R.gNote=DOCS.find(d=>d.id==='D-101').vs.length===v0;
    document.getElementById('dc-note').value='补车库充电桩 32A 独立回路走线';
    docVerSave();
    const d101=DOCS.find(d=>d.id==='D-101');
    R.newVer=d101.vs.length===4&&d101.vs[0].v===4&&!d101.vs[0].sent
      &&OPLOG[0].action==='上传文档新版本';
    // 整份删除：有发放过的版本 → 拦
    docDel('D-101'); R.gDel=!!DOCS.find(d=>d.id==='D-101');
    // 邮件转发：发件身份＝工程管理 admin@ · 发出即定格已发放
    docMailOpen('D-202');
    h=document.getElementById('dcbox').innerHTML;
    R.mailBar=h.includes('发件身份')&&h.includes('admin@konnext.com.au')&&h.includes('署名（经办人');
    document.getElementById('dc-to').value='__manual__';
    document.getElementById('dc-mail').value='not-an-email';
    docMailSend();
    R.gMail=!docCur(DOCS.find(d=>d.id==='D-202')).sent;    // 邮箱格式拦
    document.getElementById('dc-to').value='Leo · VoltPro|leo@voltpro.com.au';
    docMailSend();
    const d202=DOCS.find(d=>d.id==='D-202');
    R.mailSent=!!docCur(d202).sent&&docCur(d202).sent.includes('Leo')
      &&OPLOG[0].action==='邮件转发文档'&&OPLOG[0].detail.includes('admin@konnext.com.au');
    docDel('D-202'); R.gDel2=!!DOCS.find(d=>d.id==='D-202');   // 发放后不可删
    // 文件夹：非空不让删
    docDir='tg'; docDirDel();
    R.gDir=!!DOC_DIRS.find(x=>x.id==='tg');
    docDir='p88a';
    // 还原演示态
    d101.vs=d101.vs.filter(v=>v.v!==4); docCur(d202).sent='';
    OPLOG.splice(0,OPLOG.length-l0); NOTIF.shift(); renderAll();
    return JSON.stringify(R);});
  const D51=JSON.parse(dc);
  ok(D51.tree,'文档库缺树（项目文档 / 技术文档）');
  ok(D51.list,'文档列表缺 版本/已发放/固定链接');
  ok(D51.search,'全库搜索无效（应跨文件夹并显示路径）');
  ok(D51.hist,'版本历史缺旧版保留 / 当前标 / 已发放锁定');
  ok(D51.gSent,'已发放版本竟能删（应拦）');
  ok(D51.gNote,'新版本没写「改了什么」竟能存（应拦）');
  ok(D51.newVer,'传新版本未存成 v+1 / 未留痕');
  ok(D51.gDel&&D51.gDel2,'有发放记录的文档竟能整份删（应拦）');
  ok(D51.mailBar,'邮件转发缺发件身份（工程管理 admin@）/ 署名');
  ok(D51.gMail,'邮箱格式错竟能发（应拦）');
  ok(D51.mailSent,'邮件转发未定格「已发放」/ 未留痕发件身份');
  ok(D51.gDir,'非空文件夹竟能删（应拦）');
  // ═══ 五十二轮：日志查阅增强 · 设置补齐 · 部门总说明 ═══
  const lg52=await page.evaluate(()=>{ const R={}; const l0=OPLOG.length;
    loginAs('eng'); logClear(); go('eng','操作日志');
    let h=document.getElementById('main').innerHTML;
    const all=document.querySelectorAll('#main tbody tr').length;
    R.ui=h.includes('近 7 天')&&h.includes('导出 CSV')&&h.includes('清空筛选')===false
      &&h.includes('操作人')&&h.includes('全部项目');
    logRangeSet('今天');
    const today=document.querySelectorAll('#main tbody tr').length;
    R.range=today<all&&today>0;
    logRangeSet('全部'); logPjF='KX-2026-0188'; renderAll();
    const byPj=[...document.querySelectorAll('#main tbody tr')].every(t=>t.innerHTML.includes('KX-2026-0188'));
    logPjF='公司级'; renderAll();
    const coy=[...document.querySelectorAll('#main tbody tr')].every(t=>t.innerHTML.includes('公司级'));
    R.pjF=byPj&&coy;
    logPjF='全部'; logWho='陈工'; renderAll();
    R.whoF=[...document.querySelectorAll('#main tbody tr')].every(t=>t.innerHTML.includes('陈工'));
    logClear(); renderAll();
    R.upstream=document.getElementById('main').innerHTML.includes('标记拒付停服')
      &&document.getElementById('main').innerHTML.includes('出库到场');
    logExport('eng',3);
    R.exportLog=OPLOG[0].action==='导出操作日志';
    OPLOG.splice(0,OPLOG.length-l0); logClear();
    // 设置：任务类型 + SM 清单
    go('eng','设置');
    h=document.getElementById('main').innerHTML;
    R.setUI=h.includes('排班任务类型')&&h.includes('内建 · 不可删')
      &&h.includes('SM 模板与出发前清单')&&h.includes('条件项');
    const t0=SCH_TYPES.length;
    schTypeDel('安装'); R.gBuiltin=SCH_TYPES.length===t0;
    document.getElementById('sct-new').value='安装'; schTypeAdd();
    R.gDupType=SCH_TYPES.length===t0;
    document.getElementById('sct-new').value='复勘'; schTypeAdd();
    R.addType=SCH_TYPES.some(t=>t.k==='复勘')&&SCH_NORM['复勘']===240;
    schTypeDel('复勘'); uiOk();
    R.delType=!SCH_TYPES.some(t=>t.k==='复勘')&&SCH_NORM['复勘']===undefined;
    const c0=SM_CHK[2].length;
    document.getElementById('smchk-new-2').value='网线测试仪';
    smChkAdd(2);
    R.chkAdd=SM_CHK[2].length===c0+1&&SM_CHK[2].includes('网线测试仪');
    smChkDel(2,SM_CHK[2].indexOf('网线测试仪')); uiOk();
    R.chkDel=SM_CHK[2].length===c0;
    // 帮助：部门总说明
    go('eng','总览'); helpTab='dept'; helpOpen();
    const hb=document.getElementById('helpbody').innerHTML;
    R.guide=hb.includes('工程管理 · 总说明')&&hb.includes('S 是钱、SM 是会')
      &&hb.includes('派工是计划，打卡是事实')&&hb.includes('每日工时管理');
    helpTab='page'; helpOpen();
    R.pageTab=document.getElementById('helpbody').innerHTML.includes('本页操作');
    helpClose();
    OPLOG.splice(0,OPLOG.length-l0); renderAll();
    return JSON.stringify(R);});
  const L52=JSON.parse(lg52);
  ok(L52.ui,'操作日志缺时间/操作人/项目/导出等查阅方式');
  ok(L52.range,'按时间查（今天）无效');
  ok(L52.pjF,'按项目查（含公司级一档）无效');
  ok(L52.whoF,'按操作人查无效');
  ok(L52.upstream,'工程操作日志缺上下游条目（财务停服 / 库管出库到场）');
  ok(L52.exportLog,'导出 CSV 本身未留痕');
  ok(L52.setUI,'工程设置缺任务类型 / SM 出发前清单面板');
  ok(L52.gBuiltin,'内建任务类型竟能删（应拦）');
  ok(L52.gDupType,'重复任务类型未拦');
  ok(L52.addType&&L52.delType,'新增/删除任务类型未生效（含合理时长联动）');
  ok(L52.chkAdd&&L52.chkDel,'SM 出发前清单项增删未生效');
  ok(L52.guide,'帮助缺「部门总说明」（工程管理全流程）');
  ok(L52.pageTab,'帮助「本页说明」页签失效');
  await page.evaluate(()=>{loginAs('eng');docDir='p88a';go('eng','文档库');});
  await page.screenshot({path:__dirname+'/shot_文档库.png'});
  await page.evaluate(()=>{go('eng','操作日志');});
  await page.screenshot({path:__dirname+'/shot_操作日志查阅.png'});

  console.log(`渲染页面数: ${rendered}`);
  console.log(`运行时报错: ${errors.length}`); errors.forEach(e=>console.log('  '+e));
  console.log(`断言失败: ${fails.length}`); fails.forEach(f=>console.log('  ✗ '+f));
  console.log(errors.length===0&&fails.length===0?'★ 冒烟测试全部通过':'★ 有失败项');
  await browser.close();
  process.exit(errors.length||fails.length?1:0);
})();
