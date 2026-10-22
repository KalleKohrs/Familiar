-- 0017_backup
-- Nächtliche verschlüsselte Datensicherung nach Backblaze B2 (ADR 0009).
--
-- Ablauf:
--   1. pg_cron ruft um 02:30 UTC private.start_backup() auf: Einmal-Token wie in 0008, pg_net ruft
--      die Edge Function backup auf.
--   2. Die Function löst das Token über backup_begin ein, liest mit backup_export alle zu sichernden
--      Tabellen in EINEM Snapshot (Funktion ist STABLE) und lädt sie verschlüsselt hoch.
--   3. Bilder inkrementell: backup_image_plan liefert neue/geänderte und verschwundene Dateien
--      (Vergleich storage.objects ↔ private.backup_objects). Reicht ein Aufruf nicht, ruft die
--      Function über backup_finish sich selbst erneut auf (höchstens 20 Etappen).
--   4. backup_finish schreibt das Ergebnis nach private.backup_runs.
--   5. Wächter um 08:00 UTC: Gab es seit 30 Stunden keine erfolgreiche Sicherung, ruft
--      private.check_backup() die Function im Modus "alert" auf (Warn-E-Mail).
-- Nicht gesichert: Sitzungen, Einmal-Tokens, Outlook (Zugangsdaten im Vault gelten nur in diesem
-- Projekt; Verbindung wird nach einer Wiederherstellung neu hergestellt), Push-Geräte, Mitteilungs-
-- Aufträge, Live Activities. Neue Tabellen in public werden automatisch mitgesichert.
-- Bewusst ohne Löschbefehle: Verschwundene Bilder werden markiert (hidden_at), nicht entfernt.

-- ---------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------

create table private.backup_runs (
  id               bigint generated always as identity primary key,
  started_at       timestamptz not null default now(),
  finished_at      timestamptz,
  status           text not null default 'running' check (status in ('running', 'ok', 'failed')),
  db_file          text,
  db_bytes         bigint,
  db_raw_bytes     bigint,
  images_uploaded  integer not null default 0,
  images_hidden    integer not null default 0,
  images_pending   integer,
  chain            integer not null default 0,
  error            text
);

-- Welche Datei mit welchem Stand bei B2 liegt.
create table private.backup_objects (
  bucket_id     text not null,
  name          text not null,
  etag          text not null,
  backed_up_at  timestamptz not null default now(),
  hidden_at     timestamptz,
  primary key (bucket_id, name)
);

alter table private.backup_runs enable row level security;
alter table private.backup_objects enable row level security;
create policy "backup_runs_deny_all" on private.backup_runs for all using (false);
create policy "backup_objects_deny_all" on private.backup_objects for all using (false);
revoke all on table private.backup_runs, private.backup_objects from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Start (pg_cron, Fortsetzung, Wächter)
-- ---------------------------------------------------------------------------

create function private.start_backup(p_mode text default 'run', p_run_id bigint default null, p_chain integer default 0)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_url   text;
begin
  insert into private.cron_tokens (token_hash, purpose)
  values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), 'backup');

  select s.value into v_url from private.app_settings s where s.key = 'functions_base_url';

  return net.http_post(
    url := v_url || '/backup',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-familiar-cron-token', v_token),
    body := jsonb_build_object('mode', p_mode, 'run_id', p_run_id, 'chain', p_chain),
    timeout_milliseconds := 30000
  );
end;
$$;

revoke execute on function private.start_backup(text, bigint, integer) from public, anon, authenticated;

create function private.check_backup()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from private.backup_runs r
     where r.status = 'ok' and r.finished_at > now() - interval '30 hours'
  ) then
    return null;
  end if;
  return private.start_backup('alert');
end;
$$;

revoke execute on function private.check_backup() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. RPCs für die Edge Function (nur service_role)
-- ---------------------------------------------------------------------------

-- Token einlösen; Modus "run" ohne run_id legt einen neuen Lauf an.
create function public.backup_begin(p_token text, p_mode text, p_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run_id bigint := p_run_id;
  v_last_ok timestamptz;
begin
  update private.cron_tokens t
     set used_at = now()
   where t.token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and t.purpose = 'backup'
     and t.used_at is null
     and t.created_at > now() - interval '15 minutes';
  if not found then
    raise exception using errcode = '42501', message = 'Ungültiges oder abgelaufenes Token.';
  end if;

  select max(r.finished_at) into v_last_ok from private.backup_runs r where r.status = 'ok';

  if p_mode = 'run' and v_run_id is null then
    insert into private.backup_runs default values returning id into v_run_id;
  end if;

  return jsonb_build_object('run_id', v_run_id, 'last_ok', v_last_ok);
end;
$$;

-- Alle zu sichernden Tabellen als ein JSON-Dokument. STABLE: Alle Abfragen sehen denselben
-- Snapshot (den der aufrufenden Anweisung), die Sicherung ist also in sich stimmig.
create function public.backup_export()
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_table record;
  v_rows text;
  v_out text := '';
begin
  for v_table in
    select c.table_schema, c.table_name
      from information_schema.tables c
     where c.table_type = 'BASE TABLE'
       and (
         (c.table_schema = 'public' and c.table_name not in (
           'devices', 'live_activities', 'notification_jobs',
           'calendar_connections', 'external_calendars', 'external_events'))
         or (c.table_schema = 'auth' and c.table_name in ('users', 'identities'))
         or (c.table_schema = 'supabase_migrations' and c.table_name = 'schema_migrations')
       )
     order by c.table_schema, c.table_name
  loop
    execute format('select coalesce(json_agg(t), ''[]'')::text from %I.%I t',
                   v_table.table_schema, v_table.table_name)
      into v_rows;
    v_out := v_out || case when v_out = '' then '' else ',' end
             || to_json(v_table.table_schema || '.' || v_table.table_name)::text || ':' || v_rows;
  end loop;

  return ('{"format":1,"created_at":' || to_json(now())::text || ',"tables":{' || v_out || '}}')::json;
end;
$$;

-- Neue oder geänderte Dateien (höchstens p_limit) und verschwundene Dateien.
create function public.backup_image_plan(p_limit integer)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with source as (
    select o.bucket_id, o.name, coalesce(o.metadata ->> 'eTag', o.updated_at::text) as etag,
           coalesce((o.metadata ->> 'size')::bigint, 0) as size
      from storage.objects o
     where o.bucket_id in ('task-images', 'avatars')
  ),
  changed as (
    select s.* from source s
     where not exists (
       select 1 from private.backup_objects b
        where b.bucket_id = s.bucket_id and b.name = s.name and b.etag = s.etag and b.hidden_at is null)
  ),
  removed as (
    select b.bucket_id, b.name from private.backup_objects b
     where b.hidden_at is null
       and not exists (select 1 from source s where s.bucket_id = b.bucket_id and s.name = b.name)
  )
  select jsonb_build_object(
    'changed', coalesce((select jsonb_agg(jsonb_build_object('bucket', c.bucket_id, 'name', c.name, 'etag', c.etag, 'size', c.size)
                                          order by c.bucket_id, c.name)
                           from (select * from changed order by bucket_id, name limit p_limit) c), '[]'::jsonb),
    'changed_total', (select count(*) from changed),
    'removed', coalesce((select jsonb_agg(jsonb_build_object('bucket', r.bucket_id, 'name', r.name)) from removed r), '[]'::jsonb),
    'source_total', (select count(*) from source),
    'backed_total', (select count(*) from private.backup_objects b where b.hidden_at is null),
    'families', (select count(*) from public.families)
  );
$$;

create function public.backup_image_saved(p_bucket text, p_name text, p_etag text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into private.backup_objects (bucket_id, name, etag)
  values (p_bucket, p_name, p_etag)
  on conflict (bucket_id, name) do update
    set etag = excluded.etag, backed_up_at = now(), hidden_at = null;
$$;

create function public.backup_image_hidden(p_bucket text, p_name text)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.backup_objects b set hidden_at = now()
   where b.bucket_id = p_bucket and b.name = p_name;
$$;

-- Zwischenstand bzw. Ergebnis eines Laufs; p_status 'running' + p_continue startet die nächste Etappe.
create function public.backup_finish(p_run_id bigint, p_status text, p_stats jsonb, p_error text, p_continue boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_chain integer;
begin
  update private.backup_runs r
     set status          = p_status,
         finished_at     = case when p_status = 'running' then null else now() end,
         db_file         = coalesce(p_stats ->> 'db_file', r.db_file),
         db_bytes        = coalesce((p_stats ->> 'db_bytes')::bigint, r.db_bytes),
         db_raw_bytes    = coalesce((p_stats ->> 'db_raw_bytes')::bigint, r.db_raw_bytes),
         images_uploaded = r.images_uploaded + coalesce((p_stats ->> 'images_uploaded')::integer, 0),
         images_hidden   = r.images_hidden + coalesce((p_stats ->> 'images_hidden')::integer, 0),
         images_pending  = (p_stats ->> 'images_pending')::integer,
         chain           = case when p_continue then r.chain + 1 else r.chain end,
         error           = p_error
   where r.id = p_run_id
  returning r.chain into v_chain;

  if p_continue then
    perform private.start_backup('run', p_run_id, v_chain);
  end if;
end;
$$;

revoke execute on function public.backup_begin(text, text, bigint) from public, anon, authenticated;
revoke execute on function public.backup_export() from public, anon, authenticated;
revoke execute on function public.backup_image_plan(integer) from public, anon, authenticated;
revoke execute on function public.backup_image_saved(text, text, text) from public, anon, authenticated;
revoke execute on function public.backup_image_hidden(text, text) from public, anon, authenticated;
revoke execute on function public.backup_finish(bigint, text, jsonb, text, boolean) from public, anon, authenticated;
grant execute on function public.backup_begin(text, text, bigint) to service_role;
grant execute on function public.backup_export() to service_role;
grant execute on function public.backup_image_plan(integer) to service_role;
grant execute on function public.backup_image_saved(text, text, text) to service_role;
grant execute on function public.backup_image_hidden(text, text) to service_role;
grant execute on function public.backup_finish(bigint, text, jsonb, text, boolean) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Wiederherstellung (Edge Function backup-restore, nur von Hand)
-- ---------------------------------------------------------------------------
-- Aufruf im SQL-Editor, z. B. select private.start_restore('probe', '2026-10-22');
--   probe    – vollständige Wiederherstellung in einer Transaktion, Zählung, dann ROLLBACK;
--              dazu Stichprobe von Bildern (entschlüsseln und mit dem Original vergleichen)
--   restore  – Datenbank wiederherstellen, danach alle Bilder (Etappen über p_cursor).
--              Ist das Projekt nicht leer, nur mit p_confirm = 'ÜBERSCHREIBEN'.
-- Die Function verbindet sich direkt mit der Datenbank (SUPABASE_DB_URL); das Ergebnis steht in
-- private.restore_runs.

create table private.restore_runs (
  id           bigint generated always as identity primary key,
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  mode         text not null,
  backup_date  date not null,
  status       text not null default 'running' check (status in ('running', 'ok', 'failed')),
  report       jsonb not null default '{}'::jsonb
);

alter table private.restore_runs enable row level security;
create policy "restore_runs_deny_all" on private.restore_runs for all using (false);
revoke all on table private.restore_runs from public, anon, authenticated;

create function private.start_restore(
  p_mode text, p_date date, p_confirm text default null, p_cursor text default null, p_run_id bigint default null)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_url   text;
  v_run   bigint := p_run_id;
begin
  if p_mode not in ('probe', 'restore', 'images') then
    raise exception 'Modus muss probe, restore oder images sein.';
  end if;

  if v_run is null then
    insert into private.restore_runs (mode, backup_date) values (p_mode, p_date) returning id into v_run;
  end if;

  insert into private.cron_tokens (token_hash, purpose)
  values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), 'restore');

  select s.value into v_url from private.app_settings s where s.key = 'functions_base_url';

  perform net.http_post(
    url := v_url || '/backup-restore',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-familiar-cron-token', v_token),
    body := jsonb_build_object('mode', p_mode, 'date', p_date, 'confirm', p_confirm, 'cursor', p_cursor, 'run_id', v_run),
    timeout_milliseconds := 30000
  );
  return v_run;
end;
$$;

revoke execute on function private.start_restore(text, date, text, text, bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Zeitplan: Sicherung 02:30 UTC, Wächter 08:00 UTC
-- ---------------------------------------------------------------------------

select cron.schedule('familiar-backup', '30 2 * * *', $$select private.start_backup()$$);
select cron.schedule('familiar-backup-check', '0 8 * * *', $$select private.check_backup()$$);
