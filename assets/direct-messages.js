(function(root){
  'use strict';
  // Owns conversation state, paging, rendering, and realtime subscriptions.
  function create({getClient,getCurrentUser,getPage,showPage,byId,document,
    friendAvatar,avatarForUser,openSafetyReport,showToast}){
    let dmPeer=null,dmChannel=null,dmHistory=[],dmBusy=false,dmPageReturn='friend-profile';
    let messagesInboxGeneration=0,messagesInboxChannel=null,messagesInboxOwner=null;
    let inboxRows=new Map(),inboxCursor=null,inboxHasMore=false,inboxPaging=false;
    function stopMessagesInbox(){
      if(messagesInboxChannel&&getClient())getClient().removeChannel(messagesInboxChannel).catch(()=>{});
      messagesInboxChannel=null;messagesInboxOwner=null;
    }
    function subscribeMessagesInbox(){
      if(!getClient()||!getCurrentUser())return;
      if(messagesInboxChannel&&messagesInboxOwner===getCurrentUser().id)return;
      stopMessagesInbox();
      messagesInboxOwner=getCurrentUser().id;
      messagesInboxChannel=getClient().channel('loopa-inbox-'+getCurrentUser().id)
        .on('postgres_changes',{event:'INSERT',schema:'public',table:'loopa_dm_messages_v87',filter:'recipient_id=eq.'+getCurrentUser().id},()=>{
          if(getPage()==='messages')refreshMessagesInbox();
        }).subscribe();
    }
    function inboxState(text,allowNav=false){
      const root=byId('messagesList');root.replaceChildren();
      const box=document.createElement('div');box.className='messages-state';box.textContent=text;
      if(allowNav){const btn=document.createElement('button');btn.type='button';btn.textContent='Перейти к друзьям';btn.onclick=()=>showPage('friends');box.append(btn);}
      root.append(box);
    }
    async function refreshMessagesInbox(older=false){
      if(older&&inboxPaging)return;
      if(!older){inboxRows=new Map();inboxCursor=null;}
      inboxPaging=true;
      const previousCursor=inboxCursor;
      const revision=++messagesInboxGeneration,owner=getCurrentUser()?.id;
      if(!owner||!getClient()){inboxPaging=false;inboxState('Войди в LOOPA, чтобы видеть свои переписки.');return;}
      if(!older)inboxState('Загружаем переписки…');
      try{
        const {data,error}=await getClient().rpc('loopa_dm_inbox',{before_id:older?inboxCursor:null,page_size:51});
        if(error)throw error;
        if(revision!==messagesInboxGeneration||getCurrentUser()?.id!==owner)return;
        inboxHasMore=(data||[]).length>50;
        const page=(data||[]).slice(0,50);
        inboxCursor=page.at(-1)?.id||null;
        const latest=inboxRows;
        for(const msg of page){
          const peerId=msg.sender_id===owner?msg.recipient_id:msg.sender_id;
          if(peerId&&!latest.has(peerId))latest.set(peerId,msg);
        }
        if(!latest.size){inboxState('Здесь появятся твои переписки. Открой профиль друга и нажми «Написать», чтобы начать общение.',true);return;}
        const ids=[...latest.keys()];
        const {data:people,error:profileError}=await getClient().rpc('loopa_public_profiles')
          .select('id,display_name,avatar_path,updated_at').in('id',ids);
        if(revision!==messagesInboxGeneration||getCurrentUser()?.id!==owner)return;
        // If a profile isn't public or was removed, keep the conversation accessible.
        const names=new Map((!profileError&&people||[]).map(p=>[p.id,p]));
        const root=byId('messagesList');root.replaceChildren();
        for(const [peerId,msg] of latest){
          const profile=names.get(peerId)||{id:peerId,display_name:'Пользователь LOOPA'};
          const btn=document.createElement('button');btn.type='button';btn.className='message-conversation';
          btn.setAttribute('aria-label','Открыть переписку с '+(profile.display_name||'пользователем'));
          btn.append(friendAvatar(profile));
          const copy=document.createElement('span');copy.className='message-conversation-content';
          const heading=document.createElement('span');heading.className='message-conversation-head';
          const name=document.createElement('strong');name.textContent=profile.display_name||'Пользователь LOOPA';
          const date=document.createElement('time');date.dateTime=msg.created_at;
          const stamp=new Date(msg.created_at);
          date.textContent=Number.isFinite(stamp.getTime())?stamp.toLocaleDateString('ru-RU',{day:'numeric',month:'short'})+' · '+stamp.toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'}):'';
          heading.append(name,date);
          const preview=document.createElement('span');preview.className='message-conversation-preview';
          preview.textContent=(msg.sender_id===owner?'Ты: ':'')+(msg.body||'');
          copy.append(heading,preview);btn.append(copy);
          btn.onclick=()=>openDirectMessage(profile);
          root.append(btn);
        }
        if(inboxHasMore){const more=document.createElement('button');more.type='button';more.className='action';more.textContent='Ещё переписки';more.onclick=()=>refreshMessagesInbox(true);root.append(more);}
      }catch(error){
        if(revision!==messagesInboxGeneration)return;
        if(older){inboxCursor=previousCursor;showToast('Не удалось загрузить старые переписки. Попробуй ещё раз.');}
        else inboxState('Не удалось загрузить переписки. Проверь подключение и попробуй ещё раз.');
      }finally{if(revision===messagesInboxGeneration)inboxPaging=false;}

    }
    function clearDirectMessageChannel(){
      if(dmChannel&&getClient()){getClient().removeChannel(dmChannel).catch(()=>{});dmChannel=null;}
    }
    let dmHistoryEpoch=0,dmOlderBusy=false,dmHasOlder=false;
    async function loadDirectMessages(older=false){
      if(!getClient()||!getCurrentUser()||!dmPeer||(older&&dmOlderBusy))return;
      const owner=getCurrentUser().id,peer=dmPeer.id,epoch=dmHistoryEpoch;
      const log=byId('dmLog'),height=log.scrollHeight,top=log.scrollTop;
      const nearBottom=height-top-log.clientHeight<80,initial=dmHistory.length===0;
      if(older)dmOlderBusy=true;
      try{
        let query=getClient().from('loopa_dm_messages_v87')
          .select('id,sender_id,recipient_id,body,created_at')
          .or(`and(sender_id.eq.${owner},recipient_id.eq.${peer}),and(sender_id.eq.${peer},recipient_id.eq.${owner})`)
          .order('id',{ascending:!older&&!initial}).limit(101);
        if(older&&dmHistory.length)query=query.lt('id',dmHistory[0].id);
        else if(!initial)query=query.gt('id',dmHistory.at(-1).id);
        const {data,error}=await query;
        if(getCurrentUser()?.id!==owner||dmPeer?.id!==peer||epoch!==dmHistoryEpoch)return;
        if(error)throw error;
        if(older||initial)dmHasOlder=(data||[]).length>100;
        const page=(data||[]).slice(0,100);
        if(older||initial)page.reverse();
        const merged=new Map(dmHistory.map(m=>[String(m.id),m]));
        page.forEach(m=>merged.set(String(m.id),m));
        dmHistory=[...merged.values()].sort((a,b)=>BigInt(a.id)<BigInt(b.id)?-1:BigInt(a.id)>BigInt(b.id)?1:0);
        renderDirectMessages();
        if(older)log.scrollTop=top+(log.scrollHeight-height);
        else if(!nearBottom)log.scrollTop=top;
        if(!older&&!initial&&(data||[]).length>100)void loadDirectMessages();
      }catch(error){
        if(epoch===dmHistoryEpoch)showToast('Не удалось загрузить сообщения. Попробуй ещё раз.');
      }finally{if(epoch===dmHistoryEpoch)dmOlderBusy=false;}
    }
    function renderDirectMessages(){
      const log=byId('dmLog');log.replaceChildren();
      if(!dmHistory.length){const el=document.createElement('p');el.className='dm-empty';el.textContent='Сообщений пока нет. Напиши первым.';log.append(el);return;}
      if(dmHasOlder){const more=document.createElement('button');more.type='button';more.className='action';more.textContent='Загрузить ранние сообщения';more.onclick=()=>loadDirectMessages(true);log.append(more);}
      const groups=[];
      for(const msg of dmHistory){
        const last=groups.at(-1);
        const prev=last?.items.at(-1);
        const interval=prev?new Date(msg.created_at)-new Date(prev.created_at):Infinity;
        if(last&&last.sender===msg.sender_id&&interval<300000){last.items.push(msg);}
        else groups.push({sender:msg.sender_id,items:[msg]});
      }
      const current={id:getCurrentUser().id,display_name:byId('profile-name').value||'Ты',avatar_path:getCurrentUser().user_metadata?.avatar_path};
      for(const group of groups){
        const mine=group.sender===getCurrentUser().id,who=mine?current:dmPeer;
        const wrap=document.createElement('div');wrap.className='dm-group '+(mine?'me':'peer');
        const head=document.createElement('span');head.className='dm-group-label';head.textContent=mine?'Ты':(who.display_name||'Друг');wrap.append(head);
        group.items.forEach((msg,index)=>{
          const row=document.createElement('div');row.className='dm-message-row';
          const ava=document.createElement('div');ava.className=index===group.items.length-1?'dm-message-avatar':'dm-avatar-space';
          if(index===group.items.length-1)ava.append(avatarForUser(who));
          const bubble=document.createElement('div');bubble.className='dm-bubble';
          const text=document.createElement('span');text.textContent=msg.body;
          const time=document.createElement('time');time.dateTime=msg.created_at;time.textContent=new Date(msg.created_at).toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'});
          bubble.append(text,time);
          if(!mine){
            const report=document.createElement('button');report.type='button';report.className='dm-message-report';
            report.textContent='⚑';report.title='Пожаловаться на сообщение';report.setAttribute('aria-label','Пожаловаться на сообщение');
            report.onclick=()=>openSafetyReport({userId:msg.sender_id,messageId:msg.id,displayName:who.display_name||'пользователя'});
            bubble.append(report);
          }
          row.append(ava,bubble);wrap.append(row);
        });log.append(wrap);
      }
      log.scrollTop=log.scrollHeight;
    }
    async function openDirectMessage(profile){
      if(!getCurrentUser()||!profile?.id)return;
      if(profile.id===getCurrentUser().id)return;
      dmPageReturn=getPage()==='friend-profile'?'friend-profile':(getPage()==='messages'?'messages':'friends');
      dmHistoryEpoch++;dmOlderBusy=false;dmHasOlder=false;dmHistory=[];
      dmPeer={...profile};
      byId('dmPeerName').textContent=profile.display_name||'Друг';
      byId('dmPeerAvatar').replaceChildren(avatarForUser(profile));
      byId('dmInput').value='';
      byId('dm-error').hidden=true;
      byId('dmLog').replaceChildren();
      clearDirectMessageChannel();
      showPage('dm');
      await loadDirectMessages();
      if(!dmPeer||dmPeer.id!==profile.id||!getCurrentUser()||getPage()!=='dm')return;
      const owner=getCurrentUser().id;
      const peerId=profile.id;
      dmChannel=getClient().channel('loopa-dm-'+owner+'-'+peerId)
        .on('postgres_changes',{event:'INSERT',schema:'public',table:'loopa_dm_messages_v87',filter:'recipient_id=eq.'+owner},payload=>{
          if(dmPeer?.id===payload.new.sender_id)loadDirectMessages();
        }).subscribe();
    }
    byId('dmBack').onclick=()=>{
      clearDirectMessageChannel();
      showPage(dmPageReturn==='friend-profile'?'friend-profile':(dmPageReturn==='messages'?'messages':'friends'));
    };
    byId('dmReportUser').onclick=()=>{
      if(dmPeer)openSafetyReport({userId:dmPeer.id,displayName:dmPeer.display_name||'пользователя'});
    };
    byId('dmForm').addEventListener('submit',async event=>{
      event.preventDefault();
      const body=byId('dmInput').value.trim();
      if(!body||!dmPeer||!getCurrentUser()||dmBusy)return;
      dmBusy=true;byId('dmSend').disabled=true;byId('dm-error').hidden=true;
      const peerId=dmPeer.id,owner=getCurrentUser().id;
      try{
        const {data,error}=await getClient().from('loopa_dm_messages_v87')
           .insert({sender_id:owner,recipient_id:peerId,body})
           .select('id,sender_id,recipient_id,body,created_at').single();
        if(error)throw error;
        if(dmPeer?.id===peerId&&getCurrentUser()?.id===owner){
          byId('dmInput').value='';
          if(!dmHistory.some(item=>item.id===data.id))dmHistory.push(data);
          renderDirectMessages();
        }
      }catch(e){
        const el=byId('dm-error');el.hidden=false;
        el.textContent=/row.level.security|violates row.level|permission denied/i.test(e.message||'')
          ?'Сообщение не отправлено: получатель ограничил переписку или вы заблокированы.'
          :'Не удалось отправить сообщение. Проверь SQL v87 и подключение к Supabase.';
      }finally{dmBusy=false;byId('dmSend').disabled=false;}
    });
    function reset(){
      messagesInboxGeneration++;stopMessagesInbox();clearDirectMessageChannel();
      dmHistoryEpoch++;dmPeer=null;dmHistory=[];dmOlderBusy=false;dmHasOlder=false;
      inboxRows=new Map();inboxCursor=null;inboxHasMore=false;inboxPaging=false;
    }
    return Object.freeze({openDirectMessage,refreshMessagesInbox,subscribeMessagesInbox,
      stopMessagesInbox,clearDirectMessageChannel,reset,get returnPage(){return dmPageReturn;}});
  }
  root.LOOPADirectMessages=Object.freeze({create});
})(window);
