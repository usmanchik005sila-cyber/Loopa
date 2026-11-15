'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
function setup({getStorage,client}={}){
 const c={};c.window=c;vm.createContext(c);
 for(const file of ['account-continuity.js','resume-storage.js'])vm.runInContext(fs.readFileSync(path.join(__dirname,'../assets',file),'utf8'),c);
 let owner='first';const values=new Map(),notices=[];
 const storage={getItem:k=>values.get(k),setItem:(k,v)=>values.set(k,v)};
 const api=c.LOOPAResumeStorage.create({getClient:()=>client,getUserId:()=>owner,getStorage:getStorage||(()=>storage),isHidden:()=>false,showToast:m=>notices.push(m)});
 return {api,values,notices,switchOwner:id=>owner=id};
}
test('existing local checkpoint format remains readable and accounts stay separate',()=>{
 const {api,values,switchOwner}=setup();const point={video:'video',pos:120,duration:600,savedAt:Date.now()};
 values.set('loopa-resume-v1:first',JSON.stringify([point]));assert.equal(api.readSavedResume('video').pos,120);
 switchOwner('second');assert.equal(api.readSavedResume('video'),null);
 api.writeResumeCheckpoints('second',[{...point,pos:240}]);assert.equal(api.readSavedResume('video').pos,240);
 switchOwner('first');assert.equal(api.readSavedResume('video').pos,120);
});
test('restricted browser storage falls back without throwing',()=>{
 const {api}=setup({getStorage:()=>{throw Error('blocked');}});assert.equal(api.readResumeCheckpoints().length,0);assert.doesNotThrow(()=>api.writeResumeCheckpoints('first',[]));
});
test('cloud completion after account switch never marks a different account saved',async()=>{
 let finish;const pending=new Promise(r=>finish=r);let writes=0;
 const {api,switchOwner}=setup({client:{from:()=>({upsert:()=>{writes++;return pending;}})}});
 const record={video:'video',pos:120,duration:600,savedAt:Date.now()};api.writeResumeCheckpoints('first',[record]);
 const task=api.writeResumeCloud(record,'first',true);switchOwner('second');finish({error:null});await task;
 assert.equal(writes,1);assert.equal(api.readSavedResume('video'),null);
 switchOwner('first');assert.equal(api.readSavedResume('video').cloud,false);
});
test('failed cloud write keeps the local point and deduplicates error notifications',async()=>{
 const {api,notices}=setup({client:{from:()=>({upsert:async()=>({error:{code:'NETWORK'}})})}});
 const record={video:'video',pos:120,savedAt:Date.now()};api.writeResumeCheckpoints('first',[record]);
 assert.equal(await api.writeResumeCloud(record,'first',true),false);assert.equal(await api.writeResumeCloud(record,'first',true),false);
 assert.equal(api.readSavedResume('video').pos,120);assert.equal(notices.length,1);
});
