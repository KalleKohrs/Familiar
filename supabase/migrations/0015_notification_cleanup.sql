-- 0015_notification_cleanup
-- Datensparsamkeit: Mitteilungs-Aufträge, beendete Live Activities und abgemeldete Geräte werden
-- nach 30 Tagen gelöscht; verbrauchte Cron-Einmal-Tokens nach einem Tag. Täglich 03:45 UTC.
-- Enthält DELETE → im Supabase-SQL-Editor ausführen (MCP-Bestätigung kommt in der App nicht an).

create function private.purge_notifications()
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
end;
$$;

revoke execute on function private.purge_notifications() from public, anon, authenticated;

select cron.schedule('familiar-purge-notifications', '45 3 * * *', $$select private.purge_notifications()$$);

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261021190000', '0015_notification_cleanup', array['-- siehe supabase/migrations/0015_notification_cleanup.sql']);
