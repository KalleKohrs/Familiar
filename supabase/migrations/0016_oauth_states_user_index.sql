-- 0016_oauth_states_user_index
-- Supabase-Advisor „unindexed foreign keys“: Fremdschlüssel private.oauth_states.user_id ohne Index
-- (Löschen eines Kontos durchsucht die Tabelle sonst vollständig).
create index if not exists oauth_states_user_id_idx on private.oauth_states (user_id);
