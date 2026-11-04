#!/usr/bin/env bash
# Run against a disposable container; safe to repeat after a server restart.
set -euo pipefail
container="$1"
engine="${2:-docker}"
admin="${3:-postgres}"
psql() { "$engine" exec -i "$container" psql -h /run/postgresql -U "$admin" -d postgres -XqAt -v ON_ERROR_STOP=1 "$@"; }

test "$(psql -c 'show pg_durable.worker_role')" = "$admin"
test "$(psql -c 'show pg_durable.host')" = /run/postgresql
test "$(psql -c 'show pg_durable.database')" = postgres
test "$(psql -c 'show pg_durable.enable_superuser_instances')" = off
psql -c 'create extension if not exists pg_durable'
ready=f
for _ in $(seq 60); do
  ready="$(psql -c "select exists (select 1 from df._worker_epoch where last_seen_at > now() - interval '15 seconds')")"
  [ "$ready" = t ] && break
  sleep 1
done
test "$ready" = t

# An ordinary login role proves the worker can authenticate as the submitter,
# execute SQL and persist completion without enabling superuser workflows.
psql <<'SQL'
do $$ begin
  if not exists (select from pg_roles where rolname = 'durable_smoke') then
    create role durable_smoke login;
  end if;
end $$;
select df.grant_usage('durable_smoke');
create table if not exists public.durable_smoke_result (answer integer);
truncate public.durable_smoke_result;
grant usage on schema public to durable_smoke;
grant insert, select on public.durable_smoke_result to durable_smoke;
SQL
id="$("$engine" exec "$container" psql -h /run/postgresql -U durable_smoke -d postgres -XqAt -v ON_ERROR_STOP=1 \
  -c "select df.start('INSERT INTO public.durable_smoke_result VALUES (42)')")"
status=
for _ in $(seq 60); do
  status="$(psql -v id="$id" <<< "select status from df.instances where id = :'id'")"
  case "$status" in completed | failed) break ;; esac
  sleep 1
done
test "$status" = completed
test "$(psql -c 'select answer from public.durable_smoke_result')" = 42
echo 'ok   pg_durable worker executes and completes a non-superuser workflow'
