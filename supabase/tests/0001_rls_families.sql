-- 0001_rls_families
-- RLS- und RPC-Tests für Phase 1 (Profile, Familien, Mitglieder, Einladungen).
--
-- Ausführen: komplette Datei per execute_sql (Supabase-MCP) oder psql.
-- Alles läuft in EINER Transaktion und wird am Ende zurückgerollt:
-- Testnutzer, Testschema „tests“ und alle Daten verschwinden wieder.
-- Ergebnis: letzte Abfrage listet jeden Test mit bestanden ja/nein.
--
-- Simulierte Nutzer: set_config('role', 'authenticated') + request.jwt.claims (sub),
-- wie in der Supabase-Doku „RLS Performance and Best Practices“ beschrieben.
-- Fehler werden als 'ERROR:<hint>' (App-Fehlerschlüssel) bzw. 'ERROR:<SQLSTATE>'
-- (Postgres-Fehler, z. B. 42501 = permission denied) verglichen.
--
-- Matrix: Nicht-Mitglied (Otto), Mitglied (Max), Admin (Anna),
--         dazu Jana (Beitritt/Fehlversuche) und Rita (Rate-Limit).

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
    when 'admin'    then '11111111-1111-4111-8111-111111111111'
    when 'member'   then '22222222-2222-4222-8222-222222222222'
    when 'outsider' then '33333333-3333-4333-8333-333333333333'
    when 'joiner'   then '44444444-4444-4444-8444-444444444444'
    when 'rate'     then '55555555-5555-4555-8555-555555555555'
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
-- A. Testnutzer + Profil-Trigger
-- ---------------------------------------------------------------------------

insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role) values
  (tests.u('admin'),    'anna.admin@example.test',    '{"full_name": "Anna Admin"}', '{}', 'authenticated', 'authenticated'),
  (tests.u('member'),   'max@example.test',           '{"name": "Max Mitglied"}',    '{}', 'authenticated', 'authenticated'),
  (tests.u('outsider'), 'otto.outsider@example.test', '{}',                          '{}', 'authenticated', 'authenticated'),
  (tests.u('joiner'),   null,                         '{}',                          '{}', 'authenticated', 'authenticated'),
  (tests.u('rate'),     'rita@example.test',          '{"full_name": "   "}',        '{}', 'authenticated', 'authenticated');

select tests.expect('A1 Trigger: Name aus full_name',
  (select display_name from public.profiles where id = tests.u('admin')), 'Anna Admin');
select tests.expect('A2 Trigger: Name aus name',
  (select display_name from public.profiles where id = tests.u('member')), 'Max Mitglied');
select tests.expect('A3 Trigger: Name aus E-Mail-Lokalteil',
  (select display_name from public.profiles where id = tests.u('outsider')), 'otto.outsider');
select tests.expect('A4 Trigger: Fallback ohne E-Mail',
  (select display_name from public.profiles where id = tests.u('joiner')), 'Mitglied');
select tests.expect('A5 Trigger: leerer full_name → E-Mail-Lokalteil',
  (select display_name from public.profiles where id = tests.u('rate')), 'rita');

-- ---------------------------------------------------------------------------
-- B. create_family
-- ---------------------------------------------------------------------------

select tests.put('fam', tests.run_as(tests.u('admin'),
  $$select (public.create_family('  Familie Test  ', '#ff7f66')).id$$));
select tests.ok('B1 [Admin] create_family legt Familie an', tests.id('fam') is not null, tests.get('fam'));
select tests.expect('B2 create_family: Name getrimmt, Farbe normalisiert',
  (select name || '|' || color_hex || '|' || task_visibility from public.families where id = tests.id('fam')),
  'Familie Test|#FF7F66|all');
select tests.expect('B3 create_family: Ersteller ist admin',
  (select role::text from public.family_members where family_id = tests.id('fam') and user_id = tests.u('admin')),
  'admin');
select tests.expect('B4 create_family: Rechte-Schalter standardmäßig an',
  (select format('%s|%s|%s', members_can_invite::text, members_can_manage_family::text, members_can_remove_members::text)
     from public.families where id = tests.id('fam')),
  'true|true|true');
select tests.expect('B5 create_family: leerer Name',
  tests.run_as(tests.u('admin'), $$select (public.create_family('   ', '#FF7F66')).id$$),
  'ERROR:invalid_family_name');
select tests.expect('B6 create_family: Name > 60 Zeichen',
  tests.run_as(tests.u('admin'), format('select (public.create_family(%L, %L)).id', repeat('x', 61), '#FF7F66')),
  'ERROR:invalid_family_name');
select tests.expect('B7 create_family: ungültige Farbe',
  tests.run_as(tests.u('admin'), $$select (public.create_family('Test', 'rot')).id$$),
  'ERROR:invalid_color');
select tests.expect('B8 create_family: ohne sub-Claim',
  tests.run_as(null, $$select (public.create_family('Test', '#FF7F66')).id$$),
  'ERROR:not_authenticated');
select tests.expect('B9 [anon] create_family nicht ausführbar',
  tests.run_as(null, $$select (public.create_family('Test', '#FF7F66')).id$$, 'anon'),
  'ERROR:42501');

-- Eigene Familie des Nicht-Mitglieds (für Isolation)
select tests.put('fam_otto', tests.run_as(tests.u('outsider'),
  $$select (public.create_family('Familie Otto', '#5EC2F2')).id$$));
select tests.ok('B10 [Nicht-Mitglied] legt eigene Familie an', tests.id('fam_otto') is not null, tests.get('fam_otto'));

-- ---------------------------------------------------------------------------
-- C. create_invite
-- ---------------------------------------------------------------------------

select tests.put('code1', tests.run_as(tests.u('admin'),
  format('select (public.create_invite(%L)).code', tests.id('fam'))));
select tests.ok('C1 [Admin] create_invite: 8 Zeichen Crockford-Base32',
  tests.get('code1') ~ '^[0-9A-HJKMNP-TV-Z]{8}$', tests.get('code1'));
select tests.put('inv1', (select id::text from public.family_invites where code = tests.get('code1')));
select tests.ok('C2 create_invite: läuft nach 7 Tagen ab, nicht widerrufen, use_count 0',
  (select expires_at = created_at + interval '7 days' and revoked_at is null and use_count = 0
     and created_by = tests.u('admin')
     from public.family_invites where id = tests.id('inv1')));
select tests.expect('C3 [Nicht-Mitglied] create_invite',
  tests.run_as(tests.u('outsider'), format('select (public.create_invite(%L)).code', tests.id('fam'))),
  'ERROR:family_not_found');
select tests.ok('C4 generate_invite_code: 200 Codes gültig und verschieden',
  (select count(distinct c) = 200 and bool_and(c ~ '^[0-9A-HJKMNP-TV-Z]{8}$')
     from (select private.generate_invite_code() c from generate_series(1, 200)) s));
select tests.expect('C5 normalize_invite_code: Klein, Bindestrich, Leerzeichen, O/I/L',
  private.normalize_invite_code(' ab-cd ef oil '), 'ABCDEF011');

-- ---------------------------------------------------------------------------
-- D. join_family (Mitglied tritt bei)
-- ---------------------------------------------------------------------------

select tests.expect('D1 [Mitglied] join_family mit klein geschriebenem Code und Bindestrich',
  tests.run_as(tests.u('member'), format(
    $q$select j->>'status' || ':' || coalesce(j->>'family_id', '') from public.join_family(%L) as j$q$,
    lower(substr(tests.get('code1'), 1, 4)) || '-' || lower(substr(tests.get('code1'), 5)))),
  'joined:' || tests.get('fam'));
select tests.expect('D2 join_family: neue Rolle member',
  (select role::text from public.family_members where family_id = tests.id('fam') and user_id = tests.u('member')),
  'member');
select tests.expect('D3 join_family: use_count erhöht',
  (select use_count::text from public.family_invites where id = tests.id('inv1')), '1');
select tests.expect('D4 [Mitglied] join_family erneut: idempotent',
  tests.run_as(tests.u('member'), format(
    $q$select j->>'status' || ':' || coalesce(j->>'family_id', '') from public.join_family(%L) as j$q$,
    tests.get('code1'))),
  'already_member:' || tests.get('fam'));
select tests.expect('D5 join_family erneut: use_count unverändert, keine Doppelmitgliedschaft',
  (select (select use_count from public.family_invites where id = tests.id('inv1'))::text || '|' ||
          (select count(*) from public.family_members where family_id = tests.id('fam'))::text),
  '1|2');

-- ---------------------------------------------------------------------------
-- E. Lesen (RLS-Matrix)
-- ---------------------------------------------------------------------------

select tests.expect('E1 [Admin] sieht nur eigene Familie',
  tests.run_as(tests.u('admin'), 'select string_agg(name, ''|'' order by name) from public.families'),
  'Familie Test');
select tests.expect('E2 [Mitglied] sieht Familie',
  tests.run_as(tests.u('member'), 'select string_agg(name, ''|'' order by name) from public.families'),
  'Familie Test');
select tests.expect('E3 [Nicht-Mitglied] sieht fremde Familie nicht',
  tests.run_as(tests.u('outsider'), format('select count(*) from public.families where id = %L', tests.id('fam'))),
  '0');
select tests.expect('E4 [Nicht-Mitglied] sieht nur eigene Familie',
  tests.run_as(tests.u('outsider'), 'select string_agg(name, ''|'' order by name) from public.families'),
  'Familie Otto');
select tests.expect('E5 [Admin] sieht Mitglieder der Familie',
  tests.run_as(tests.u('admin'), format('select count(*) from public.family_members where family_id = %L', tests.id('fam'))),
  '2');
select tests.expect('E6 [Mitglied] sieht Mitglieder der Familie',
  tests.run_as(tests.u('member'), format('select count(*) from public.family_members where family_id = %L', tests.id('fam'))),
  '2');
select tests.expect('E7 [Nicht-Mitglied] sieht keine fremden Mitglieder',
  tests.run_as(tests.u('outsider'), format('select count(*) from public.family_members where family_id = %L', tests.id('fam'))),
  '0');
select tests.expect('E8 [Admin] sieht Profile: sich + Mitglied',
  tests.run_as(tests.u('admin'), 'select string_agg(display_name, ''|'' order by display_name) from public.profiles'),
  'Anna Admin|Max Mitglied');
select tests.expect('E9 [Mitglied] sieht Profile: sich + Admin',
  tests.run_as(tests.u('member'), 'select string_agg(display_name, ''|'' order by display_name) from public.profiles'),
  'Anna Admin|Max Mitglied');
select tests.expect('E10 [Nicht-Mitglied] sieht nur eigenes Profil',
  tests.run_as(tests.u('outsider'), 'select string_agg(display_name, ''|'' order by display_name) from public.profiles'),
  'otto.outsider');
select tests.expect('E11 Nutzer ohne Familie sieht eigenes Profil',
  tests.run_as(tests.u('joiner'), 'select string_agg(display_name, ''|'' order by display_name) from public.profiles'),
  'Mitglied');
select tests.expect('E12 [Admin] sieht Einladungen',
  tests.run_as(tests.u('admin'), format('select count(*) from public.family_invites where family_id = %L', tests.id('fam'))),
  '1');
select tests.expect('E13 [Mitglied] sieht Einladungen (Einladerecht an)',
  tests.run_as(tests.u('member'), format('select count(*) from public.family_invites where family_id = %L', tests.id('fam'))),
  '1');
select tests.expect('E14 [Nicht-Mitglied] sieht keine fremden Einladungen',
  tests.run_as(tests.u('outsider'), format('select count(*) from public.family_invites where family_id = %L', tests.id('fam'))),
  '0');
select tests.expect('E15 [anon] families nicht lesbar',
  tests.run_as(null, 'select count(*) from public.families', 'anon'), 'ERROR:42501');
select tests.expect('E16 [anon] profiles nicht lesbar',
  tests.run_as(null, 'select count(*) from public.profiles', 'anon'), 'ERROR:42501');
select tests.expect('E17 [anon] family_members nicht lesbar',
  tests.run_as(null, 'select count(*) from public.family_members', 'anon'), 'ERROR:42501');
select tests.expect('E18 [anon] family_invites nicht lesbar',
  tests.run_as(null, 'select count(*) from public.family_invites', 'anon'), 'ERROR:42501');

-- ---------------------------------------------------------------------------
-- F. Direktes Schreiben verweigert
-- ---------------------------------------------------------------------------

select tests.expect('F1 [Mitglied] insert families',
  tests.run_as(tests.u('member'), $$insert into public.families (name, color_hex) values ('X', '#000000') returning id$$),
  'ERROR:42501');
select tests.expect('F2 [Admin] update families',
  tests.run_as(tests.u('admin'), $$update public.families set name = 'X' returning id$$),
  'ERROR:42501');
select tests.expect('F3 [Admin] delete families',
  tests.run_as(tests.u('admin'), $$delete from public.families returning id$$),
  'ERROR:42501');
select tests.expect('F4 [Nicht-Mitglied] insert family_members (sich selbst hinzufügen)',
  tests.run_as(tests.u('outsider'), format(
    $q$insert into public.family_members (family_id, user_id, role) values (%L, %L, 'admin') returning user_id$q$,
    tests.id('fam'), tests.u('outsider'))),
  'ERROR:42501');
select tests.expect('F5 [Mitglied] update family_members (sich zum Admin machen)',
  tests.run_as(tests.u('member'), $$update public.family_members set role = 'admin' returning user_id$$),
  'ERROR:42501');
select tests.expect('F6 [Admin] delete family_members',
  tests.run_as(tests.u('admin'), $$delete from public.family_members returning user_id$$),
  'ERROR:42501');
select tests.expect('F7 [Mitglied] update profiles (eigenes Profil direkt)',
  tests.run_as(tests.u('member'), $$update public.profiles set display_name = 'Hack' returning id$$),
  'ERROR:42501');
select tests.expect('F8 [Mitglied] insert profiles',
  tests.run_as(tests.u('member'), format(
    $q$insert into public.profiles (id, display_name) values (%L, 'X') returning id$q$, tests.u('joiner'))),
  'ERROR:42501');
select tests.expect('F9 [Mitglied] insert family_invites',
  tests.run_as(tests.u('member'), format(
    $q$insert into public.family_invites (family_id, code) values (%L, 'ABCDEFGH') returning id$q$, tests.id('fam'))),
  'ERROR:42501');
select tests.expect('F10 [Admin] update family_invites',
  tests.run_as(tests.u('admin'), $$update public.family_invites set use_count = 0 returning id$$),
  'ERROR:42501');
select tests.expect('F11 [Mitglied] private.invite_attempts nicht lesbar',
  tests.run_as(tests.u('member'), 'select count(*) from private.invite_attempts'),
  'ERROR:42501');
select tests.expect('F12 [Mitglied] private-Funktionen nicht direkt aufrufbar',
  tests.run_as(tests.u('member'), 'select private.generate_invite_code()'),
  'ERROR:42501');
select tests.expect('F13 [Mitglied] RLS-Helfer nicht direkt aufrufbar (kein USAGE auf private)',
  tests.run_as(tests.u('member'), format('select private.is_family_member(%L)', tests.id('fam'))),
  'ERROR:42501');
select tests.expect('F14 [anon] join_family nicht ausführbar',
  tests.run_as(null, $$select public.join_family('ABCDEFGH')$$, 'anon'),
  'ERROR:42501');

-- ---------------------------------------------------------------------------
-- G. update_family (Recht manage_family)
-- ---------------------------------------------------------------------------

select tests.expect('G1 [Mitglied] update_family Name (Schalter an)',
  tests.run_as(tests.u('member'), format($q$select (public.update_family(%L, p_name => '  Familie Neu ')).name$q$, tests.id('fam'))),
  'Familie Neu');
select tests.expect('G2 [Mitglied] update_family Farbe + Sichtbarkeit',
  tests.run_as(tests.u('member'), format(
    $q$select f.color_hex || '|' || f.task_visibility || '|' || f.name
         from public.update_family(%L, p_color_hex => '#00aaff', p_task_visibility => 'assigned_only') f$q$,
    tests.id('fam'))),
  '#00AAFF|assigned_only|Familie Neu');
select tests.ok('G3 update_family: updated_at gepflegt',
  (select updated_at >= created_at from public.families where id = tests.id('fam')));
select tests.expect('G4 [Nicht-Mitglied] update_family',
  tests.run_as(tests.u('outsider'), format($q$select (public.update_family(%L, p_name => 'X')).name$q$, tests.id('fam'))),
  'ERROR:family_not_found');
select tests.expect('G5 update_family: Name zu lang',
  tests.run_as(tests.u('member'), format('select (public.update_family(%L, p_name => %L)).name', tests.id('fam'), repeat('x', 61))),
  'ERROR:invalid_family_name');
select tests.expect('G6 update_family: ungültige Farbe',
  tests.run_as(tests.u('member'), format($q$select (public.update_family(%L, p_color_hex => '#12345')).name$q$, tests.id('fam'))),
  'ERROR:invalid_color');

-- ---------------------------------------------------------------------------
-- H. set_family_permissions (nur Admin) + Wirkung der Schalter
-- ---------------------------------------------------------------------------

select tests.expect('H1 [Mitglied] set_family_permissions',
  tests.run_as(tests.u('member'), format('select (public.set_family_permissions(%L, false, false, false)).id', tests.id('fam'))),
  'ERROR:admin_required');
select tests.expect('H2 [Nicht-Mitglied] set_family_permissions',
  tests.run_as(tests.u('outsider'), format('select (public.set_family_permissions(%L, false, false, false)).id', tests.id('fam'))),
  'ERROR:family_not_found');
select tests.expect('H3 [Admin] set_family_permissions alle aus',
  tests.run_as(tests.u('admin'), format(
    $q$select format('%%s|%%s|%%s', f.members_can_invite::text, f.members_can_manage_family::text, f.members_can_remove_members::text)
         from public.set_family_permissions(%L, false, false, false) f$q$, tests.id('fam'))),
  'false|false|false');
select tests.expect('H4 [Mitglied] update_family ohne Recht',
  tests.run_as(tests.u('member'), format($q$select (public.update_family(%L, p_name => 'X')).name$q$, tests.id('fam'))),
  'ERROR:permission_denied_manage_family');
select tests.expect('H5 [Admin] update_family trotz Schalter aus',
  tests.run_as(tests.u('admin'), format($q$select (public.update_family(%L, p_name => 'Familie Test')).name$q$, tests.id('fam'))),
  'Familie Test');
select tests.expect('H6 [Mitglied] create_invite ohne Recht',
  tests.run_as(tests.u('member'), format('select (public.create_invite(%L)).code', tests.id('fam'))),
  'ERROR:permission_denied_invite');
select tests.expect('H7 [Mitglied] sieht Einladungen ohne Einladerecht nicht',
  tests.run_as(tests.u('member'), format('select count(*) from public.family_invites where family_id = %L', tests.id('fam'))),
  '0');
select tests.expect('H8 [Admin] sieht Einladungen weiterhin',
  tests.run_as(tests.u('admin'), format('select count(*) from public.family_invites where family_id = %L', tests.id('fam'))),
  '1');
select tests.expect('H9 [Mitglied] revoke_invite ohne Recht',
  tests.run_as(tests.u('member'), format('select (public.revoke_invite(%L)).id', tests.id('inv1'))),
  'ERROR:permission_denied_invite');
select tests.expect('H10 [Admin] set_family_permissions: null lässt Werte unverändert',
  tests.run_as(tests.u('admin'), format(
    $q$select format('%%s|%%s|%%s', f.members_can_invite::text, f.members_can_manage_family::text, f.members_can_remove_members::text)
         from public.set_family_permissions(%L, p_members_can_invite => true) f$q$, tests.id('fam'))),
  'true|false|false');
select tests.put('code2', tests.run_as(tests.u('member'), format('select (public.create_invite(%L)).code', tests.id('fam'))));
select tests.ok('H11 [Mitglied] create_invite mit Recht', tests.get('code2') ~ '^[0-9A-HJKMNP-TV-Z]{8}$', tests.get('code2'));
select tests.expect('H12 has_family_permission: unbekanntes Recht wirft Fehler',
  tests.run_as(null, format($q$select private.has_family_permission(%L, 'delete_everything')$q$, tests.id('fam')), 'owner'),
  'ERROR:22023');

-- ---------------------------------------------------------------------------
-- I. revoke_invite
-- ---------------------------------------------------------------------------

select tests.expect('I1 [Nicht-Mitglied] revoke_invite',
  tests.run_as(tests.u('outsider'), format('select (public.revoke_invite(%L)).id', tests.id('inv1'))),
  'ERROR:invite_not_found');
select tests.expect('I2 [Admin] revoke_invite',
  tests.run_as(tests.u('admin'), format('select (public.revoke_invite(%L)).revoked_at is not null', tests.id('inv1'))),
  'true');
select tests.expect('I3 [Admin] revoke_invite erneut: idempotent',
  tests.run_as(tests.u('admin'), format('select (public.revoke_invite(%L)).revoked_at is not null', tests.id('inv1'))),
  'true');
select tests.expect('I4 revoke_invite: unbekannte ID',
  tests.run_as(tests.u('admin'), format('select (public.revoke_invite(%L)).id', gen_random_uuid())),
  'ERROR:invite_not_found');

-- ---------------------------------------------------------------------------
-- J. join_family: Fehlerfälle (Jana)
-- ---------------------------------------------------------------------------

select tests.expect('J1 join_family: widerrufener Code',
  tests.run_as(tests.u('joiner'), format($q$select j->>'status' from public.join_family(%L) j$q$, tests.get('code1'))),
  'revoked');
select tests.expect('J2 join_family: falsches Format zählt nicht',
  tests.run_as(tests.u('joiner'), $q$select j->>'status' from public.join_family('abc') j$q$),
  'invalid_format');
select tests.expect('J3 join_family: null-Code',
  tests.run_as(tests.u('joiner'), $q$select j->>'status' from public.join_family(null) j$q$),
  'invalid_format');
select tests.expect('J4 join_family: unbekannter Code',
  tests.run_as(tests.u('joiner'), $q$select j->>'status' from public.join_family('ZZZZ-ZZZZ') j$q$),
  'invalid_code');
with ins as (
  insert into public.family_invites (family_id, code, created_by, created_at, expires_at)
  values (tests.id('fam'), private.generate_invite_code(), tests.u('admin'), now() - interval '8 days', now() - interval '1 day')
  returning code
)
select tests.put('code_expired', code) from ins;
select tests.expect('J5 join_family: abgelaufener Code',
  tests.run_as(tests.u('joiner'), format($q$select j->>'status' from public.join_family(%L) j$q$, tests.get('code_expired'))),
  'expired');
select tests.expect('J6 join_family: Fehlversuche protokolliert (revoked, invalid_code, expired)',
  (select string_agg(reason, '|' order by reason) from private.invite_attempts where user_id = tests.u('joiner')),
  'expired|invalid_code|revoked');
select tests.expect('J7 join_family: Fehlversuche machen nicht zum Mitglied',
  (select count(*)::text from public.family_members where family_id = tests.id('fam') and user_id = tests.u('joiner')),
  '0');
select tests.expect('J8 join_family: Antwort enthält deutsche Meldung',
  tests.run_as(tests.u('joiner'), $q$select j->>'message' from public.join_family('x') j$q$),
  'Ein Einladungscode hat 8 Zeichen (Buchstaben und Ziffern).');
select tests.expect('J9 [Jana] join_family mit gültigem Code',
  tests.run_as(tests.u('joiner'), format($q$select j->>'status' from public.join_family(%L) j$q$, tests.get('code2'))),
  'joined');

-- ---------------------------------------------------------------------------
-- K. Rate-Limit (Rita): max. 10 Fehlversuche pro Stunde
-- ---------------------------------------------------------------------------

select tests.expect('K1 10 Fehlversuche werden einzeln abgewiesen',
  tests.run_as(tests.u('rate'), $q$
    select string_agg(public.join_family('ZZZZZZZ' || substr('0123456789ABCDEFGHJK', g, 1)) ->> 'status', ',' order by g)
    from generate_series(1, 10) g$q$),
  'invalid_code,invalid_code,invalid_code,invalid_code,invalid_code,invalid_code,invalid_code,invalid_code,invalid_code,invalid_code');
select tests.expect('K2 11. Versuch mit GÜLTIGEM Code → rate_limited',
  tests.run_as(tests.u('rate'), format($q$select j->>'status' from public.join_family(%L) j$q$, tests.get('code2'))),
  'rate_limited');
select tests.ok('K3 rate_limited: retry_after_seconds zwischen 1 und 3600',
  case when v ~ '^[0-9]+$' then v::int between 1 and 3600 else false end, v)
from (select tests.run_as(tests.u('rate'),
        format($q$select j->>'retry_after_seconds' from public.join_family(%L) j$q$, tests.get('code2'))) as v) s;
select tests.expect('K4 rate_limited: kein Beitritt',
  (select count(*)::text from public.family_members where family_id = tests.id('fam') and user_id = tests.u('rate')),
  '0');
select tests.expect('K5 rate_limited: zählt nicht weiter hoch',
  (select count(*)::text from private.invite_attempts where user_id = tests.u('rate')),
  '10');
update private.invite_attempts set attempted_at = now() - interval '61 minutes' where user_id = tests.u('rate');
select tests.expect('K6 nach Ablauf des Fensters: Beitritt möglich',
  tests.run_as(tests.u('rate'), format($q$select j->>'status' from public.join_family(%L) j$q$, tests.get('code2'))),
  'joined');
select tests.expect('K7 alte Fehlversuche aufgeräumt',
  (select count(*)::text from private.invite_attempts where user_id = tests.u('rate')),
  '0');
select tests.expect('K8 Fehlversuche anderer Nutzer zählen nicht (Jana weiterhin unter Limit)',
  tests.run_as(tests.u('joiner'), $q$select j->>'status' from public.join_family('ZZZZZZZZ') j$q$),
  'invalid_code');

-- ---------------------------------------------------------------------------
-- L. set_member_role (nur Admin, Schutz letzter Admin)
-- ---------------------------------------------------------------------------

select tests.expect('L1 [Mitglied] set_member_role',
  tests.run_as(tests.u('member'), format($q$select (public.set_member_role(%L, %L, 'admin')).role$q$, tests.id('fam'), tests.u('member'))),
  'ERROR:admin_required');
select tests.expect('L2 [Nicht-Mitglied] set_member_role',
  tests.run_as(tests.u('outsider'), format($q$select (public.set_member_role(%L, %L, 'admin')).role$q$, tests.id('fam'), tests.u('outsider'))),
  'ERROR:family_not_found');
select tests.expect('L3 [Admin] letzter Admin kann sich nicht herabstufen',
  tests.run_as(tests.u('admin'), format($q$select (public.set_member_role(%L, %L, 'member')).role$q$, tests.id('fam'), tests.u('admin'))),
  'ERROR:last_admin');
select tests.expect('L4 [Admin] set_member_role für Nicht-Mitglied',
  tests.run_as(tests.u('admin'), format($q$select (public.set_member_role(%L, %L, 'admin')).role$q$, tests.id('fam'), tests.u('outsider'))),
  'ERROR:member_not_found');
select tests.expect('L5 [Admin] ernennt Mitglied zum Admin',
  tests.run_as(tests.u('admin'), format($q$select (public.set_member_role(%L, %L, 'admin')).role$q$, tests.id('fam'), tests.u('member'))),
  'admin');
select tests.expect('L6 neuer Admin stuft alten Admin herab',
  tests.run_as(tests.u('member'), format($q$select (public.set_member_role(%L, %L, 'member')).role$q$, tests.id('fam'), tests.u('admin'))),
  'member');
select tests.expect('L7 jetzt letzter Admin kann sich nicht herabstufen',
  tests.run_as(tests.u('member'), format($q$select (public.set_member_role(%L, %L, 'member')).role$q$, tests.id('fam'), tests.u('member'))),
  'ERROR:last_admin');
select tests.expect('L8 herabgestufter Admin hat keine Admin-Rechte mehr',
  tests.run_as(tests.u('admin'), format('select (public.set_family_permissions(%L, true, true, true)).id', tests.id('fam'))),
  'ERROR:admin_required');
select tests.expect('L9 Rückkehr zum Ausgangszustand (Anna Admin)',
  tests.run_as(tests.u('member'), format($q$select (public.set_member_role(%L, %L, 'admin')).role$q$, tests.id('fam'), tests.u('admin'))),
  'admin');
select tests.expect('L10 Rückkehr zum Ausgangszustand (Max Mitglied)',
  tests.run_as(tests.u('admin'), format($q$select (public.set_member_role(%L, %L, 'member')).role$q$, tests.id('fam'), tests.u('member'))),
  'member');
select tests.expect('L11 set_member_role: gleiche Rolle ist No-op',
  tests.run_as(tests.u('admin'), format($q$select (public.set_member_role(%L, %L, 'member')).role$q$, tests.id('fam'), tests.u('member'))),
  'member');

-- ---------------------------------------------------------------------------
-- M. remove_member (Recht remove_members oder sich selbst)
-- Stand: Anna admin; Max, Jana, Rita member; Schalter invite an, manage/remove aus
-- ---------------------------------------------------------------------------

select tests.expect('M1 [Mitglied] remove_member ohne Recht',
  tests.run_as(tests.u('member'), format('select public.remove_member(%L, %L)', tests.id('fam'), tests.u('joiner'))),
  'ERROR:permission_denied_remove_members');
select tests.expect('M2 [Admin] Schalter remove_members an',
  tests.run_as(tests.u('admin'), format('select (public.set_family_permissions(%L, p_members_can_remove_members => true)).members_can_remove_members', tests.id('fam'))),
  'true');
select tests.expect('M3 [Nicht-Mitglied] remove_member',
  tests.run_as(tests.u('outsider'), format('select public.remove_member(%L, %L)', tests.id('fam'), tests.u('joiner'))),
  'ERROR:family_not_found');
select tests.expect('M4 [Mitglied] darf Admin nicht entfernen',
  tests.run_as(tests.u('member'), format('select public.remove_member(%L, %L)', tests.id('fam'), tests.u('admin'))),
  'ERROR:admin_required_to_remove_admin');
select tests.expect('M5 [Mitglied] remove_member für Nicht-Mitglied',
  tests.run_as(tests.u('member'), format('select public.remove_member(%L, %L)', tests.id('fam'), tests.u('outsider'))),
  'ERROR:member_not_found');
select tests.expect('M6 [Mitglied] entfernt Mitglied (Recht an)',
  tests.run_as(tests.u('member'), format('select public.remove_member(%L, %L)', tests.id('fam'), tests.u('joiner'))),
  'removed');
select tests.expect('M7 Entfernte sieht Familie nicht mehr',
  tests.run_as(tests.u('joiner'), format('select count(*) from public.families where id = %L', tests.id('fam'))),
  '0');
select tests.expect('M8 Entfernte sieht frühere Mitglieder-Profile nicht mehr',
  tests.run_as(tests.u('joiner'), 'select count(*) from public.profiles'),
  '1');
select tests.expect('M9 [Rita] entfernt sich selbst (= verlassen)',
  tests.run_as(tests.u('rate'), format('select public.remove_member(%L, %L)', tests.id('fam'), tests.u('rate'))),
  'left');
select tests.expect('M10 [Admin] remove_member für bereits entfernte Person',
  tests.run_as(tests.u('admin'), format('select public.remove_member(%L, %L)', tests.id('fam'), tests.u('joiner'))),
  'ERROR:member_not_found');

-- ---------------------------------------------------------------------------
-- N. update_profile (nur eigenes Profil)
-- ---------------------------------------------------------------------------

select tests.expect('N1 [Mitglied] update_profile Name getrimmt',
  tests.run_as(tests.u('member'), $$select (public.update_profile(p_display_name => '  Maxi  ')).display_name$$),
  'Maxi');
select tests.expect('N2 [Admin] sieht neuen Namen des Mitglieds',
  tests.run_as(tests.u('admin'), format('select display_name from public.profiles where id = %L', tests.u('member'))),
  'Maxi');
select tests.expect('N3 update_profile ändert nur eigenes Profil',
  (select display_name from public.profiles where id = tests.u('admin')),
  'Anna Admin');
select tests.expect('N4 update_profile: leerer Name',
  tests.run_as(tests.u('member'), $$select (public.update_profile(p_display_name => '  ')).display_name$$),
  'ERROR:invalid_display_name');
select tests.expect('N5 update_profile: Name > 80 Zeichen',
  tests.run_as(tests.u('member'), format('select (public.update_profile(p_display_name => %L)).display_name', repeat('x', 81))),
  'ERROR:invalid_display_name');
select tests.expect('N6 update_profile: Avatar im fremden Ordner',
  tests.run_as(tests.u('member'), format('select (public.update_profile(p_avatar_path => %L)).avatar_path', tests.u('admin') || '/avatar.jpg')),
  'ERROR:invalid_avatar_path');
select tests.expect('N7 update_profile: Avatar mit Pfad-Traversal',
  tests.run_as(tests.u('member'), format('select (public.update_profile(p_avatar_path => %L)).avatar_path', tests.u('member') || '/../x.jpg')),
  'ERROR:invalid_avatar_path');
select tests.expect('N8 update_profile: Avatar im eigenen Ordner',
  tests.run_as(tests.u('member'), format('select (public.update_profile(p_avatar_path => %L)).avatar_path', tests.u('member') || '/avatar.jpg')),
  tests.u('member') || '/avatar.jpg');
select tests.expect('N9 update_profile: Name bleibt bei nur Avatar-Änderung',
  (select display_name from public.profiles where id = tests.u('member')),
  'Maxi');
select tests.expect('N10 update_profile: leerer Avatar-Pfad entfernt Bild',
  tests.run_as(tests.u('member'), $$select coalesce((public.update_profile(p_avatar_path => '')).avatar_path, 'entfernt')$$),
  'entfernt');
select tests.expect('N11 update_profile: ohne sub-Claim',
  tests.run_as(null, $$select (public.update_profile(p_display_name => 'X')).display_name$$),
  'ERROR:not_authenticated');
select tests.expect('N12 [anon] update_profile nicht ausführbar',
  tests.run_as(null, $$select (public.update_profile(p_display_name => 'X')).display_name$$, 'anon'),
  'ERROR:42501');

-- ---------------------------------------------------------------------------
-- O. leave_family (letzter Admin, letzte Person löscht Familie)
-- Stand: Anna admin, Max member
-- ---------------------------------------------------------------------------

select tests.expect('O1 [Nicht-Mitglied] leave_family',
  tests.run_as(tests.u('outsider'), format('select public.leave_family(%L)', tests.id('fam'))),
  'ERROR:family_not_found');
select tests.expect('O2 [Admin] letzter Admin darf nicht gehen, solange andere da sind',
  tests.run_as(tests.u('admin'), format('select public.leave_family(%L)', tests.id('fam'))),
  'ERROR:last_admin');
select tests.expect('O3 [Mitglied] verlässt Familie',
  tests.run_as(tests.u('member'), format('select public.leave_family(%L)', tests.id('fam'))),
  'left');
select tests.expect('O4 Admin und Ex-Mitglied sehen ihre Profile gegenseitig nicht mehr',
  tests.run_as(tests.u('admin'), format('select count(*) from public.profiles where id = %L', tests.u('member'))),
  '0');
select tests.expect('O5 [Admin] als letzte Person: Familie wird gelöscht',
  tests.run_as(tests.u('admin'), format('select public.leave_family(%L)', tests.id('fam'))),
  'family_deleted');
select tests.expect('O6 Familie, Mitglieder und Einladungen sind weg',
  (select format('%s|%s|%s',
     (select count(*) from public.families where id = tests.id('fam')),
     (select count(*) from public.family_members where family_id = tests.id('fam')),
     (select count(*) from public.family_invites where family_id = tests.id('fam')))),
  '0|0|0');
select tests.expect('O7 andere Familie unberührt',
  tests.run_as(tests.u('outsider'), 'select count(*) from public.families'),
  '1');

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
