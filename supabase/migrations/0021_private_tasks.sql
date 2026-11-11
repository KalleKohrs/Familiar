-- 0021_private_tasks
-- Private Aufgaben (ADR 0012): Aufgaben und Serien, die nur ihr Ersteller sieht – auch nicht Admins,
-- unabhängig von der Familien-Einstellung „Sichtbarkeit“.
--
-- Regeln:
--   * tasks.is_private / task_series.is_private; gesetzt wird es nur beim Anlegen (create_task,
--     create_recurring_task, Parameter p_private mit Standard false → ältere App-Versionen laufen weiter).
--     Später nicht umschaltbar. Termine einer privaten Serie sind privat (Trigger tasks_inherit_privacy).
--   * Eine private Aufgabe gehört dem Ersteller und ist nur ihm zugewiesen (die RPCs setzen das selbst;
--     die Trigger *_enforce_private_assignee sichern es zusätzlich ab). Private Serien sind nie „Reihum“.
--   * Sichtbar und bearbeitbar nur für den Ersteller (RLS, can_view_task, can_view_series – damit auch
--     Zuweisungen, Bilder, Storage, Verlauf, Kalender-Projektion, Anstupsen und Live Activities).
--   * Die Familienrechte „Aufgaben anlegen/bearbeiten/löschen“ gelten nicht für private Aufgaben:
--     Sie betreffen nur den Ersteller selbst.
--   * Mitteilungen/Live Activities gibt es nur für den Ersteller (einziger Zugewiesener); Realtime-Hinweise
--     gehen nur an ihn.
--   * „Verlauf leeren“ (clear_history) trifft private Aufgaben anderer nicht.
--   * Austritt (Verlassen, Entfernen, Kontolöschung): private Aufgaben und Serien der Person werden
--     gelöscht (handle_member_departure; bei der Kontolöschung zusätzlich vor dem Profil).
--
-- Enthält drop function und delete → im Supabase-SQL-Editor ausführen (nicht über apply_migration).

-- ---------------------------------------------------------------------------
-- Spalten
-- ---------------------------------------------------------------------------

alter table public.tasks
  add column is_private boolean not null default false;

alter table public.task_series
  add column is_private boolean not null default false,
  add constraint task_series_private_together check (not is_private or assignment_mode = 'together');

-- ---------------------------------------------------------------------------
-- Sichtbarkeit: Privates sieht nur der Ersteller
-- ---------------------------------------------------------------------------

alter policy "tasks_select_visible"
  on public.tasks
  using (
    family_id = any (array (select private.my_family_ids()))
    and (
      created_by = (select auth.uid())
      or (
        not is_private
        and (
          family_id = any (array (select private.my_all_tasks_family_ids()))
          or id = any (array (select private.my_assigned_task_ids()))
          or series_id = any (array (select private.my_rotation_series_ids()))
        )
      )
    )
  );

alter policy "task_series_select_visible"
  on public.task_series
  using (
    family_id = any (array (select private.my_family_ids()))
    and (
      created_by = (select auth.uid())
      or (
        not is_private
        and (
          family_id = any (array (select private.my_all_tasks_family_ids()))
          or id = any (array (select private.my_assigned_series_ids()))
        )
      )
    )
  );

create or replace function private.can_view_task(p_task_id uuid)
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
        t.created_by = (select auth.uid())
        or (
          not t.is_private
          and (
            f.task_visibility = 'all'
            or exists (
              select 1 from public.task_assignees a
              where a.task_id = t.id and a.user_id = (select auth.uid())
            )
            or exists (
              select 1
              from public.series_assignees sa
              join public.task_series s on s.id = sa.series_id and s.assignment_mode = 'rotate'
              where sa.series_id = t.series_id and sa.user_id = (select auth.uid())
            )
          )
        )
      )
  );
$$;

create or replace function private.can_view_series(p_series_id uuid)
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
        s.created_by = (select auth.uid())
        or (
          not s.is_private
          and (
            f.task_visibility = 'all'
            or exists (
              select 1 from public.series_assignees a
              where a.series_id = s.id and a.user_id = (select auth.uid())
            )
          )
        )
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- Absicherung in der Datenbank: Termine erben „privat“, Zugewiesene nur der Ersteller
-- ---------------------------------------------------------------------------

create function private.inherit_task_privacy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_private boolean;
begin
  if new.series_id is not null then
    select s.is_private into v_private from public.task_series s where s.id = new.series_id;
    new.is_private := coalesce(v_private, new.is_private);
  end if;
  return new;
end;
$$;

revoke execute on function private.inherit_task_privacy() from public, anon, authenticated;

create trigger tasks_inherit_privacy
  before insert on public.tasks
  for each row execute function private.inherit_task_privacy();

create function private.enforce_private_task_assignee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.tasks t
             where t.id = new.task_id and t.is_private and t.created_by is distinct from new.user_id) then
    raise exception using errcode = '23514',
      message = 'Eine private Aufgabe kann nur ihrem Ersteller zugewiesen sein.';
  end if;
  return new;
end;
$$;

revoke execute on function private.enforce_private_task_assignee() from public, anon, authenticated;

create trigger task_assignees_enforce_private
  before insert or update of user_id on public.task_assignees
  for each row execute function private.enforce_private_task_assignee();

create function private.enforce_private_series_assignee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.task_series s
             where s.id = new.series_id and s.is_private and s.created_by is distinct from new.user_id) then
    raise exception using errcode = '23514',
      message = 'Eine private Serie kann nur ihrem Ersteller zugewiesen sein.';
  end if;
  return new;
end;
$$;

revoke execute on function private.enforce_private_series_assignee() from public, anon, authenticated;

create trigger series_assignees_enforce_private
  before insert or update of user_id on public.series_assignees
  for each row execute function private.enforce_private_series_assignee();

-- ---------------------------------------------------------------------------
-- Realtime: „Aufgabe geändert“ bei privaten Aufgaben nur an den Ersteller
-- ---------------------------------------------------------------------------

create or replace function private.broadcast_task_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member uuid;
begin
  for v_member in
    select m.user_id from public.family_members m
    where m.family_id = new.family_id
      and (not new.is_private or m.user_id = new.created_by)
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

create or replace function private.broadcast_series_change()
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
    select m.user_id from public.family_members m
    where m.family_id = new.family_id
      and (not new.is_private or m.user_id = new.created_by)
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

-- ---------------------------------------------------------------------------
-- Familienrechte gelten nicht für private Aufgaben
-- ---------------------------------------------------------------------------

create function private.require_task_permission(p_family_id uuid, p_permission text, p_private boolean)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if coalesce(p_private, false) then
    return;
  end if;
  perform private.require_task_permission(p_family_id, p_permission);
end;
$$;

revoke execute on function private.require_task_permission(uuid, text, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- RPCs: neue Parameter p_private (Standard false); sonst unverändert aus 0010/0018
-- ---------------------------------------------------------------------------

drop function public.create_task(uuid, text, public.completion_mode, uuid[], text, date, time, text, jsonb);
drop function public.create_recurring_task(uuid, text, public.completion_mode, uuid[], public.recurrence_freq, date,
                                           smallint[], smallint[], text, time, text, jsonb, text, text);

create function public.create_task(
  p_family_id uuid,
  p_title text,
  p_completion_mode public.completion_mode,
  p_assignee_ids uuid[],
  p_description text default null,
  p_start_date date default null,
  p_start_time time default null,
  p_timezone text default 'Europe/Berlin',
  p_images jsonb default '[]'::jsonb,
  p_private boolean default false
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
  perform private.require_task_permission(p_family_id, 'create_tasks', coalesce(p_private, false));
  if coalesce(p_private, false) then
    -- Private Aufgabe: gehört dem Ersteller, er ist der Einzige, dem sie zugewiesen ist.
    v_assignees := array[v_uid];
  else
    select coalesce(array_agg(distinct a), '{}') into v_assignees from unnest(p_assignee_ids) as a;
  end if;
  perform private.validate_task_input(p_family_id, p_title, v_description, p_start_date, p_start_time,
                                      p_timezone, p_completion_mode, v_assignees);

  insert into public.tasks (family_id, created_by, title, description, start_date, start_time, timezone, completion_mode,
                            is_private)
  values (p_family_id, v_uid, btrim(p_title), v_description, p_start_date, p_start_time, p_timezone, p_completion_mode,
          coalesce(p_private, false))
  returning * into v_task;

  insert into public.task_assignees (task_id, user_id, assigned_by)
  select v_task.id, a, v_uid from unnest(v_assignees) as a;

  perform private.set_task_images(v_task.id, p_family_id, p_images);

  return v_task;
end;
$$;

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
  p_images jsonb default '[]'::jsonb,
  p_assignment_mode text default 'together',
  p_rotation_unit text default 'occurrence',
  p_private boolean default false
)
returns public.task_series
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := private.require_uid();
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_assignees   uuid[] := private.ordered_unique(p_assignee_ids);
  v_mode        public.completion_mode;
  v_weekdays    smallint[];
  v_month_days  smallint[];
  v_today       date;
  v_first       date;
  v_series      public.task_series;
begin
  perform private.require_member(p_family_id);
  perform private.require_task_permission(p_family_id, 'create_tasks', coalesce(p_private, false));
  if coalesce(p_private, false) then
    -- Private Serie: nur für den Ersteller, nie Reihum.
    v_assignees := array[v_uid];
    p_assignment_mode := 'together';
    p_rotation_unit := 'occurrence';
  end if;
  if p_start_date is null then
    perform private.raise_app_error('recurrence_requires_date');
  end if;
  perform private.validate_task_input(p_family_id, p_title, v_description, p_start_date, p_start_time,
                                      p_timezone, p_completion_mode, v_assignees);
  v_mode := private.validate_rotation(p_assignment_mode, p_rotation_unit, v_assignees, p_completion_mode);
  select r.weekdays, r.month_days into v_weekdays, v_month_days
  from private.normalize_recurrence(p_freq, p_weekdays, p_month_days) as r;

  v_today := (now() at time zone p_timezone)::date;

  -- Die Reihe beginnt beim ersten Termin, der tatsächlich entsteht (Vergangenes wird nicht erzeugt):
  -- So ist die erste Person der Liste wirklich als Erste dran.
  select d into v_first
  from private.series_dates(p_freq, v_weekdays, v_month_days, greatest(p_start_date, v_today),
                            greatest(p_start_date, v_today) + 62) as d
  order by d
  limit 1;

  insert into public.task_series (family_id, created_by, title, description, completion_mode, freq,
                                  weekdays, month_days, start_date, start_time, timezone, generated_until,
                                  assignment_mode, rotation_unit, rotation_start, is_private)
  values (p_family_id, v_uid, btrim(p_title), v_description, v_mode, p_freq,
          v_weekdays, v_month_days, p_start_date, p_start_time, p_timezone,
          case when p_start_date < v_today then v_today - 1 end,
          p_assignment_mode, p_rotation_unit, coalesce(v_first, greatest(p_start_date, v_today)),
          coalesce(p_private, false))
  returning * into v_series;

  perform private.set_series_assignees(v_series.id, v_assignees);
  perform private.set_series_images(v_series.id, p_family_id, p_images);
  perform private.generate_series_occurrences(v_series.id);
  perform private.notify_new_series(v_series.id, v_uid, v_today);

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
  perform private.require_task_permission(v_task.family_id, 'edit_tasks', v_task.is_private);
  if v_task.deleted_at is not null or v_task.completed_at is not null then
    perform private.raise_app_error('task_closed');
  end if;
  if p_expected_version is distinct from v_task.version then
    perform private.raise_app_error('task_conflict');
  end if;

  if v_task.is_private then
    v_assignees := array[v_task.created_by];
  else
    select coalesce(array_agg(distinct a), '{}') into v_assignees from unnest(p_assignee_ids) as a;
  end if;
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
  p_images jsonb default '[]'::jsonb,
  p_assignment_mode text default 'together',
  p_rotation_unit text default 'occurrence'
)
returns public.tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid := private.require_uid();
  v_description  text := nullif(btrim(coalesce(p_description, '')), '');
  v_assignees    uuid[] := private.ordered_unique(p_assignee_ids);
  v_mode         public.completion_mode;
  v_weekdays     smallint[];
  v_month_days   smallint[];
  v_task         public.tasks;
  v_before       public.tasks;
  v_series       public.task_series;
  v_rule_changed boolean;
  v_changed      boolean;
  v_today        date;
  v_later        public.tasks;
  v_bulk         text := coalesce(current_setting('familiar.bulk_change', true), '');
  v_first_before jsonb;
  v_next         record;
begin
  v_task := private.lock_visible_task(p_task_id);
  perform private.require_task_permission(v_task.family_id, 'edit_tasks', v_task.is_private);
  if v_task.is_private then
    v_assignees := array[v_task.created_by];
    p_assignment_mode := 'together';
    p_rotation_unit := 'occurrence';
  end if;
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
  perform private.validate_task_input(v_task.family_id, p_title, v_description, p_start_date, p_start_time,
                                      p_timezone, p_completion_mode, v_assignees);
  v_mode := private.validate_rotation(p_assignment_mode, p_rotation_unit, v_assignees, p_completion_mode);
  select r.weekdays, r.month_days into v_weekdays, v_month_days
  from private.normalize_recurrence(p_freq, p_weekdays, p_month_days) as r;

  if v_mode <> v_task.completion_mode
     and exists (select 1 from public.task_assignees a where a.task_id = p_task_id and a.completed_at is not null) then
    perform private.raise_app_error('completion_mode_locked');
  end if;

  v_rule_changed := p_freq <> v_series.freq
                    or v_weekdays <> v_series.weekdays
                    or v_month_days <> v_series.month_days;
  v_today := (now() at time zone p_timezone)::date;
  v_before := v_task;
  -- Relevante Änderung (E6) des gewählten Termins oder der Regel → „geändert“.
  v_changed := btrim(p_title) is distinct from v_before.title
               or p_start_date is distinct from v_before.start_date
               or p_start_time is distinct from v_before.start_time
               or v_mode is distinct from v_before.completion_mode
               or v_rule_changed;

  -- Vorher: nächster offener Termin je Person unter den Terminen, die diese Änderung betrifft
  -- (der gewählte und alle späteren, nicht einzeln geänderten).
  select coalesce(jsonb_object_agg(x.user_id, x.first_date), '{}'::jsonb) into v_first_before
  from (
    select a.user_id, min(t.occurrence_date) as first_date
    from public.tasks t
    join public.task_assignees a on a.task_id = t.id and a.completed_at is null
    where t.series_id = v_series.id
      and t.occurrence_date >= v_before.occurrence_date
      and (t.id = p_task_id or not t.is_detached)
      and t.completed_at is null
      and t.deleted_at is null
    group by a.user_id
  ) x;

  -- Ab hier keine Einzelmitteilungen je Termin; gesammelt gemeldet wird am Ende.
  perform set_config('familiar.bulk_change', 'on', true);

  -- Serie; bei Reihum beginnt die übergebene Reihenfolge mit dem gewählten Termin.
  update public.task_series s
     set title           = btrim(p_title),
         description     = v_description,
         completion_mode = v_mode,
         freq            = p_freq,
         weekdays        = v_weekdays,
         month_days      = v_month_days,
         start_time      = p_start_time,
         timezone        = p_timezone,
         assignment_mode = p_assignment_mode,
         rotation_unit   = p_rotation_unit,
         rotation_start  = v_task.occurrence_date,
         version         = s.version + 1
   where s.id = v_series.id
  returning * into v_series;

  perform private.set_series_assignees(v_series.id, v_assignees);
  perform private.set_series_images(v_series.id, v_task.family_id, p_images);

  -- Gewähltes Vorkommen
  v_task := private.write_task_content(p_task_id, p_title, v_description, p_start_date, p_start_time, p_timezone,
                                       v_mode, private.occurrence_assignees(v_series, v_task.occurrence_date),
                                       p_images, false);

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
                                         p_timezone, v_mode,
                                         private.occurrence_assignees(v_series, v_later.occurrence_date),
                                         p_images, false);
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

  -- Gesammelt melden: je Person höchstens eine Mitteilung für ihren nächsten offenen Termin –
  -- „zugewiesen“, wenn dieser Termin neu für sie ist, sonst „geändert“ bei relevanter Änderung.
  for v_next in
    select distinct on (a.user_id) a.user_id, t.id as task_id, t.occurrence_date, t.version
    from public.tasks t
    join public.task_assignees a on a.task_id = t.id and a.completed_at is null
    where t.series_id = v_series.id
      and t.occurrence_date >= v_before.occurrence_date
      and (t.id = p_task_id or not t.is_detached)
      and t.completed_at is null
      and t.deleted_at is null
      and a.user_id is distinct from v_uid
    order by a.user_id, t.occurrence_date
  loop
    if (v_first_before ->> v_next.user_id::text)::date is distinct from v_next.occurrence_date then
      perform private.enqueue_notification('assigned', v_next.task_id, v_next.user_id, v_uid,
        'assigned:' || v_next.task_id || ':' || v_next.user_id || ':series:' || v_series.version);
    elsif v_changed then
      perform private.enqueue_notification('changed', v_next.task_id, v_next.user_id, v_uid,
        'changed:' || v_next.task_id || ':' || v_next.user_id || ':' || v_next.version);
    end if;
  end loop;

  perform set_config('familiar.bulk_change', v_bulk, true);

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
  perform private.require_task_permission(v_task.family_id, 'delete_tasks', v_task.is_private);
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
  perform private.require_task_permission(v_task.family_id, 'delete_tasks', v_task.is_private);
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
  perform private.require_task_permission(v_task.family_id, 'delete_tasks', v_task.is_private);
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
  perform private.require_task_permission(v_deletion.family_id, 'delete_tasks',
    (select s.is_private from public.task_series s where s.id = v_deletion.series_id));

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

revoke execute on function public.create_task(uuid, text, public.completion_mode, uuid[], text, date, time, text,
  jsonb, boolean) from public, anon, service_role;
revoke execute on function public.create_recurring_task(uuid, text, public.completion_mode, uuid[],
  public.recurrence_freq, date, smallint[], smallint[], text, time, text, jsonb, text, text, boolean)
  from public, anon, service_role;
grant execute on function public.create_task(uuid, text, public.completion_mode, uuid[], text, date, time, text,
  jsonb, boolean) to authenticated;
grant execute on function public.create_recurring_task(uuid, text, public.completion_mode, uuid[],
  public.recurrence_freq, date, smallint[], smallint[], text, time, text, jsonb, text, text, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Austritt (Verlassen, Entfernen): private Aufgaben und Serien der Person löschen
-- ---------------------------------------------------------------------------

create or replace function private.handle_member_departure()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bulk    text := coalesce(current_setting('familiar.bulk_change', true), '');
  v_task    public.tasks;
  v_series  public.task_series;
  v_person  uuid;
  v_touched uuid[];
  v_done    uuid[];
begin
  -- Ganze Familie gelöscht (Kaskade): nichts mehr zu verteilen.
  if not exists (select 1 from public.families f where f.id = old.family_id) then
    return null;
  end if;
  perform set_config('familiar.bulk_change', 'on', true);

  -- Private Aufgaben und Serien der austretenden Person verschwinden mit ihr: Sie gehören ihr allein
  -- und sind für niemanden sonst sichtbar (ADR 0012). Das Löschen fällt weder im Verlauf noch
  -- als Mitteilung auf; Zuweisungen, Bildverknüpfungen und Verlaufseinträge folgen per Cascade.
  delete from public.task_series s
   where s.family_id = old.family_id and s.is_private and s.created_by = old.user_id;
  delete from public.tasks t
   where t.family_id = old.family_id and t.is_private and t.created_by = old.user_id;

  delete from public.series_assignees a
   using public.task_series s
   where s.id = a.series_id and s.family_id = old.family_id and a.user_id = old.user_id;

  with removed as (
    delete from public.task_assignees a
     using public.tasks t
     where t.id = a.task_id
       and t.family_id = old.family_id
       and t.completed_at is null
       and t.deleted_at is null
       and a.user_id = old.user_id
       and a.completed_at is null
    returning a.task_id
  )
  select coalesce(array_agg(distinct r.task_id), '{}') into v_touched from removed r;

  -- Reihum-Termine ohne zuständige Person neu besetzen.
  for v_task in
    select t.*
    from public.tasks t
    join public.task_series s on s.id = t.series_id and s.assignment_mode = 'rotate'
    where t.family_id = old.family_id
      and t.completed_at is null
      and t.deleted_at is null
      and not exists (select 1 from public.task_assignees a where a.task_id = t.id)
    for update of t
  loop
    select * into v_series from public.task_series s where s.id = v_task.series_id;
    v_person := private.rotation_assignee(v_series, v_task.occurrence_date);
    if v_person is not null then
      insert into public.task_assignees (task_id, user_id, assigned_by)
      values (v_task.id, v_person, null)
      on conflict (task_id, user_id) do nothing;
      v_touched := v_touched || v_task.id;
    end if;
  end loop;

  -- „Jede Person einzeln“: Haben alle Übrigen erledigt, ist die Aufgabe komplett.
  with done as (
    update public.tasks t
       set completed_at      = x.done_at,
           completed_by      = x.done_by,
           completion_source = 'assignee'
      from (
        select a.task_id,
               max(a.completed_at) as done_at,
               (array_agg(a.user_id order by a.completed_at desc))[1] as done_by
        from public.task_assignees a
        join public.tasks o on o.id = a.task_id
        where o.family_id = old.family_id
          and o.completion_mode = 'each'
          and o.completed_at is null
          and o.deleted_at is null
        group by a.task_id
        having bool_and(a.completed_at is not null)
      ) as x
     where t.id = x.task_id
    returning t.id
  )
  select coalesce(array_agg(d.id), '{}') into v_done from done d;

  -- Version erhöhen: Apps laden per Realtime neu, offene Editoren merken die Änderung.
  update public.tasks t
     set version = t.version + 1
   where t.id = any (v_touched || v_done);

  perform set_config('familiar.bulk_change', v_bulk, true);
  return null;
end;
$$;

-- Kontolöschung: Das Profil verschwindet, „erstellt von“ würde bei den Aufgaben auf null gesetzt – dann
-- wären private Aufgaben für niemanden mehr erreichbar. Deshalb vorher löschen (BEFORE-Trigger läuft
-- vor den Cascade-Aktionen, unabhängig von deren Reihenfolge).
create function private.delete_private_tasks_of_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.task_series s where s.is_private and s.created_by = old.id;
  delete from public.tasks t where t.is_private and t.created_by = old.id;
  return old;
end;
$$;

revoke execute on function private.delete_private_tasks_of_profile() from public, anon, authenticated;

create trigger profiles_delete_private_tasks
  before delete on public.profiles
  for each row execute function private.delete_private_tasks_of_profile();

-- ---------------------------------------------------------------------------
-- Verlauf leeren: nicht die privaten Aufgaben anderer (die eigenen schon)
-- ---------------------------------------------------------------------------

create or replace function public.clear_history()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid      uuid := private.require_uid();
  v_families uuid[];
  v_tasks    integer;
  v_series   integer;
  v_log      integer;
begin
  select coalesce(array_agg(m.family_id), '{}') into v_families
  from public.family_members m
  where m.user_id = v_uid and m.role = 'admin';
  if cardinality(v_families) = 0 then
    perform private.raise_app_error('admin_required');
  end if;

  -- Gelöschte Serien (Verlaufseinträge, Zuweisungen, Bildverknüpfungen per Cascade; erledigte
  -- Vorkommen bleiben zunächst mit series_id = null und werden unten mit entfernt).
  -- Private Serien anderer bleiben unangetastet.
  with removed as (
    delete from public.task_series s
     where s.family_id = any (v_families) and s.deleted_at is not null
       and (not s.is_private or s.created_by = v_uid)
    returning s.id
  )
  select count(*) into v_series from removed;

  -- Erledigte und gelöschte Aufgaben.
  with removed as (
    delete from public.tasks t
     where t.family_id = any (v_families)
       and (t.completed_at is not null or t.deleted_at is not null)
       and (not t.is_private or t.created_by = v_uid)
    returning t.id
  )
  select count(*) into v_tasks from removed;

  -- Übrige Verlaufseinträge von Serien (z. B. wiederhergestellte).
  with removed as (
    delete from public.series_deletions d
     where d.family_id = any (v_families)
       and not exists (select 1 from public.task_series s
                       where s.id = d.series_id and s.is_private and s.created_by is distinct from v_uid)
    returning d.id
  )
  select count(*) into v_log from removed;

  return v_tasks + v_series;
end;
$$;

-- Eingespielt über den SQL-Editor: Eintrag in der Migrationsliste gleich mit anlegen (wie 0018, 0019).
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261111120000', '0021_private_tasks', array['-- siehe supabase/migrations/0021_private_tasks.sql']);
