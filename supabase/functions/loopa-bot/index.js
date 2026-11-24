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
const REQUEST_ID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function ownerTelegramId(){
  const value=String(Deno.env.get("LOOPA_OWNER_TELEGRAM_ID")||"").trim();
  const id=Number(value);
  return /^[1-9][0-9]{0,19}$/.test(value)&&Number.isSafeInteger(id)?id:null;
}
function trackingLink(id){
  if(!REQUEST_ID_RE.test(id||""))throw Error("invalid_tracking_link");
  return "https://t.me/"+BOT_NAME+"?start=ref_"+id;
}
async function handleTrackingCommand(token,chatId,command,args){
  let text;
  if(command==="link"){
    const label=args.trim().replace(/\s+/gu," ");
    if(!label||[...label].length>48||/\p{C}/u.test(label)){
      text="Чтобы создать ссылку, отправь /link и название до 48 символов. Например: /link Анонс в канале";
    }else{
      const {data,error}=await adminClient().rpc("loopa_create_telegram_tracking_link",{p_label:label});
      if(error)throw error;
      text=label+"\n"+trackingLink(data)+"\n\nСтатистика: /links";
    }
  }else{
    const page=args.trim()||"1";
    if(!/^\d{1,5}$/.test(page)||Number(page)<1||Number(page)>10000){
      text="Чтобы открыть другую страницу, отправь /links и номер страницы.";
    }else{
      const {data,error}=await adminClient().rpc("loopa_list_telegram_tracking_links",{p_page:Number(page)});
      if(error||!Array.isArray(data))throw Error("tracking_links_unavailable");
      const entries=data.slice(0,10).map(row=>row.label+" · "+row.visitors+" уник.\n"+trackingLink(row.id));
      text=entries.length?["Уникальные запуски бота · страница "+Number(page),...entries].join("\n\n")
        :"На этой странице ссылок нет. Создай ссылку командой /link Название.";
      if(data.length>10&&Number(page)<10000)text+="\n\nДальше: /links "+(Number(page)+1);
    }
  }
  await botAPI(token,"sendMessage",{chat_id:chatId,text,link_preview_options:{is_disabled:true}});
}
function isMissingAuthUser(error){
  const message=String(error?.message||"").toLowerCase();
  return error?.status===404||error?.code==="user_not_found"||message.includes("user not found");
}
function deletionNoticeText(requestId,status){
  const heading=status==="completed"?"✅ Удаление аккаунта LOOPA завершено":
    status==="failed_after_auth"?"⚠️ Аккаунт удалён, но очистка данных требует повтора":
    status==="failed"?"⚠️ Автоматическое удаление не завершено":
    "🛡 Заявка на автоматическое удаление LOOPA";
  return heading+"\n\nНомер заявки: <code>"+escapeHtml(requestId)+"</code>"+
    (status==="failed_after_auth"||status==="failed"
      ?"\nДля повтора обработки отправь /retrydelete "+escapeHtml(requestId)+".":"");
}
async function editDeletionNotice(token,chatId,messageId,requestId,status){
  if(!chatId||!messageId)return;
  try{
    await botAPI(token,"editMessageText",{
      chat_id:chatId,message_id:messageId,
      text:deletionNoticeText(requestId,status),parse_mode:"HTML",
      reply_markup:{inline_keyboard:[]}
    });
  }catch{}
}
async function clearAccountAvatars(db,userId){
  const avatars=db.storage.from("avatars");
  const prefixes=[userId];
  const paths=[];
  const pageSize=100;
  for(const prefix of prefixes){
    for(let offset=0;;offset+=pageSize){
      const {data:files,error}=await avatars.list(prefix,{
        limit:pageSize,offset,sortBy:{column:"name",order:"asc"}
      });
      if(error)throw error;
      const page=files||[];
      for(const file of page){
        const name=file?.name;
        if(typeof name!=="string"||!name||name==="."||name===".."||name.includes("/"))
          throw Error("invalid_avatar_object_name");
        const path=prefix+"/"+name;
        if(file.id)paths.push(path);
        else prefixes.push(path);
      }
      if(page.length<pageSize)break;
    }
  }
  for(let offset=0;offset<paths.length;offset+=pageSize){
    const {error}=await avatars.remove(paths.slice(offset,offset+pageSize));
    if(error)throw error;
  }
}
async function processAccountDeletion(db,token,requestId,actorId,ownerId){
  const {data:claim,error:claimError}=await db.rpc("loopa_account_deletion_process_v1",{
    p_action:"claim",p_request_id:requestId,p_actor:actorId||null
  });
  if(claimError)return {error:"delete_request_unavailable",httpStatus:500};
  if(claim?.status==="already_processing")return {error:"deletion_already_processing",httpStatus:409};
  if(claim?.status!=="processing")return {error:"delete_request_not_pending",httpStatus:409};
  const userId=String(claim.user_id||"");
  if(!REQUEST_ID_RE.test(userId))return {error:"invalid_delete_owner",httpStatus:500};

  let notice;
  if(ownerId){
    try{
      notice=await botAPI(token,"sendMessage",{
        chat_id:ownerId,
        text:deletionNoticeText(requestId,"processing"),
        parse_mode:"HTML",
        link_preview_options:{is_disabled:true}
      });
    }catch{
      console.error("deletion_owner_notice_unavailable");
    }
  }

  let authDeleted=false,authDeleteStarted=false;
  try{
    const {data:userResult,error:userLookupError}=await db.auth.admin.getUserById(userId);
    if(userLookupError&&!isMissingAuthUser(userLookupError))throw userLookupError;
    authDeleted=!userResult?.user;

    await clearAccountAvatars(db,userId);
    if(!authDeleted){
      authDeleteStarted=true;
      const {error:deleteError}=await db.auth.admin.deleteUser(userId);
      if(deleteError&&!isMissingAuthUser(deleteError))throw deleteError;
      authDeleted=true;
      // Remove any final upload that completed while Auth was being deleted.
      await clearAccountAvatars(db,userId);
    }

    const {data:purged,error:purgeError}=await db.rpc("loopa_account_deletion_process_v1",{
      p_action:"purge",p_request_id:requestId,p_actor:null
    });
    if(purgeError)throw purgeError;
    if(purged?.status!=="purged")throw Error("deletion_cleanup_incomplete");

    const {data:completed,error:completeError}=await db.rpc("loopa_account_deletion_process_v1",{
      p_action:"complete",p_request_id:requestId,p_actor:null
    });
    if(completeError)throw completeError;
    if(completed?.status!=="completed")throw Error("deletion_finalize_incomplete");

    await editDeletionNotice(token,ownerId,notice?.message_id,requestId,"completed");
    if(claim.telegram_id){
      try{
        await botAPI(token,"sendMessage",{
          chat_id:Number(claim.telegram_id),
          text:"Запрос на удаление LOOPA выполнен. Аккаунт и связанные данные удалены.",
          link_preview_options:{is_disabled:true}
        });
      }catch{}
    }
    return {status:"completed",request_id:requestId};
  }catch{
    console.error(authDeleted?"account_deletion_cleanup_failed":"account_deletion_failed");
    if(!authDeleted&&!authDeleteStarted){
      await db.rpc("loopa_account_deletion_process_v1",{
        p_action:"release",p_request_id:requestId,p_actor:actorId||null
      }).catch(()=>{});
    }
    const status=authDeleted?"failed_after_auth":"failed";
    await editDeletionNotice(token,ownerId,notice?.message_id,requestId,status);
    if(authDeleted&&ownerId&&!notice?.message_id){
      try{
        await botAPI(token,"sendMessage",{
          chat_id:ownerId,text:deletionNoticeText(requestId,"failed_after_auth"),
          parse_mode:"HTML",link_preview_options:{is_disabled:true}
        });
      }catch{}
    }
    return {
      error:authDeleted?"account_deleted_cleanup_incomplete":"account_deletion_failed",
      httpStatus:authDeleted?500:503
    };
  }
}
function safeCover(value){
  if(typeof value!=="string"||value.length>800)return "";
  try{
    const url=new URL(value);
    if(url.protocol==="https:"&&!url.username&&!url.password&&!url.port&&
      (url.hostname==="pic.rutubelist.ru"||
      /(^|\.)(ytimg\.com|rtbcdn\.ru|rutube\.ru|userapi\.com|vkusercdn\.ru|vkvideo\.ru)$/.test(url.hostname))){
      url.hash="";
      return url.href;
    }
  }catch{}
  return "";
}
const inviteCardUrl=WEBHOOK_URL+"/card-v3.jpg?action=invite_photo";
const invitePlatform=new Set(["YouTube","VK Видео","RUTUBE"]);
function cardText(value,maxLength){
  return typeof value==="string"?Array.from(value.normalize("NFC").replace(/\s+/g," ")
    .replace(/[\p{Cc}\p{Cf}]/gu,"").trim()).slice(0,maxLength).join(""):"";
}
function inviteDetails(title,source,cover,duration){
  return {title:cardText(title,220),source:invitePlatform.has(source)?source:"",cover:safeCover(cover),
    seconds:Number.isSafeInteger(duration)&&duration>0&&duration<=604800?duration:0};
}
async function photoCard(token,id,title,source,cover,url,duration,author){
  const details=inviteDetails(title,source,cover,duration);
  const sig=await webhookSecret(token,"loopa.invite.photo.v3:"+JSON.stringify(details));
  const photo=inviteCardUrl+"&"+new URLSearchParams({v:"3",...details,sig});
  return {
    // Telegram iOS can display the thumbnail in the outgoing message. Both URLs must serve the card.
    type:"photo",id:"c3_"+id,photo_url:photo,thumbnail_url:photo,photo_width:1280,photo_height:720,
    title:details.title||"Приглашение в LOOPA",
    description:[details.source,cardText(author,100)].filter(Boolean).join(" · ")||"Совместный просмотр",
    reply_markup:{inline_keyboard:[[{text:"Смотреть вместе",url,style:"primary"}]]}
  };
}
async function serveInvitePhoto(url,token,head){
  const params=url.searchParams,raw=params.get("cover")||"",sig=params.get("sig")||"";
  const details=inviteDetails(params.get("title"),params.get("source"),raw,Number(params.get("seconds")));
  if(url.search.length>7000||raw&&raw!==details.cover)return result({error:"invalid_photo"},403);
  const v=params.get("v");
  if(v==="2"||v==="3"){
    if(!sameSecret(sig,await webhookSecret(token,"loopa.invite.photo.v"+v+":"+JSON.stringify(details))))
      return result({error:"invalid_photo"},403);
  }else{
    if(v||details.title||details.source||details.seconds||raw&&!sameSecret(sig,
      await webhookSecret(token,"loopa.invite.photo.v1:"+details.cover)))return result({error:"invalid_photo"},403);
  }
  const photo=head?null:await (await import("./invite-photo.js")).invitePhoto(details.cover,details);
  const headers={"Content-Type":"image/jpeg","Cache-Control":details.cover?"public, max-age=60":"public, max-age=86400","X-Content-Type-Options":"nosniff"};
  if(photo)headers["Content-Length"]=String(photo.byteLength);
  return new Response(photo,{headers});
}
function roomVideoMetadata(video){
  try{
    const {hostname,pathname,searchParams}=new URL(video);
    const youtube=/^\/embed\/([A-Za-z0-9_-]{11})$/.exec(pathname)?.[1];
    if(hostname==="www.youtube.com"&&youtube)return {provider:"youtube",id:youtube,source:"YouTube",
      cover:"https://i.ytimg.com/vi/"+youtube+"/hqdefault.jpg"};
    const rutube=/^\/play\/embed\/([a-f0-9]{32})\/?$/i.exec(pathname)?.[1];
    if(hostname==="rutube.ru"&&rutube)return {provider:"rutube",id:rutube.toLowerCase(),source:"RUTUBE"};
    const oid=searchParams.get("oid")||"",vid=searchParams.get("id")||"";
    if(hostname==="vkvideo.ru"&&pathname==="/video_ext.php"&&/^-?\d{1,19}$/.test(oid)&&/^\d{1,19}$/.test(vid))
      return {provider:"vk",id:oid+"_"+vid,source:"VK Видео"};
  }catch{}
  return {};
}
async function vkVideos(method,params){
  const key=Deno.env.get("VK_VIDEO_TOKEN");
  if(!key)return null;
  const response=await fetch("https://api.vk.com/method/"+method,{
    method:"POST",body:new URLSearchParams({...params,access_token:key,v:"5.199"}),
    redirect:"error",signal:AbortSignal.timeout(1600)
  });
  if(!response.ok)return null;
  const data=await response.json();
  return Array.isArray(data?.response?.items)?data.response.items:null;
}
function decodeHtmlText(text){
  return text.replace(/&(?:amp|quot|apos|lt|gt|#\d+|#x[a-f0-9]+);/gi,entity=>{
    if(entity[1]!=="#")return ({amp:"&",quot:'"',apos:"'",lt:"<",gt:">"})[entity.slice(1,-1).toLowerCase()]||entity;
    const hex=entity[2].toLowerCase()==="x";
    const code=parseInt(entity.slice(hex?3:2,-1),hex?16:10);
    return code>0&&code<=0x10ffff?String.fromCodePoint(code):"";
  });
}
async function vkPublicMetadata(id){
  const response=await fetch("https://vkvideo.ru/video"+id,{
    redirect:"error",signal:AbortSignal.timeout(1300)
  });
  if(!response.ok||!response.headers.get("content-type")?.includes("text/html")||!response.body)return null;
  const reader=response.body.getReader(),decoder=new TextDecoder();
  let html="",size=0;
  try{
    while(size<160_000&&!/<\/head>/i.test(html)){
      const {done,value}=await reader.read();
      if(done)break;
      html+=decoder.decode(value.subarray(0,160_000-size),{stream:true});
      size+=value.length;
    }
  }finally{await reader.cancel();}
  const properties=new Map();
  for(const [tag] of html.matchAll(/<meta\s[^>]*>/gi)){
    const attrs=new Map([...tag.matchAll(/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)]
      .map(([,key,quoted,single])=>[key.toLowerCase(),quoted??single]));
    if(attrs.has("property")&&attrs.has("content"))properties.set(attrs.get("property"),decodeHtmlText(attrs.get("content")));
  }
  const original=properties.get("og:url")||"";
  if(!["https://vkvideo.ru/video"+id,"https://vk.com/video"+id].includes(original.split("?")[0].replace(/\/$/,"")))return null;
  return {title:properties.get("og:title"),cover:safeCover(properties.get("og:image")),
    duration:Number(properties.get("video:duration"))};
}
const roomMetadataCache=new Map();
async function roomInviteDetails(code,jwt){
  const key=Deno.env.get("SUPABASE_ANON_KEY"),url=Deno.env.get("SUPABASE_URL");
  if(!key||!url)throw Error("room_invite_config_missing");
  const client=createClient(url,key,{global:{headers:{Authorization:"Bearer "+jwt}},
    auth:{autoRefreshToken:false,persistSession:false}});
  const {data,error}=await client.rpc("loopa_room_invite_details",{p_code:code.toUpperCase()})
    .abortSignal(AbortSignal.timeout(1600));
  if(error)throw error;
  return data;
}
async function getRoomVideoCard(room,jwt){
  const info=roomVideoMetadata(room.video);
  if(!info.id)return info;
  info.title=room.title==="Видео"?"":room.title;
  info.cover=safeCover(room.image)||info.cover;
  if(info.title&&info.cover&&info.provider!=="rutube")return info;
  const key=info.provider+":"+info.id,cached=roomMetadataCache.get(key);
  if(cached?.expires>Date.now()){
    const record=await cached.task;
    return {...info,title:info.title||record?.title,cover:info.cover||record?.cover,duration:record?.duration};
  }
  const task=(async()=>{
    if(info.provider==="vk"){
      const [items,publicMetadata]=await Promise.all([
        vkVideos("video.get",{videos:info.id}).catch(()=>null),vkPublicMetadata(info.id).catch(()=>null)
      ]);
      const hit=items?.find(item=>item.owner_id+"_"+item.id===info.id&&!item.is_private);
      return hit?{title:hit.title,cover:safeCover(hit.image?.at(-1)?.url)||publicMetadata?.cover,
        duration:hit.duration||publicMetadata?.duration}:publicMetadata;
    }
    const response=await fetch("https://"+PROJECT_REF+".supabase.co/functions/v1/video-search",{
      method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+jwt},
      body:JSON.stringify({provider:info.provider,id:info.id,mode:"metadata"}),
      redirect:"error",signal:AbortSignal.timeout(1600)
    });
    const {item}=response.ok?await response.json():{};
    return item&&{title:item.title,cover:item.image,duration:item.duration};
  })().catch(()=>null);
  if(roomMetadataCache.size>=80)roomMetadataCache.delete(roomMetadataCache.keys().next().value);
  const entry={task,expires:Date.now()+30_000};
  roomMetadataCache.set(key,entry);
  const record=await task;
  if(record)entry.expires=Date.now()+600_000;
  return {...info,title:info.title||record?.title,cover:info.cover||record?.cover,duration:record?.duration};
}
async function miniAppAction(request,token){
  if(request.headers.get("Origin")!==SITE_ORIGIN)return result({error:"invalid_origin"},403);
  const jwt=/^Bearer (.+)$/i.exec(request.headers.get("Authorization")||"")?.[1];
  if(!jwt)return result({error:"login_required"},401);
  if(Number(request.headers.get("content-length")||0)>2048)return result({error:"too_large"},413);
  const input=await request.json();
  if(!["notify_invite","share_room","delete_account"].includes(input?.action))return result({error:"unknown_action"},400);
  const db=adminClient();
  const {data:auth,error}=await db.auth.getUser(jwt);
  if(error||!auth?.user?.id)return result({error:"login_required"},401);
  const uid=auth.user.id;
  if(input.action==="delete_account"){
    const requestId=String(input.request_id||"");
    if(!REQUEST_ID_RE.test(requestId))return result({error:"invalid_deletion_request"},400);
    const ownerId=ownerTelegramId();
    const outcome=await processAccountDeletion(db,token,requestId,uid,ownerId);
    const {httpStatus,...body}=outcome;
    return result(body,httpStatus||200);
  }
  if(input.action==="notify_invite"){
    if(!/^[0-9a-f-]{36}$/i.test(input.invitation||""))return result({error:"invalid_invite"},400);
    const {data:claim,error:claimError}=await db.rpc("loopa_claim_telegram_invite",{p_invitation:input.invitation,p_sender:uid});
    if(claimError)throw claimError;
    if(!claim)return result({status:"not_eligible"});
    const chatId=Number(claim.telegram_id);
    if(!Number.isSafeInteger(chatId)||chatId<=0)return result({status:"not_eligible"});
    try{
      const room=await roomInviteDetails(claim.code,jwt).catch(()=>null);
      if(room){
        const info=await getRoomVideoCard(room,jwt).catch(()=>({}));
        const card=await photoCard(token,"invite",info.title,info.source,info.cover,roomLink(claim.code),info.duration);
        try{
          await botAPI(token,"sendPhoto",{chat_id:chatId,photo:card.photo_url,reply_markup:card.reply_markup});
          return result({status:"sent"});
        }catch{}
      }
      await botAPI(token,"sendMessage",{
        chat_id:chatId,
        text:"Посмотрим вместе?",
        reply_markup:{inline_keyboard:[[{text:"Смотреть вместе",url:roomLink(claim.code),style:"primary"}]]}
      });
      return result({status:"sent"});
    }catch{return result({status:"telegram_unavailable"});}
  }
  const code=String(input.code||"");
  if(!/^[a-f0-9]{12}$/i.test(code))return result({error:"invalid_room"},400);
  const room=await roomInviteDetails(code,jwt);
  if(!room)return result({error:"not_room_host"},403);
  const {data:link,error:linkError}=await db.from("telegram_miniapp_links").select("telegram_id").eq("user_id",uid).maybeSingle();
  if(linkError)throw linkError;
  const telegramId=Number(link?.telegram_id);
  if(!Number.isSafeInteger(telegramId)||telegramId<=0)return result({error:"telegram_not_linked"},409);
  const info=await getRoomVideoCard(room,jwt).catch(()=>({}));
  const card=await photoCard(token,crypto.randomUUID(),info.title,info.source,info.cover,roomLink(code),info.duration);
  const prepared=await botAPI(token,"savePreparedInlineMessage",{
    user_id:telegramId,result:card,
    allow_user_chats:true,allow_group_chats:true
  });
  return result({status:"ready",message_id:prepared.id});
}


const WELCOME = [
  "<b>LOOPA</b>",
  "",
  "Мини-приложение, в котором можно смотреть видео вместе.",
  "",
  "<i>Лупа будет за вас, если вы будете за Лупу…</i>"
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
    headers: {"Content-Type":"application/json; charset=utf-8", "Cache-Control":"no-store", "Access-Control-Allow-Origin":SITE_ORIGIN, "Access-Control-Allow-Headers":"apikey, authorization, x-client-info, content-type", "Access-Control-Allow-Methods":"GET, POST, OPTIONS", "Vary":"Origin"}
  });
}
function sameSecret(a,b) {
  if(a.length!==b.length)return false;
  let diff=0;
  for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);
  return diff===0;
}
async function webhookSecret(token,context="loopa.telegram.webhook.v1") {
  const key=await crypto.subtle.importKey(
    "raw",utf8.encode(token),{name:"HMAC",hash:"SHA-256"},false,["sign"]
  );
  const signature=new Uint8Array(await crypto.subtle.sign(
    "HMAC",key,utf8.encode(context)
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
const inlineVideos=new Map();
const inlineVideoId=/^[A-Za-z0-9_-]{11}$/;
async function youtubeInlineResults(token,query){
  const key=Deno.env.get("YOUTUBE_API_KEY");
  if(!key)return null;
  const params=new URLSearchParams({
    key,q:query,part:"snippet",type:"video",videoEmbeddable:"true",safeSearch:"moderate",maxResults:"8"
  });
  const response=await fetch("https://www.googleapis.com/youtube/v3/search?"+params,{
    redirect:"error",signal:AbortSignal.timeout(2500)
  });
  if(!response.ok)return null;
  const {items}=await response.json();
  if(!Array.isArray(items))return null;
  const ids=new Set();
  return Promise.all(items.filter(item=>{
    const id=item?.id?.videoId;
    if(!inlineVideoId.test(id||"")||ids.has(id)||!item?.snippet?.title)return false;
    ids.add(id);
    return true;
  }).map(({id:{videoId},snippet})=>photoCard(token,"yt_"+videoId,snippet.title,"YouTube",
    "https://i.ytimg.com/vi/"+videoId+"/hqdefault.jpg",
    "https://t.me/"+BOT_NAME+"/loopa?startapp=yt_"+videoId,undefined,snippet.channelTitle)));
}
const inlineRutubeUrl="https://functions.yandexcloud.net/d4e8n1se4iuc8ql4rm82";
const inlineRutubeId=/^https:\/\/rutube\.ru\/video\/([a-f0-9]{32})\/$/i;
async function rutubeInlineResults(token,query){
  const body=JSON.stringify({q:query,page:1,ticket:crypto.randomUUID(),expires:Date.now()+12000});
  const proof=await webhookSecret(token,"loopa.telegram.inline-rutube.v1:"+body);
  const response=await fetch(inlineRutubeUrl,{
    method:"POST",headers:{"Content-Type":"application/json","X-Loopa-Inline-Proof":proof},
    body,redirect:"error",signal:AbortSignal.timeout(2400)
  });
  if(!response.ok)return null;
  const {items}=await response.json();
  if(!Array.isArray(items))return null;
  const ids=new Set();
  return Promise.all(items.slice(0,8).flatMap(item=>{
    const id=inlineRutubeId.exec(item?.url||"")?.[1]?.toLowerCase();
    if(!id||!item?.title||ids.has(id))return [];
    ids.add(id);
    return [photoCard(token,"rt_"+id,item.title,"RUTUBE",item.image,
      "https://t.me/"+BOT_NAME+"/loopa?startapp=rt_"+id,item.duration,item.author)];
  }));
}
async function vkInlineResults(token,query){
  const items=await vkVideos("video.search",{q:query,count:"8",adult:"0"});
  if(!items)return null;
  const ids=new Set();
  return Promise.all(items.flatMap(item=>{
    const id=item?.owner_id+"_"+item?.id;
    if(!/^-?\d{1,19}_\d{1,19}$/.test(id)||!item.title||item.is_private||ids.has(id))return [];
    ids.add(id);
    return [photoCard(token,"vk_"+id,item.title,"VK Видео",item.image?.at(-1)?.url,
      "https://t.me/"+BOT_NAME+"/loopa?startapp=vk_"+id,item.duration)];
  }));
}
async function verifyInlineRutube(request,token){
  const proof=request.headers.get("X-Loopa-Inline-Proof")||"";
  if(!/^[a-f0-9]{64}$/.test(proof)||Number(request.headers.get("content-length")||0)>4096)
    return result({ok:false},401);
  const reader=request.body?.getReader();
  if(!reader)return result({ok:false},401);
  const bytes=new Uint8Array(4096);
  let size=0;
  while(true){
    const {value,done}=await reader.read();
    if(done)break;
    if(size+value.length>bytes.length){await reader.cancel();return result({ok:false},413);}
    bytes.set(value,size);
    size+=value.length;
  }
  const body=new TextDecoder().decode(bytes.subarray(0,size));
  if(!sameSecret(proof,await webhookSecret(token,"loopa.telegram.inline-rutube.v1:"+body)))
    return result({ok:false},401);
  const ticket=JSON.parse(body),now=Date.now();
  if(!REQUEST_ID_RE.test(ticket?.ticket||"")||!Number.isSafeInteger(ticket.expires)
    ||ticket.expires<=now||ticket.expires>now+12000)
    return result({ok:false},401);
  const {data,error}=await adminClient().rpc("loopa_consume_inline_rutube_ticket",{p_ticket:ticket.ticket})
    .abortSignal(AbortSignal.timeout(1000));
  return result({ok:!error&&data===true},error?503:data===true?200:401);
}
async function handleInlineVideo(token,query){
  const id=query?.id,userId=query?.from?.id;
  if(typeof id!=="string"||!id.length||id.length>128||!Number.isSafeInteger(userId)||userId<=0)return;
  const term=typeof query.query==="string"?query.query.trim().replace(/\s+/g," "):"";
  let results=[],cacheTime=0;
  if(term.length>=3&&term.length<=100){
    const key=term.toLocaleLowerCase("ru");
    const cached=inlineVideos.get(key);
    if(cached?.expires>Date.now()){
      results=cached.results;
      cacheTime=cached.cacheTime;
    }else{
      try{
        const actor=await webhookSecret(token,"loopa.telegram.inline-budget.v1:"+userId);
        const {data,error}=await adminClient().rpc("loopa_take_inline_video_budget",{p_actor:actor})
          .abortSignal(AbortSignal.timeout(1500));
        if(!error&&data===true){
          const [youtube,rutube,vk]=await Promise.all([
            youtubeInlineResults(token,term).catch(()=>null),
            rutubeInlineResults(token,term).catch(()=>null),
            vkInlineResults(token,term).catch(()=>null)
          ]);
          const count=Math.max(youtube?.length||0,rutube?.length||0,vk?.length||0);
          for(let index=0;index<count;index++){
            if(youtube?.[index])results.push(youtube[index]);
            if(rutube?.[index])results.push(rutube[index]);
            if(vk?.[index])results.push(vk[index]);
          }
          if(youtube||rutube||vk){
            cacheTime=youtube&&rutube?60:10;
            if(inlineVideos.size>=100)inlineVideos.delete(inlineVideos.keys().next().value);
            inlineVideos.set(key,{results,cacheTime,expires:Date.now()+(youtube&&rutube?300000:10000)});
          }
        }
      }catch{/* Leave the query retryable if the provider or quota check is unavailable. */}
    }
  }
  // Telegram uses a vertical list when inline results include an article.
  // Keep video results as photos so sending one doesn't require an edit or BotFather feedback.
  const catalog={type:"article",id:"loopa_open",title:"Открыть LOOPA",
    input_message_content:{message_text:"Открыть LOOPA",link_preview_options:{is_disabled:true}},
    reply_markup:{inline_keyboard:[[{text:"Открыть LOOPA",url:"https://t.me/"+BOT_NAME+"/loopa",style:"primary"}]]}};
  await botAPI(token,"answerInlineQuery",{inline_query_id:id,results:results.length?[...results,catalog]:[],cache_time:cacheTime});
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
    issues:!!info.last_error_date,
    inlineMode:!!bot.supports_inline_queries,
    inlineWebhook:!info.allowed_updates?.length||info.allowed_updates.includes("inline_query"),
    inlineProvider:!!Deno.env.get("YOUTUBE_API_KEY"),
    trackingOwnerConfigured:ownerTelegramId()!==null,
    vkSearchConfigured:!!Deno.env.get("VK_VIDEO_TOKEN")};
}
Deno.serve(async request=>{
  try{
    const token=Deno.env.get("TELEGRAM_BOT_TOKEN");
    if(!token)return result({error:"bot_token_not_configured"},503);
    const url=new URL(request.url);
    if(["GET","HEAD"].includes(request.method)&&url.searchParams.get("action")==="invite_photo")
      return await serveInvitePhoto(url,token,request.method==="HEAD");
    if(request.method==="GET"&&url.searchParams.get("action")==="status"){
      const info=await getStatus(token);
      return result(info,info.error?409:200);
    }
    if(request.method==="POST"&&url.searchParams.get("action")==="verify-inline-rutube")
      return await verifyInlineRutube(request,token);
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
    if(update?.inline_query){
      await handleInlineVideo(token,update.inline_query);
      return result({ok:true});
    }
    const retryMessage=update?.message;
    const retryText=String(retryMessage?.text||"").trim();
    const retryMatch=retryText.match(/^\/retrydelete(?:@([A-Za-z0-9_]+))?\s+([0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i);
    if(retryMatch){
      const ownerId=ownerTelegramId();
      const chatId=retryMessage?.chat?.id;
      if(retryMessage?.chat?.type!=="private"||!Number.isSafeInteger(chatId)||retryMessage?.from?.id!==chatId||String(chatId)!==String(ownerId)||(retryMatch[1]&&retryMatch[1].toLowerCase()!==BOT_NAME.toLowerCase())){
        return result({ok:true});
      }
      const outcome=await processAccountDeletion(adminClient(),token,retryMatch[2].toLowerCase(),null,ownerId);
      await botAPI(token,"sendMessage",{
        chat_id:chatId,
        text:outcome.status==="completed"?"Повторная очистка завершена.":"Повторная очистка пока не завершена. Проверь журналы Supabase."
      });
      return result({ok:true});
    }
    const message=update?.message;
    if(!message||message.chat?.type!=="private")return result({ok:true});
    const command=String(message.text||"").trim().match(/^\/(start|help|stop|myid|links?)(?:@([A-Za-z0-9_]+))?(?:\s+([\s\S]*))?$/i);
    if(!command||(command[2]&&command[2].toLowerCase()!==BOT_NAME.toLowerCase()))
      return result({ok:true});
    const chatId=message.chat.id;
    if(!Number.isSafeInteger(chatId))return result({ok:true});
    if(message.from?.id!==chatId)return result({ok:true});
    const name=command[1].toLowerCase();
    if(name==="link"||name==="links"){
      if(chatId===ownerTelegramId())await handleTrackingCommand(token,chatId,name,command[3]||"");
      return result({ok:true});
    }
    if(name==="myid"){
      await botAPI(token,"sendMessage",{
        chat_id:chatId,
        text:"Твой Telegram ID: <code>"+escapeHtml(String(chatId))+"</code>\nУкажи его в секретах Supabase как LOOPA_OWNER_TELEGRAM_ID.",
        parse_mode:"HTML"
      });
      return result({ok:true});
    }
    if(name==="start"&&chatId!==ownerTelegramId()){
      const id=/^ref_([a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12})$/.exec(command[3]||"")?.[1];
      if(id){
        const hash=await webhookSecret(token,"loopa.tracking.open.v1:"+id+":"+chatId);
        const {error}=await adminClient().rpc("loopa_record_telegram_tracking_open",{p_link_id:id,p_visitor_hash:hash});
        if(error)throw error;
      }
    }
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
      text:name==="start"?WELCOME:HELP+(chatId===ownerTelegramId()?"\n\n/link Название — создать ссылку\n/links — статистика ссылок":""),
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
