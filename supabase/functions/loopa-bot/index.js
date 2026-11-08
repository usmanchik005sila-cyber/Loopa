// LOOPA Bot welcome handler. No secret credentials stored in GitHub.
// Supabase Edge Function "loopa-bot"; Telegram webhook requests are verified.
const BOT_NAME = "LOOPAvideo_bot";
const SITE_URL = "https://loopacinema.ru/";
const PROJECT_REF = "wnubqzwsvclvcvozibtc";
const WEBHOOK_URL = "https://" + PROJECT_REF + ".supabase.co/functions/v1/loopa-bot";
const utf8 = new TextEncoder();

const WELCOME = [
  "🎬 <b>LOOPA</b>",
  "",
  "Кино становится ближе, когда смотришь вместе.",
  "",
  "Создай комнату, выбери видео и пригласи близкого человека.",
  "Смотрите синхронно и общайтесь в чате — даже на расстоянии.",
  "",
  "Нажми кнопку ниже, чтобы начать."
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
    headers: {"Content-Type":"application/json; charset=utf-8", "Cache-Control":"no-store"}
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
    const command=String(message.text||"").trim().match(/^\/(start|help)(?:@([A-Za-z0-9_]+))?(?:\s|$)/i);
    if(!command||(command[2]&&command[2].toLowerCase()!==BOT_NAME.toLowerCase()))
      return result({ok:true});
    const chatId=message.chat.id;
    if(!Number.isSafeInteger(chatId))return result({ok:true});
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
