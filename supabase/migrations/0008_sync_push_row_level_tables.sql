-- Stage B, part 2 — the two tables that merge whole rows instead of fields.
--
-- WHY THESE TWO ARE DIFFERENT, so nobody "fixes" the asymmetry later:
--
--   * `item_labels` is a pure join table. Presence is the only fact it
--     records, so there are no fields to merge — the newer of "labelled" and
--     "unlabelled" simply holds.
--   * `suggestion_feedback` records one verdict. `action` and `at` always
--     change together (a user does not half-change their mind), so
--     field-level merge would buy nothing and cost a column.
--
-- NEITHER TABLE HAS `field_ts` ON THE SERVER, AND NEITHER SHOULD GET ONE.
-- Local SQLite does put a `field_ts` on `suggestion_feedback` — it comes from
-- the blanket stamp helper in P4 stage A and is unused. That asymmetry is
-- deliberate and harmless; adding the column here to "match" would add a
-- merge path with nothing to merge.
--
-- The clock these two compare is `updated_at`, and the comparison is
-- deliberately client-value-against-stored-server-value:
--
--     incoming (row_in->>'updated_at')  vs  stored (server's now() at merge)
--
-- Stored `updated_at` is always the server's clock, set here, never taken
-- from the client — same rule as every other sync_push_*. That is what keeps
-- a wrong client clock from winning forever: a machine a year in the future
-- writes, pushes, and the server stamps the row with real now(), so the next
-- machine's ordinary write beats it. Strictly newer wins, so a tie keeps
-- stored and a replayed push is a no-op.
--
-- Signature is `(payload jsonb)` — no `client_synced_at`. That parameter only
-- ever existed to tell a real prose conflict from an un-pulled client (0006),
-- and neither of these tables forks. Conflict copies are for items only.
--
-- `security invoker` + `set search_path = public, extensions`, as everywhere
-- else. DEFINER would bypass every RLS policy on the way in.

------------------------------------------------------------------------------
-- item_labels — composite PK (item_id, label_id), no `id` column.
--
-- Revival is the whole point of the tombstone: re-labelling something you
-- once un-labelled must set `deleted_at` back to NULL, not be swallowed
-- because a row already exists. This is exactly the trap that bit the Mac
-- client, so the incoming `deleted_at` is applied verbatim — including NULL.
------------------------------------------------------------------------------
create or replace function sync_push_item_labels(payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  row_in      jsonb;
  existing    item_labels%rowtype;
  merged      item_labels%rowtype;
  incoming_ts timestamptz;
  results     jsonb := '[]'::jsonb;
begin
  for row_in in select * from jsonb_array_elements(payload)
  loop
    select * into existing from item_labels
     where item_id  = (row_in->>'item_id')::uuid
       and label_id = (row_in->>'label_id')::uuid;

    if not found then
      insert into item_labels (item_id, label_id, user_id, deleted_at, updated_at)
      values ((row_in->>'item_id')::uuid, (row_in->>'label_id')::uuid,
              auth.uid(), (row_in->>'deleted_at')::timestamptz, now())
      returning * into merged;
      results := results || to_jsonb(merged);
      continue;
    end if;

    incoming_ts := (row_in->>'updated_at')::timestamptz;

    if incoming_ts is null or incoming_ts <= existing.updated_at then
      -- Older or tied. Stored stands; hand it back so the client can settle.
      results := results || to_jsonb(existing);
      continue;
    end if;

    update item_labels
       set deleted_at = (row_in->>'deleted_at')::timestamptz,
           updated_at = now()
     where item_id  = existing.item_id
       and label_id = existing.label_id
    returning * into merged;
    results := results || to_jsonb(merged);
  end loop;

  return results;
end $$;

------------------------------------------------------------------------------
-- suggestion_feedback — composite PK (item_id, jar_id), no `id` column.
--
-- One verdict per (item, jar). A newer verdict replaces an older one whole:
-- `action`, `at` and `deleted_at` all come from the winning side, because
-- they are one fact recorded at one moment.
------------------------------------------------------------------------------
create or replace function sync_push_feedback(payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  row_in      jsonb;
  existing    suggestion_feedback%rowtype;
  merged      suggestion_feedback%rowtype;
  incoming_ts timestamptz;
  results     jsonb := '[]'::jsonb;
begin
  for row_in in select * from jsonb_array_elements(payload)
  loop
    select * into existing from suggestion_feedback
     where item_id = (row_in->>'item_id')::uuid
       and jar_id  = (row_in->>'jar_id')::uuid;

    if not found then
      insert into suggestion_feedback (item_id, jar_id, user_id, action, at,
                                       deleted_at, updated_at)
      values ((row_in->>'item_id')::uuid, (row_in->>'jar_id')::uuid,
              auth.uid(), row_in->>'action',
              coalesce((row_in->>'at')::timestamptz, now()),
              (row_in->>'deleted_at')::timestamptz, now())
      returning * into merged;
      results := results || to_jsonb(merged);
      continue;
    end if;

    incoming_ts := (row_in->>'updated_at')::timestamptz;

    if incoming_ts is null or incoming_ts <= existing.updated_at then
      results := results || to_jsonb(existing);
      continue;
    end if;

    update suggestion_feedback
       set action     = row_in->>'action',
           at         = coalesce((row_in->>'at')::timestamptz, existing.at),
           deleted_at = (row_in->>'deleted_at')::timestamptz,
           updated_at = now()
     where item_id = existing.item_id
       and jar_id  = existing.jar_id
    returning * into merged;
    results := results || to_jsonb(merged);
  end loop;

  return results;
end $$;
