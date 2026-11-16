'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const html=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
const code=html.slice(html.indexOf('    function safeInviteImage('),html.indexOf('    function setInviteCover('));
const c={URL};vm.createContext(c);vm.runInContext(code,c);
test('real RUTUBE CDN cover is accepted without accepting lookalike domains',()=>{
 assert.equal(c.safeInviteImage('https://pic.rtbcdn.ru/video/cover.jpg'),'https://pic.rtbcdn.ru/video/cover.jpg');
 for(const u of ['http://pic.rtbcdn.ru/a.jpg','https://rtbcdn.ru.evil.test/a.jpg','https://evilrtbcdn.ru/a.jpg','https://rtbcdn.ru@evil.test/a.jpg','javascript:alert(1)'])assert.equal(c.safeInviteImage(u),'');
 assert.equal(c.safeInviteImage('https://i.ytimg.com/vi/test/default.jpg'),'https://i.ytimg.com/vi/test/default.jpg');
});
