-- 0018_rotation_and_nudges
-- Reihum-Aufgaben und Anstupsen (ADR 0010).
--
-- Reihum: Bei Serien mit assignment_mode = 'rotate' bekommt jedes Vorkommen genau eine Person.
--   Dran ist liste[k mod n]: liste = Zugewiesene der Serie in Reihenfolge (position), nur aktuelle
--   Mitglieder; k = Anzahl Serientermine in [rotation_start, Termin) bzw. bei rotation_unit = 'week'
--   die Anzahl ganzer ISO-Wochen zwischen den Montagen. Gleiche Regel in Swift (RotationRules).
-- Anstupsen: nudge_task legt einen Mitteilungsauftrag „nudge“ an; höchstens einmal pro Stunde je
--   Aufgabe und Person, Ruhezeit 21–7 Uhr (Zeitzone der Aufgabe) → Zustellung um 7 Uhr.
-- Mitteilungen bei Serien (wichtig für Reihum):
--   * Automatisch erzeugte Vorkommen melden sich weiter nur über „Jetzt“/Erinnerungen – und die
--     bekommt nur, wer an dem Termin zugewiesen (bei Reihum: dran) ist.
--   * Neue Serie: wer beim ersten Termin dran bzw. zugewiesen ist, bekommt einmal „zugewiesen“.
--   * Ändert jemand die Zuweisung eines Termins (Tauschen, neue Reihenfolge), bekommt die neue Person
--     „zugewiesen“, und bei der bisherigen endet eine laufende Live Activity.
--
-- Enthält drop function (Signaturänderung der Serien-RPCs) → im Supabase-SQL-Editor ausführen.

alter type public.notification_kind add value if not exists 'nudge';

-- ---------------------------------------------------------------------------
-- Reihum: Spalten
-- ---------------------------------------------------------------------------

alter table public.task_series
  add column assignment_mode text not null default 'together'
    check (assignment_mode in ('together', 'rotate')),
  add column rotation_unit text not null default 'occurrence'
    check (rotation_unit in ('occurrence', 'week')),
  add column rotation_start date;

alter table public.series_assignees
  add column position smallint not null default 0;

-- Index des Termins in der Reihe (0 = erste Person der Liste).
create function private.rotation_index(p_series public.task_series, p_date date)
returns integer
language sql
stable
set search_path = ''
as $$
  select case
    when p_series.rotation_unit = 'week' then
      (((p_date - (extract(isodow from p_date)::int - 1))
        - (coalesce(p_series.rotation_start, p_series.start_date)
           - (extract(isodow from coalesce(p_series.rotation_start, p_series.start_date))::int - 1))) / 7)
    else
      (select count(*)::int
       from private.series_dates(p_series.freq, p_series.weekdays, p_series.month_days,
                                 coalesce(p_series.rotation_start, p_series.start_date), p_date - 1))
  end;
$$;

revoke execute on function private.rotation_index(public.task_series, date) from public, anon, authenticated;

-- Wer bei Reihum an einem Termin dran ist (null, wenn niemand mehr Mitglied ist).
create function private.rotation_assignee(p_series public.task_series, p_date date)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_people uuid[];
  v_index  integer;
begin
  select coalesce(array_agg(a.user_id order by a.position, a.user_id), '{}') into v_people
  from public.series_assignees a
  join public.family_members m on m.family_id = p_series.family_id and m.user_id = a.user_id
  where a.series_id = p_series.id;

  if cardinality(v_people) = 0 then
    return null;
  end if;
  v_index := private.rotation_index(p_series, p_date);
  -- Termine vor rotation_start (bei Wochen möglich) zählen negativ; mod immer positiv machen.
  return v_people[(((v_index % cardinality(v_people)) + cardinality(v_people)) % cardinality(v_people)) + 1];
end;
$$;

revoke execute on function private.rotation_assignee(public.task_series, date) from public, anon, authenticated;

-- Zugewiesene ohne Duplikate, Reihenfolge der ersten Nennung bleibt erhalten.
create function private.ordered_unique(p_ids uuid[])
returns uuid[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(x.id order by x.ord), '{}')
  from (
    select distinct on (u.id) u.id, u.ord
    from unnest(p_ids) with ordinality as u(id, ord)
    where u.id is not null
    order by u.id, u.ord
  ) as x;
$$;

revoke execute on function private.ordered_unique(uuid[]) from public, anon, authenticated;

-- Prüft die Reihum-Angaben; liefert die zu verwendende Erledigungsart.
create function private.validate_rotation(
  p_assignment_mode text,
  p_rotation_unit text,
  p_assignees uuid[],
  p_completion_mode public.completion_mode
)
returns public.completion_mode
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_assignment_mode not in ('together', 'rotate') or p_rotation_unit not in ('occurrence', 'week') then
    perform private.raise_app_error('invalid_rotation');
  end if;
  if p_assignment_mode = 'rotate' then
    if cardinality(p_assignees) < 2 then
      perform private.raise_app_error('rotation_needs_two');
    end if;
    -- Reihum: immer genau eine Person pro Termin.
    return 'any_one';
  end if;
  return p_completion_mode;
end;
$$;

revoke execute on function private.validate_rotation(text, text, uuid[], public.completion_mode)
  from public, anon, authenticated;

-- Zugewiesene der Serie in Reihenfolge neu setzen.
create function private.set_series_assignees(p_series_id uuid, p_assignees uuid[])
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  delete from public.series_assignees a
   where a.series_id = p_series_id
     and not (a.user_id = any (p_assignees));
  insert into public.series_assignees (series_id, user_id, assigned_by, position)
  select p_series_id, u.id, v_uid, (u.ord - 1)::smallint
  from unnest(p_assignees) with ordinality as u(id, ord)
  on conflict (series_id, user_id) do update set position = excluded.position;
end;
$$;

revoke execute on function private.set_series_assignees(uuid, uuid[]) from public, anon, authenticated;

-- Personen eines Termins: alle Zugewiesenen (together) oder die eine, die dran ist (rotate).
create function private.occurrence_assignees(p_series public.task_series, p_date date)
returns uuid[]
language plpgsql
stable
set search_path = ''
as $$
declare
  v_person uuid;
  v_people uuid[];
begin
  if p_series.assignment_mode = 'rotate' then
    v_person := private.rotation_assignee(p_series, p_date);
    return case when v_person is null then '{}'::uuid[] else array[v_person] end;
  end if;
  select coalesce(array_agg(a.user_id order by a.position, a.user_id), '{}') into v_people
  from public.series_assignees a
  join public.family_members m on m.family_id = p_series.family_id and m.user_id = a.user_id
  where a.series_id = p_series.id;
  return v_people;
end;
$$;

revoke execute on function private.occurrence_assignees(public.task_series, date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Erzeugung: wie 0009, Zuweisung über occurrence_assignees
-- ---------------------------------------------------------------------------

create or replace function private.generate_series_occurrences(p_series_id uuid)
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

  -- Automatisch erzeugte Zuweisungen lösen keine „zugewiesen“-Mitteilung aus (notify_assignment).
  perform set_config('familiar.generating', 'on', true);
  foreach v_date in array v_dates loop
    v_task_id := null;
    insert into public.tasks (family_id, series_id, occurrence_date, created_by, title, description,
                              start_date, start_time, timezone, completion_mode)
    values (v_series.family_id, v_series.id, v_date, v_series.created_by, v_series.title, v_series.description,
            v_date, v_series.start_time, v_series.timezone, v_series.completion_mode)
    on conflict (series_id, occurrence_date) do nothing
    returning id into v_task_id;

    if v_task_id is not null then
      -- Nur Personen, die noch Mitglied sind (occurrence_assignees prüft das).
      insert into public.task_assignees (task_id, user_id, assigned_by)
      select v_task_id, p.id,
             (select a.assigned_by from public.series_assignees a where a.series_id = v_series.id and a.user_id = p.id)
      from unnest(private.occurrence_assignees(v_series, v_date)) as p(id);

      insert into public.task_image_links (task_id, image_id, position)
      select v_task_id, l.image_id, l.position
      from public.series_image_links l
      where l.series_id = v_series.id;

      v_count := v_count + 1;
    end if;
  end loop;
  perform set_config('familiar.generating', 'off', true);

  update public.task_series s
     set generated_until = greatest(s.generated_until, v_dates[cardinality(v_dates)])
   where s.id = v_series.id;

  return v_count;
end;
$$;

revoke execute on function private.generate_series_occurrences(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Mitteilungen bei Zuweisungen (Serien, Tauschen)
-- ---------------------------------------------------------------------------

-- Neue Serie: einmal „zugewiesen“ an die Personen des ersten offenen Termins (nicht an sich selbst).
create function private.notify_new_series(p_series_id uuid, p_actor uuid, p_today date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_first uuid;
  v_user  uuid;
begin
  select t.id into v_first from public.tasks t
  where t.series_id = p_series_id and t.occurrence_date >= p_today and t.deleted_at is null
  order by t.occurrence_date
  limit 1;
  if v_first is null then
    return;
  end if;
  for v_user in
    select a.user_id from public.task_assignees a where a.task_id = v_first and a.user_id is distinct from p_actor
  loop
    perform private.enqueue_notification('assigned', v_first, v_user, p_actor,
      'assigned:' || v_first || ':' || v_user || ':series');
  end loop;
end;
$$;

revoke execute on function private.notify_new_series(uuid, uuid, date) from public, anon, authenticated;

-- Wie 0012, aber Serien-Vorkommen melden sich auch – außer bei der automatischen Erzeugung.
-- So erfährt beim Tauschen oder Umstellen der Reihenfolge die neue Person davon.
create or replace function private.notify_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('familiar.generating', true), 'off') = 'on' then
    return null;
  end if;
  if new.user_id is distinct from new.assigned_by then
    perform private.enqueue_notification('assigned', new.task_id, new.user_id, new.assigned_by,
      'assigned:' || new.task_id || ':' || new.user_id || ':' || extract(epoch from new.assigned_at)::bigint);
  end if;
  return null;
end;
$$;

revoke execute on function private.notify_assignment() from public, anon, authenticated;

-- Zuweisung entfernt (z. B. Termin getauscht): laufende Live Activity dieser Person beenden.
-- Nur bei noch offenen, existierenden Aufgaben – beim Löschen ganzer Aufgaben (Kaskade) nicht.
create function private.notify_unassignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.tasks t
             where t.id = old.task_id and t.completed_at is null and t.deleted_at is null) then
    perform private.enqueue_activity_end(old.task_id, old.user_id,
      'unassigned:' || floor(extract(epoch from now()))::bigint);
  end if;
  return null;
end;
$$;

revoke execute on function private.notify_unassignment() from public, anon, authenticated;

create trigger task_assignees_notify_removal
  after delete on public.task_assignees
  for each row execute function private.notify_unassignment();

-- ---------------------------------------------------------------------------
-- Serien-RPCs mit Reihum-Angaben (neue Signatur)
-- ---------------------------------------------------------------------------

drop function public.create_recurring_task(uuid, text, public.completion_mode, uuid[], public.recurrence_freq, date,
                                           smallint[], smallint[], text, time, text, jsonb);

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
  p_rotation_unit text default 'occurrence'
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
  v_series      public.task_series;
begin
  perform private.require_member(p_family_id);
  perform private.require_task_permission(p_family_id, 'create_tasks');
  if p_start_date is null then
    perform private.raise_app_error('recurrence_requires_date');
  end if;
  perform private.validate_task_input(p_family_id, p_title, v_description, p_start_date, p_start_time,
                                      p_timezone, p_completion_mode, v_assignees);
  v_mode := private.validate_rotation(p_assignment_mode, p_rotation_unit, v_assignees, p_completion_mode);
  select r.weekdays, r.month_days into v_weekdays, v_month_days
  from private.normalize_recurrence(p_freq, p_weekdays, p_month_days) as r;

  v_today := (now() at time zone p_timezone)::date;

  insert into public.task_series (family_id, created_by, title, description, completion_mode, freq,
                                  weekdays, month_days, start_date, start_time, timezone, generated_until,
                                  assignment_mode, rotation_unit, rotation_start)
  values (p_family_id, v_uid, btrim(p_title), v_description, v_mode, p_freq,
          v_weekdays, v_month_days, p_start_date, p_start_time, p_timezone,
          case when p_start_date < v_today then v_today - 1 end,
          p_assignment_mode, p_rotation_unit, p_start_date)
  returning * into v_series;

  perform private.set_series_assignees(v_series.id, v_assignees);
  perform private.set_series_images(v_series.id, p_family_id, p_images);
  perform private.generate_series_occurrences(v_series.id);
  perform private.notify_new_series(v_series.id, v_uid, v_today);

  select * into v_series from public.task_series s where s.id = v_series.id;
  return v_series;
end;
$$;

drop function public.update_series_from(uuid, integer, text, public.completion_mode, uuid[], public.recurrence_freq,
                                        date, smallint[], smallint[], text, time, text, jsonb);

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

  select * into v_task from public.tasks t where t.id = p_task_id;
  return v_task;
end;
$$;

revoke execute on function public.create_recurring_task(uuid, text, public.completion_mode, uuid[], public.recurrence_freq,
  date, smallint[], smallint[], text, time, text, jsonb, text, text) from public, anon, service_role;
revoke execute on function public.update_series_from(uuid, integer, text, public.completion_mode, uuid[],
  public.recurrence_freq, date, smallint[], smallint[], text, time, text, jsonb, text, text) from public, anon, service_role;
grant execute on function public.create_recurring_task(uuid, text, public.completion_mode, uuid[], public.recurrence_freq,
  date, smallint[], smallint[], text, time, text, jsonb, text, text) to authenticated;
grant execute on function public.update_series_from(uuid, integer, text, public.completion_mode, uuid[],
  public.recurrence_freq, date, smallint[], smallint[], text, time, text, jsonb, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Anstupsen
-- ---------------------------------------------------------------------------

create table private.task_nudges (
  id         bigint generated always as identity primary key,
  task_id    uuid not null references public.tasks (id) on delete cascade,
  from_user  uuid not null references public.profiles (id) on delete cascade,
  to_user    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index task_nudges_lookup_idx on private.task_nudges (task_id, to_user, created_at);
create index task_nudges_from_user_idx on private.task_nudges (from_user);
create index task_nudges_to_user_idx on private.task_nudges (to_user);
create index task_nudges_created_at_idx on private.task_nudges (created_at);

alter table private.task_nudges enable row level security;

-- Erinnert eine zugewiesene, noch offene Person. Liefert, wann die Mitteilung zugestellt wird.
create function public.nudge_task(p_task_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_uid();
  v_task   public.tasks;
  v_local  timestamp;
  v_send   timestamptz := now();
  v_quiet  boolean := false;
begin
  v_task := private.lock_visible_task(p_task_id);
  if p_user_id = v_uid then
    perform private.raise_app_error('nudge_self');
  end if;
  if v_task.completed_at is not null or v_task.deleted_at is not null
     or not exists (select 1 from public.task_assignees a
                    where a.task_id = p_task_id and a.user_id = p_user_id and a.completed_at is null) then
    perform private.raise_app_error('nudge_not_open');
  end if;
  if exists (select 1 from private.task_nudges n
             where n.task_id = p_task_id and n.to_user = p_user_id and n.created_at > now() - interval '1 hour') then
    perform private.raise_app_error('nudge_too_soon');
  end if;

  -- Ruhezeit 21–7 Uhr in der Zeitzone der Aufgabe: Zustellung um 7 Uhr.
  v_local := now() at time zone v_task.timezone;
  if extract(hour from v_local) >= 21 or extract(hour from v_local) < 7 then
    v_quiet := true;
    v_send := ((case when extract(hour from v_local) >= 21 then v_local::date + 1 else v_local::date end)
               + time '07:00') at time zone v_task.timezone;
  end if;

  -- Alte Einträge braucht nur die Stunden-Grenze; nebenbei aufräumen.
  delete from private.task_nudges n where n.created_at < now() - interval '1 day';
  insert into private.task_nudges (task_id, from_user, to_user) values (p_task_id, v_uid, p_user_id);

  perform private.enqueue_notification('nudge', p_task_id, p_user_id, v_uid,
    'nudge:' || p_task_id || ':' || p_user_id || ':' || floor(extract(epoch from now()) / 3600)::bigint,
    v_send);

  return jsonb_build_object('scheduled_for', v_send, 'quiet_hours', v_quiet);
end;
$$;

revoke execute on function public.nudge_task(uuid, uuid) from public, anon, service_role;
grant execute on function public.nudge_task(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Prüf-Zugang für Apple (Edge Function review-sign-in): Fehlversuche begrenzen
-- ---------------------------------------------------------------------------

-- Höchstens 10 Fehlversuche pro Stunde (alle Absender zusammen); danach antwortet die Function 429.
create table private.review_sign_in_attempts (
  id         bigint generated always as identity primary key,
  succeeded  boolean not null,
  created_at timestamptz not null default now()
);

create index review_sign_in_attempts_created_at_idx on private.review_sign_in_attempts (created_at);

alter table private.review_sign_in_attempts enable row level security;

create function public.review_sign_in_allowed()
returns boolean
language sql
security definer
set search_path = ''
as $$
  select count(*) < 10 from private.review_sign_in_attempts a
  where not a.succeeded and a.created_at > now() - interval '1 hour';
$$;

create function public.review_sign_in_record(p_succeeded boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.review_sign_in_attempts a where a.created_at < now() - interval '1 day';
  insert into private.review_sign_in_attempts (succeeded) values (coalesce(p_succeeded, false));
end;
$$;

revoke execute on function public.review_sign_in_allowed() from public, anon, authenticated;
revoke execute on function public.review_sign_in_record(boolean) from public, anon, authenticated;
grant execute on function public.review_sign_in_allowed() to service_role;
grant execute on function public.review_sign_in_record(boolean) to service_role;

-- ---------------------------------------------------------------------------
-- Fehlerkatalog ergänzen
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
    ('permission_denied_delete_tasks',  '42501', 'In dieser Familie dürfen nur Admins Aufgaben löschen oder wiederherstellen.'),
    ('calendar_not_found',              'P0002', 'Kalender nicht gefunden.'),
    ('invalid_device_token',            '22023', 'Ungültiges Geräte-Token.'),
    ('invalid_rotation',                '22023', 'Unbekannte Reihum-Einstellung.'),
    ('rotation_needs_two',              '22023', 'Für „Reihum“ braucht es mindestens zwei Personen.'),
    ('nudge_self',                      '22023', 'Du kannst dich nicht selbst erinnern.'),
    ('nudge_not_open',                  'P0001', 'Diese Person hat die Aufgabe schon erledigt.'),
    ('nudge_too_soon',                  'P0001', 'Du hast diese Person gerade erst erinnert. Versuche es in einer Stunde noch einmal.')
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
