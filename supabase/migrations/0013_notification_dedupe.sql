-- 0013_notification_dedupe
-- Abhaken erzeugte zwei activity_end-Aufträge (eigener Haken + Aufgabe komplett). Beide
-- Zeitstempel sind dasselbe now() der Transaktion; mit demselben Grund-Präfix fallen sie über
-- dedupe_key zu einem Auftrag zusammen.

create or replace function private.notify_assignee_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.completed_at is null and new.completed_at is not null then
    perform private.enqueue_activity_end(new.task_id, new.user_id,
      'completed:' || extract(epoch from new.completed_at)::bigint);
  end if;
  return null;
end;
$$;

revoke execute on function private.notify_assignee_completion() from public, anon, authenticated;
