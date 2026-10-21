-- 0008_history_purge
-- Verlauf (Phase 4): Erledigte und gelöschte Aufgaben bleiben 30 Tage, danach werden sie
-- samt nicht mehr verknüpfter Bilder entfernt.
--
-- Ablauf ohne dauerhaftes Geheimnis:
--   1. pg_cron ruft täglich private.start_history_purge() auf. Die Funktion erzeugt ein
--      Einmal-Token, speichert nur dessen SHA-256 und ruft per pg_net die Edge Function
--      purge-history mit dem Token im Header auf.
--   2. Die Function löst das Token über public.purge_expired_history ein (nur service_role,
--      Token höchstens 15 Minuten gültig und nur einmal verwendbar).
--   3. Die RPC entfernt abgelaufene Aufgaben und verwaiste Bildzeilen und liefert die Pfade
--      der Dateien, die die Function über die Storage-API löscht (Supabase: Dateien nie per SQL löschen).

-- ---------------------------------------------------------------------------
-- Einstellungen und Einmal-Tokens (Schema private, für Clients unerreichbar)
-- ---------------------------------------------------------------------------

create table private.app_settings (
  key   text primary key,
  value text not null
);

-- Pro Umgebung anzupassen (Dev-Projekt ldeouecoaqyfvubhrjei).
insert into private.app_settings (key, value)
values ('functions_base_url', 'https://ldeouecoaqyfvubhrjei.supabase.co/functions/v1');

create table private.cron_tokens (
  token_hash  text primary key,
  purpose     text not null,
  created_at  timestamptz not null default now(),
  used_at     timestamptz
);

alter table private.app_settings enable row level security;
alter table private.cron_tokens enable row level security;
create policy "app_settings_deny_all" on private.app_settings for all using (false);
create policy "cron_tokens_deny_all" on private.cron_tokens for all using (false);
revoke all on table private.app_settings, private.cron_tokens from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Start (pg_cron)
-- ---------------------------------------------------------------------------

create function private.start_history_purge()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_url   text;
begin
  -- Alte Tokens aufräumen (benutzt oder verfallen).
  delete from private.cron_tokens t where t.created_at < now() - interval '1 day';

  insert into private.cron_tokens (token_hash, purpose)
  values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), 'purge_history');

  select s.value into v_url from private.app_settings s where s.key = 'functions_base_url';

  return net.http_post(
    url := v_url || '/purge-history',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-familiar-cron-token', v_token),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
end;
$$;

revoke execute on function private.start_history_purge() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2./3. Bereinigung (aufgerufen von der Edge Function mit Secret-Key = service_role)
-- ---------------------------------------------------------------------------

create function public.purge_expired_history(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tasks integer;
  v_images integer;
  v_paths text[];
begin
  update private.cron_tokens t
     set used_at = now()
   where t.token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and t.purpose = 'purge_history'
     and t.used_at is null
     and t.created_at > now() - interval '15 minutes';
  if not found then
    raise exception using errcode = '42501', message = 'Ungültiges oder abgelaufenes Token.';
  end if;

  -- Aufgaben, die seit mehr als 30 Tagen erledigt oder gelöscht sind (Zuweisungen und
  -- Bildverknüpfungen folgen per Cascade).
  with expired as (
    delete from public.tasks t
     where t.completed_at < now() - interval '30 days'
        or t.deleted_at < now() - interval '30 days'
    returning t.id
  )
  select count(*) into v_tasks from expired;

  -- Bilder ohne Verknüpfung (z. B. aus abgelaufenen Aufgaben oder beim Bearbeiten entfernt);
  -- ein Tag Schonfrist für gerade laufende Speichervorgänge.
  with orphaned as (
    delete from public.images i
     where i.created_at < now() - interval '1 day'
       and not exists (select 1 from public.task_image_links l where l.image_id = i.id)
    returning i.id
  )
  select count(*) into v_images from orphaned;

  -- Dateien ohne Bildzeile: verwaiste Bilder von oben und Uploads, deren Speichern scheiterte.
  select coalesce(array_agg(o.name order by o.name), '{}')
    into v_paths
  from storage.objects o
  where o.bucket_id = 'task-images'
    and o.created_at < now() - interval '1 day'
    and not exists (
      select 1 from public.images i where i.path = o.name or i.thumb_path = o.name
    );

  return jsonb_build_object('deleted_tasks', v_tasks, 'deleted_images', v_images, 'file_paths', to_jsonb(v_paths));
end;
$$;

revoke execute on function public.purge_expired_history(text) from public, anon, authenticated;
grant execute on function public.purge_expired_history(text) to service_role;

-- ---------------------------------------------------------------------------
-- Zeitplan: täglich 03:15 UTC
-- ---------------------------------------------------------------------------

select cron.schedule('familiar-purge-history', '15 3 * * *', $$select private.start_history_purge()$$);
