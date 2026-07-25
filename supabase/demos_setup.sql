-- Elder Wand — Demo sites. Served by the `demo` Edge Function (which returns
-- text/html so it RENDERS — Supabase Storage force-serves HTML as text/plain).
-- Run once in Supabase SQL Editor.

create table if not exists demos (
  id         uuid primary key,          -- = lead id
  html       text not null,
  updated_at timestamptz not null default now()
);

alter table demos enable row level security;
drop policy if exists demos_all on demos;
create policy demos_all on demos for all using (true) with check (true);

alter table leads add column if not exists demo_url text;
