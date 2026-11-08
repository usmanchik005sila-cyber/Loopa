# Telegram Mini App — безопасный вход LOOPA

Режим мини-приложения открывается через https://t.me/LOOPAvideo_bot/loopa.

## Что делает интеграция

- Первый вход: пользователь авторизуется прежним способом (Telegram OIDC / Google / почта), затем **сам** нажимает «Привязать Mini App» в настройках профиля.
- Следующие запуски: Mini App отправляет `Telegram.WebApp.initData` на Supabase Edge Function, которая проверяет HMAC с токеном **бота LOOPAvideo_bot** и срок данных (10 минут). При известной привязке сервер выдаёт одноразовый hash для получения Supabase-сессии.
- Таблица связывает Telegram user ID и **существующий** Supabase user UUID. Ничего не объединяется по имени/телефону, не создаются новые аккаунты автоматически. Друзья, сообщения, комнаты сохраняются на прежнем UUID.
- Если у аккаунта не было email (например, вход только через Telegram OIDC), **при явной привязке** сервер добавляет технический адрес `miniapp-<telegram id>@auth.loopacinema.invalid` для поддержки Supabase magiclink. На этот адрес письма не доставляются, это не почта пользователя. Внешний интерфейс его скрывает.

## Порядок развёртывания

1. В Supabase проекта LOOPA запусти SQL-файл `supabase/migrations/20261108_telegram_miniapp_links.sql` в **SQL Editor**.
2. В Supabase Edge Functions добавь секрет `TELEGRAM_BOT_TOKEN` — токен **этого же бота LOOPAvideo_bot** из BotFather. **Никогда не вставляй секрет в index.html или публичный GitHub**, не присылай его в чат.
3. Проверь доступность `SUPABASE_URL` и одного из `SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SECRET_KEY` / `SUPABASE_SECRET_KEYS.default` в окружении Edge Functions. Значение сервисного ключа нельзя публиковать.
4. Разверни функцию `telegram-miniapp-auth` по `supabase/functions/telegram-miniapp-auth/index.js` с конфигурацией из `supabase/config.toml` (для первого входа `verify_jwt=false`, проверки происходят внутри функции). Через Supabase CLI: `supabase functions deploy telegram-miniapp-auth --project-ref <REF> --no-verify-jwt`.
5. После слияния PR открой Mini App по ссылке, войди в **свой действующий профиль** и нажми кнопку «Привязать Mini App» в «Профиль → Личные данные».
6. Полностью закрой приложение, затем открой снова. Теперь профиль должен автоматически восстановиться. В обычном браузере ничего не меняется.

Вместо `--no-verify-jwt` можно использовать настройки из `supabase/config.toml` при локально настроенном Supabase CLI. **Не включай публичный доступ к другим функциям.**

## Важные проверки перед запуском для всех пользователей

- Проверить SQL RLS: у `anon` и `authenticated` нет доступа к `telegram_miniapp_links`.
- Проверить подпись: изменённое / истёкшее `initData` отвергается сервером.
- Проверить попытку связать чужой профиль / второй Telegram — должна возвращаться ошибка 409.
- Проверить авторизацию с настоящего iPhone внутри Telegram; до реального теста нельзя считать интеграцию готовой.
- После деплоя проверь CORS: `https://loopacinema.ru` — единственный разрешённый источник.

**Ни GitHub Pages, ни Cloudflare Worker `loopa-telegram-auth` изменять не нужно.**
