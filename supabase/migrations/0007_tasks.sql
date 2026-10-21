-- 0007_tasks
-- Aufgaben-Kern (Phase 3): Aufgaben, Zuweisungen mit Status pro Person, Bilder,
-- Sichtbarkeit laut Familien-Einstellung, Schreib-RPCs und Realtime-Hinweise.
--
-- Grundsätze wie in 0003/0004: Lesen per RLS, Schreiben nur über RPCs
-- (security definer, search_path = '', explizite Prüfungen, Fehlerkatalog).
-- Wiederholungen (task_series) und Verlauf folgen in Phase 4/5; die Spalten
-- series_id, occurrence_date, is_detached und deleted_by_series_op sind dafür vorgesehen.

-- ---------------------------------------------------------------------------
-- Typen
-- ---------------------------------------------------------------------------

create type public.completion_mode as enum ('any_one', 'each');
create type public.completion_source as enum ('assignee', 'creator');

-- ---------------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------------

create table public.tasks (
  id                    uuid primary key default gen_random_uuid(),
  family_id             uuid not null references public.families (id) on delete cascade,
  series_id             uuid,
  occurrence_date       date,
  created_by            uuid references public.profiles (id) on delete set null,
  title                 text not null check (char_length(btrim(title)) between 1 and 200),
  description           text check (description is null or char_length(description) between 1 and 4000),
  start_date            date,
  start_time            time,
  timezone              text not null default 'Europe/Berlin',
  starts_at             timestamptz,
  sort_at               timestamptz not null default now(),
  completion_mode       public.completion_mode not null,
  is_detached           boolean not null default false,
  completed_at          timestamptz,
  completed_by          uuid references public.profiles (id) on delete set null,
  completion_source     public.completion_source,
  deleted_at            timestamptz,
  deleted_by            uuid references public.profiles (id) on delete set null,
  deleted_by_series_op  uuid,
  version               integer not null default 1,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  constraint tasks_time_requires_date check (start_time is null or start_date is not null),
  constraint tasks_series_occurrence check ((series_id is null) = (occurrence_date is null)),
  constraint tasks_completion_consistent check ((completed_at is null) = (completion_source is null)),
  constraint tasks_series_occurrence_unique unique (series_id, occurrence_date)
);

comment on column public.tasks.starts_at is
  'Startzeitpunkt aus start_date/start_time in timezone (nur Datum = Tagesbeginn); per Trigger.';
comment on column public.tasks.sort_at is
  'starts_at, sonst created_at; per Trigger. Die App sortiert undatierte Aufgaben zuerst.';

create index tasks_family_open_sort_idx on public.tasks (family_id, sort_at)
  where deleted_at is null and completed_at is null;
create index tasks_created_by_idx on public.tasks (created_by);
create index tasks_completed_by_idx on public.tasks (completed_by);
create index tasks_deleted_by_idx on public.tasks (deleted_by);

create table public.task_assignees (
  task_id      uuid not null references public.tasks (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  assigned_by  uuid references public.profiles (id) on delete set null,
  assigned_at  timestamptz not null default now(),
  completed_at timestamptz,
  primary key (task_id, user_id)
);

create index task_assignees_user_id_idx on public.task_assignees (user_id);
create index task_assignees_assigned_by_idx on public.task_assignees (assigned_by);

-- Bilder liegen im Bucket task-images unter {family_id}/{image_id}.jpg und …_thumb.jpg.
create table public.images (
  id          uuid primary key,
  family_id   uuid not null references public.families (id) on delete cascade,
  path        text not null unique,
  thumb_path  text not null unique,
  width       integer not null check (width > 0),
  height      integer not null check (height > 0),
  created_by  uuid references public.profiles (id) on delete set null,
  created_at  timestamptz not null default now()
);

create index images_family_id_idx on public.images (family_id);
create index images_created_by_idx on public.images (created_by);

create table public.task_image_links (
  task_id   uuid not null references public.tasks (id) on delete cascade,
  image_id  uuid not null references public.images (id) on delete cascade,
  position  smallint not null default 0 check (position >= 0),
  primary key (task_id, image_id)
);

create index task_image_links_image_id_idx on public.task_image_links (image_id);

-- ---------------------------------------------------------------------------
-- Trigger: Zeiten berechnen, updated_at
-- ---------------------------------------------------------------------------

create function private.compute_task_times()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.starts_at := case
    when new.start_date is null then null
    else (new.start_date + coalesce(new.start_time, time '00:00')) at time zone new.timezone
  end;
  new.sort_at := coalesce(new.starts_at, new.created_at);
  return new;
end;
$$;

revoke execute on function private.compute_task_times() from public, anon, authenticated;

create trigger tasks_compute_times
  before insert or update of start_date, start_time, timezone on public.tasks
  for each row execute function private.compute_task_times();

create trigger tasks_set_updated_at
  before update on public.tasks
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- Sichtbarkeit (Plan, Abschnitt 3; Entscheidung F1: Ersteller sieht eigene Aufgaben immer)
-- ---------------------------------------------------------------------------

-- Familien, in denen der Nutzer alle Aufgaben sieht (Sichtbarkeit 'all').
create function private.my_all_tasks_family_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.family_id
  from public.family_members m
  join public.families f on f.id = m.family_id
  where m.user_id = (select auth.uid())
    and f.task_visibility = 'all';
$$;

-- Aufgaben, denen der Nutzer zugewiesen ist.
create function private.my_assigned_task_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select a.task_id
  from public.task_assignees a
  where a.user_id = (select auth.uid());
$$;

-- Darf der Nutzer die Aufgabe sehen? Mitglied UND (alle sichtbar ODER Ersteller ODER zugewiesen).
create function private.can_view_task(p_task_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.tasks t
    join public.family_members m on m.family_id = t.family_id and m.user_id = (select auth.uid())
    join public.families f on f.id = t.family_id
    where t.id = p_task_id
      and (
        f.task_visibility = 'all'
        or t.created_by = (select auth.uid())
        or exists (
          select 1 from public.task_assignees a
          where a.task_id = t.id and a.user_id = (select auth.uid())
        )
      )
  );
$$;

-- Ist das Bild an mindestens eine sichtbare Aufgabe angehängt?
create function private.can_view_image(p_image_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.task_image_links l
    where l.image_id = p_image_id and private.can_view_task(l.task_id)
  );
$$;

-- Für die Storage-Policy: Gehört die Datei (Bild oder Miniatur) zu einer sichtbaren Aufgabe?
create function private.can_view_task_image_object(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.images i
    join public.task_image_links l on l.image_id = i.id
    where (i.path = p_name or i.thumb_path = p_name)
      and private.can_view_task(l.task_id)
  );
$$;

revoke execute on function private.my_all_tasks_family_ids() from public, anon;
revoke execute on function private.my_assigned_task_ids() from public, anon;
revoke execute on function private.can_view_task(uuid) from public, anon;
revoke execute on function private.can_view_image(uuid) from public, anon;
revoke execute on function private.can_view_task_image_object(text) from public, anon;

grant execute on function private.my_all_tasks_family_ids() to authenticated;
grant execute on function private.my_assigned_task_ids() to authenticated;
grant execute on function private.can_view_task(uuid) to authenticated;
grant execute on function private.can_view_image(uuid) to authenticated;
grant execute on function private.can_view_task_image_object(text) to authenticated;

-- ---------------------------------------------------------------------------
-- RLS, Rechte, Lese-Policies
-- ---------------------------------------------------------------------------

alter table public.tasks            enable row level security;
alter table public.task_assignees   enable row level security;
alter table public.images           enable row level security;
alter table public.task_image_links enable row level security;

revoke all on table public.tasks            from anon, authenticated;
revoke all on table public.task_assignees   from anon, authenticated;
revoke all on table public.images           from anon, authenticated;
revoke all on table public.task_image_links from anon, authenticated;

grant select on table public.tasks            to authenticated;
grant select on table public.task_assignees   to authenticated;
grant select on table public.images           to authenticated;
grant select on table public.task_image_links to authenticated;

create policy "tasks_select_visible"
  on public.tasks
  for select
  to authenticated
  using (
    family_id = any (array (select private.my_family_ids()))
    and (
      family_id = any (array (select private.my_all_tasks_family_ids()))
      or created_by = (select auth.uid())
      or id = any (array (select private.my_assigned_task_ids()))
    )
  );

create policy "task_assignees_select_visible_task"
  on public.task_assignees
  for select
  to authenticated
  using (private.can_view_task(task_id));

create policy "images_select_visible_task"
  on public.images
  for select
  to authenticated
  using (private.can_view_image(id));

create policy "task_image_links_select_visible_task"
  on public.task_image_links
  for select
  to authenticated
  using (private.can_view_task(task_id));

-- ---------------------------------------------------------------------------
-- Storage: Bucket task-images
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('task-images', 'task-images', false, 5242880, array['image/jpeg']);

-- Hochladen: nur in den Ordner einer eigenen Familie, nur {uuid}.jpg bzw. {uuid}_thumb.jpg.
create policy "task_images_insert_member"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'task-images'
    and (storage.foldername(name))[1] = any (array (select f::text from private.my_family_ids() as f))
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}(_thumb)?\.jpg$'
  );

-- Lesen: nur Dateien, die an eine sichtbare Aufgabe angehängt sind.
create policy "task_images_select_visible_task"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'task-images'
    and private.can_view_task_image_object(name)
  );

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
    ('invalid_scope',                   '22023', 'Unbekannte Aktion.')
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
-- Interne Helfer für die RPCs
-- ---------------------------------------------------------------------------

-- Prüft Titel, Beschreibung, Start, Zeitzone, Erledigungsart und Zuweisungen.
create function private.validate_task_input(
  p_family_id uuid,
  p_title text,
  p_description text,
  p_start_date date,
  p_start_time time,
  p_timezone text,
  p_completion_mode public.completion_mode,
  p_assignee_ids uuid[]
)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 200 then
    perform private.raise_app_error('invalid_task_title');
  end if;
  if p_description is not null and char_length(p_description) > 4000 then
    perform private.raise_app_error('invalid_task_description');
  end if;
  if p_start_time is not null and p_start_date is null then
    perform private.raise_app_error('invalid_start');
  end if;
  if p_timezone is null
     or not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = p_timezone) then
    perform private.raise_app_error('invalid_timezone');
  end if;
  if p_completion_mode is null then
    perform private.raise_app_error('invalid_completion_mode');
  end if;
  if coalesce(cardinality(p_assignee_ids), 0) = 0 then
    perform private.raise_app_error('assignees_required');
  end if;
  if exists (
    select 1 from unnest(p_assignee_ids) as a(user_id)
    where not exists (
      select 1 from public.family_members m
      where m.family_id = p_family_id and m.user_id = a.user_id
    )
  ) then
    perform private.raise_app_error('assignee_not_member');
  end if;
end;
$$;

revoke execute on function private.validate_task_input(uuid, text, text, date, time, text, public.completion_mode, uuid[])
  from public, anon, authenticated;

-- Übernimmt die Bildliste (Reihenfolge = Position) für eine Aufgabe.
-- p_images: [{"id": uuid, "width": int, "height": int}, …]. Neue Bilder müssen vom Aufrufer
-- bereits nach {family_id}/{id}.jpg und …_thumb.jpg hochgeladen sein.
create function private.set_task_images(p_task_id uuid, p_family_id uuid, p_images jsonb)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_uid       uuid := (select auth.uid());
  v_item      jsonb;
  v_position  integer := 0;
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
    insert into public.task_image_links (task_id, image_id, position)
    values (p_task_id, v_image_id, v_position)
    on conflict (task_id, image_id) do update set position = excluded.position;
    v_position := v_position + 1;
  end loop;

  delete from public.task_image_links l
   where l.task_id = p_task_id
     and not (l.image_id = any (v_ids));
end;
$$;

revoke execute on function private.set_task_images(uuid, uuid, jsonb) from public, anon, authenticated;

-- Lädt die Aufgabe gesperrt und prüft Sichtbarkeit; wirft task_not_found.
create function private.lock_visible_task(p_task_id uuid)
returns public.tasks
language plpgsql
set search_path = ''
as $$
declare
  v_task public.tasks;
begin
  select * into v_task from public.tasks t where t.id = p_task_id for update;
  if not found or not private.can_view_task(p_task_id) then
    perform private.raise_app_error('task_not_found');
  end if;
  return v_task;
end;
$$;

revoke execute on function private.lock_visible_task(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- create_task: jedes Mitglied; mindestens eine zugewiesene Person.
-- Der Ersteller wird nicht automatisch zugewiesen (Guide, Abschnitt 2).
-- ---------------------------------------------------------------------------

create function public.create_task(
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

-- ---------------------------------------------------------------------------
-- update_task: jedes Mitglied mit Sicht auf die Aufgabe; vollständiger Stand.
-- p_expected_version schützt vor dem Überschreiben fremder Änderungen.
-- ---------------------------------------------------------------------------

create function public.update_task(
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
  v_uid         uuid := private.require_uid();
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_assignees   uuid[];
  v_task        public.tasks;
begin
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

  -- Zuweisungen abgleichen: Entfernte fallen weg, bestehende behalten ihren Status.
  delete from public.task_assignees a
   where a.task_id = p_task_id
     and not (a.user_id = any (v_assignees));
  insert into public.task_assignees (task_id, user_id, assigned_by)
  select p_task_id, a, v_uid from unnest(v_assignees) as a
  on conflict (task_id, user_id) do nothing;

  perform private.set_task_images(p_task_id, v_task.family_id, p_images);

  update public.tasks t
     set title           = btrim(p_title),
         description     = v_description,
         start_date      = p_start_date,
         start_time      = p_start_time,
         timezone        = p_timezone,
         completion_mode = p_completion_mode,
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

-- ---------------------------------------------------------------------------
-- complete_task(task, scope)
--   'self': als zugewiesene Person abhaken. „Eine für alle“ erledigt damit die ganze Aufgabe,
--           „einzeln“ nur den eigenen Teil (komplett, sobald alle erledigt haben).
--   'all':  die ganze Aufgabe erledigen – zugewiesene Personen in „Eine für alle“
--           oder wer die Aufgabe erstellt hat (completion_source = 'creator').
-- Bereits Erledigtes wird unverändert zurückgegeben (idempotent).
-- ---------------------------------------------------------------------------

create function public.complete_task(p_task_id uuid, p_scope text default 'self')
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := private.require_uid();
  v_task        public.tasks;
  v_is_assignee boolean;
  v_is_creator  boolean;
begin
  if p_scope is null or p_scope not in ('self', 'all') then
    perform private.raise_app_error('invalid_scope');
  end if;

  v_task := private.lock_visible_task(p_task_id);
  if v_task.deleted_at is not null then
    perform private.raise_app_error('task_closed');
  end if;
  if v_task.completed_at is not null then
    return v_task;
  end if;

  v_is_assignee := exists (select 1 from public.task_assignees a where a.task_id = p_task_id and a.user_id = v_uid);
  v_is_creator  := v_task.created_by = v_uid;

  if v_task.completion_mode = 'any_one' and v_is_assignee then
    update public.task_assignees a set completed_at = now()
     where a.task_id = p_task_id and a.user_id = v_uid;
    update public.tasks t
       set completed_at = now(), completed_by = v_uid, completion_source = 'assignee', version = t.version + 1
     where t.id = p_task_id
    returning * into v_task;

  elsif v_task.completion_mode = 'each' and p_scope = 'self' and v_is_assignee then
    update public.task_assignees a set completed_at = coalesce(a.completed_at, now())
     where a.task_id = p_task_id and a.user_id = v_uid;
    if exists (select 1 from public.task_assignees a where a.task_id = p_task_id and a.completed_at is null) then
      update public.tasks t set version = t.version + 1 where t.id = p_task_id returning * into v_task;
    else
      update public.tasks t
         set completed_at = now(), completed_by = v_uid, completion_source = 'assignee', version = t.version + 1
       where t.id = p_task_id
      returning * into v_task;
    end if;

  elsif v_is_creator and (p_scope = 'all' or not v_is_assignee) then
    update public.tasks t
       set completed_at = now(), completed_by = v_uid, completion_source = 'creator', version = t.version + 1
     where t.id = p_task_id
    returning * into v_task;

  else
    perform private.raise_app_error('not_allowed_to_complete');
  end if;

  return v_task;
end;
$$;

-- ---------------------------------------------------------------------------
-- uncomplete_task(task, scope)
--   'self': eigenen Haken zurücknehmen (zugewiesene Person). War die Aufgabe dadurch komplett,
--           ist sie wieder offen.
--   'all':  komplett erledigte Aufgabe wieder öffnen – jedes Mitglied mit Sicht darauf
--           (Undo und später Wiederherstellen aus dem Verlauf). Alle Haken werden zurückgesetzt.
-- ---------------------------------------------------------------------------

create function public.uncomplete_task(p_task_id uuid, p_scope text default 'self')
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := private.require_uid();
  v_task        public.tasks;
  v_is_assignee boolean;
begin
  if p_scope is null or p_scope not in ('self', 'all') then
    perform private.raise_app_error('invalid_scope');
  end if;

  v_task := private.lock_visible_task(p_task_id);
  if v_task.deleted_at is not null then
    perform private.raise_app_error('task_closed');
  end if;

  if p_scope = 'all' then
    if v_task.completed_at is null then
      return v_task;
    end if;
    update public.task_assignees a set completed_at = null where a.task_id = p_task_id;
    update public.tasks t
       set completed_at = null, completed_by = null, completion_source = null, version = t.version + 1
     where t.id = p_task_id
    returning * into v_task;
    return v_task;
  end if;

  v_is_assignee := exists (select 1 from public.task_assignees a where a.task_id = p_task_id and a.user_id = v_uid);
  if not v_is_assignee then
    perform private.raise_app_error('not_allowed_to_complete');
  end if;

  update public.task_assignees a set completed_at = null
   where a.task_id = p_task_id and a.user_id = v_uid;

  if v_task.completed_at is not null
     and (v_task.completion_mode = 'each' and v_task.completion_source = 'assignee'
          or v_task.completion_mode = 'any_one' and v_task.completed_by = v_uid) then
    if v_task.completion_mode = 'any_one' then
      update public.task_assignees a set completed_at = null where a.task_id = p_task_id;
    end if;
    update public.tasks t
       set completed_at = null, completed_by = null, completion_source = null, version = t.version + 1
     where t.id = p_task_id
    returning * into v_task;
  else
    update public.tasks t set version = t.version + 1 where t.id = p_task_id returning * into v_task;
  end if;

  return v_task;
end;
$$;

-- ---------------------------------------------------------------------------
-- delete_task / restore_task: weiches Löschen (Verlauf ab Phase 4); jedes Mitglied mit Sicht.
-- ---------------------------------------------------------------------------

create function public.delete_task(p_task_id uuid)
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

create function public.restore_task(p_task_id uuid)
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
  update public.tasks t
     set deleted_at = null, deleted_by = null, version = t.version + 1
   where t.id = p_task_id
  returning * into v_task;
  return v_task;
end;
$$;

-- ---------------------------------------------------------------------------
-- Rechte: nur authenticated darf die RPCs ausführen.
-- ---------------------------------------------------------------------------

revoke execute on function public.create_task(uuid, text, public.completion_mode, uuid[], text, date, time, text, jsonb)
  from public, anon, service_role;
revoke execute on function public.update_task(uuid, integer, text, public.completion_mode, uuid[], text, date, time, text, jsonb)
  from public, anon, service_role;
revoke execute on function public.complete_task(uuid, text) from public, anon, service_role;
revoke execute on function public.uncomplete_task(uuid, text) from public, anon, service_role;
revoke execute on function public.delete_task(uuid) from public, anon, service_role;
revoke execute on function public.restore_task(uuid) from public, anon, service_role;

grant execute on function public.create_task(uuid, text, public.completion_mode, uuid[], text, date, time, text, jsonb)
  to authenticated;
grant execute on function public.update_task(uuid, integer, text, public.completion_mode, uuid[], text, date, time, text, jsonb)
  to authenticated;
grant execute on function public.complete_task(uuid, text) to authenticated;
grant execute on function public.uncomplete_task(uuid, text) to authenticated;
grant execute on function public.delete_task(uuid) to authenticated;
grant execute on function public.restore_task(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime: Hinweis „Aufgabe geändert“ an alle Mitglieder der Familie.
-- Privater Kanal user:<uid>; Inhalt nur IDs – die App lädt danach per RLS neu (Plan, Abschnitt 1).
-- Jede Änderung über die RPCs berührt die tasks-Zeile, daher reicht ein Trigger.
-- ---------------------------------------------------------------------------

create function private.broadcast_task_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member uuid;
begin
  for v_member in
    select m.user_id from public.family_members m where m.family_id = new.family_id
  loop
    perform realtime.send(
      jsonb_build_object('task_id', new.id, 'family_id', new.family_id),
      'task_changed',
      'user:' || v_member::text,
      true
    );
  end loop;
  return null;
end;
$$;

revoke execute on function private.broadcast_task_change() from public, anon, authenticated;

create trigger tasks_broadcast_change
  after insert or update on public.tasks
  for each row execute function private.broadcast_task_change();

-- Nur der eigene Kanal darf empfangen werden; senden dürfen Clients nicht.
create policy "realtime_receive_own_user_channel"
  on realtime.messages
  for select
  to authenticated
  using (
    (select realtime.topic()) = 'user:' || (select auth.uid())::text
    and realtime.messages.extension in ('broadcast')
  );
