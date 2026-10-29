-- 0011_clear_history
-- Tests für Migration 0019: Verlauf leeren (nur Admins, nur eigene Familien, endgültig).
-- Läuft in begin … rollback; im SQL-Editor ausführen.

begin;

create schema tests;
create table tests.results (id serial primary key, name text not null, passed boolean not null, info text);

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
select set_config('tests.fa', run.v, true) from (select tests.run_as('c1111111-1111-4111-8111-111111111111',
  $$select (public.create_family('A', '#5EC2F2')).id$$) as v) run;
select set_config('tests.ca', tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.create_invite(%L)).code$$, current_setting('tests.fa'))), true);
select tests.run_as('c3333333-3333-4333-8333-333333333333',
  format($$select public.join_family(%L) ->> 'status'$$, current_setting('tests.ca')));
select set_config('tests.fb', tests.run_as('c3333333-3333-4333-8333-333333333333',
  $$select (public.create_family('B', '#8FD19E')).id$$), true);
select set_config('tests.cb', tests.run_as('c3333333-3333-4333-8333-333333333333',
  format($$select (public.create_invite(%L)).code$$, current_setting('tests.fb'))), true);
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select public.join_family(%L) ->> 'status'$$, current_setting('tests.cb')));

-- Je Familie: eine offene, eine erledigte und eine gelöschte Aufgabe.
select set_config('tests.' || x.f || x.n, tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.create_task(%L, %L, 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[])).id$$,
         current_setting('tests.' || x.f), x.f || x.n)), true)
from (values ('fa', 'offen'), ('fa', 'erledigt'), ('fa', 'geloescht'),
             ('fb', 'offen'), ('fb', 'erledigt'), ('fb', 'geloescht')) as x(f, n);
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.complete_task(%L)).id::text$$, current_setting('tests.faerledigt')));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.complete_task(%L)).id::text$$, current_setting('tests.fberledigt')));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.delete_task(%L)).id::text$$, current_setting('tests.fageloescht')));
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.delete_task(%L)).id::text$$, current_setting('tests.fbgeloescht')));

-- Gelöschte Serie in Familie A.
select set_config('tests.sat', tests.run_as('c1111111-1111-4111-8111-111111111111', format(
  $$select (public.create_recurring_task(%L, 'Serie', 'any_one', array['c1111111-1111-4111-8111-111111111111']::uuid[],
            'daily', (now() at time zone 'Europe/Berlin')::date)).id$$, current_setting('tests.fa'))), true);
select set_config('tests.sa', (select series_id::text from public.tasks where id = current_setting('tests.sat')::uuid), true);
select tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.delete_series(%L)).id::text$$, current_setting('tests.sat')));

select tests.expect('H1 Vorher: Verlaufseintrag der Serie vorhanden',
  (select count(*)::text from public.series_deletions where family_id = current_setting('tests.fa')::uuid), '1');

-- Clara ist nur in Familie A Admin: A wird geleert, B (Mitglied) bleibt.
select tests.expect('H2 Admin leert den Verlauf',
  (tests.run_as('c1111111-1111-4111-8111-111111111111', $$select public.clear_history()::text$$)::int > 0)::text, 'true');
select tests.expect('H3 Familie A: erledigt, gelöscht und Serie weg, offen bleibt',
  (select count(*)::text from public.tasks where family_id = current_setting('tests.fa')::uuid
     and (completed_at is not null or deleted_at is not null)) || '|'
  || (select count(*)::text from public.tasks where family_id = current_setting('tests.fa')::uuid and id = current_setting('tests.faoffen')::uuid)
  || '|' || (select count(*)::text from public.series_deletions where family_id = current_setting('tests.fa')::uuid)
  || '|' || (select count(*)::text from public.task_series where id = current_setting('tests.sa')::uuid),
  '0|1|0|0');
select tests.expect('H4 Familie B (nur Mitglied): Verlauf bleibt',
  (select count(*)::text from public.tasks where family_id = current_setting('tests.fb')::uuid
     and (completed_at is not null or deleted_at is not null)), '2');
select tests.expect('H5 Mia (Admin von B) leert B',
  tests.run_as('c3333333-3333-4333-8333-333333333333', $$select (public.clear_history() > 0)::text$$) || '|'
  || (select count(*)::text from public.tasks where family_id = current_setting('tests.fb')::uuid
        and (completed_at is not null or deleted_at is not null)), 'true|0');

-- Otto ist nur Mitglied (Familie A) und darf nichts leeren.
select set_config('tests.ca2', tests.run_as('c1111111-1111-4111-8111-111111111111',
  format($$select (public.create_invite(%L)).code$$, current_setting('tests.fa'))), true);
select tests.run_as('c4444444-4444-4444-8444-444444444444',
  format($$select public.join_family(%L) ->> 'status'$$, current_setting('tests.ca2')));
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
