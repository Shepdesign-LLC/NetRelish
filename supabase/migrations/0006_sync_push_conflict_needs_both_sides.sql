-- Three fixes to sync_push.
--
-- 1. THE DEFECT. "Both sides edited prose" was only ever testing one side.
--    `stored_ts > client_synced_at` asks whether the SERVER wrote since the
--    client last synced; nothing asked whether the CLIENT did. So a client
--    that edited nothing and merely re-sent its snapshot forked the item —
--    the bodies differed (the server had changed it) and the server's
--    timestamp was recent. Full-snapshot push is the obvious client
--    implementation, so every client would have done this, steadily burying
--    a Pantry in duplicates. Reproduced against this database before fixing.
--
-- 2. `set search_path` — clears linter 0011 (function_search_path_mutable).
--    `extensions` is on the path because pgvector moved there in 0004.
--
-- 3. The INSERT branch silently dropped `sealed_at` and `deleted_at`, so a
--    tab sealed offline came back unsealed after its first sync.

create or replace function sync_push(payload jsonb, client_synced_at timestamptz)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  row_in      jsonb;
  existing    items%rowtype;
  merged      items%rowtype;
  new_ts      jsonb;
  fld         text;
  incoming_ts timestamptz;
  stored_ts   timestamptz;
  results     jsonb := '[]'::jsonb;
  conflict_id uuid;
begin
  for row_in in select * from jsonb_array_elements(payload)
  loop
    select * into existing from items where id = (row_in->>'id')::uuid;

    if not found then
      insert into items (id, user_id, jar_id, kind, url, title, body, meta,
                         created_at, touched_at, sealed_at, deleted_at,
                         field_ts, updated_at)
      values ((row_in->>'id')::uuid, auth.uid(),
              nullif(row_in->>'jar_id','')::uuid, row_in->>'kind',
              row_in->>'url', row_in->>'title', row_in->>'body',
              coalesce(row_in->'meta','{}'::jsonb),
              coalesce((row_in->>'created_at')::timestamptz, now()),
              coalesce((row_in->>'touched_at')::timestamptz, now()),
              (row_in->>'sealed_at')::timestamptz,
              (row_in->>'deleted_at')::timestamptz,
              coalesce(row_in->'field_ts','{}'::jsonb), now())
      returning * into merged;
      results := results || to_jsonb(merged);
      continue;
    end if;

    incoming_ts := (row_in->'field_ts'->>'body')::timestamptz;
    stored_ts   := (existing.field_ts->>'body')::timestamptz;

    if incoming_ts is not null
       and row_in->>'body' is distinct from existing.body
       and stored_ts is not null
       and stored_ts   > client_synced_at      -- the server wrote
       and incoming_ts > client_synced_at then -- and so did the client
      conflict_id := gen_random_uuid();
      insert into items (id, user_id, jar_id, kind, url, title, body, meta,
                         created_at, touched_at, field_ts, updated_at)
      values (conflict_id, auth.uid(), existing.jar_id, existing.kind,
              existing.url, existing.title, row_in->>'body',
              coalesce(row_in->'meta','{}'::jsonb)
                || jsonb_build_object('conflict_of', existing.id,
                                      'conflict_at', now()),
              existing.created_at, now(),
              coalesce(row_in->'field_ts','{}'::jsonb), now());
      results := results || jsonb_build_object('conflict_copy', conflict_id,
                                               'of', existing.id);
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
          when 'title'  then merged.title  := row_in->>'title';
          when 'body'   then merged.body   := row_in->>'body';
          when 'url'    then merged.url    := row_in->>'url';
          when 'jar_id' then merged.jar_id := nullif(row_in->>'jar_id','')::uuid;
          when 'meta'   then merged.meta   := row_in->'meta';
          when 'sealed_at'  then merged.sealed_at  := (row_in->>'sealed_at')::timestamptz;
          when 'deleted_at' then merged.deleted_at := (row_in->>'deleted_at')::timestamptz;
          else null;
        end case;
      end if;
    end loop;

    update items set title=merged.title, body=merged.body, url=merged.url,
                     jar_id=merged.jar_id, meta=merged.meta,
                     sealed_at=merged.sealed_at, deleted_at=merged.deleted_at,
                     field_ts=new_ts, updated_at=now()
    where id = existing.id
    returning * into merged;
    results := results || to_jsonb(merged);
  end loop;

  return results;
end $$;
