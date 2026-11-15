'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const html=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
const code=html.slice(html.indexOf('    function samplePlayers('),html.indexOf('    async function changeRoomVideo('));
test('VK cached getters are not published as fresh playback samples',()=>{
 const seen=[];const c={roomState:{video:'vk'},ytPlayer:null,vkPlayer:{getCurrentTime:()=>120,getState:()=> 'playing',getDuration:()=>600},observed:{playing:false},observe:(...v)=>seen.push(v),Number};vm.createContext(c);vm.runInContext(code,c);
 c.samplePlayers();c.samplePlayers();assert.equal(seen.length,0);c.samplePlayers(true);assert.equal(seen.length,1);assert.deepEqual(seen[0],[true,120]);assert.equal(c.mediaDuration,600);
});
