begin;

create table loopa_private.inline_rutube_tickets (
  ticket uuid primary key,
  consumed_at timestamptz not null default clock_timestamp()
);
alter table loopa_private.inline_rutube_tickets enable row level security;
revoke all on loopa_private.inline_rutube_tickets from public, anon, authenticated, service_role;

create function public.loopa_consume_inline_rutube_ticket(p_ticket uuid)
returns boolean
language plpgsql security definer set search_path = ''
as $$
begin
  delete from loopa_private.inline_rutube_tickets
    where consumed_at < clock_timestamp() - interval '1 minute';
  insert into loopa_private.inline_rutube_tickets(ticket) values (p_ticket)
    on conflict do nothing;
  return found;
end;
$$;
revoke all on function public.loopa_consume_inline_rutube_ticket(uuid) from public, anon, authenticated;
grant execute on function public.loopa_consume_inline_rutube_ticket(uuid) to service_role;

commit;
