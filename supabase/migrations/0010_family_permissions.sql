-- 0010_family_permissions
-- Familienrechte und Konto (Phase 9, Entscheidung E4 vom 2026-10-21).
--
-- Admins können für normale Mitglieder einschränken (Standard: alles erlaubt):
--   einladen · Familie bearbeiten · Mitglieder entfernen (seit 0002/0004) und neu
--   Aufgaben anlegen · Aufgaben bearbeiten · Aufgaben löschen und wiederherstellen.
-- Abhaken und Rückgängig bleiben immer erlaubt (zugewiesene Personen müssen erledigen können).
-- Abweichung vom Guide (dort dürfen alle Mitglieder Aufgaben anlegen/bearbeiten) auf Wunsch des Nutzers.
--
-- Außerdem: delete_family (nur Admin) und prepare_account_deletion (nur service_role, für die
-- Edge Function account-delete).

-- ---------------------------------------------------------------------------
-- Neue Schalter
-- ---------------------------------------------------------------------------

alter table public.families
  add column members_can_create_tasks boolean not null default true,
  add column members_can_edit_tasks   boolean not null default true,
  add column members_can_delete_tasks boolean not null default true;

create or replace function private.has_family_permission(p_family_id uuid, p_permission text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role   public.family_role;
  v_family public.families%rowtype;
begin
  if p_permission not in ('invite', 'manage_family', 'remove_members',
                          'create_tasks', 'edit_tasks', 'delete_tasks') then
    raise exception 'Unbekanntes Familienrecht: %', p_permission
      using errcode = '22023';
  end if;

  select m.role into v_role
  from public.family_members m
  where m.family_id = p_family_id
    and m.user_id = (select auth.uid());

  if v_role is null then
    return false;
  end if;
  if v_role = 'admin' then
    return true;
  end if;

  select * into v_family from public.families f where f.id = p_family_id;

  return case p_permission
    when 'invite'         then v_family.members_can_invite
    when 'manage_family'  then v_family.members_can_manage_family
    when 'remove_members' then v_family.members_can_remove_members
    when 'create_tasks'   then v_family.members_can_create_tasks
    when 'edit_tasks'     then v_family.members_can_edit_tasks
    when 'delete_tasks'   then v_family.members_can_delete_tasks
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fehlerkatalog erweitern
-- ---------------------------------------------------------------------------

create or replace function private.raise_app_error(p_key text)
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
    ('invite_code_generation_failed',   'P0001', 'Es konnte kein eindeutiger Einladungscode erzeugt werden. Bitte erneut versuchen.'),
    ('invalid_task_title',              '22023', 'Der Titel muss 1 bis 200 Zeichen lang sein.'),
    ('invalid_task_description',        '22023', 'Die Beschreibung darf höchstens 4000 Zeichen lang sein.'),
    ('invalid_start',                   '22023', 'Eine Uhrzeit braucht auch ein Datum.'),
    ('invalid_timezone',                '22023', 'Unbekannte Zeitzone.'),
    ('invalid_completion_mode',         '22023', 'Bitte wähle eine Erledigungsart.'),
    ('assignees_required',              '22023', 'Bitte weise mindestens eine Person zu.'),
    ('assignee_not_member',             '22023', 'Zugewiesene Personen müssen Mitglied der Familie sein.'),
    ('too_many_images',                 '22023', 'Eine Aufgabe kann höchstens 10 Bilder haben.'),
    ('invalid_image',                   '22023', 'Ein Bild wurde nicht vollständig hochgeladen. Bitte versuche es erneut.'),
    ('task_not_found',                  'P0002', 'Aufgabe nicht gefunden oder für dich nicht sichtbar.'),
    ('task_conflict',                   'P0001', 'Die Aufgabe wurde inzwischen von jemand anderem geändert. Bitte öffne sie neu.'),
    ('task_closed',                     'P0001', 'Erledigte oder gelöschte Aufgaben können nicht bearbeitet werden.'),
    ('completion_mode_locked',          'P0001', 'Die Erledigungsart lässt sich nicht mehr ändern, weil schon jemand abgehakt hat.'),
    ('not_allowed_to_complete',         '42501', 'Nur zugewiesene Personen oder wer die Aufgabe erstellt hat, dürfen sie abhaken.'),
    ('invalid_scope',                   '22023', 'Unbekannte Aktion.'),
    ('invalid_recurrence',              '22023', 'Bitte wähle für die Wiederholung mindestens einen Wochentag bzw. Monatstag.'),
    ('recurrence_requires_date',        '22023', 'Eine wiederkehrende Aufgabe braucht ein Startdatum.'),
    ('not_an_occurrence',               '22023', 'Diese Aufgabe gehört zu keiner Serie.'),
    ('series_not_found',                'P0002', 'Serie nicht gefunden oder für dich nicht sichtbar.'),
    ('series_deleted',                  'P0001', 'Die Serie wurde gelöscht. Stelle sie zuerst im Verlauf wieder her.'),
    ('restore_series_instead',          'P0001', 'Dieses Vorkommen wurde mit der ganzen Serie gelöscht. Stelle die Serie im Verlauf wieder her.'),
    ('series_deletion_not_found',       'P0002', 'Dieser Verlaufseintrag existiert nicht mehr.'),
    ('invalid_range',                   '22023', 'Der Zeitraum ist zu groß oder ungültig.'),
    ('permission_denied_create_tasks',  '42501', 'In dieser Familie dürfen nur Admins Aufgaben anlegen.'),
    ('permission_denied_edit_tasks',    '42501', 'In dieser Familie dürfen nur Admins Aufgaben bearbeiten.'),
    ('permission_denied_delete_tasks',  '42501', 'In dieser Familie dürfen nur Admins Aufgaben löschen oder wiederherstellen.')
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

revoke execute on function private.raise_app_error(text) from public, anon, authenticated;

-- Wirft den passenden Fehler, wenn das Aufgabenrecht fehlt.
create function private.require_task_permission(p_family_id uuid, p_permission text)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not private.has_family_permission(p_family_id, p_permission) then
    perform private.raise_app_error('permission_denied_' || p_permission);
  end if;
end;
$$;

revoke execute on function private.require_task_permission(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- set_family_permissions: alle sechs Schalter (nur Admin); null = unverändert.
-- ---------------------------------------------------------------------------

drop function public.set_family_permissions(uuid, boolean, boolean, boolean);

create function public.set_family_permissions(
  p_family_id uuid,
  p_members_can_invite boolean default null,
  p_members_can_manage_family boolean default null,
  p_members_can_remove_members boolean default null,
  p_members_can_create_tasks boolean default null,
  p_members_can_edit_tasks boolean default null,
  p_members_can_delete_tasks boolean default null
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
         members_can_remove_members = coalesce(p_members_can_remove_members, f.members_can_remove_members),
         members_can_create_tasks   = coalesce(p_members_can_create_tasks, f.members_can_create_tasks),
         members_can_edit_tasks     = coalesce(p_members_can_edit_tasks, f.members_can_edit_tasks),
         members_can_delete_tasks   = coalesce(p_members_can_delete_tasks, f.members_can_delete_tasks)
   where f.id = p_family_id
  returning * into v_family;

  return v_family;
end;
$$;

revoke execute on function public.set_family_permissions(uuid, boolean, boolean, boolean, boolean, boolean, boolean)
  from public, anon, service_role;
grant execute on function public.set_family_permissions(uuid, boolean, boolean, boolean, boolean, boolean, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Aufgaben-RPCs: unveränderter Inhalt aus 0007/0009, ergänzt um die Rechteprüfung.
-- ---------------------------------------------------------------------------

create or replace function public.create_task(
  p_family_id uuid,
  p_title text,
  p_completion_mode public.completion_mode,
  p_assignee_ids uuid[],
  p_description text default null,
  p_start_date date default null,
  p_start_time time default null,
  p_timezone text default 'Europe/Berlin',
  p_images jsonb default '[]'::jsonb
)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := private.require_uid();
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_assignees   uuid[];
  v_task        public.tasks;
begin
  perform private.require_member(p_family_id);
  perform private.require_task_permission(p_family_id, 'create_tasks');
  select coalesce(array_agg(distinct a), '{}') into v_assignees from unnest(p_assignee_ids) as a;
  perform private.validate_task_input(p_family_id, p_title, v_description, p_start_date, p_start_time,
                                      p_timezone, p_completion_mode, v_assignees);

  insert into public.tasks (family_id, created_by, title, description, start_date, start_time, timezone, completion_mode)
  values (p_family_id, v_uid, btrim(p_title), v_description, p_start_date, p_start_time, p_timezone, p_completion_mode)
  returning * into v_task;

  insert into public.task_assignees (task_id, user_id, assigned_by)
  select v_task.id, a, v_uid from unnest(v_assignees) as a;

  perform private.set_task_images(v_task.id, p_family_id, p_images);

  return v_task;
end;
$$;

create or replace function public.create_recurring_task(
  p_family_id uuid,
  p_title text,
  p_completion_mode public.completion_mode,
  p_assignee_ids uuid[],
  p_freq public.recurrence_freq,
  p_start_date date,
  p_weekdays smallint[] default '{}',
  p_month_days smallint[] default '{}',
  p_description text default null,
  p_start_time time default null,
  p_timezone text default 'Europe/Berlin',
  p_images jsonb default '[]'::jsonb
)
returns public.task_series
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := private.require_uid();
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_assignees   uuid[];
  v_weekdays    smallint[];
  v_month_days  smallint[];
  v_today       date;
  v_series      public.task_series;
begin
  perform private.require_member(p_family_id);
  perform private.require_task_permission(p_family_id, 'create_tasks');
  if p_start_date is null then
    perform private.raise_app_error('recurrence_requires_date');
  end if;
  select coalesce(array_agg(distinct a), '{}') into v_assignees from unnest(p_assignee_ids) as a;
  perform private.validate_task_input(p_family_id, p_title, v_description, p_start_date, p_start_time,
                                      p_timezone, p_completion_mode, v_assignees);
  select r.weekdays, r.month_days into v_weekdays, v_month_days
  from private.normalize_recurrence(p_freq, p_weekdays, p_month_days) as r;

  v_today := (now() at time zone p_timezone)::date;

  insert into public.task_series (family_id, created_by, title, description, completion_mode, freq,
                                  weekdays, month_days, start_date, start_time, timezone, generated_until)
  values (p_family_id, v_uid, btrim(p_title), v_description, p_completion_mode, p_freq,
          v_weekdays, v_month_days, p_start_date, p_start_time, p_timezone,
          case when p_start_date < v_today then v_today - 1 end)
  returning * into v_series;

  insert into public.series_assignees (series_id, user_id, assigned_by)
  select v_series.id, a, v_uid from unnest(v_assignees) as a;

  perform private.set_series_images(v_series.id, p_family_id, p_images);
  perform private.generate_series_occurrences(v_series.id);

  select * into v_series from public.task_series s where s.id = v_series.id;
  return v_series;
end;
$$;

create or replace function public.update_task(
  p_task_id uuid,
  p_expected_version integer,
  p_title text,
  p_completion_mode public.completion_mode,
  p_assignee_ids uuid[],
  p_description text default null,
  p_start_date date default null,
  p_start_time time default null,
  p_timezone text default 'Europe/Berlin',
  p_images jsonb default '[]'::jsonb
)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_assignees   uuid[];
  v_task        public.tasks;
begin
  perform private.require_uid();
  v_task := private.lock_visible_task(p_task_id);
  perform private.require_task_permission(v_task.family_id, 'edit_tasks');
  if v_task.deleted_at is not null or v_task.completed_at is not null then
    perform private.raise_app_error('task_closed');
  end if;
  if p_expected_version is distinct from v_task.version then
    perform private.raise_app_error('task_conflict');
  end if;

  select coalesce(array_agg(distinct a), '{}') into v_assignees from unnest(p_assignee_ids) as a;
  perform private.validate_task_input(v_task.family_id, p_title, v_description, p_start_date, p_start_time,
                                      p_timezone, p_completion_mode, v_assignees);

  if p_completion_mode <> v_task.completion_mode
     and exists (select 1 from public.task_assignees a where a.task_id = p_task_id and a.completed_at is not null) then
    perform private.raise_app_error('completion_mode_locked');
  end if;

  return private.write_task_content(p_task_id, p_title, v_description, p_start_date, p_start_time, p_timezone,
                                    p_completion_mode, v_assignees, p_images, v_task.series_id is not null);
end;
$$;

create or replace function public.update_series_from(
  p_task_id uuid,
  p_expected_version integer,
  p_title text,
  p_completion_mode public.completion_mode,
  p_assignee_ids uuid[],
  p_freq public.recurrence_freq,
  p_start_date date,
  p_weekdays smallint[] default '{}',
  p_month_days smallint[] default '{}',
  p_description text default null,
  p_start_time time default null,
  p_timezone text default 'Europe/Berlin',
  p_images jsonb default '[]'::jsonb
)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid := private.require_uid();
  v_description  text := nullif(btrim(coalesce(p_description, '')), '');
  v_assignees    uuid[];
  v_weekdays     smallint[];
  v_month_days   smallint[];
  v_task         public.tasks;
  v_series       public.task_series;
  v_rule_changed boolean;
  v_today        date;
  v_later        public.tasks;
begin
  v_task := private.lock_visible_task(p_task_id);
  perform private.require_task_permission(v_task.family_id, 'edit_tasks');
  if v_task.series_id is null then
    perform private.raise_app_error('not_an_occurrence');
  end if;
  if v_task.deleted_at is not null or v_task.completed_at is not null then
    perform private.raise_app_error('task_closed');
  end if;
  if p_expected_version is distinct from v_task.version then
    perform private.raise_app_error('task_conflict');
  end if;

  select * into v_series from public.task_series s where s.id = v_task.series_id for update;
  if not found then
    perform private.raise_app_error('series_not_found');
  end if;
  if v_series.deleted_at is not null then
    perform private.raise_app_error('series_deleted');
  end if;

  if p_start_date is null then
    perform private.raise_app_error('recurrence_requires_date');
  end if;
  select coalesce(array_agg(distinct a), '{}') into v_assignees from unnest(p_assignee_ids) as a;
  perform private.validate_task_input(v_task.family_id, p_title, v_description, p_start_date, p_start_time,
                                      p_timezone, p_completion_mode, v_assignees);
  select r.weekdays, r.month_days into v_weekdays, v_month_days
  from private.normalize_recurrence(p_freq, p_weekdays, p_month_days) as r;

  if p_completion_mode <> v_task.completion_mode
     and exists (select 1 from public.task_assignees a where a.task_id = p_task_id and a.completed_at is not null) then
    perform private.raise_app_error('completion_mode_locked');
  end if;

  v_rule_changed := p_freq <> v_series.freq
                    or v_weekdays <> v_series.weekdays
                    or v_month_days <> v_series.month_days;
  v_today := (now() at time zone p_timezone)::date;

  -- Serie
  update public.task_series s
     set title           = btrim(p_title),
         description     = v_description,
         completion_mode = p_completion_mode,
         freq            = p_freq,
         weekdays        = v_weekdays,
         month_days      = v_month_days,
         start_time      = p_start_time,
         timezone        = p_timezone,
         version         = s.version + 1
   where s.id = v_series.id;

  delete from public.series_assignees a
   where a.series_id = v_series.id
     and not (a.user_id = any (v_assignees));
  insert into public.series_assignees (series_id, user_id, assigned_by)
  select v_series.id, a, v_uid from unnest(v_assignees) as a
  on conflict (series_id, user_id) do nothing;

  perform private.set_series_images(v_series.id, v_task.family_id, p_images);

  -- Gewähltes Vorkommen
  v_task := private.write_task_content(p_task_id, p_title, v_description, p_start_date, p_start_time, p_timezone,
                                       p_completion_mode, v_assignees, p_images, false);

  -- Spätere, noch unberührte Vorkommen
  for v_later in
    select t.*
    from public.tasks t
    where t.series_id = v_series.id
      and t.occurrence_date > v_task.occurrence_date
      and not t.is_detached
      and t.completed_at is null
      and t.deleted_at is null
      and not exists (select 1 from public.task_assignees a where a.task_id = t.id and a.completed_at is not null)
    order by t.occurrence_date
    for update
  loop
    if v_rule_changed and v_later.occurrence_date > v_today then
      delete from public.tasks t where t.id = v_later.id;
    else
      perform private.write_task_content(v_later.id, p_title, v_description, v_later.start_date, p_start_time,
                                         p_timezone, p_completion_mode, v_assignees, p_images, false);
    end if;
  end loop;

  -- Neue Regel gilt für alles nach heute bzw. nach dem gewählten Vorkommen.
  if v_rule_changed then
    update public.task_series s
       set generated_until = greatest(
             v_task.occurrence_date,
             v_today,
             (select max(t.occurrence_date) from public.tasks t where t.series_id = s.id)
           )
     where s.id = v_series.id;
  end if;

  perform private.generate_series_occurrences(v_series.id);

  select * into v_task from public.tasks t where t.id = p_task_id;
  return v_task;
end;
$$;

create or replace function public.delete_task(p_task_id uuid)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := private.require_uid();
  v_task public.tasks;
begin
  v_task := private.lock_visible_task(p_task_id);
  perform private.require_task_permission(v_task.family_id, 'delete_tasks');
  if v_task.deleted_at is not null then
    return v_task;
  end if;
  update public.tasks t
     set deleted_at = now(), deleted_by = v_uid, version = t.version + 1
   where t.id = p_task_id
  returning * into v_task;
  return v_task;
end;
$$;

create or replace function public.delete_series(p_task_id uuid)
returns public.series_deletions
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := private.require_uid();
  v_task     public.tasks;
  v_series   public.task_series;
  v_deletion public.series_deletions;
begin
  v_task := private.lock_visible_task(p_task_id);
  perform private.require_task_permission(v_task.family_id, 'delete_tasks');
  if v_task.series_id is null then
    perform private.raise_app_error('not_an_occurrence');
  end if;

  select * into v_series from public.task_series s where s.id = v_task.series_id for update;
  if not found then
    perform private.raise_app_error('series_not_found');
  end if;

  if v_series.deleted_at is not null then
    select * into v_deletion
    from public.series_deletions d
    where d.series_id = v_series.id and d.restored_at is null
    order by d.deleted_at desc
    limit 1;
    return v_deletion;
  end if;

  insert into public.series_deletions (series_id, family_id, deleted_by)
  values (v_series.id, v_series.family_id, v_uid)
  returning * into v_deletion;

  update public.task_series s
     set deleted_at = v_deletion.deleted_at, deleted_by = v_uid, version = s.version + 1
   where s.id = v_series.id;

  update public.tasks t
     set deleted_at = v_deletion.deleted_at,
         deleted_by = v_uid,
         deleted_by_series_op = v_deletion.id,
         version = t.version + 1
   where t.series_id = v_series.id
     and t.completed_at is null
     and t.deleted_at is null;

  return v_deletion;
end;
$$;

create or replace function public.restore_task(p_task_id uuid)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task public.tasks;
begin
  perform private.require_uid();
  v_task := private.lock_visible_task(p_task_id);
  perform private.require_task_permission(v_task.family_id, 'delete_tasks');
  if v_task.deleted_at is null then
    return v_task;
  end if;
  if v_task.deleted_by_series_op is not null then
    perform private.raise_app_error('restore_series_instead');
  end if;
  update public.tasks t
     set deleted_at = null, deleted_by = null, version = t.version + 1
   where t.id = p_task_id
  returning * into v_task;
  return v_task;
end;
$$;

create or replace function public.restore_series_deletion(p_deletion_id uuid)
returns public.task_series
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := private.require_uid();
  v_deletion public.series_deletions;
  v_series   public.task_series;
begin
  select * into v_deletion from public.series_deletions d where d.id = p_deletion_id for update;
  if not found or not private.can_view_series(v_deletion.series_id) then
    perform private.raise_app_error('series_deletion_not_found');
  end if;
  perform private.require_task_permission(v_deletion.family_id, 'delete_tasks');

  select * into v_series from public.task_series s where s.id = v_deletion.series_id for update;
  if v_deletion.restored_at is not null then
    return v_series;
  end if;

  update public.tasks t
     set deleted_at = null, deleted_by = null, deleted_by_series_op = null, version = t.version + 1
   where t.deleted_by_series_op = v_deletion.id;

  update public.task_series s
     set deleted_at  = null,
         deleted_by  = null,
         resume_from = (now() at time zone s.timezone)::date,
         version     = s.version + 1
   where s.id = v_series.id;

  update public.series_deletions d
     set restored_at = now(), restored_by = v_uid
   where d.id = v_deletion.id;

  perform private.generate_series_occurrences(v_series.id);

  select * into v_series from public.task_series s where s.id = v_series.id;
  return v_series;
end;
$$;

-- ---------------------------------------------------------------------------
-- delete_family: nur Admin. Alles Zugehörige folgt per Cascade; verwaiste Bilddateien
-- entfernt die tägliche Bereinigung (0008/0009) über die Storage-API.
-- ---------------------------------------------------------------------------

create function public.delete_family(p_family_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_uid();
  if private.require_member(p_family_id) <> 'admin' then
    perform private.raise_app_error('admin_required');
  end if;
  delete from public.families f where f.id = p_family_id;
end;
$$;

revoke execute on function public.delete_family(uuid) from public, anon, service_role;
grant execute on function public.delete_family(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- prepare_account_deletion (nur service_role, aufgerufen von der Edge Function account-delete
-- nach Prüfung des Nutzer-JWT):
--   * Familien, in denen der Nutzer allein ist, werden gelöscht.
--   * Ist er einziger Admin einer Familie mit weiteren Mitgliedern, wird das am längsten
--     dabei befindliche andere Mitglied Admin (keine Familie bleibt ohne Admin).
--   * Aufgabenbilder, die er hochgeladen hat, bleiben für die Familie erhalten; der Besitz wird
--     gelöst (Supabase: Nutzer mit eigenen Storage-Objekten lassen sich nicht löschen).
--   * Rückgabe: Pfade seiner Profilbilder, die die Function über die Storage-API löscht.
-- Das Löschen des Auth-Nutzers selbst (auth.admin.deleteUser) übernimmt die Function; Profil,
-- Mitgliedschaften und Zuweisungen folgen per Cascade, „erstellt von“ wird null.
-- ---------------------------------------------------------------------------

create function public.prepare_account_deletion(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_family_id uuid;
  v_paths text[];
begin
  if p_user_id is null then
    raise exception using errcode = '22023', message = 'Nutzer fehlt.';
  end if;

  for v_family_id in
    select m.family_id from public.family_members m where m.user_id = p_user_id
  loop
    if not exists (
      select 1 from public.family_members o where o.family_id = v_family_id and o.user_id <> p_user_id
    ) then
      delete from public.families f where f.id = v_family_id;
    elsif not exists (
      select 1 from public.family_members a
      where a.family_id = v_family_id and a.user_id <> p_user_id and a.role = 'admin'
    ) and exists (
      select 1 from public.family_members me
      where me.family_id = v_family_id and me.user_id = p_user_id and me.role = 'admin'
    ) then
      update public.family_members m
         set role = 'admin'
       where m.family_id = v_family_id
         and m.user_id = (
           select o.user_id from public.family_members o
           where o.family_id = v_family_id and o.user_id <> p_user_id
           order by o.joined_at, o.user_id
           limit 1
         );
    end if;
  end loop;

  update storage.objects o
     set owner = null, owner_id = null
   where o.bucket_id = 'task-images'
     and o.owner_id = p_user_id::text;

  select coalesce(array_agg(o.name order by o.name), '{}')
    into v_paths
  from storage.objects o
  where o.bucket_id = 'avatars'
    and (storage.foldername(o.name))[1] = p_user_id::text;

  return jsonb_build_object('avatar_paths', to_jsonb(v_paths));
end;
$$;

revoke execute on function public.prepare_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.prepare_account_deletion(uuid) to service_role;
