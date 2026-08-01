// KONNEXT UI 原型冒烟测试（全量回归 · 跨会话归档版）
// 用法（云容器）：cd docs/tools && node ui-smoke.js
//   依赖 playwright（首次先 npm i playwright --no-save；浏览器用预装 /opt/pw-browsers，勿 playwright install）
// 覆盖：6 角色 × 全页面渲染零报错 + 售前定稿断言（§14）+ 待办三动作 +
//       操作日志真记录（§14 二十轮）+ 财务全线断言（§15 二十一/二十二轮）
// 期望输出：运行时报错 0 · 断言失败 0 · ★ 冒烟测试全部通过
const { chromium } = require('playwright');
(async()=>{
  const browser = await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
  const page = await browser.newPage({viewport:{width:1440,height:900}});
  const errors=[];
  page.on('console',m=>{ if(m.type()==='error') errors.push('console: '+m.text()); });
  page.on('pageerror',e=>errors.push('pageerror: '+e.message));
  await page.goto('file://'+require('path').join(__dirname,'..','KONNEXT_UI原型.html'));

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
  ok(n===7,`财务默认「财务相关」应 7 行（不含接洽中/已流失），实际 ${n}`);
  n=await page.evaluate(()=>{pjFilter='全部';renderAll();
    const x=document.querySelectorAll('#main tbody tr').length;pjFilter=null;return x;});
  ok(n===9,`财务点「全部」应 9 行（读全部原则），实际 ${n}`);
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
  const nPj=await page.evaluate(()=>{go('fin','项目列表');pjFilter='全部';pjQ='Epping';renderAll();
    const n=document.querySelectorAll('#main tbody tr').length;pjQ='';pjFilter=null;renderAll();return n;});
  ok(nPj===1,`项目列表搜「Epping」应 1 行，实际 ${nPj}`);
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
    const hit=h.includes('立项 12 个')&&h.includes('已签约 6')&&h.includes('已流标 1');
    statPeriod='month';renderAll();return hit;});
  ok(yearOk,'「年」档去向柱应真算出 12/6/1（含财务线三项目）');
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
  ok(lgq===2,`日志搜「定金」应 2 行，实际 ${lgq}`);
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
    const r={g1,g2,inv:!!f.ms[3].inv,total:h.includes('A$59,613.83'),lock:h.includes('v1 定格')};
    // 还原
    f.ms[3].inv=undefined; f.ms[3].ver=0; f.ms[3].firstInv=undefined;
    f.vars=f.vars.filter(v=>v.src!=='未退料'); f.unret=2013.83;
    f.vars.forEach(v=>{if([4,5,6].includes(v.id)){v.amt=null;v.by=undefined;v.at=undefined;v.note=undefined;}});
    renderAll(); return JSON.stringify(r);});
  const s4=JSON.parse(s4Chk);
  ok(s4.g1&&s4.g2,'S4 请款门禁（待估价/未退料）未拦');
  ok(s4.inv&&s4.total,'S4 组合应收 59,613.83（尾款+变更+未退料）未算对/未定格');
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
      cat:h.includes('交通递送')&&h.includes('材料 / 工具 / 交通递送'),
      addr:h.includes('项目 · 地址')&&h.includes('11 Bond St, Mosman NSW')});});
  const e24=JSON.parse(exp24);
  ok(e24.no&&e24.cat,'报销类别未收窄为 材料/工具/交通递送');
  ok(e24.addr,'报销表缺项目昵称+完整地址列');
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
  const cmChk=await page.evaluate(()=>{go('fin','成本与利润率');
    return document.getElementById('main').innerHTML.includes('<b>张宅</b>');});
  ok(cmChk,'成本利润率页昵称未按口径');
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
      render:!sms.includes('张宅')&&sms.includes('31 Blaxland Rd')&&sms.includes('超期 168 天')&&sms.includes('第 3 次'),
      renderEn:en.includes('Materials Payment')&&en.includes('168 days overdue')&&!en.includes('张宅'),
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
    const logOk=OPLOG[0].detail.includes('发送人');
    m.remind.splice(n0); NOTIF.splice(0,3); renderAll();
    return JSON.stringify({boxOpen,hasAll,noNick,enBox,sent1,sent2,logOk});});
  const rf=JSON.parse(rmFlow);
  ok(rf.boxOpen&&rf.hasAll,'催款弹窗缺渠道/语言/发送人/回执说明');
  ok(rf.noNick,'催款弹窗内容出现了项目昵称（对外应只用地址）');
  ok(rf.enBox,'英文模版切换未生效');
  ok(rf.sent1&&rf.sent2,'弹窗发送未生效/未回复被当作再催前提');
  ok(rf.logOk,'催款日志缺发送人');
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

  console.log(`渲染页面数: ${rendered}`);
  console.log(`运行时报错: ${errors.length}`); errors.forEach(e=>console.log('  '+e));
  console.log(`断言失败: ${fails.length}`); fails.forEach(f=>console.log('  ✗ '+f));
  console.log(errors.length===0&&fails.length===0?'★ 冒烟测试全部通过':'★ 有失败项');
  await browser.close();
  process.exit(errors.length||fails.length?1:0);
})();
