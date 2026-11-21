'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {stripTypeScriptTypes}=require('node:module');
const source=stripTypeScriptTypes(fs.readFileSync(path.join(__dirname,'../supabase/functions/video-search/index.ts'),'utf8'));
function server({items=[],fail=false,budgetAllowed=true,budgetFail=false,bridgeStatus=200,suggestions=['поиск','поиск видео']}={}){
 let handler,authorized=true,now=1000;const calls=[],budgetCalls=[];let lastResponse;
 class Clock extends Date{static now(){return now;}}
 const context={Response,URLSearchParams,AbortSignal,Date:Clock,Deno:{env:{get:key=>key==='SUPABASE_URL'?'https://test.supabase.co':'fixture'},serve:fn=>handler=fn},fetch:async(url,options)=>{
  if(url.endsWith('/auth/v1/user'))return Response.json({}, {status:authorized?200:401});
  if(url.endsWith('/rpc/loopa_search_budget')){budgetCalls.push(JSON.parse(options.body));return Response.json({allowed:budgetAllowed,retry_after:3},{status:budgetFail?500:200});}
  calls.push({url,options});
  if(fail)throw new Error('provider unavailable');
  if(url.includes('suggestqueries.google.com'))return Response.json(['query',suggestions]);
  if(bridgeStatus!==200)return new Response(null,{status:bridgeStatus,headers:{'Retry-After':'4'}});
  return Response.json({items,next:'2'});
 }};
 vm.runInNewContext(source,context);
 return {calls,budgetCalls,lastResponse:()=>lastResponse,setAuthorized:v=>authorized=v,advance:ms=>now+=ms,invoke:async body=>{
  const response=await handler(new Request('https://test/video-search',{method:'POST',headers:{Authorization:'Bearer fixture','Content-Type':'application/json'},body:JSON.stringify(body)}));
  lastResponse=response;return {status:response.status,data:await response.json()};
 }};
}
test('RUTUBE autocomplete never searches the catalog and caches bounded unique phrases',async()=>{
 const s=server({suggestions:['званый ужин','званый ужин',null,'','x'.repeat(151),'обзор','кино','шоу','клип','природа','ещё']});
 const first=await s.invoke({provider:'rutube',q:'званый',mode:'suggest'});
 assert.equal(first.status,200);
 assert.deepEqual(first.data.suggestions,['званый ужин','обзор','кино','шоу','клип','природа']);
 assert.equal(s.calls.length,1);
 const url=new URL(s.calls[0].url);
 assert.equal(url.hostname,'suggestqueries.google.com');assert.equal(url.searchParams.get('q'),'званый');
 assert.equal(url.searchParams.has('ds'),false);
 assert.deepEqual((await s.invoke({provider:'rutube',q:'ЗВАНЫЙ',mode:'suggest'})).data,first.data);
 assert.equal(s.calls.length,1);
 s.setAuthorized(false);
 assert.equal((await s.invoke({provider:'rutube',q:'званый',mode:'suggest'})).status,401);
 assert.equal(s.calls.length,1);
 s.setAuthorized(true);s.advance(600001);
 await s.invoke({provider:'rutube',q:'званый',mode:'suggest'});assert.equal(s.calls.length,2);
});
test('YouTube video autocomplete has a separate cache from general RUTUBE query completions',async()=>{
 const s=server();
 for(const provider of ['rutube','youtube','rutube','youtube'])await s.invoke({provider,q:'природа',mode:'suggest'});
 assert.equal(s.calls.length,2);
 assert.equal(new URL(s.calls[1].url).searchParams.get('ds'),'yt');
});
test('submitted RUTUBE searches still use the catalog and keep page-specific cache',async()=>{
 const items=[{title:'Природа',url:'https://rutube.ru/video/fixture/'}],s=server({items});
 const first=await s.invoke({provider:'rutube',q:'природа'});
 assert.deepEqual(first,{status:200,data:{items,next:'2'}});
 await s.invoke({provider:'rutube',q:'ПРИРОДА'});assert.equal(s.calls.length,1);
 assert.match(s.calls[0].url,/functions.yandexcloud.net/);
 await s.invoke({provider:'rutube',q:'природа',page:2});assert.equal(s.calls.length,2);
 assert.deepEqual(JSON.parse(s.calls[1].options.body),{q:'природа',page:2});
 s.advance(120001);await s.invoke({provider:'rutube',q:'природа'});assert.equal(s.calls.length,3);
});
test('failed suggestions do not block search or cache a provider failure',async()=>{
 const s=server({fail:true});
 assert.deepEqual(await s.invoke({provider:'rutube',q:'природа',mode:'suggest'}),{status:200,data:{suggestions:[]}});
 assert.equal((await s.invoke({provider:'rutube',q:'природа'})).status,502);
 assert.equal(s.calls.length,2);
});
test('invalid requests do not reach RUTUBE; other provider suggestions remain intact',async()=>{
 const s=server();
 for(const body of [{q:'а'},{q:'a'.repeat(101)},{q:'природа',page:0},{q:'природа',page:101}]){
  assert.equal((await s.invoke({provider:'rutube',...body})).status,400);
 }
 assert.equal(s.calls.length,0);
 assert.deepEqual((await s.invoke({provider:'vk',q:'природа',mode:'suggest'})).data,{suggestions:[]});
 assert.deepEqual((await s.invoke({provider:'youtube',q:'природа',mode:'suggest'})).data,{suggestions:['поиск','поиск видео']});
});
test('rapid RUTUBE typing requests only the final prefix and ignores a room change',()=>{
 const html=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
 const code=html.slice(html.indexOf('    function queueSuggestionFetch('),html.indexOf('    function requestSuggestions('));
 let timerId=0;const timers=new Map(),calls=[];
 const c={clearTimeout:id=>timers.delete(id),setTimeout:(fn,ms)=>{timers.set(++timerId,{fn,ms});return timerId;},suggestionTimer:0,suggestionLastRequestAt:0,Date,
  canShowSuggestions:()=>true,suggestionKey:(p,q)=>p+q,readSuggestionMemo:()=>null,suggestionInFlight:new Map(),suggestionRetryAfter:new Map(),currentUser:{id:'owner'},roomState:{code:'room'},suggestionProvider:()=> 'rutube',suggestionField:{value:''},fetchSuggestions:(...args)=>calls.push(args)};
 vm.createContext(c);vm.runInContext(code,c);
 for(const q of ['пр','при','природа']){c.suggestionField.value=q;c.queueSuggestionFetch('rutube',q);}
 assert.equal(timers.size,1);const pending=[...timers.values()][0];assert.equal(pending.ms,35);pending.fn();
 assert.deepEqual(calls,[['rutube','природа','owner','room']]);
 c.queueSuggestionFetch('rutube','пр');assert.equal([...timers.values()].at(-1).ms,0);
 c.suggestionLastRequestAt=Date.now();c.queueSuggestionFetch('rutube','при');assert.ok([...timers.values()].at(-1).ms<=150);
 c.queueSuggestionFetch('rutube','природа');c.roomState.code='another-room';[...timers.values()].at(-1).fn();assert.equal(calls.length,1);
});
test('cached prefix matches render immediately and stay inside their provider',()=>{
 const html=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
 const code=html.slice(html.indexOf('    const suggestionMemo='),html.indexOf('    function canShowSuggestions('));
 const c={Date,byId:()=>({value:'rutube'})};vm.createContext(c);vm.runInContext(code,c);
 c.memoSuggestions('rutube','зв',['Званый ужин','Звезда']);
 assert.deepEqual(Array.from(c.immediateSuggestions('rutube','зван')),['Званый ужин']);
 assert.deepEqual(Array.from(c.immediateSuggestions('youtube','зван')),[]);
});
test('late unrelated prefix replies cannot replace current RUTUBE suggestions',async()=>{
 const html=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
 const memo=html.slice(html.indexOf('    const suggestionMemo='),html.indexOf('    function canShowSuggestions('));
 const fetcher=html.slice(html.indexOf('    async function fetchSuggestions('),html.indexOf('    function queueSuggestionFetch('));
 const pending=[],shown=[],field={value:'пр'},source={value:'rutube'};
 const c={Date,AbortController,setTimeout:()=>1,clearTimeout:()=>{},byId:id=>id==='source'?source:field,
  currentUser:{id:'owner'},roomState:{code:'room'},canShowSuggestions:()=>true,queueSuggestionFetch:()=>{},
  client:{functions:{invoke:()=>new Promise(resolve=>pending.push(resolve))}},
  refreshCurrentSuggestions:()=>shown.push(Array.from(c.immediateSuggestions(source.value,field.value)))};
 vm.createContext(c);vm.runInContext(memo+fetcher,c);
 const old=c.fetchSuggestions('rutube','зв','owner','room'),latest=c.fetchSuggestions('rutube','пр','owner','room');
 pending[1]({data:{suggestions:['природа']}});await latest;
 pending[0]({data:{suggestions:['званый ужин']}});await old;
 assert.deepEqual(shown,[['природа'],['природа']]);
 const swapped=c.fetchSuggestions('rutube','ки','owner','room');c.roomState.code='new-room';
 pending[2]({data:{suggestions:['кино']}});await swapped;
 assert.equal(c.readSuggestionMemo('rutube','ки'),null);
});

test('search and suggestions share durable account quotas across cached calls',async()=>{
 const s=server();
 await s.invoke({provider:'rutube',q:'природа',mode:'suggest'});
 await s.invoke({provider:'rutube',q:'природа',mode:'suggest'});
 await s.invoke({provider:'rutube',q:'природа'});
 assert.deepEqual(s.budgetCalls,[{p_mode:'suggest'},{p_mode:'suggest'},{p_mode:'search'}]);
});
test('exhausted quotas return 429 and Retry-After without calling upstream',async()=>{
 const s=server({budgetAllowed:false});
 for(const mode of ['suggest','search']){
  const result=await s.invoke({provider:'rutube',q:'природа',mode});
  assert.equal(result.status,429);assert.equal(result.data.retry_after,3);
  assert.equal(s.lastResponse().headers.get('Retry-After'),'3');
 }
 assert.equal(s.calls.length,0);
});
test('quota outages fail closed without calling upstream',async()=>{
 const s=server({budgetFail:true});
 assert.equal((await s.invoke({provider:'youtube',q:'природа'})).status,503);
 assert.equal(s.calls.length,0);
});
test('RUTUBE bridge quota exhaustion keeps its status and retry interval',async()=>{
 const s=server({bridgeStatus:429});
 const outcome=await s.invoke({provider:'rutube',q:'природа'});
 assert.equal(outcome.status,429);
 assert.equal(outcome.data.retry_after,4);
 assert.equal(s.lastResponse().headers.get('Retry-After'),'4');
 assert.equal(s.calls[0].options.redirect,'error');
});
