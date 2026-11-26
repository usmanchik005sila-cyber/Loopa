const assert = require('node:assert/strict');
const { createHmac, webcrypto } = require('node:crypto');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = readFileSync(path.join(__dirname, '../supabase/functions/loopa-bot/index.js'), 'utf8')
  .replace(/^import .*\n/, '');
const token = 'fixture-bot-token';
const signature = createHmac('sha256', token).update('loopa.telegram.webhook.v1').digest('hex');

test('Telegram inline video search requires a signed update, caches results and respects quota', async () => {
  const env = {
    TELEGRAM_BOT_TOKEN: token, YOUTUBE_API_KEY: 'fixture-youtube-key',
    SUPABASE_SERVICE_ROLE_KEY: 'fixture-service-key', SUPABASE_URL: 'https://example.test'
  };
  const answers = [];
  let receive, searches = 0, quotaChecks = 0, allowed = true, rutubeAvailable = true;
  const consumed = new Set();
  const rtId = '1234567890abcdef1234567890abcdef';
  const verify = (body, proof) => receive(new Request('https://example.test/loopa-bot?action=verify-inline-rutube', {
    method: 'POST', headers: { 'X-Loopa-Inline-Proof': proof }, body
  }));
  vm.runInNewContext(source, {
    Deno: { env: { get: key => env[key] }, serve: handler => { receive = handler; } },
    crypto: webcrypto, TextEncoder, TextDecoder, URL, URLSearchParams, AbortSignal, Response,
    createClient: () => ({
      rpc(name, args) {
        if (name === 'loopa_consume_inline_rutube_ticket') {
          return { abortSignal: async () => {
            const fresh = !consumed.has(args.p_ticket);
            consumed.add(args.p_ticket);
            return { data: fresh };
          }};
        }
        quotaChecks++;
        assert.equal(name, 'loopa_take_inline_video_budget');
        assert.match(args.p_actor, /^[a-f0-9]{64}$/);
        return { abortSignal: async () => ({ data: allowed }) };
      }
    }),
    fetch: async (url, options) => {
      const endpoint = new URL(url);
      if (endpoint.hostname === 'www.googleapis.com') {
        searches++;
        assert.ok(['Аниме','Музыка'].includes(endpoint.searchParams.get('q')));
        assert.equal(endpoint.searchParams.get('videoEmbeddable'), 'true');
        return Response.json({ items: [
          { id: { videoId: 'K8vD4XbI2Ww' }, snippet: { title: 'Пример', channelTitle: 'Автор' } },
          { id: { videoId: '../unsafe' }, snippet: { title: 'Неверный идентификатор' } }
        ] });
      }
      if (endpoint.hostname === 'functions.yandexcloud.net') {
        if (!rutubeAvailable) return Response.json({}, { status: 503 });
        const proof = options.headers['X-Loopa-Inline-Proof'];
        assert.equal((await verify(options.body + ' ', proof)).status, 401);
        assert.equal((await verify(options.body, proof)).status, 200);
        assert.equal((await verify(options.body, proof)).status, 401);
        return Response.json({ items: [{ url: 'https://rutube.ru/video/' + rtId + '/',
          title: 'Ролик RUTUBE', author: 'Канал', duration: 772, image: 'https://pic.rutubelist.ru/cover.jpg' }] });
      }
      assert.equal(endpoint.pathname, '/bot' + token + '/answerInlineQuery');
      answers.push(JSON.parse(options.body));
      return Response.json({ ok: true, result: true });
    }
  });
  const update = (id, query, secret = signature) => receive(new Request('https://example.test/loopa-bot', {
    method: 'POST',
    headers: { 'X-Telegram-Bot-Api-Secret-Token': secret },
    body: JSON.stringify({ inline_query: { id, from: { id: 42 }, query } })
  }));
  assert.equal((await update('bad', 'Аниме', 'wrong')).status, 401);
  assert.equal(answers.length, 0);
  assert.equal((await update('query-1', ' Аниме ')).status, 200);
  assert.equal(answers[0].inline_query_id, 'query-1');
  assert.equal(answers[0].results.length, 3);
  assert.equal(answers[0].results[0].description, 'YouTube · Автор');
  assert.equal(answers[0].results[0].type, 'photo');
  assert.equal(answers[0].results[0].photo_width, 1280);
  assert.equal(answers[0].results[0].photo_height, 720);
  assert.equal(answers[0].results[0].caption, undefined);
  const photo = new URL(answers[0].results[0].photo_url);
  assert.equal(answers[0].results[0].id, 'c4_yt_K8vD4XbI2Ww');
  assert.equal(answers[0].results[0].thumbnail_url, photo.href);
  assert.match(photo.pathname, /\/card-v4\.jpg$/);
  assert.equal(photo.searchParams.get('v'), '4');
  assert.equal(photo.searchParams.get('action'), 'invite_photo');
  assert.match(photo.searchParams.get('sig'), /^[a-f0-9]{64}$/);
  assert.equal(photo.searchParams.get('title'), 'Пример');
  assert.equal(photo.searchParams.get('source'), 'YouTube');
  assert.equal(answers[0].results[0].input_message_content, undefined);
  assert.equal((await receive(new Request(photo,{method:'HEAD'}))).headers.get('content-type'),'image/jpeg');
  for(const [field,value] of [['cover','https://www.rutube.ru/redirect-test'],['title','Подмена'],['seconds','45']]){
    const changed=new URL(photo);
    changed.searchParams.set(field,value);
    assert.equal((await receive(new Request(changed,{method:'HEAD'}))).status,403);
  }
  assert.equal(answers[0].results[0].reply_markup.inline_keyboard[0][0].url,
    'https://t.me/LOOPAvideo_bot/loopa?startapp=yt_K8vD4XbI2Ww');

  assert.equal(answers[0].results[1].description, 'RUTUBE · Канал');
  assert.equal(answers[0].results[1].type, 'photo');
  assert.equal(answers[0].results[1].thumbnail_url, answers[0].results[1].photo_url);
  assert.equal(new URL(answers[0].results[1].photo_url).searchParams.get('seconds'), '772');
  assert.equal(answers[0].results[1].reply_markup.inline_keyboard[0][0].url,
    'https://t.me/LOOPAvideo_bot/loopa?startapp=rt_' + rtId);
  assert.equal(consumed.size, 1);
  assert.equal(answers[0].results[2].type, 'article');
  assert.equal(answers[0].results[2].id, 'loopa_open');

  await update('query-2', 'аниме');
  assert.deepEqual(answers[1].results, answers[0].results);
  await update('query-3', 'ан');
  assert.deepEqual(answers[2].results, []);
  assert.equal(quotaChecks, 1);

  allowed = false;
  await update('query-4', 'другой запрос');
  assert.deepEqual(answers[3].results, []);
  assert.equal(answers[3].cache_time, 0);
  assert.equal(searches, 1);
  assert.equal(quotaChecks, 2);

  allowed = true;
  rutubeAvailable = false;
  await update('query-5', 'Музыка');
  assert.deepEqual(answers[4].results, [answers[0].results[0], answers[0].results[2]]);
  assert.equal(answers[4].cache_time, 10);
});

test('room invites send a photo with the original room link and require the host', async () => {
  const code = 'ABCDEF123456';
  const media = 'https://vkvideo.ru/video_ext.php?oid=-7&id=42';
  const env = {
    TELEGRAM_BOT_TOKEN: token, VK_VIDEO_TOKEN: 'fixture-vk-key', SUPABASE_ANON_KEY: 'fixture-anon-key',
    SUPABASE_SERVICE_ROLE_KEY: 'fixture-service-key', SUPABASE_URL: 'https://example.test'
  };
  const prepared = [];
  let receive;
  vm.runInNewContext(source, {
    Deno: { env: { get: key => env[key] }, serve: handler => { receive = handler; } },
    crypto: webcrypto, TextEncoder, TextDecoder, URL, URLSearchParams, AbortSignal, Response,
    createClient: (_url, key, opts) => key === env.SUPABASE_ANON_KEY ? {
      rpc(name, args) {
        assert.equal(name, 'loopa_room_invite_details');
        assert.equal(args.p_code, code);
        return { abortSignal: async () => ({ data: opts.global.headers.Authorization === 'Bearer host' ? { video: media } : null }) };
      }
    } : {
      auth: { getUser: async jwt => ({ data: { user: { id: jwt } } }) },
      from(table) {
        assert.equal(table, 'telegram_miniapp_links');
        return { select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: { telegram_id: 1234 } }) }) }) };
      }
    },
    fetch: async (url, options) => {
      if (url === 'https://api.vk.com/method/video.get') {
        assert.equal(options.body.get('videos'), '-7_42');
        return Response.json({ response: { items: [
          { owner_id: -7, id: 42, title: 'Тестовое видео', duration: 93, image: [{ url: 'https://sun1.userapi.com/cover.jpg' }] }
        ] } });
      }
      if (url === 'https://vkvideo.ru/video-7_42') return new Response(null, { status: 503 });
      assert.match(url, /\/savePreparedInlineMessage$/);
      prepared.push(JSON.parse(options.body));
      return Response.json({ ok: true, result: { id: 'fixture-message' } });
    }
  });
  const invite = jwt => receive(new Request('https://example.test/loopa-bot', {
    method: 'POST', headers: { Origin: 'https://loopacinema.ru', Authorization: 'Bearer ' + jwt },
    body: JSON.stringify({ action: 'share_room', code: code.toLowerCase() })
  }));
  assert.equal((await invite('guest')).status, 403);
  assert.equal(prepared.length, 0);
  assert.deepEqual(await (await invite('host')).json(), { status: 'ready', message_id: 'fixture-message' });
  const message = prepared[0];
  assert.equal(message.allow_user_chats, true);
  assert.equal(message.allow_group_chats, true);
  assert.equal(message.result.type, 'photo');
  assert.equal(message.result.caption, undefined);
  const photo = new URL(message.result.photo_url);
  assert.equal(message.result.thumbnail_url, photo.href);
  assert.equal(photo.searchParams.get('title'),'Тестовое видео');
  assert.equal(photo.searchParams.get('source'),'VK Видео');
  assert.equal(photo.searchParams.get('seconds'),'93');
  assert.deepEqual(message.result.reply_markup.inline_keyboard, [[{
    text: 'Смотреть вместе', url: 'https://t.me/LOOPAvideo_bot/loopa?startapp=room_abcdef123456', style: 'primary'
  }]]);
});

test('tracking commands work only for the bot owner in a private Telegram chat', async () => {
  const linkId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const rpc = [], messages = [];
  const env = { TELEGRAM_BOT_TOKEN:token, LOOPA_OWNER_TELEGRAM_ID:'42',
    SUPABASE_SERVICE_ROLE_KEY:'fixture', SUPABASE_URL:'https://example.test' };
  let receive;
  vm.runInNewContext(source,{
    Deno:{env:{get:key=>env[key]},serve:handler=>{receive=handler;}},
    crypto:webcrypto,TextEncoder,URL,Response,AbortSignal,
    createClient:()=>({from:()=>({upsert:async()=>({error:null})}),rpc:async(name,args)=>{
      rpc.push([name,JSON.parse(JSON.stringify(args))]);
      return {data:name.startsWith('loopa_create')?linkId:[{id:linkId,label:'Космос',visitors:2}]};
    }}),
    fetch:async(url,options)=>{
      assert.match(url,/sendMessage$/);
      messages.push(JSON.parse(options.body));
      return Response.json({ok:true});
    }
  });
  async function command(text, id, type='private'){
    return receive(new Request('https://example.test/loopa-bot',{
      method:'POST',headers:{'X-Telegram-Bot-Api-Secret-Token':signature},
      body:JSON.stringify({message:{chat:{type,id},from:{id},text}})
    }));
  }
  await command('/link Космос', 43);
  await command('/links', 42, 'group');
  assert.equal(rpc.length,0);
  assert.equal(messages.length,0);
  assert.equal((await command('/link   Космос',42)).status,200);
  assert.equal((await command('/links 2',42)).status,200);
  assert.deepEqual(rpc,[
    ['loopa_create_telegram_tracking_link',{p_label:'Космос'}],
    ['loopa_list_telegram_tracking_links',{p_page:2}]
  ]);
  assert.match(messages[0].text,new RegExp('/LOOPAvideo_bot\\?start=ref_'+linkId));
  assert.match(messages[1].text,/Космос · 2 уник/);
  await command('/start',43);
  await command('/start ref_'+linkId,42);
  await command('/start ref_'+linkId,43,'group');
  assert.equal(rpc.length,2);
  await command('/start ref_'+linkId,43);
  await command('/start ref_'+linkId,43);
  const hash=createHmac('sha256',token).update('loopa.tracking.open.v1:'+linkId+':43').digest('hex');
  assert.deepEqual(rpc.slice(2),Array(2).fill([
    'loopa_record_telegram_tracking_open',{p_link_id:linkId,p_visitor_hash:hash}
  ]));
  assert.equal(messages.at(-1).reply_markup.inline_keyboard[0][0].text,'🎬 Открыть LOOPA');
});
