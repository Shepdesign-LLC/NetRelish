-- rls_isolation.sql — proof that row-level security actually isolates accounts.
--
-- CLAUDE.md §4a says what may leave a user's account. That promise is worth
-- exactly as much as this file: a policy that exists is not a policy that
-- works. So this does not inspect pg_policy and declare victory. It creates
-- two real auth users, gives one of them data, and proves the other one
-- cannot read it, change it, delete it, or claim it.
--
-- Run top to bottom, as a role that can SET ROLE (the Supabase `postgres`
-- role, or the SQL editor). It is idempotent: every insert is ON CONFLICT
-- DO NOTHING, and the write attempts made by account B are all expected to
-- affect zero rows.
--
-- Technique: rather than minting real JWTs, the session's role and JWT claims
-- are simulated with set_config(..., true) inside a transaction, which is what
-- auth.uid() reads. Two things to know before editing this:
--   1. While role = authenticated you cannot write to the results table
--      (permission denied). Outcomes are captured into plpgsql variables and
--      only written after the role is reset to postgres.
--   2. RAISE NOTICE output is not returned by every SQL client. Results are
--      returned as rows, from t_results.
--
-- Fixtures are left in place on purpose — account A, its jar and its item are
-- reused by the sync round-trip test. Do not add cleanup to the bottom of
-- this file.

------------------------------------------------------------------------------
-- 1. Two real accounts. Every user_id in the schema has an FK to auth.users,
--    so simulated uuids are not enough — these rows have to exist.
------------------------------------------------------------------------------
insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values
 ('aaaaaaaa-0000-0000-0000-00000000000a','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','a@netrelish.test','x',now(),now(),now()),
 ('bbbbbbbb-0000-0000-0000-00000000000b','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','b@netrelish.test','x',now(),now(),now())
on conflict (id) do nothing;

------------------------------------------------------------------------------
-- 2. A jar and an item, owned by account A. The body text is what the
--    full-text check searches for.
------------------------------------------------------------------------------
insert into jars (id, user_id, name, hue) values
 ('11111111-1111-1111-1111-111111111111',
  'aaaaaaaa-0000-0000-0000-00000000000a','A jar',1)
on conflict (id) do nothing;

insert into items (id, user_id, jar_id, kind, title, body) values
 ('22222222-2222-2222-2222-222222222222',
  'aaaaaaaa-0000-0000-0000-00000000000a',
  '11111111-1111-1111-1111-111111111111',
  'page','A page','pickled cucumbers in brine')
on conflict (id) do nothing;

------------------------------------------------------------------------------
-- 3. Results table. Postgres-only; see note 1 in the header.
------------------------------------------------------------------------------
drop table if exists t_results;
create temp table t_results (
  check_name text,
  got        text,
  want       text,
  ok         boolean
);

------------------------------------------------------------------------------
-- 4. The test itself.
------------------------------------------------------------------------------
do $$
declare
  a_uid  uuid := 'aaaaaaaa-0000-0000-0000-00000000000a';
  b_uid  uuid := 'bbbbbbbb-0000-0000-0000-00000000000b';
  a_jar  uuid := '11111111-1111-1111-1111-111111111111';
  a_item uuid := '22222222-2222-2222-2222-222222222222';

  v_grants       int;
  v_b_uid        text;
  v_b_sel_items  int;
  v_b_sel_jars   int;
  v_b_upd_items  int;
  v_b_upd_jars   int;
  v_b_steal      int;
  v_b_del_items  int;
  v_b_del_jars   int;
  v_b_ins_item   text;
  v_b_ins_jar    text;
  v_b_fts        int;
  v_a_uid        text;
  v_a_items      int;
  v_a_jars       int;
  v_a_fts_rows   int;
  v_a_fts_title  text;
begin
  --------------------------------------------------------------------------
  -- Guard. If `authenticated` had no table privileges at all, every check
  -- below would "pass" for the wrong reason — permission denied rather than
  -- RLS. Assert the grants exist so that "blocked" means blocked by policy.
  --------------------------------------------------------------------------
  select count(*) into v_grants
  from information_schema.role_table_grants
  where table_schema = 'public'
    and grantee = 'authenticated'
    and privilege_type = 'SELECT'
    and table_name in ('jars','items','tabs','labels','item_labels',
                       'recipes','suggestion_feedback','embeddings');

  --------------------------------------------------------------------------
  -- Act as account B.
  --------------------------------------------------------------------------
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', b_uid, 'role','authenticated')::text, true);

  -- Prove the simulation took. Without this, a wall of zeroes could just mean
  -- auth.uid() returned NULL and nobody can see anything.
  v_b_uid := coalesce(auth.uid()::text, '<null>');

  -- SELECT
  select count(*) into v_b_sel_items from items where id = a_item;
  select count(*) into v_b_sel_jars  from jars  where id = a_jar;

  -- UPDATE (blocked by USING — zero rows, no error)
  update items set title = 'hijacked by B' where id = a_item;
  get diagnostics v_b_upd_items = row_count;

  update jars set name = 'hijacked by B' where id = a_jar;
  get diagnostics v_b_upd_jars = row_count;

  -- Steal: reassign ownership of A's row to B.
  update items set user_id = b_uid where id = a_item;
  get diagnostics v_b_steal = row_count;

  -- DELETE
  delete from items where id = a_item;
  get diagnostics v_b_del_items = row_count;

  delete from jars where id = a_jar;
  get diagnostics v_b_del_jars = row_count;

  -- Plant: the other half of theft — write a row into A's account. This is
  -- the path that actually reaches WITH CHECK, and it raises rather than
  -- silently affecting zero rows.
  begin
    insert into items (id, user_id, kind, title)
    values (gen_random_uuid(), a_uid, 'note', 'planted by B');
    v_b_ins_item := 'allowed';
  exception
    when insufficient_privilege then v_b_ins_item := 'blocked';
    when others then v_b_ins_item := 'error: ' || sqlerrm;
  end;

  begin
    insert into jars (id, user_id, name, hue)
    values (gen_random_uuid(), a_uid, 'planted by B', 2);
    v_b_ins_jar := 'allowed';
  exception
    when insufficient_privilege then v_b_ins_jar := 'blocked';
    when others then v_b_ins_jar := 'error: ' || sqlerrm;
  end;

  -- Search is a second read path into the same table. It must be fenced too.
  select count(*) into v_b_fts
  from items where fts @@ websearch_to_tsquery('english','brine');

  --------------------------------------------------------------------------
  -- Act as account A. A test where nobody can read anything is not a passing
  -- test — these checks are what make the zeroes above mean something.
  --------------------------------------------------------------------------
  perform set_config('request.jwt.claims',
    json_build_object('sub', a_uid, 'role','authenticated')::text, true);

  v_a_uid := coalesce(auth.uid()::text, '<null>');

  select count(*) into v_a_items from items;
  select count(*) into v_a_jars  from jars;

  select count(*) into v_a_fts_rows
  from items where fts @@ websearch_to_tsquery('english','brine');

  select title into v_a_fts_title
  from items where fts @@ websearch_to_tsquery('english','brine')
  order by created_at limit 1;

  --------------------------------------------------------------------------
  -- Back to postgres before writing results. See note 1 in the header.
  --------------------------------------------------------------------------
  perform set_config('role','postgres',true);

  insert into t_results (check_name, got, want, ok) values
    ('guard: authenticated holds SELECT on all 8 tables',
       v_grants::text, '8', v_grants = 8),
    ('simulation: auth.uid() is B',
       v_b_uid, b_uid::text, v_b_uid = b_uid::text),
    ('B select items (A''s item)',
       v_b_sel_items::text, '0', v_b_sel_items = 0),
    ('B select jars (A''s jar)',
       v_b_sel_jars::text, '0', v_b_sel_jars = 0),
    ('B update items (rows changed)',
       v_b_upd_items::text, '0', v_b_upd_items = 0),
    ('B update jars (rows changed)',
       v_b_upd_jars::text, '0', v_b_upd_jars = 0),
    ('B steal item by reassigning user_id',
       v_b_steal::text, '0', v_b_steal = 0),
    ('B delete items (rows deleted)',
       v_b_del_items::text, '0', v_b_del_items = 0),
    ('B delete jars (rows deleted)',
       v_b_del_jars::text, '0', v_b_del_jars = 0),
    ('B insert item owned by A (WITH CHECK)',
       v_b_ins_item, 'blocked', v_b_ins_item = 'blocked'),
    ('B insert jar owned by A (WITH CHECK)',
       v_b_ins_jar, 'blocked', v_b_ins_jar = 'blocked'),
    ('B full-text search for "brine"',
       v_b_fts::text, '0', v_b_fts = 0),
    ('simulation: auth.uid() is A',
       v_a_uid, a_uid::text, v_a_uid = a_uid::text),
    ('A still sees its own items',
       v_a_items::text, '1', v_a_items = 1),
    ('A still sees its own jars',
       v_a_jars::text, '1', v_a_jars = 1),
    ('A full-text search for "brine" (rows)',
       v_a_fts_rows::text, '1', v_a_fts_rows = 1),
    ('A full-text search for "brine" (title)',
       coalesce(v_a_fts_title,'<null>'), 'A page', v_a_fts_title = 'A page');
end $$;

------------------------------------------------------------------------------
-- 5. The other six tables.
--
--    Sections 1-4 prove isolation on jars and items in every direction. That
--    still leaves the risk the policy loop in 0003_rls.sql was written to
--    catch: a table it silently skipped. So sweep the rest — as account B,
--    try to write a row into account A's data. Each must be stopped by
--    WITH CHECK.
--
--    Only the write direction is swept here, because these tables are empty
--    and "B read zero rows" from an empty table proves nothing. An INSERT
--    naming A as the owner is a real attempt on a real policy either way.
--
--    A note on item_labels: its label_id is deliberately a uuid that does not
--    exist. RLS is evaluated on the new tuple during the insert, while the
--    foreign key is an AFTER trigger, so the policy is what rejects it. If
--    RLS ever stopped applying, the result would be a foreign-key error
--    rather than 'blocked' — which fails this check, correctly.
------------------------------------------------------------------------------
do $$
declare
  a_uid  uuid := 'aaaaaaaa-0000-0000-0000-00000000000a';
  b_uid  uuid := 'bbbbbbbb-0000-0000-0000-00000000000b';
  a_jar  uuid := '11111111-1111-1111-1111-111111111111';
  a_item uuid := '22222222-2222-2222-2222-222222222222';

  -- Every probe is formatted with the same three arguments, so each statement
  -- can name exactly the ones it needs:
  --   %1$L account A's uuid   %2$L A's item id   %3$L A's jar id
  probes text[][] := array[
    ['tabs',
     'insert into tabs (id,user_id,jar_id) values (gen_random_uuid(), %1$L, %3$L)'],
    ['labels',
     'insert into labels (id,user_id,name) values (gen_random_uuid(), %1$L, ''planted by B'')'],
    ['recipes',
     'insert into recipes (id,user_id,jar_id,name,steps) values (gen_random_uuid(), %1$L, %3$L, ''planted by B'', ''[]''::jsonb)'],
    ['suggestion_feedback',
     'insert into suggestion_feedback (item_id,jar_id,user_id,action) values (%2$L, %3$L, %1$L, ''accepted'')'],
    ['embeddings',
     'insert into embeddings (item_id,user_id,vector,model) values (%2$L, %1$L, array_fill(0::real, array[1024])::extensions.vector, ''planted by B'')'],
    ['item_labels',
     'insert into item_labels (item_id,label_id,user_id) values (%2$L, gen_random_uuid(), %1$L)']
  ];
  i    int;
  tbl  text;
  res  text;
begin
  for i in 1 .. array_length(probes,1) loop
    tbl := probes[i][1];

    perform set_config('role','authenticated',true);
    perform set_config('request.jwt.claims',
      json_build_object('sub', b_uid, 'role','authenticated')::text, true);

    begin
      execute format(probes[i][2], a_uid, a_item, a_jar);
      res := 'allowed';
    exception
      when insufficient_privilege then res := 'blocked';
      when others then res := 'error[' || sqlstate || ']: ' || sqlerrm;
    end;

    perform set_config('role','postgres',true);
    insert into t_results (check_name, got, want, ok)
    values ('B insert into ' || tbl || ' owned by A (WITH CHECK)',
            res, 'blocked', res = 'blocked');
  end loop;
end $$;

------------------------------------------------------------------------------
-- 6. The report.
------------------------------------------------------------------------------
select check_name, got, want, ok from t_results order by ok, check_name;

------------------------------------------------------------------------------
-- 7. Make failure loud. A test whose failure has to be noticed by eye is not
--    a test.
------------------------------------------------------------------------------
do $$
declare bad int;
begin
  select count(*) into bad from t_results where not ok;
  if bad > 0 then
    raise exception 'RLS ISOLATION FAILED: % check(s)', bad;
  end if;
end $$;
