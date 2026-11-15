'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const html=fs.readFileSync(require('node:path').join(__dirname,'../assets/direct-messages.js'),'utf8');
const source=html.slice(html.indexOf('    async function loadDirectMessages(older=false)'),html.indexOf('    function renderDirectMessages()'));
test('older pages merge without duplicates, retain newer messages, and preserve viewport',async()=>{
 const log={scrollHeight:1000,scrollTop:40,clientHeight:200};let cursor;
 const ctx={client:{from:()=>{const q={select:()=>q,or:()=>q,order:()=>q,limit:()=>q,lt:(_,id)=>{cursor=id;return q;},then:resolve=>resolve({data:[{id:100},{id:99}],error:null})};return q;}},currentUser:{id:'owner'},dmPeer:{id:'peer'},dmHistoryEpoch:1,dmOlderBusy:false,dmHasOlder:true,dmHistory:[{id:100},{id:101},{id:102}],byId:()=>log,renderDirectMessages:()=>{log.scrollHeight=1200;log.scrollTop=1200;},showToast:()=>{},BigInt};
 ctx.getClient=()=>ctx.client;ctx.getCurrentUser=()=>ctx.currentUser;vm.createContext(ctx);vm.runInContext(source,ctx);await ctx.loadDirectMessages(true);
 assert.equal(cursor,100);assert.deepEqual(Array.from(ctx.dmHistory,m=>m.id),[99,100,101,102]);assert.equal(log.scrollTop,240);assert.equal(ctx.dmOlderBusy,false);
});
test('a reply for an abandoned conversation cannot replace the active history',async()=>{
 let complete;const wait=new Promise(r=>complete=r);
 const ctx={client:{from:()=>{const q={select:()=>q,or:()=>q,order:()=>q,limit:()=>wait};return q;}},currentUser:{id:'owner'},dmPeer:{id:'old'},dmHistoryEpoch:1,dmOlderBusy:false,dmHasOlder:false,dmHistory:[],byId:()=>({scrollHeight:0,scrollTop:0,clientHeight:200}),renderDirectMessages:()=>{throw Error('stale render');},showToast:()=>{},BigInt};
 ctx.getClient=()=>ctx.client;ctx.getCurrentUser=()=>ctx.currentUser;vm.createContext(ctx);vm.runInContext(source,ctx);const pending=ctx.loadDirectMessages();ctx.dmPeer={id:'new'};ctx.dmHistoryEpoch++;complete({data:[{id:1}],error:null});await pending;assert.equal(ctx.dmHistory.length,0);
});
