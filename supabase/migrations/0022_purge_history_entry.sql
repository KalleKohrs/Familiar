-- 0022_purge_history_entry
-- Einen einzelnen Verlaufseintrag endgültig löschen (Wischen nach links im Verlauf):
--  · 'task'   – eine erledigte oder gelöschte Aufgabe,
--  · 'series' – eine gelöschte Serie samt ihren mitgelöschten Terminen.
-- Recht wie beim Löschen und Wiederherstellen: „Aufgaben löschen“ der Familie (private Aufgaben: der Ersteller,
-- weil nur er sie sieht). Nicht rückgängig zu machen. Die Wiederholungs-Erzeugung legt gelöschte Termine nicht neu
-- an (`task_series.generated_until`). Bilder, die danach nirgends mehr verknüpft sind, räumt die tägliche
-- Bereinigung (purge-history) samt Dateien auf.
-- Enthält delete → im Supabase-SQL-Editor ausführen (nicht über apply_migration).

create function public.purge_history_entry(p_kind text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task     public.tasks;
  v_deletion public.series_deletions;
begin
  perform private.require_uid();

  if p_kind = 'task' then
    v_task := private.lock_visible_task(p_id);
    perform private.require_task_permission(v_task.family_id, 'delete_tasks', v_task.is_private);
    -- Nur Einträge, die wirklich im Verlauf stehen; Termine einer gelöschten Serie gehören zum Serien-Eintrag.
    if v_task.completed_at is null and v_task.deleted_at is null then
      perform private.raise_app_error('task_not_found');
    end if;
    if v_task.deleted_by_series_op is not null then
      perform private.raise_app_error('restore_series_instead');
    end if;
    delete from public.tasks t where t.id = p_id;

  elsif p_kind = 'series' then
    select * into v_deletion from public.series_deletions d where d.id = p_id for update;
    if not found or not private.can_view_series(v_deletion.series_id) then
      perform private.raise_app_error('series_deletion_not_found');
    end if;
    perform private.require_task_permission(v_deletion.family_id, 'delete_tasks',
      (select s.is_private from public.task_series s where s.id = v_deletion.series_id));

    -- Mitgelöschte Termine zuerst (sonst blieben sie nach dem Löschen der Serie ohne Serie zurück).
    delete from public.tasks t where t.deleted_by_series_op = v_deletion.id;
    delete from public.series_deletions d where d.id = v_deletion.id;
    -- Die Serie selbst nur entfernen, wenn sie gelöscht ist (eine wiederhergestellte läuft weiter).
    delete from public.task_series s where s.id = v_deletion.series_id and s.deleted_at is not null;

  else
    perform private.raise_app_error('invalid_scope');
  end if;
end;
$$;

revoke execute on function public.purge_history_entry(text, uuid) from public, anon, service_role;
grant execute on function public.purge_history_entry(text, uuid) to authenticated;

-- Eingespielt über den SQL-Editor: Eintrag in der Migrationsliste gleich mit anlegen (wie 0019).
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261112120000', '0022_purge_history_entry', array['-- siehe supabase/migrations/0022_purge_history_entry.sql']);
