# LOOPA Telegram bot — приветствие

Обработчик Telegram-сообщений для @LOOPAvideo_bot.

- /start — короткое приветствие LOOPA и встроенная кнопка «🎬 Открыть LOOPA»
- /help — инструкция по использованию Mini App с той же кнопкой
- /myid — показывает Telegram ID владельца для настройки уведомлений
- /retrydelete <UUID> — только для владельца; повторяет незавершённую очистку после ошибки, но не требует одобрять запрос
- Другие сообщения и чаты не обрабатываются
- Ссылка кнопки: https://loopacinema.ru/
- Секрет TELEGRAM_BOT_TOKEN хранится только в настройках Edge Functions Supabase; в GitHub он не хранится.
- Запросы Telegram проверяются через X-Telegram-Bot-Api-Secret-Token. Для header используется HMAC-SHA256 от серверного токена, с сообщением "loopa.telegram.webhook.v1".
- Обработчик независим от сайта и функции telegram-miniapp-auth.
- Запросы на удаление исполняются автоматически после явного подтверждения пользователя в LOOPA. Если Telegram-уведомление настроено, бот присылает владельцу информационное сообщение без кнопок одобрения. Сбой уведомления не блокирует удаление аккаунта.
- Чтобы получать уведомления, владелец сначала пишет боту /start и /myid, затем добавляет показанный числовой ID как секрет `LOOPA_OWNER_TELEGRAM_ID` в настройках Edge Functions Supabase. Существующие `TELEGRAM_BOT_TOKEN` и webhook URL не меняются.
- Сообщение об успешном удалении содержит только ID заявки, без имени и адреса пользователя. Для незавершённой очистки бот покажет ID и команду /retrydelete.

## Развёртывание

1. Обновить файл supabase/functions/loopa-bot/index.js в Edge Function **loopa-bot** с verify_jwt=false.
2. Проверить адрес https://wnubqzwsvclvcvozibtc.supabase.co/functions/v1/loopa-bot?action=status
3. Убедиться, что токен соответствует @LOOPAvideo_bot и webhook: "empty" либо "loopa". Если "external", НЕ заменять его без анализа существующего обработчика.
4. Зарегистрировать webhook https://wnubqzwsvclvcvozibtc.supabase.co/functions/v1/loopa-bot через Telegram Bot API setWebhook. Передать secret_token, вычисленный сервером. Нельзя публиковать токен Telegram или подставлять его в URL браузера.
5. Повторно проверить статус (webhook: "loopa"), отправить /start и /myid в приватный чат с ботом, при желании добавить ID как секрет `LOOPA_OWNER_TELEGRAM_ID`, затем проверить кнопку «🎬 Открыть LOOPA».

Важно: Telegram допускает лишь один активный webhook на бота. Перед установкой нужно проверить getWebhookInfo, чтобы не нарушить существующую систему авторизации или другие обработчики.

Основной index.html и Cloudflare OAuth Worker не меняются.
