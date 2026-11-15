'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const html=fs.readFileSync(path.join(root,'index.html'),'utf8');
const sql=fs.readFileSync(path.join(root,'supabase/migrations/20261115162000_shared_control_explicit_grant.sql'),'utf8');
const rollback=fs.readFileSync(path.join(root,'supabase/rollback/20261115_shared_control_explicit_grant_down.sql'),'utf8');

test('guest permission is based on same-video live server grant, not just checkbox',()=>{
  assert.match(html,/sharedMode=!!\(roomState\?\.shared_control/);
  assert.match(html,/roomState\.shared_control_video===roomState\.video/);
  assert.match(html,/Date\.parse\(roomState\.shared_control_until\)>Date\.now\(\)/);
  assert.match(html,/guestPlaybackLock\.hidden=!active\|\|host\|\|sharedMode;/);
});
test('host must renew its own grant and it is revoked on exit',()=>{
  assert.match(html,/action:'renew',room_code:code/);
  assert.match(html,/action:'mode',room_code:roomState\.code,enabled:false/);
  assert.match(html,/guestManualUntil=0;applyRoom\(true\)/);
});
test('server denies guest control without a live host and video grant',()=>{
  assert.match(sql,/shared_control_video<>room_row\.video/);
  assert.match(sql,/shared_control_until<=clock_timestamp\(\)/);
  assert.match(sql,/m\.member=room_row\.host/);
  assert.match(sql,/Совместное управление выключено/);
  assert.match(sql,/action='renew'/);
  assert.match(sql,/action='mode'/);
  assert.match(sql,/control_applied_seq=r\.control_seq/);
  assert.match(sql,/shared_control=false,shared_control_video='',shared_control_until=null/);
});
test('changing video revokes the grant and pending control',()=>{
  assert.match(sql,/new\.video is distinct from old\.video/);
  assert.match(sql,/new\.shared_control=false/);
  assert.match(sql,/new\.control_applied_seq=new\.control_seq/);
  assert.match(sql,/create trigger loopa_revoke_collab_video/);
});
test('server revert script restores previous functions and columns',()=>{
  assert.match(rollback,/drop trigger if exists loopa_revoke_collab_video/);
  assert.match(rollback,/drop column if exists shared_control_until/);
  assert.match(rollback,/CREATE OR REPLACE FUNCTION public\.loopa_collab27/);
  assert.match(rollback,/CREATE OR REPLACE FUNCTION public\.loopa_sync57/);
});
