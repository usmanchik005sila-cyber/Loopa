(function(root){
  'use strict';
  // Storage and cloud persistence are independent of player and DOM state.
  function create({getClient,getUserId,getStorage,isHidden,showToast}){
    const LOOPAAAccountContinuity=root.LOOPAAAccountContinuity;
    const resumeStorageKeyFor=userId=>userId?'loopa-resume-v1:'+userId:null;
    const resumeCloudWriteAt=new Map(),resumeCloudWritePending=new Map(),resumeCloudWriteQueued=new Map(),resumeCloudErrorShown=new Set();
    function readResumeCheckpoints(userId=getUserId()){
      const key=resumeStorageKeyFor(userId);if(!key)return [];
      try{
        const parsed=JSON.parse(getStorage().getItem(key)||'[]');
        return LOOPAAAccountContinuity.mergeResumeCheckpoints(parsed,[],Date.now());
      }catch{return [];}
    }
    function writeResumeCheckpoints(userId,entries){
      const key=resumeStorageKeyFor(userId);if(!key)return;
      try{getStorage().setItem(key,JSON.stringify(entries.slice(0,20)));}catch{}
    }
    function readSavedResume(video,userId=getUserId()){
      if(!video)return null;
      return readResumeCheckpoints(userId).find(x=>x.video===video)||null;
    }
    function resumeCloudErrorMessage(error){
      if(error?.code==='42P01'||error?.code==='PGRST205')
        return 'Облачное сохранение ещё не настроено. Пока точка просмотра останется на этом устройстве.';
      return 'Не удалось синхронизировать точку просмотра. Проверь подключение; локальная копия сохранена.';
    }
    function reportResumeCloudError(userId,video,error){
      const key=userId+'|'+video;
      if(resumeCloudErrorShown.has(key)||getUserId()!==userId)return;
      resumeCloudErrorShown.add(key);
      if(!isHidden())showToast(resumeCloudErrorMessage(error));
    }
    function markResumeCloudSaved(userId,record){
      const entries=readResumeCheckpoints(userId);
      const current=entries.find(x=>x.video===record.video);
      if(!current||current.savedAt!==record.savedAt||current.pos!==record.pos)return;
      current.cloud=true;
      writeResumeCheckpoints(userId,entries);
    }
    async function writeResumeCloud(record,userId,force=false){
      const client=getClient();
      if(!client||!userId||getUserId()!==userId)return false;
      const key=userId+'|'+record.video;
      if(resumeCloudWritePending.has(key)){
        const queued=resumeCloudWriteQueued.get(key);
        if(!queued||record.savedAt>queued.record.savedAt)resumeCloudWriteQueued.set(key,{record,userId,force});
        return resumeCloudWritePending.get(key).then(()=>{
          const latest=resumeCloudWriteQueued.get(key);
          if(!latest)return true;
          resumeCloudWriteQueued.delete(key);
          return writeResumeCloud(latest.record,latest.userId,latest.force);
        });
      }
      if(!force&&Date.now()-(resumeCloudWriteAt.get(key)||0)<15000)return false;
      resumeCloudWriteAt.set(key,Date.now());
      const pending=(async()=>{
        const {error}=await client.from('loopa_resume_points').upsert({
          user_id:userId,media:record.video,position_seconds:Math.round(record.pos),
          duration_seconds:Math.round(record.duration||0)
        },{onConflict:'user_id,media'});
        if(error)throw error;
        resumeCloudErrorShown.delete(key);
        if(getUserId()===userId)markResumeCloudSaved(userId,record);
        return true;
      })().catch(error=>{reportResumeCloudError(userId,record.video,error);return false;})
        .finally(()=>{
          resumeCloudWritePending.delete(key);
          if(!resumeCloudWriteQueued.has(key))return;
          const latest=resumeCloudWriteQueued.get(key);
          resumeCloudWriteQueued.delete(key);
          void writeResumeCloud(latest.record,latest.userId,latest.force);
        });
      resumeCloudWritePending.set(key,pending);
      return pending;
    }
    async function deleteResumeCloud(video,userId){
      const client=getClient();
      if(!client||!userId||getUserId()!==userId)return;
      try{
        const {error}=await client.from('loopa_resume_points').delete()
          .eq('user_id',userId).eq('media',video);
        if(error)throw error;
        resumeCloudErrorShown.delete(userId+'|'+video);
      }catch(error){reportResumeCloudError(userId,video,error);}
    }
    async function readResumeCloud(video,userId){
      const client=getClient();
      if(!client||!userId||getUserId()!==userId)return null;
      const cutoff=new Date(Date.now()-LOOPAAAccountContinuity.CHECKPOINT_TTL_MS).toISOString();
      const {data,error}=await client.from('loopa_resume_points')
        .select('media,position_seconds,duration_seconds,updated_at')
        .eq('user_id',userId).eq('media',video).gte('updated_at',cutoff).maybeSingle();
      if(error)throw error;
      return LOOPAAAccountContinuity.normalizeResumeCheckpoint(data,Date.now(),true);
    }
    return Object.freeze({resumeStorageKeyFor,readResumeCheckpoints,writeResumeCheckpoints,
      readSavedResume,writeResumeCloud,deleteResumeCloud,readResumeCloud,reportResumeCloudError});
  }
  root.LOOPAResumeStorage=Object.freeze({create});
})(window);
