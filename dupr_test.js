// PickleScore 評分公式 V1 單元測試：node dupr_test.js
// 公式本體從 index.html 複製（改 index.html 的 DUPR_CFG / duprGame 後，這裡也要同步）
const DUPR_CFG={START:3,SLOPE:7.88,EMIN:.05,EMAX:.95,KMAX:.40,KMIN:.10,KDECAY:30,CAP:.06,GAP:.5};
const kOf=n=>{const c=DUPR_CFG;return c.KMIN+(c.KMAX-c.KMIN)*Math.exp(-n/c.KDECAY)};
const r3=x=>Math.round(x*1000)/1000;
// 單場：ra/rb 賽前分數陣列、ka/kb K 值陣列
function duprGame(ra,rb,sa,sb,ka,kb){const c=DUPR_CFG,av=t=>t.reduce((s,x)=>s+x,0)/t.length,RA=av(ra),RB=av(rb);
  const ea=Math.min(c.EMAX,Math.max(c.EMIN,.5+(RA-RB)/c.SLOPE)),s=sa/(sa+sb),perf=s-ea,gap=Math.abs(RA-RB),skip=gap>=c.GAP-1e-9&&((RA>RB)===(sa>sb));
  const d=(k,sg)=>skip?0:r3(Math.max(-c.CAP,Math.min(c.CAP,k*perf*sg)));
  return {RA,RB,ea,s,perf,gap,skip,da:ka.map(k=>d(k,1)),db:kb.map(k=>d(k,-1))}}
// 依時間順序跑完全部比賽；rows:{id,a,b,sa,sb,t}
function duprRun(rows){const R={},N={},per={};const get=u=>u in R?R[u]:DUPR_CFG.START;
  rows.slice().sort((x,y)=>x.t-y.t).forEach(g=>{const ra=g.a.map(get),rb=g.b.map(get),ka=g.a.map(u=>kOf(N[u]||0)),kb=g.b.map(u=>kOf(N[u]||0));
    const o=duprGame(ra,rb,g.sa,g.sb,ka,kb),p={};
    g.a.forEach((u,i)=>p[u]={b:ra[i],k:ka[i],d:o.da[i],a:r3(ra[i]+o.da[i])});g.b.forEach((u,i)=>p[u]={b:rb[i],k:kb[i],d:o.db[i],a:r3(rb[i]+o.db[i])});
    Object.keys(p).forEach(u=>{R[u]=p[u].a;if(!o.skip)N[u]=(N[u]||0)+1;else if(!(u in N))N[u]=N[u]||0});
    per[g.id]={ea:o.ea,s:o.s,perf:o.perf,gap:o.gap,skip:o.skip,p}});
  return {R,N,per}}
// 預期比分（例 15 分制 → 15:12）
function expPts(ea,T){const w=ea>=.5?ea:1-ea,lo=Math.min(T-2,Math.round(T*(1-w)/w));return ea>=.5?[T,Math.max(0,lo)]:[Math.max(0,lo),T]}

const T=[[[2.851,2.734],[.369,.129],[2.996,3.187],[.237,.100],10,15,[-.023,-.008,.015,.006]],
[[2.827,2.648],[.369,.168],[2.219,3.193],[.199,.100],15,14,[.005,.002,-.003,-.001]],
[[2.832,2.712],[.369,.171],[2.489,3.192],[.171,.100],12,15,[-.017,-.008,.008,.005]],
[[2.816,2.215],[.369,.199],[2.650,3.004],[.168,.237],15,12,[.035,.019,-.016,-.023]]];
let ok=true;T.forEach(([ra,ka,rb,kb,sa,sb,exp],i)=>{const o=duprGame(ra,rb,sa,sb,ka,kb),got=[...o.da,...o.db];const pass=got.every((x,j)=>Math.abs(x-exp[j])<=.001+1e-9);ok=ok&&pass;console.log('case',i+1,pass?'PASS':'FAIL',got.join(','),'exp',exp.join(','),'E',o.ea.toFixed(4))});
const o5=duprGame([3.5,3.4],[2.8,2.9],15,8,[.3,.3],[.3,.3]);const p5=[...o5.da,...o5.db].every(x=>x===0);ok=ok&&p5;console.log('case 5',p5?'PASS':'FAIL',o5.gap.toFixed(2));
const o6=duprGame([2.8,2.9],[3.5,3.4],15,8,[.3,.3],[.3,.3]);console.log('upset still counts:',[...o6.da,...o6.db].join(','));
const o7=duprGame([3,3],[3,3],15,5,[.4,.4],[.4,.4]);console.log('cap check 15-5:',[...o7.da,...o7.db].join(','));
console.log('exp 15:',expPts(.555,15),expPts(.42,15),expPts(.5,11));
console.log(ok?'ALL PASS':'SOME FAIL')
