create extension if not exists vector;

create table jars (
  id               uuid primary key,
  user_id          uuid not null references auth.users(id) on delete cascade,
  name             text not null,
  hue              smallint not null check (hue between 1 and 6),
  created_at       timestamptz not null default now(),
  sealed_at        timestamptz,
  shelf_life_hours integer,
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  field_ts         jsonb not null default '{}'::jsonb
);

create table items (
  id          uuid primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  jar_id      uuid references jars(id) on delete set null,
  kind        text not null check (kind in ('page','note','task','file','message')),
  url         text,
  title       text not null,
  body        text,
  meta        jsonb,
  created_at  timestamptz not null default now(),
  touched_at  timestamptz not null default now(),
  sealed_at   timestamptz,
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  field_ts    jsonb not null default '{}'::jsonb,
  fts         tsvector generated always as (
                to_tsvector('english', coalesce(title,'') || ' ' || coalesce(body,''))
              ) stored
);

create index idx_jars_user       on jars  (user_id, created_at desc);
create index idx_jars_sync       on jars  (user_id, updated_at);
create index idx_items_user_jar  on items (user_id, jar_id, touched_at desc);
create index idx_items_user_kind on items (user_id, kind, touched_at desc);
create index idx_items_sync      on items (user_id, updated_at);
create index idx_items_fts       on items using gin (fts);

create unique index idx_items_user_url on items (user_id, url)
  where url is not null and deleted_at is null;
