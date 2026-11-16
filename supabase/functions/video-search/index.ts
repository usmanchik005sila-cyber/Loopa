// Supabase Edge Function: video-search
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info'};
function reply(body:unknown,status=200){return Response.json(body,{status,headers});}
const suggestionCache=new Map<string,{expires:number,values:string[]}>();
const rutubeCache=new Map<string,{expires:number,data:any}>();
function searchReply(data:any,status=200){return {data,status};}
async function rutubePage(term:string,pageNumber:number,auth:string,timeout=25000){
 const key=JSON.stringify([term.toLocaleLowerCase('ru'),pageNumber]);
 const cached=rutubeCache.get(key);
 if(cached&&cached.expires>Date.now())return searchReply(cached.data);
 const response=await fetch('https://functions.yandexcloud.net/d4e8n1se4iuc8ql4rm82',{
 method:'POST',headers:{'Content-Type':'application/json','X-Loopa-Authorization':auth},
 body:JSON.stringify({q:term,page:pageNumber}),signal:AbortSignal.timeout(timeout)});
 let data;try{data=await response.json();}catch{return searchReply({message:'Поиск RUTUBE ещё не готов. Проверь настройку облачной функции.'},502);}
 if(!response.ok)return searchReply({message:typeof data.message==='string'?data.message:'Облачная функция RUTUBE недоступна. Проверь её версию и публичный доступ.'},response.status===401?401:502);
 if(!Array.isArray(data.items))return searchReply({message:'Обнови код функции RUTUBE в Yandex Cloud.'},502);
 const result={items:data.items,next:data.next??null};
 if(rutubeCache.size>=80)rutubeCache.delete(rutubeCache.keys().next().value!);
 rutubeCache.set(key,{expires:Date.now()+120000,data:result});
 return searchReply(result);
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{headers});
 try{
 const auth=req.headers.get('Authorization')||'';
 const user=await fetch(Deno.env.get('SUPABASE_URL')+'/auth/v1/user',{headers:{Authorization:auth,apikey:Deno.env.get('SUPABASE_ANON_KEY')!}});
 if(!user.ok)return reply({message:'Войди в аккаунт'},401);
 const {provider,q,page,mode}=await req.json();
 if(typeof q!=='string'||q.trim().length<2||q.length>100)return reply({message:'Введи название видео'},400);
 if(mode==='suggest'){
 if(provider==='rutube'){
  try{
   const result=await rutubePage(q.trim(),1,auth,4500);
   if(result.status!==200)return reply({suggestions:[]});
   const suggestions=[...new Set<string>(result.data.items
    .map((item:any)=>typeof item.title==='string'?item.title.trim().slice(0,100):'')
    .filter((title:string)=>title.length>1))].slice(0,6);
   return reply({suggestions});
  }catch{return reply({suggestions:[]});}
 }
 if(provider!=='youtube')return reply({suggestions:[]});
 const term=q.trim(),cacheKey=term.toLocaleLowerCase('ru'),cached=suggestionCache.get(cacheKey);
 if(cached&&cached.expires>Date.now())return reply({suggestions:cached.values});
 try{
 const params=new URLSearchParams({client:'firefox',ds:'yt',hl:'ru',q:term,ie:'utf-8',oe:'utf-8'});
 const response=await fetch('https://suggestqueries.google.com/complete/search?'+params,{signal:AbortSignal.timeout(3000)});
 if(!response.ok)return reply({suggestions:[]});
 const data=await response.json();
 const values=Array.isArray(data?.[1])?[...new Set<string>(data[1].filter((v:unknown):v is string=>typeof v==='string'&&v.length>0&&v.length<=150))].slice(0,6):[];
 if(suggestionCache.size>=200)suggestionCache.delete(suggestionCache.keys().next().value!);
 suggestionCache.set(cacheKey,{expires:Date.now()+600000,values});
 return reply({suggestions:values});
 }catch{return reply({suggestions:[]});}
 }
 if(provider==='youtube'){
 const key=Deno.env.get('YOUTUBE_API_KEY');if(!key)return reply({message:'Поиск YouTube ещё не подключён'});
 const params=new URLSearchParams({key,q,part:'snippet',type:'video',videoEmbeddable:'true',maxResults:'12'});
 if(typeof page==='string'&&page.length<256&&page)params.set('pageToken',page);
 const response=await fetch('https://www.googleapis.com/youtube/v3/search?'+params);const data=await response.json();
 if(!response.ok)return reply({message:'YouTube временно не принимает запросы. Проверь ключ и квоту.'});
 return reply({items:data.items.map((v:any)=>({title:v.snippet.title,author:v.snippet.channelTitle,image:v.snippet.thumbnails.medium?.url,url:'https://youtu.be/'+v.id.videoId})),next:data.nextPageToken});
 }
 if(provider==='rutube'){
 const pageNumber=page==null?1:Number(page);
 if(!Number.isInteger(pageNumber)||pageNumber<1||pageNumber>100)return reply({message:'Некорректная страница'},400);
 const result=await rutubePage(q.trim(),pageNumber,auth);
 return reply(result.data,result.status);
 }
 if(provider!=='vk')return reply({message:'Неизвестный источник'},400);
 const token=Deno.env.get('VK_VIDEO_TOKEN');if(!token)return reply({message:'Поиск VK Видео ещё не подключён'});
 const offset=Math.min(1000,Math.max(0,Number(page)||0));
 const response=await fetch('https://api.vk.com/method/video.search',{method:'POST',body:new URLSearchParams({access_token:token,v:'5.199',q,count:'12',offset:String(offset),adult:'0'})});
 const data=await response.json();if(!data.response)return reply({message:'VK не разрешил поиск с текущим токеном.'});
 return reply({items:data.response.items.filter((v:any)=>v.can_add_to_faves!==undefined||v.id).map((v:any)=>({title:v.title,image:v.image?.at(-1)?.url,url:'https://vkvideo.ru/video'+v.owner_id+'_'+v.id})),next:offset+12<data.response.count&&offset<1000?String(offset+12):null});
 }catch{return reply({message:'Не удалось получить каталог'},502);}
});
