'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
function harness(){
 const elements=new Map();function el(){return {children:[],listeners:{},value:'',scrollHeight:400,scrollTop:0,clientHeight:200,append(...x){this.children.push(...x);},replaceChildren(...x){this.children=x;},setAttribute(){},addEventListener(n,f){this.listeners[n]=f;}};}
 const byId=id=>{if(!elements.has(id))elements.set(id,el());return elements.get(id);};
 let page='messages',owner={id:'owner',user_metadata:{}},pendingSend,inserted=0;const profiles=[];const channels=[],removed=[];
 const client={from:()=>{const q={select:()=>q,or:()=>q,order:()=>q,limit:()=>q,insert:()=>{inserted++;return q;},single:()=>new Promise(r=>pendingSend=r),then:resolve=>Promise.resolve({data:[],error:null}).then(resolve)};return q;},channel:name=>{const c={name,on:()=>c,subscribe:()=>c};channels.push(c);return c;},removeChannel:c=>{removed.push(c);return Promise.resolve();}};
 const ctx={window:{}};vm.createContext(ctx);vm.runInContext(fs.readFileSync(path.join(__dirname,'../assets/direct-messages.js'),'utf8'),ctx);
 const api=ctx.window.LOOPADirectMessages.create({getClient:()=>client,getCurrentUser:()=>owner,getPage:()=>page,showPage:p=>page=p,byId,document:{createElement:el},friendAvatar:el,avatarForUser:el,openFriendProfile:p=>{profiles.push(p);page='friend-profile';},openSafetyReport:()=>{},showToast:()=>{}});
 return {api,byId,channels,removed,profiles,sends:()=>inserted,finishSend:()=>pendingSend({data:{id:1,sender_id:'owner',recipient_id:'peer',body:'hello',created_at:new Date().toISOString()},error:null}),switchUser:()=>owner={id:'other'}};
}
test('module opens a conversation, suppresses duplicate sends and releases its channel on reset',async()=>{
 const h=harness();await h.api.openDirectMessage({id:'peer',display_name:'Peer'});assert.equal(h.api.returnPage,'messages');assert.equal(h.channels.length,1);
 h.byId('dmInput').value='hello';const submit=h.byId('dmForm').listeners.submit;const pending=submit({preventDefault(){}});await submit({preventDefault(){}});assert.equal(h.sends(),1);h.finishSend();await pending;assert.equal(h.byId('dmInput').value,'');h.api.reset();assert.equal(h.removed.length,1);
});
test('send completion after an account switch does not clear the new account input',async()=>{
 const h=harness();await h.api.openDirectMessage({id:'peer'});h.byId('dmInput').value='hello';const pending=h.byId('dmForm').listeners.submit({preventDefault(){}});h.api.reset();h.switchUser();h.byId('dmInput').value='new draft';h.finishSend();await pending;assert.equal(h.byId('dmInput').value,'new draft');
});
test('inbox subscriptions are deduplicated and stopped on reset',()=>{
 const h=harness();h.api.subscribeMessagesInbox();h.api.subscribeMessagesInbox();assert.equal(h.channels.length,1);h.api.reset();assert.equal(h.removed.length,1);
});

test('conversation avatar opens peer profile and return restores conversation navigation',async()=>{
 const h=harness();await h.api.openDirectMessage({id:'peer',display_name:'Peer'});
 h.byId('dmInput').value='draft';
 h.byId('dmPeerAvatar').onclick();assert.equal(h.profiles[0].id,'peer');
 await h.api.resumeDirectMessage();assert.equal(h.api.returnPage,'messages');assert.equal(h.byId('dmInput').value,'draft');
 assert.equal(h.channels.length,2);
 h.api.reset();h.byId('dmPeerAvatar').onclick();assert.equal(h.profiles.length,1);
});
