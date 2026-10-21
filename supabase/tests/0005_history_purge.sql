-- 0005_history_purge
-- Tests für die 30-Tage-Bereinigung (Migration 0008). Eine Transaktion, am Ende rollback.
-- Ergebnis am 2026-10-21: 7/7 grün. Zusätzlich End-to-End: private.start_history_purge()
-- → Edge Function purge-history → HTTP 200, Token eingelöst.

begin;
create schema tests;
create table tests.results (id serial primary key, name text, passed boolean, info text);
create table tests.ctx (key text primary key, val text);
create function tests.expect(p_name text, p_actual text, p_expected text) returns void language sql as $$
  insert into tests.results (name, passed, info) values (p_name, p_actual is not distinct from p_expected,
    'erwartet: ' || coalesce(p_expected, 'NULL') || ' | erhalten: ' || coalesce(p_actual, 'NULL')); $$;
create function tests.as_user(p_user uuid, p_sql text) returns text language plpgsql as $$
declare v text; v_state text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin execute p_sql into v; exception when others then get stacked diagnostics v_state = returned_sqlstate; v := 'ERROR:' || v_state; end;
  reset role;
  return v;
end; $$;
create function tests.as_service(p_sql text) returns text language plpgsql as $$
declare v text; v_state text;
begin
  set local role service_role;
  begin execute p_sql into v; exception when others then get stacked diagnostics v_state = returned_sqlstate; v := 'ERROR:' || v_state; end;
  reset role;
  return v;
end; $$;
grant usage on schema tests to authenticated, service_role;
grant all on all tables in schema tests to authenticated, service_role;
grant all on all sequences in schema tests to authenticated, service_role;

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  ('e1111111-1111-4111-8111-111111111111', 'eva@example.test', '{"full_name": "Eva"}', '{}', 'authenticated', 'authenticated');
insert into tests.ctx values ('f', tests.as_user('e1111111-1111-4111-8111-111111111111', $$select (public.create_family('Familie E', '#5EC2F2')).id$$));
insert into tests.ctx select 't_' || n, tests.as_user('e1111111-1111-4111-8111-111111111111',
  format($$select (public.create_task(%L, %L, 'any_one', array['e1111111-1111-4111-8111-111111111111']::uuid[])).id$$, (select val from tests.ctx where key = 'f'), n))
  from unnest(array['alt_erledigt', 'alt_geloescht', 'neu_erledigt', 'offen']) as n;
update public.tasks set completed_at = now() - interval '31 days', completed_by = created_by, completion_source = 'assignee' where title = 'alt_erledigt';
update public.tasks set deleted_at = now() - interval '31 days', deleted_by = created_by where title = 'alt_geloescht';
update public.tasks set completed_at = now() - interval '5 days', completed_by = created_by, completion_source = 'assignee' where title = 'neu_erledigt';
insert into public.images (id, family_id, path, thumb_path, width, height, created_at)
values ('f1111111-1111-4111-8111-111111111111', (select val::uuid from tests.ctx where key = 'f'), 'x/verwaist.jpg', 'x/verwaist_thumb.jpg', 10, 10, now() - interval '2 days');
insert into storage.objects (bucket_id, name, created_at) values ('task-images', 'x/verwaist.jpg', now() - interval '2 days'), ('task-images', 'x/frisch.jpg', now());
insert into private.cron_tokens (token_hash, purpose) values (encode(sha256(convert_to('testtoken', 'UTF8')), 'hex'), 'purge_history');

select tests.expect('Q1 Nutzer dürfen die Bereinigung nicht aufrufen',
  tests.as_user('e1111111-1111-4111-8111-111111111111', $$select public.purge_expired_history('testtoken')::text$$), 'ERROR:42501');
select tests.expect('Q2 falsches Token', tests.as_service($$select public.purge_expired_history('falsch')::text$$), 'ERROR:42501');
insert into tests.ctx values ('result', tests.as_service($$select public.purge_expired_history('testtoken')::text$$));
select tests.expect('Q3 zwei abgelaufene Aufgaben entfernt', ((select val from tests.ctx where key = 'result')::jsonb ->> 'deleted_tasks'), '2');
select tests.expect('Q4 Aufgaben unter 30 Tagen und offene bleiben',
  (select string_agg(title, ',' order by title) from public.tasks where family_id = (select val::uuid from tests.ctx where key = 'f')), 'neu_erledigt,offen');
select tests.expect('Q5 verwaiste Bildzeile entfernt', ((select val from tests.ctx where key = 'result')::jsonb ->> 'deleted_images'), '1');
select tests.expect('Q6 nur die alte Datei ohne Zeile wird zum Löschen gemeldet',
  ((select val from tests.ctx where key = 'result')::jsonb -> 'file_paths')::text, '["x/verwaist.jpg"]');
select tests.expect('Q7 Token nicht wiederverwendbar', tests.as_service($$select public.purge_expired_history('testtoken')::text$$), 'ERROR:42501');

select count(*) as gesamt, count(*) filter (where passed) as bestanden,
  coalesce(string_agg(name || ' :: ' || info, E'\n') filter (where not passed), 'alle grün') as fehler from tests.results;
rollback;
