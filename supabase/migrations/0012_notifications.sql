-- 0012_notifications
-- Mitteilungen und Live Activities (Phase 7, Plan Abschnitt 5, ADR 0005).
--
-- Grundsätze:
--   * Die Datenbank bleibt maßgeblich; Mitteilungen sind nur Hinweise.
--   * Ereignisse (zugewiesen, erledigt, geändert, gelöscht) legen Trigger sofort als Auftrag an.
--   * Zeitgesteuertes (Live Activity 5 min vor Start, „Jetzt“, Erinnerungen) wird nicht im Voraus
--     geplant: private.enqueue_due_notifications() prüft jede Minute aus dem aktuellen Stand, was
--     gerade fällig ist. Änderungen an Startzeit, Zuweisung oder Erledigung wirken so automatisch;
--     nichts muss storniert werden. dedupe_key (eindeutig) verhindert Doppelte.
--   * push-dispatch (Edge Function, Einmal-Token wie purge-history) holt fällige Aufträge samt
--     Geräte-Tokens, sendet an APNs und meldet Ergebnisse zurück; ungültige Tokens werden markiert.
-- Entscheidungen (Vorschläge laut Plan, gelten bis zum Widerspruch):
--   E3: Nur-Datum: Mitteilung + Live Activity um 08:00 Ortszeit (Aufgaben-Zeitzone) am Tag selbst
--       (liegt die Zuweisung später, ab Zuweisung); ohne Datum: sofort; Erinnerungen danach alle 24 h.
--   E5: Kein automatischer Neustart einer Live Activity nach dem 8-h-Limit.
--   E6: „Relevante Änderung“ = Titel, Startzeit, Erledigungsart (Zuweisung über eigene Aufträge),
--       Löschung. Beschreibung und Bilder lösen nichts aus.
-- Bewusst ohne DELETE: Geräte werden beim Abmelden ungültig markiert; alte Aufträge räumt die
-- 30-Tage-Bereinigung auf (Folgemigration).

-- ---------------------------------------------------------------------------
-- Typen und Tabellen
-- ---------------------------------------------------------------------------

create type public.apns_environment as enum ('sandbox', 'production');
create type public.notification_kind as enum (
  'assigned', 'started', 'reminder', 'completed', 'changed', 'deleted',
  'activity_start', 'activity_update', 'activity_end'
);
create type public.notification_status as enum ('pending', 'sending', 'sent', 'failed', 'skipped');
create type public.live_activity_state as enum ('active', 'ended');

create table public.devices (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references public.profiles (id) on delete cascade,
  apns_token           text not null unique,
  apns_environment     public.apns_environment not null,
  push_to_start_token  text,
  app_version          text,
  timezone             text,
  last_seen_at         timestamptz not null default now(),
  invalidated_at       timestamptz,
  created_at           timestamptz not null default now()
);

create index devices_user_id_idx on public.devices (user_id) where invalidated_at is null;

create table public.live_activities (
  id            uuid primary key default gen_random_uuid(),
  task_id       uuid not null references public.tasks (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  device_id     uuid not null references public.devices (id) on delete cascade,
  activity_id   text not null,
  update_token  text,
  state         public.live_activity_state not null default 'active',
  started_at    timestamptz not null default now(),
  ended_at      timestamptz,
  constraint live_activities_activity_unique unique (device_id, activity_id)
);

create index live_activities_task_idx on public.live_activities (task_id) where state = 'active';
create index live_activities_user_id_idx on public.live_activities (user_id);

create table public.notification_jobs (
  id             bigint generated always as identity primary key,
  kind           public.notification_kind not null,
  task_id        uuid references public.tasks (id) on delete cascade,
  user_id        uuid not null references public.profiles (id) on delete cascade,
  actor_id       uuid references public.profiles (id) on delete set null,
  scheduled_for  timestamptz not null default now(),
  status         public.notification_status not null default 'pending',
  attempts       integer not null default 0,
  last_error     text,
  sent_at        timestamptz,
  claim_id       uuid,
  claimed_at     timestamptz,
  dedupe_key     text not null unique,
  created_at     timestamptz not null default now()
);

create index notification_jobs_due_idx on public.notification_jobs (scheduled_for) where status = 'pending';
create index notification_jobs_claim_idx on public.notification_jobs (claim_id) where status = 'sending';
create index notification_jobs_task_idx on public.notification_jobs (task_id);
create index notification_jobs_user_idx on public.notification_jobs (user_id);
create index notification_jobs_actor_idx on public.notification_jobs (actor_id);

-- RLS: Geräte und Live Activities nur eigene lesen; Aufträge gar nicht.
alter table public.devices           enable row level security;
alter table public.live_activities   enable row level security;
alter table public.notification_jobs enable row level security;

revoke all on table public.devices, public.live_activities, public.notification_jobs from anon, authenticated;
grant select on table public.devices, public.live_activities to authenticated;

create policy "devices_select_own" on public.devices
  for select to authenticated using (user_id = (select auth.uid()));
create policy "live_activities_select_own" on public.live_activities
  for select to authenticated using (user_id = (select auth.uid()));
create policy "notification_jobs_deny_all" on public.notification_jobs for all using (false);

-- ---------------------------------------------------------------------------
-- Aufträge anlegen
-- ---------------------------------------------------------------------------

-- Legt einen Auftrag an; doppelte dedupe_keys werden ignoriert.
create function private.enqueue_notification(
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
  values (p_kind, p_task_id, p_user_id, p_actor_id, p_scheduled_for, p_dedupe_key)
  on conflict (dedupe_key) do nothing;
$$;

revoke execute on function private.enqueue_notification(public.notification_kind, uuid, uuid, uuid, text, timestamptz)
  from public, anon, authenticated;

-- Ende aller aktiven Live Activities einer Aufgabe (optional nur für eine Person).
create function private.enqueue_activity_end(p_task_id uuid, p_user_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
begin
  for v_user in
    select distinct a.user_id from public.live_activities a
    where a.task_id = p_task_id and a.state = 'active' and (p_user_id is null or a.user_id = p_user_id)
  loop
    perform private.enqueue_notification('activity_end', p_task_id, v_user, null,
      'activity_end:' || p_task_id || ':' || v_user || ':' || p_reason);
  end loop;
end;
$$;

revoke execute on function private.enqueue_activity_end(uuid, uuid, text) from public, anon, authenticated;

-- Zuweisung: neu zugewiesene Person (nicht der Auslöser). Vorkommen einer Serie melden sich über
-- „Jetzt“/Erinnerungen, nicht bei jeder Erzeugung.
create function private.notify_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_series uuid;
begin
  select t.series_id into v_series from public.tasks t where t.id = new.task_id;
  if v_series is null and new.user_id is distinct from new.assigned_by then
    perform private.enqueue_notification('assigned', new.task_id, new.user_id, new.assigned_by,
      'assigned:' || new.task_id || ':' || new.user_id || ':' || extract(epoch from new.assigned_at)::bigint);
  end if;
  return null;
end;
$$;

revoke execute on function private.notify_assignment() from public, anon, authenticated;

create trigger task_assignees_notify
  after insert on public.task_assignees
  for each row execute function private.notify_assignment();

-- Eigener Haken („einzeln“): eigene Live Activity endet.
create function private.notify_assignee_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.completed_at is null and new.completed_at is not null then
    perform private.enqueue_activity_end(new.task_id, new.user_id,
      'self_done:' || extract(epoch from new.completed_at)::bigint);
  end if;
  return null;
end;
$$;

revoke execute on function private.notify_assignee_completion() from public, anon, authenticated;

create trigger task_assignees_notify_completion
  after update of completed_at on public.task_assignees
  for each row execute function private.notify_assignee_completion();

-- Aufgabe erledigt, gelöscht oder relevant geändert.
create function private.notify_task_change()
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
    for v_user in
      select a.user_id from public.task_assignees a
      where a.task_id = new.id and a.user_id is distinct from v_actor and a.completed_at is null
    loop
      perform private.enqueue_notification('changed', new.id, v_user, v_actor,
        'changed:' || new.id || ':' || v_user || ':' || new.version);
    end loop;
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

create trigger tasks_notify_change
  after update on public.tasks
  for each row execute function private.notify_task_change();

-- ---------------------------------------------------------------------------
-- Zeitgesteuert: jede Minute prüfen, was jetzt fällig ist
-- ---------------------------------------------------------------------------

-- Bezugszeitpunkt einer offenen Zuweisung: Start (mit Uhrzeit), 08:00 am Tag (nur Datum, E3),
-- bzw. Zuweisung (ohne Datum). Nie vor der Zuweisung selbst.
create function private.notification_anchor(p_task public.tasks, p_assigned_at timestamptz)
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select case
    when p_task.start_time is not null then p_task.starts_at
    when p_task.start_date is not null then
      greatest((p_task.start_date + time '08:00') at time zone p_task.timezone, p_assigned_at)
    else p_assigned_at
  end;
$$;

revoke execute on function private.notification_anchor(public.tasks, timestamptz) from public, anon, authenticated;

create function private.enqueue_due_notifications()
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

-- Jede Minute: fällige Aufträge anlegen, dann push-dispatch anstoßen (nur wenn etwas wartet).
create function private.start_push_dispatch()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_url   text;
begin
  perform private.enqueue_due_notifications();
  if not exists (
    select 1 from public.notification_jobs j where j.status = 'pending' and j.scheduled_for <= now()
  ) then
    return null;
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into private.cron_tokens (token_hash, purpose)
  values (encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), 'push_dispatch');
  select s.value into v_url from private.app_settings s where s.key = 'functions_base_url';

  return net.http_post(
    url := v_url || '/push-dispatch',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-familiar-cron-token', v_token),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
end;
$$;

revoke execute on function private.start_push_dispatch() from public, anon, authenticated;

select cron.schedule('familiar-push-dispatch', '* * * * *', $$select private.start_push_dispatch()$$);

-- ---------------------------------------------------------------------------
-- RPCs für die App (authenticated)
-- ---------------------------------------------------------------------------

-- Gerät registrieren bzw. aktualisieren. Wandert ein Token zu einem anderen Konto (Abmelden/
-- Anmelden auf demselben Gerät), gehört es danach dem neuen Konto.
create function public.register_device(
  p_apns_token text,
  p_environment public.apns_environment,
  p_push_to_start_token text default null,
  p_app_version text default null,
  p_timezone text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
  v_id  uuid;
begin
  if p_apns_token is null or p_apns_token !~ '^[0-9a-f]{32,200}$' then
    perform private.raise_app_error('invalid_device_token');
  end if;
  insert into public.devices (user_id, apns_token, apns_environment, push_to_start_token, app_version, timezone)
  values (v_uid, p_apns_token, p_environment, p_push_to_start_token, p_app_version, p_timezone)
  on conflict (apns_token) do update
    set user_id = v_uid,
        apns_environment = excluded.apns_environment,
        push_to_start_token = coalesce(excluded.push_to_start_token, public.devices.push_to_start_token),
        app_version = excluded.app_version,
        timezone = excluded.timezone,
        last_seen_at = now(),
        invalidated_at = null
  returning id into v_id;
  return v_id;
end;
$$;

-- Abmelden: Gerät bekommt keine Mitteilungen mehr (vor signOut aufrufen).
create function public.unregister_device(p_apns_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  update public.devices d set invalidated_at = now()
   where d.apns_token = p_apns_token and d.user_id = v_uid;
  update public.live_activities a set state = 'ended', ended_at = now()
   where a.user_id = v_uid and a.state = 'active'
     and a.device_id in (select d.id from public.devices d where d.apns_token = p_apns_token);
end;
$$;

-- Live Activity melden (Start in der App oder per Push-to-Start), mit Update-Token.
create function public.register_live_activity(
  p_task_id uuid,
  p_apns_token text,
  p_activity_id text,
  p_update_token text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := private.require_uid();
  v_device uuid;
begin
  select d.id into v_device from public.devices d
  where d.apns_token = p_apns_token and d.user_id = v_uid and d.invalidated_at is null;
  if v_device is null or not private.can_view_task(p_task_id) then
    perform private.raise_app_error('task_not_found');
  end if;
  insert into public.live_activities (task_id, user_id, device_id, activity_id, update_token)
  values (p_task_id, v_uid, v_device, p_activity_id, p_update_token)
  on conflict (device_id, activity_id) do update
    set update_token = excluded.update_token, state = 'active', ended_at = null;
end;
$$;

-- Live Activity beendet (z. B. vom Nutzer weggewischt oder nach Ablauf).
create function public.end_live_activity(p_apns_token text, p_activity_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := private.require_uid();
begin
  update public.live_activities a set state = 'ended', ended_at = now()
   where a.activity_id = p_activity_id and a.user_id = v_uid
     and a.device_id in (select d.id from public.devices d where d.apns_token = p_apns_token);
end;
$$;

revoke execute on function public.register_device(text, public.apns_environment, text, text, text) from public, anon, service_role;
revoke execute on function public.unregister_device(text) from public, anon, service_role;
revoke execute on function public.register_live_activity(uuid, text, text, text) from public, anon, service_role;
revoke execute on function public.end_live_activity(text, text) from public, anon, service_role;
grant execute on function public.register_device(text, public.apns_environment, text, text, text) to authenticated;
grant execute on function public.unregister_device(text) to authenticated;
grant execute on function public.register_live_activity(uuid, text, text, text) to authenticated;
grant execute on function public.end_live_activity(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- RPCs für push-dispatch (nur service_role)
-- ---------------------------------------------------------------------------

-- Token einlösen und bis zu 200 fällige Aufträge übernehmen (FOR UPDATE SKIP LOCKED).
-- Liefert je Auftrag Inhalt, Empfänger-Geräte und – für Live Activities – den ContentState.
create function public.push_claim_jobs(p_token text)
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
      'starts_at_unix', extract(epoch from t.starts_at),
      'completion_mode', t.completion_mode,
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

-- Ergebnisse zurückmelden.
-- p_results: [{"id": bigint, "status": "sent"|"failed"|"skipped", "error": text,
--              "invalid_device_ids": [uuid], "ended_activity_ids": [uuid]}, …]
create function public.push_report_results(p_results jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
begin
  for v_item in select value from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) loop
    update public.notification_jobs j
       set status = case
                      when v_item ->> 'status' = 'failed' and j.attempts < 3 then 'pending'::public.notification_status
                      else (v_item ->> 'status')::public.notification_status
                    end,
           scheduled_for = case when v_item ->> 'status' = 'failed' then now() + interval '2 minutes' else j.scheduled_for end,
           last_error = v_item ->> 'error',
           sent_at = case when v_item ->> 'status' = 'sent' then now() else j.sent_at end
     where j.id = (v_item ->> 'id')::bigint;

    update public.devices d set invalidated_at = now()
     where d.id in (select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(v_item -> 'invalid_device_ids', '[]'::jsonb)) as x);

    update public.live_activities a set state = 'ended', ended_at = now()
     where a.id in (select (x #>> '{}')::uuid from jsonb_array_elements(coalesce(v_item -> 'ended_activity_ids', '[]'::jsonb)) as x);
  end loop;
end;
$$;

revoke execute on function public.push_claim_jobs(text) from public, anon, authenticated;
revoke execute on function public.push_report_results(jsonb) from public, anon, authenticated;
grant execute on function public.push_claim_jobs(text) to service_role;
grant execute on function public.push_report_results(jsonb) to service_role;

-- ---------------------------------------------------------------------------
-- Fehlerkatalog: invalid_device_token ergänzen
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
    ('invalid_device_token',            '22023', 'Ungültiges Geräte-Token.')
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
