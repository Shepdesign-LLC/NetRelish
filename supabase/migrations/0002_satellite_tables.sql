create table tabs (
  id          uuid primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  jar_id      uuid references jars(id) on delete cascade,
  item_id     uuid references items(id) on delete set null,
  url         text,
  scroll_y    integer not null default 0,
  position    integer not null default 0,
  opened_at   timestamptz not null default now(),
  touched_at  timestamptz not null default now(),
  seal_after  timestamptz,
  sealed_at   timestamptz,
  sealed_batch uuid,
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  field_ts    jsonb not null default '{}'::jsonb
);

create table labels (
  id         uuid primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  field_ts   jsonb not null default '{}'::jsonb,
  unique (user_id, name)
);

create table item_labels (
  item_id    uuid not null references items(id)  on delete cascade,
  label_id   uuid not null references labels(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (item_id, label_id)
);

create table recipes (
  id         uuid primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  jar_id     uuid not null references jars(id) on delete cascade,
  name       text not null,
  steps      jsonb not null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  field_ts   jsonb not null default '{}'::jsonb
);

create table suggestion_feedback (
  item_id    uuid not null references items(id) on delete cascade,
  jar_id     uuid not null references jars(id)  on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  action     text not null check (action in ('accepted','rejected')),
  at         timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (item_id, jar_id)
);

create table embeddings (
  item_id    uuid primary key references items(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  vector     vector(1024) not null,
  model      text not null,
  created_at timestamptz not null default now()
);

create index idx_tabs_sync        on tabs        (user_id, updated_at);
create index idx_labels_sync      on labels      (user_id, updated_at);
create index idx_item_labels_sync on item_labels (user_id, updated_at);
create index idx_recipes_sync     on recipes     (user_id, updated_at);
create index embeddings_vec_idx   on embeddings using hnsw (vector vector_cosine_ops);
