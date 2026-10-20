-- 0002_profiles_families
-- Profile, Familien, Mitgliedschaften, Einladungen, Rate-Limit-Tabelle.
-- RLS, Policies und Rechte folgen in 0003; Schreiben nur über RPCs (0004).

-- ---------------------------------------------------------------------------
-- Gemeinsame Trigger-Funktion: updated_at pflegen
-- ---------------------------------------------------------------------------

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function private.set_updated_at() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null
               check (char_length(btrim(display_name)) between 1 and 80),
  -- Pfad im (späteren) Storage-Bucket „avatars“: {user_id}/{datei}
  avatar_path  text
               check (avatar_path is null or char_length(avatar_path) between 3 and 255),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.profiles is
  'Öffentliches Profil je Auth-Nutzer. Wird per Trigger auf auth.users angelegt; Änderungen nur über update_profile().';

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

-- Profil bei Registrierung anlegen.
-- Name: user_metadata.full_name → user_metadata.name → E-Mail-Lokalteil → „Mitglied“.
-- Läuft in derselben Transaktion wie die Registrierung: darf nie fehlschlagen.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
begin
  v_name := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(btrim(split_part(coalesce(new.email, ''), '@', 1)), ''),
    'Mitglied'
  );
  v_name := btrim(left(v_name, 80));
  if v_name = '' then
    v_name := 'Mitglied';
  end if;

  insert into public.profiles (id, display_name)
  values (new.id, v_name)
  on conflict (id) do nothing;

  return new;
end;
$$;

revoke execute on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ---------------------------------------------------------------------------
-- families
-- ---------------------------------------------------------------------------

create table public.families (
  id                         uuid primary key default gen_random_uuid(),
  name                       text not null
                             check (char_length(btrim(name)) between 1 and 60),
  color_hex                  text not null
                             check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  task_visibility            public.task_visibility not null default 'all',
  members_can_invite         boolean not null default true,
  members_can_manage_family  boolean not null default true,
  members_can_remove_members boolean not null default true,
  created_by                 uuid references public.profiles (id) on delete set null,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now()
);

comment on table public.families is
  'Familie mit Farbe, Aufgaben-Sichtbarkeit und drei Rechte-Schaltern für Mitglieder (Admins haben immer alle Rechte).';

create index families_created_by_idx on public.families (created_by);

create trigger families_set_updated_at
  before update on public.families
  for each row execute function private.set_updated_at();

-- ---------------------------------------------------------------------------
-- family_members
-- ---------------------------------------------------------------------------

create table public.family_members (
  family_id uuid not null references public.families (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  role      public.family_role not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (family_id, user_id)
);

comment on table public.family_members is
  'Mitgliedschaft Nutzer↔Familie mit Rolle. Schutz für den letzten Admin in den RPCs.';

-- RLS-Helfer suchen „meine Familien“ über user_id.
create index family_members_user_id_idx on public.family_members (user_id);

-- ---------------------------------------------------------------------------
-- family_invites
-- ---------------------------------------------------------------------------

create table public.family_invites (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid not null references public.families (id) on delete cascade,
  -- 8 Zeichen Crockford-Base32 (ohne I, L, O, U) = 40 Bit aus gen_random_bytes(5)
  code       text not null unique
             check (code ~ '^[0-9A-HJKMNP-TV-Z]{8}$'),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  revoked_at timestamptz,
  use_count  integer not null default 0 check (use_count >= 0),
  check (expires_at > created_at)
);

comment on table public.family_invites is
  'Einladungscodes. Beitritt nur über join_family(code); Codes erzeugt create_invite().';

create index family_invites_family_id_idx on public.family_invites (family_id);
create index family_invites_created_by_idx on public.family_invites (created_by);

-- Erzeugt einen zufälligen 8-stelligen Crockford-Base32-Code (40 Bit).
create function private.generate_invite_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  c_alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_bytes bytea := extensions.gen_random_bytes(5);
  v_bits  bigint := 0;
  v_code  text := '';
begin
  for i in 0..4 loop
    v_bits := (v_bits << 8) | get_byte(v_bytes, i);
  end loop;
  for i in reverse 7..0 loop
    v_code := v_code || substr(c_alphabet, ((v_bits >> (i * 5)) & 31)::int + 1, 1);
  end loop;
  return v_code;
end;
$$;

revoke execute on function private.generate_invite_code() from public, anon, authenticated;

-- Normalisiert eine Nutzereingabe nach Crockford-Regeln:
-- Großschreibung, Leerzeichen/Bindestriche entfernen, O→0, I/L→1.
create function private.normalize_invite_code(p_input text)
returns text
language sql
immutable
set search_path = ''
as $$
  select translate(
    regexp_replace(upper(coalesce(p_input, '')), '[\s-]', '', 'g'),
    'OIL',
    '011'
  );
$$;

revoke execute on function private.normalize_invite_code(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- private.invite_attempts: fehlgeschlagene Beitrittsversuche (Rate-Limit)
-- ---------------------------------------------------------------------------

create table private.invite_attempts (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references auth.users (id) on delete cascade,
  attempted_at timestamptz not null default now(),
  reason       text not null
               check (reason in ('invalid_code', 'expired', 'revoked'))
);

comment on table private.invite_attempts is
  'Fehlversuche bei join_family(); max. 10 pro Nutzer und Stunde. Nur intern (Schema private).';

create index invite_attempts_user_time_idx
  on private.invite_attempts (user_id, attempted_at desc);
