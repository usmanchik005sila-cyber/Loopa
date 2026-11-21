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

test('host drops a pending fetch after the playback grant changed or the app was hidden', async () => {
  const { c, calls } = setup();
  c.roomState.control_generation = 7;
  c.client.rpc = async () => {
    c.roomState.control_generation = 8;
    return { data: { pending: true, seq: 1, video: 'video', pos: 120, playing: false } };
  };
  await c.receiveGuestControl();
  assert.deepEqual(calls, []);
  c.client.rpc = async () => {
    c.document.hidden = true;
    return { data: { pending: true, seq: 2, video: 'video', pos: 130, playing: false } };
  };
  await c.receiveGuestControl();
  assert.deepEqual(calls, []);
});

test('host does not queue an older click after switching video or sending a newer click', async () => {
  const listenerStart = html.indexOf("    playbackControls.addEventListener('click',async e=>");
  const listener = html.slice(listenerStart, html.indexOf('    // v85:', listenerStart));
  let click;
  let finishSync;
  const writes = [];
  const sandbox = {
    roomState: { code: 'ROOM', video: 'video', pos: 21 },
    roomEpoch: 1, hostTransportRequest: 0, sharedMode: false, rutubeAd: false,
    mediaDuration: 0, timelineTarget: null, sample: null, applyingUntil: 0, pending: null,
    performance: { now: () => 100 },
    playbackControls: { addEventListener: (_name, handler) => { click = handler; } },
    hostHere: () => Boolean(sandbox.roomState),
    revealControls() {}, updatePlaybackControls() {}, commandPlayer() {},
    syncPlayback: () => new Promise(resolve => { finishSync = resolve; }),
    flushPlayback: () => writes.push({ ...sandbox.pending }),
  };
  vm.runInNewContext(listener, sandbox);
  const event = { target: { closest: () => ({ id: 'roomToggle', dataset: {} }) } };

  const beforeSwitch = click(event);
  sandbox.roomState.video = 'new-video';
  finishSync();
  await beforeSwitch;
  assert.deepEqual(writes, []);

  const older = click(event);
  const finishOlder = finishSync;
  const newer = click(event);
  finishSync();
  await newer;
  finishOlder();
  await older;
  assert.equal(writes.length, 1);
  assert.equal(writes[0].video, 'new-video');
});

test('a fresh native player command survives an in-flight reply for the previous grant', async () => {
  const start = html.indexOf('    function guestControlCurrent(');
  const source = html.slice(start, html.indexOf('    // Pull until acknowledged', start));
  const requests = [];
  let finishOld;
  const sandbox = {
    currentUser: { id: 'guest' },
    roomState: { code: 'ROOM', video: 'video', control_generation: 1 },
    roomEpoch: 1, sharedMode: true, guestControlInflight: false, guestControlQueued: null,
    guestManualUntil: 0, document: { hidden: false }, hostHere: () => false,
    performance: { now: () => 100 },
    client: { rpc: (_name, input) => {
      requests.push({...input});
      return requests.length === 1 ? new Promise(resolve => { finishOld = resolve; }) : Promise.resolve({});
    } },
    showToast: message => assert.fail(message),
  };
  vm.runInNewContext(source, sandbox);
  const initial = { code: 'ROOM', video: 'video', user: 'guest', epoch: 1,
    generation: 1, pos: 30, playing: true };
  const old = sandbox.sendGuestControl(initial);
  sandbox.roomState.control_generation = 2;
  await sandbox.sendGuestControl({ ...initial, generation: 2, pos: 60, playing: false });
  finishOld({ error: { message: 'stale context' } });
  await old;
  assert.deepEqual(requests.map(input => [input.expected_generation, input.position_seconds, input.is_playing]),
    [[1, 30, true], [2, 60, false]]);
});
