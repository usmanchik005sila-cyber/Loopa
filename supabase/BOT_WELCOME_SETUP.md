# LOOPA Telegram bot — приветствие

Обработчик Telegram-сообщений для @LOOPAvideo_bot.

- /start — короткое приветствие LOOPA и встроенная кнопка «🎬 Открыть LOOPA»
- /help — инструкция по использованию Mini App с той же кнопкой
- Другие сообщения и чаты не обрабатываются
- Ссылка кнопки: https://loopacinema.ru/
- Секрет TELEGRAM_BOT_TOKEN хранится только в настройках Edge Functions Supabase; в GitHub он не хранится.
- Запросы Telegram проверяются через X-Telegram-Bot-Api-Secret-Token. Для header используется HMAC-SHA256 от серверного токена, с сообщением "loopa.telegram.webhook.v1".
- Обработчик независим от сайта и функции telegram-miniapp-auth.

## Развёртывание

1. Развернуть файл supabase/functions/loopa-bot/index.js как Edge Function **loopa-bot** с verify_jwt=false.
2. Проверить адрес https://wnubqzwsvclvcvozibtc.supabase.co/functions/v1/loopa-bot?action=status
3. Убедиться, что токен соответствует @LOOPAvideo_bot и webhook: "empty" либо "loopa". Если "external", НЕ заменять его без анализа существующего обработчика.
4. Зарегистрировать webhook https://wnubqzwsvclvcvozibtc.supabase.co/functions/v1/loopa-bot через Telegram Bot API setWebhook. Передать secret_token, вычисленный сервером. Нельзя публиковать токен Telegram или подставлять его в URL браузера.
5. Повторно проверить статус (webhook: "loopa"), отправить /start в приватный чат с ботом, проверить кнопку «🎬 Открыть LOOPA».

Важно: Telegram допускает лишь один активный webhook на бота. Перед установкой нужно проверить getWebhookInfo, чтобы не нарушить существующую систему авторизации или другие обработчики.

Основной index.html и Cloudflare OAuth Worker не меняются.
