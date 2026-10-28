-- 0018_rotation_and_nudges
-- Reihum-Aufgaben und Anstupsen (ADR 0010).
--
-- Reihum: Bei Serien mit assignment_mode = 'rotate' bekommt jedes Vorkommen genau eine Person.
--   Dran ist liste[k mod n]: liste = Zugewiesene der Serie in Reihenfolge (position), nur aktuelle
--   Mitglieder. rotation_start ist immer ein echter Termin (der erste Termin der Reihe bzw. der
--   Termin, ab dem geändert wurde) und hat k = 0; danach zählt k die Serientermine in
--   (rotation_start, Termin] – so bekommt nach einer Regeländerung niemand zwei Termine hintereinander.
--   Bei rotation_unit = 'week' ist k die Anzahl ganzer ISO-Wochen zwischen den Montagen.
--   Gleiche Regel in Swift (RotationRules).
-- Sichtbarkeit: Wer bei einer Reihum-Serie mitmacht, sieht alle ihre Termine – auch in Familien mit
--   „nur Zugewiesene“ (sonst wären Tauschen und Erinnern unmöglich).
-- Austritt (Verlassen, Entfernen, Kontolöschung): offene Zuweisungen und Serienplätze der Person
--   entfallen; Reihum-Termine, bei denen sie dran war, gehen an die nächste Person.
-- Anstupsen: nudge_task legt einen Mitteilungsauftrag „nudge“ an; höchstens einmal pro Stunde je
--   Aufgabe und Person, Ruhezeit 21–7 Uhr (Zeitzone der Aufgabe) → eine gebündelte Zustellung um 7 Uhr.
-- Mitteilungen bei Serien (wichtig für Reihum):
--   * Automatisch erzeugte Vorkommen melden sich weiter nur über „Jetzt“/Erinnerungen – und die
--     bekommt nur, wer an dem Termin zugewiesen (bei Reihum: dran) ist.
--   * Neue Serie: wer beim ersten Termin dran bzw. zugewiesen ist, bekommt einmal „zugewiesen“.
--   * Tauschen eines Termins: Die neue Person bekommt „zugewiesen“, bei der bisherigen endet eine
--     laufende Live Activity.
--   * Ändern ab einem Termin: höchstens eine Mitteilung je Person – „zugewiesen“, wenn sich ihr
--     nächster Termin geändert hat, sonst „geändert“ bei relevanter Änderung (statt einer je Termin).
--   Sammeländerungen (Erzeugung, Ändern ab Termin, Austritt) setzen dafür die Transaktions-
--   Einstellung familiar.bulk_change = 'on'; die Trigger senden dann keine Einzelmitteilungen.
--
-- Enthält drop function/policy und delete → im Supabase-SQL-Editor ausführen.

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

-- Index des Termins in der Reihe (0 = erste Person der Liste). rotation_start selbst hat immer 0,
-- auch wenn er nach einer Regeländerung nicht auf die neue Regel fällt.
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
    when p_date <= coalesce(p_series.rotation_start, p_series.start_date) then 0
    else
      (select count(*)::int
       from private.series_dates(p_series.freq, p_series.weekdays, p_series.month_days,
                                 coalesce(p_series.rotation_start, p_series.start_date) + 1, p_date))
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
  v_bulk    text := coalesce(current_setting('familiar.bulk_change', true), '');
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
  perform set_config('familiar.bulk_change', 'on', true);
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
  -- Vorherigen Wert wiederherstellen (läuft auch innerhalb anderer Sammeländerungen).
  perform set_config('familiar.bulk_change', v_bulk, true);

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

-- Wie 0012, aber Serien-Vorkommen melden sich auch – außer bei Sammeländerungen (Erzeugung,
-- Ändern ab Termin, Austritt; die melden selbst gesammelt). So erfährt beim Tauschen die neue Person davon.
create or replace function private.notify_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(current_setting('familiar.bulk_change', true), '') = 'on' then
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
-- Nur bei noch offenen, existierenden Aufgaben – beim Löschen ganzer Aufgaben (Kaskade) nicht – und
-- nur, solange es die Person noch gibt: Bei der Kontolöschung verschwinden ihre Zuweisungen per
-- Kaskade, ein Auftrag für das gelöschte Profil würde die Löschung abbrechen (Fremdschlüssel).
create function private.notify_unassignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.tasks t
             where t.id = old.task_id and t.completed_at is null and t.deleted_at is null)
     and exists (select 1 from public.profiles p where p.id = old.user_id) then
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

-- Wie 0012, aber nur für Personen, die es noch gibt. Während einer Kontolöschung laufen Trigger
-- (Austritt, Zuweisungen, Live Activities), solange die Zeilen der Person noch nicht alle per
-- Kaskade weg sind; ein Auftrag für das gelöschte Profil würde die Löschung abbrechen.
create or replace function private.enqueue_notification(
  p_kind public.notification_kind,
  p_task_id uuid,
  p_user_id uuid,
  p_actor_id uuid,
  p_dedupe_key text,
  p_scheduled_for timestamptz default now()
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notification_jobs (kind, task_id, user_id, actor_id, scheduled_for, dedupe_key)
  select p_kind, p_task_id, p_user_id,
         (select a.id from public.profiles a where a.id = p_actor_id),
         p_scheduled_for, p_dedupe_key
  where exists (select 1 from public.profiles p where p.id = p_user_id)
  on conflict (dedupe_key) do nothing;
$$;

revoke execute on function private.enqueue_notification(public.notification_kind, uuid, uuid, uuid, text, timestamptz)
  from public, anon, authenticated;

-- Wie 0012, aber nur Live Activities auf angemeldeten Geräten (abgemeldete bekommen keine Pushes mehr).
create or replace function private.enqueue_activity_end(p_task_id uuid, p_user_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  for v_user in
    select distinct a.user_id
    from public.live_activities a
    join public.devices d on d.id = a.device_id and d.invalidated_at is null
    where a.task_id = p_task_id and a.state = 'active' and (p_user_id is null or a.user_id = p_user_id)
  loop
    perform private.enqueue_notification('activity_end', p_task_id, v_user, null,
      'activity_end:' || p_task_id || ':' || v_user || ':' || p_reason);
  end loop;
end;
$$;

revoke execute on function private.enqueue_activity_end(uuid, uuid, text) from public, anon, authenticated;

-- Wie 0012; bei Sammeländerungen keine „geändert“-Mitteilung je Termin (update_series_from meldet
-- gesammelt). Live-Activity-Aktualisierungen laufen unverändert.
create or replace function private.notify_task_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_user  uuid;
begin
  -- Komplett erledigt: Ersteller + Zugewiesene, außer wer selbst abgehakt hat; alle Activities enden.
  if old.completed_at is null and new.completed_at is not null then
    for v_user in
      select distinct u from (
        select new.created_by as u
        union all
        select a.user_id from public.task_assignees a where a.task_id = new.id
      ) x
      where u is not null
        and u is distinct from new.completed_by
        and not exists (
          select 1 from public.task_assignees a
          where a.task_id = new.id and a.user_id = x.u and a.completed_at is not null
        )
    loop
      perform private.enqueue_notification('completed', new.id, v_user, new.completed_by,
        'completed:' || new.id || ':' || v_user || ':' || extract(epoch from new.completed_at)::bigint);
    end loop;
    perform private.enqueue_activity_end(new.id, null, 'completed:' || extract(epoch from new.completed_at)::bigint);
    return null;
  end if;

  -- Gelöscht (einzeln oder mit der Serie): Zugewiesene außer dem Auslöser; Activities enden.
  if old.deleted_at is null and new.deleted_at is not null then
    if new.deleted_by_series_op is null then
      for v_user in
        select a.user_id from public.task_assignees a
        where a.task_id = new.id and a.user_id is distinct from new.deleted_by and a.completed_at is null
      loop
        perform private.enqueue_notification('deleted', new.id, v_user, new.deleted_by,
          'deleted:' || new.id || ':' || v_user || ':' || extract(epoch from new.deleted_at)::bigint);
      end loop;
    end if;
    perform private.enqueue_activity_end(new.id, null, 'deleted:' || extract(epoch from new.deleted_at)::bigint);
    return null;
  end if;

  -- Relevante Änderung an einer offenen Aufgabe (E6).
  if new.completed_at is null and new.deleted_at is null and (
       new.title is distinct from old.title
       or new.start_date is distinct from old.start_date
       or new.start_time is distinct from old.start_time
       or new.completion_mode is distinct from old.completion_mode
     ) then
    if coalesce(current_setting('familiar.bulk_change', true), '') <> 'on' then
      for v_user in
        select a.user_id from public.task_assignees a
        where a.task_id = new.id and a.user_id is distinct from v_actor and a.completed_at is null
      loop
        perform private.enqueue_notification('changed', new.id, v_user, v_actor,
          'changed:' || new.id || ':' || v_user || ':' || new.version);
      end loop;
    end if;
    if new.start_date is distinct from old.start_date or new.start_time is distinct from old.start_time then
      -- Neue Startzeit: laufende Activity endet; die neue startet zur neuen Zeit.
      perform private.enqueue_activity_end(new.id, null, 'rescheduled:' || new.version);
    else
      for v_user in
        select distinct a.user_id from public.live_activities a where a.task_id = new.id and a.state = 'active'
      loop
        perform private.enqueue_notification('activity_update', new.id, v_user, v_actor,
          'activity_update:' || new.id || ':' || v_user || ':' || new.version);
      end loop;
    end if;
  elsif new.completed_at is null and new.deleted_at is null and new.version is distinct from old.version then
    -- Sonstige Änderung (z. B. jemand hat abgehakt): Personenstatus in laufenden Activities.
    for v_user in
      select distinct a.user_id from public.live_activities a where a.task_id = new.id and a.state = 'active'
    loop
      perform private.enqueue_notification('activity_update', new.id, v_user, v_actor,
        'activity_update:' || new.id || ':' || v_user || ':' || new.version);
    end loop;
  end if;
  return null;
end;
$$;

revoke execute on function private.notify_task_change() from public, anon, authenticated;

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
  v_first       date;
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

  -- Die Reihe beginnt beim ersten Termin, der tatsächlich entsteht (Vergangenes wird nicht erzeugt):
  -- So ist die erste Person der Liste wirklich als Erste dran.
  select d into v_first
  from private.series_dates(p_freq, v_weekdays, v_month_days, greatest(p_start_date, v_today),
                            greatest(p_start_date, v_today) + 62) as d
  order by d
  limit 1;

  insert into public.task_series (family_id, created_by, title, description, completion_mode, freq,
                                  weekdays, month_days, start_date, start_time, timezone, generated_until,
                                  assignment_mode, rotation_unit, rotation_start)
  values (p_family_id, v_uid, btrim(p_title), v_description, v_mode, p_freq,
          v_weekdays, v_month_days, p_start_date, p_start_time, p_timezone,
          case when p_start_date < v_today then v_today - 1 end,
          p_assignment_mode, p_rotation_unit, coalesce(v_first, greatest(p_start_date, v_today)))
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

revoke execute on function public.create_recurring_task(uuid, text, public.completion_mode, uuid[], public.recurrence_freq,
  date, smallint[], smallint[], text, time, text, jsonb, text, text) from public, anon, service_role;
revoke execute on function public.update_series_from(uuid, integer, text, public.completion_mode, uuid[],
  public.recurrence_freq, date, smallint[], smallint[], text, time, text, jsonb, text, text) from public, anon, service_role;
grant execute on function public.create_recurring_task(uuid, text, public.completion_mode, uuid[], public.recurrence_freq,
  date, smallint[], smallint[], text, time, text, jsonb, text, text) to authenticated;
grant execute on function public.update_series_from(uuid, integer, text, public.completion_mode, uuid[],
  public.recurrence_freq, date, smallint[], smallint[], text, time, text, jsonb, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Austritt aus einer Familie (Verlassen, Entfernen, Kontolöschung)
-- ---------------------------------------------------------------------------

-- Wer nicht mehr Mitglied ist, ist für nichts mehr zuständig: Offene Zuweisungen in der Familie und
-- die Plätze in Serien entfallen, eine laufende Live Activity endet (notify_unassignment).
-- Reihum-Termine ohne zuständige Person gehen an die Person, die nach der Regel dran ist – ohne
-- „zugewiesen“-Mitteilung; „Jetzt“ und Erinnerungen folgen wie üblich.
-- „Jede Person einzeln“: Haben alle Übrigen erledigt, ist die Aufgabe komplett.
-- Bei der Kontolöschung können die Zeilen der Person schon per Kaskade fehlen; deshalb wird über die
-- ganze Familie geprüft, nicht nur über die Zeilen der Person.
create function private.handle_member_departure()
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

revoke execute on function private.handle_member_departure() from public, anon, authenticated;

create trigger family_members_departure
  after delete on public.family_members
  for each row execute function private.handle_member_departure();

-- Einmalig: Zuweisungen von Personen, die schon vor dieser Migration ausgetreten sind (die App ist noch
-- nicht veröffentlicht; Reihum gab es vorher nicht – Neuverteilung von Terminen übernimmt der Trigger).
delete from public.series_assignees a
 using public.task_series s
 where s.id = a.series_id
   and not exists (select 1 from public.family_members m where m.family_id = s.family_id and m.user_id = a.user_id);

delete from public.task_assignees a
 using public.tasks t
 where t.id = a.task_id
   and t.completed_at is null
   and t.deleted_at is null
   and a.completed_at is null
   and not exists (select 1 from public.family_members m where m.family_id = t.family_id and m.user_id = a.user_id);

-- ---------------------------------------------------------------------------
-- Sichtbarkeit: Wer bei einer Reihum-Serie mitmacht, sieht alle ihre Termine
-- ---------------------------------------------------------------------------

-- Reihum-Serien, bei denen der Nutzer mitmacht.
create function private.my_rotation_series_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select a.series_id
  from public.series_assignees a
  join public.task_series s on s.id = a.series_id and s.assignment_mode = 'rotate'
  where a.user_id = (select auth.uid());
$$;

revoke execute on function private.my_rotation_series_ids() from public, anon;
grant execute on function private.my_rotation_series_ids() to authenticated;

-- Wie 0007, zusätzlich: Termin einer Reihum-Serie, bei der der Nutzer mitmacht.
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
        f.task_visibility = 'all'
        or t.created_by = (select auth.uid())
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
  );
$$;

alter policy "tasks_select_visible"
  on public.tasks
  using (
    family_id = any (array (select private.my_family_ids()))
    and (
      family_id = any (array (select private.my_all_tasks_family_ids()))
      or created_by = (select auth.uid())
      or id = any (array (select private.my_assigned_task_ids()))
      or series_id = any (array (select private.my_rotation_series_ids()))
    )
  );

-- ---------------------------------------------------------------------------
-- Mitteilungen nur an aktuelle Mitglieder
-- ---------------------------------------------------------------------------

-- Wie 0012, aber nur für Personen, die noch Mitglied der Familie sind.
create or replace function private.enqueue_due_notifications()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now    timestamptz := now();
  v_row    record;
  v_anchor timestamptz;
  v_slot   timestamptz;
  v_lead   interval;
  v_count  integer := 0;
begin
  for v_row in
    select t as task, a.user_id, a.assigned_at
    from public.tasks t
    join public.task_assignees a on a.task_id = t.id and a.completed_at is null
    -- Nur aktuelle Mitglieder (wer ausgetreten ist, bekommt nichts mehr aus der Familie).
    join public.family_members m on m.family_id = t.family_id and m.user_id = a.user_id
    where t.completed_at is null
      and t.deleted_at is null
      -- Nur Aufgaben, deren Bezugspunkt in den letzten 31 Tagen oder der nächsten Viertelstunde liegt.
      and coalesce(t.starts_at, a.assigned_at) > v_now - interval '31 days'
      and coalesce(t.starts_at, a.assigned_at) < v_now + interval '15 minutes'
  loop
    v_anchor := private.notification_anchor(v_row.task, v_row.assigned_at);
    if v_anchor is null then
      continue;
    end if;

    -- Live Activity: mit Uhrzeit 5 Minuten vorher, sonst zum Bezugspunkt; nur innerhalb 1 h danach.
    -- (Kein CASE in der IF-Bedingung: PL/pgSQL beendet sie beim ersten THEN.)
    v_lead := case when (v_row.task).start_time is not null then interval '5 minutes' else interval '0' end;
    if v_now >= v_anchor - v_lead and v_now < v_anchor + interval '1 hour' then
      perform private.enqueue_notification('activity_start', (v_row.task).id, v_row.user_id, null,
        'activity_start:' || (v_row.task).id || ':' || v_row.user_id || ':' || extract(epoch from v_anchor)::bigint);
      v_count := v_count + 1;
    end if;

    -- „Jetzt“: zum Bezugspunkt (nicht bei Aufgaben ohne Datum – dort gab es „zugewiesen“).
    if (v_row.task).start_date is not null and v_now >= v_anchor and v_now < v_anchor + interval '1 hour' then
      perform private.enqueue_notification('started', (v_row.task).id, v_row.user_id, null,
        'started:' || (v_row.task).id || ':' || v_row.user_id || ':' || extract(epoch from v_anchor)::bigint);
    end if;

    -- Erinnerungen: mit Uhrzeit 1 h nach Start, dann alle 24 h; sonst alle 24 h nach dem Bezugspunkt.
    v_slot := v_anchor + case when (v_row.task).start_time is not null then interval '1 hour' else interval '24 hours' end;
    if v_now >= v_slot then
      v_slot := v_slot + floor(extract(epoch from (v_now - v_slot)) / 86400) * interval '24 hours';
      -- Nur frisch fällige Slots (keine Nachholflut nach Ausfällen).
      if v_now < v_slot + interval '30 minutes' then
        perform private.enqueue_notification('reminder', (v_row.task).id, v_row.user_id, null,
          'reminder:' || (v_row.task).id || ':' || v_row.user_id || ':' || extract(epoch from v_slot)::bigint);
      end if;
    end if;
  end loop;
  return v_count;
end;
$$;

revoke execute on function private.enqueue_due_notifications() from public, anon, authenticated;

-- Wie 0014, zusätzlich is_member: push-dispatch überspringt Aufträge an Ausgetretene
-- (außer dem Ende einer Live Activity).
create or replace function public.push_claim_jobs(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim uuid := gen_random_uuid();
begin
  update private.cron_tokens t
     set used_at = now()
   where t.token_hash = encode(sha256(convert_to(coalesce(p_token, ''), 'UTF8')), 'hex')
     and t.purpose = 'push_dispatch'
     and t.used_at is null
     and t.created_at > now() - interval '15 minutes';
  if not found then
    raise exception using errcode = '42501', message = 'Ungültiges oder abgelaufenes Token.';
  end if;

  -- Hängengebliebene Aufträge (z. B. Abbruch der Function) nach 10 Minuten wieder freigeben.
  update public.notification_jobs j
     set status = 'pending'
   where j.status = 'sending' and j.claimed_at < now() - interval '10 minutes';

  update public.notification_jobs j
     set status = 'sending', attempts = j.attempts + 1, claim_id = v_claim, claimed_at = now()
   where j.id in (
     select j2.id from public.notification_jobs j2
     where j2.status = 'pending' and j2.scheduled_for <= now()
     order by j2.scheduled_for, j2.id
     limit 200
     for update skip locked
   );

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', j.id,
      'kind', j.kind,
      'task_id', j.task_id,
      'user_id', j.user_id,
      'actor_name', (select p.display_name from public.profiles p where p.id = j.actor_id),
      'title', t.title,
      'family_name', f.name,
      'family_color', f.color_hex,
      'starts_at_unix', case when t.start_time is not null then extract(epoch from t.starts_at) end,
      'completion_mode', t.completion_mode,
      -- Nur noch Mitglieder der Familie bekommen Inhalte; Live-Activity-Ende geht trotzdem raus.
      'is_member', exists (select 1 from public.family_members m
                           where m.family_id = t.family_id and m.user_id = j.user_id),
      'is_open', t.completed_at is null and t.deleted_at is null and exists (
                   select 1 from public.task_assignees a
                   where a.task_id = t.id and a.user_id = j.user_id and a.completed_at is null
                 ),
      'can_complete', exists (
                        select 1 from public.task_assignees a
                        where a.task_id = t.id and a.user_id = j.user_id and a.completed_at is null
                      ) or t.created_by = j.user_id,
      'assignees', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'initials', upper(left(coalesce(p.display_name, '?'), 1)),
                 'isDone', a.completed_at is not null) order by p.display_name), '[]'::jsonb)
        from public.task_assignees a join public.profiles p on p.id = a.user_id
        where a.task_id = t.id
      ),
      'devices', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'id', d.id, 'token', d.apns_token, 'environment', d.apns_environment,
                 'push_to_start_token', d.push_to_start_token)), '[]'::jsonb)
        from public.devices d where d.user_id = j.user_id and d.invalidated_at is null
      ),
      'activities', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'id', a.id, 'update_token', a.update_token, 'environment', d.apns_environment)), '[]'::jsonb)
        from public.live_activities a join public.devices d on d.id = a.device_id
        where a.task_id = j.task_id and a.user_id = j.user_id and a.state = 'active' and a.update_token is not null
      )
    ) order by j.id)
    from public.notification_jobs j
    left join public.tasks t on t.id = j.task_id
    left join public.families f on f.id = t.family_id
    where j.claim_id = v_claim and j.status = 'sending'
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.push_claim_jobs(text) from public, anon, authenticated;
grant execute on function public.push_claim_jobs(text) to service_role;

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
create policy "task_nudges_deny_all" on private.task_nudges for all using (false) with check (false);
revoke all on table private.task_nudges from public, anon, authenticated;

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
  if v_task.completed_at is not null or v_task.deleted_at is not null then
    perform private.raise_app_error('nudge_not_open');
  end if;
  if not exists (select 1 from public.family_members m
                 where m.family_id = v_task.family_id and m.user_id = p_user_id) then
    perform private.raise_app_error('member_not_found');
  end if;
  if not exists (select 1 from public.task_assignees a
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

  -- Alte Einträge löscht täglich private.purge_notifications (nach einem Tag).
  insert into private.task_nudges (task_id, from_user, to_user) values (p_task_id, v_uid, p_user_id);

  -- Während der Ruhezeit fallen alle Erinnerungen an diese Person zu einer um 7 Uhr zusammen.
  perform private.enqueue_notification('nudge', p_task_id, p_user_id, v_uid,
    'nudge:' || p_task_id || ':' || p_user_id || ':'
      || case when v_quiet then 'quiet:' || extract(epoch from v_send)::bigint
              else floor(extract(epoch from now()) / 3600)::bigint::text end,
    v_send);

  return jsonb_build_object('scheduled_for', v_send, 'quiet_hours', v_quiet);
end;
$$;

revoke execute on function public.nudge_task(uuid, uuid) from public, anon, service_role;
grant execute on function public.nudge_task(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Prüf-Zugang für Apple (Edge Function review-sign-in): Fehlversuche begrenzen
-- ---------------------------------------------------------------------------

-- Höchstens 10 Fehlversuche pro Stunde (für die Prüf-Adresse, alle Absender zusammen); danach
-- antwortet die Function 429. Jeder Versuch zählt zunächst als Fehlversuch und wird erst nach
-- richtigem Code als erfolgreich markiert – so kommen auch gleichzeitige Anfragen nicht an der
-- Grenze vorbei (Sperre per Advisory Lock). Einträge löscht täglich private.purge_notifications.
create table private.review_sign_in_attempts (
  id         bigint generated always as identity primary key,
  succeeded  boolean not null default false,
  created_at timestamptz not null default now()
);

create index review_sign_in_attempts_created_at_idx on private.review_sign_in_attempts (created_at);

alter table private.review_sign_in_attempts enable row level security;
create policy "review_sign_in_attempts_deny_all" on private.review_sign_in_attempts
  for all using (false) with check (false);
revoke all on table private.review_sign_in_attempts from public, anon, authenticated;

-- Versuch anmelden: liefert dessen Nummer oder null, wenn der Zugang gerade gesperrt ist.
create function public.review_sign_in_begin()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('familiar.review_sign_in'));
  if (select count(*) from private.review_sign_in_attempts a
      where not a.succeeded and a.created_at > now() - interval '1 hour') >= 10 then
    return null;
  end if;
  insert into private.review_sign_in_attempts default values returning id into v_id;
  return v_id;
end;
$$;

-- Richtiger Code: Versuch zählt nicht mehr als Fehlversuch.
create function public.review_sign_in_succeeded(p_attempt_id bigint)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.review_sign_in_attempts a
     set succeeded = true
   where a.id = p_attempt_id and a.created_at > now() - interval '5 minutes';
$$;

revoke execute on function public.review_sign_in_begin() from public, anon, authenticated;
revoke execute on function public.review_sign_in_succeeded(bigint) from public, anon, authenticated;
grant execute on function public.review_sign_in_begin() to service_role;
grant execute on function public.review_sign_in_succeeded(bigint) to service_role;

-- ---------------------------------------------------------------------------
-- Tägliche Bereinigung (wie 0015) um Erinnern und Prüf-Zugang ergänzen (Löschfrist ein Tag)
-- ---------------------------------------------------------------------------

create or replace function private.purge_notifications()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.notification_jobs j
   where j.created_at < now() - interval '30 days'
     and j.status in ('sent', 'failed', 'skipped');
  delete from public.live_activities a
   where a.state = 'ended' and a.ended_at < now() - interval '30 days';
  -- Abgemeldete bzw. von APNs abgelehnte Geräte (Activities hängen per cascade daran).
  delete from public.devices d
   where d.invalidated_at < now() - interval '30 days';
  delete from private.cron_tokens t
   where t.created_at < now() - interval '1 day';
  delete from private.task_nudges n
   where n.created_at < now() - interval '1 day';
  delete from private.review_sign_in_attempts a
   where a.created_at < now() - interval '1 day';
end;
$$;

revoke execute on function private.purge_notifications() from public, anon, authenticated;

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
    ('nudge_not_open',                  'P0001', 'Für diese Person ist die Aufgabe nicht mehr offen.'),
    ('nudge_too_soon',                  'P0001', 'Diese Person wurde in der letzten Stunde schon erinnert. Versuche es später noch einmal.')
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

-- Eingespielt über den SQL-Editor: Eintrag in der Migrationsliste gleich mit anlegen (wie 0015).
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261024120000', '0018_rotation_and_nudges', array['-- siehe supabase/migrations/0018_rotation_and_nudges.sql']);
