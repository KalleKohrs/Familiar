-- 0008_outlook
-- Tests für Migration 0011: Vault, Kalender-/Terminabgleich, strikte Trennung pro Nutzer,
-- keine Token-RPCs für Clients, Trennen, Einmal-State. Ergebnis 2026-10-21: 21/21 (O3 geteilt).

begin;
create schema tests;
grant usage on schema tests to authenticated, anon;
create table tests.results (id serial primary key, name text not null, passed boolean not null, info text);
create table tests.ctx (key text primary key, val text);
select set_config('tests.base_role', current_user, true);
create function tests.u(p_name text) returns uuid language sql immutable as $$
  select case p_name when 'clara' then 'c1111111-1111-4111-8111-111111111111' when 'mia' then 'c3333333-3333-4333-8333-333333333333' end::uuid; $$;
create function tests.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end; $$;
create function tests.act_as_base() returns void language plpgsql as $$
begin
  perform set_config('role', current_setting('tests.base_role'), true);
  perform set_config('request.jwt.claims', '', true);
end; $$;
create function tests.run_as(p_user uuid, p_sql text, p_role text default 'authenticated') returns text language plpgsql as $$
declare v_result text; v_hint text; v_state text;
begin
  if p_role = 'authenticated' then perform tests.act_as(p_user); end if;
  begin
    execute p_sql into v_result;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint, v_state = returned_sqlstate;
    perform tests.act_as_base();
    return 'ERROR:' || case when v_hint ~ '^[a-z][a-z_]*$' then v_hint else v_state end;
  end;
  perform tests.act_as_base();
  return coalesce(v_result, 'NULL');
end; $$;
create function tests.expect(p_name text, p_actual text, p_expected text) returns void language sql as $$
  insert into tests.results (name, passed, info) values (p_name, p_actual is not distinct from p_expected,
    'erwartet: ' || coalesce(p_expected, 'NULL') || ' | erhalten: ' || coalesce(p_actual, 'NULL')); $$;
create function tests.put(p_key text, p_val text) returns text language sql as $$
  insert into tests.ctx values (p_key, p_val) on conflict (key) do update set val = excluded.val returning val; $$;
create function tests.id(p_key text) returns uuid language sql stable as $$ select val::uuid from tests.ctx where key = p_key; $$;
grant all on all tables in schema tests to authenticated;
grant all on all sequences in schema tests to authenticated;
grant all on all functions in schema tests to authenticated;
insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  (tests.u('clara'), 'clara@example.test', '{"full_name": "Clara"}', '{}', 'authenticated', 'authenticated'),
  (tests.u('mia'),   'mia@example.test',   '{"full_name": "Mia"}',   '{}', 'authenticated', 'authenticated');

select tests.put('conn', public.outlook_save_connection(tests.u('clara'), 'acc-1', 'clara@firma.test', 'refresh-1', 'Calendars.ReadBasic')::text);
select tests.expect('O1 Refresh-Token liegt verschlüsselt im Vault',
  (select (s.decrypted_secret = 'refresh-1')::text from private.calendar_credentials c join vault.decrypted_secrets s on s.id = c.vault_secret_id where c.connection_id = tests.id('conn')), 'true');
select tests.expect('O2 Erneutes Verbinden aktualisiert dieselbe Verbindung',
  (public.outlook_save_connection(tests.u('clara'), 'acc-1', 'clara@firma.test', 'refresh-2', 'x') = tests.id('conn'))::text, 'true');
select tests.expect('O3a Kalender angelegt',
  public.outlook_upsert_calendars(tests.id('conn'), '[{"id":"cal-a","name":"Kalender","is_default":true},{"id":"cal-b","name":"Geburtstage","is_default":false}]')::text, '2');
-- Eigener Befehl: im selben Befehl wäre noch der alte Stand sichtbar.
select tests.expect('O3b Standardkalender vorausgewählt',
  (select string_agg(provider_calendar_id || ':' || is_selected::text, ',' order by provider_calendar_id) from public.external_calendars where connection_id = tests.id('conn')),
  'cal-a:true,cal-b:false');
select tests.put('cal', (select id::text from public.external_calendars where provider_calendar_id = 'cal-a'));
select tests.expect('O4 Termine übernehmen',
  public.outlook_apply_events(tests.id('cal'), now() - interval '7 days', now() + interval '120 days',
    jsonb_build_array(
      jsonb_build_object('id','e1','title','Meeting','starts_at', now() + interval '1 day','ends_at', now() + interval '1 day 1 hour','organizer_email','chef@firma.test'),
      jsonb_build_object('id','e2','title','Urlaub','starts_at', '2026-11-02T00:00:00Z','ends_at','2026-11-03T00:00:00Z','is_all_day',true,'start_date','2026-11-02','end_date','2026-11-03')))::text, '2');
select tests.expect('O5 Im Fenster fehlender Termin wird entfernt (in Outlook gelöscht)',
  public.outlook_apply_events(tests.id('cal'), now() - interval '7 days', now() + interval '120 days',
    jsonb_build_array(jsonb_build_object('id','e1','title','Meeting (verschoben)','starts_at', now() + interval '2 days','ends_at', now() + interval '2 days 1 hour')))::text, '1');
select tests.expect('O6 Änderung übernommen',
  (select title from public.external_events where provider_event_id = 'e1'), 'Meeting (verschoben)');

select tests.expect('V1 Clara sieht ihre Verbindung, Kalender und Termine',
  tests.run_as(tests.u('clara'), $$select (select count(*) from public.calendar_connections)::text || '/' || (select count(*) from public.external_calendars)::text || '/' || (select count(*) from public.external_events)::text$$), '1/2/1');
select tests.expect('V2 Mia sieht nichts davon',
  tests.run_as(tests.u('mia'), $$select (select count(*) from public.calendar_connections)::text || '/' || (select count(*) from public.external_calendars)::text || '/' || (select count(*) from public.external_events)::text$$), '0/0/0');
select tests.expect('V3 Clients kommen nicht an Tokens (RPC)',
  tests.run_as(tests.u('clara'), $$select public.outlook_sync_jobs('x')::text$$), 'ERROR:42501');
select tests.expect('V4 Clients können keine Verbindung anlegen',
  tests.run_as(tests.u('clara'), format($$select public.outlook_save_connection(%L, 'a', 'b', 'c', 'd')::text$$, tests.u('clara'))), 'ERROR:42501');
select tests.expect('V5 Clients lesen keine Zugangsdaten',
  tests.run_as(tests.u('clara'), $$select count(*)::text from private.calendar_credentials$$), 'ERROR:42501');
select tests.expect('V6 Clients schreiben nicht direkt in Termine',
  tests.run_as(tests.u('clara'), format($$insert into public.external_events (user_id, calendar_id, provider_event_id, title, starts_at, ends_at) values (%L, %L, 'x', 'x', now(), now()) returning 'ok'$$, tests.u('clara'), tests.id('cal'))), 'ERROR:42501');

select tests.expect('A1 Mia kann Claras Kalender nicht umschalten',
  tests.run_as(tests.u('mia'), format($$select (public.set_calendar_selected(%L, false)).id::text$$, tests.id('cal'))), 'ERROR:calendar_not_found');
select tests.expect('A2 Abwählen entfernt zwischengespeicherte Termine',
  tests.run_as(tests.u('clara'), format($$select (public.set_calendar_selected(%L, false)).is_selected::text$$, tests.id('cal'))), 'false');
select tests.expect('A3 … Termine weg',
  (select count(*)::text from public.external_events where calendar_id = tests.id('cal')), '0');
select tests.expect('A4 Mia kann Claras Verbindung nicht trennen',
  tests.run_as(tests.u('mia'), format($$select 'ok' from (select public.disconnect_calendar(%L)) x$$, tests.id('conn'))), 'ERROR:calendar_not_found');
select tests.put('secret', (select vault_secret_id::text from private.calendar_credentials where connection_id = tests.id('conn')));
select tests.expect('A5 Clara trennt',
  tests.run_as(tests.u('clara'), format($$select 'ok' from (select public.disconnect_calendar(%L)) x$$, tests.id('conn'))), 'ok');
select tests.expect('A6 Verbindung, Kalender und Vault-Geheimnis sind weg',
  (select count(*) from public.calendar_connections where id = tests.id('conn'))::text || '/' ||
  (select count(*) from public.external_calendars where connection_id = tests.id('conn'))::text || '/' ||
  (select count(*) from vault.secrets where id = tests.id('secret'))::text, '0/0/0');
select tests.expect('A7 Abgleich ohne Verbindung wird nicht angestoßen',
  tests.run_as(tests.u('clara'), $$select public.request_calendar_sync()::text$$), 'false');

select public.outlook_create_oauth_state(tests.u('mia'), 'hash-1', 'verifier-1');
select tests.expect('S1 State einlösbar', (public.outlook_consume_oauth_state('hash-1') ->> 'code_verifier'), 'verifier-1');
select tests.expect('S2 … aber nur einmal', coalesce((public.outlook_consume_oauth_state('hash-1'))::text, 'NULL'), 'NULL');

select (select count(*) from tests.results) as gesamt, (select count(*) from tests.results where passed) as bestanden,
  coalesce((select string_agg(name || ' :: ' || coalesce(info, ''), E'\n' order by id) from tests.results where not passed), 'alle grün') as fehler;
rollback;
