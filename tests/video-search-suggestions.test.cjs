'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const {stripTypeScriptTypes}=require('node:module');
const source=stripTypeScriptTypes(fs.readFileSync(path.join(__dirname,'../supabase/functions/video-search/index.ts'),'utf8'));
function server({items=[],fail=false}={}){
 let handler,authorized=true,now=1000;const calls=[];
 class Clock extends Date{static now(){return now;}}
 const context={Response,URLSearchParams,AbortSignal,Date:Clock,Deno:{env:{get:key=>key==='SUPABASE_URL'?'https://test.supabase.co':'fixture'},serve:fn=>handler=fn},fetch:async(url,options)=>{
  if(url.endsWith('/auth/v1/user'))return Response.json({}, {status:authorized?200:401});
  calls.push({url,options});
  if(fail)throw new Error('provider unavailable');
  if(url.includes('suggestqueries.google.com'))return Response.json(['query',['YouTube suggestion']]);
  return Response.json({items,next:'2'});
 }};
 vm.runInNewContext(source,context);
 return {calls,setAuthorized:v=>authorized=v,advance:ms=>now+=ms,invoke:async body=>{
  const response=await handler(new Request('https://test/video-search',{method:'POST',headers:{Authorization:'Bearer fixture','Content-Type':'application/json'},body:JSON.stringify(body)}));
  return {status:response.status,data:await response.json()};
 }};
}
test('RUTUBE suggestions use bounded unique titles and reuse the first search page',async()=>{
 const items=[' Природа ','Природа','',null,'а','x'.repeat(130),'Вода','Лес','Горы','Море','Океан'].map(title=>({title}));
 const s=server({items});
 const first=await s.invoke({provider:'rutube',q:'природа',mode:'suggest'});
 assert.equal(first.status,200);assert.equal(first.data.suggestions.length,6);
 assert.deepEqual(first.data.suggestions.slice(0,2),['Природа','x'.repeat(100)]);
 const search=await s.invoke({provider:'rutube',q:'ПРИРОДА'});
 assert.deepEqual(search.data,{items,next:'2'});assert.equal(s.calls.length,1);
 await s.invoke({provider:'rutube',q:'природа',page:2});assert.equal(s.calls.length,2);
 assert.deepEqual(JSON.parse(s.calls[1].options.body),{q:'природа',page:2});
});
test('expired RUTUBE cache refreshes, but unauthenticated users never read it',async()=>{
 const s=server({items:[{title:'Природа'}]});
 await s.invoke({provider:'rutube',q:'природа'});
 s.setAuthorized(false);
 assert.equal((await s.invoke({provider:'rutube',q:'природа',mode:'suggest'})).status,401);
 assert.equal(s.calls.length,1);
 s.setAuthorized(true);s.advance(120001);
 await s.invoke({provider:'rutube',q:'природа',mode:'suggest'});assert.equal(s.calls.length,2);
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
 assert.deepEqual((await s.invoke({provider:'youtube',q:'природа',mode:'suggest'})).data,{suggestions:['YouTube suggestion']});
});
test('rapid RUTUBE typing requests only the final prefix and ignores a room change',()=>{
 const html=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
 const code=html.slice(html.indexOf('    function queueSuggestionFetch('),html.indexOf('    function requestSuggestions('));
 let timerId=0;const timers=new Map(),calls=[];
 const c={clearTimeout:id=>timers.delete(id),setTimeout:(fn,ms)=>{timers.set(++timerId,{fn,ms});return timerId;},suggestionTimer:0,suggestionLastRequestAt:0,Date,
  canShowSuggestions:()=>true,suggestionKey:(p,q)=>p+q,readSuggestionMemo:()=>null,suggestionInFlight:new Map(),suggestionRetryAfter:new Map(),currentUser:{id:'owner'},roomState:{code:'room'},suggestionProvider:()=> 'rutube',suggestionField:{value:''},fetchSuggestions:(...args)=>calls.push(args)};
 vm.createContext(c);vm.runInContext(code,c);
 for(const q of ['пр','при','природа']){c.suggestionField.value=q;c.queueSuggestionFetch('rutube',q);}
 assert.equal(timers.size,1);const pending=[...timers.values()][0];assert.equal(pending.ms,350);pending.fn();
 assert.deepEqual(calls,[['rutube','природа','owner','room']]);
 c.queueSuggestionFetch('rutube','природа');c.roomState.code='another-room';[...timers.values()].at(-1).fn();assert.equal(calls.length,1);
});
