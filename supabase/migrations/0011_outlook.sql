-- 0011_outlook
-- Persönliche Outlook-Termine (Phase 8, Plan Abschnitt 7). Strikt pro Nutzer: nur der Nutzer selbst
-- sieht seine Verbindung, Kalender und Termine. Nie schreibend nach Outlook (Calendars.ReadBasic),
-- Termine erzeugen nie Aufgaben.
--
-- Ablauf:
--   * Verbinden: Edge Function outlook-oauth-start (Nutzer-JWT) legt einen Einmal-State samt
--     PKCE-Verifier an und liefert die Microsoft-Anmelde-URL. Microsoft leitet auf
--     outlook-oauth-callback um; die Function löst Code + Verifier mit dem Client Secret ein,
--     speichert das Refresh-Token nur im Vault, legt Kalender an und stößt den ersten Abgleich an.
--   * Abgleich: outlook-sync (alle 15 Minuten per pg_cron, sofort nach dem Verbinden und auf
--     Wunsch des Nutzers) holt calendarView über −7 … +120 Tage, ersetzt die Termine im Fenster
--     und speichert das jeweils neueste Refresh-Token. Abgelehnte Tokens → Status needs_reauth.
-- Tokens erreichen Clients nie; alle Token-RPCs sind nur für service_role.

-- ---------------------------------------------------------------------------
-- Typen und Tabellen
-- ---------------------------------------------------------------------------

create type public.calendar_provider as enum ('outlook');
create type public.calendar_connection_status as enum ('active', 'needs_reauth', 'error');

create table public.calendar_connections (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references public.profiles (id) on delete cascade,
  provider             public.calendar_provider not null default 'outlook',
  account_email        text,
  provider_account_id  text not null,
  status               public.calendar_connection_status not null default 'active',
  last_sync_at         timestamptz,
  last_error           text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint calendar_connections_account_unique unique (user_id, provider, provider_account_id)
);

create index calendar_connections_user_id_idx on public.calendar_connections (user_id);

create trigger calendar_connections_set_updated_at
  before update on public.calendar_connections
  for each row execute function private.set_updated_at();

create table public.external_calendars (
  id                    uuid primary key default gen_random_uuid(),
  connection_id         uuid not null references public.calendar_connections (id) on delete cascade,
  user_id               uuid not null references public.profiles (id) on delete cascade,
  provider_calendar_id  text not null,
  name                  text not null,
  color                 text,
  is_default            boolean not null default false,
  is_selected           boolean not null default false,
  constraint external_calendars_unique unique (connection_id, provider_calendar_id)
);

create index external_calendars_user_id_idx on public.external_calendars (user_id);

create table public.external_events (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references public.profiles (id) on delete cascade,
  calendar_id        uuid not null references public.external_calendars (id) on delete cascade,
  provider           public.calendar_provider not null default 'outlook',
  provider_event_id  text not null,
  title              text not null,
  starts_at          timestamptz not null,
  ends_at            timestamptz not null,
  is_all_day         boolean not null default false,
  -- Ganztägig: Kalendertage ohne Zeitzone (Outlook liefert sie „schwebend“).
  start_date         date,
  end_date           date,
  location_name      text,
  organizer_name     text,
  organizer_email    text,
  is_cancelled       boolean not null default false,
  synced_at          timestamptz not null default now(),
  constraint external_events_unique unique (calendar_id, provider_event_id)
);

create index external_events_user_time_idx on public.external_events (user_id, starts_at);

-- Tokens und OAuth-State: Schema private, für Clients unerreichbar.
create table private.calendar_credentials (
  connection_id    uuid primary key references public.calendar_connections (id) on delete cascade,
  vault_secret_id  uuid not null,
  scopes           text
);

create table private.oauth_states (
  state_hash     text primary key,
  user_id        uuid not null references public.profiles (id) on delete cascade,
  code_verifier  text not null,
  created_at     timestamptz not null default now(),
  used_at        timestamptz
);

alter table private.calendar_credentials enable row level security;
alter table private.oauth_states enable row level security;
create policy "calendar_credentials_deny_all" on private.calendar_credentials for all using (false);
create policy "oauth_states_deny_all" on private.oauth_states for all using (false);
revoke all on table private.calendar_credentials, private.oauth_states from public, anon, authenticated;

-- Einmal-Tokens aus 0008 können sich auf einen Nutzer beziehen (Abgleich nur für ihn).
alter table private.cron_tokens add column subject uuid;

-- Gelöschte Zugangsdaten: zugehöriges Vault-Geheimnis mit entfernen.
create function private.delete_calendar_secret()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets s where s.id = old.vault_secret_id;
  return old;
end;
$$;

revoke execute on function private.delete_calendar_secret() from public, anon, authenticated;

create trigger calendar_credentials_delete_secret
  after delete on private.calendar_credentials
  for each row execute function private.delete_calendar_secret();

-- ---------------------------------------------------------------------------
-- RLS: nur eigene Daten lesen; Schreiben nur über RPCs
-- ---------------------------------------------------------------------------

alter table public.calendar_connections enable row level security;
alter table public.external_calendars   enable row level security;
alter table public.external_events      enable row level security;

revoke all on table public.calendar_connections from anon, authenticated;
revoke all on table public.external_calendars   from anon, authenticated;
revoke all on table public.external_events      from anon, authenticated;

grant select on table public.calendar_connections to authenticated;
grant select on table public.external_calendars   to authenticated;
grant select on table public.external_events      to authenticated;

create policy "calendar_connections_select_own" on public.calendar_connections
  for select to authenticated using (user_id = (select auth.uid()));
create policy "external_calendars_select_own" on public.external_calendars
  for select to authenticated using (user_id = (select auth.uid()));
create policy "external_events_select_own" on public.external_events
  for select to authenticated using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Abgleich anstoßen (pg_net → outlook-sync mit Einmal-Token wie bei purge-history)
-- ---------------------------------------------------------------------------

create function private.start_outlook_sync(p_user_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text := encode(extensions.gen_random_bytes(32), 'hex');
  v_url   text;
begin
  delete from private.cron_tokens t where t.created_at < now() - interval '1 day';

  insert into private.cron_tokens (token_hash, purpose, subject)
  values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), 'outlook_sync', p_user_id);

  select s.value into v_url from private.app_settings s where s.key = 'functions_base_url';

  return net.http_post(
    url := v_url || '/outlook-sync',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-familiar-cron-token', v_token),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

revoke execute on function private.start_outlook_sync(uuid) from public, anon, authenticated;

select cron.schedule('familiar-outlook-sync', '*/15 * * * *', $$select private.start_outlook_sync(null)$$);

-- ---------------------------------------------------------------------------
-- RPCs für die App (authenticated)
-- ---------------------------------------------------------------------------

-- Kalender ein-/ausblenden. Ausgeblendete verlieren ihre zwischengespeicherten Termine.
create function public.set_calendar_selected(p_calendar_id uuid, p_selected boolean)
returns public.external_calendars
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := private.require_uid();
  v_calendar public.external_calendars;
begin
  update public.external_calendars c
     set is_selected = coalesce(p_selected, false)
   where c.id = p_calendar_id and c.user_id = v_uid
  returning * into v_calendar;
  if not found then
    perform private.raise_app_error('calendar_not_found');
  end if;
  if not v_calendar.is_selected then
    delete from public.external_events e where e.calendar_id = v_calendar.id;
  else
    perform private.start_outlook_sync(v_uid);
  end if;
  return v_calendar;
end;
$$;

-- Verbindung trennen: Zugangsdaten (samt Vault-Geheimnis), Kalender und Termine werden entfernt.
create function public.disconnect_calendar(p_connection_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  delete from public.calendar_connections c where c.id = p_connection_id and c.user_id = v_uid;
  if not found then
    perform private.raise_app_error('calendar_not_found');
  end if;
end;
$$;

-- Abgleich jetzt anstoßen (höchstens alle 2 Minuten pro Nutzer).
create function public.request_calendar_sync()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  if not exists (select 1 from public.calendar_connections c where c.user_id = v_uid and c.status = 'active') then
    return false;
  end if;
  if exists (
    select 1 from private.cron_tokens t
    where t.purpose = 'outlook_sync' and t.subject = v_uid and t.created_at > now() - interval '2 minutes'
  ) then
    return false;
  end if;
  perform private.start_outlook_sync(v_uid);
  return true;
end;
$$;

revoke execute on function public.set_calendar_selected(uuid, boolean) from public, anon, service_role;
revoke execute on function public.disconnect_calendar(uuid) from public, anon, service_role;
revoke execute on function public.request_calendar_sync() from public, anon, service_role;
grant execute on function public.set_calendar_selected(uuid, boolean) to authenticated;
grant execute on function public.disconnect_calendar(uuid) to authenticated;
grant execute on function public.request_calendar_sync() to authenticated;

-- ---------------------------------------------------------------------------
-- RPCs für die Edge Functions (nur service_role)
-- ---------------------------------------------------------------------------

-- outlook-oauth-start: Einmal-State anlegen (nur der SHA-256 des States wird gespeichert).
create function public.outlook_create_oauth_state(p_user_id uuid, p_state_hash text, p_code_verifier text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.oauth_states s where s.created_at < now() - interval '1 hour';
  insert into private.oauth_states (state_hash, user_id, code_verifier)
  values (p_state_hash, p_user_id, p_code_verifier);
end;
$$;

-- outlook-oauth-callback: State einlösen (einmalig, höchstens 10 Minuten alt).
create function public.outlook_consume_oauth_state(p_state_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state private.oauth_states;
begin
  update private.oauth_states s
     set used_at = now()
   where s.state_hash = p_state_hash
     and s.used_at is null
     and s.created_at > now() - interval '10 minutes'
  returning * into v_state;
  if not found then
    return null;
  end if;
  return jsonb_build_object('user_id', v_state.user_id, 'code_verifier', v_state.code_verifier);
end;
$$;

-- Verbindung anlegen bzw. erneuern; Refresh-Token nur im Vault.
create function public.outlook_save_connection(
  p_user_id uuid,
  p_account_id text,
  p_account_email text,
  p_refresh_token text,
  p_scopes text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_connection_id uuid;
  v_secret_id     uuid;
begin
  insert into public.calendar_connections (user_id, provider, provider_account_id, account_email, status, last_error)
  values (p_user_id, 'outlook', p_account_id, p_account_email, 'active', null)
  on conflict (user_id, provider, provider_account_id)
  do update set account_email = excluded.account_email, status = 'active', last_error = null
  returning id into v_connection_id;

  select c.vault_secret_id into v_secret_id
  from private.calendar_credentials c where c.connection_id = v_connection_id;

  if v_secret_id is null then
    v_secret_id := vault.create_secret(p_refresh_token, null, 'Outlook-Refresh-Token ' || v_connection_id::text);
    insert into private.calendar_credentials (connection_id, vault_secret_id, scopes)
    values (v_connection_id, v_secret_id, p_scopes);
  else
    perform vault.update_secret(v_secret_id, p_refresh_token);
    update private.calendar_credentials c set scopes = p_scopes where c.connection_id = v_connection_id;
  end if;

  return v_connection_id;
end;
$$;

-- Kalenderliste abgleichen: neue anlegen (Standardkalender vorausgewählt), fehlende entfernen.
-- p_calendars: [{"id": text, "name": text, "color": text, "is_default": bool}, …]
create function public.outlook_upsert_calendars(p_connection_id uuid, p_calendars jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_count   integer;
begin
  select c.user_id into v_user_id from public.calendar_connections c where c.id = p_connection_id;
  if v_user_id is null then
    raise exception using errcode = 'P0002', message = 'Verbindung nicht gefunden.';
  end if;

  insert into public.external_calendars (connection_id, user_id, provider_calendar_id, name, color, is_default, is_selected)
  select p_connection_id, v_user_id, c ->> 'id', coalesce(nullif(c ->> 'name', ''), 'Kalender'),
         c ->> 'color', coalesce((c ->> 'is_default')::boolean, false), coalesce((c ->> 'is_default')::boolean, false)
  from jsonb_array_elements(coalesce(p_calendars, '[]'::jsonb)) as c
  where c ->> 'id' is not null
  on conflict (connection_id, provider_calendar_id)
  do update set name = excluded.name, color = excluded.color, is_default = excluded.is_default;

  delete from public.external_calendars e
   where e.connection_id = p_connection_id
     and not exists (
       select 1 from jsonb_array_elements(coalesce(p_calendars, '[]'::jsonb)) as c
       where c ->> 'id' = e.provider_calendar_id
     );

  select count(*) into v_count from public.external_calendars e where e.connection_id = p_connection_id;
  return v_count;
end;
$$;

-- outlook-sync: Token einlösen und die zu bearbeitenden Verbindungen samt Refresh-Token liefern.
create function public.outlook_sync_jobs(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_subject uuid;
  v_jobs    jsonb;
begin
  update private.cron_tokens t
     set used_at = now()
   where t.token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and t.purpose = 'outlook_sync'
     and t.used_at is null
     and t.created_at > now() - interval '15 minutes'
  returning t.subject into v_subject;
  if not found then
    raise exception using errcode = '42501', message = 'Ungültiges oder abgelaufenes Token.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'connection_id', c.id,
           'refresh_token', s.decrypted_secret,
           'calendars', (
             select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'provider_calendar_id', e.provider_calendar_id)), '[]'::jsonb)
             from public.external_calendars e
             where e.connection_id = c.id and e.is_selected
           )
         )), '[]'::jsonb)
    into v_jobs
  from public.calendar_connections c
  join private.calendar_credentials cc on cc.connection_id = c.id
  join vault.decrypted_secrets s on s.id = cc.vault_secret_id
  where c.status = 'active'
    and (v_subject is null or c.user_id = v_subject);

  return v_jobs;
end;
$$;

-- Neuestes Refresh-Token speichern (Microsoft: altes verwerfen).
create function public.outlook_store_refresh_token(p_connection_id uuid, p_refresh_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_secret_id uuid;
begin
  select c.vault_secret_id into v_secret_id from private.calendar_credentials c where c.connection_id = p_connection_id;
  if v_secret_id is not null and p_refresh_token is not null and p_refresh_token <> '' then
    perform vault.update_secret(v_secret_id, p_refresh_token);
  end if;
end;
$$;

-- Termine eines Kalenders im Fenster ersetzen (Änderungen, Absagen und Löschungen werden erfasst).
-- p_events: [{"id", "title", "starts_at", "ends_at", "is_all_day", "start_date", "end_date",
--             "location", "organizer_name", "organizer_email", "is_cancelled"}, …]
create function public.outlook_apply_events(
  p_calendar_id uuid,
  p_window_start timestamptz,
  p_window_end timestamptz,
  p_events jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_count   integer;
begin
  select c.user_id into v_user_id from public.external_calendars c where c.id = p_calendar_id and c.is_selected;
  if v_user_id is null then
    return 0;
  end if;

  insert into public.external_events (user_id, calendar_id, provider_event_id, title, starts_at, ends_at, is_all_day,
                                      start_date, end_date, location_name, organizer_name, organizer_email,
                                      is_cancelled, synced_at)
  select v_user_id, p_calendar_id, e ->> 'id', coalesce(nullif(e ->> 'title', ''), 'Termin'),
         (e ->> 'starts_at')::timestamptz, (e ->> 'ends_at')::timestamptz,
         coalesce((e ->> 'is_all_day')::boolean, false),
         (e ->> 'start_date')::date, (e ->> 'end_date')::date,
         nullif(e ->> 'location', ''), nullif(e ->> 'organizer_name', ''), nullif(e ->> 'organizer_email', ''),
         coalesce((e ->> 'is_cancelled')::boolean, false), now()
  from jsonb_array_elements(coalesce(p_events, '[]'::jsonb)) as e
  where e ->> 'id' is not null
  on conflict (calendar_id, provider_event_id)
  do update set title = excluded.title, starts_at = excluded.starts_at, ends_at = excluded.ends_at,
                is_all_day = excluded.is_all_day, start_date = excluded.start_date, end_date = excluded.end_date,
                location_name = excluded.location_name, organizer_name = excluded.organizer_name,
                organizer_email = excluded.organizer_email, is_cancelled = excluded.is_cancelled,
                synced_at = excluded.synced_at;

  -- Im Fenster nicht mehr vorhanden → in Outlook gelöscht.
  delete from public.external_events x
   where x.calendar_id = p_calendar_id
     and x.starts_at < p_window_end
     and x.ends_at > p_window_start
     and not exists (
       select 1 from jsonb_array_elements(coalesce(p_events, '[]'::jsonb)) as e
       where e ->> 'id' = x.provider_event_id
     );

  -- Ältere Termine außerhalb des Fensters braucht niemand mehr.
  delete from public.external_events x where x.calendar_id = p_calendar_id and x.ends_at < p_window_start;

  select count(*) into v_count from public.external_events x where x.calendar_id = p_calendar_id;
  return v_count;
end;
$$;

-- Ergebnis eines Abgleichs festhalten.
create function public.outlook_mark_connection(p_connection_id uuid, p_status public.calendar_connection_status, p_error text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.calendar_connections c
     set status = p_status,
         last_error = p_error,
         last_sync_at = case when p_status = 'active' then now() else c.last_sync_at end
   where c.id = p_connection_id;
end;
$$;

-- Erster Abgleich direkt nach dem Verbinden.
create function public.outlook_request_sync_for(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.start_outlook_sync(p_user_id);
end;
$$;

revoke execute on function public.outlook_create_oauth_state(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.outlook_consume_oauth_state(text) from public, anon, authenticated;
revoke execute on function public.outlook_save_connection(uuid, text, text, text, text) from public, anon, authenticated;
revoke execute on function public.outlook_upsert_calendars(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.outlook_sync_jobs(text) from public, anon, authenticated;
revoke execute on function public.outlook_store_refresh_token(uuid, text) from public, anon, authenticated;
revoke execute on function public.outlook_apply_events(uuid, timestamptz, timestamptz, jsonb) from public, anon, authenticated;
revoke execute on function public.outlook_mark_connection(uuid, public.calendar_connection_status, text) from public, anon, authenticated;
revoke execute on function public.outlook_request_sync_for(uuid) from public, anon, authenticated;

grant execute on function public.outlook_create_oauth_state(uuid, text, text) to service_role;
grant execute on function public.outlook_consume_oauth_state(text) to service_role;
grant execute on function public.outlook_save_connection(uuid, text, text, text, text) to service_role;
grant execute on function public.outlook_upsert_calendars(uuid, jsonb) to service_role;
grant execute on function public.outlook_sync_jobs(text) to service_role;
grant execute on function public.outlook_store_refresh_token(uuid, text) to service_role;
grant execute on function public.outlook_apply_events(uuid, timestamptz, timestamptz, jsonb) to service_role;
grant execute on function public.outlook_mark_connection(uuid, public.calendar_connection_status, text) to service_role;
grant execute on function public.outlook_request_sync_for(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- Fehlerkatalog: calendar_not_found ergänzen
-- ---------------------------------------------------------------------------

create or replace function private.raise_app_error(p_key text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_state   text;
  v_message text;
begin
  select e.state, e.message
    into v_state, v_message
  from (values
    ('not_authenticated',               '42501', 'Nicht angemeldet.'),
    ('invalid_family_name',             '22023', 'Der Familienname muss 1 bis 60 Zeichen lang sein.'),
    ('invalid_color',                   '22023', 'Die Farbe muss im Format #RRGGBB angegeben werden.'),
    ('invalid_display_name',            '22023', 'Der Anzeigename muss 1 bis 80 Zeichen lang sein.'),
    ('invalid_avatar_path',             '22023', 'Der Bildpfad muss im eigenen Ordner liegen ({user_id}/{datei}).'),
    ('invalid_role',                    '22023', 'Unbekannte Rolle.'),
    ('family_not_found',                'P0002', 'Familie nicht gefunden oder du bist kein Mitglied.'),
    ('member_not_found',                'P0002', 'Diese Person ist kein Mitglied der Familie.'),
    ('invite_not_found',                'P0002', 'Einladung nicht gefunden.'),
    ('profile_not_found',               'P0002', 'Profil nicht gefunden.'),
    ('admin_required',                  '42501', 'Nur Admins dürfen das.'),
    ('permission_denied_invite',        '42501', 'Du darfst in dieser Familie niemanden einladen.'),
    ('permission_denied_manage_family', '42501', 'Du darfst diese Familie nicht bearbeiten.'),
    ('permission_denied_remove_members','42501', 'Du darfst in dieser Familie keine Mitglieder entfernen.'),
    ('admin_required_to_remove_admin',  '42501', 'Nur Admins dürfen andere Admins entfernen.'),
    ('last_admin',                      'P0001', 'Die Familie braucht mindestens einen Admin. Ernenne zuerst eine andere Person zum Admin.'),
    ('invite_code_generation_failed',   'P0001', 'Es konnte kein eindeutiger Einladungscode erzeugt werden. Bitte erneut versuchen.'),
    ('invalid_task_title',              '22023', 'Der Titel muss 1 bis 200 Zeichen lang sein.'),
    ('invalid_task_description',        '22023', 'Die Beschreibung darf höchstens 4000 Zeichen lang sein.'),
    ('invalid_start',                   '22023', 'Eine Uhrzeit braucht auch ein Datum.'),
    ('invalid_timezone',                '22023', 'Unbekannte Zeitzone.'),
    ('invalid_completion_mode',         '22023', 'Bitte wähle eine Erledigungsart.'),
    ('assignees_required',              '22023', 'Bitte weise mindestens eine Person zu.'),
    ('assignee_not_member',             '22023', 'Zugewiesene Personen müssen Mitglied der Familie sein.'),
    ('too_many_images',                 '22023', 'Eine Aufgabe kann höchstens 10 Bilder haben.'),
    ('invalid_image',                   '22023', 'Ein Bild wurde nicht vollständig hochgeladen. Bitte versuche es erneut.'),
    ('task_not_found',                  'P0002', 'Aufgabe nicht gefunden oder für dich nicht sichtbar.'),
    ('task_conflict',                   'P0001', 'Die Aufgabe wurde inzwischen von jemand anderem geändert. Bitte öffne sie neu.'),
    ('task_closed',                     'P0001', 'Erledigte oder gelöschte Aufgaben können nicht bearbeitet werden.'),
    ('completion_mode_locked',          'P0001', 'Die Erledigungsart lässt sich nicht mehr ändern, weil schon jemand abgehakt hat.'),
    ('not_allowed_to_complete',         '42501', 'Nur zugewiesene Personen oder wer die Aufgabe erstellt hat, dürfen sie abhaken.'),
    ('invalid_scope',                   '22023', 'Unbekannte Aktion.'),
    ('invalid_recurrence',              '22023', 'Bitte wähle für die Wiederholung mindestens einen Wochentag bzw. Monatstag.'),
    ('recurrence_requires_date',        '22023', 'Eine wiederkehrende Aufgabe braucht ein Startdatum.'),
    ('not_an_occurrence',               '22023', 'Diese Aufgabe gehört zu keiner Serie.'),
    ('series_not_found',                'P0002', 'Serie nicht gefunden oder für dich nicht sichtbar.'),
    ('series_deleted',                  'P0001', 'Die Serie wurde gelöscht. Stelle sie zuerst im Verlauf wieder her.'),
    ('restore_series_instead',          'P0001', 'Dieses Vorkommen wurde mit der ganzen Serie gelöscht. Stelle die Serie im Verlauf wieder her.'),
    ('series_deletion_not_found',       'P0002', 'Dieser Verlaufseintrag existiert nicht mehr.'),
    ('invalid_range',                   '22023', 'Der Zeitraum ist zu groß oder ungültig.'),
    ('permission_denied_create_tasks',  '42501', 'In dieser Familie dürfen nur Admins Aufgaben anlegen.'),
    ('permission_denied_edit_tasks',    '42501', 'In dieser Familie dürfen nur Admins Aufgaben bearbeiten.'),
    ('permission_denied_delete_tasks',  '42501', 'In dieser Familie dürfen nur Admins Aufgaben löschen oder wiederherstellen.'),
    ('calendar_not_found',              'P0002', 'Kalender nicht gefunden.')
  ) as e(key, state, message)
  where e.key = p_key;

  if v_state is null then
    v_state := 'P0001';
    v_message := 'Unbekannter Fehler.';
  end if;

  raise exception using
    errcode = v_state,
    message = v_message,
    hint    = p_key;
end;
$$;

revoke execute on function private.raise_app_error(text) from public, anon, authenticated;
