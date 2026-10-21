-- 0009_recurrence
-- Wiederholungen (Phase 5): Regel (task_series) plus eigenständige Vorkommen (tasks mit series_id).
--
-- Regeln (Guide, Abschnitt 4; Plan, Abschnitt 4):
--   * täglich, an Wochentagen (ISO 1 = Montag … 7 = Sonntag) oder an Monatstagen (1–31).
--   * E2: Fehlt ein Monatstag (z. B. 31. im April), zählt der letzte Tag des Monats; fallen mehrere
--     Monatstage auf denselben Tag, entsteht nur ein Vorkommen.
--   * Erzeugt werden alle Vorkommen bis heute (verpasste bleiben überfällig) und das nächste künftige.
--     Kein Nachholen vor dem Anlegen der Serie. generated_until ist die Wasserstandsmarke: Daten bis
--     dahin werden nie wieder erzeugt – auch nicht, wenn ein Vorkommen gelöscht oder bereinigt wurde.
--   * Bearbeiten „Nur dieses Vorkommen“ = update_task (markiert is_detached).
--     „Dieses und zukünftige“ = update_series_from: Serie bekommt den neuen Stand; spätere offene,
--     noch unberührte Vorkommen werden angepasst bzw. bei geänderter Regel neu geplant.
--     Erledigte oder schon angefangene Vorkommen bleiben unverändert.
--   * Serie löschen: ein Verlaufseintrag (series_deletions); offene Vorkommen werden mit
--     deleted_by_series_op markiert statt einzeln im Verlauf zu erscheinen. Erledigte bleiben.
--     Wiederherstellen aktiviert diese Vorkommen wieder; die Erzeugung läuft ab heute weiter
--     (resume_from), Termine aus der Löschphase werden nicht nachgeholt.

-- ---------------------------------------------------------------------------
-- Typen und Tabellen
-- ---------------------------------------------------------------------------

create type public.recurrence_freq as enum ('daily', 'weekly', 'monthly');

create table public.task_series (
  id               uuid primary key default gen_random_uuid(),
  family_id        uuid not null references public.families (id) on delete cascade,
  created_by       uuid references public.profiles (id) on delete set null,
  title            text not null check (char_length(btrim(title)) between 1 and 200),
  description      text check (description is null or char_length(description) between 1 and 4000),
  completion_mode  public.completion_mode not null,
  freq             public.recurrence_freq not null,
  weekdays         smallint[] not null default '{}',
  month_days       smallint[] not null default '{}',
  start_date       date not null,
  start_time       time,
  timezone         text not null default 'Europe/Berlin',
  generated_until  date,
  resume_from      date,
  deleted_at       timestamptz,
  deleted_by       uuid references public.profiles (id) on delete set null,
  version          integer not null default 1,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint task_series_rule_valid check (
    (freq = 'daily' and weekdays = '{}' and month_days = '{}')
    or (freq = 'weekly' and cardinality(weekdays) between 1 and 7
        and 1 <= all (weekdays) and 7 >= all (weekdays) and month_days = '{}')
    or (freq = 'monthly' and cardinality(month_days) between 1 and 31
        and 1 <= all (month_days) and 31 >= all (month_days) and weekdays = '{}')
  )
);

comment on column public.task_series.generated_until is
  'Letztes erzeugte Vorkommensdatum (Wasserstandsmarke); spätere Läufe beginnen danach.';
comment on column public.task_series.resume_from is
  'Nach dem Wiederherstellen einer gelöschten Serie: Erzeugung erst ab diesem Tag.';

create index task_series_family_id_idx on public.task_series (family_id);
create index task_series_created_by_idx on public.task_series (created_by);
create index task_series_deleted_by_idx on public.task_series (deleted_by);
create index task_series_active_idx on public.task_series (generated_until) where deleted_at is null;

create trigger task_series_set_updated_at
  before update on public.task_series
  for each row execute function private.set_updated_at();

create table public.series_assignees (
  series_id    uuid not null references public.task_series (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  assigned_by  uuid references public.profiles (id) on delete set null,
  assigned_at  timestamptz not null default now(),
  primary key (series_id, user_id)
);

create index series_assignees_user_id_idx on public.series_assignees (user_id);
create index series_assignees_assigned_by_idx on public.series_assignees (assigned_by);

create table public.series_image_links (
  series_id  uuid not null references public.task_series (id) on delete cascade,
  image_id   uuid not null references public.images (id) on delete cascade,
  position   smallint not null default 0 check (position >= 0),
  primary key (series_id, image_id)
);

create index series_image_links_image_id_idx on public.series_image_links (image_id);

-- Ein Verlaufseintrag pro Serien-Löschung.
create table public.series_deletions (
  id           uuid primary key default gen_random_uuid(),
  series_id    uuid not null references public.task_series (id) on delete cascade,
  family_id    uuid not null references public.families (id) on delete cascade,
  deleted_by   uuid references public.profiles (id) on delete set null,
  deleted_at   timestamptz not null default now(),
  restored_at  timestamptz,
  restored_by  uuid references public.profiles (id) on delete set null
);

create index series_deletions_series_id_idx on public.series_deletions (series_id);
create index series_deletions_family_id_idx on public.series_deletions (family_id);
create index series_deletions_deleted_by_idx on public.series_deletions (deleted_by);
create index series_deletions_restored_by_idx on public.series_deletions (restored_by);

-- Vorkommen an Serie und Löschvorgang binden. Wird eine Serie nach 30 Tagen endgültig entfernt,
-- bleiben erledigte Vorkommen als Einzelaufgaben mit ihrem occurrence_date erhalten.
alter table public.tasks drop constraint tasks_series_occurrence;
alter table public.tasks
  add constraint tasks_series_requires_occurrence check (series_id is null or occurrence_date is not null),
  add constraint tasks_series_id_fkey foreign key (series_id)
    references public.task_series (id) on delete set null,
  add constraint tasks_deleted_by_series_op_fkey foreign key (deleted_by_series_op)
    references public.series_deletions (id) on delete set null;

create index tasks_deleted_by_series_op_idx on public.tasks (deleted_by_series_op);

-- ---------------------------------------------------------------------------
-- Sichtbarkeit: wie bei Aufgaben (Mitglied UND (alle sichtbar ODER Ersteller ODER zugewiesen))
-- ---------------------------------------------------------------------------

create function private.my_assigned_series_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select a.series_id
  from public.series_assignees a
  where a.user_id = (select auth.uid());
$$;

create function private.can_view_series(p_series_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.task_series s
    join public.family_members m on m.family_id = s.family_id and m.user_id = (select auth.uid())
    join public.families f on f.id = s.family_id
    where s.id = p_series_id
      and (
        f.task_visibility = 'all'
        or s.created_by = (select auth.uid())
        or exists (
          select 1 from public.series_assignees a
          where a.series_id = s.id and a.user_id = (select auth.uid())
        )
      )
  );
$$;

-- Bilder: sichtbar über eine sichtbare Aufgabe oder eine sichtbare Serie.
create or replace function private.can_view_image(p_image_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.task_image_links l
    where l.image_id = p_image_id and private.can_view_task(l.task_id)
  ) or exists (
    select 1 from public.series_image_links l
    where l.image_id = p_image_id and private.can_view_series(l.series_id)
  );
$$;

create or replace function private.can_view_task_image_object(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.images i
    where (i.path = p_name or i.thumb_path = p_name)
      and private.can_view_image(i.id)
  );
$$;

revoke execute on function private.my_assigned_series_ids() from public, anon;
revoke execute on function private.can_view_series(uuid) from public, anon;
grant execute on function private.my_assigned_series_ids() to authenticated;
grant execute on function private.can_view_series(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS, Rechte, Lese-Policies
-- ---------------------------------------------------------------------------

alter table public.task_series        enable row level security;
alter table public.series_assignees   enable row level security;
alter table public.series_image_links enable row level security;
alter table public.series_deletions   enable row level security;

revoke all on table public.task_series        from anon, authenticated;
revoke all on table public.series_assignees   from anon, authenticated;
revoke all on table public.series_image_links from anon, authenticated;
revoke all on table public.series_deletions   from anon, authenticated;

grant select on table public.task_series        to authenticated;
grant select on table public.series_assignees   to authenticated;
grant select on table public.series_image_links to authenticated;
grant select on table public.series_deletions   to authenticated;

create policy "task_series_select_visible"
  on public.task_series
  for select
  to authenticated
  using (
    family_id = any (array (select private.my_family_ids()))
    and (
      family_id = any (array (select private.my_all_tasks_family_ids()))
      or created_by = (select auth.uid())
      or id = any (array (select private.my_assigned_series_ids()))
    )
  );

create policy "series_assignees_select_visible_series"
  on public.series_assignees
  for select
  to authenticated
  using (private.can_view_series(series_id));

create policy "series_image_links_select_visible_series"
  on public.series_image_links
  for select
  to authenticated
  using (private.can_view_series(series_id));

create policy "series_deletions_select_visible_series"
  on public.series_deletions
  for select
  to authenticated
  using (private.can_view_series(series_id));

-- ---------------------------------------------------------------------------
-- Fehlerkatalog erweitern (bestehende Schlüssel unverändert)
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
    ('invalid_range',                   '22023', 'Der Zeitraum ist zu groß oder ungültig.')
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

-- ---------------------------------------------------------------------------
-- Regel-Algorithmus (einziger Ort; genutzt von Erzeugung und Kalender-Projektion)
-- ---------------------------------------------------------------------------

-- Alle Tage in [p_from, p_to], die zur Regel passen, aufsteigend.
create function private.series_dates(
  p_freq public.recurrence_freq,
  p_weekdays smallint[],
  p_month_days smallint[],
  p_from date,
  p_to date
)
returns setof date
language sql
immutable
set search_path = ''
as $$
  select g.d::date
  from pg_catalog.generate_series(p_from::timestamp, p_to::timestamp, interval '1 day') as g(d)
  where p_freq = 'daily'
     or (p_freq = 'weekly' and extract(isodow from g.d)::smallint = any (p_weekdays))
     or (p_freq = 'monthly' and exists (
           select 1
           from unnest(p_month_days) as m(day)
           where least(
                   m.day::integer,
                   extract(day from date_trunc('month', g.d) + interval '1 month - 1 day')::integer
                 ) = extract(day from g.d)::integer
         ))
  order by 1;
$$;

revoke execute on function private.series_dates(public.recurrence_freq, smallint[], smallint[], date, date)
  from public, anon, authenticated;

-- Prüft die Regel und liefert sortierte, eindeutige Tage (täglich: beide leer).
create function private.normalize_recurrence(
  p_freq public.recurrence_freq,
  p_weekdays smallint[],
  p_month_days smallint[],
  out weekdays smallint[],
  out month_days smallint[]
)
language plpgsql
immutable
set search_path = ''
as $$
begin
  select coalesce(array_agg(distinct d order by d), '{}') into weekdays from unnest(p_weekdays) as d;
  select coalesce(array_agg(distinct d order by d), '{}') into month_days from unnest(p_month_days) as d;

  if p_freq is null then
    perform private.raise_app_error('invalid_recurrence');
  elsif p_freq = 'daily' then
    weekdays := '{}';
    month_days := '{}';
  elsif p_freq = 'weekly' then
    if cardinality(weekdays) = 0 or not (1 <= all (weekdays) and 7 >= all (weekdays)) then
      perform private.raise_app_error('invalid_recurrence');
    end if;
    month_days := '{}';
  else
    if cardinality(month_days) = 0 or not (1 <= all (month_days) and 31 >= all (month_days)) then
      perform private.raise_app_error('invalid_recurrence');
    end if;
    weekdays := '{}';
  end if;
end;
$$;

revoke execute on function private.normalize_recurrence(public.recurrence_freq, smallint[], smallint[])
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Bilder: gemeinsame Prüfung für Aufgaben und Serien
-- ---------------------------------------------------------------------------

-- Prüft die Bildliste, legt neue Bildzeilen an und liefert die IDs in Reihenfolge.
-- p_images: [{"id": uuid, "width": int, "height": int}, …]. Neue Bilder müssen vom Aufrufer
-- bereits nach {family_id}/{id}.jpg und …_thumb.jpg hochgeladen sein.
create function private.ensure_images(p_family_id uuid, p_images jsonb)
returns uuid[]
language plpgsql
set search_path = ''
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_item      jsonb;
  v_image_id  uuid;
  v_path      text;
  v_thumb     text;
  v_width     integer;
  v_height    integer;
  v_ids       uuid[] := '{}';
begin
  if p_images is null or jsonb_typeof(p_images) <> 'array' then
    p_images := '[]'::jsonb;
  end if;
  if jsonb_array_length(p_images) > 10 then
    perform private.raise_app_error('too_many_images');
  end if;

  for v_item in select value from jsonb_array_elements(p_images) loop
    begin
      v_image_id := (v_item ->> 'id')::uuid;
    exception when others then
      perform private.raise_app_error('invalid_image');
    end;
    if v_image_id is null or v_image_id = any (v_ids) then
      perform private.raise_app_error('invalid_image');
    end if;

    if not exists (select 1 from public.images i where i.id = v_image_id and i.family_id = p_family_id) then
      v_path  := p_family_id::text || '/' || v_image_id::text || '.jpg';
      v_thumb := p_family_id::text || '/' || v_image_id::text || '_thumb.jpg';
      begin
        v_width  := (v_item ->> 'width')::integer;
        v_height := (v_item ->> 'height')::integer;
      exception when others then
        perform private.raise_app_error('invalid_image');
      end;
      if coalesce(v_width, 0) <= 0 or coalesce(v_height, 0) <= 0
         or exists (select 1 from public.images i where i.id = v_image_id)
         or (
           select count(*) from storage.objects o
           where o.bucket_id = 'task-images'
             and o.name in (v_path, v_thumb)
             and coalesce(o.owner_id, o.owner::text) = v_uid::text
         ) <> 2 then
        perform private.raise_app_error('invalid_image');
      end if;
      insert into public.images (id, family_id, path, thumb_path, width, height, created_by)
      values (v_image_id, p_family_id, v_path, v_thumb, v_width, v_height, v_uid);
    end if;

    v_ids := v_ids || v_image_id;
  end loop;

  return v_ids;
end;
$$;

revoke execute on function private.ensure_images(uuid, jsonb) from public, anon, authenticated;

create or replace function private.set_task_images(p_task_id uuid, p_family_id uuid, p_images jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_ids uuid[] := private.ensure_images(p_family_id, p_images);
begin
  insert into public.task_image_links (task_id, image_id, position)
  select p_task_id, i.image_id, (i.ord - 1)::smallint
  from unnest(v_ids) with ordinality as i(image_id, ord)
  on conflict (task_id, image_id) do update set position = excluded.position;

  delete from public.task_image_links l
   where l.task_id = p_task_id
     and not (l.image_id = any (v_ids));
end;
$$;

revoke execute on function private.set_task_images(uuid, uuid, jsonb) from public, anon, authenticated;

create function private.set_series_images(p_series_id uuid, p_family_id uuid, p_images jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_ids uuid[] := private.ensure_images(p_family_id, p_images);
begin
  insert into public.series_image_links (series_id, image_id, position)
  select p_series_id, i.image_id, (i.ord - 1)::smallint
  from unnest(v_ids) with ordinality as i(image_id, ord)
  on conflict (series_id, image_id) do update set position = excluded.position;

  delete from public.series_image_links l
   where l.series_id = p_series_id
     and not (l.image_id = any (v_ids));
end;
$$;

revoke execute on function private.set_series_images(uuid, uuid, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Inhalt einer Aufgabe schreiben (update_task und update_series_from)
-- Zuweisungen abgleichen (bestehende behalten ihren Status), Bilder, Felder, Version.
-- Prüfungen (Sicht, Version, Eingaben) erledigt der Aufrufer.
-- ---------------------------------------------------------------------------

create function private.write_task_content(
  p_task_id uuid,
  p_title text,
  p_description text,
  p_start_date date,
  p_start_time time,
  p_timezone text,
  p_completion_mode public.completion_mode,
  p_assignee_ids uuid[],
  p_images jsonb,
  p_detach boolean
)
returns public.tasks
language plpgsql
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_task public.tasks;
begin
  select * into v_task from public.tasks t where t.id = p_task_id;

  delete from public.task_assignees a
   where a.task_id = p_task_id
     and not (a.user_id = any (p_assignee_ids));
  insert into public.task_assignees (task_id, user_id, assigned_by)
  select p_task_id, a, v_uid from unnest(p_assignee_ids) as a
  on conflict (task_id, user_id) do nothing;

  perform private.set_task_images(p_task_id, v_task.family_id, p_images);

  update public.tasks t
     set title           = btrim(p_title),
         description     = p_description,
         start_date      = p_start_date,
         start_time      = p_start_time,
         timezone        = p_timezone,
         completion_mode = p_completion_mode,
         is_detached     = t.is_detached or p_detach,
         version         = t.version + 1
   where t.id = p_task_id
  returning * into v_task;

  -- „Jede Person einzeln“: Haben nach dem Entfernen alle Übrigen erledigt, ist die Aufgabe komplett.
  if v_task.completion_mode = 'each'
     and not exists (select 1 from public.task_assignees a where a.task_id = p_task_id and a.completed_at is null) then
    update public.tasks t
       set completed_at      = (select max(a.completed_at) from public.task_assignees a where a.task_id = p_task_id),
           completed_by      = (select a.user_id from public.task_assignees a where a.task_id = p_task_id
                                order by a.completed_at desc limit 1),
           completion_source = 'assignee'
     where t.id = p_task_id
    returning * into v_task;
  end if;

  return v_task;
end;
$$;

revoke execute on function private.write_task_content(uuid, text, text, date, time, text, public.completion_mode, uuid[], jsonb, boolean)
  from public, anon, authenticated;

-- update_task: unverändertes Verhalten; bei Vorkommen bedeutet es „Nur dieses Vorkommen“
-- (is_detached = true, spätere Serienänderungen lassen es in Ruhe).
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

-- ---------------------------------------------------------------------------
-- Erzeugung (idempotent über unique (series_id, occurrence_date) und generated_until)
-- ---------------------------------------------------------------------------

create function private.generate_series_occurrences(p_series_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_series  public.task_series;
  v_today   date;
  v_from    date;
  v_dates   date[];
  v_next    date;
  v_date    date;
  v_task_id uuid;
  v_count   integer := 0;
begin
  select * into v_series from public.task_series s where s.id = p_series_id for update;
  if not found or v_series.deleted_at is not null then
    return 0;
  end if;

  v_today := (now() at time zone v_series.timezone)::date;
  -- greatest ignoriert NULL-Werte.
  v_from := greatest(v_series.start_date, v_series.resume_from, v_series.generated_until + 1);

  select coalesce(array_agg(d order by d), '{}') into v_dates
  from private.series_dates(v_series.freq, v_series.weekdays, v_series.month_days, v_from, v_today) as d;

  -- Dazu das nächste künftige Vorkommen, solange noch keines erzeugt ist.
  if v_series.generated_until is null or v_series.generated_until <= v_today then
    select d into v_next
    from private.series_dates(v_series.freq, v_series.weekdays, v_series.month_days,
                              greatest(v_from, v_today + 1), greatest(v_from, v_today + 1) + 62) as d
    limit 1;
    if v_next is not null then
      v_dates := v_dates || v_next;
    end if;
  end if;

  if cardinality(v_dates) = 0 then
    return 0;
  end if;

  foreach v_date in array v_dates loop
    v_task_id := null;
    insert into public.tasks (family_id, series_id, occurrence_date, created_by, title, description,
                              start_date, start_time, timezone, completion_mode)
    values (v_series.family_id, v_series.id, v_date, v_series.created_by, v_series.title, v_series.description,
            v_date, v_series.start_time, v_series.timezone, v_series.completion_mode)
    on conflict (series_id, occurrence_date) do nothing
    returning id into v_task_id;

    if v_task_id is not null then
      -- Nur Personen, die noch Mitglied sind.
      insert into public.task_assignees (task_id, user_id, assigned_by)
      select v_task_id, a.user_id, a.assigned_by
      from public.series_assignees a
      join public.family_members m on m.family_id = v_series.family_id and m.user_id = a.user_id
      where a.series_id = v_series.id;

      insert into public.task_image_links (task_id, image_id, position)
      select v_task_id, l.image_id, l.position
      from public.series_image_links l
      where l.series_id = v_series.id;

      v_count := v_count + 1;
    end if;
  end loop;

  update public.task_series s
     set generated_until = greatest(s.generated_until, v_dates[cardinality(v_dates)])
   where s.id = v_series.id;

  return v_count;
end;
$$;

revoke execute on function private.generate_series_occurrences(uuid) from public, anon, authenticated;

-- Für pg_cron: alle aktiven Serien, die noch etwas zu erzeugen haben.
create function private.generate_all_series_occurrences()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_series_id uuid;
  v_total     integer := 0;
begin
  for v_series_id in
    select s.id
    from public.task_series s
    where s.deleted_at is null
      and (s.generated_until is null or s.generated_until <= (now() at time zone s.timezone)::date)
    order by s.id
  loop
    v_total := v_total + private.generate_series_occurrences(v_series_id);
  end loop;
  return v_total;
end;
$$;

revoke execute on function private.generate_all_series_occurrences() from public, anon, authenticated;

select cron.schedule('familiar-generate-occurrences', '*/5 * * * *',
                     $$select private.generate_all_series_occurrences()$$);

-- ---------------------------------------------------------------------------
-- create_recurring_task: jedes Mitglied; legt die Serie an und erzeugt sofort die Vorkommen.
-- Liegt das Startdatum in der Vergangenheit, wird nichts nachgeholt (erstes Vorkommen ab heute).
-- ---------------------------------------------------------------------------

create function public.create_recurring_task(
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

-- ---------------------------------------------------------------------------
-- update_series_from: „Dieses und zukünftige“ ab dem Vorkommen p_task_id.
--   * Serie: neuer Inhalt und neue Regel für alles, was noch erzeugt wird.
--   * Das gewählte Vorkommen bekommt den neuen Stand (inkl. Datum/Uhrzeit aus dem Editor).
--   * Spätere offene, nicht abgekoppelte Vorkommen ohne Haken: bei gleicher Regel neuer Inhalt
--     (eigenes Datum bleibt, Uhrzeit neu); bei geänderter Regel werden künftige (nach heute)
--     entfernt und nach der neuen Regel neu erzeugt, überfällige bekommen den neuen Inhalt.
--   * Erledigte, gelöschte, abgekoppelte oder schon angefangene Vorkommen bleiben unverändert.
-- ---------------------------------------------------------------------------

create function public.update_series_from(
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

-- ---------------------------------------------------------------------------
-- delete_series: „Gesamte Serie“ ab einem sichtbaren Vorkommen. Ein Verlaufseintrag;
-- offene Vorkommen (auch überfällige) werden mit diesem Eintrag markiert. Erledigte bleiben.
-- Idempotent: Ist die Serie schon gelöscht, kommt der offene Eintrag zurück.
-- ---------------------------------------------------------------------------

create function public.delete_series(p_task_id uuid)
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

-- ---------------------------------------------------------------------------
-- restore_series_deletion: jedes Mitglied mit Sicht auf die Serie (Guide, Abschnitt 3/4).
-- ---------------------------------------------------------------------------

create function public.restore_series_deletion(p_deletion_id uuid)
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

-- Einzelnes Wiederherstellen eines mit der Serie gelöschten Vorkommens ist nicht vorgesehen.
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

-- ---------------------------------------------------------------------------
-- Kalender-Projektion (Phase 6): künftige, noch nicht erzeugte Vorkommen sichtbarer Serien.
-- Sicht wie bei Aufgaben (can_view_series). Höchstens 400 Tage.
-- ---------------------------------------------------------------------------

create function public.project_series_occurrences(p_from date, p_to date)
returns table (series_id uuid, family_id uuid, occurrence_date date, start_time time, timezone text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_uid();
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    perform private.raise_app_error('invalid_range');
  end if;
  return query
    select s.id, s.family_id, d.d, s.start_time, s.timezone
    from public.task_series s
    cross join lateral private.series_dates(
      s.freq, s.weekdays, s.month_days,
      greatest(p_from, s.start_date, s.resume_from, s.generated_until + 1),
      p_to
    ) as d(d)
    where s.deleted_at is null
      and private.can_view_series(s.id)
    order by d.d, s.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rechte: nur authenticated darf die RPCs ausführen.
-- ---------------------------------------------------------------------------

revoke execute on function public.create_recurring_task(uuid, text, public.completion_mode, uuid[], public.recurrence_freq, date, smallint[], smallint[], text, time, text, jsonb)
  from public, anon, service_role;
revoke execute on function public.update_series_from(uuid, integer, text, public.completion_mode, uuid[], public.recurrence_freq, date, smallint[], smallint[], text, time, text, jsonb)
  from public, anon, service_role;
revoke execute on function public.delete_series(uuid) from public, anon, service_role;
revoke execute on function public.restore_series_deletion(uuid) from public, anon, service_role;
revoke execute on function public.project_series_occurrences(date, date) from public, anon, service_role;

grant execute on function public.create_recurring_task(uuid, text, public.completion_mode, uuid[], public.recurrence_freq, date, smallint[], smallint[], text, time, text, jsonb)
  to authenticated;
grant execute on function public.update_series_from(uuid, integer, text, public.completion_mode, uuid[], public.recurrence_freq, date, smallint[], smallint[], text, time, text, jsonb)
  to authenticated;
grant execute on function public.delete_series(uuid) to authenticated;
grant execute on function public.restore_series_deletion(uuid) to authenticated;
grant execute on function public.project_series_occurrences(date, date) to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime: Serienänderungen (z. B. Löschen/Wiederherstellen) ebenfalls melden.
-- ---------------------------------------------------------------------------

create function private.broadcast_series_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member uuid;
begin
  -- Reines Fortschreiben der Wasserstandsmarke meldet die Aufgaben-Zeile selbst.
  if tg_op = 'UPDATE' and new.version = old.version then
    return null;
  end if;
  for v_member in
    select m.user_id from public.family_members m where m.family_id = new.family_id
  loop
    perform realtime.send(
      jsonb_build_object('series_id', new.id, 'family_id', new.family_id),
      'task_changed',
      'user:' || v_member::text,
      true
    );
  end loop;
  return null;
end;
$$;

revoke execute on function private.broadcast_series_change() from public, anon, authenticated;

create trigger task_series_broadcast_change
  after insert or update on public.task_series
  for each row execute function private.broadcast_series_change();

-- ---------------------------------------------------------------------------
-- 30-Tage-Bereinigung erweitern: Serien-Löschungen und Serienbilder.
-- ---------------------------------------------------------------------------

create or replace function public.purge_expired_history(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tasks integer;
  v_series integer;
  v_images integer;
  v_paths text[];
begin
  update private.cron_tokens t
     set used_at = now()
   where t.token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and t.purpose = 'purge_history'
     and t.used_at is null
     and t.created_at > now() - interval '15 minutes';
  if not found then
    raise exception using errcode = '42501', message = 'Ungültiges oder abgelaufenes Token.';
  end if;

  -- Aufgaben, die seit mehr als 30 Tagen erledigt oder gelöscht sind (auch mit der Serie gelöschte
  -- Vorkommen). Zuweisungen und Bildverknüpfungen folgen per Cascade.
  with expired as (
    delete from public.tasks t
     where t.completed_at < now() - interval '30 days'
        or t.deleted_at < now() - interval '30 days'
    returning t.id
  )
  select count(*) into v_tasks from expired;

  -- Seit mehr als 30 Tagen gelöschte Serien (Verlaufseintrag, Zuweisungen, Bildverknüpfungen per
  -- Cascade; erledigte Vorkommen bleiben mit series_id = null). Danach abgelaufene Einträge
  -- wiederhergestellter Serien.
  with expired as (
    delete from public.task_series s
     where s.deleted_at < now() - interval '30 days'
    returning s.id
  )
  select count(*) into v_series from expired;

  delete from public.series_deletions d
   where d.deleted_at < now() - interval '30 days';

  -- Bilder ohne Verknüpfung; ein Tag Schonfrist für gerade laufende Speichervorgänge.
  with orphaned as (
    delete from public.images i
     where i.created_at < now() - interval '1 day'
       and not exists (select 1 from public.task_image_links l where l.image_id = i.id)
       and not exists (select 1 from public.series_image_links l where l.image_id = i.id)
    returning i.id
  )
  select count(*) into v_images from orphaned;

  -- Dateien ohne Bildzeile: verwaiste Bilder von oben und Uploads, deren Speichern scheiterte.
  select coalesce(array_agg(o.name order by o.name), '{}')
    into v_paths
  from storage.objects o
  where o.bucket_id = 'task-images'
    and o.created_at < now() - interval '1 day'
    and not exists (
      select 1 from public.images i where i.path = o.name or i.thumb_path = o.name
    );

  return jsonb_build_object('deleted_tasks', v_tasks, 'deleted_series', v_series, 'deleted_images', v_images,
                            'file_paths', to_jsonb(v_paths));
end;
$$;

revoke execute on function public.purge_expired_history(text) from public, anon, authenticated;
grant execute on function public.purge_expired_history(text) to service_role;
