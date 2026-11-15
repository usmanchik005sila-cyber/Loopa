'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const source=html.slice(html.indexOf('    function observe(playing,pos){'),html.indexOf('    async function flushPlayback(){'));
function observeContext(sharedMode){
 const calls=[];const c={roomState:{video:'test'},sample:{playing:true,pos:20,now:100},performance:{now:()=>100},rutubeAd:false,playerIssue:null,nativeNeedsStart:false,localMuted:false,hostHere:()=>false,LOOPAWatchReliability:{isSnapshotFresh:()=>true},syncSnapshot:{playing:true},positionNow:()=>20,applyingUntil:0,sharedMode,guestSettingsOpen:true,guestManualUntil:0,saveResumeCheckpoint:()=>{},revealControls:()=>{},queueGuestControl:()=>calls.push('publish'),applyRoom:force=>calls.push(force?'restore':'sync'),updatePlaybackControls:()=>{}};
 vm.createContext(c);vm.runInContext(source,c);return {c,calls};
}
test('open personal settings do not publish guest pause or seek without host permission',()=>{
 const {c,calls}=observeContext(false);c.observe(false,250);assert.ok(!calls.includes('publish'));assert.ok(calls.includes('restore'));
});
test('explicit shared control still propagates guest transport actions',()=>{
 const {c,calls}=observeContext(true);c.observe(false,250);assert.ok(calls.includes('publish'));
});
test('personal settings button toggles local access only',()=>{
 const source=html.match(/guestSettingsButton\.addEventListener\('click',\(\)=>\{([\s\S]*?)\}\);/)[1];let renders=0;
 const c={guestSettingsOpen:false,updatePlaybackControls:()=>renders++};vm.createContext(c);vm.runInContext(source,c);assert.equal(c.guestSettingsOpen,true);vm.runInContext(source,c);assert.equal(c.guestSettingsOpen,false);assert.equal(renders,2);
});
