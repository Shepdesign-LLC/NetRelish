-- ============================================================
-- Zest · 0001_init.sql
-- Supabase schema for zest.netrelish.com
--
-- Written for the post-2026-10-30 behaviour: Supabase no longer
-- auto-grants Data API access to new tables in public. Every table
-- below ships its grants in this file, next to its RLS.
--
-- Access model: nothing in Zest talks to Supabase from a browser.
-- Only Vercel functions, with the service key. So:
--   * service_role gets the grants it needs
--   * anon and authenticated get NOTHING (no grants at all)
--   * RLS is enabled everywhere as a second lock — if a table is
--     ever exposed by mistake, it is closed by default because no
--     permissive policy exists for those roles
--
-- Auth note: Zest does not use Supabase Auth (magic links go out
-- through Resend so the email is branded). There is no auth.uid()
-- to write policies against; ownership is enforced in the API layer
-- and the grants below are what actually keep the data private.
-- ============================================================

-- Belt and braces: stop Postgres granting defaults on anything
-- created in public from here on, even if the project setting moves.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;

create extension if not exists pgcrypto;
create extension if not exists citext;   -- users.email below is citext; not enabled by default on a fresh database

-- ------------------------------------------------------------
-- enums
-- ------------------------------------------------------------
create type zest_tool    as enum ('zest', 'mail', 'md', 'image', 'all');
create type zest_tier    as enum ('free', 'pro', 'suite');
create type zest_status  as enum ('active', 'past_due', 'canceled');
create type zest_role    as enum ('owner', 'member');

-- ------------------------------------------------------------
-- accounts
-- ------------------------------------------------------------
create table public.users (
  id                  uuid primary key default gen_random_uuid(),
  email               citext unique not null,
  name                text,
  stripe_customer_id  text unique,
  created_at          timestamptz not null default now()
);

create table public.licenses (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references public.users(id) on delete cascade,
  tool                    zest_tool not null,
  tier                    zest_tier not null default 'pro',
  status                  zest_status not null default 'active',
  seats                   int not null default 1 check (seats between 1 and 100),
  lifetime                boolean not null default false,
  stripe_subscription_id  text unique,
  current_period_end      timestamptz,
  created_at              timestamptz not null default now()
);
create index licenses_user_idx on public.licenses(user_id) where status = 'active';

create table public.devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.users(id) on delete cascade,
  fingerprint  text not null,
  name         text,
  last_seen    timestamptz not null default now(),
  unique (user_id, fingerprint)
);

create table public.team_members (
  license_id  uuid not null references public.licenses(id) on delete cascade,
  user_id     uuid not null references public.users(id) on delete cascade,
  role        zest_role not null default 'member',
  created_at  timestamptz not null default now(),
  primary key (license_id, user_id)
);

-- ------------------------------------------------------------
-- content
-- ------------------------------------------------------------
create table public.brands (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.users(id) on delete cascade,
  license_id  uuid references public.licenses(id) on delete set null,
  name        text not null,
  json        jsonb not null,                    -- zest-brand.json
  version     int not null default 1,
  updated_at  timestamptz not null default now()
);
create index brands_owner_idx on public.brands(owner_id);

create table public.designs (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.users(id) on delete cascade,
  tool        zest_tool not null,
  name        text not null,
  json        jsonb not null,
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index designs_owner_idx on public.designs(owner_id, tool) where deleted_at is null;

create table public.modules (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.users(id) on delete cascade,
  tool        zest_tool not null,
  name        text not null,
  json        jsonb not null,
  updated_at  timestamptz not null default now()
);
create index modules_owner_idx on public.modules(owner_id, tool);

create table public.documents (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.users(id) on delete cascade,
  title       text not null default 'Untitled',
  markdown    text not null default '',
  html        text,
  skin        jsonb,
  updated_at  timestamptz not null default now()
);
create index documents_owner_idx on public.documents(owner_id);

create table public.publications (
  id           uuid primary key default gen_random_uuid(),
  document_id  uuid not null references public.documents(id) on delete cascade,
  slug         text unique not null,
  s3_key       text not null,
  domain       text,
  is_public    boolean not null default true,
  views        bigint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.assets (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.users(id) on delete cascade,
  tool        zest_tool not null,
  s3_key      text not null,
  bytes       bigint not null,
  mime        text not null,
  alt         text,
  created_at  timestamptz not null default now()
);
create index assets_owner_idx on public.assets(owner_id);

create table public.usage (
  user_id        uuid not null references public.users(id) on delete cascade,
  month          date not null,                  -- first of month
  drafts_used    int  not null default 0,
  storage_bytes  bigint not null default 0,
  primary key (user_id, month)
);

-- ------------------------------------------------------------
-- updated_at
-- ------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array['brands','designs','modules','documents','publications'] loop
    execute format(
      'create trigger %I_touch before update on public.%I
         for each row execute function public.touch_updated_at()', t, t);
  end loop;
end $$;

-- ============================================================
-- RLS — on everywhere, no permissive policies.
-- service_role bypasses RLS; anon and authenticated are locked out
-- by having no grants AND no policy. Two locks, one key.
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array['users','licenses','devices','team_members','brands',
                           'designs','modules','documents','publications','assets','usage'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;

-- ============================================================
-- GRANTS — explicit, because nothing is automatic any more.
-- Only service_role. anon and authenticated are granted nothing.
-- ============================================================
-- Belt and braces again: strip anything a pre-existing default-privilege
-- grant attached to these tables. The default-privilege revocation above
-- only covers select/insert/update/delete, so a project whose old defaults
-- granted ALL would leave truncate, references and trigger on anon and
-- authenticated — and RLS does not restrict truncate.
do $$
declare t text;
begin
  foreach t in array array['users','licenses','devices','team_members','brands',
                           'designs','modules','documents','publications','assets','usage'] loop
    execute format('revoke all on public.%I from public, anon, authenticated, service_role', t);
  end loop;
end $$;
revoke all on all sequences in schema public from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['users','licenses','devices','team_members','brands',
                           'designs','modules','documents','publications','assets','usage'] loop
    execute format('grant select, insert, update, delete on public.%I to service_role', t);
  end loop;
end $$;

grant usage on schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

-- If a table ever needs to be readable by the browser directly,
-- add its grant here explicitly and write the matching policy.
-- Nothing is exposed by accident.

-- ============================================================
-- Verify: run after `supabase db reset` or on a preview branch.
-- Expect one row per table for service_role and nothing for anon
-- or authenticated. If a table is missing, the Data API cannot
-- see it — that is the failure mode this file exists to prevent.
-- ============================================================
-- select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type)
--   from information_schema.role_table_grants
--  where table_schema = 'public' and grantee in ('anon','authenticated','service_role')
--  group by 1, 2 order by 1, 2;
