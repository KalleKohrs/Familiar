-- 0011_clear_history
-- Tests für Migration 0019: Verlauf leeren (nur Admins, nur eigene Familien, endgültig).
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

-- Familie A: Clara Admin, Mia Mitglied. Familie B: Mia Admin, Clara Mitglied.
select tests.put('fa', run.v) from (select tests.run_as('c1111111-1111-4111-8111-111111111111',
  $$select (public.create_family('A', '#5EC2F2')).id$$) as v) run;
select tests.put('ca', tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.create_invite(%L)).code$$, tests.get('fa'))));
select tests.run_as('c3333333-3333-4333-8333-333333333333',
  format($$select public.join_family(%L) ->> 'status'$$, tests.get('ca')));
select tests.put('fb', tests.run_as('c3333333-3333-4333-8333-333333333333',
  $$select (public.create_family('B', '#8FD19E')).id$$));
select tests.put('cb', tests.run_as('c3333333-3333-4333-8333-333333333333',
  format($$select (public.create_invite(%L)).code$$, tests.get('fb'))));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select public.join_family(%L) ->> 'status'$$, tests.get('cb')));

-- Je Familie: eine offene, eine erledigte und eine gelöschte Aufgabe.
select tests.put(x.f || x.n, tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.create_task(%L, %L, 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[])).id$$,
         tests.get(x.f), x.f || x.n)))
from (values ('fa', 'offen'), ('fa', 'erledigt'), ('fa', 'geloescht'),
             ('fb', 'offen'), ('fb', 'erledigt'), ('fb', 'geloescht')) as x(f, n);
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.complete_task(%L)).id::text$$, tests.get('faerledigt')));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.complete_task(%L)).id::text$$, tests.get('fberledigt')));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.delete_task(%L)).id::text$$, tests.get('fageloescht')));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.delete_task(%L)).id::text$$, tests.get('fbgeloescht')));

-- Gelöschte Serie in Familie A.
select tests.run_as('c1111111-1111-4111-8111-111111111111', format(
  $$select (public.create_recurring_task(%L, 'Serie', 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[],
            'daily', (now() at time zone 'Europe/Berlin')::date)).id::text$$, tests.get('fa')));
select tests.put('sat', (select id::text from public.tasks
  where family_id = tests.get('fa')::uuid and title = 'Serie' and series_id is not null order by occurrence_date limit 1));
select tests.put('sa', (select series_id::text from public.tasks where id = tests.get('sat')::uuid));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.delete_series(%L)).id::text$$, tests.get('sat')));

select tests.expect('H1 Vorher: Verlaufseintrag der Serie vorhanden',
  (select count(*)::text from public.series_deletions where family_id = tests.get('fa')::uuid), '1');

-- Clara ist nur in Familie A Admin: A wird geleert, B (Mitglied) bleibt.
select tests.expect('H2 Admin leert den Verlauf',
  (tests.run_as('c1111111-1111-4111-8111-111111111111', $$select public.clear_history()::text$$)::int > 0)::text, 'true');
select tests.expect('H3 Familie A: erledigt, gelöscht und Serie weg, offen bleibt',
  (select count(*)::text from public.tasks where family_id = tests.get('fa')::uuid
     and (completed_at is not null or deleted_at is not null)) || '|'
  || (select count(*)::text from public.tasks where family_id = tests.get('fa')::uuid and id = tests.get('faoffen')::uuid)
  || '|' || (select count(*)::text from public.series_deletions where family_id = tests.get('fa')::uuid)
  || '|' || (select count(*)::text from public.task_series where id = tests.get('sa')::uuid),
  '0|1|0|0');
select tests.expect('H3b Serie war vorhanden (Prüfung nicht leer)', (tests.get('sa') is not null)::text, 'true');
select tests.expect('H4 Familie B (nur Mitglied): Verlauf bleibt',
  (select count(*)::text from public.tasks where family_id = tests.get('fb')::uuid
     and (completed_at is not null or deleted_at is not null)), '2');
select tests.put('h5', tests.run_as('c3333333-3333-4333-8333-333333333333', $$select (public.clear_history() > 0)::text$$));
-- Getrennte Anweisung: sonst sähe die Zählung den Stand vor dem Leeren.
select tests.expect('H5 Mia (Admin von B) leert B',
  tests.get('h5') || '|' || (select count(*)::text from public.tasks where family_id = tests.get('fb')::uuid
        and (completed_at is not null or deleted_at is not null)), 'true|0');

-- Otto ist nur Mitglied (Familie A) und darf nichts leeren.
select tests.put('ca2', tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.create_invite(%L)).code$$, tests.get('fa'))));
select tests.run_as('c4444444-4444-4444-8444-444444444444',
  format($$select public.join_family(%L) ->> 'status'$$, tests.get('ca2')));
select tests.expect('H6 Mitglied ohne Admin-Recht abgelehnt',
  tests.run_as('c4444444-4444-4444-8444-444444444444', $$select public.clear_history()::text$$), 'ERROR:admin_required');

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
