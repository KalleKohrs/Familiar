-- 0001_extensions_and_schemas
-- Phase 1 „Backend-Basis“: Extensions, privates Schema, Enums.
--
-- Doku-Stand 2026-10-20:
--   pg_cron: https://supabase.com/docs/guides/cron/install
--   pg_net:  https://supabase.com/docs/guides/database/extensions/pg_net
--            (Schema „extensions“ wie im Guide „Automatic embeddings“)
--   private Schema für security-definer-Helfer:
--            https://supabase.com/docs/guides/database/postgres/row-level-security#use-security-definer-functions

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------

-- pg_cron legt sein eigenes Schema „cron“ an.
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

-- pg_net legt seine Funktionen im Schema „net“ an.
create extension if not exists pg_net with schema extensions;

-- pgcrypto (gen_random_bytes) ist in Supabase vorinstalliert; hier nur abgesichert.
create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------------
-- Schema „private“: nicht über die Data API exponiert.
-- Enthält RLS-Hilfsfunktionen, Trigger-Funktionen und interne Tabellen.
-- anon/authenticated bekommen hier grundsätzlich nichts; einzelne
-- RLS-Hilfsfunktionen erhalten in 0003 gezielt EXECUTE für authenticated.
-- ---------------------------------------------------------------------------

create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon, authenticated;

-- Hinweis: Postgres vergibt EXECUTE auf neue Funktionen global an PUBLIC.
-- Ein schema-spezifisches „alter default privileges … revoke“ hebt globale
-- Defaults nicht auf. Deshalb entzieht jede Migration EXECUTE pro Funktion
-- explizit (revoke … from public, anon, authenticated).

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.family_role as enum ('admin', 'member');
create type public.task_visibility as enum ('all', 'assigned_only');
