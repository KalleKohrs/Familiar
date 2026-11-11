-- 0012_private_tasks
-- Tests für Migration 0021: private Aufgaben und Serien (nur der Ersteller sieht und ändert sie).
-- Läuft in begin … rollback; nach Migration 0021 im SQL-Editor ausführen (oder – vor dem Einspielen –
-- Migration 0021 und diesen Test in einer Transaktion mit rollback).
-- Nutzer: Clara (Admin Familie A), Mia (Mitglied A), Otto (kein Mitglied), Nina (Mitglied A).

begin;

create schema tests;
create table tests.results (id serial primary key, name text not null, passed boolean not null, info text);
create table tests.ctx (key text primary key, val text);
create function tests.put(p_key text, p_val text) returns text
language sql as $$
  insert into tests.ctx (key, val) values (p_key, p_val)
  on conflict (key) do update set val = excluded.val returning val;
$$;
create function tests.get(p_key text) returns text
language sql stable as $$ select val from tests.ctx where key = p_key; $$;

create function tests.expect(p_name text, p_actual text, p_expected text) returns void
language sql as $$
  insert into tests.results (name, passed, info)
  values (p_name, p_actual is not distinct from p_expected,
          'erwartet: ' || coalesce(p_expected, 'NULL') || ' | erhalten: ' || coalesce(p_actual, 'NULL'));
$$;

-- Führt SQL als angemeldeter Nutzer aus (Ergebnis der ersten Spalte oder ERROR:<hint>).
create function tests.run_as(p_user uuid, p_sql text) returns text
language plpgsql as $$
declare v text; v_hint text; v_state text; v_role text := current_user;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    execute p_sql into v;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint, v_state = returned_sqlstate;
    perform set_config('role', current_setting('tests.base_role'), true);
    return 'ERROR:' || case when v_hint ~ '^[a-z][a-z_]*$' then v_hint else v_state end;
  end;
  perform set_config('role', current_setting('tests.base_role'), true);
  return coalesce(v, 'NULL');
end;
$$;
select set_config('tests.base_role', current_user, true);
grant usage on schema tests to authenticated;
grant all on all tables in schema tests to authenticated;
grant all on all sequences in schema tests to authenticated;
grant all on all functions in schema tests to authenticated;


insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  ('c1111111-1111-4111-8111-111111111111', 'clara@example.test', '{"full_name": "Clara"}', '{}', 'authenticated', 'authenticated'),
  ('c3333333-3333-4333-8333-333333333333', 'mia@example.test',   '{"full_name": "Mia"}',   '{}', 'authenticated', 'authenticated'),
  ('c4444444-4444-4444-8444-444444444444', 'otto@example.test',  '{"full_name": "Otto"}',  '{}', 'authenticated', 'authenticated'),
  ('c5555555-5555-4555-8555-555555555555', 'nina@example.test',  '{"full_name": "Nina"}',  '{}', 'authenticated', 'authenticated');

create function tests.sees(p_user uuid, p_task uuid) returns text
language sql as $$
  select tests.run_as(p_user, format('select count(*)::text from public.tasks where id = %L', p_task));
$$;

create function tests.try(p_sql text) returns text
language plpgsql as $$
begin execute p_sql; return 'ok';
exception when others then return 'ERROR:' || sqlstate; end;
$$;

-- Familie A (Clara Admin; Mia, Nina Mitglieder), Sichtbarkeit zunächst „alle“.
select tests.put('fa', tests.run_as('c1111111-1111-4111-8111-111111111111', $$select (public.create_family('A', '#5EC2F2')).id$$));
select tests.put('ca', tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select (public.create_invite(%L)).code$$, tests.get('fa'))));
select tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select public.join_family(%L) ->> 'status'$$, tests.get('ca')));
select tests.run_as('c5555555-5555-4555-8555-555555555555', format($$select public.join_family(%L) ->> 'status'$$, tests.get('ca')));

-- Mia legt eine private Aufgabe an – absichtlich mit Clara als „zugewiesen“ (wird ignoriert).
select tests.put('p1', tests.run_as('c3333333-3333-4333-8333-333333333333', format(
  $$select (public.create_task(%L, 'Geschenk für Papa', 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[],
            null, null, null, 'Europe/Berlin', '[]'::jsonb, true)).id::text$$, tests.get('fa'))));
select tests.put('s1', tests.run_as('c3333333-3333-4333-8333-333333333333', format(
  $$select (public.create_task(%L, 'Gemeinsam', 'any_one', array['c3333333-3333-4333-8333-333333333333']::uuid[])).id::text$$, tests.get('fa'))));

-- Lesen
select tests.expect('P1 Ersteller sieht die private Aufgabe', tests.sees('c3333333-3333-4333-8333-333333333333', tests.get('p1')::uuid), '1');
select tests.expect('P2 Admin (Sichtbarkeit „alle“) sieht sie nicht', tests.sees('c1111111-1111-4111-8111-111111111111', tests.get('p1')::uuid), '0');
select tests.expect('P3 anderes Mitglied sieht sie nicht', tests.sees('c5555555-5555-4555-8555-555555555555', tests.get('p1')::uuid), '0');
select tests.expect('P4 Nicht-Mitglied sieht sie nicht', tests.sees('c4444444-4444-4444-8444-444444444444', tests.get('p1')::uuid), '0');
select tests.expect('P5 normale Aufgabe bleibt für alle sichtbar (Admin)', tests.sees('c1111111-1111-4111-8111-111111111111', tests.get('s1')::uuid), '1');
select tests.expect('P6 private Aufgabe: ist privat und nur dem Ersteller zugewiesen',
  (select t.is_private::text || '|' || t.created_by::text || '|' || (select string_agg(a.user_id::text, ',')
     from public.task_assignees a where a.task_id = t.id) from public.tasks t where t.id = tests.get('p1')::uuid),
  'true|' || 'c3333333-3333-4333-8333-333333333333' || '|' || 'c3333333-3333-4333-8333-333333333333');
select tests.expect('P6b Zuweisung für andere unsichtbar (Admin sieht keine Zuweisung)',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select count(*)::text from public.task_assignees where task_id = %L$$, tests.get('p1'))), '0');

-- Sichtbarkeit „nur Zugewiesene“: ändert nichts
select tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select (public.update_family(%L, null, null, 'assigned_only')).id::text$$, tests.get('fa')));
select tests.expect('P7 „nur Zugewiesene“: Ersteller sieht weiter', tests.sees('c3333333-3333-4333-8333-333333333333', tests.get('p1')::uuid), '1');
select tests.expect('P8 „nur Zugewiesene“: Admin sieht nicht', tests.sees('c1111111-1111-4111-8111-111111111111', tests.get('p1')::uuid), '0');
-- Schreiben durch andere: wie „nicht gefunden“
select tests.expect('P9 Admin kann nicht bearbeiten',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select (public.update_task(%L, 1, 'Hack', 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[])).id::text$$, tests.get('p1'))),
  'ERROR:task_not_found');
select tests.expect('P10 Admin kann nicht löschen',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select (public.delete_task(%L)).id::text$$, tests.get('p1'))), 'ERROR:task_not_found');
select tests.expect('P11 Admin kann nicht abhaken',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select (public.complete_task(%L)).id::text$$, tests.get('p1'))), 'ERROR:task_not_found');
select tests.expect('P12 anderes Mitglied kann nicht anstupsen',
  tests.run_as('c5555555-5555-4555-8555-555555555555', format($$select (public.nudge_task(%L, 'c3333333-3333-4333-8333-333333333333')) ->> 'quiet_hours'$$, tests.get('p1'))), 'ERROR:task_not_found');

-- Schreiben durch den Ersteller: alles wie bisher, auch gegen Familienrechte
select tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select (public.set_family_permissions(%L, null, null, null, false, false, false)).id::text$$, tests.get('fa')));
select tests.expect('P13 Ersteller bearbeitet trotz gesperrtem „bearbeiten“; Zuweisung bleibt er allein',
  tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.update_task(%L, 1, 'Geschenk für Opa', 'any_one', array['c1111111-1111-4111-8111-111111111111','c5555555-5555-4555-8555-555555555555']::uuid[])).title$$, tests.get('p1'))),
  'Geschenk für Opa');
select tests.expect('P13b nach dem Bearbeiten nur noch der Ersteller zugewiesen',
  (select string_agg(a.user_id::text, ',') from public.task_assignees a where a.task_id = tests.get('p1')::uuid), 'c3333333-3333-4333-8333-333333333333');
select tests.expect('P14 Ersteller legt trotz gesperrtem „anlegen“ eine private Aufgabe an',
  (tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.create_task(%L, 'Noch eine', 'any_one', array['c3333333-3333-4333-8333-333333333333']::uuid[],
     null, null, null, 'Europe/Berlin', '[]'::jsonb, true)).id::text$$, tests.get('fa'))) ~ '^[0-9a-f-]{36}$')::text, 'true');
select tests.expect('P14b … aber keine gemeinsame Aufgabe',
  tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.create_task(%L, 'Gemeinsam 2', 'any_one', array['c3333333-3333-4333-8333-333333333333']::uuid[])).id::text$$, tests.get('fa'))),
  'ERROR:permission_denied_create_tasks');
select tests.put('p2', tests.run_as('c3333333-3333-4333-8333-333333333333', format(
  $$select (public.create_task(%L, 'Zum Löschen', 'any_one', array['c3333333-3333-4333-8333-333333333333']::uuid[],
            null, null, null, 'Europe/Berlin', '[]'::jsonb, true)).id::text$$, tests.get('fa'))));
select tests.expect('P15 Ersteller löscht trotz gesperrtem „löschen“',
  tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.delete_task(%L)).deleted_at is not null$$, tests.get('p2'))), 'true');
select tests.expect('P16 … und stellt wieder her',
  tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.restore_task(%L)).deleted_at is null$$, tests.get('p2'))), 'true');
select tests.expect('P17 Ersteller hakt ab',
  tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.complete_task(%L)).completed_at is not null$$, tests.get('p1'))), 'true');
select tests.expect('P18 Ersteller macht Abhaken rückgängig',
  tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.uncomplete_task(%L)).completed_at is null$$, tests.get('p1'))), 'true');
select tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select (public.set_family_permissions(%L, null, null, null, true, true, true)).id::text$$, tests.get('fa')));

-- Direkter Datenbankzugriff kann keine Fremden zuweisen
select tests.expect('P19 Zuweisung eines Fremden an eine private Aufgabe wird von der Datenbank abgewiesen',
  tests.try(format($$insert into public.task_assignees (task_id, user_id) values (%L, 'c1111111-1111-4111-8111-111111111111')$$, tests.get('p1'))),
  'ERROR:23514');

-- Bilder: Verknüpfung über eine private Aufgabe ist nur für den Ersteller sichtbar
insert into public.images (id, family_id, path, thumb_path, width, height, created_by)
values ('d1111111-1111-4111-8111-111111111111', tests.get('fa')::uuid,
        tests.get('fa') || '/d1111111-1111-4111-8111-111111111111.jpg',
        tests.get('fa') || '/d1111111-1111-4111-8111-111111111111_thumb.jpg', 100, 100, 'c3333333-3333-4333-8333-333333333333'::uuid);
insert into public.task_image_links (task_id, image_id, position)
values (tests.get('p1')::uuid, 'd1111111-1111-4111-8111-111111111111', 0);
select tests.expect('B1 Bild: Ersteller sieht Bildzeile und Verknüpfung',
  tests.run_as('c3333333-3333-4333-8333-333333333333', $$select (select count(*) from public.images)::text || '|' || (select count(*) from public.task_image_links)$$), '1|1');
select tests.expect('B2 Bild: Admin und anderes Mitglied sehen nichts',
  tests.run_as('c1111111-1111-4111-8111-111111111111', $$select (select count(*) from public.images)::text || '|' || (select count(*) from public.task_image_links)$$)
  || ',' || tests.run_as('c5555555-5555-4555-8555-555555555555', $$select (select count(*) from public.images)::text || '|' || (select count(*) from public.task_image_links)$$), '0|0,0|0');
insert into storage.objects (bucket_id, name)
values ('task-images', tests.get('fa') || '/d1111111-1111-4111-8111-111111111111.jpg'),
       ('task-images', tests.get('fa') || '/d1111111-1111-4111-8111-111111111111_thumb.jpg');
select tests.expect('B3 Storage-Policy: Ersteller sieht beide Dateien, Admin und Mitglied keine',
  tests.run_as('c3333333-3333-4333-8333-333333333333', $$select count(*)::text from storage.objects where bucket_id = 'task-images'$$)
  || ',' || tests.run_as('c1111111-1111-4111-8111-111111111111', $$select count(*)::text from storage.objects where bucket_id = 'task-images'$$)
  || ',' || tests.run_as('c5555555-5555-4555-8555-555555555555', $$select count(*)::text from storage.objects where bucket_id = 'task-images'$$),
  '2,0,0');

-- Benachrichtigungen: für andere nichts; Mia erhält als Einzige Erinnerungen
select tests.expect('N1 Anlegen/Ändern/Abhaken erzeugte keine Aufträge an andere',
  (select count(*)::text from public.notification_jobs j where j.task_id = tests.get('p1')::uuid and j.user_id <> 'c3333333-3333-4333-8333-333333333333'::uuid), '0');
select tests.expect('N2 … und auch keine an den Ersteller selbst als Auslöser',
  (select count(*)::text from public.notification_jobs j where j.task_id = tests.get('p1')::uuid and j.kind in ('assigned','changed','completed','deleted')), '0');

-- Verlauf: erledigte/gelöschte private Aufgaben sind für andere unsichtbar
select tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.complete_task(%L)).id::text$$, tests.get('p1')));
select tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.delete_task(%L)).id::text$$, tests.get('p2')));
select tests.expect('V1 Verlauf: Admin sieht keine erledigten/gelöschten privaten Aufgaben',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select count(*)::text from public.tasks where id in (%L, %L)$$, tests.get('p1'), tests.get('p2'))), '0');
select tests.expect('V2 Verlauf: Ersteller sieht beide',
  tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select count(*)::text from public.tasks where id in (%L, %L)$$, tests.get('p1'), tests.get('p2'))), '2');
select tests.expect('V3 Admin leert den Verlauf: private Aufgaben anderer bleiben',
  (tests.run_as('c1111111-1111-4111-8111-111111111111', $$select public.clear_history()::text$$) is not null)::text
  || '|' || (select count(*)::text from public.tasks where id in (tests.get('p1')::uuid, tests.get('p2')::uuid)), 'true|2');
-- Serien
select tests.put('r1', tests.run_as('c3333333-3333-4333-8333-333333333333', format(
  $$select (public.create_recurring_task(%L, 'Privat täglich', 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[], 'daily',
            (now() at time zone 'Europe/Berlin')::date, '{}', '{}', null, null, 'Europe/Berlin', '[]'::jsonb,
            'rotate', 'occurrence', true)).id::text$$, tests.get('fa'))));
select tests.expect('R1 private Serie: privat, nie Reihum, nur Ersteller zugewiesen',
  (select s.is_private::text || '|' || s.assignment_mode || '|' || (select string_agg(a.user_id::text, ',') from public.series_assignees a where a.series_id = s.id)
   from public.task_series s where s.id = tests.get('r1')::uuid), 'true|together|' || 'c3333333-3333-4333-8333-333333333333');
select tests.expect('R2 Termine erben „privat“ und sind nur dem Ersteller zugewiesen',
  (select count(*)::text || '|' || bool_and(t.is_private)::text || '|' || count(distinct a.user_id)::text
   from public.tasks t join public.task_assignees a on a.task_id = t.id where t.series_id = tests.get('r1')::uuid), '2|true|1');
select tests.put('rt', (select id::text from public.tasks where series_id = tests.get('r1')::uuid order by occurrence_date limit 1));
select tests.expect('R3 Serie: Admin und Mitglied sehen weder Serie noch Termin',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select count(*)::text from public.task_series where id = %L$$, tests.get('r1')))
  || ',' || tests.run_as('c5555555-5555-4555-8555-555555555555', format($$select count(*)::text from public.tasks where series_id = %L$$, tests.get('r1'))), '0,0');
select tests.expect('R4 Serie: Ersteller sieht sie',
  tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select count(*)::text from public.task_series where id = %L$$, tests.get('r1'))), '1');
select tests.expect('R5 Kalender-Projektion: nur für den Ersteller',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select count(*)::text from public.project_series_occurrences(current_date, current_date + 30) p where p.series_id = %L$$, tests.get('r1')))
  || ',' || (tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select count(*)::text from public.project_series_occurrences(current_date, current_date + 30) p where p.series_id = %L$$, tests.get('r1')))::int > 0)::text, '0,true');
select tests.expect('R6 Admin kann Serie nicht ändern/löschen',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select (public.delete_series(%L)).id::text$$, tests.get('rt'))), 'ERROR:task_not_found');
select tests.expect('R7 Ersteller ändert „ab diesem Termin“, Zuweisung bleibt er allein',
  tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.update_series_from(%L, 1, 'Privat neu', 'any_one', array['c1111111-1111-4111-8111-111111111111','c5555555-5555-4555-8555-555555555555']::uuid[], 'daily',
     (now() at time zone 'Europe/Berlin')::date)).title$$, tests.get('rt'))), 'Privat neu');
select tests.expect('R7b … alle Termine weiter nur ihm zugewiesen',
  (select count(distinct a.user_id)::text from public.tasks t join public.task_assignees a on a.task_id = t.id
    where t.series_id = tests.get('r1')::uuid), '1');
select tests.expect('R8 Ersteller löscht die Serie und stellt sie wieder her',
  tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.delete_series(%L)).id is not null$$, tests.get('rt')))
  || ',' || tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select (public.restore_series_deletion((select id from public.series_deletions where series_id = %L))).deleted_at is null$$, tests.get('r1'))), 'true,true');
select tests.expect('R9 Verlaufseintrag der Serie für Admin unsichtbar',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select count(*)::text from public.series_deletions where series_id = %L$$, tests.get('r1'))), '0');
select tests.expect('R10 Erinnerungs-/Mitteilungsaufträge der Serie nur an den Ersteller',
  (select count(*)::text from public.notification_jobs j join public.tasks t on t.id = j.task_id
    where t.series_id = tests.get('r1')::uuid and j.user_id <> 'c3333333-3333-4333-8333-333333333333'::uuid), '0');

-- Familien-Serie bleibt von „privat“ unberührt
select tests.put('r2', tests.run_as('c1111111-1111-4111-8111-111111111111', format(
  $$select (public.create_recurring_task(%L, 'Gemeinsam täglich', 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[],
            'daily', (now() at time zone 'Europe/Berlin')::date)).id::text$$, tests.get('fa'))));
select tests.expect('R11 normale Serie: Ersteller (Admin) sieht sie weiter, nicht privat',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select count(*)::text from public.task_series where id = %L and not is_private$$, tests.get('r2'))), '1');

-- Austritt: Mia verlässt die Familie → ihre privaten Aufgaben und Serien verschwinden, gemeinsame bleiben
select tests.expect('X0 Vorher: Mias private Aufgaben und Serie vorhanden',
  ((select count(*) from public.tasks where is_private and created_by = 'c3333333-3333-4333-8333-333333333333'::uuid) >= 4)::text || '|'
  || (select count(*)::text from public.task_series where is_private and created_by = 'c3333333-3333-4333-8333-333333333333'::uuid), 'true|1');
select tests.run_as('c3333333-3333-4333-8333-333333333333', format($$select public.leave_family(%L) is not null$$, tests.get('fa')));
select tests.expect('X1 Nach dem Austritt: keine privaten Aufgaben und Serien von Mia mehr',
  (select count(*)::text from public.tasks where is_private and created_by = 'c3333333-3333-4333-8333-333333333333'::uuid) || '|'
  || (select count(*)::text from public.task_series where is_private and created_by = 'c3333333-3333-4333-8333-333333333333'::uuid) || '|'
  || (select count(*)::text from public.task_assignees where task_id = tests.get('p1')::uuid) || '|'
  || (select count(*)::text from public.task_image_links where task_id = tests.get('p1')::uuid), '0|0|0|0');
select tests.expect('X2 Gemeinsame Aufgabe von Mia bleibt', (select count(*)::text from public.tasks where id = tests.get('s1')::uuid), '1');

-- Kontolöschung: private Aufgaben von Nina in Familie A verschwinden mit dem Konto
select tests.put('p3', tests.run_as('c5555555-5555-4555-8555-555555555555', format(
  $$select (public.create_task(%L, 'Ninas Geheimnis', 'any_one', array['c5555555-5555-4555-8555-555555555555']::uuid[],
            null, null, null, 'Europe/Berlin', '[]'::jsonb, true)).id::text$$, tests.get('fa'))));
select tests.expect('K0 Vorher vorhanden', (select count(*)::text from public.tasks where id = tests.get('p3')::uuid), '1');
delete from auth.users where id = 'c5555555-5555-4555-8555-555555555555'::uuid;
select tests.expect('K1 Konto gelöscht: private Aufgabe weg (nicht nur ohne Ersteller zurückgeblieben)',
  (select count(*)::text from public.tasks where id = tests.get('p3')::uuid)
  || '|' || (select count(*)::text from public.tasks where is_private and created_by is null), '0|0');

-- Alte App-Version: Aufruf ohne p_private legt eine normale Aufgabe an
select tests.expect('A1 Aufruf ohne p_private (alte App) legt eine normale Aufgabe an',
  tests.run_as('c1111111-1111-4111-8111-111111111111', format($$select (public.create_task(%L, 'Alt', 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[])).is_private::text$$, tests.get('fa'))), 'false');

do $$
begin
  raise exception E'ERGEBNIS gesamt=% bestanden=%\n%',
    (select count(*) from tests.results),
    (select count(*) from tests.results where passed),
    coalesce((select string_agg(name || ' :: ' || coalesce(info, ''), E'\n' order by id)
              from tests.results where not passed), 'alle grün');
end;
$$;

rollback;
