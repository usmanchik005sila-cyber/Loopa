export const STATS_REFRESH = "owner_stats_refresh_v1";
const timestamp = new Intl.DateTimeFormat("ru-RU", {
  timeZone: "Europe/Moscow", dateStyle: "short", timeStyle: "medium",
});
const count = new Intl.NumberFormat("ru-RU");

function formattedCount(value) {
  if (!Number.isSafeInteger(value) || value < 0) throw Error("invalid_owner_stats");
  return count.format(value);
}

export function formatOwnerStats(stats) {
  const collected = Date.parse(stats.room_tracking_started_at);
  const sampled = Date.parse(stats.as_of);
  if (!Number.isFinite(collected) || !Number.isFinite(sampled) || collected > sampled) {
    throw Error("invalid_owner_stats_dates");
  }
  const f = formattedCount;
  const lines = [
    "📊 Статистика LOOPA",
    "",
    "Зарегистрировано: " + f(stats.registered),
    "Онлайн: " + f(stats.online),
    "Новые регистрации:",
    "• Сегодня: " + f(stats.new_today),
    "• За 7 дней: " + f(stats.new_7d),
    "• За 30 дней: " + f(stats.new_30d),
    "Активные за 24 часа: " + f(stats.active_24h),
    "Активные за 30 дней: " + f(stats.active_30d),
    "",
    "Активные комнаты: " + f(stats.active_rooms),
    "Сейчас смотрят вместе: " + f(stats.watching_together),
    "Создано комнат за 24 часа: " + f(stats.rooms_created_24h),
    "",
    "Выбор платформы в комнатах за 30 дней:",
    "• YouTube: " + f(stats.providers.youtube),
    "• VK Видео: " + f(stats.providers.vk),
    "• RUTUBE: " + f(stats.providers.rutube),
  ];
  if (sampled - collected < 30 * 86400000) {
    lines.push("", "События комнат учитываются с " + timestamp.format(collected) + " МСК.");
  }
  lines.push("", "Обновлено " + timestamp.format(sampled) + " МСК");
  return lines.join("\n");
}

function isOwnerChat(message, actorId, ownerId) {
  return Number.isSafeInteger(ownerId) && ownerId > 0 && actorId === ownerId
    && message?.chat?.type === "private" && message.chat.id === ownerId;
}

export async function handleOwnerStats({ ownerId, message, callback, load, api }) {
  const target = callback ? callback.message : message;
  const actorId = callback ? callback.from?.id : message?.from?.id;
  if (!isOwnerChat(target, actorId, ownerId)) return;
  if (callback && (callback.data !== STATS_REFRESH || typeof callback.id !== "string"
    || !callback.id.length || callback.id.length > 128 || !Number.isSafeInteger(target.message_id)
    || target.message_id <= 0 || !Number.isSafeInteger(target.date) || target.date <= 0)) return;

  let text;
  try {
    text = formatOwnerStats(await load());
  } catch {
    const unavailable = "Статистика временно недоступна. Попробуй ещё раз.";
    if (callback) {
      await api("answerCallbackQuery", { callback_query_id: callback.id, text: unavailable, show_alert: true });
    } else {
      await api("sendMessage", { chat_id: ownerId, text: unavailable });
    }
    return;
  }
  const payload = {
    chat_id: ownerId, text,
    reply_markup: { inline_keyboard: [[{ text: "Обновить статистику", callback_data: STATS_REFRESH, style: "primary" }]] },
  };
  if (callback) {
    await api("answerCallbackQuery", { callback_query_id: callback.id });
    try {
      await api("editMessageText", { ...payload, message_id: target.message_id });
    } catch (error) {
      if (error?.code !== "message_not_modified") throw error;
    }
  } else {
    await api("sendMessage", { ...payload, protect_content: true });
  }
}
