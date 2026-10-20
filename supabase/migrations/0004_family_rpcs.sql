-- 0004_family_rpcs
-- Schreib-RPCs für Familien, Mitglieder, Einladungen und Profil.
-- Alle RPCs: security definer, search_path = '', explizite Prüfungen,
-- sprechende Fehler (Meldung auf Deutsch, stabiler Schlüssel im Feld „hint“).
-- EXECUTE nur für authenticated.

-- ---------------------------------------------------------------------------
-- Interne Helfer
-- ---------------------------------------------------------------------------

-- Fehlerkatalog: wirft einen Fehler mit deutscher Meldung, passendem SQLSTATE
-- (PostgREST leitet daraus den HTTP-Status ab) und dem Schlüssel als „hint“.
create function private.raise_app_error(p_key text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_state   text;
  v_message text;
begin
  select e.state, e.message
    into v_state, v_message
  from (values
    ('not_authenticated',               '42501', 'Nicht angemeldet.'),
    ('invalid_family_name',             '22023', 'Der Familienname muss 1 bis 60 Zeichen lang sein.'),
    ('invalid_color',                   '22023', 'Die Farbe muss im Format #RRGGBB angegeben werden.'),
    ('invalid_display_name',            '22023', 'Der Anzeigename muss 1 bis 80 Zeichen lang sein.'),
    ('invalid_avatar_path',             '22023', 'Der Bildpfad muss im eigenen Ordner liegen ({user_id}/{datei}).'),
    ('invalid_role',                    '22023', 'Unbekannte Rolle.'),
    ('family_not_found',                'P0002', 'Familie nicht gefunden oder du bist kein Mitglied.'),
    ('member_not_found',                'P0002', 'Diese Person ist kein Mitglied der Familie.'),
    ('invite_not_found',                'P0002', 'Einladung nicht gefunden.'),
    ('profile_not_found',               'P0002', 'Profil nicht gefunden.'),
    ('admin_required',                  '42501', 'Nur Admins dürfen das.'),
    ('permission_denied_invite',        '42501', 'Du darfst in dieser Familie niemanden einladen.'),
    ('permission_denied_manage_family', '42501', 'Du darfst diese Familie nicht bearbeiten.'),
    ('permission_denied_remove_members','42501', 'Du darfst in dieser Familie keine Mitglieder entfernen.'),
    ('admin_required_to_remove_admin',  '42501', 'Nur Admins dürfen andere Admins entfernen.'),
    ('last_admin',                      'P0001', 'Die Familie braucht mindestens einen Admin. Ernenne zuerst eine andere Person zum Admin.'),
    ('invite_code_generation_failed',   'P0001', 'Es konnte kein eindeutiger Einladungscode erzeugt werden. Bitte erneut versuchen.')
  ) as e(key, state, message)
  where e.key = p_key;

  if v_state is null then
    v_state := 'P0001';
    v_message := 'Unbekannter Fehler.';
  end if;

  raise exception using
    errcode = v_state,
    message = v_message,
    hint    = p_key;
end;
$$;

-- Liefert die ID des angemeldeten Nutzers oder wirft not_authenticated.
create function private.require_uid()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    perform private.raise_app_error('not_authenticated');
  end if;
  return v_uid;
end;
$$;

-- Liefert die Rolle des aktuellen Nutzers oder wirft family_not_found
-- (Nicht-Mitglieder erfahren nicht, ob die Familie existiert).
create function private.require_member(p_family_id uuid)
returns public.family_role
language plpgsql
stable
set search_path = ''
as $$
declare
  v_role public.family_role;
begin
  v_role := private.family_role(p_family_id);
  if v_role is null then
    perform private.raise_app_error('family_not_found');
  end if;
  return v_role;
end;
$$;

-- Ergebnisobjekt für join_family().
create function private.join_family_result(
  p_status text,
  p_family_id uuid default null,
  p_retry_after_seconds integer default null
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'status', p_status,
    'family_id', p_family_id,
    'retry_after_seconds', p_retry_after_seconds,
    'message', case p_status
      when 'joined'         then 'Du bist der Familie beigetreten.'
      when 'already_member' then 'Du bist bereits Mitglied dieser Familie.'
      when 'invalid_format' then 'Ein Einladungscode hat 8 Zeichen (Buchstaben und Ziffern).'
      when 'invalid_code'   then 'Dieser Einladungscode ist ungültig.'
      when 'expired'        then 'Dieser Einladungscode ist abgelaufen.'
      when 'revoked'        then 'Dieser Einladungscode wurde zurückgezogen.'
      when 'rate_limited'   then 'Zu viele Fehlversuche. Bitte versuche es später erneut.'
    end
  );
$$;

revoke execute on function private.raise_app_error(text) from public, anon, authenticated;
revoke execute on function private.require_uid() from public, anon, authenticated;
revoke execute on function private.require_member(uuid) from public, anon, authenticated;
revoke execute on function private.join_family_result(text, uuid, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- create_family(name, color_hex): Ersteller wird Admin.
-- ---------------------------------------------------------------------------

create function public.create_family(p_name text, p_color_hex text)
returns public.families
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_uid();
  v_name   text := btrim(coalesce(p_name, ''));
  v_family public.families;
begin
  if char_length(v_name) not between 1 and 60 then
    perform private.raise_app_error('invalid_family_name');
  end if;
  if p_color_hex is null or p_color_hex !~ '^#[0-9A-Fa-f]{6}$' then
    perform private.raise_app_error('invalid_color');
  end if;

  insert into public.families (name, color_hex, created_by)
  values (v_name, upper(p_color_hex), v_uid)
  returning * into v_family;

  insert into public.family_members (family_id, user_id, role)
  values (v_family.id, v_uid, 'admin');

  return v_family;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_invite(family_id): braucht Recht „invite“.
-- ---------------------------------------------------------------------------

create function public.create_invite(p_family_id uuid)
returns public.family_invites
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_uid();
  v_invite public.family_invites;
begin
  perform private.require_member(p_family_id);
  if not private.has_family_permission(p_family_id, 'invite') then
    perform private.raise_app_error('permission_denied_invite');
  end if;

  -- 40 Bit Zufall: Kollisionen sind sehr selten, werden aber abgefangen.
  for i in 1..5 loop
    begin
      insert into public.family_invites (family_id, code, created_by)
      values (p_family_id, private.generate_invite_code(), v_uid)
      returning * into v_invite;
      return v_invite;
    exception when unique_violation then
      null;
    end;
  end loop;

  perform private.raise_app_error('invite_code_generation_failed');
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- revoke_invite(invite_id): braucht Recht „invite“; idempotent.
-- ---------------------------------------------------------------------------

create function public.revoke_invite(p_invite_id uuid)
returns public.family_invites
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite public.family_invites;
begin
  perform private.require_uid();

  select * into v_invite
  from public.family_invites i
  where i.id = p_invite_id;

  if not found or not private.is_family_member(v_invite.family_id) then
    perform private.raise_app_error('invite_not_found');
  end if;
  if not private.has_family_permission(v_invite.family_id, 'invite') then
    perform private.raise_app_error('permission_denied_invite');
  end if;

  update public.family_invites i
     set revoked_at = coalesce(i.revoked_at, now())
   where i.id = p_invite_id
  returning * into v_invite;

  return v_invite;
end;
$$;

-- ---------------------------------------------------------------------------
-- join_family(code)
--
-- Gibt ein JSON-Objekt {status, family_id, retry_after_seconds, message} zurück
-- und wirft bei ungültigen Codes bewusst KEINEN Fehler: Ein Fehler würde die
-- Transaktion zurückrollen und damit auch den protokollierten Fehlversuch –
-- das Rate-Limit wäre wirkungslos.
--
-- status: joined | already_member | invalid_format | invalid_code | expired
--         | revoked | rate_limited
-- Rate-Limit: max. 10 Fehlversuche (invalid_code/expired/revoked) pro Nutzer
-- in der letzten Stunde. invalid_format zählt nicht (kein DB-Treffer möglich).
-- ---------------------------------------------------------------------------

create function public.join_family(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_failures constant integer := 10;
  c_window       constant interval := interval '1 hour';
  v_uid      uuid := private.require_uid();
  v_code     text;
  v_failures integer;
  v_oldest   timestamptz;
  v_invite   public.family_invites;
begin
  -- Parallele Versuche desselben Nutzers serialisieren (Rate-Limit exakt halten).
  perform pg_advisory_xact_lock(hashtextextended('familiar.join_family:' || v_uid::text, 0));

  delete from private.invite_attempts a
   where a.user_id = v_uid
     and a.attempted_at < now() - c_window;

  select count(*), min(a.attempted_at)
    into v_failures, v_oldest
  from private.invite_attempts a
  where a.user_id = v_uid
    and a.attempted_at >= now() - c_window;

  if v_failures >= c_max_failures then
    return private.join_family_result(
      'rate_limited',
      null,
      greatest(1, ceil(extract(epoch from (v_oldest + c_window - now())))::integer)
    );
  end if;

  v_code := private.normalize_invite_code(p_code);
  if v_code !~ '^[0-9A-HJKMNP-TV-Z]{8}$' then
    return private.join_family_result('invalid_format');
  end if;

  select * into v_invite
  from public.family_invites i
  where i.code = v_code
  for update;

  if not found then
    insert into private.invite_attempts (user_id, reason) values (v_uid, 'invalid_code');
    return private.join_family_result('invalid_code');
  end if;

  -- Idempotent: wer schon Mitglied ist, bekommt einfach die Familie zurück.
  if exists (
    select 1 from public.family_members m
    where m.family_id = v_invite.family_id and m.user_id = v_uid
  ) then
    return private.join_family_result('already_member', v_invite.family_id);
  end if;

  if v_invite.revoked_at is not null then
    insert into private.invite_attempts (user_id, reason) values (v_uid, 'revoked');
    return private.join_family_result('revoked');
  end if;

  if v_invite.expires_at <= now() then
    insert into private.invite_attempts (user_id, reason) values (v_uid, 'expired');
    return private.join_family_result('expired');
  end if;

  insert into public.family_members (family_id, user_id, role)
  values (v_invite.family_id, v_uid, 'member')
  on conflict (family_id, user_id) do nothing;

  update public.family_invites i
     set use_count = i.use_count + 1
   where i.id = v_invite.id;

  return private.join_family_result('joined', v_invite.family_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- update_family(family_id, name, color_hex, task_visibility)
-- Braucht Recht „manage_family“. null = unverändert.
-- ---------------------------------------------------------------------------

create function public.update_family(
  p_family_id uuid,
  p_name text default null,
  p_color_hex text default null,
  p_task_visibility public.task_visibility default null
)
returns public.families
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family public.families;
begin
  perform private.require_uid();
  perform private.require_member(p_family_id);
  if not private.has_family_permission(p_family_id, 'manage_family') then
    perform private.raise_app_error('permission_denied_manage_family');
  end if;

  if p_name is not null and char_length(btrim(p_name)) not between 1 and 60 then
    perform private.raise_app_error('invalid_family_name');
  end if;
  if p_color_hex is not null and p_color_hex !~ '^#[0-9A-Fa-f]{6}$' then
    perform private.raise_app_error('invalid_color');
  end if;

  update public.families f
     set name            = coalesce(btrim(p_name), f.name),
         color_hex       = coalesce(upper(p_color_hex), f.color_hex),
         task_visibility = coalesce(p_task_visibility, f.task_visibility)
   where f.id = p_family_id
  returning * into v_family;

  return v_family;
end;
$$;

-- ---------------------------------------------------------------------------
-- set_family_permissions(family_id, …): nur Admin. null = unverändert.
-- ---------------------------------------------------------------------------

create function public.set_family_permissions(
  p_family_id uuid,
  p_members_can_invite boolean default null,
  p_members_can_manage_family boolean default null,
  p_members_can_remove_members boolean default null
)
returns public.families
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family public.families;
begin
  perform private.require_uid();
  if private.require_member(p_family_id) <> 'admin' then
    perform private.raise_app_error('admin_required');
  end if;

  update public.families f
     set members_can_invite         = coalesce(p_members_can_invite, f.members_can_invite),
         members_can_manage_family  = coalesce(p_members_can_manage_family, f.members_can_manage_family),
         members_can_remove_members = coalesce(p_members_can_remove_members, f.members_can_remove_members)
   where f.id = p_family_id
  returning * into v_family;

  return v_family;
end;
$$;

-- ---------------------------------------------------------------------------
-- set_member_role(family_id, user_id, role): nur Admin; letzter Admin bleibt.
-- ---------------------------------------------------------------------------

create function public.set_member_role(
  p_family_id uuid,
  p_user_id uuid,
  p_role public.family_role
)
returns public.family_members
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.family_members;
  v_admins integer;
begin
  perform private.require_uid();
  perform private.require_member(p_family_id);

  -- Rollenänderungen pro Familie serialisieren (Schutz des letzten Admins).
  perform 1 from public.families f where f.id = p_family_id for update;

  if private.family_role(p_family_id) is distinct from 'admin' then
    perform private.raise_app_error('admin_required');
  end if;
  if p_role is null then
    perform private.raise_app_error('invalid_role');
  end if;

  select * into v_member
  from public.family_members m
  where m.family_id = p_family_id and m.user_id = p_user_id;

  if not found then
    perform private.raise_app_error('member_not_found');
  end if;
  if v_member.role = p_role then
    return v_member;
  end if;

  if v_member.role = 'admin' and p_role = 'member' then
    select count(*) into v_admins
    from public.family_members m
    where m.family_id = p_family_id and m.role = 'admin';
    if v_admins <= 1 then
      perform private.raise_app_error('last_admin');
    end if;
  end if;

  update public.family_members m
     set role = p_role
   where m.family_id = p_family_id and m.user_id = p_user_id
  returning * into v_member;

  return v_member;
end;
$$;

-- ---------------------------------------------------------------------------
-- leave_family(family_id)
-- Letzter Admin darf nicht gehen, solange andere Mitglieder da sind.
-- Geht die letzte Person, wird die Familie gelöscht.
-- Rückgabe: 'left' | 'family_deleted'
-- ---------------------------------------------------------------------------

create function public.leave_family(p_family_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid := private.require_uid();
  v_role         public.family_role;
  v_others       integer;
  v_other_admins integer;
begin
  perform private.require_member(p_family_id);

  perform 1 from public.families f where f.id = p_family_id for update;

  -- Nach dem Sperren erneut lesen (Stand kann sich geändert haben).
  v_role := private.require_member(p_family_id);

  select count(*),
         count(*) filter (where m.role = 'admin')
    into v_others, v_other_admins
  from public.family_members m
  where m.family_id = p_family_id and m.user_id <> v_uid;

  if v_others = 0 then
    delete from public.families f where f.id = p_family_id;
    return 'family_deleted';
  end if;

  if v_role = 'admin' and v_other_admins = 0 then
    perform private.raise_app_error('last_admin');
  end if;

  delete from public.family_members m
   where m.family_id = p_family_id and m.user_id = v_uid;

  return 'left';
end;
$$;

-- ---------------------------------------------------------------------------
-- remove_member(family_id, user_id)
-- Sich selbst entfernen = leave_family. Andere entfernen braucht Recht
-- „remove_members“; Admins dürfen nur von Admins entfernt werden.
-- Rückgabe: 'removed' | 'left' | 'family_deleted'
-- ---------------------------------------------------------------------------

create function public.remove_member(p_family_id uuid, p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := private.require_uid();
  v_target_role public.family_role;
begin
  if p_user_id = v_uid then
    return public.leave_family(p_family_id);
  end if;

  perform private.require_member(p_family_id);

  perform 1 from public.families f where f.id = p_family_id for update;

  if not private.has_family_permission(p_family_id, 'remove_members') then
    perform private.raise_app_error('permission_denied_remove_members');
  end if;

  select m.role into v_target_role
  from public.family_members m
  where m.family_id = p_family_id and m.user_id = p_user_id;

  if v_target_role is null then
    perform private.raise_app_error('member_not_found');
  end if;
  if v_target_role = 'admin' and private.family_role(p_family_id) <> 'admin' then
    perform private.raise_app_error('admin_required_to_remove_admin');
  end if;

  delete from public.family_members m
   where m.family_id = p_family_id and m.user_id = p_user_id;

  return 'removed';
end;
$$;

-- ---------------------------------------------------------------------------
-- update_profile(display_name, avatar_path): nur das eigene Profil.
-- null = unverändert; avatar_path = '' entfernt das Profilbild.
-- ---------------------------------------------------------------------------

create function public.update_profile(
  p_display_name text default null,
  p_avatar_path text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := private.require_uid();
  v_profile public.profiles;
begin
  if p_display_name is not null and char_length(btrim(p_display_name)) not between 1 and 80 then
    perform private.raise_app_error('invalid_display_name');
  end if;

  if p_avatar_path is not null and p_avatar_path <> ''
     and p_avatar_path !~ ('^' || v_uid::text || '/[A-Za-z0-9][A-Za-z0-9._-]{0,199}$') then
    perform private.raise_app_error('invalid_avatar_path');
  end if;

  update public.profiles p
     set display_name = coalesce(btrim(p_display_name), p.display_name),
         avatar_path  = case
                          when p_avatar_path is null then p.avatar_path
                          when p_avatar_path = ''    then null
                          else p_avatar_path
                        end
   where p.id = v_uid
  returning * into v_profile;

  if not found then
    perform private.raise_app_error('profile_not_found');
  end if;

  return v_profile;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rechte: nur authenticated darf die RPCs ausführen.
-- ---------------------------------------------------------------------------

revoke execute on function public.create_family(text, text) from public, anon, service_role;
revoke execute on function public.create_invite(uuid) from public, anon, service_role;
revoke execute on function public.revoke_invite(uuid) from public, anon, service_role;
revoke execute on function public.join_family(text) from public, anon, service_role;
revoke execute on function public.update_family(uuid, text, text, public.task_visibility) from public, anon, service_role;
revoke execute on function public.set_family_permissions(uuid, boolean, boolean, boolean) from public, anon, service_role;
revoke execute on function public.set_member_role(uuid, uuid, public.family_role) from public, anon, service_role;
revoke execute on function public.leave_family(uuid) from public, anon, service_role;
revoke execute on function public.remove_member(uuid, uuid) from public, anon, service_role;
revoke execute on function public.update_profile(text, text) from public, anon, service_role;

grant execute on function public.create_family(text, text) to authenticated;
grant execute on function public.create_invite(uuid) to authenticated;
grant execute on function public.revoke_invite(uuid) to authenticated;
grant execute on function public.join_family(text) to authenticated;
grant execute on function public.update_family(uuid, text, text, public.task_visibility) to authenticated;
grant execute on function public.set_family_permissions(uuid, boolean, boolean, boolean) to authenticated;
grant execute on function public.set_member_role(uuid, uuid, public.family_role) to authenticated;
grant execute on function public.leave_family(uuid) to authenticated;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
grant execute on function public.update_profile(text, text) to authenticated;
