-- Stage B, part 1 — field-level merge for the four remaining tables that
-- carry `field_ts`: jars, tabs, labels, recipes.
--
-- Same policy as 0005/0006's sync_push for items, and deliberately the same
-- shape so the four read as one rule written four times rather than four
-- rules:
--
--   * Field-level last-write-wins. Each row carries `field_ts`, a map of
--     column name -> ISO timestamp of that column's last write. Incoming
--     beats stored only when STRICTLY newer, so a tie keeps stored and a
--     replayed push is harmless.
--   * `updated_at` is set here with now(), never taken from the client. A
--     wrong client clock must not be able to win forever, and must not be
--     able to hide a row from another client's `updated_at >` pull.
--   * `security invoker` + `set search_path`. INVOKER is load-bearing: these
--     functions run inside the caller's RLS, so a client pushing at another
--     account's id reaches nothing. DEFINER here would hand every account
--     the whole database. `extensions` is on the path because pgvector moved
--     there in 0004; the explicit path also clears linter 0011.
--
-- Two things these functions deliberately do NOT do:
--
--   1. **No conflict copies.** Forking a row is only worth it for prose, and
--      prose only lives in items.body. A jar that forks into two jars because
--      two machines renamed it is worse than one machine's rename losing.
--      Conflict copies stay in sync_push(), for items, only.
--   2. **No generic merge.** One row-shape-agnostic plpgsql function for all
--      six tables is possible and would be clever. It would also be the least
--      readable code in the repo, and this is the code that silently corrupts
--      data when it is wrong. Six explicit functions, six explicit CASEs.
--
-- `client_synced_at` is unused in all four. It exists only so every
-- sync_push_* on a field_ts table has one signature the client can call
-- without special-casing; it only ever mattered for items' conflict copies
-- (see 0006). Do not remove it to "tidy up" — that breaks the caller.

------------------------------------------------------------------------------
-- jars — name, hue, sealed_at, shelf_life_hours, deleted_at
------------------------------------------------------------------------------
create or replace function sync_push_jars(payload jsonb, client_synced_at timestamptz)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  row_in      jsonb;
  existing    jars%rowtype;
  merged      jars%rowtype;
  new_ts      jsonb;
  fld         text;
  incoming_ts timestamptz;
  stored_ts   timestamptz;
  results     jsonb := '[]'::jsonb;
begin
  for row_in in select * from jsonb_array_elements(payload)
  loop
    select * into existing from jars where id = (row_in->>'id')::uuid;

    if not found then
      insert into jars (id, user_id, name, hue, created_at, sealed_at,
                        shelf_life_hours, deleted_at, field_ts, updated_at)
      values ((row_in->>'id')::uuid, auth.uid(),
              row_in->>'name', (row_in->>'hue')::smallint,
              coalesce((row_in->>'created_at')::timestamptz, now()),
              (row_in->>'sealed_at')::timestamptz,
              (row_in->>'shelf_life_hours')::integer,
              (row_in->>'deleted_at')::timestamptz,
              coalesce(row_in->'field_ts','{}'::jsonb), now())
      returning * into merged;
      results := results || to_jsonb(merged);
      continue;
    end if;

    merged := existing;
    new_ts := existing.field_ts;
    for fld in select jsonb_object_keys(coalesce(row_in->'field_ts','{}'::jsonb))
    loop
      incoming_ts := (row_in->'field_ts'->>fld)::timestamptz;
      stored_ts   := (existing.field_ts->>fld)::timestamptz;
      if stored_ts is null or incoming_ts > stored_ts then
        new_ts := new_ts || jsonb_build_object(fld, incoming_ts);
        case fld
          when 'name'      then merged.name      := row_in->>'name';
          when 'hue'       then merged.hue       := (row_in->>'hue')::smallint;
          when 'sealed_at' then merged.sealed_at := (row_in->>'sealed_at')::timestamptz;
          when 'shelf_life_hours'
                           then merged.shelf_life_hours := (row_in->>'shelf_life_hours')::integer;
          when 'deleted_at' then merged.deleted_at := (row_in->>'deleted_at')::timestamptz;
          else null;
        end case;
      end if;
    end loop;

    update jars set name=merged.name, hue=merged.hue,
                    sealed_at=merged.sealed_at,
                    shelf_life_hours=merged.shelf_life_hours,
                    deleted_at=merged.deleted_at,
                    field_ts=new_ts, updated_at=now()
    where id = existing.id
    returning * into merged;
    results := results || to_jsonb(merged);
  end loop;

  return results;
end $$;

------------------------------------------------------------------------------
-- tabs — jar_id, item_id, url, scroll_y, position, opened_at, touched_at,
--        seal_after, sealed_at, sealed_batch, deleted_at
--
-- `position` is quoted throughout: it is a col_name keyword in Postgres and
-- an unquoted bare reference is a parse hazard, not a style preference.
------------------------------------------------------------------------------
create or replace function sync_push_tabs(payload jsonb, client_synced_at timestamptz)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  row_in      jsonb;
  existing    tabs%rowtype;
  merged      tabs%rowtype;
  new_ts      jsonb;
  fld         text;
  incoming_ts timestamptz;
  stored_ts   timestamptz;
  results     jsonb := '[]'::jsonb;
begin
  for row_in in select * from jsonb_array_elements(payload)
  loop
    select * into existing from tabs where id = (row_in->>'id')::uuid;

    if not found then
      insert into tabs (id, user_id, jar_id, item_id, url, scroll_y, "position",
                        opened_at, touched_at, seal_after, sealed_at,
                        sealed_batch, deleted_at, field_ts, updated_at)
      values ((row_in->>'id')::uuid, auth.uid(),
              nullif(row_in->>'jar_id','')::uuid,
              nullif(row_in->>'item_id','')::uuid,
              row_in->>'url',
              coalesce((row_in->>'scroll_y')::integer, 0),
              coalesce((row_in->>'position')::integer, 0),
              coalesce((row_in->>'opened_at')::timestamptz, now()),
              coalesce((row_in->>'touched_at')::timestamptz, now()),
              (row_in->>'seal_after')::timestamptz,
              (row_in->>'sealed_at')::timestamptz,
              nullif(row_in->>'sealed_batch','')::uuid,
              (row_in->>'deleted_at')::timestamptz,
              coalesce(row_in->'field_ts','{}'::jsonb), now())
      returning * into merged;
      results := results || to_jsonb(merged);
      continue;
    end if;

    merged := existing;
    new_ts := existing.field_ts;
    for fld in select jsonb_object_keys(coalesce(row_in->'field_ts','{}'::jsonb))
    loop
      incoming_ts := (row_in->'field_ts'->>fld)::timestamptz;
      stored_ts   := (existing.field_ts->>fld)::timestamptz;
      if stored_ts is null or incoming_ts > stored_ts then
        new_ts := new_ts || jsonb_build_object(fld, incoming_ts);
        case fld
          when 'jar_id'   then merged.jar_id   := nullif(row_in->>'jar_id','')::uuid;
          when 'item_id'  then merged.item_id  := nullif(row_in->>'item_id','')::uuid;
          when 'url'      then merged.url      := row_in->>'url';
          when 'scroll_y' then merged.scroll_y := coalesce((row_in->>'scroll_y')::integer, 0);
          when 'position' then merged."position" := coalesce((row_in->>'position')::integer, 0);
          when 'opened_at'    then merged.opened_at    := (row_in->>'opened_at')::timestamptz;
          when 'touched_at'   then merged.touched_at   := (row_in->>'touched_at')::timestamptz;
          when 'seal_after'   then merged.seal_after   := (row_in->>'seal_after')::timestamptz;
          when 'sealed_at'    then merged.sealed_at    := (row_in->>'sealed_at')::timestamptz;
          when 'sealed_batch' then merged.sealed_batch := nullif(row_in->>'sealed_batch','')::uuid;
          when 'deleted_at'   then merged.deleted_at   := (row_in->>'deleted_at')::timestamptz;
          else null;
        end case;
      end if;
    end loop;

    update tabs set jar_id=merged.jar_id, item_id=merged.item_id, url=merged.url,
                    scroll_y=merged.scroll_y, "position"=merged."position",
                    opened_at=merged.opened_at, touched_at=merged.touched_at,
                    seal_after=merged.seal_after, sealed_at=merged.sealed_at,
                    sealed_batch=merged.sealed_batch, deleted_at=merged.deleted_at,
                    field_ts=new_ts, updated_at=now()
    where id = existing.id
    returning * into merged;
    results := results || to_jsonb(merged);
  end loop;

  return results;
end $$;

------------------------------------------------------------------------------
-- labels — name, deleted_at
--
-- `labels` carries unique (user_id, name). Two machines renaming two labels
-- into each other's names is a legitimate 23505 out of here, not a bug to
-- swallow: the alternative is inventing a name the user never typed.
------------------------------------------------------------------------------
create or replace function sync_push_labels(payload jsonb, client_synced_at timestamptz)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  row_in      jsonb;
  existing    labels%rowtype;
  merged      labels%rowtype;
  new_ts      jsonb;
  fld         text;
  incoming_ts timestamptz;
  stored_ts   timestamptz;
  results     jsonb := '[]'::jsonb;
begin
  for row_in in select * from jsonb_array_elements(payload)
  loop
    select * into existing from labels where id = (row_in->>'id')::uuid;

    if not found then
      insert into labels (id, user_id, name, deleted_at, field_ts, updated_at)
      values ((row_in->>'id')::uuid, auth.uid(), row_in->>'name',
              (row_in->>'deleted_at')::timestamptz,
              coalesce(row_in->'field_ts','{}'::jsonb), now())
      returning * into merged;
      results := results || to_jsonb(merged);
      continue;
    end if;

    merged := existing;
    new_ts := existing.field_ts;
    for fld in select jsonb_object_keys(coalesce(row_in->'field_ts','{}'::jsonb))
    loop
      incoming_ts := (row_in->'field_ts'->>fld)::timestamptz;
      stored_ts   := (existing.field_ts->>fld)::timestamptz;
      if stored_ts is null or incoming_ts > stored_ts then
        new_ts := new_ts || jsonb_build_object(fld, incoming_ts);
        case fld
          when 'name'       then merged.name       := row_in->>'name';
          when 'deleted_at' then merged.deleted_at := (row_in->>'deleted_at')::timestamptz;
          else null;
        end case;
      end if;
    end loop;

    update labels set name=merged.name, deleted_at=merged.deleted_at,
                      field_ts=new_ts, updated_at=now()
    where id = existing.id
    returning * into merged;
    results := results || to_jsonb(merged);
  end loop;

  return results;
end $$;

------------------------------------------------------------------------------
-- recipes — jar_id, name, steps, deleted_at
--
-- `steps` is merged as a whole jsonb value under one stamp. A recipe's steps
-- are an ordered list; merging two edits element-wise would produce a recipe
-- neither machine recorded, which is worse than one of them losing.
------------------------------------------------------------------------------
create or replace function sync_push_recipes(payload jsonb, client_synced_at timestamptz)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  row_in      jsonb;
  existing    recipes%rowtype;
  merged      recipes%rowtype;
  new_ts      jsonb;
  fld         text;
  incoming_ts timestamptz;
  stored_ts   timestamptz;
  results     jsonb := '[]'::jsonb;
begin
  for row_in in select * from jsonb_array_elements(payload)
  loop
    select * into existing from recipes where id = (row_in->>'id')::uuid;

    if not found then
      insert into recipes (id, user_id, jar_id, name, steps, deleted_at,
                           field_ts, updated_at)
      values ((row_in->>'id')::uuid, auth.uid(),
              nullif(row_in->>'jar_id','')::uuid,
              row_in->>'name',
              coalesce(row_in->'steps','[]'::jsonb),
              (row_in->>'deleted_at')::timestamptz,
              coalesce(row_in->'field_ts','{}'::jsonb), now())
      returning * into merged;
      results := results || to_jsonb(merged);
      continue;
    end if;

    merged := existing;
    new_ts := existing.field_ts;
    for fld in select jsonb_object_keys(coalesce(row_in->'field_ts','{}'::jsonb))
    loop
      incoming_ts := (row_in->'field_ts'->>fld)::timestamptz;
      stored_ts   := (existing.field_ts->>fld)::timestamptz;
      if stored_ts is null or incoming_ts > stored_ts then
        new_ts := new_ts || jsonb_build_object(fld, incoming_ts);
        case fld
          when 'jar_id'     then merged.jar_id     := nullif(row_in->>'jar_id','')::uuid;
          when 'name'       then merged.name       := row_in->>'name';
          when 'steps'      then merged.steps      := coalesce(row_in->'steps','[]'::jsonb);
          when 'deleted_at' then merged.deleted_at := (row_in->>'deleted_at')::timestamptz;
          else null;
        end case;
      end if;
    end loop;

    update recipes set jar_id=merged.jar_id, name=merged.name, steps=merged.steps,
                       deleted_at=merged.deleted_at,
                       field_ts=new_ts, updated_at=now()
    where id = existing.id
    returning * into merged;
    results := results || to_jsonb(merged);
  end loop;

  return results;
end $$;
