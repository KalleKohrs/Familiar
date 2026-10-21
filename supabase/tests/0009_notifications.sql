-- 0009_notifications
-- Tests für Migration 0012: Mitteilungs-Aufträge, Geräte, Live Activities, push-dispatch-RPCs.

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

create function tests.jobs(p_task uuid, p_kind text) returns text
language sql stable as $$
  select coalesce(string_agg(p.display_name, ',' order by p.display_name), '-')
  from public.notification_jobs j join public.profiles p on p.id = j.user_id
  where j.task_id = p_task and j.kind::text = p_kind;
$$;

-- Ereignisse ---------------------------------------------------------------

select tests.put('t', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Einkaufen', 'any_one', array[%L, %L]::uuid[])).id$$,
  tests.id('f'), tests.u('clara'), tests.u('mia'))));
select tests.expect('E1 Zuweisung meldet nur Mia, nicht die Erstellerin selbst',
  tests.jobs(tests.id('t'), 'assigned'), 'Mia');

select tests.run_as(tests.u('clara'), format(
  $$select (public.update_task(%L, 1, 'Einkaufen gehen', 'any_one', array[%L, %L]::uuid[], 'Milch')).version$$,
  tests.id('t'), tests.u('clara'), tests.u('mia')));
select tests.expect('E2 Titeländerung meldet Mia, nicht Clara',
  tests.jobs(tests.id('t'), 'changed'), 'Mia');
select tests.run_as(tests.u('clara'), format(
  $$select (public.update_task(%L, 2, 'Einkaufen gehen', 'any_one', array[%L, %L]::uuid[], 'Milch und Brot')).version$$,
  tests.id('t'), tests.u('clara'), tests.u('mia')));
select tests.expect('E3 Nur Beschreibung geändert: keine weitere Meldung (E6)',
  (select count(*)::text from public.notification_jobs where task_id = tests.id('t') and kind = 'changed'), '1');

select tests.run_as(tests.u('mia'), format($$select (public.complete_task(%L)).id$$, tests.id('t')));
select tests.expect('E4 Erledigt meldet Clara, nicht Mia (hat selbst abgehakt)',
  tests.jobs(tests.id('t'), 'completed'), 'Clara');

select tests.put('t2', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Müll', 'any_one', array[%L]::uuid[])).id$$, tests.id('f'), tests.u('mia'))));
select tests.run_as(tests.u('clara'), format($$select 'ok' from (select public.delete_task(%L)) x$$, tests.id('t2')));
select tests.expect('E5 Löschen meldet Mia',
  tests.jobs(tests.id('t2'), 'deleted'), 'Mia');

-- Zeitgesteuert ------------------------------------------------------------

-- Start in 3 Minuten (Berliner Zeit)
select tests.put('soon', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Bald', 'any_one', array[%L]::uuid[], null, %L::date, %L::time)).id$$,
  tests.id('f'), tests.u('mia'),
  ((now() + interval '3 minutes') at time zone 'Europe/Berlin')::date,
  ((now() + interval '3 minutes') at time zone 'Europe/Berlin')::time)));
-- Start vor 30 Minuten
select tests.put('now', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Läuft', 'any_one', array[%L]::uuid[], null, %L::date, %L::time)).id$$,
  tests.id('f'), tests.u('mia'),
  ((now() - interval '30 minutes') at time zone 'Europe/Berlin')::date,
  ((now() - interval '30 minutes') at time zone 'Europe/Berlin')::time)));
-- Start vor 70 Minuten
select tests.put('late', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Verpasst', 'any_one', array[%L]::uuid[], null, %L::date, %L::time)).id$$,
  tests.id('f'), tests.u('mia'),
  ((now() - interval '70 minutes') at time zone 'Europe/Berlin')::date,
  ((now() - interval '70 minutes') at time zone 'Europe/Berlin')::time)));
-- Nur Datum: heute
select tests.put('today', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Heute irgendwann', 'any_one', array[%L]::uuid[], null, %L::date)).id$$,
  tests.id('f'), tests.u('mia'), (now() at time zone 'Europe/Berlin')::date)));
-- Nur Datum: in 3 Tagen
select tests.put('later', tests.run_as(tests.u('clara'), format(
  $$select (public.create_task(%L, 'Später', 'any_one', array[%L]::uuid[], null, %L::date)).id$$,
  tests.id('f'), tests.u('mia'), (now() at time zone 'Europe/Berlin')::date + 3)));

select private.enqueue_due_notifications();

select tests.expect('Z1 5 Minuten vorher: Live Activity, aber noch kein „Jetzt“',
  tests.jobs(tests.id('soon'), 'activity_start') || '/' || tests.jobs(tests.id('soon'), 'started'), 'Mia/-');
select tests.expect('Z2 Läuft seit 30 min: Live Activity und „Jetzt“, noch keine Erinnerung',
  tests.jobs(tests.id('now'), 'activity_start') || '/' || tests.jobs(tests.id('now'), 'started') || '/' || tests.jobs(tests.id('now'), 'reminder'),
  'Mia/Mia/-');
select tests.expect('Z3 Seit 70 min: erste Erinnerung (1 h), kein verspätetes „Jetzt“',
  tests.jobs(tests.id('late'), 'reminder') || '/' || tests.jobs(tests.id('late'), 'started'), 'Mia/-');
select tests.expect('Z4 Nur Datum heute: Live Activity + „Jetzt“ (08:00 bzw. ab Zuweisung, E3)',
  tests.jobs(tests.id('today'), 'activity_start') || '/' || tests.jobs(tests.id('today'), 'started'), 'Mia/Mia');
select tests.expect('Z5 Nur Datum in 3 Tagen: noch nichts',
  (select count(*)::text from public.notification_jobs where task_id = tests.id('later') and kind <> 'assigned'), '0');
select tests.put('n_jobs', (select count(*)::text from public.notification_jobs));
select private.enqueue_due_notifications();
select tests.expect('Z6 Zweiter Lauf legt nichts doppelt an',
  (select count(*)::text from public.notification_jobs), tests.get('n_jobs'));

-- Geräte und Live Activities ------------------------------------------------

select tests.expect('G1 Ungültiges Token wird abgelehnt',
  tests.run_as(tests.u('mia'), $$select public.register_device('kein-token', 'sandbox')::text$$), 'ERROR:invalid_device_token');
select tests.put('dev', tests.run_as(tests.u('mia'),
  $$select public.register_device(repeat('ab', 32), 'sandbox', 'pts-mia', '1.0', 'Europe/Berlin')::text$$));
select tests.expect('G2 Mia sieht ihr Gerät, Clara nicht',
  tests.run_as(tests.u('mia'), $$select count(*)::text from public.devices$$) || '/' ||
  tests.run_as(tests.u('clara'), $$select count(*)::text from public.devices$$), '1/0');
select tests.expect('G3 Clients schreiben Geräte nicht direkt',
  tests.run_as(tests.u('mia'), $$update public.devices set invalidated_at = now() returning 'x'$$), 'ERROR:42501');
select tests.expect('G4 Clients lesen keine Aufträge',
  tests.run_as(tests.u('mia'), $$select count(*)::text from public.notification_jobs$$), 'ERROR:42501');
select tests.expect('G5 Otto (kein Mitglied) kann keine Live Activity für die Aufgabe melden',
  tests.run_as(tests.u('otto'), format($$select 'ok' from (select public.register_live_activity(%L, %L, 'act-x', 'upd-x')) x$$,
    tests.id('now'), repeat('ab', 32))), 'ERROR:task_not_found');
select tests.expect('G6 Mia meldet ihre Live Activity',
  tests.run_as(tests.u('mia'), format($$select 'ok' from (select public.register_live_activity(%L, %L, 'act-1', 'upd-1')) x$$,
    tests.id('now'), repeat('ab', 32))), 'ok');

select tests.run_as(tests.u('clara'), format(
  $$select (public.update_task(%L, 1, 'Läuft', 'each', array[%L]::uuid[], null, %L::date, %L::time)).version$$,
  tests.id('now'), tests.u('mia'),
  (select start_date from public.tasks where id = tests.id('now')), (select start_time from public.tasks where id = tests.id('now'))));
select tests.expect('G7 Inhaltsänderung aktualisiert die laufende Activity',
  tests.jobs(tests.id('now'), 'activity_update'), 'Mia');
select tests.run_as(tests.u('mia'), format($$select (public.complete_task(%L)).id$$, tests.id('now')));
select tests.expect('G8 Abhaken beendet die Activity (ein Auftrag)',
  tests.jobs(tests.id('now'), 'activity_end'), 'Mia');

-- push-dispatch-RPCs ----------------------------------------------------------

select tests.expect('P1 Clients können keine Aufträge übernehmen',
  tests.run_as(tests.u('mia'), $$select public.push_claim_jobs('x')::text$$), 'ERROR:42501');
select tests.expect('P2 Falsches Token wird abgelehnt',
  tests.run_as(null, $$select public.push_claim_jobs('falsch')::text$$, 'owner'), 'ERROR:42501');
insert into private.cron_tokens (token_hash, purpose) values (encode(sha256(convert_to('tok-1', 'UTF8')), 'hex'), 'push_dispatch');
select tests.put('claim', public.push_claim_jobs('tok-1')::text);
select tests.expect('P3 Übernommene Aufträge tragen Geräte und Titel',
  (select (e -> 'devices' -> 0 ->> 'token') = repeat('ab', 32) and e ->> 'title' = 'Bald'
     from jsonb_array_elements(tests.get('claim')::jsonb) e
    where e ->> 'kind' = 'activity_start' and (e ->> 'task_id')::uuid = tests.id('soon'))::text, 'true');
select tests.expect('P4 Token ist nur einmal gültig',
  tests.run_as(null, $$select public.push_claim_jobs('tok-1')::text$$, 'owner'), 'ERROR:42501');
select tests.expect('P5 Übernommene Aufträge sind in Arbeit',
  (select count(*)::text from public.notification_jobs where status = 'pending'), '0');

select tests.put('j_fail', (select id::text from public.notification_jobs where task_id = tests.id('soon') and kind = 'activity_start'));
select tests.put('j_sent', (select id::text from public.notification_jobs where task_id = tests.id('t') and kind = 'assigned'));
select public.push_report_results(jsonb_build_array(
  jsonb_build_object('id', tests.get('j_fail')::bigint, 'status', 'failed', 'error', 'timeout'),
  jsonb_build_object('id', tests.get('j_sent')::bigint, 'status', 'sent', 'invalid_device_ids', jsonb_build_array(tests.get('dev')))));
select tests.expect('P6 Fehlschlag wird erneut versucht, Erfolg ist gesendet',
  (select status::text from public.notification_jobs where id = tests.get('j_fail')::bigint) || '/' ||
  (select status::text from public.notification_jobs where id = tests.get('j_sent')::bigint), 'pending/sent');
select tests.expect('P7 Ungültig gemeldetes Gerät ist abgemeldet',
  (select (invalidated_at is not null)::text from public.devices where id = tests.id('dev')), 'true');

select tests.run_as(tests.u('mia'), $$select public.register_device(repeat('ab', 32), 'sandbox')::text$$);
select tests.expect('G9 Erneutes Registrieren reaktiviert und behält das Push-to-Start-Token',
  (select (invalidated_at is null)::text || '/' || push_to_start_token from public.devices where id = tests.id('dev')), 'true/pts-mia');
select tests.run_as(tests.u('clara'), $$select public.register_device(repeat('ab', 32), 'sandbox')::text$$);
select tests.expect('G10 Token wechselt beim Kontowechsel auf dem Gerät den Besitzer',
  (select user_id = tests.u('clara') from public.devices where id = tests.id('dev'))::text, 'true');
select tests.run_as(tests.u('clara'), format($$select 'ok' from (select public.unregister_device(%L)) x$$, repeat('ab', 32)));
select tests.expect('G11 Abmelden macht das Gerät ungültig',
  (select (invalidated_at is not null)::text from public.devices where id = tests.id('dev')), 'true');

select (select count(*) from tests.results) as gesamt, (select count(*) from tests.results where passed) as bestanden,
  coalesce((select string_agg(name || ' :: ' || coalesce(info, ''), E'\n' order by id) from tests.results where not passed), 'alle grün') as fehler;
rollback;
