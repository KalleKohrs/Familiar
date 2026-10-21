-- 0006_recurrence
-- Tests für Wiederholungen (Migration 0009): Regel, Erzeugung, Wasserstandsmarke, Sichtbarkeit,
-- „Nur dieses“ / „Dieses und zukünftige“, Serie löschen und wiederherstellen, Projektion.
-- Alle Daten relativ zu heute (Europe/Berlin), da die Erzeugung now() nutzt.

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

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  (tests.u('clara'), 'clara@example.test', '{"full_name": "Clara"}', '{}', 'authenticated', 'authenticated'),
  (tests.u('mia'),   'mia@example.test',   '{"full_name": "Mia"}',   '{}', 'authenticated', 'authenticated'),
  (tests.u('otto'),  'otto@example.test',  '{"full_name": "Otto"}',  '{}', 'authenticated', 'authenticated');

select set_config('tests.today', (now() at time zone 'Europe/Berlin')::date::text, true);
create function tests.d(p_offset integer) returns date
language sql stable as $$ select current_setting('tests.today')::date + p_offset; $$;
create function tests.dow(p_offset integer) returns smallint
language sql stable as $$ select extract(isodow from tests.d(p_offset))::smallint; $$;

-- Anzahl Vorkommen einer Serie (als Eigentümer, ohne RLS), optional gefiltert.
create function tests.occ(p_series uuid, p_where text default 'true') returns text
language plpgsql as $$
declare v text;
begin
  execute format('select count(*)::text from public.tasks t where t.series_id = %L and (%s)', p_series, p_where) into v;
  return v;
end;
$$;

grant all on all functions in schema tests to authenticated, anon;

select tests.put('f', tests.run_as(tests.u('clara'), $$select (public.create_family('Familie F', '#5EC2F2')).id$$));
select tests.put('code', tests.run_as(tests.u('clara'), format($$select (public.create_invite(%L)).code$$, tests.id('f'))));
select tests.run_as(tests.u('mia'), format($$select public.join_family(%L) ->> 'status'$$, tests.get('code')));

-- ---------------------------------------------------------------------------
-- Anlegen und Erzeugen
-- ---------------------------------------------------------------------------

select tests.put('s1', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Blumen gießen', 'any_one', array[%L]::uuid[], 'daily', %L,
            p_start_time => '18:00')).id$$,
  tests.id('f'), tests.u('mia'), tests.d(0))));
select tests.expect('R1 täglich ab heute: heute + nächstes künftiges Vorkommen',
  tests.occ(tests.id('s1')), '2');
select tests.expect('R2 Vorkommen heute und morgen',
  (select string_agg((occurrence_date - tests.d(0))::text, ',' order by occurrence_date)
     from public.tasks where series_id = tests.id('s1')), '0,1');
select tests.expect('R3 Vorkommen übernehmen Inhalt, Uhrzeit und Zuweisung',
  (select string_agg(distinct t.title || '|' || t.start_time::text || '|' || a.user_id::text, ';')
     from public.tasks t join public.task_assignees a on a.task_id = t.id where t.series_id = tests.id('s1')),
  'Blumen gießen|18:00:00|' || tests.u('mia')::text);
select tests.expect('R4 Erzeugung erneut: nichts doppelt (idempotent)',
  tests.run_as(null, $$select private.generate_all_series_occurrences()::text || '/' ||
    (select count(*) from public.tasks t where t.series_id is not null)::text$$, 'owner'), '0/2');

select tests.put('s2', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Zähne', 'each', array[%L, %L]::uuid[], 'weekly', %L,
            p_weekdays => array[1,2,3,4,5,6,7]::smallint[])).id$$,
  tests.id('f'), tests.u('mia'), tests.u('clara'), tests.d(-7))));
select tests.expect('R5 Startdatum in der Vergangenheit: kein Nachholen',
  (select string_agg((occurrence_date - tests.d(0))::text, ',' order by occurrence_date)
     from public.tasks where series_id = tests.id('s2')), '0,1');

select tests.put('s3', tests.run_as(tests.u('mia'), format(
  $$select (public.create_recurring_task(%L, 'Miete', 'any_one', array[%L]::uuid[], 'monthly', %L,
            p_month_days => array[%s, %s]::smallint[])).id$$,
  tests.id('f'), tests.u('clara'), tests.d(1), extract(day from tests.d(3)), extract(day from tests.d(5)))));
select tests.expect('R6 monatlich, Start in der Zukunft: genau ein künftiges Vorkommen',
  (select string_agg((occurrence_date - tests.d(0))::text, ',' order by occurrence_date)
     from public.tasks where series_id = tests.id('s3')), '3');

select tests.expect('R7 Wochentage fehlen',
  tests.run_as(tests.u('clara'), format(
    $$select (public.create_recurring_task(%L, 'X', 'any_one', array[%L]::uuid[], 'weekly', %L)).id$$,
    tests.id('f'), tests.u('mia'), tests.d(0))), 'ERROR:invalid_recurrence');
select tests.expect('R8 Startdatum fehlt',
  tests.run_as(tests.u('clara'), format(
    $$select (public.create_recurring_task(%L, 'X', 'any_one', array[%L]::uuid[], 'daily', null)).id$$,
    tests.id('f'), tests.u('mia'))), 'ERROR:recurrence_requires_date');
select tests.expect('R9 Monatstag 32 ungültig',
  tests.run_as(tests.u('clara'), format(
    $$select (public.create_recurring_task(%L, 'X', 'any_one', array[%L]::uuid[], 'monthly', %L,
              p_month_days => array[32]::smallint[])).id$$,
    tests.id('f'), tests.u('mia'), tests.d(0))), 'ERROR:invalid_recurrence');
select tests.expect('R10 Nicht-Mitglied kann keine Serie anlegen',
  tests.run_as(tests.u('otto'), format(
    $$select (public.create_recurring_task(%L, 'X', 'any_one', array[%L]::uuid[], 'daily', %L)).id$$,
    tests.id('f'), tests.u('mia'), tests.d(0))), 'ERROR:family_not_found');
select tests.expect('R11 Wochentage werden sortiert und entdoppelt',
  tests.run_as(tests.u('clara'), format(
    $$select (public.create_recurring_task(%L, 'Sport', 'any_one', array[%L]::uuid[], 'weekly', %L,
              p_weekdays => array[5,1,5]::smallint[])).weekdays::text$$,
    tests.id('f'), tests.u('mia'), tests.d(0))), '{1,5}');

-- ---------------------------------------------------------------------------
-- Sichtbarkeit
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  (tests.u('max'), 'max@example.test', '{"full_name": "Max"}', '{}', 'authenticated', 'authenticated');
select tests.run_as(tests.u('max'), format($$select public.join_family(%L) ->> 'status'$$, tests.get('code')));

select tests.expect('V1 [Otto] sieht keine Serien',
  tests.run_as(tests.u('otto'), $$select count(*) from public.task_series$$), '0');
select tests.expect('V2 [Max] sieht bei „alle“ alle Serien',
  tests.run_as(tests.u('max'), format($$select count(*) from public.task_series where family_id = %L$$, tests.id('f'))), '4');
select tests.run_as(tests.u('clara'), format($$select (public.update_family(%L, null, null, 'assigned_only')).task_visibility$$, tests.id('f')));
select tests.expect('V3 [Max] sieht bei „nur zugewiesene“ keine fremden Serien',
  tests.run_as(tests.u('max'), $$select count(*) from public.task_series$$), '0');
select tests.expect('V4 [Mia] sieht zugewiesene und eigene Serien',
  tests.run_as(tests.u('mia'), $$select count(*) from public.task_series$$), '4');
select tests.expect('V5 [Max] sieht keine Zuweisungen fremder Serien',
  tests.run_as(tests.u('max'), $$select count(*) from public.series_assignees$$), '0');
select tests.expect('V6 [Otto] Projektion leer',
  tests.run_as(tests.u('otto'), format($$select count(*) from public.project_series_occurrences(%L, %L)$$,
    tests.d(0), tests.d(30))), '0');
select tests.run_as(tests.u('clara'), format($$select (public.update_family(%L, null, null, 'all')).task_visibility$$, tests.id('f')));

-- ---------------------------------------------------------------------------
-- Projektion
-- ---------------------------------------------------------------------------

select tests.expect('P1 Projektion täglich: nur noch nicht erzeugte Tage (ab übermorgen)',
  tests.run_as(tests.u('mia'), format(
    $$select min(occurrence_date - %L::date)::text || '/' || count(*)::text
        from public.project_series_occurrences(%L, %L) where series_id = %L$$,
    tests.d(0), tests.d(0), tests.d(9), tests.id('s1'))), '2/8');
select tests.expect('P2 Zeitraum zu groß',
  tests.run_as(tests.u('mia'), format($$select count(*) from public.project_series_occurrences(%L, %L)$$,
    tests.d(0), tests.d(500))), 'ERROR:invalid_range');

-- ---------------------------------------------------------------------------
-- Bearbeiten
-- ---------------------------------------------------------------------------

select tests.put('s1_today', (select id::text from public.tasks where series_id = tests.id('s1') and occurrence_date = tests.d(0)));
select tests.put('s1_tomorrow', (select id::text from public.tasks where series_id = tests.id('s1') and occurrence_date = tests.d(1)));

select tests.expect('E1 „Nur dieses“: update_task koppelt das Vorkommen ab',
  tests.run_as(tests.u('mia'), format(
    $$select (public.update_task(%L, 1, 'Blumen gießen (Balkon)', 'any_one', array[%L]::uuid[],
              p_start_date => %L, p_start_time => '19:00')).is_detached::text$$,
    tests.id('s1_today'), tests.u('mia'), tests.d(0))), 'true');
select tests.expect('E2 Serie und morgiges Vorkommen bleiben unverändert',
  (select s.title || '|' || t.title from public.task_series s join public.tasks t on t.series_id = s.id
    where s.id = tests.id('s1') and t.id = tests.id('s1_tomorrow')), 'Blumen gießen|Blumen gießen');
select tests.expect('E3 update_series_from bei normaler Aufgabe',
  tests.run_as(tests.u('clara'), format(
    $$select (public.update_series_from(%L, 1, 'X', 'any_one', array[%L]::uuid[], 'daily', %L)).id$$,
    (select tests.put('plain', tests.run_as(tests.u('clara'), format(
      $q$select (public.create_task(%L, 'Einmalig', 'any_one', array[%L]::uuid[])).id$q$, tests.id('f'), tests.u('mia'))))),
    tests.u('mia'), tests.d(0))), 'ERROR:not_an_occurrence');

-- s2 (täglich über alle Wochentage, „each“, Mia + Clara): heute abhaken lassen (Mia), dann ab heute ändern.
select tests.put('s2_today', (select id::text from public.tasks where series_id = tests.id('s2') and occurrence_date = tests.d(0)));
select tests.put('s2_tomorrow', (select id::text from public.tasks where series_id = tests.id('s2') and occurrence_date = tests.d(1)));
select tests.run_as(tests.u('mia'), format($$select (public.complete_task(%L)).version$$, tests.id('s2_tomorrow')));
select tests.put('s2_tomorrow_v', (select version::text from public.tasks where id = tests.id('s2_tomorrow')));

select tests.expect('E4 „Dieses und zukünftige“ mit neuem Titel',
  tests.run_as(tests.u('clara'), format(
    $$select (public.update_series_from(%L, 1, 'Zähne putzen', 'each', array[%L, %L]::uuid[], 'weekly', %L,
              p_weekdays => array[1,2,3,4,5,6,7]::smallint[])).title$$,
    tests.id('s2_today'), tests.u('mia'), tests.u('clara'), tests.d(0))), 'Zähne putzen');
select tests.expect('E5 angefangenes Vorkommen (Mia hat schon abgehakt) bleibt unverändert',
  (select title || '|' || version::text from public.tasks where id = tests.id('s2_tomorrow')),
  'Zähne|' || tests.get('s2_tomorrow_v'));
select tests.expect('E6 Serie hat neuen Titel',
  (select title from public.task_series where id = tests.id('s2')), 'Zähne putzen');

-- Regel ändern: s1 ab heute (abgekoppelt → Fehler? nein: das gewählte Vorkommen darf abgekoppelt sein)
-- Wir nehmen s3 (monatlich, ein künftiges Vorkommen in 3 Tagen) und stellen auf wöchentlich am Wochentag in 6 Tagen um.
select tests.put('s3_occ', (select id::text from public.tasks where series_id = tests.id('s3')));
select tests.expect('E7 Regeländerung ab dem künftigen Vorkommen',
  tests.run_as(tests.u('mia'), format(
    $$select (public.update_series_from(%L, 1, 'Miete', 'any_one', array[%L]::uuid[], 'weekly', %L,
              p_weekdays => array[%s]::smallint[])).occurrence_date - %L::date$$,
    tests.id('s3_occ'), tests.u('clara'), tests.d(3), tests.dow(6), tests.d(0))), '3');
select tests.expect('E8 gewähltes Vorkommen bleibt, nichts doppelt',
  tests.occ(tests.id('s3')), '1');
select tests.expect('E9 Wasserstand = gewähltes Vorkommen; Regel ist wöchentlich',
  (select (generated_until - tests.d(0))::text || '|' || freq::text || '|' || weekdays::text
     from public.task_series where id = tests.id('s3')),
  '3|weekly|{' || tests.dow(6)::text || '}');

-- Regel ändern bei täglicher Serie s1 vom heutigen (abgekoppelten) Vorkommen aus: morgiges wird neu geplant.
select tests.expect('E10 Regeländerung täglich → wöchentlich (Tag in 3 Tagen)',
  tests.run_as(tests.u('clara'), format(
    $$select (public.update_series_from(%L, 2, 'Blumen gießen', 'any_one', array[%L]::uuid[], 'weekly', %L,
              p_weekdays => array[%s]::smallint[], p_start_time => '18:00')).title$$,
    tests.id('s1_today'), tests.u('mia'), tests.d(0), tests.dow(3))), 'Blumen gießen');
select tests.expect('E11 morgiges Vorkommen entfernt, neues in 3 Tagen',
  (select string_agg((occurrence_date - tests.d(0))::text, ',' order by occurrence_date)
     from public.tasks where series_id = tests.id('s1')), '0,3');

-- ---------------------------------------------------------------------------
-- Einzelnes Vorkommen löschen: wird nicht neu erzeugt (Wasserstandsmarke)
-- ---------------------------------------------------------------------------

select tests.run_as(tests.u('mia'), format($$select (public.delete_task(%L)).id$$,
  (select id from public.tasks where series_id = tests.id('s1') and occurrence_date = tests.d(3))));
select tests.run_as(null, $$select private.generate_all_series_occurrences()$$, 'owner');
select tests.expect('D1 gelöschtes Vorkommen kommt nicht wieder',
  tests.occ(tests.id('s1'), format('occurrence_date = %L', tests.d(3))) || '/' ||
  tests.occ(tests.id('s1'), format('occurrence_date = %L and deleted_at is null', tests.d(3))), '1/0');

-- ---------------------------------------------------------------------------
-- Serie löschen und wiederherstellen (s2: heute offen, morgen angefangen)
-- ---------------------------------------------------------------------------

select tests.run_as(tests.u('clara'), format($$select (public.complete_task(%L, 'all')).id$$, tests.id('s2_today')));
select tests.put('del', tests.run_as(tests.u('mia'), format($$select (public.delete_series(%L)).id$$, tests.id('s2_tomorrow'))));
select tests.expect('S1 Löschvorgang angelegt und sichtbar',
  tests.run_as(tests.u('clara'), format($$select count(*) from public.series_deletions where id = %L$$, tests.id('del'))), '1');
select tests.expect('S2 offene Vorkommen markiert, erledigtes bleibt',
  tests.occ(tests.id('s2'), format('deleted_by_series_op = %L', tests.id('del'))) || '/' ||
  tests.occ(tests.id('s2'), 'completed_at is not null and deleted_at is null'), '1/1');
select tests.expect('S3 erneutes Löschen idempotent',
  tests.run_as(tests.u('clara'), format($$select (public.delete_series(%L)).id::text$$, tests.id('s2_tomorrow'))), tests.get('del'));
select tests.expect('S4 Einzeln wiederherstellen nicht erlaubt',
  tests.run_as(tests.u('clara'), format($$select (public.restore_task(%L)).id$$, tests.id('s2_tomorrow'))), 'ERROR:restore_series_instead');
select tests.expect('S5 gelöschte Serie wird nicht weiter erzeugt',
  tests.run_as(null, format($$select private.generate_series_occurrences(%L)::text$$, tests.id('s2')), 'owner'), '0');
select tests.expect('S6 Bearbeiten „ab hier“ an gelöschter Serie',
  tests.run_as(tests.u('clara'), format(
    $$select (public.update_series_from(%L, 1, 'X', 'each', array[%L]::uuid[], 'daily', %L)).id$$,
    tests.id('s2_tomorrow'), tests.u('mia'), tests.d(1))), 'ERROR:task_closed');
select tests.expect('S7 [Otto] kann nicht wiederherstellen',
  tests.run_as(tests.u('otto'), format($$select (public.restore_series_deletion(%L)).id$$, tests.id('del'))),
  'ERROR:series_deletion_not_found');
select tests.expect('S8 [Clara] stellt die Serie wieder her',
  tests.run_as(tests.u('clara'), format($$select coalesce((public.restore_series_deletion(%L)).deleted_at::text, 'aktiv')$$,
    tests.id('del'))), 'aktiv');
select tests.expect('S9 Vorkommen wieder aktiv, Haken von Mia erhalten',
  (select (deleted_at is null)::text || '|' ||
          (select count(*) from public.task_assignees a where a.task_id = t.id and a.completed_at is not null)::text
     from public.tasks t where t.id = tests.id('s2_tomorrow')), 'true|1');
select tests.expect('S10 Eintrag als wiederhergestellt markiert, Erzeugung ab heute',
  (select (d.restored_by = tests.u('clara'))::text || '|' || (s.resume_from - tests.d(0))::text
     from public.series_deletions d join public.task_series s on s.id = d.series_id where d.id = tests.id('del')),
  'true|0');
select tests.expect('S11 nach Wiederherstellen nichts doppelt',
  tests.occ(tests.id('s2')), '2');

select
  (select count(*) from tests.results)                     as gesamt,
  (select count(*) from tests.results where passed)        as bestanden,
  (select count(*) from tests.results where not passed)    as fehlgeschlagen,
  coalesce((select string_agg(name || ' :: ' || coalesce(info, ''), E'\n' order by id)
              from tests.results where not passed), 'alle grün') as fehler,
  (select string_agg(case when passed then 'ok  ' else 'FAIL' end || ' ' || name, E'\n' order by id)
     from tests.results) as protokoll;

rollback;
