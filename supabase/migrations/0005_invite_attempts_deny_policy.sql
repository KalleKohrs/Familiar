-- 0005_invite_attempts_deny_policy
-- private.invite_attempts ist absichtlich für alle Client-Rollen gesperrt
-- (nur public.join_family schreibt/liest als security definer).
-- Supabase-Advisor 0008 empfiehlt, diese Absicht mit einer Ablehnungs-Policy
-- ausdrücklich zu machen statt RLS ohne Policy stehen zu lassen.

create policy invite_attempts_deny_all on private.invite_attempts
  for all
  using (false)
  with check (false);

comment on policy invite_attempts_deny_all on private.invite_attempts is
  'Kein Zugriff für Client-Rollen; nur public.join_family (security definer) nutzt die Tabelle.';
