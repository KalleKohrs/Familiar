-- 0003_rls_helpers_policies
-- RLS-Hilfsfunktionen (Schema private), RLS auf allen Tabellen, Lese-Policies,
-- Entzug direkter Schreibrechte.
--
-- Muster laut Supabase-Doku „RLS performance recommendations“:
--   * security definer + set search_path = '' im nicht exponierten Schema
--   * (select auth.uid()) statt auth.uid()
--   * Policies mit „to authenticated“
--   * Mengen-Funktionen + „= any (array(select …))“ statt Join pro Zeile

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------------

-- Ist der aktuelle Nutzer Mitglied der Familie?
create function private.is_family_member(p_family_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.family_members m
    where m.family_id = p_family_id
      and m.user_id = (select auth.uid())
  );
$$;

-- Rolle des aktuellen Nutzers in der Familie (null = kein Mitglied).
create function private.family_role(p_family_id uuid)
returns public.family_role
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.family_members m
  where m.family_id = p_family_id
    and m.user_id = (select auth.uid());
$$;

-- Hat der aktuelle Nutzer das Recht in der Familie?
-- Rechte: 'invite' | 'manage_family' | 'remove_members'.
-- Admins haben immer alle Rechte; Mitglieder nur, wenn der Schalter an ist.
-- Unbekannte Rechte führen zu einem Fehler (Tippfehler sollen auffallen).
create function private.has_family_permission(p_family_id uuid, p_permission text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role   public.family_role;
  v_family public.families%rowtype;
begin
  if p_permission not in ('invite', 'manage_family', 'remove_members') then
    raise exception 'Unbekanntes Familienrecht: %', p_permission
      using errcode = '22023';
  end if;

  select m.role into v_role
  from public.family_members m
  where m.family_id = p_family_id
    and m.user_id = (select auth.uid());

  if v_role is null then
    return false;
  end if;
  if v_role = 'admin' then
    return true;
  end if;

  select * into v_family from public.families f where f.id = p_family_id;

  return case p_permission
    when 'invite'         then v_family.members_can_invite
    when 'manage_family'  then v_family.members_can_manage_family
    when 'remove_members' then v_family.members_can_remove_members
  end;
end;
$$;

-- Alle Familien des aktuellen Nutzers (für Policies: einmal pro Statement).
create function private.my_family_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.family_id
  from public.family_members m
  where m.user_id = (select auth.uid());
$$;

-- Alle Familien, in denen der aktuelle Nutzer das Recht hat.
create function private.my_family_ids_with_permission(p_permission text)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.family_id
  from public.family_members m
  where m.user_id = (select auth.uid())
    and private.has_family_permission(m.family_id, p_permission);
$$;

-- Alle Nutzer, mit denen der aktuelle Nutzer mindestens eine Familie teilt
-- (inklusive sich selbst, sofern er in einer Familie ist).
create function private.co_member_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select distinct other.user_id
  from public.family_members mine
  join public.family_members other on other.family_id = mine.family_id
  where mine.user_id = (select auth.uid());
$$;

-- Policies werden mit den Rechten des anfragenden Nutzers ausgewertet:
-- authenticated braucht EXECUTE auf die Helfer, aber kein USAGE auf „private“
-- (Policies sind bereits aufgelöst; das Schema bleibt über die API unsichtbar).
revoke execute on function private.is_family_member(uuid) from public, anon;
revoke execute on function private.family_role(uuid) from public, anon;
revoke execute on function private.has_family_permission(uuid, text) from public, anon;
revoke execute on function private.my_family_ids() from public, anon;
revoke execute on function private.my_family_ids_with_permission(text) from public, anon;
revoke execute on function private.co_member_ids() from public, anon;

grant execute on function private.is_family_member(uuid) to authenticated;
grant execute on function private.family_role(uuid) to authenticated;
grant execute on function private.has_family_permission(uuid, text) to authenticated;
grant execute on function private.my_family_ids() to authenticated;
grant execute on function private.my_family_ids_with_permission(text) to authenticated;
grant execute on function private.co_member_ids() to authenticated;

-- ---------------------------------------------------------------------------
-- RLS aktivieren
-- ---------------------------------------------------------------------------

alter table public.profiles       enable row level security;
alter table public.families       enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invites enable row level security;
-- Auch die interne Tabelle: ohne Policy kommt dort niemand außer dem Eigentümer hin.
alter table private.invite_attempts enable row level security;

-- ---------------------------------------------------------------------------
-- Tabellenrechte: anon nichts, authenticated nur lesen.
-- (Supabase vergibt per Default-Privileges sonst alles an anon/authenticated.)
-- service_role behält seine Rechte für spätere Edge Functions.
-- ---------------------------------------------------------------------------

revoke all on table public.profiles       from anon, authenticated;
revoke all on table public.families       from anon, authenticated;
revoke all on table public.family_members from anon, authenticated;
revoke all on table public.family_invites from anon, authenticated;
revoke all on table private.invite_attempts from public, anon, authenticated;

grant select on table public.profiles       to authenticated;
grant select on table public.families       to authenticated;
grant select on table public.family_members to authenticated;
grant select on table public.family_invites to authenticated;

-- ---------------------------------------------------------------------------
-- Lese-Policies
-- ---------------------------------------------------------------------------

create policy "profiles_select_self_or_co_member"
  on public.profiles
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or id = any (array (select private.co_member_ids()))
  );

create policy "families_select_member"
  on public.families
  for select
  to authenticated
  using (id = any (array (select private.my_family_ids())));

create policy "family_members_select_member"
  on public.family_members
  for select
  to authenticated
  using (family_id = any (array (select private.my_family_ids())));

create policy "family_invites_select_inviter"
  on public.family_invites
  for select
  to authenticated
  using (family_id = any (array (select private.my_family_ids_with_permission('invite'))));

-- Keine insert/update/delete-Policies: Schreiben ausschließlich über die
-- security-definer-RPCs aus 0004.
