-- 0004_tasks_papierkorb
-- Tests für delete_task / restore_task (Migration 0007): weiches Löschen, Sichtbarkeit, Rechte.
-- Ausführung im Supabase-SQL-Editor, falls der MCP wegen „delete“ nach Bestätigung fragt.

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

select tests.put('f', tests.run_as(tests.u('clara'), $$select (public.create_family('Familie F', '#5EC2F2')).id$$));
select tests.put('code', tests.run_as(tests.u('clara'), format($$select (public.create_invite(%L)).code$$, tests.id('f'))));
select tests.run_as(tests.u('mia'), format($$select public.join_family(%L) ->> 'status'$$, tests.get('code')));
select tests.put('t', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Einkaufen', 'any_one', array[%L]::uuid[])).id$$, tests.id('f'), tests.u('mia'))));

select tests.expect('P1 [Otto] darf nicht löschen',
  tests.run_as(tests.u('otto'), format($$select (public.delete_task(%L)).id$$, tests.id('t'))), 'ERROR:task_not_found');
select tests.expect('P2 [Mia] löscht (jedes Mitglied mit Sicht)',
  tests.run_as(tests.u('mia'), format($$select ((public.delete_task(%L)).deleted_by)::text$$, tests.id('t'))), tests.u('mia')::text);
select tests.expect('P3 gelöschte Aufgabe bleibt für den Verlauf lesbar',
  tests.run_as(tests.u('clara'), format($$select count(*) from public.tasks where id = %L and deleted_at is not null$$, tests.id('t'))), '1');
select tests.expect('P4 gelöschte Aufgabe nicht abhakbar',
  tests.run_as(tests.u('mia'), format($$select (public.complete_task(%L)).id$$, tests.id('t'))), 'ERROR:task_closed');
select tests.expect('P5 erneutes Löschen idempotent',
  tests.run_as(tests.u('clara'), format($$select ((public.delete_task(%L)).deleted_by)::text$$, tests.id('t'))), tests.u('mia')::text);
select tests.expect('P6 [Clara] stellt wieder her',
  tests.run_as(tests.u('clara'), format($$select coalesce((public.restore_task(%L)).deleted_at::text, 'aktiv')$$, tests.id('t'))), 'aktiv');
select tests.expect('P7 Version zählt jede Änderung',
  (select version::text from public.tasks where id = tests.id('t')), '3');

select
  (select count(*) from tests.results)                     as gesamt,
  (select count(*) from tests.results where passed)        as bestanden,
  (select count(*) from tests.results where not passed)    as fehlgeschlagen,
  coalesce((select string_agg(name || ' :: ' || coalesce(info, ''), E'\n' order by id)
              from tests.results where not passed), 'alle grün') as fehler,
  (select string_agg(case when passed then 'ok  ' else 'FAIL' end || ' ' || name, E'\n' order by id)
     from tests.results) as protokoll;

rollback;
