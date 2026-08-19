-- Corrects 0008. Row-level LWW had nothing valid to compare.
--
-- 0008 decided the winner with:
--
--     incoming (row_in->>'updated_at')  vs  stored (server's now() at merge)
--
-- and its own header says so. Those are two different clocks. Field-level
-- tables get away with this because they keep both: `field_ts` holds CLIENT
-- INTENT (when the user changed this field) while `updated_at` holds SERVER
-- RECEIPT (the pull cursor, always now(), so a wrong client clock can neither
-- win forever nor hide a row).
--
-- item_labels and suggestion_feedback have no field_ts, so setting
-- updated_at = now() destroyed the only record of client intent — and the next
-- push compared its intent against the server's receipt and always lost. The
-- case these tables exist for broke: device A unlabels at 10:00, device B
-- labels at 10:05, B syncs second, and both collapse to receipt order.
--
-- `client_ts` restores the missing clock. LWW compares client_ts to client_ts;
-- updated_at stays server receipt and stays the pull cursor.
--
-- Proven after this migration: an unlabel after a label tombstones; a NEWER
-- relabel revives the row; a STALE unlabel does not win; a newer verdict wins;
-- a stale verdict does not.

alter table item_labels         add column if not exists client_ts timestamptz;
alter table suggestion_feedback add column if not exists client_ts timestamptz;

-- Existing rows never stated an intent; receipt is the best estimate we have.
update item_labels         set client_ts = coalesce(client_ts, updated_at);
update suggestion_feedback set client_ts = coalesce(client_ts, updated_at);

create or replace function sync_push_item_labels(payload jsonb)
returns jsonb language plpgsql security invoker set search_path = public, extensions as $$
declare
  r jsonb; ex item_labels%rowtype; mg item_labels%rowtype;
  cts timestamptz; out_rows jsonb := '[]'::jsonb;
begin
  for r in select * from jsonb_array_elements(payload) loop
    -- The client's own assertion time. Fall back to updated_at for clients
    -- that predate this column.
    cts := coalesce((r->>'client_ts')::timestamptz, (r->>'updated_at')::timestamptz);
    select * into ex from item_labels
     where item_id = (r->>'item_id')::uuid and label_id = (r->>'label_id')::uuid;

    if not found then
      insert into item_labels (item_id, label_id, user_id, deleted_at, client_ts, updated_at)
      values ((r->>'item_id')::uuid, (r->>'label_id')::uuid, auth.uid(),
              (r->>'deleted_at')::timestamptz, coalesce(cts, now()), now())
      returning * into mg;
      out_rows := out_rows || to_jsonb(mg); continue;
    end if;

    -- Strictly newer intent wins; a tie keeps what is stored.
    if cts is not null and (ex.client_ts is null or cts > ex.client_ts) then
      update item_labels
         set deleted_at = (r->>'deleted_at')::timestamptz,
             client_ts  = cts,
             updated_at = now()
       where item_id = ex.item_id and label_id = ex.label_id
      returning * into mg;
      out_rows := out_rows || to_jsonb(mg);
    else
      out_rows := out_rows || to_jsonb(ex);
    end if;
  end loop;
  return out_rows;
end $$;

create or replace function sync_push_feedback(payload jsonb)
returns jsonb language plpgsql security invoker set search_path = public, extensions as $$
declare
  r jsonb; ex suggestion_feedback%rowtype; mg suggestion_feedback%rowtype;
  cts timestamptz; out_rows jsonb := '[]'::jsonb;
begin
  for r in select * from jsonb_array_elements(payload) loop
    cts := coalesce((r->>'client_ts')::timestamptz, (r->>'updated_at')::timestamptz);
    select * into ex from suggestion_feedback
     where item_id = (r->>'item_id')::uuid and jar_id = (r->>'jar_id')::uuid;

    if not found then
      insert into suggestion_feedback (item_id, jar_id, user_id, action, at,
                                       deleted_at, client_ts, updated_at)
      values ((r->>'item_id')::uuid, (r->>'jar_id')::uuid, auth.uid(),
              r->>'action', coalesce((r->>'at')::timestamptz, now()),
              (r->>'deleted_at')::timestamptz, coalesce(cts, now()), now())
      returning * into mg;
      out_rows := out_rows || to_jsonb(mg); continue;
    end if;

    if cts is not null and (ex.client_ts is null or cts > ex.client_ts) then
      update suggestion_feedback
         set action     = r->>'action',
             at         = coalesce((r->>'at')::timestamptz, ex.at),
             deleted_at = (r->>'deleted_at')::timestamptz,
             client_ts  = cts,
             updated_at = now()
       where item_id = ex.item_id and jar_id = ex.jar_id
      returning * into mg;
      out_rows := out_rows || to_jsonb(mg);
    else
      out_rows := out_rows || to_jsonb(ex);
    end if;
  end loop;
  return out_rows;
end $$;
