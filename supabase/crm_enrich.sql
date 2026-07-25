-- Elder Wand — richer lead details. Run once in Supabase SQL Editor.
alter table leads add column if not exists address  text;
alter table leads add column if not exists category text;
alter table leads add column if not exists lat      double precision;
alter table leads add column if not exists lon      double precision;
