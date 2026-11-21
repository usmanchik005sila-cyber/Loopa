'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
function harness({canSend=true}={}){
 const elements=new Map();function el(){return {children:[],listeners:{},value:'',scrollHeight:400,scrollTop:0,clientHeight:200,append(...x){this.children.push(...x);},replaceChildren(...x){this.children=x;},setAttribute(){},addEventListener(n,f){this.listeners[n]=f;},focus(){},showModal(){this.open=true;},close(){this.open=false;}};}
 const byId=id=>{if(!elements.has(id))elements.set(id,el());return elements.get(id);};
 let page='messages',owner={id:'owner',user_metadata:{}},pendingSend,inserted=0;const profiles=[];const channels=[],removed=[],reports=[],blocks=[];
 const client={rpc:async()=>({data:canSend}),from:()=>{const q={select:()=>q,or:()=>q,order:()=>q,limit:()=>q,insert:()=>{inserted++;return q;},single:()=>new Promise(r=>pendingSend=r),then:resolve=>Promise.resolve({data:[],error:null}).then(resolve)};return q;},channel:name=>{const c={name,on:()=>c,subscribe:()=>c};channels.push(c);return c;},removeChannel:c=>{removed.push(c);return Promise.resolve();}};
 const ctx={window:{}};vm.createContext(ctx);vm.runInContext(fs.readFileSync(path.join(__dirname,'../assets/direct-messages.js'),'utf8'),ctx);
 const api=ctx.window.LOOPADirectMessages.create({getClient:()=>client,getCurrentUser:()=>owner,getPage:()=>page,showPage:p=>page=p,byId,document:{createElement:el,addEventListener(){}},friendAvatar:el,avatarForUser:el,openFriendProfile:p=>{profiles.push(p);page='friend-profile';},openSafetyReport:report=>reports.push(report),showToast:()=>{},blockUser:async id=>{blocks.push(id);return true;}});
 return {api,byId,channels,removed,profiles,reports,blocks,sends:()=>inserted,finishSend:()=>pendingSend({data:{id:1,sender_id:'owner',recipient_id:'peer',body:'hello',created_at:new Date().toISOString()},error:null}),switchUser:()=>owner={id:'other'}};
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

test('chat actions report the current peer, then a confirmed block disables sending',async()=>{
 const h=harness();
 await h.api.openDirectMessage({id:'peer',display_name:'Peer'});
 h.byId('dmActionsToggle').onclick();
 assert.equal(h.byId('dmActionsPanel').hidden,false);
 h.byId('dmReportUser').onclick();
 assert.equal(h.reports[0].userId,'peer');
 assert.equal(h.byId('dmActionsPanel').hidden,true);
 h.byId('dmActionsToggle').onclick();
 h.byId('dmBlockUser').onclick();
 assert.equal(h.byId('dm-block-dialog').open,true);
 h.byId('dm-block-cancel').onclick();
 assert.deepEqual(h.blocks,[]);
 h.byId('dmActionsToggle').onclick();
 h.byId('dmBlockUser').onclick();
 await h.byId('dm-block-confirm').onclick();
 assert.deepEqual(h.blocks,['peer']);
 assert.equal(h.byId('dmInput').disabled,true);
 assert.equal(h.byId('dmSend').disabled,true);
 h.byId('dmInput').value='draft';
 await h.byId('dmForm').listeners.submit({preventDefault(){}});
 assert.equal(h.sends(),0);
});

test('chat history opens with a disabled composer when the server denies sending',async()=>{
 const h=harness({canSend:false});
 await h.api.openDirectMessage({id:'peer'});
 assert.equal(h.byId('dmInput').disabled,true);
 assert.equal(h.byId('dm-error').hidden,false);
 assert.equal(h.channels.length,1);
});
