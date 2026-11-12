-- 0003_tasks
-- Tests für Aufgaben (Migration 0007): Eingaben, Sichtbarkeit, Abhaken, Bearbeiten, Bilder, Realtime.
-- Löschen/Wiederherstellen testet 0004_tasks_papierkorb.sql (eigene Datei, weil SQL mit
-- dem Wort für Löschen eine Bestätigung im Supabase-MCP auslöst).
--
-- Harness wie 0001/0002: eine Transaktion, am Ende rollback.
-- Familie F (Sichtbarkeit „alle“): Clara (Admin), Max, Mia. Familie G („nur zugewiesene“): dieselben drei.
-- Otto ist in keiner Familie.

begin;

-- ---------------------------------------------------------------------------
-- Test-Infrastruktur (nur in dieser Transaktion)
-- ---------------------------------------------------------------------------

create schema tests;
grant usage on schema tests to authenticated, anon;

create table tests.results (
  id     serial primary key,
  name   text not null,
  passed boolean not null,
  info   text
);
create table tests.ctx (key text primary key, val text);

select set_config('tests.base_role', current_user, true);

create function tests.u(p_name text) returns uuid
language sql immutable as $$
  select case p_name
    when 'clara' then 'c1111111-1111-4111-8111-111111111111'
    when 'max'   then 'c2222222-2222-4222-8222-222222222222'
    when 'mia'   then 'c3333333-3333-4333-8333-333333333333'
    when 'otto'  then 'c4444444-4444-4444-8444-444444444444'
  end::uuid;
$$;

create function tests.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    case when p_user is null
      then json_build_object('role', 'authenticated')::text
      else json_build_object('sub', p_user, 'role', 'authenticated')::text
    end, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create function tests.act_as_anon() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('role', 'anon', true);
end;
$$;

create function tests.act_as_base() returns void
language plpgsql as $$
begin
  perform set_config('role', current_setting('tests.base_role'), true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

-- Führt eine Abfrage als Nutzer aus; Ergebnis (erste Spalte) als Text
-- oder 'ERROR:<hint|SQLSTATE>'. p_role: 'authenticated' | 'anon' | 'owner'
-- ('owner' = ohne Rollenwechsel, als Eigentümer der Objekte).
create function tests.run_as(p_user uuid, p_sql text, p_role text default 'authenticated')
returns text
language plpgsql as $$
declare
  v_result text;
  v_hint   text;
  v_state  text;
begin
  if p_role = 'anon' then
    perform tests.act_as_anon();
  elsif p_role = 'authenticated' then
    perform tests.act_as(p_user);
  end if;
  begin
    execute p_sql into v_result;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint, v_state = returned_sqlstate;
    perform tests.act_as_base();
    -- Nur App-Fehlerschlüssel als hint übernehmen; Supabase hängt z. B. an
    -- „permission denied“ einen eigenen Hint („Grant the required privileges …“).
    return 'ERROR:' || case when v_hint ~ '^[a-z][a-z_]*$' then v_hint else v_state end;
  end;
  perform tests.act_as_base();
  return coalesce(v_result, 'NULL');
end;
$$;

create function tests.ok(p_name text, p_passed boolean, p_info text default null) returns void
language sql as $$
  insert into tests.results (name, passed, info) values (p_name, coalesce(p_passed, false), p_info);
$$;

create function tests.expect(p_name text, p_actual text, p_expected text) returns void
language sql as $$
  select tests.ok(p_name, p_actual is not distinct from p_expected,
                  'erwartet: ' || coalesce(p_expected, 'NULL') || ' | erhalten: ' || coalesce(p_actual, 'NULL'));
$$;

create function tests.put(p_key text, p_val text) returns text
language sql as $$
  insert into tests.ctx (key, val) values (p_key, p_val)
  on conflict (key) do update set val = excluded.val
  returning val;
$$;

create function tests.get(p_key text) returns text
language sql stable as $$ select val from tests.ctx where key = p_key; $$;

create function tests.id(p_key text) returns uuid
language sql stable as $$
  select case when val ~ '^[0-9a-f-]{36}$' then val::uuid end from tests.ctx where key = p_key;
$$;

grant all on all tables in schema tests to authenticated, anon;
grant all on all sequences in schema tests to authenticated, anon;

-- ---------------------------------------------------------------------------
-- A. Testnutzer und Familien
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  (tests.u('clara'), 'clara@example.test', '{"full_name": "Clara"}', '{}', 'authenticated', 'authenticated'),
  (tests.u('max'),   'max@example.test',   '{"full_name": "Max"}',   '{}', 'authenticated', 'authenticated'),
  (tests.u('mia'),   'mia@example.test',   '{"full_name": "Mia"}',   '{}', 'authenticated', 'authenticated'),
  (tests.u('otto'),  'otto@example.test',  '{"full_name": "Otto"}',  '{}', 'authenticated', 'authenticated');

select tests.put('f', tests.run_as(tests.u('clara'), $$select (public.create_family('Familie F', '#5EC2F2')).id$$));
select tests.put('g', tests.run_as(tests.u('clara'), $$select (public.create_family('Familie G', '#B39DFF')).id$$));
select tests.put('f_code', tests.run_as(tests.u('clara'), format($$select (public.create_invite(%L)).code$$, tests.id('f'))));
select tests.put('g_code', tests.run_as(tests.u('clara'), format($$select (public.create_invite(%L)).code$$, tests.id('g'))));
select tests.run_as(tests.u(n), format($$select public.join_family(%L) ->> 'status'$$, tests.get('f_code'))) from unnest(array['max','mia']) as n;
select tests.run_as(tests.u(n), format($$select public.join_family(%L) ->> 'status'$$, tests.get('g_code'))) from unnest(array['max','mia']) as n;
select tests.run_as(tests.u('clara'), format($$select (public.update_family(%L, null, null, 'assigned_only')).task_visibility$$, tests.id('g')));
select tests.expect('A1 beide Familien mit drei Mitgliedern',
  (select count(*)::text from public.family_members where family_id in (tests.id('f'), tests.id('g'))), '6');

-- ---------------------------------------------------------------------------
-- B. create_task: Eingaben
-- ---------------------------------------------------------------------------

select tests.put('t1', tests.run_as(tests.u('max'), format(
  $$select (public.create_task(%L, '  Müll rausbringen  ', 'any_one', array[%L]::uuid[])).id$$,
  tests.id('f'), tests.u('mia'))));
select tests.ok('B1 [Max] legt Aufgabe für Mia an', tests.id('t1') is not null, tests.get('t1'));
select tests.expect('B2 Titel getrimmt, Ersteller Max, nicht automatisch zugewiesen',
  (select t.title || '|' || (t.created_by = tests.u('max'))::text || '|' ||
          (select string_agg(a.user_id::text, ',') from public.task_assignees a where a.task_id = t.id)
     from public.tasks t where t.id = tests.id('t1')),
  'Müll rausbringen|true|' || tests.u('mia')::text);
select tests.expect('B3 ohne Personen',
  tests.run_as(tests.u('max'), format($$select (public.create_task(%L, 'X', 'any_one', '{}'::uuid[])).id$$, tests.id('f'))),
  'ERROR:assignees_required');
select tests.expect('B4 Person außerhalb der Familie',
  tests.run_as(tests.u('max'), format($$select (public.create_task(%L, 'X', 'any_one', array[%L]::uuid[])).id$$, tests.id('f'), tests.u('otto'))),
  'ERROR:assignee_not_member');
select tests.expect('B5 Uhrzeit ohne Datum',
  tests.run_as(tests.u('max'), format($$select (public.create_task(%L, 'X', 'any_one', array[%L]::uuid[], p_start_time => '08:00')).id$$, tests.id('f'), tests.u('mia'))),
  'ERROR:invalid_start');
select tests.expect('B6 unbekannte Zeitzone',
  tests.run_as(tests.u('max'), format($$select (public.create_task(%L, 'X', 'any_one', array[%L]::uuid[], p_timezone => 'Mars/Olympus')).id$$, tests.id('f'), tests.u('mia'))),
  'ERROR:invalid_timezone');
select tests.expect('B7 ohne Erledigungsart',
  tests.run_as(tests.u('max'), format($$select (public.create_task(%L, 'X', null, array[%L]::uuid[])).id$$, tests.id('f'), tests.u('mia'))),
  'ERROR:invalid_completion_mode');
select tests.expect('B8 leerer Titel',
  tests.run_as(tests.u('max'), format($$select (public.create_task(%L, '   ', 'any_one', array[%L]::uuid[])).id$$, tests.id('f'), tests.u('mia'))),
  'ERROR:invalid_task_title');
select tests.expect('B9 [Otto] in fremder Familie',
  tests.run_as(tests.u('otto'), format($$select (public.create_task(%L, 'X', 'any_one', array[%L]::uuid[])).id$$, tests.id('f'), tests.u('mia'))),
  'ERROR:family_not_found');
select tests.put('t_dated', tests.run_as(tests.u('max'), format(
  $$select (public.create_task(%L, 'Arzt', 'any_one', array[%L]::uuid[], p_start_date => '2026-11-03', p_start_time => '08:15', p_timezone => 'Europe/Berlin')).id$$,
  tests.id('f'), tests.u('max'))));
select tests.expect('B10 starts_at aus Datum, Uhrzeit und Zeitzone (Winterzeit UTC+1)',
  (select to_char(starts_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI') from public.tasks where id = tests.id('t_dated')),
  '2026-11-03 07:15');
select tests.expect('B11 sort_at = starts_at',
  (select (sort_at = starts_at)::text from public.tasks where id = tests.id('t_dated')), 'true');

-- ---------------------------------------------------------------------------
-- C. Sichtbarkeit (Familie G: nur zugewiesene; Ersteller sieht eigene immer – F1)
-- ---------------------------------------------------------------------------

select tests.put('tg', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Geheim', 'any_one', array[%L]::uuid[])).id$$, tests.id('g'), tests.u('mia'))));
select tests.expect('C1 [Clara] sieht F-Aufgabe von Max (Sichtbarkeit alle)',
  tests.run_as(tests.u('clara'), format($$select count(*) from public.tasks where id = %L$$, tests.id('t1'))), '1');
select tests.expect('C2 [Max] sieht G-Aufgabe nicht (nicht zugewiesen)',
  tests.run_as(tests.u('max'), format($$select count(*) from public.tasks where id = %L$$, tests.id('tg'))), '0');
select tests.expect('C3 [Mia] sieht G-Aufgabe (zugewiesen)',
  tests.run_as(tests.u('mia'), format($$select count(*) from public.tasks where id = %L$$, tests.id('tg'))), '1');
select tests.expect('C4 [Clara] sieht eigene G-Aufgabe ohne Zuweisung (F1)',
  tests.run_as(tests.u('clara'), format($$select count(*) from public.tasks where id = %L$$, tests.id('tg'))), '1');
select tests.expect('C5 [Max] sieht Zuweisungen der G-Aufgabe nicht',
  tests.run_as(tests.u('max'), format($$select count(*) from public.task_assignees where task_id = %L$$, tests.id('tg'))), '0');
select tests.expect('C6 [Otto] sieht keine Aufgaben',
  tests.run_as(tests.u('otto'), $$select count(*) from public.tasks$$), '0');
select tests.expect('C7 [anon] darf nicht lesen',
  tests.run_as(null, $$select count(*) from public.tasks$$, 'anon'), 'ERROR:42501');
select tests.expect('C8 [Max] kann unsichtbare Aufgabe nicht abhaken',
  tests.run_as(tests.u('max'), format($$select (public.complete_task(%L, 'all')).id$$, tests.id('tg'))), 'ERROR:task_not_found');
select tests.expect('C9 kein direktes Schreiben',
  tests.run_as(tests.u('max'), format($$update public.tasks set title = 'x' where id = %L returning id$$, tests.id('t1'))), 'ERROR:42501');

-- ---------------------------------------------------------------------------
-- D. Abhaken „Eine Person für alle“
-- ---------------------------------------------------------------------------

select tests.expect('D1 [Clara] weder zugewiesen noch Ersteller',
  tests.run_as(tests.u('clara'), format($$select (public.complete_task(%L)).id$$, tests.id('t1'))), 'ERROR:not_allowed_to_complete');
select tests.expect('D2 [Mia] hakt ab → ganze Aufgabe erledigt',
  tests.run_as(tests.u('mia'), format($$select (public.complete_task(%L)).completion_source$$, tests.id('t1'))), 'assignee');
select tests.expect('D3 erneutes Abhaken ist idempotent',
  tests.run_as(tests.u('mia'), format($$select (public.complete_task(%L)).completed_by$$, tests.id('t1'))), tests.u('mia')::text);
select tests.expect('D4 [Clara] öffnet wieder (Rückgängig für alle mit Sicht)',
  tests.run_as(tests.u('clara'), format($$select coalesce((public.uncomplete_task(%L, 'all')).completed_at::text, 'offen')$$, tests.id('t1'))), 'offen');
select tests.expect('D5 [Max] als Ersteller erledigt für alle',
  tests.run_as(tests.u('max'), format($$select (public.complete_task(%L, 'all')).completion_source$$, tests.id('t1'))), 'creator');
select tests.expect('D6 ungültiger Umfang',
  tests.run_as(tests.u('max'), format($$select (public.complete_task(%L, 'irgendwas')).id$$, tests.id('t1'))), 'ERROR:invalid_scope');

-- ---------------------------------------------------------------------------
-- E. Abhaken „Jede Person einzeln“ (Ersteller Clara, zugewiesen Max + Mia)
-- ---------------------------------------------------------------------------

select tests.put('te', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Zimmer', 'each', array[%L, %L]::uuid[])).id$$, tests.id('f'), tests.u('max'), tests.u('mia'))));
select tests.expect('E1 [Max] hakt für sich ab → Aufgabe bleibt offen',
  tests.run_as(tests.u('max'), format($$select coalesce((public.complete_task(%L, 'self')).completed_at::text, 'offen')$$, tests.id('te'))), 'offen');
select tests.expect('E2 Status pro Person',
  (select string_agg((completed_at is not null)::text, ',' order by user_id) from public.task_assignees where task_id = tests.id('te')),
  'true,false');
select tests.expect('E3 [Mia] hakt ab → komplett erledigt',
  tests.run_as(tests.u('mia'), format($$select (public.complete_task(%L, 'self')).completion_source$$, tests.id('te'))), 'assignee');
-- Hinweis: Änderung und Prüfung in getrennten Anweisungen – innerhalb einer Anweisung sieht
-- Postgres die Änderungen der aufgerufenen Funktion noch nicht.
select tests.expect('E4 [Mia] nimmt Haken zurück → wieder offen',
  tests.run_as(tests.u('mia'), format($$select coalesce((public.uncomplete_task(%L, 'self')).completed_at::text, 'offen')$$, tests.id('te'))),
  'offen');
select tests.expect('E4b Max bleibt erledigt, Mia offen',
  (select string_agg((completed_at is not null)::text, ',' order by user_id) from public.task_assignees where task_id = tests.id('te')),
  'true,false');
select tests.expect('E5 [Max] darf nicht für alle erledigen (nicht Ersteller)',
  tests.run_as(tests.u('max'), format($$select (public.complete_task(%L, 'all')).id$$, tests.id('te'))), 'ERROR:not_allowed_to_complete');

-- ---------------------------------------------------------------------------
-- F. update_task
-- ---------------------------------------------------------------------------

select tests.expect('F1 veraltete Version',
  tests.run_as(tests.u('mia'), format($$select (public.update_task(%L, 1, 'Neu', 'each', array[%L]::uuid[])).id$$, tests.id('te'), tests.u('mia'))),
  'ERROR:task_conflict');
select tests.expect('F2 Erledigungsart gesperrt, weil Max schon abgehakt hat',
  tests.run_as(tests.u('mia'), format($$select (public.update_task(%L, %s, 'Neu', 'any_one', array[%L, %L]::uuid[])).id$$,
    tests.id('te'), (select version from public.tasks where id = tests.id('te')), tests.u('max'), tests.u('mia'))),
  'ERROR:completion_mode_locked');
select tests.expect('F3 [Mia] entfernt Max und ändert den Titel; Aufgabe bleibt offen',
  tests.run_as(tests.u('mia'), format($$select (u).title || '|' || ((u).completed_at is null)::text from (select public.update_task(%L, %s, ' Zimmer aufräumen ', 'each', array[%L]::uuid[], p_description => 'Bitte bis Freitag') as u) s$$,
    tests.id('te'), (select version from public.tasks where id = tests.id('te')), tests.u('mia'))),
  'Zimmer aufräumen|true');
select tests.expect('F3b nur noch Mia zugewiesen',
  (select count(*)::text from public.task_assignees where task_id = tests.id('te')), '1');
select tests.expect('F4 erledigte Aufgabe nicht bearbeitbar',
  tests.run_as(tests.u('max'), format($$select (public.update_task(%L, %s, 'X', 'any_one', array[%L]::uuid[])).id$$,
    tests.id('t1'), (select version from public.tasks where id = tests.id('t1')), tests.u('mia'))),
  'ERROR:task_closed');
select tests.expect('F5 Datum entfernen: starts_at wird null',
  tests.run_as(tests.u('max'), format($$select coalesce((public.update_task(%L, %s, 'Arzt', 'any_one', array[%L]::uuid[])).starts_at::text, 'ohne')$$,
    tests.id('t_dated'), (select version from public.tasks where id = tests.id('t_dated')), tests.u('max'))),
  'ohne');

-- ---------------------------------------------------------------------------
-- H. Bilder (Bucket task-images)
-- ---------------------------------------------------------------------------

select tests.put('img', 'd1111111-1111-4111-8111-111111111111');
select tests.expect('H1 Bild ohne hochgeladene Dateien → abgelehnt',
  tests.run_as(tests.u('max'), format($$select (public.create_task(%L, 'Mit Bild', 'any_one', array[%L]::uuid[], p_images => %L::jsonb)).id$$,
    tests.id('f'), tests.u('mia'), jsonb_build_array(jsonb_build_object('id', tests.get('img'), 'width', 800, 'height', 600)))),
  'ERROR:invalid_image');
select tests.expect('H2 [Max] lädt Bild und Miniatur in Familie F hoch',
  tests.run_as(tests.u('max'), format($$insert into storage.objects (bucket_id, name, owner_id) values
      ('task-images', %L, %L), ('task-images', %L, %L) returning 'ok'$$,
    tests.get('f') || '/' || tests.get('img') || '.jpg', tests.u('max')::text,
    tests.get('f') || '/' || tests.get('img') || '_thumb.jpg', tests.u('max')::text)),
  'ok');
select tests.expect('H3 [Otto] darf nicht in Familie F hochladen',
  tests.run_as(tests.u('otto'), format($$insert into storage.objects (bucket_id, name) values ('task-images', %L) returning 'ok'$$,
    tests.get('f') || '/d9999999-9999-4999-8999-999999999999.jpg')),
  'ERROR:42501');
select tests.expect('H4 [Max] falscher Dateiname',
  tests.run_as(tests.u('max'), format($$insert into storage.objects (bucket_id, name) values ('task-images', %L) returning 'ok'$$,
    tests.get('f') || '/urlaub.png')),
  'ERROR:42501');
select tests.put('ti', tests.run_as(tests.u('max'), format(
  $$select (public.create_task(%L, 'Mit Bild', 'any_one', array[%L]::uuid[], p_images => %L::jsonb)).id$$,
  tests.id('f'), tests.u('mia'), jsonb_build_array(jsonb_build_object('id', tests.get('img'), 'width', 800, 'height', 600)))));
select tests.expect('H5 Aufgabe mit Bild angelegt, Pfade vom Server',
  (select i.path || '|' || i.width from public.images i join public.task_image_links l on l.image_id = i.id where l.task_id = tests.id('ti')),
  tests.get('f') || '/' || tests.get('img') || '.jpg|800');
-- Duplizieren: dieselbe Bilddatei an einer zweiten Aufgabe der gleichen Familie (ohne neuen Upload).
select tests.put('dup', tests.run_as(tests.u('max'), format(
  $$select (public.create_task(%L, 'Kopie mit Bild', 'any_one', array[%L]::uuid[], p_images => %L::jsonb)).id$$,
  tests.id('f'), tests.u('mia'), jsonb_build_array(jsonb_build_object('id', tests.get('img'), 'width', 800, 'height', 600)))));
select tests.expect('H5b Kopie verknüpft dasselbe Bild',
  (select count(*)::text from public.task_image_links where image_id = tests.get('img')::uuid), '2');
select tests.expect('H5c anderes Familien-Bild lässt sich nicht in Familie G übernehmen',
  tests.run_as(tests.u('max'), format($$select (public.create_task(%L, 'Fremdes Bild', 'any_one', array[%L]::uuid[], p_images => %L::jsonb)).id$$,
    tests.id('g'), tests.u('mia'), jsonb_build_array(jsonb_build_object('id', tests.get('img'), 'width', 800, 'height', 600)))),
  'ERROR:invalid_image');
select tests.expect('H5d Kopie wieder ohne Bild (nur diese Verknüpfung fällt weg)',
  tests.run_as(tests.u('max'), format($$select (public.update_task(%L, %s, 'Kopie mit Bild', 'any_one', array[%L]::uuid[])).id$$,
    tests.id('dup'), (select version from public.tasks where id = tests.id('dup')), tests.u('mia'))),
  tests.get('dup'));
select tests.expect('H5e Original behält sein Bild',
  (select count(*)::text from public.task_image_links where task_id = tests.id('ti')), '1');
select tests.expect('H6 [Mia] sieht Bild und Miniatur',
  tests.run_as(tests.u('mia'), $$select count(*) from storage.objects where bucket_id = 'task-images'$$), '2');
select tests.expect('H7 [Otto] sieht keine Aufgabenbilder',
  tests.run_as(tests.u('otto'), $$select count(*) from storage.objects where bucket_id = 'task-images'$$), '0');
select tests.expect('H8 [Mia] entfernt das Bild per update_task',
  tests.run_as(tests.u('mia'), format($$select (public.update_task(%L, %s, 'Mit Bild', 'any_one', array[%L]::uuid[])).id$$,
    tests.id('ti'), (select version from public.tasks where id = tests.id('ti')), tests.u('mia'))),
  tests.get('ti'));
select tests.expect('H8b Verknüpfung entfernt',
  (select count(*)::text from public.task_image_links where task_id = tests.id('ti')), '0');
select tests.expect('H9 nicht mehr verknüpftes Bild ist unsichtbar',
  tests.run_as(tests.u('mia'), $$select count(*) from storage.objects where bucket_id = 'task-images'$$), '0');

-- ---------------------------------------------------------------------------
-- I. Realtime
-- ---------------------------------------------------------------------------

-- realtime.messages ist nach Tagen partitioniert; die Partitionen legt der Realtime-Dienst selbst an,
-- sobald er für das Projekt aktiv ist. Ohne Partition verwirft realtime.send die Nachricht mit Warnung.
select tests.expect('I1 Hinweise an alle drei Mitglieder von F (übersprungen ohne Realtime-Partition)',
  case when exists (select 1 from pg_inherits where inhparent = 'realtime.messages'::regclass)
    then (select count(distinct topic)::text from realtime.messages
           where topic in ('user:' || tests.u('clara'), 'user:' || tests.u('max'), 'user:' || tests.u('mia'))
             and event = 'task_changed')
    else 'übersprungen' end,
  case when exists (select 1 from pg_inherits where inhparent = 'realtime.messages'::regclass)
    then '3' else 'übersprungen' end);
select tests.expect('I2 kein Hinweis an Otto',
  (select count(*)::text from realtime.messages where topic = 'user:' || tests.u('otto')), '0');
select tests.expect('I3 Empfangs-Policy nur für den eigenen Kanal',
  (select count(*)::text from pg_policies where schemaname = 'realtime' and policyname = 'realtime_receive_own_user_channel' and cmd = 'SELECT'),
  '1');

-- ---------------------------------------------------------------------------
-- Ergebnis
-- ---------------------------------------------------------------------------

select
  (select count(*) from tests.results)                     as gesamt,
  (select count(*) from tests.results where passed)        as bestanden,
  (select count(*) from tests.results where not passed)    as fehlgeschlagen,
  coalesce((select string_agg(name || ' :: ' || coalesce(info, ''), E'\n' order by id)
              from tests.results where not passed), 'alle grün') as fehler,
  (select string_agg(case when passed then 'ok  ' else 'FAIL' end || ' ' || name, E'\n' order by id)
     from tests.results) as protokoll;

rollback;
