-- 0010_rotation_nudges
-- Tests für Migration 0018: Reihum-Serien (Reihenfolge, Wochen, Ändern ab Termin, Regeländerung,
-- Austritt, Sichtbarkeit), gesammelte Mitteilungen, Anstupsen, Bereinigung, Prüf-Zugang, Kontolöschung.

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
    when 'lena'  then 'c5555555-5555-4555-8555-555555555555'
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

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  (tests.u('max'),  'max@example.test',  '{"full_name": "Max"}',  '{}', 'authenticated', 'authenticated'),
  (tests.u('lena'), 'lena@example.test', '{"full_name": "Lena"}', '{}', 'authenticated', 'authenticated');

select tests.put('f', tests.run_as(tests.u('clara'), $$select (public.create_family('Familie F', '#5EC2F2')).id$$));
select tests.put('code', tests.run_as(tests.u('clara'), format($$select (public.create_invite(%L)).code$$, tests.id('f'))));
select tests.run_as(tests.u('mia'), format($$select public.join_family(%L) ->> 'status'$$, tests.get('code')));
select tests.put('code2', tests.run_as(tests.u('clara'), format($$select (public.create_invite(%L)).code$$, tests.id('f'))));
select tests.run_as(tests.u('otto'), format($$select public.join_family(%L) ->> 'status'$$, tests.get('code2')));

-- Wer ist bei einem Vorkommen zugewiesen (Namen sortiert, als Eigentümer).
create function tests.who(p_series uuid, p_offset integer) returns text
language sql stable as $$
  select coalesce(string_agg(p.display_name, ',' order by p.display_name), '–')
  from public.tasks t join public.task_assignees a on a.task_id = t.id join public.profiles p on p.id = a.user_id
  where t.series_id = p_series and t.occurrence_date = tests.d(p_offset);
$$;
grant all on all functions in schema tests to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Reihum: Anlegen
-- ---------------------------------------------------------------------------

select tests.put('s', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Müll rausbringen', 'each', array[%L, %L, %L]::uuid[], 'weekly', %L,
            p_weekdays => array[%s]::smallint[], p_assignment_mode => 'rotate')).id$$,
  tests.id('f'), tests.u('mia'), tests.u('otto'), tests.u('clara'), tests.d(0), tests.dow(0))));
select tests.expect('W1 Reihum heute: erste Person der Liste', tests.who(tests.id('s'), 0), 'Mia');
select tests.expect('W2 Reihum nächste Woche: zweite Person', tests.who(tests.id('s'), 7), 'Otto');
select tests.expect('W3 Reihum erzwingt „eine Person“',
  (select completion_mode::text from public.task_series where id = tests.id('s')), 'any_one');
select tests.expect('W4 Reihenfolge gespeichert',
  (select string_agg(p.display_name, ',' order by a.position) from public.series_assignees a
     join public.profiles p on p.id = a.user_id where a.series_id = tests.id('s')), 'Mia,Otto,Clara');
select tests.expect('W5 dritter und vierter Termin: Clara, dann wieder Mia',
  (select private.rotation_index(s, tests.d(14))::text || ',' || private.rotation_index(s, tests.d(21))::text
     || ',' || (select display_name from public.profiles where id = private.rotation_assignee(s, tests.d(14)))
     || ',' || (select display_name from public.profiles where id = private.rotation_assignee(s, tests.d(21)))
   from public.task_series s where s.id = tests.id('s')),
  '2,3,Clara,Mia');
select tests.expect('W5b Neue Serie: nur Mia (heute dran) bekommt „zugewiesen“, nicht die Erstellerin',
  (select string_agg(p.display_name, ',' order by p.display_name) from public.notification_jobs j
     join public.profiles p on p.id = j.user_id join public.tasks t on t.id = j.task_id
   where j.kind = 'assigned' and t.series_id = tests.id('s')), 'Mia');
select tests.expect('W6 Reihum mit nur einer Person abgelehnt',
  tests.run_as(tests.u('clara'), format(
    $$select (public.create_recurring_task(%L, 'Allein', 'any_one', array[%L]::uuid[], 'daily', %L,
              p_assignment_mode => 'rotate')).id$$, tests.id('f'), tests.u('mia'), tests.d(0))),
  'ERROR:rotation_needs_two');
select tests.expect('W7 Unbekannte Reihum-Einstellung abgelehnt',
  tests.run_as(tests.u('clara'), format(
    $$select (public.create_recurring_task(%L, 'X', 'any_one', array[%L, %L]::uuid[], 'daily', %L,
              p_assignment_mode => 'zufall')).id$$, tests.id('f'), tests.u('mia'), tests.u('otto'), tests.d(0))),
  'ERROR:invalid_rotation');

-- Wöchentlicher Wechsel bei täglicher Serie: Index zählt Wochen, nicht Termine.
select tests.put('sw', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Tisch decken', 'any_one', array[%L, %L]::uuid[], 'daily', %L,
            p_assignment_mode => 'rotate', p_rotation_unit => 'week')).id$$,
  tests.id('f'), tests.u('otto'), tests.u('mia'), tests.d(0))));
select tests.expect('W8 Wochenwechsel: gleiche Woche gleicher Index, Folgewoche +1',
  (select private.rotation_index(s, tests.d(0) - (extract(isodow from tests.d(0))::int - 1))::text || ','
       || private.rotation_index(s, tests.d(0) - (extract(isodow from tests.d(0))::int - 1) + 6)::text || ','
       || private.rotation_index(s, tests.d(0) - (extract(isodow from tests.d(0))::int - 1) + 7)::text
   from public.task_series s where s.id = tests.id('sw')),
  '0,0,1');
-- ---------------------------------------------------------------------------
-- Reihum: Ändern ab einem Termin
-- ---------------------------------------------------------------------------

select tests.put('t7', (select id::text from public.tasks where series_id = tests.id('s') and occurrence_date = tests.d(7)));
select tests.expect('W10 Ändern ab nächster Woche mit neuer Reihenfolge',
  tests.run_as(tests.u('clara'), format(
    $$select (public.update_series_from(%L, (select version from public.tasks where id = %L), 'Müll rausbringen', 'any_one',
              array[%L, %L, %L]::uuid[], 'weekly', %L, p_weekdays => array[%s]::smallint[],
              p_assignment_mode => 'rotate')).id is not null$$,
    tests.id('t7'), tests.id('t7'), tests.u('clara'), tests.u('mia'), tests.u('otto'), tests.d(7), tests.dow(7))),
  'true');
select tests.expect('W11 gewählter Termin bekommt die erste Person', tests.who(tests.id('s'), 7), 'Clara');
select tests.expect('W12 heutiger Termin bleibt unverändert', tests.who(tests.id('s'), 0), 'Mia');
select tests.expect('W13 rotation_start = gewählter Termin',
  (select (rotation_start = tests.d(7))::text from public.task_series where id = tests.id('s')), 'true');

select tests.expect('W13b Umstellen: neue Person des Termins (Clara = Erstellerin) bekommt nichts, Otto ist ausgetragen',
  (select count(*)::text from public.notification_jobs j
   where j.kind = 'assigned' and j.task_id = tests.id('t7')), '0');

-- Tauschen eines einzelnen Termins (Mia übernimmt): Mia wird benachrichtigt.
select tests.run_as(tests.u('clara'), format(
  $$select (public.update_task(%L, (select version from public.tasks where id = %L), 'Müll rausbringen', 'any_one',
            array[%L]::uuid[], p_start_date => %L)).id is not null$$,
  tests.id('t7'), tests.id('t7'), tests.u('mia'), tests.d(7)));
select tests.expect('W13c Tausch: Mia bekommt „zugewiesen“ für den getauschten Termin',
  (select count(*)::text from public.notification_jobs j
   where j.kind = 'assigned' and j.task_id = tests.id('t7') and j.user_id = tests.u('mia')), '1');

-- Zurück zu „gemeinsam“: alle drei am Termin.
select tests.put('w14', tests.run_as(tests.u('clara'), format(
    $$select (public.update_series_from(%L, (select version from public.tasks where id = %L), 'Müll rausbringen', 'any_one',
              array[%L, %L, %L]::uuid[], 'weekly', %L, p_weekdays => array[%s]::smallint[])).id is not null$$,
    tests.id('t7'), tests.id('t7'), tests.u('clara'), tests.u('mia'), tests.u('otto'), tests.d(7), tests.dow(7))));
-- Getrennte Anweisung: tests.who ist stable und sähe sonst den Stand vor der Änderung.
select tests.expect('W14 Wechsel zu „gemeinsam“ weist allen zu',
  tests.get('w14') || '|' || tests.who(tests.id('s'), 7), 'true|Clara,Mia,Otto');

-- ---------------------------------------------------------------------------
-- Reihum: Regeländerung, Start in der Vergangenheit
-- ---------------------------------------------------------------------------

-- Wöchentlich am Wochentag von morgen, Mia und Clara; dann ab dem ersten Termin auf einen anderen
-- Wochentag umgestellt: Der umgestellte Termin bleibt bei Mia, der nächste ist Clara (nicht wieder Mia).
select tests.put('sr', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Bad putzen', 'any_one', array[%L, %L]::uuid[], 'weekly', %L,
            p_weekdays => array[%s]::smallint[], p_assignment_mode => 'rotate')).id$$,
  tests.id('f'), tests.u('mia'), tests.u('clara'), tests.d(1), tests.dow(1))));
select tests.put('tr1', (select id::text from public.tasks where series_id = tests.id('sr') and occurrence_date = tests.d(1)));
select tests.run_as(tests.u('clara'), format(
  $$select (public.update_series_from(%L, (select version from public.tasks where id = %L), 'Bad putzen', 'any_one',
            array[%L, %L]::uuid[], 'weekly', %L, p_weekdays => array[%s]::smallint[],
            p_assignment_mode => 'rotate')).id is not null$$,
  tests.id('tr1'), tests.id('tr1'), tests.u('mia'), tests.u('clara'), tests.d(1), tests.dow(3)));
select tests.expect('W16 Regeländerung: kein Doppeldienst (umgestellter Termin Mia, dann Clara, dann Mia)',
  tests.who(tests.id('sr'), 1) || ',' ||
  (select (select display_name from public.profiles where id = private.rotation_assignee(s, tests.d(3))) || ','
       || (select display_name from public.profiles where id = private.rotation_assignee(s, tests.d(10)))
   from public.task_series s where s.id = tests.id('sr')),
  'Mia,Clara,Mia');

-- Startdatum vor einer Woche: Vergangenes entsteht nicht, die erste Person ist beim ersten echten Termin dran.
select tests.put('sp', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Fenster putzen', 'any_one', array[%L, %L]::uuid[], 'weekly', %L,
            p_weekdays => array[%s]::smallint[], p_assignment_mode => 'rotate')).id$$,
  tests.id('f'), tests.u('mia'), tests.u('clara'), tests.d(-7), tests.dow(0))));
select tests.expect('W17 Start in der Vergangenheit: heute Mia, nächste Woche Clara, Reihe beginnt heute',
  tests.who(tests.id('sp'), 0) || '|' || tests.who(tests.id('sp'), 7) || '|'
    || (select (rotation_start = tests.d(0))::text from public.task_series where id = tests.id('sp')),
  'Mia|Clara|true');

-- ---------------------------------------------------------------------------
-- Ändern ab einem Termin: eine Mitteilung je Person statt einer je Termin
-- ---------------------------------------------------------------------------

select tests.put('sb', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Blumen gießen', 'any_one', array[%L]::uuid[], 'daily', %L)).id$$,
  tests.id('f'), tests.u('mia'), tests.d(0))));
-- Drei überfällige, offene Termine nachbilden (wie nach drei Tagen ohne Abhaken).
update public.task_series set start_date = tests.d(-3), generated_until = null where id = tests.id('sb');
select private.generate_series_occurrences(tests.id('sb'));
select tests.put('tb3', (select id::text from public.tasks where series_id = tests.id('sb') and occurrence_date = tests.d(-3)));
select tests.expect('W18a fünf offene Termine (3 überfällig, heute, morgen)',
  tests.occ(tests.id('sb'), 'completed_at is null'), '5');
select tests.run_as(tests.u('clara'), format(
  $$select (public.update_series_from(%L, (select version from public.tasks where id = %L), 'Pflanzen gießen', 'any_one',
            array[%L, %L]::uuid[], 'daily', %L)).id is not null$$,
  tests.id('tb3'), tests.id('tb3'), tests.u('mia'), tests.u('otto'), tests.d(-3)));
select tests.expect('W18b Otto (neu) bekommt einmal „zugewiesen“, Mia einmal „geändert“',
  (select 'zugewiesen:' || count(*) filter (where j.kind = 'assigned' and j.user_id = tests.u('otto'))
       || '|geändert:' || count(*) filter (where j.kind = 'changed' and j.user_id = tests.u('mia'))
   from public.notification_jobs j join public.tasks t on t.id = j.task_id
   where t.series_id = tests.id('sb')),
  'zugewiesen:1|geändert:1');
select tests.expect('W18c alle fünf Termine an Mia und Otto',
  tests.occ(tests.id('sb'), $$completed_at is null and title = 'Pflanzen gießen'
    and (select count(*) from public.task_assignees a where a.task_id = t.id) = 2$$), '5');

-- ---------------------------------------------------------------------------
-- Austritt
-- ---------------------------------------------------------------------------

-- Täglich reihum Otto, Mia; Otto hat für heute eine laufende Live Activity.
select tests.put('sx', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Hund füttern', 'any_one', array[%L, %L]::uuid[], 'daily', %L,
            p_assignment_mode => 'rotate')).id$$,
  tests.id('f'), tests.u('otto'), tests.u('mia'), tests.d(0))));
select tests.put('tx0', (select id::text from public.tasks where series_id = tests.id('sx') and occurrence_date = tests.d(0)));
select tests.expect('W19a vor dem Austritt: heute Otto, morgen Mia',
  tests.who(tests.id('sx'), 0) || ',' || tests.who(tests.id('sx'), 1), 'Otto,Mia');
insert into public.devices (id, user_id, apns_token, apns_environment)
values ('d4444444-4444-4444-8444-444444444444', tests.u('otto'), repeat('ab', 32), 'sandbox');
insert into public.live_activities (task_id, user_id, device_id, activity_id, update_token)
values (tests.id('tx0'), tests.u('otto'), 'd4444444-4444-4444-8444-444444444444', 'otto-heute', repeat('cd', 32));

-- Austritt: Reihe rückt zusammen.
select tests.run_as(tests.u('otto'), format($$select public.leave_family(%L) is not null$$, tests.id('f')));
select tests.expect('W15 nach Austritt nur noch aktuelle Mitglieder in der Reihe',
  (select string_agg(coalesce((select display_name from public.profiles where id = private.rotation_assignee(s, tests.d(0) + 7 * i)), '–'), ',' order by i)
   from public.task_series s, generate_series(0, 3) as i
   where s.id = tests.id('sw')),
  (select string_agg(x, ',') from (values ('Mia'), ('Mia'), ('Mia'), ('Mia')) v(x)));
select tests.expect('W19b Austritt: Ottos Termin geht an Mia, ohne „zugewiesen“; seine Live Activity endet',
  tests.who(tests.id('sx'), 0) || '|' || tests.who(tests.id('sx'), 1) || '|'
    || (select count(*)::text from public.notification_jobs
         where kind = 'assigned' and task_id = tests.id('tx0') and user_id = tests.u('mia')) || '|'
    || (select count(*)::text from public.notification_jobs
         where kind = 'activity_end' and task_id = tests.id('tx0') and user_id = tests.u('otto')),
  'Mia|Mia|0|1');
select tests.expect('W19c Otto hat in der Familie keine offenen Zuweisungen und keine Serienplätze mehr',
  (select count(*)::text from public.task_assignees a join public.tasks t on t.id = a.task_id
    where a.user_id = tests.u('otto') and t.family_id = tests.id('f') and t.completed_at is null) || '|'
  || (select count(*)::text from public.series_assignees a join public.task_series s on s.id = a.series_id
    where a.user_id = tests.u('otto') and s.family_id = tests.id('f')),
  '0|0');
select tests.expect('W19d gemeinsame Serie: Otto ausgetragen, die anderen bleiben',
  tests.who(tests.id('sb'), 0), 'Mia');

-- ---------------------------------------------------------------------------
-- Anstupsen
-- ---------------------------------------------------------------------------

select tests.put('t0', (select id::text from public.tasks where series_id = tests.id('s') and occurrence_date = tests.d(0)));
select tests.expect('N1 Clara erinnert Mia',
  tests.run_as(tests.u('clara'), format($$select (public.nudge_task(%L, %L) ->> 'scheduled_for') is not null$$,
    tests.id('t0'), tests.u('mia'))), 'true');
select tests.expect('N2 Auftrag „nudge“ für Mia mit Clara als Absenderin',
  (select count(*)::text from public.notification_jobs
    where kind = 'nudge' and task_id = tests.id('t0') and user_id = tests.u('mia') and actor_id = tests.u('clara')
      and scheduled_for >= now() - interval '1 minute'), '1');
select tests.expect('N3 innerhalb einer Stunde nicht erneut',
  tests.run_as(tests.u('clara'), format($$select public.nudge_task(%L, %L)::text$$, tests.id('t0'), tests.u('mia'))),
  'ERROR:nudge_too_soon');
select tests.expect('N4 nicht sich selbst',
  tests.run_as(tests.u('mia'), format($$select public.nudge_task(%L, %L)::text$$, tests.id('t0'), tests.u('mia'))),
  'ERROR:nudge_self');
select tests.expect('N5 nicht Nicht-Mitglieder',
  tests.run_as(tests.u('max'), format($$select public.nudge_task(%L, %L)::text$$, tests.id('t0'), tests.u('mia'))),
  'ERROR:task_not_found');
select tests.run_as(tests.u('mia'), format($$select (public.complete_task(%L)).id is not null$$, tests.id('t0')));
select tests.expect('N6 erledigte Aufgabe: nicht mehr erinnern',
  tests.run_as(tests.u('clara'), format($$select public.nudge_task(%L, %L)::text$$, tests.id('t0'), tests.u('otto'))),
  'ERROR:nudge_not_open');
select tests.expect('N7 Ruhezeit: Zustellung frühestens jetzt, nachts erst 7 Uhr',
  (select (case when extract(hour from now() at time zone 'Europe/Berlin') >= 21
                  or extract(hour from now() at time zone 'Europe/Berlin') < 7
             then extract(hour from scheduled_for at time zone 'Europe/Berlin') = 7
             else scheduled_for <= now() end)::text
   from public.notification_jobs where kind = 'nudge' and task_id = tests.id('t0') limit 1), 'true');
select tests.expect('N8 Clients sehen keine Anstups-Einträge',
  tests.run_as(tests.u('clara'), $$select count(*)::text from private.task_nudges$$), 'ERROR:42501');
select tests.expect('N9 Ausgetretene nicht erinnern',
  tests.run_as(tests.u('clara'), format($$select public.nudge_task(%L, %L)::text$$,
    (select id from public.tasks where series_id = tests.id('sx') and occurrence_date = tests.d(1)), tests.u('otto'))),
  'ERROR:member_not_found');

-- ---------------------------------------------------------------------------
-- Sichtbarkeit: Reihum in Familien mit „nur Zugewiesene“
-- ---------------------------------------------------------------------------

select tests.put('g', tests.run_as(tests.u('clara'), $$select (public.create_family('Familie G', '#8FD19E')).id$$));
select tests.run_as(tests.u('clara'), format($$select (public.update_family(%L, null, null, 'assigned_only')).id$$, tests.id('g')));
select tests.put('gcode', tests.run_as(tests.u('clara'), format($$select (public.create_invite(%L)).code$$, tests.id('g'))));
select tests.run_as(tests.u('mia'), format($$select public.join_family(%L) ->> 'status'$$, tests.get('gcode')));
select tests.put('gcode2', tests.run_as(tests.u('clara'), format($$select (public.create_invite(%L)).code$$, tests.id('g'))));
select tests.run_as(tests.u('max'), format($$select public.join_family(%L) ->> 'status'$$, tests.get('gcode2')));
select tests.put('sv', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Spülmaschine', 'any_one', array[%L, %L]::uuid[], 'daily', %L,
            p_assignment_mode => 'rotate')).id$$,
  tests.id('g'), tests.u('mia'), tests.u('max'), tests.d(0))));
select tests.put('so', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Nur Mia', 'any_one', array[%L]::uuid[], 'daily', %L)).id$$,
  tests.id('g'), tests.u('mia'), tests.d(0))));
select tests.put('tv0', (select id::text from public.tasks where series_id = tests.id('sv') and occurrence_date = tests.d(0)));
select tests.expect('V1 Max sieht beide Reihum-Termine (auch Mias Termin heute)',
  tests.run_as(tests.u('max'), format($$select count(*)::text from public.tasks where series_id = %L$$, tests.id('sv'))), '2');
select tests.expect('V2 Max sieht die Serie ohne ihn nicht',
  tests.run_as(tests.u('max'), format($$select count(*)::text from public.tasks where series_id = %L$$, tests.id('so'))), '0');
select tests.expect('V3 Max sieht, wer heute dran ist',
  tests.run_as(tests.u('max'), format($$select count(*)::text from public.task_assignees where task_id = %L$$, tests.id('tv0'))), '1');
select tests.expect('V4 Max kann Mia an ihren Termin erinnern',
  tests.run_as(tests.u('max'), format($$select (public.nudge_task(%L, %L) ->> 'scheduled_for') is not null$$,
    tests.id('tv0'), tests.u('mia'))), 'true');
select tests.expect('V5 Max darf Mias Termin nicht für sie abhaken',
  tests.run_as(tests.u('max'), format($$select (public.complete_task(%L)).id::text$$, tests.id('tv0'))),
  'ERROR:not_allowed_to_complete');

-- ---------------------------------------------------------------------------
-- Zeitgesteuerte Mitteilungen nur an Mitglieder
-- ---------------------------------------------------------------------------

select tests.put('te', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Ohne Datum', 'any_one', array[%L]::uuid[])).id$$, tests.id('f'), tests.u('mia'))));
-- Veraltete Zuweisung an jemanden, der nicht (mehr) Mitglied ist.
insert into public.task_assignees (task_id, user_id, assigned_by) values (tests.id('te'), tests.u('max'), null);
select private.enqueue_due_notifications();
select tests.expect('E1 Live-Activity-Start nur für Mia, nicht für Nicht-Mitglied Max',
  (select count(*) filter (where user_id = tests.u('mia'))::text || '|' || count(*) filter (where user_id = tests.u('max'))::text
   from public.notification_jobs where kind = 'activity_start' and task_id = tests.id('te')),
  '1|0');

-- ---------------------------------------------------------------------------
-- Tägliche Bereinigung: Erinnern und Prüf-Zugang nach einem Tag
-- ---------------------------------------------------------------------------

insert into private.task_nudges (task_id, from_user, to_user, created_at)
values (tests.id('tv0'), tests.u('clara'), tests.u('mia'), now() - interval '2 days');
insert into private.review_sign_in_attempts (succeeded, created_at) values (false, now() - interval '2 days');
select private.purge_notifications();
select tests.expect('P1 alte Einträge gelöscht, frische bleiben',
  (select count(*) filter (where created_at < now() - interval '1 day')::text || '|'
       || count(*) filter (where created_at >= now() - interval '1 day')::text
   from private.task_nudges where task_id in (tests.id('t0'), tests.id('tv0'))) || '|'
  || (select count(*)::text from private.review_sign_in_attempts where created_at < now() - interval '1 day'),
  '0|2|0');

-- ---------------------------------------------------------------------------
-- Prüf-Zugang (Edge Function review-sign-in)
-- ---------------------------------------------------------------------------

select tests.expect('R1 Clients dürfen den Prüf-Zugang nicht zählen',
  tests.run_as(tests.u('clara'), $$select public.review_sign_in_begin()::text$$), 'ERROR:42501');
select tests.put('r_before', (select count(*)::text from private.review_sign_in_attempts
                               where not succeeded and created_at > now() - interval '1 hour'));
select tests.put('r1', public.review_sign_in_begin()::text);
select public.review_sign_in_succeeded(tests.get('r1')::bigint);
select tests.expect('R2 richtiger Code zählt nicht als Fehlversuch',
  (select count(*)::text from private.review_sign_in_attempts where not succeeded and created_at > now() - interval '1 hour'),
  tests.get('r_before'));
create function tests.review_begins(p_n integer) returns integer
language plpgsql as $$
declare v integer := 0;
begin
  for i in 1..p_n loop
    if public.review_sign_in_begin() is not null then v := v + 1; end if;
  end loop;
  return v;
end;
$$;
select tests.expect('R3 höchstens 10 Fehlversuche pro Stunde',
  tests.review_begins(12)::text, greatest(0, 10 - tests.get('r_before')::integer)::text);

-- ---------------------------------------------------------------------------
-- Kontolöschung trotz laufender Live Activity (Fremdschlüssel der Mitteilungs-Aufträge)
-- ---------------------------------------------------------------------------

select tests.put('lcode', tests.run_as(tests.u('clara'), format($$select (public.create_invite(%L)).code$$, tests.id('f'))));
select tests.run_as(tests.u('lena'), format($$select public.join_family(%L) ->> 'status'$$, tests.get('lcode')));
select tests.put('sl', tests.run_as(tests.u('clara'), format(
  $$select (public.create_recurring_task(%L, 'Katze füttern', 'any_one', array[%L, %L]::uuid[], 'daily', %L,
            p_assignment_mode => 'rotate')).id$$,
  tests.id('f'), tests.u('lena'), tests.u('mia'), tests.d(0))));
select tests.put('tl0', (select id::text from public.tasks where series_id = tests.id('sl') and occurrence_date = tests.d(0)));
insert into public.devices (id, user_id, apns_token, apns_environment)
values ('d5555555-5555-4555-8555-555555555555', tests.u('lena'), repeat('ef', 32), 'sandbox');
insert into public.live_activities (task_id, user_id, device_id, activity_id, update_token)
values (tests.id('tl0'), tests.u('lena'), 'd5555555-5555-4555-8555-555555555555', 'lena-heute', repeat('12', 32));
select tests.run_as(null, format($$select (public.prepare_account_deletion(%L) -> 'avatar_paths')::text$$, tests.u('lena')), 'owner');
select tests.expect('K1 Konto mit laufender Live Activity lässt sich löschen',
  tests.run_as(null, format($$with d as (delete from auth.users where id = %L returning 1) select count(*)::text from d$$,
    tests.u('lena')), 'owner'),
  '1');
select tests.expect('K2 nach der Löschung ist Mia heute dran',
  tests.who(tests.id('sl'), 0), 'Mia');

select
  (select count(*) from tests.results)                     as gesamt,
  (select count(*) from tests.results where passed)        as bestanden,
  (select count(*) from tests.results where not passed)    as fehlgeschlagen,
  coalesce((select string_agg(name || ' :: ' || coalesce(info, ''), E'\n' order by id)
              from tests.results where not passed), 'alle grün') as fehler,
  (select string_agg(case when passed then 'ok  ' else 'FAIL' end || ' ' || name, E'\n' order by id)
     from tests.results) as protokoll;

rollback;
