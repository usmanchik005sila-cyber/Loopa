begin;

create table loopa_private.telegram_tracking_links (
  id uuid primary key default gen_random_uuid(),
  label text not null unique check (char_length(label) between 1 and 48),
  created_at timestamptz not null default clock_timestamp()
);
create index telegram_tracking_links_order_idx
  on loopa_private.telegram_tracking_links (created_at desc, id desc);

create table loopa_private.telegram_tracking_opens (
  link_id uuid not null references loopa_private.telegram_tracking_links(id) on delete cascade,
  visitor_hash text not null check (visitor_hash ~ '^[a-f0-9]{64}$'),
  primary key (link_id, visitor_hash)
);

alter table loopa_private.telegram_tracking_links enable row level security;
alter table loopa_private.telegram_tracking_opens enable row level security;
revoke all on loopa_private.telegram_tracking_links, loopa_private.telegram_tracking_opens
  from public, anon, authenticated;
grant usage on schema loopa_private to service_role;
grant select, insert, update (label) on loopa_private.telegram_tracking_links to service_role;
grant select, insert on loopa_private.telegram_tracking_opens to service_role;

create function public.loopa_create_telegram_tracking_link(p_label text)
returns uuid language sql security invoker set search_path = ''
as $$
  insert into loopa_private.telegram_tracking_links(label) values (p_label)
  on conflict (label) do update set label = excluded.label
  returning id;
$$;

create function public.loopa_list_telegram_tracking_links(p_page integer)
returns table(id uuid, label text, visitors bigint)
language sql stable security invoker set search_path = ''
as $$
  with links as (
    select l.id, l.label, l.created_at from loopa_private.telegram_tracking_links l
    order by l.created_at desc, l.id desc
    limit 11 offset (greatest(1, least(p_page, 10000)) - 1) * 10
  )
  select l.id, l.label, (select count(*) from loopa_private.telegram_tracking_opens o where o.link_id = l.id)
  from links l
  order by l.created_at desc, l.id desc;
$$;

create function public.loopa_record_telegram_tracking_open(p_link_id uuid, p_visitor_hash text)
returns void language sql security invoker set search_path = ''
as $$
  insert into loopa_private.telegram_tracking_opens(link_id, visitor_hash)
  select id, p_visitor_hash from loopa_private.telegram_tracking_links where id = p_link_id
  on conflict (link_id, visitor_hash) do nothing;
$$;

revoke all on function public.loopa_create_telegram_tracking_link(text),
  public.loopa_list_telegram_tracking_links(integer),
  public.loopa_record_telegram_tracking_open(uuid,text) from public, anon, authenticated;
grant execute on function public.loopa_create_telegram_tracking_link(text),
  public.loopa_list_telegram_tracking_links(integer),
  public.loopa_record_telegram_tracking_open(uuid,text) to service_role;

commit;
