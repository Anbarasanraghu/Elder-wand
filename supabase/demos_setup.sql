-- Elder Wand — Demo sites hosting (free, on Supabase Storage).
-- Run once in Supabase SQL Editor.

-- public bucket that serves the generated demo pages
insert into storage.buckets (id, name, public)
values ('demos', 'demos', true)
on conflict (id) do nothing;

-- personal single-user app: let the anon key upload/replace demo files
drop policy if exists "demos_all" on storage.objects;
create policy "demos_all" on storage.objects
  for all using (bucket_id = 'demos') with check (bucket_id = 'demos');

-- remember the generated link on the lead
alter table leads add column if not exists demo_url text;
