const assert = require('node:assert/strict');
const test = require('node:test');
const { handleOwnerStats, STATS_REFRESH, formatOwnerStats } = require('../supabase/functions/loopa-bot/owner-stats.mjs');

const chat = { id: 123, type: 'private' };
const message = { chat, from: { id: 123 }, message_id: 10, date: 1767225600, text: '/stats' };
const callback = { id: 'cb', from: { id: 123 }, message, data: STATS_REFRESH };
const stats = {
  as_of: '2026-11-30T04:00:00Z', room_tracking_started_at: '2026-11-28T10:00:00Z',
  registered: 50, new_today: 2, new_7d: 10, new_30d: 20, online: 5,
  active_24h: 8, active_30d: 40, active_rooms: 3, watching_together: 5, rooms_created_24h: 6,
  providers: { youtube: 24, vk: 4, rutube: 8 },
};

async function run(update, options = {}) {
  const calls = [];
  await handleOwnerStats({
    ownerId: 123, ...update, ...options,
    load: async () => {
      calls.push(['load']);
      if (options.unavailable) throw Error('internal db failure');
      return stats;
    },
    api: async (method, payload) => {
      calls.push([method, payload]);
      if (method === 'editMessageText' && options.unchanged) {
        throw Object.assign(Error('message unchanged'), { code: 'message_not_modified' });
      }
    },
  });
  return calls;
}

test('owner stats command loads real aggregate payload and sends a protected message with a blue refresh button', async () => {
  const calls = await run({ message });
  assert.deepEqual(calls.map(([method]) => method), ['load', 'sendMessage']);
  const payload = calls[1][1];
  assert.equal(payload.chat_id, chat.id);
  assert.equal(payload.protect_content, true);
  assert.deepEqual(payload.reply_markup.inline_keyboard, [[{
    text: 'Обновить статистику', style: 'primary', callback_data: STATS_REFRESH,
  }]]);
  assert.match(payload.text, /Зарегистрировано: 50/);
  assert.match(payload.text, /Онлайн: 5/);
  assert.match(payload.text, /Сегодня: 2/);
  assert.match(payload.text, /За 7 дней: 10/);
  assert.match(payload.text, /За 30 дней: 20/);
  assert.match(payload.text, /Активные за 24 часа: 8/);
  assert.match(payload.text, /Активные за 30 дней: 40/);
  assert.match(payload.text, /Активные комнаты: 3/);
  assert.match(payload.text, /Сейчас смотрят вместе: 5/);
  assert.match(payload.text, /Создано комнат за 24 часа: 6/);
  assert.match(payload.text, /YouTube: 24.*VK Видео: 4.*RUTUBE: 8/s);
  assert.match(payload.text, /События комнат учитываются с .* МСК/);
});

test('owner refresh reloads stats and edits the exact message, even when the result is unchanged', async () => {
  const calls = await run({ callback }, { unchanged: true });
  assert.deepEqual(calls.map(([method]) => method), ['load', 'answerCallbackQuery', 'editMessageText']);
  assert.equal(calls[1][1].callback_query_id, callback.id);
  assert.equal(calls[2][1].message_id, message.message_id);
  assert.equal(calls[2][1].chat_id, chat.id);
});

test('owner checks fail closed before accessing Supabase or Telegram', async () => {
  for (const update of [
    { message: { ...message, from: { id: 456 } } },
    { message: { ...message, chat: { ...chat, type: 'group' } } },
    { callback: { ...callback, from: { id: 456 } } },
    { callback: { ...callback, from: { id: '123' } } },
    { callback: { ...callback, message: { ...message, chat: { ...chat, id: 456 } } } },
    { callback: { ...callback, message: { ...message, chat: { ...chat, type: 'group' } } } },
    { callback: { ...callback, message: { ...message, date: 0 } } },
    { callback: { ...callback, message: { ...message, message_id: 0 } } },
    { callback: { ...callback, message: undefined, inline_message_id: 'inline' } },
    { callback: { ...callback, data: 'other' } },
  ]) assert.deepEqual(await run(update), []);
  assert.deepEqual(await run({ message, callback }, { ownerId: null }), []);
});

test('a failed refresh preserves the last message and returns a generic alert', async () => {
  const calls = await run({ callback }, { unavailable: true });
  assert.deepEqual(calls.map(([method]) => method), ['load', 'answerCallbackQuery']);
  assert.equal(calls[1][1].show_alert, true);
  assert.doesNotMatch(calls[1][1].text, /internal/);
  assert.throws(() => formatOwnerStats({ ...stats, registered: null }));
});
