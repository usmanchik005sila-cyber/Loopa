(function (root) {
  'use strict';

  const CHECKPOINT_TTL_MS = 90 * 24 * 60 * 60 * 1000;
  const MAX_CHECKPOINT_SECONDS = 360000;
  const MAX_CHECKPOINTS = 20;

  function normalizeResumeCheckpoint(raw, now = Date.now(), cloud = false) {
    if (!raw || typeof raw !== 'object') return null;
    const video = typeof raw.video === 'string' ? raw.video
      : typeof raw.media === 'string' ? raw.media : '';
    const pos = Number(raw.pos ?? raw.position_seconds);
    const duration = Number(raw.duration ?? raw.duration_seconds ?? 0);
    const savedAt = Number.isFinite(Number(raw.savedAt))
      ? Number(raw.savedAt)
      : Date.parse(raw.updated_at || '');
    if (!video || video.length > 2048 || !Number.isFinite(pos) ||
        pos < 20 || pos > MAX_CHECKPOINT_SECONDS || !Number.isFinite(savedAt) ||
        savedAt > now + 5 * 60 * 1000 || now - savedAt >= CHECKPOINT_TTL_MS ||
        !Number.isFinite(duration) || duration < 0 || duration > MAX_CHECKPOINT_SECONDS) {
      return null;
    }
    return {
      video,
      pos: Math.round(pos),
      duration: Math.round(duration),
      savedAt,
      cloud: cloud || raw.cloud === true,
      ...(typeof raw.room === 'string' ? {room: raw.room} : {})
    };
  }

  function mergeResumeCheckpoints(local = [], remote = [], now = Date.now()) {
    const byVideo = new Map();
    for (const [records, isCloud] of [[local, false], [remote, true]]) {
      for (const raw of Array.isArray(records) ? records : []) {
        const checkpoint = normalizeResumeCheckpoint(raw, now, isCloud);
        if (!checkpoint) continue;
        const previous = byVideo.get(checkpoint.video);
        if (!previous || checkpoint.savedAt >= previous.savedAt) {
          byVideo.set(checkpoint.video, checkpoint);
        }
      }
    }
    return [...byVideo.values()]
      .sort((a, b) => b.savedAt - a.savedAt)
      .slice(0, MAX_CHECKPOINTS);
  }

  function identityLinkError(error, provider) {
    const raw = `${error?.code || ''} ${error?.message || error || ''}`;
    if (/manual linking|linking is disabled|identity linking is disabled/i.test(raw)) {
      return 'Привязка аккаунтов отключена в настройках Supabase. Включи Allow manual linking и повтори попытку.';
    }
    if (/already linked to another user|identity[_\s-]*already[_\s-]*exists|already (exists|registered)|account.*already.*(used|linked)|conflict/i.test(raw)) {
      return `Этот аккаунт ${provider} уже привязан к другому профилю LOOPA. Выйди и войди в нужный профиль; разные профили автоматически не объединяются.`;
    }
    if (/identity[\s_-]*(?:is[\s_-]*)?already[\s_-]*linked/i.test(raw)) {
      return `Этот аккаунт ${provider} уже привязан к текущему профилю LOOPA. Обнови страницу, чтобы увидеть его статус.`;
    }
    return null;
  }

  root.LOOPAAAccountContinuity = Object.freeze({
    CHECKPOINT_TTL_MS,
    normalizeResumeCheckpoint,
    mergeResumeCheckpoints,
    identityLinkError
  });
})(window);
