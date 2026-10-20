-- 0002_storage_avatars
-- Tests für den Storage-Bucket „avatars“ (Migration 0006).
--
-- Ausführen und Harness wie 0001_rls_families.sql: eine Transaktion, am Ende rollback.
-- Matrix: Besitzerin (Olivia), Familienmitglied (Carl), Nicht-Mitglied (Otto).
-- Storage-Zugriffe werden als Zeilen in storage.objects simuliert; die Storage-API prüft
-- dieselben RLS-Policies.

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
    when 'owner'    then 'a1111111-1111-4111-8111-111111111111'
    when 'comember' then 'a2222222-2222-4222-8222-222222222222'
    when 'outsider' then 'a3333333-3333-4333-8333-333333333333'
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

-- ---------------------------------------------------------------------------
-- A. Testnutzer und gemeinsame Familie (Olivia + Carl)
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  (tests.u('owner'),    'olivia@example.test', '{"full_name": "Olivia"}', '{}', 'authenticated', 'authenticated'),
  (tests.u('comember'), 'carl@example.test',   '{"full_name": "Carl"}',   '{}', 'authenticated', 'authenticated'),
  (tests.u('outsider'), 'otto@example.test',   '{"full_name": "Otto"}',   '{}', 'authenticated', 'authenticated');

select tests.put('fam', tests.run_as(tests.u('owner'),
  $$select (public.create_family('Avatar-Test', '#5EC2F2')).id$$));
select tests.put('code', tests.run_as(tests.u('owner'),
  format($$select (public.create_invite(%L)).code$$, tests.id('fam'))));
select tests.expect('A1 Carl tritt der Familie bei',
  tests.run_as(tests.u('comember'), format($$select public.join_family(%L) ->> 'status'$$, tests.get('code'))),
  'joined');

-- ---------------------------------------------------------------------------
-- B. Bucket-Konfiguration
-- ---------------------------------------------------------------------------

select tests.expect('B1 Bucket privat, 1 MB, nur JPEG',
  (select format('%s|%s|%s', public::text, file_size_limit, array_to_string(allowed_mime_types, ','))
     from storage.buckets where id = 'avatars'),
  'false|1048576|image/jpeg');
select tests.expect('B2 keine DELETE-Policy für Clients',
  (select count(*)::text from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and cmd = 'DELETE'
      and policyname like 'avatars%'),
  '0');

-- ---------------------------------------------------------------------------
-- C. Hochladen (INSERT)
-- ---------------------------------------------------------------------------

select tests.expect('C1 [Olivia] eigenes avatar.jpg hochladen',
  tests.run_as(tests.u('owner'), format(
    $$insert into storage.objects (bucket_id, name) values ('avatars', %L) returning name$$,
    tests.u('owner')::text || '/avatar.jpg')),
  tests.u('owner')::text || '/avatar.jpg');
select tests.expect('C2 [Olivia] in Carls Ordner hochladen → verweigert',
  tests.run_as(tests.u('owner'), format(
    $$insert into storage.objects (bucket_id, name) values ('avatars', %L) returning name$$,
    tests.u('comember')::text || '/avatar.jpg')),
  'ERROR:42501');
select tests.expect('C3 [Olivia] anderer Dateiname im eigenen Ordner → verweigert',
  tests.run_as(tests.u('owner'), format(
    $$insert into storage.objects (bucket_id, name) values ('avatars', %L) returning name$$,
    tests.u('owner')::text || '/zweites.jpg')),
  'ERROR:42501');
select tests.expect('C4 [anon] hochladen → verweigert',
  tests.run_as(null, format(
    $$insert into storage.objects (bucket_id, name) values ('avatars', %L) returning name$$,
    tests.u('owner')::text || '/avatar.jpg'), 'anon'),
  'ERROR:42501');

-- ---------------------------------------------------------------------------
-- D. Lesen (SELECT)
-- ---------------------------------------------------------------------------

select tests.expect('D1 [Olivia] sieht eigenes Bild',
  tests.run_as(tests.u('owner'), $$select count(*) from storage.objects where bucket_id = 'avatars'$$),
  '1');
select tests.expect('D2 [Carl, gemeinsame Familie] sieht Olivias Bild',
  tests.run_as(tests.u('comember'), $$select count(*) from storage.objects where bucket_id = 'avatars'$$),
  '1');
select tests.expect('D3 [Otto, keine gemeinsame Familie] sieht nichts',
  tests.run_as(tests.u('outsider'), $$select count(*) from storage.objects where bucket_id = 'avatars'$$),
  '0');
select tests.expect('D4 [anon] sieht nichts',
  tests.run_as(null, $$select count(*) from storage.objects where bucket_id = 'avatars'$$, 'anon'),
  '0');

-- ---------------------------------------------------------------------------
-- E. Überschreiben (UPDATE, für upsert)
-- ---------------------------------------------------------------------------

select tests.expect('E1 [Olivia] eigenes Bild überschreiben',
  tests.run_as(tests.u('owner'), format(
    $$update storage.objects set metadata = '{"size": 1}'::jsonb
       where bucket_id = 'avatars' and name = %L returning name$$,
    tests.u('owner')::text || '/avatar.jpg')),
  tests.u('owner')::text || '/avatar.jpg');
select tests.expect('E2 [Carl] Olivias Bild überschreiben → keine Zeile',
  tests.run_as(tests.u('comember'), format(
    $$update storage.objects set metadata = '{"size": 2}'::jsonb
       where bucket_id = 'avatars' and name = %L returning name$$,
    tests.u('owner')::text || '/avatar.jpg')),
  'NULL');
select tests.expect('E3 [Olivia] eigenes Bild umbenennen → verweigert',
  tests.run_as(tests.u('owner'), format(
    $$update storage.objects set name = %L
       where bucket_id = 'avatars' and name = %L returning name$$,
    tests.u('owner')::text || '/anders.jpg', tests.u('owner')::text || '/avatar.jpg')),
  'ERROR:42501');

-- ---------------------------------------------------------------------------
-- F. Profil verweist auf das Bild
-- ---------------------------------------------------------------------------

select tests.expect('F1 [Olivia] update_profile mit eigenem avatar.jpg',
  tests.run_as(tests.u('owner'), format(
    $$select (public.update_profile(null, %L)).avatar_path$$, tests.u('owner')::text || '/avatar.jpg')),
  tests.u('owner')::text || '/avatar.jpg');
select tests.expect('F2 [Olivia] Bild entfernen setzt avatar_path auf null',
  tests.run_as(tests.u('owner'), $$select coalesce((public.update_profile(null, '')).avatar_path, 'leer')$$),
  'leer');

-- ---------------------------------------------------------------------------
-- Ergebnis
-- ---------------------------------------------------------------------------

select
  (select count(*) from tests.results)                     as gesamt,
  (select count(*) from tests.results where passed)        as bestanden,
  (select count(*) from tests.results where not passed)    as fehlgeschlagen,
  coalesce((select string_agg(name || ' :: ' || coalesce(info, ''), E'\n' order by id)
              from tests.results where not passed), 'alle grün') as fehler,
  (select string_agg(case when passed then 'ok  ' else 'FAIL' end || ' ' || name, E'\n' order by id)
     from tests.results) as protokoll;

rollback;
