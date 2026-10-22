-- 0010_rotation_nudges
-- Tests für Migration 0018: Reihum-Serien (Reihenfolge, Wochen, Ändern ab Termin, Austritt) und Anstupsen.

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

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  (tests.u('max'), 'max@example.test', '{"full_name": "Max"}', '{}', 'authenticated', 'authenticated');

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
select tests.expect('W14 Wechsel zu „gemeinsam“ weist allen zu',
  tests.run_as(tests.u('clara'), format(
    $$select (public.update_series_from(%L, (select version from public.tasks where id = %L), 'Müll rausbringen', 'any_one',
              array[%L, %L, %L]::uuid[], 'weekly', %L, p_weekdays => array[%s]::smallint[])).id is not null$$,
    tests.id('t7'), tests.id('t7'), tests.u('clara'), tests.u('mia'), tests.u('otto'), tests.d(7), tests.dow(7))) || '|'
    || tests.who(tests.id('s'), 7),
  'true|Clara,Mia,Otto');

-- Austritt: Reihe rückt zusammen.
select tests.run_as(tests.u('otto'), format($$select public.leave_family(%L) is not null$$, tests.id('f')));
select tests.expect('W15 nach Austritt nur noch aktuelle Mitglieder in der Reihe',
  (select string_agg(coalesce((select display_name from public.profiles where id = private.rotation_assignee(s, tests.d(0) + 7 * i)), '–'), ',' order by i)
   from public.task_series s, generate_series(0, 3) as i
   where s.id = tests.id('sw')),
  (select string_agg(x, ',') from (values ('Mia'), ('Mia'), ('Mia'), ('Mia')) v(x)));

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

select
  (select count(*) from tests.results)                     as gesamt,
  (select count(*) from tests.results where passed)        as bestanden,
  (select count(*) from tests.results where not passed)    as fehlgeschlagen,
  coalesce((select string_agg(name || ' :: ' || coalesce(info, ''), E'\n' order by id)
              from tests.results where not passed), 'alle grün') as fehler,
  (select string_agg(case when passed then 'ok  ' else 'FAIL' end || ' ' || name, E'\n' order by id)
     from tests.results) as protokoll;

rollback;
