-- 0013_purge_history_entry
-- Tests für Migration 0022: einzelnen Verlaufseintrag endgültig löschen (Aufgabe, Serie, Rechte, private Aufgaben).
-- Läuft in begin … rollback; im SQL-Editor ausführen.

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
  ('c4444444-4444-4444-8444-444444444444', 'otto@example.test',  '{"full_name": "Otto"}',  '{}', 'authenticated', 'authenticated');

-- Familie A: Clara Admin, Mia Mitglied. Otto gehört nicht dazu.
select tests.put('fa', tests.run_as('c1111111-1111-4111-8111-111111111111',
  $$select (public.create_family('A', '#5EC2F2')).id$$));
select tests.put('ca', tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.create_invite(%L)).code$$, tests.get('fa'))));
select tests.run_as('c3333333-3333-4333-8333-333333333333',
  format($$select public.join_family(%L) ->> 'status'$$, tests.get('ca')));

-- Aufgaben: erledigt, gelöscht, offen (alle von Clara, Clara zugewiesen).
select tests.put(x.n, tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.create_task(%L, %L, 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[])).id$$,
         tests.get('fa'), x.n)))
from (values ('erledigt'), ('geloescht'), ('offen')) as x(n);
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.complete_task(%L)).id::text$$, tests.get('erledigt')));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.delete_task(%L)).id::text$$, tests.get('geloescht')));

select tests.expect('P1 Offene Aufgabe steht nicht im Verlauf: abgelehnt',
  tests.run_as('c1111111-1111-4111-8111-111111111111',
    format($$select public.purge_history_entry('task', %L)::text$$, tests.get('offen'))), 'ERROR:task_not_found');
select tests.expect('P2 Fremde Person (Otto) sieht die Aufgabe nicht: abgelehnt',
  tests.run_as('c4444444-4444-4444-8444-444444444444',
    format($$select public.purge_history_entry('task', %L)::text$$, tests.get('erledigt'))), 'ERROR:task_not_found');
select tests.expect('P3 Unbekannte Art abgelehnt',
  tests.run_as('c1111111-1111-4111-8111-111111111111',
    format($$select public.purge_history_entry('bla', %L)::text$$, tests.get('erledigt'))), 'ERROR:invalid_scope');

select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select public.purge_history_entry('task', %L)::text$$, tests.get('erledigt')));
select tests.expect('P4 Erledigte Aufgabe endgültig gelöscht, die anderen bleiben',
  (select count(*)::text from public.tasks where id = tests.get('erledigt')::uuid) || '|'
  || (select count(*)::text from public.tasks where id = tests.get('geloescht')::uuid) || '|'
  || (select count(*)::text from public.tasks where id = tests.get('offen')::uuid), '0|1|1');

-- Mia (Mitglied, darf laut Standard löschen) entfernt die gelöschte Aufgabe.
select tests.run_as('c3333333-3333-4333-8333-333333333333',
  format($$select public.purge_history_entry('task', %L)::text$$, tests.get('geloescht')));
select tests.expect('P5 Mitglied mit Recht löscht eine gelöschte Aufgabe endgültig',
  (select count(*)::text from public.tasks where id = tests.get('geloescht')::uuid), '0');

-- Serie: löschen, dann den Verlaufseintrag endgültig entfernen.
select tests.run_as('c1111111-1111-4111-8111-111111111111', format(
  $$select (public.create_recurring_task(%L, 'Serie', 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[],
            'daily', (now() at time zone 'Europe/Berlin')::date)).id::text$$, tests.get('fa')));
select tests.put('sat', (select id::text from public.tasks
  where family_id = tests.get('fa')::uuid and title = 'Serie' and series_id is not null order by occurrence_date limit 1));
select tests.put('sa', (select series_id::text from public.tasks where id = tests.get('sat')::uuid));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.delete_series(%L)).id::text$$, tests.get('sat')));
select tests.put('sd', (select id::text from public.series_deletions where series_id = tests.get('sa')::uuid));

select tests.expect('P6 Termin einer gelöschten Serie einzeln löschen: auf den Serien-Eintrag verwiesen',
  tests.run_as('c1111111-1111-4111-8111-111111111111',
    format($$select public.purge_history_entry('task', %L)::text$$, tests.get('sat'))), 'ERROR:restore_series_instead');
select tests.expect('P7 Fremde Person (Otto) kann den Serien-Eintrag nicht löschen',
  tests.run_as('c4444444-4444-4444-8444-444444444444',
    format($$select public.purge_history_entry('series', %L)::text$$, tests.get('sd'))), 'ERROR:series_deletion_not_found');
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select public.purge_history_entry('series', %L)::text$$, tests.get('sd')));
select tests.expect('P8 Serie, Eintrag und mitgelöschte Termine sind weg',
  (select count(*)::text from public.series_deletions where id = tests.get('sd')::uuid) || '|'
  || (select count(*)::text from public.task_series where id = tests.get('sa')::uuid) || '|'
  || (select count(*)::text from public.tasks where title = 'Serie' and family_id = tests.get('fa')::uuid), '0|0|0');

-- Private Aufgabe von Clara: nur sie darf sie sehen und endgültig löschen.
select tests.put('priv', tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.create_task(%L, 'Privat', 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[],
            p_private => true)).id$$, tests.get('fa'))));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.complete_task(%L)).id::text$$, tests.get('priv')));
select tests.expect('P9 Private Aufgabe: Mia sieht sie nicht, abgelehnt',
  tests.run_as('c3333333-3333-4333-8333-333333333333',
    format($$select public.purge_history_entry('task', %L)::text$$, tests.get('priv'))), 'ERROR:task_not_found');
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select public.purge_history_entry('task', %L)::text$$, tests.get('priv')));
select tests.expect('P10 Ersteller löscht seine private Aufgabe endgültig',
  (select count(*)::text from public.tasks where id = tests.get('priv')::uuid), '0');

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
