import { createClient } from "npm:@supabase/supabase-js@2";
// LOOPA Bot welcome handler. No secret credentials stored in GitHub.
// Supabase Edge Function "loopa-bot"; Telegram webhook requests are verified.
const BOT_NAME = "LOOPAvideo_bot";
const SITE_ORIGIN = "https://loopacinema.ru";
const SITE_URL = "https://loopacinema.ru/";
const PROJECT_REF = "wnubqzwsvclvcvozibtc";
const WEBHOOK_URL = "https://" + PROJECT_REF + ".supabase.co/functions/v1/loopa-bot";
const utf8 = new TextEncoder();
function adminClient(){
  const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),url=Deno.env.get("SUPABASE_URL");
  if(!key||!url)throw Error("admin_config_missing");
  return createClient(url,key,{auth:{autoRefreshToken:false,persistSession:false}});
}
function roomLink(code){
  if(!/^[a-f0-9]{12}$/i.test(code||""))throw Error("invalid_code");
  return "https://t.me/"+BOT_NAME+"/loopa?startapp=room_"+code.toLowerCase();
}
const escapeHtml=x=>String(x).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
async function miniAppAction(request,token){
  if(request.headers.get("Origin")!==SITE_ORIGIN)return result({error:"invalid_origin"},403);
  const jwt=/^Bearer (.+)$/i.exec(request.headers.get("Authorization")||"")?.[1];
  if(!jwt)return result({error:"login_required"},401);
  if(Number(request.headers.get("content-length")||0)>2048)return result({error:"too_large"},413);
  const input=await request.json();
  if(!["notify_invite","share_room"].includes(input?.action))return result({error:"unknown_action"},400);
  const db=adminClient();
  const {data:auth,error}=await db.auth.getUser(jwt);
  if(error||!auth?.user?.id)return result({error:"login_required"},401);
  const uid=auth.user.id;
  if(input.action==="notify_invite"){
    if(!/^[0-9a-f-]{36}$/i.test(input.invitation||""))return result({error:"invalid_invite"},400);
    const {data:claim,error:claimError}=await db.rpc("loopa_claim_telegram_invite",{p_invitation:input.invitation,p_sender:uid});
    if(claimError)throw claimError;
    if(!claim)return result({status:"not_eligible"});
    const chatId=Number(claim.telegram_id);
    if(!Number.isSafeInteger(chatId)||chatId<=0)return result({status:"not_eligible"});
    try{
      await botAPI(token,"sendMessage",{
        chat_id:chatId,
        text:"🎬 <b>Приглашение в LOOPA</b>\n\n<b>"+escapeHtml(claim.sender_name||"Друг")+"</b> зовёт тебя посмотреть видео вместе.\n\n<i>Один экран. Общие моменты.</i>",
        parse_mode:"HTML",
        reply_markup:{inline_keyboard:[[{text:"🎞 Присоединиться",url:roomLink(claim.code)}]]}
      });
      return result({status:"sent"});
    }catch{return result({status:"telegram_unavailable"});}
  }
  const code=String(input.code||"");
  if(!/^[a-f0-9]{12}$/i.test(code))return result({error:"invalid_room"},400);
  const {data:room,error:roomError}=await db.from("loopa_rooms16").select("host").eq("code",code.toUpperCase()).maybeSingle();
  if(roomError)throw roomError;
  if(room?.host!==uid)return result({error:"not_room_host"},403);
  const {data:link,error:linkError}=await db.from("telegram_miniapp_links").select("telegram_id").eq("user_id",uid).maybeSingle();
  if(linkError)throw linkError;
  const telegramId=Number(link?.telegram_id);
  if(!Number.isSafeInteger(telegramId)||telegramId<=0)return result({error:"telegram_not_linked"},409);
  const prepared=await botAPI(token,"savePreparedInlineMessage",{
    user_id:telegramId,
    result:{
      type:"article",id:crypto.randomUUID(),title:"LOOPA — совместный просмотр",
      description:"Приглашение в твою комнату",
      input_message_content:{
        message_text:"<b><i>🎬 Смотри со мной в LOOPA! 🍿</i></b>\n\n"+roomLink(code),
        parse_mode:"HTML",
        link_preview_options:{is_disabled:false}
      },
      reply_markup:{inline_keyboard:[[{text:"🎞 Открыть комнату",url:roomLink(code)}]]}
    },
    allow_user_chats:true,allow_group_chats:true
  });
  return result({status:"ready",message_id:prepared.id});
}


const WELCOME = [
  "🎞 <b>LOOPA.</b>",
  "",
  "<i>Не просто смотреть. Переживать вместе.</i>",
  "",
  "Вас могут разделять города, страны и тысячи километров.",
  "",
  "Но не смех над одной шуткой. Не эмоции от одного момента. И точно не ваше «ТЫ ЭТО ВИДЕЛ?!»",
  "",
  "<b>Расстояние разделяет людей. LOOPA объединяет моменты.</b>"
].join("\n");
const HELP = [
  "🎬 <b>LOOPA</b>",
  "",
  "Смотри видео вместе с друзьями, где бы вы ни находились.",
  "",
  "Открой приложение, создай комнату и отправь приглашение другу.",
  "Для повторного приветствия отправь /start."
].join("\n");

function result(body, status=200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {"Content-Type":"application/json; charset=utf-8", "Cache-Control":"no-store", "Access-Control-Allow-Origin":SITE_ORIGIN, "Access-Control-Allow-Headers":"apikey, authorization, content-type", "Access-Control-Allow-Methods":"GET, POST, OPTIONS", "Vary":"Origin"}
  });
}
function sameSecret(a,b) {
  if(a.length!==b.length)return false;
  let diff=0;
  for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);
  return diff===0;
}
async function webhookSecret(token) {
  const key=await crypto.subtle.importKey(
    "raw",utf8.encode(token),{name:"HMAC",hash:"SHA-256"},false,["sign"]
  );
  const signature=new Uint8Array(await crypto.subtle.sign(
    "HMAC",key,utf8.encode("loopa.telegram.webhook.v1")
  ));
  return [...signature].map(x=>x.toString(16).padStart(2,"0")).join("");
}
async function botAPI(token,method,payload={}) {
  const response=await fetch("https://api.telegram.org/bot"+token+"/"+method,{
    method:"POST",headers:{"Content-Type":"application/json"},
    body:JSON.stringify(payload),signal:AbortSignal.timeout(10000)
  });
  const data=await response.json().catch(()=>null);
  if(!response.ok||!data?.ok)throw Error("telegram_request_failed");
  return data.result;
}
function webhookState(url){
  return !url?"empty":url===WEBHOOK_URL?"loopa":"external";
}
async function getStatus(token){
  const [bot,info]=await Promise.all([
    botAPI(token,"getMe"),botAPI(token,"getWebhookInfo")
  ]);
  if(bot?.username?.toLowerCase()!==BOT_NAME.toLowerCase()){
    return {error:"bot_token_does_not_match_loopa",webhook:"unknown"};
  }
  return {bot:BOT_NAME,webhook:webhookState(info.url||""),
    pending:Number(info.pending_update_count||0),
    issues:!!info.last_error_date};
}
Deno.serve(async request=>{
  try{
    const token=Deno.env.get("TELEGRAM_BOT_TOKEN");
    if(!token)return result({error:"bot_token_not_configured"},503);
    const url=new URL(request.url);
    if(request.method==="GET"&&url.searchParams.get("action")==="status"){
      const info=await getStatus(token);
      return result(info,info.error?409:200);
    }
    if(request.method==="OPTIONS")return request.headers.get("Origin")===SITE_ORIGIN?result({ok:true}):result({error:"invalid_origin"},403);
    if(request.method==="POST"&&request.headers.has("Authorization"))
      return await miniAppAction(request,token);
    // No mutation endpoint. Webhook installation is configured separately.
    if(request.method!=="POST")return result({error:"method_not_allowed"},405);
    const signature=request.headers.get("X-Telegram-Bot-Api-Secret-Token")||"";
    if(!sameSecret(signature,await webhookSecret(token)))
      return result({error:"invalid_webhook_signature"},401);
    if(Number(request.headers.get("content-length")||0)>65536)
      return result({error:"payload_too_large"},413);
    const raw=await request.text();
    if(raw.length>65536)return result({error:"payload_too_large"},413);
    const update=JSON.parse(raw);
    const message=update?.message;
    if(!message||message.chat?.type!=="private")return result({ok:true});
    const command=String(message.text||"").trim().match(/^\/(start|help|stop)(?:@([A-Za-z0-9_]+))?(?:\s|$)/i);
    if(!command||(command[2]&&command[2].toLowerCase()!==BOT_NAME.toLowerCase()))
      return result({ok:true});
    const chatId=message.chat.id;
    if(!Number.isSafeInteger(chatId))return result({ok:true});
    if(message.from?.id!==chatId)return result({ok:true});
    if(command[1].toLowerCase()==="start"||command[1].toLowerCase()==="stop"){
      const {error}=await adminClient().from("loopa_bot_subscriptions").upsert({
        telegram_id:String(chatId),enabled:command[1].toLowerCase()==="start",
        updated_at:new Date().toISOString()
      },{onConflict:"telegram_id"});
      if(error)throw error;
    }
    if(command[1].toLowerCase()==="stop"){
      await botAPI(token,"sendMessage",{chat_id:chatId,
        text:"🔕 Уведомления LOOPA отключены. Для повторного включения отправь /start."});
      return result({ok:true});
    }
    await botAPI(token,"sendMessage",{
      chat_id:chatId,
      text:command[1].toLowerCase()==="start"?WELCOME:HELP,
      parse_mode:"HTML",
      link_preview_options:{is_disabled:true},
      reply_markup:{
        inline_keyboard:[[{text:"🎬 Открыть LOOPA",
          web_app:{url:SITE_URL}}]]
      }
    });
    return result({ok:true});
  }catch{
    return result({error:"bot_handler_failed"},500);
  }
});
