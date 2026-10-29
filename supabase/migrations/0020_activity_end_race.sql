-- 0020: Live-Activity-Ende nach Terminänderung beendet nicht mehr die danach neu gestartete Activity.
--
-- Fehlerbild: Ändert jemand die Startzeit, legt der Server einen Auftrag „activity_end“ an (läuft bis zu einer
-- Minute später). Startet die App in der Zwischenzeit schon die neue Activity, hat push_claim_jobs sie erst
-- beim Versand mitgenommen und sofort wieder beendet. Jetzt zählen bei einem Ende für eine noch offene
-- Aufgabe nur Activities, die schon vor dem Auftrag aktiv waren.
-- Nur Funktionsersatz (create or replace).

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
          -- Ende wegen einer Terminänderung (Aufgabe für die Person noch offen): nur Activities, die schon
          -- vor dem Auftrag liefen. Eine Activity, die danach für den neuen Termin entstanden ist, bleibt.
          -- Bei Erledigt/Gelöscht/Entfernt (nicht mehr offen) endet weiterhin alles.
          and (j.kind <> 'activity_end'
               or a.started_at <= j.scheduled_for
               or not (t.completed_at is null and t.deleted_at is null and exists (
                         select 1 from public.task_assignees ta
                         where ta.task_id = t.id and ta.user_id = j.user_id and ta.completed_at is null)))
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
