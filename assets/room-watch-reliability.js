(function (root) {
  'use strict';

  function normalizeMedia(raw, origin) {
    const url = new URL(String(raw).trim());
    if (url.protocol !== 'https:') throw new Error('Нужна ссылка HTTPS');
    const host = url.hostname.replace(/^(www\.|m\.)/, '');
    const query = url.searchParams;
    let id;

    if (['youtu.be', 'youtube.com'].includes(host)) {
      id = host === 'youtu.be'
        ? url.pathname.slice(1)
        : query.get('v') || url.pathname.match(/^\/(?:shorts|embed|live)\/([^/]+)/)?.[1];
      if (/^[\w-]{11}$/.test(id || '')) {
        return 'https://www.youtube.com/embed/' + id
          + '?enablejsapi=1&playsinline=1&controls=1&fs=1&origin=' + encodeURIComponent(origin);
      }
    }

    if (host === 'rutube.ru') {
      id = url.pathname.match(/^\/(?:video|play\/embed|shorts)\/([a-f\d]{32})\/?$/i)?.[1];
      if (id) return 'https://rutube.ru/play/embed/' + id + '/';
    }

    if (['vk.com', 'vk.ru', 'vkvideo.ru'].includes(host)) {
      const pair = (query.get('z') || url.pathname).match(/(?:video|clip)(-?\d+)_(\d+)/);
      const ownerId = pair?.[1] || query.get('oid');
      const videoId = pair?.[2] || query.get('id');
      if (/^-?\d+$/.test(ownerId || '') && /^\d+$/.test(videoId || '')) {
        return 'https://vkvideo.ru/video_ext.php?oid=' + ownerId + '&id=' + videoId + '&js_api=1'
          + (query.get('hash') ? '&hash=' + encodeURIComponent(query.get('hash')) : '');
      }
    }

    throw new Error('Вставь прямую ссылку на ролик YouTube, VK Видео или RUTUBE.');
  }

  function providerFor(url) {
    try {
      const host = new URL(url).hostname.replace(/^(www\.|m\.)/, '');
      if (host === 'youtube.com' || host === 'youtu.be') return 'youtube';
      if (host === 'rutube.ru') return 'rutube';
      if (host === 'vkvideo.ru' || host === 'vk.com' || host === 'vk.ru') return 'vk';
    } catch {}
    return 'video';
  }

  function playerError(provider, code) {
    if (provider === 'youtube') {
      switch (Number(code)) {
        case 2:
          return {kind: 'error', message: 'Ссылка на YouTube некорректна. Попроси ведущего выбрать другой ролик.'};
        case 5:
          return {kind: 'error', message: 'YouTube не смог воспроизвести ролик во встроенном плеере. Перезагрузи комнату; если не поможет — выбери другое видео.'};
        case 100:
          return {kind: 'error', message: 'Видео YouTube удалено, закрыто или недоступно. Попроси ведущего выбрать другой ролик.'};
        case 101:
        case 150:
          return {kind: 'error', message: 'Автор запретил просмотр этого ролика во встроенном плеере. Попроси ведущего выбрать другое видео на YouTube.'};
        case 153:
          return {kind: 'error', message: 'YouTube не распознал встроенный плеер в этом браузере. Обнови страницу; если не поможет — выбери другой ролик.'};
        default:
          return {kind: 'error', message: 'YouTube не смог запустить это видео. Проверь ссылку или попроси ведущего выбрать другой ролик.'};
      }
    }
    if (provider === 'vk') {
      return {kind: 'error', message: 'VK Видео не смог запустить ролик. Проверь, доступно ли видео по ссылке; если нет — выбери другое.'};
    }
    if (provider === 'rutube') {
      return {kind: 'error', message: 'RUTUBE сообщил об ошибке воспроизведения. Проверь доступность ролика или попроси ведущего выбрать другой.'};
    }
    return {kind: 'error', message: 'Плеер сообщил об ошибке. Проверь интернет или попроси ведущего выбрать другое видео.'};
  }

  function autoplayBlocked(isHost) {
    return {
      kind: 'autoplay',
      message: isHost
        ? 'Браузер заблокировал автозапуск. Нажми ▶ в самом видео, чтобы начать просмотр.'
        : 'Браузер заблокировал автозапуск. Дождись запуска видео ведущим; оно синхронизируется автоматически.'
    };
  }

  function autoplaySoundProhibited(isHost) {
    return {
      kind: 'autoplay-sound',
      message: isHost
        ? 'VK Видео ограничил автозапуск со звуком. Нажми на значок звука в плеере.'
        : 'VK Видео может запуститься без звука. Включи звук в плеере; синхронизация продолжится автоматически.'
    };
  }

  function playerReadyTimeout(provider, isHost) {
    const name = provider === 'youtube' ? 'YouTube'
      : provider === 'vk' ? 'VK Видео'
        : provider === 'rutube' ? 'RUTUBE' : 'видеосервис';
    return {
      kind: 'ready-timeout',
      message: isHost
        ? name + ' не подключил управление плеером. Нажми ▶ в самом видео; если оно не запускается, выбери другой ролик.'
        : name + ' пока не подключил синхронизацию. Проверь интернет и дождись запуска видео ведущим.'
    };
  }

  function syncMessage({errorCode, ready, age} = {}) {
    if (errorCode) {
      if (['PGRST202', '42883'].includes(errorCode)) {
        return 'Синхронизация комнаты не настроена на сервере. Обнови страницу; если сообщение повторится, сообщи нам.';
      }
      return 'Связь с синхронизацией потеряна. Проверь интернет — приложение подключится автоматически.';
    }
    if (ready === false) {
      return 'Ждём ведущего. Когда он подключится и запустит видео, позиция обновится автоматически.';
    }
    if (ready === 'video-mismatch') {
      return 'Видео в комнате сменилось. Подожди, пока плеер обновится.';
    }
    if (ready === true) {
      const numericAge = Number(age);
      if (!Number.isFinite(numericAge)) {
        return 'Не удалось получить позицию ведущего. Обновляем связь — подожди немного.';
      }
      if (numericAge >= 3.5) {
        return 'Ведущий временно не на связи. Дождись переподключения — синхронизация восстановится автоматически.';
      }
    }
    return '';
  }

  function isFreshSample(age) {
    return Number.isFinite(Number(age)) && Number(age) < 3.5;
  }

  function isSnapshotFresh(snapshot, now) {
    return !!snapshot && Number.isFinite(snapshot.expires) && now <= snapshot.expires;
  }

  function snapshotPosition(snapshot, now) {
    if (!snapshot || !Number.isFinite(snapshot.pos) || !Number.isFinite(snapshot.received)) return 0;
    const elapsed = Math.max(0, (now - snapshot.received) / 1000);
    const trustedElapsed = isSnapshotFresh(snapshot, now)
      ? elapsed
      : Math.max(0, (snapshot.expires - snapshot.received) / 1000);
    return Math.max(0, snapshot.pos + (snapshot.playing ? trustedElapsed : 0));
  }

  function correctionDecision({force, now, lastCorrection, manualUntil, measured, target, currentPlaying, desiredPlaying}) {
    const seek = !!force || (now >= manualUntil && (measured === null || Math.abs(measured - target) > 0.8));
    const stateMismatch = currentPlaying !== desiredPlaying;
    const apply = (seek || stateMismatch) && (force || now - lastCorrection >= 1100);
    return {seek, apply};
  }

  root.LOOPAWatchReliability = Object.freeze({
    normalizeMedia,
    providerFor,
    playerError,
    autoplayBlocked,
    autoplaySoundProhibited,
    playerReadyTimeout,
    syncMessage,
    isFreshSample,
    isSnapshotFresh,
    snapshotPosition,
    correctionDecision
  });
})(window);
