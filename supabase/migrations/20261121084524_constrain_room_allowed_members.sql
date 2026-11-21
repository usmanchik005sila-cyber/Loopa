begin;

set local lock_timeout = '3s';

-- Keep membership comparisons boolean for every stored allow-list.
alter table public.loopa_rooms16
  add constraint loopa_rooms16_allowed_members_valid
  check (
    case when coalesce(pg_catalog.array_ndims(allowed), 1) = 1
      then pg_catalog.array_position(allowed, null::uuid) is null
      else false
    end
  );

commit;
