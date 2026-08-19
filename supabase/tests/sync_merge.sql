-- sync_merge.sql — proof that the database, not the client, decides who wins.
--
-- Three clients will push into this schema (the Mac app, the web app, the
-- extension). A merge rule written client-side would be written three times
-- and would drift, so 0005_sync_push.sql keeps the rule in one place and the
-- clients only submit. This file is what makes that claim checkable.
--
-- The policy under test:
--   * Field-level last-write-wins. Each row carries field_ts, a map of column
--     name to the timestamp of that column's last write. Strictly newer wins,
--     so a tie keeps the stored value.
--   * Except prose. When both sides edited `body` since they last agreed, no
--     winner is picked — the incoming version is inserted as a NEW item
--     tagged meta.conflict_of, so both survive. Losing a retag is an
--     annoyance; losing written prose would break CLAUDE.md §4.3, which is
--     non-negotiable.
--
-- Run top to bottom, as a role that can SET ROLE (the Supabase `postgres`
-- role, or the SQL editor). It is idempotent: it cleans conflict copies
-- before it starts and restores the shared fixture when it finishes.
--
-- Two things to know before editing this, both learned the hard way:
--   1. While role = authenticated you cannot write to the results table
--      (permission denied). Outcomes are captured into plpgsql variables and
--      only written after the role is reset to postgres.
--   2. RAISE NOTICE output is not returned by every SQL client. Results are
--      returned as rows, from t_results.
--
-- Fixtures come from rls_isolation.sql — accounts A and B, A's jar, and A's
-- item. Run that first on a fresh database. This file leaves all four in
-- place, with the item's title, body and field_ts restored, so either test
-- can be re-run in either order.
--
-- Every sync_push call is made as an authenticated account, never as
-- postgres: the function is SECURITY INVOKER, so RLS applies inside it, and
-- running it as postgres would test nothing (test 5 is the whole point).

------------------------------------------------------------------------------
-- 1. Start clean. Conflict copies are the one thing this file creates, and a
--    half-finished earlier run would make the counts in tests 2 and 3 lie.
------------------------------------------------------------------------------
delete from items where meta ? 'conflict_of';
delete from items where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b';

drop table if exists t_results;
create temp table t_results (
  check_name text,
  got        text,
  want       text,
  ok         boolean
);

------------------------------------------------------------------------------
-- 2. Different fields merge.
--
--    Both title and body were last written two hours ago; the client has been
--    away for one. It pushes a new title and nothing else. The title must
--    land and the body must be left exactly where it was — a merge that
--    clobbers untouched columns with whatever the client happened to send is
--    the classic sync bug, and it is silent.
------------------------------------------------------------------------------
do $$
declare
  a_uid  uuid := 'aaaaaaaa-0000-0000-0000-00000000000a';
  a_item uuid := '22222222-2222-2222-2222-222222222222';
  t_old  timestamptz := now() - interval '2 hours';
  t_sync timestamptz := now() - interval '1 hour';
  v_uid   text;
  v_title text;
  v_body  text;
begin
  update items
     set title    = 'A page',
         body     = 'pickled cucumbers in brine',
         field_ts = jsonb_build_object('title', t_old::text,
                                       'body',  t_old::text)
   where id = a_item;

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', a_uid, 'role','authenticated')::text, true);

  -- Prove the simulation took. Without this, every check below could pass or
  -- fail for reasons that have nothing to do with the merge.
  v_uid := coalesce(auth.uid()::text, '<null>');

  perform sync_push(
    jsonb_build_array(jsonb_build_object(
      'id',       a_item,
      'kind',     'page',
      'title',    'A page RETITLED',
      'field_ts', jsonb_build_object('title', now()::text))),
    t_sync);

  perform set_config('role','postgres',true);

  select title, body into v_title, v_body from items where id = a_item;

  insert into t_results (check_name, got, want, ok) values
    ('0. simulation: auth.uid() is A',
       v_uid, a_uid::text, v_uid = a_uid::text),
    ('1. newer title wins',
       v_title, 'A page RETITLED', v_title = 'A page RETITLED'),
    ('1. body nobody touched is left alone',
       v_body, 'pickled cucumbers in brine',
       v_body = 'pickled cucumbers in brine');
end $$;

------------------------------------------------------------------------------
-- 3. Both sides edited the prose. Keep both.
--
--    The stored body was written a minute ago; the client last agreed with
--    the server an hour ago and is pushing a different body. Neither edit has
--    seen the other, so there is no honest way to pick a winner. The incoming
--    text is inserted as a new item tagged meta.conflict_of, and the stored
--    text is not touched.
------------------------------------------------------------------------------
do $$
declare
  a_uid    uuid := 'aaaaaaaa-0000-0000-0000-00000000000a';
  a_item   uuid := '22222222-2222-2222-2222-222222222222';
  t_recent timestamptz := now() - interval '1 minute';
  t_sync   timestamptz := now() - interval '1 hour';
  v_copies     int;
  v_orig_body  text;
  v_copy_body  text;
  v_copy_of    text;
begin
  update items
     set body     = 'pickled cucumbers in brine',
         field_ts = field_ts || jsonb_build_object('body', t_recent::text)
   where id = a_item;

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', a_uid, 'role','authenticated')::text, true);

  perform sync_push(
    jsonb_build_array(jsonb_build_object(
      'id',       a_item,
      'kind',     'page',
      'title',    'A page RETITLED',
      'body',     'fermented gherkins, written on the laptop',
      'field_ts', jsonb_build_object('body', now()::text))),
    t_sync);

  perform set_config('role','postgres',true);

  select count(*) into v_copies from items where meta ? 'conflict_of';
  select body     into v_orig_body from items where id = a_item;
  select body, meta->>'conflict_of' into v_copy_body, v_copy_of
    from items where meta ? 'conflict_of' limit 1;

  insert into t_results (check_name, got, want, ok) values
    ('2. exactly one conflict copy',
       v_copies::text, '1', v_copies = 1),
    ('2. the stored prose is not overwritten',
       coalesce(v_orig_body,'<null>'), 'pickled cucumbers in brine',
       v_orig_body = 'pickled cucumbers in brine'),
    ('2. the copy carries the incoming prose',
       coalesce(v_copy_body,'<null>'), 'fermented gherkins, written on the laptop',
       v_copy_body = 'fermented gherkins, written on the laptop'),
    ('2. the copy points back at the original',
       coalesce(v_copy_of,'<null>'), a_item::text, v_copy_of = a_item::text);
end $$;

------------------------------------------------------------------------------
-- 4. A client that is up to date must NOT spawn a copy.
--
--    Same push as test 3 — a different body, arriving after a recent server
--    write — except the client has synced since that write. This is a plain
--    edit and must merge in place. If it produces a second copy, the
--    client_synced_at comparison is inverted, and every ordinary edit from
--    every client would fork the item. That bug is the reason this test
--    exists; it is the failure mode that would quietly bury a user's Pantry
--    in duplicates.
------------------------------------------------------------------------------
do $$
declare
  a_uid    uuid := 'aaaaaaaa-0000-0000-0000-00000000000a';
  a_item   uuid := '22222222-2222-2222-2222-222222222222';
  t_recent timestamptz := now() - interval '1 minute';
  v_copies int;
  v_body   text;
begin
  update items
     set field_ts = field_ts || jsonb_build_object('body', t_recent::text)
   where id = a_item;

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', a_uid, 'role','authenticated')::text, true);

  perform sync_push(
    jsonb_build_array(jsonb_build_object(
      'id',       a_item,
      'kind',     'page',
      'body',     'dill spears, written on the same laptop',
      'field_ts', jsonb_build_object('body', now()::text))),
    now());                            -- the client is current

  perform set_config('role','postgres',true);

  select count(*) into v_copies from items where meta ? 'conflict_of';
  select body     into v_body   from items where id = a_item;

  insert into t_results (check_name, got, want, ok) values
    ('3. a current client spawns no second copy',
       v_copies::text, '1', v_copies = 1),
    ('3. its edit merges in place instead',
       coalesce(v_body,'<null>'), 'dill spears, written on the same laptop',
       v_body = 'dill spears, written on the same laptop');
end $$;

------------------------------------------------------------------------------
-- 5. Ties keep the stored value.
--
--    Two writes stamped at the same instant is not a hypothetical: clients
--    round timestamps, and a retry re-sends the stamp it sent the first time.
--    The rule is strictly-newer-wins, so an equal stamp changes nothing —
--    which also makes a replayed push harmless.
------------------------------------------------------------------------------
do $$
declare
  a_uid  uuid := 'aaaaaaaa-0000-0000-0000-00000000000a';
  a_item uuid := '22222222-2222-2222-2222-222222222222';
  t_tie  timestamptz := now() - interval '30 minutes';
  t_sync timestamptz := now() - interval '1 hour';
  v_title text;
begin
  update items
     set title    = 'A page RETITLED',
         field_ts = field_ts || jsonb_build_object('title', t_tie::text)
   where id = a_item;

  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', a_uid, 'role','authenticated')::text, true);

  perform sync_push(
    jsonb_build_array(jsonb_build_object(
      'id',       a_item,
      'kind',     'page',
      'title',    'A page TIE LOSER',
      'field_ts', jsonb_build_object('title', t_tie::text))),
    t_sync);

  perform set_config('role','postgres',true);

  select title into v_title from items where id = a_item;

  insert into t_results (check_name, got, want, ok) values
    ('4. an equal timestamp does not win',
       v_title, 'A page RETITLED', v_title = 'A page RETITLED');
end $$;

------------------------------------------------------------------------------
-- 6. RLS still applies inside the function.
--
--    sync_push is SECURITY INVOKER, so account B pushing at account A's item
--    id must not reach A's row. B cannot see it, so the function's SELECT
--    finds nothing and it takes the INSERT branch instead — where the primary
--    key collides with the row B is not allowed to know about, and the whole
--    call is rejected.
--
--    Two things are recorded rather than assumed: that A's title and body are
--    untouched, and that B was left holding no row of its own. The rejection
--    itself is recorded as an observation, because the interesting part is
--    which error arrives.
------------------------------------------------------------------------------
do $$
declare
  a_uid  uuid := 'aaaaaaaa-0000-0000-0000-00000000000a';
  b_uid  uuid := 'bbbbbbbb-0000-0000-0000-00000000000b';
  a_item uuid := '22222222-2222-2222-2222-222222222222';
  v_uid_b  text;
  v_state  text;
  v_msg    text;
  v_title  text;
  v_body   text;
  v_b_rows int;
begin
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', b_uid, 'role','authenticated')::text, true);

  v_uid_b := coalesce(auth.uid()::text, '<null>');

  begin
    perform sync_push(
      jsonb_build_array(jsonb_build_object(
        'id',       a_item,
        'kind',     'page',
        'title',    'hijacked by B',
        'field_ts', jsonb_build_object('title', now()::text))),
      now() - interval '1 hour');
    v_state := 'accepted';
    v_msg   := 'accepted';
  exception
    when others then
      v_state := sqlstate;
      v_msg   := sqlerrm;
  end;

  perform set_config('role','postgres',true);

  select title, body into v_title, v_body from items where id = a_item;
  select count(*)   into v_b_rows from items where user_id = b_uid;

  insert into t_results (check_name, got, want, ok) values
    ('0. simulation: auth.uid() is B',
       v_uid_b, b_uid::text, v_uid_b = b_uid::text),
    ('5. B''s push is rejected (sqlstate)',
       v_state, '23505', v_state = '23505'),
    ('5. (detail) the rejection B actually gets',
       v_msg, v_msg, true),
    ('5. A''s title survives B''s push',
       v_title, 'A page RETITLED', v_title = 'A page RETITLED'),
    ('5. A''s body survives B''s push',
       coalesce(v_body,'<null>'), 'dill spears, written on the same laptop',
       v_body = 'dill spears, written on the same laptop'),
    ('5. B is left holding no row',
       v_b_rows::text, '0', v_b_rows = 0);
end $$;

------------------------------------------------------------------------------
-- 7. Negative control.
--
--    Section 10 is the only thing that turns a failed check into a failed
--    run. A guard that never fires is indistinguishable from a guard that
--    cannot fire, so plant a failing row, confirm the guard raises on it, and
--    take it back out.
------------------------------------------------------------------------------
do $$
declare
  bad   int;
  fired boolean := false;
begin
  insert into t_results (check_name, got, want, ok)
  values ('negative control: planted failure', 'no', 'yes', false);

  begin
    select count(*) into bad from t_results where not ok;
    if bad > 0 then
      raise exception 'SYNC MERGE FAILED: % check(s)', bad;
    end if;
  exception
    when others then fired := true;
  end;

  delete from t_results where check_name = 'negative control: planted failure';

  insert into t_results (check_name, got, want, ok)
  values ('6. the guard fires on a failing row',
          fired::text, 'true', fired);
end $$;

------------------------------------------------------------------------------
-- 8. Put the fixture back. Only rows this file created are removed; accounts
--    A and B, A's jar and A's item stay, with the item exactly as
--    rls_isolation.sql left it.
------------------------------------------------------------------------------
delete from items where meta ? 'conflict_of';
delete from items where user_id = 'bbbbbbbb-0000-0000-0000-00000000000b';

update items
   set title      = 'A page',
       body       = 'pickled cucumbers in brine',
       field_ts   = '{}'::jsonb,
       updated_at = now()
 where id = '22222222-2222-2222-2222-222222222222';

------------------------------------------------------------------------------
-- 9. The report.
------------------------------------------------------------------------------
select check_name, got, want, ok from t_results order by ok, check_name;

------------------------------------------------------------------------------
-- 10. Make failure loud. A test whose failure has to be noticed by eye is not
--     a test.
------------------------------------------------------------------------------
do $$
declare bad int;
begin
  select count(*) into bad from t_results where not ok;
  if bad > 0 then
    raise exception 'SYNC MERGE FAILED: % check(s)', bad;
  end if;
end $$;
