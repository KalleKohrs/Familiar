-- 0007_family_permissions
-- Tests für Migration 0010: Aufgabenrechte (E4), Familie löschen, Konto-Löschung vorbereiten.

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
select tests.put('solo', tests.run_as(tests.u('clara'), $$select (public.create_family('Nur Clara', '#FF7F66')).id$$));

select tests.expect('F1 Standard: Mitglied darf Aufgaben anlegen',
  tests.run_as(tests.u('mia'), format($$select (public.create_task(%L, 'Einkaufen', 'any_one', array[%L]::uuid[])).title$$,
    tests.id('f'), tests.u('mia'))), 'Einkaufen');
select tests.put('t', (select id::text from public.tasks where family_id = tests.id('f') and title = 'Einkaufen'));

select tests.expect('F2 Mitglied darf Rechte nicht ändern',
  tests.run_as(tests.u('mia'), format($$select (public.set_family_permissions(%L, p_members_can_create_tasks => false)).id$$,
    tests.id('f'))), 'ERROR:admin_required');
select tests.expect('F3 Admin schaltet Anlegen, Bearbeiten und Löschen für Mitglieder ab',
  tests.run_as(tests.u('clara'), format($$select (f.members_can_create_tasks or f.members_can_edit_tasks or f.members_can_delete_tasks)::text
      from public.set_family_permissions(%L, p_members_can_create_tasks => false, p_members_can_edit_tasks => false,
                                         p_members_can_delete_tasks => false) f$$, tests.id('f'))), 'false');
select tests.expect('F4 andere Schalter bleiben unverändert',
  (select (members_can_invite and members_can_manage_family and members_can_remove_members)::text
     from public.families where id = tests.id('f')), 'true');

select tests.expect('F5 Mitglied: Anlegen gesperrt',
  tests.run_as(tests.u('mia'), format($$select (public.create_task(%L, 'X', 'any_one', array[%L]::uuid[])).id$$,
    tests.id('f'), tests.u('mia'))), 'ERROR:permission_denied_create_tasks');
select tests.expect('F6 Mitglied: Serie anlegen gesperrt',
  tests.run_as(tests.u('mia'), format($$select (public.create_recurring_task(%L, 'X', 'any_one', array[%L]::uuid[], 'daily', current_date)).id$$,
    tests.id('f'), tests.u('mia'))), 'ERROR:permission_denied_create_tasks');
select tests.expect('F7 Mitglied: Bearbeiten gesperrt',
  tests.run_as(tests.u('mia'), format($$select (public.update_task(%L, 1, 'Y', 'any_one', array[%L]::uuid[])).id$$,
    tests.id('t'), tests.u('mia'))), 'ERROR:permission_denied_edit_tasks');
select tests.expect('F8 Mitglied: Löschen gesperrt',
  tests.run_as(tests.u('mia'), format($$select (public.delete_task(%L)).id$$, tests.id('t'))), 'ERROR:permission_denied_delete_tasks');
select tests.expect('F9 Mitglied darf weiterhin abhaken',
  tests.run_as(tests.u('mia'), format($$select ((public.complete_task(%L)).completed_at is not null)::text$$, tests.id('t'))), 'true');
select tests.expect('F10 Mitglied darf weiterhin Rückgängig (wieder öffnen)',
  tests.run_as(tests.u('mia'), format($$select ((public.uncomplete_task(%L, 'all')).completed_at is null)::text$$, tests.id('t'))), 'true');
select tests.expect('F11 Admin darf bearbeiten',
  tests.run_as(tests.u('clara'), format($$select (public.update_task(%L, 3, 'Großeinkauf', 'any_one', array[%L]::uuid[])).title$$,
    tests.id('t'), tests.u('mia'))), 'Großeinkauf');
select tests.expect('F12 Admin darf löschen',
  tests.run_as(tests.u('clara'), format($$select ((public.delete_task(%L)).deleted_at is not null)::text$$, tests.id('t'))), 'true');
select tests.expect('F13 Mitglied: Wiederherstellen gesperrt',
  tests.run_as(tests.u('mia'), format($$select (public.restore_task(%L)).id$$, tests.id('t'))), 'ERROR:permission_denied_delete_tasks');
select tests.expect('F14 Admin darf wiederherstellen',
  tests.run_as(tests.u('clara'), format($$select ((public.restore_task(%L)).deleted_at is null)::text$$, tests.id('t'))), 'true');
select tests.expect('F15 Nicht-Mitglied: weiterhin unsichtbar',
  tests.run_as(tests.u('otto'), format($$select (public.update_task(%L, 1, 'Z', 'any_one', array[%L]::uuid[])).id$$,
    tests.id('t'), tests.u('mia'))), 'ERROR:task_not_found');

-- Familie löschen
select tests.expect('L1 Mitglied darf Familie nicht löschen',
  tests.run_as(tests.u('mia'), format($$select 'ok' from (select public.delete_family(%L)) as x$$, tests.id('f'))), 'ERROR:admin_required');

-- Konto löschen vorbereiten
select tests.expect('K1 Clients dürfen prepare_account_deletion nicht aufrufen',
  tests.run_as(tests.u('clara'), format($$select public.prepare_account_deletion(%L)::text$$, tests.u('clara'))), 'ERROR:42501');
select tests.expect('K2 Vorbereitung liefert die Profilbild-Pfade',
  tests.run_as(null, format($$select (public.prepare_account_deletion(%L) -> 'avatar_paths')::text$$, tests.u('clara')), 'owner'), '[]');
select tests.expect('K3 Familie, in der Clara allein war, ist weg',
  (select count(*)::text from public.families where id = tests.id('solo')), '0');
select tests.expect('K4 Mia wird Admin der gemeinsamen Familie',
  (select role::text from public.family_members where family_id = tests.id('f') and user_id = tests.u('mia')), 'admin');
select tests.expect('K5 gemeinsame Familie und Aufgabe bleiben',
  (select count(*)::text from public.tasks where family_id = tests.id('f')), '1');

select tests.expect('L2 Admin (jetzt Mia) löscht die Familie samt Aufgaben',
  tests.run_as(tests.u('mia'), format($$select 'ok' from (select public.delete_family(%L)) as x$$, tests.id('f'))) || '/' ||
  (select count(*)::text from public.tasks where family_id = tests.id('f')), 'ok/0');

select
  (select count(*) from tests.results) as gesamt,
  (select count(*) from tests.results where passed) as bestanden,
  coalesce((select string_agg(name || ' :: ' || coalesce(info, ''), E'\n' order by id)
              from tests.results where not passed), 'alle grün') as fehler;

rollback;
