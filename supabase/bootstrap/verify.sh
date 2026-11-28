#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
work=$(mktemp -d)
box=
cleanup() {
  if [[ -n "$box" ]]; then docker stop -t 2 "$box" >/dev/null || true; fi
  rm -rf -- "$work"
}
trap cleanup EXIT
box=$(docker run -d --rm --network none -e POSTGRES_HOST_AUTH_METHOD=trust postgres@sha256:526f86d93c6ea08fd3f1fe5605650cacc781b2c6013169a0ad8f42c7d3d84f32 -c wal_level=logical)
for ((attempt = 0; attempt < 15; attempt++)); do
  if docker exec "$box" pg_isready -q -h 127.0.0.1 -U postgres; then break; fi
  sleep 1
done
db() { docker exec -i "$box" psql -X -q -h 127.0.0.1 -U postgres -v ON_ERROR_STOP=1 "$@"; }
db <<'SQL'
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema auth;
create schema storage;
create schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists "uuid-ossp" with schema extensions;
alter role postgres set search_path to public, extensions;
create table auth.users (
  id uuid primary key,
  email character varying(255),
  email_confirmed_at timestamptz,
  confirmed_at timestamptz generated always as (email_confirmed_at) stored,
  deleted_at timestamptz,
  is_anonymous boolean not null default false,
  created_at timestamptz not null default now(),
  raw_app_meta_data jsonb default '{}'::jsonb,
  raw_user_meta_data jsonb default '{}'::jsonb
);
create function auth.uid() returns uuid language sql stable set search_path = '' as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),
    nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid
$$;
create function auth.role() returns text language sql stable set search_path = '' as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role',true),''),
    nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role')
$$;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name,'/'))[1:cardinality(string_to_array(name,'/'))-1]
$$;
create table storage.buckets(id text primary key, name text not null, public boolean not null default false,
  file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id),
  name text not null, unique(bucket_id,name));
alter table storage.objects enable row level security;
grant usage on schema auth, storage, extensions to anon, authenticated, service_role;
grant select, insert, update, delete on storage.objects to authenticated;
create publication supabase_realtime;
SQL
db < schema.sql
printf 'Reconstructed application schema loaded.\n'
if db < schema.sql > "$work/second-apply.log" 2>&1; then
  printf 'Expected bootstrap to reject an initialized database.\n' >&2
  exit 1
fi
if ! grep -Fq 'LOOPA bootstrap requires an empty application database' "$work/second-apply.log"; then
  cat "$work/second-apply.log" >&2
  exit 1
fi
printf 'Bootstrap rejected an initialized database.\n'
db -At < catalog.sql > "$work/catalog.jsonl"
python3 - "$work/catalog.jsonl" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

expected = json.loads(Path('catalog-fingerprints.json').read_text())
actual = {obj['key']: obj['rows'] for obj in map(json.loads, Path(sys.argv[1]).read_text().splitlines())}
if actual.keys() != expected.keys():
    sys.exit('Catalog sections differ from baseline')

match = True
for key, fingerprint in expected.items():
    rows = actual[key]
    canonical = sorted(
        json.dumps({k: v for k, v in row.items() if k not in ('oid', 'nbytes')}, sort_keys=True)
        for row in rows
    )
    sha256 = hashlib.sha256('\n'.join(canonical).encode()).hexdigest()
    ok = len(rows) == fingerprint['count'] and sha256 == fingerprint['sha256']
    print(f'{"PASS" if ok else "FAIL"} {key} ({len(rows)} objects)')
    match = match and ok
if not match:
    sys.exit('Schema comparison failed')
PY
db < ../migrations/20261128160957_owner_bot_stats.sql
printf 'SQL suites (fresh connection per suite):\n'
failed=0
for suite in ../../tests/*.sql; do
  name=${suite##*/}
  if { printf 'BEGIN;\n'; cat "$suite"; printf '\nROLLBACK;\n'; } | db > "$work/$name.log" 2>&1; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s\n' "$name"
    cat "$work/$name.log"
    failed=1
  fi
done
exit "$failed"
