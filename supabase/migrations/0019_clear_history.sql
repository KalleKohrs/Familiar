-- 0019_clear_history
-- Verlauf leeren: Admins entfernen den gesamten Verlauf ihrer Familien endgültig (erledigte und
-- gelöschte Aufgaben, gelöschte Serien samt Verlaufseinträgen). Nicht rückgängig zu machen.
-- Bilder, die danach nirgends mehr verknüpft sind, räumt die tägliche Bereinigung (purge-history)
-- samt Dateien auf.
-- Enthält delete → im Supabase-SQL-Editor ausführen (nicht über apply_migration).

create function public.clear_history()
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
  with removed as (
    delete from public.task_series s
     where s.family_id = any (v_families) and s.deleted_at is not null
    returning s.id
  )
  select count(*) into v_series from removed;

  -- Erledigte und gelöschte Aufgaben.
  with removed as (
    delete from public.tasks t
     where t.family_id = any (v_families)
       and (t.completed_at is not null or t.deleted_at is not null)
    returning t.id
  )
  select count(*) into v_tasks from removed;

  -- Übrige Verlaufseinträge von Serien (z. B. wiederhergestellte).
  with removed as (
    delete from public.series_deletions d
     where d.family_id = any (v_families)
    returning d.id
  )
  select count(*) into v_log from removed;

  return v_tasks + v_series;
end;
$$;

revoke execute on function public.clear_history() from public, anon;
grant execute on function public.clear_history() to authenticated;

-- Eingespielt über den SQL-Editor: Eintrag in der Migrationsliste gleich mit anlegen (wie 0018).
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261029100000', '0019_clear_history', array['-- siehe supabase/migrations/0019_clear_history.sql']);
