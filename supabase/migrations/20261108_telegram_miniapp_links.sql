-- LOOPA Telegram Mini App: server-owned account bindings.
-- Apply once in Supabase SQL Editor BEFORE deploying the Edge Function.
-- Do not expose this table to anon or authenticated REST clients.
create table if not exists public.telegram_miniapp_links (
  telegram_id text primary key
    check (telegram_id ~ '^[0-9]{1,20}$'),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  linked_at timestamptz not null default now()
);

alter table public.telegram_miniapp_links enable row level security;

revoke all on table public.telegram_miniapp_links from public, anon, authenticated;
grant select, insert on table public.telegram_miniapp_links to service_role;

-- Deliberately no public RLS policies:
-- Only server-side auth.admin/service_role may read or create bindings.
-- Existing LOOPA accounts, profile records, friendships and DMs are not altered.
