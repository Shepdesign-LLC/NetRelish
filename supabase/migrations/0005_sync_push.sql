create or replace function sync_push(payload jsonb, client_synced_at timestamptz)
returns jsonb
language plpgsql
security invoker
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
                         created_at, touched_at, field_ts, updated_at)
      values ((row_in->>'id')::uuid, auth.uid(),
              nullif(row_in->>'jar_id','')::uuid, row_in->>'kind',
              row_in->>'url', row_in->>'title', row_in->>'body',
              coalesce(row_in->'meta','{}'::jsonb),
              coalesce((row_in->>'created_at')::timestamptz, now()),
              coalesce((row_in->>'touched_at')::timestamptz, now()),
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
       and stored_ts > client_synced_at then
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
          when 'deleted_at' then merged.deleted_at := (row_in->>'deleted_at')::timestamptz;
          else null;
        end case;
      end if;
    end loop;

    update items set title=merged.title, body=merged.body, url=merged.url,
                     jar_id=merged.jar_id, meta=merged.meta,
                     deleted_at=merged.deleted_at,
                     field_ts=new_ts, updated_at=now()
    where id = existing.id
    returning * into merged;
    results := results || to_jsonb(merged);
  end loop;

  return results;
end $$;
