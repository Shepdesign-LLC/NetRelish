do $$
declare t text;
begin
  foreach t in array array['jars','items','tabs','labels','item_labels',
                           'recipes','suggestion_feedback','embeddings']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists owner_all on %I', t);
    execute format(
      'create policy owner_all on %I for all using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;
