'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const html=fs.readFileSync(require('node:path').join(__dirname,'../index.html'),'utf8');
const source=html.slice(html.indexOf('    let pendingHostControl=null;'),html.indexOf('    setInterval(receiveGuestControl,500);'));
function setup(){let now=100,seq=1;const calls=[];const c={resumePlayerReady:true,roomState:{code:'TEST',video:'video'},rutubeSignalObserved:false,collabHostPolling:false,hostHere:()=>true,sharedMode:true,document:{hidden:false},rutubeAd:false,roomEpoch:1,performance:{now:()=>now},sample:null,commandPlayer:()=>calls.push('command'),updatePlaybackControls:()=>{},console,client:{rpc:async(_,a)=>{calls.push(a.action);return a.action==='pull'?{data:{pending:true,seq,video:'video',pos:120,playing:false}}:{data:{applied:true}};}}};vm.createContext(c);vm.runInContext(source,c);return {c,calls,tick:n=>now=n,seq:n=>seq=n};}
test('ignored playback command never gets ACK; observed position and state do',async()=>{
 const {c,calls,tick}=setup();await c.receiveGuestControl();assert.ok(!calls.includes('ack'));assert.equal(c.sample,null);
 tick(600);c.sample={pos:120,playing:false,now:550};await c.receiveGuestControl();assert.ok(!calls.includes('ack'),'synthetic sample must not confirm');
 c.sample={pos:120,playing:true,now:560,observed:true};await c.receiveGuestControl();assert.ok(!calls.includes('ack'),'wrong state must not confirm');
 c.sample={pos:120,playing:false,now:570,observed:true};await c.receiveGuestControl();assert.ok(calls.includes('ack'));
});
test('new sequence requires a fresh command and observation',async()=>{
 const {c,calls,tick,seq}=setup();await c.receiveGuestControl();tick(600);seq(2);c.sample={pos:120,playing:false,now:550,observed:true};await c.receiveGuestControl();assert.ok(!calls.includes('ack'));assert.equal(calls.filter(x=>x==='command').length,2);
});

test('guest transport buttons send the current room context and ignore stale replies', async () => {
  const guard = html.slice(html.indexOf('    function guestControlCurrent('), html.indexOf('    function queueGuestControl('));
  const listenerStart = html.indexOf("    playbackControls.addEventListener('click',async e=>");
  const listener = html.slice(listenerStart, html.indexOf('    // v85:', listenerStart));
  const requests = [];
  const applied = [];
  let click;
  const sandbox = {
    currentUser: { id: 'guest' },
    roomState: { code: 'ROOM', video: 'video', control_generation: 7, host: 'host', pos: 21,
      members: [{ id: 'host', online: true }] },
    roomEpoch: 1,
    sharedMode: true,
    rutubeAd: false,
    mediaDuration: 0,
    timelineTarget: null,
    sample: null,
    applyingUntil: 0,
    guestManualUntil: 0,
    document: { hidden: false },
    performance: { now: () => 100 },
    client: { rpc: async (name, input) => {
      requests.push([name, { ...input }]);
      if (requests.length === 2) sandbox.roomState.control_generation++;
      return { error: null };
    } },
    playbackControls: { addEventListener: (_name, handler) => { click = handler; } },
    hostHere: () => false,
    revealControls() {},
    updatePlaybackControls() {},
    commandPlayer: (...args) => applied.push(args),
    showToast: message => assert.fail(message),
  };
  vm.runInNewContext(guard + listener, sandbox);
  const event = { target: { closest: () => ({ id: 'roomToggle', dataset: {} }) } };
  await click(event);
  assert.deepEqual(requests[0], ['loopa_control_v2', {
    room_code: 'ROOM', expected_video: 'video', expected_generation: 7, position_seconds: 21, is_playing: true,
  }]);
  await click(event);
  assert.deepEqual(applied, [[21, true]]);
});
