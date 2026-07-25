-- Elder Wand — Lead Agent (live scraping + validation with in-app logs).
-- Run this in Supabase → SQL Editor after crm_schema.sql.

-- a scraping run + its results summary
create table if not exists scrape_runs (
  id          uuid primary key default gen_random_uuid(),
  search      text,
  area        text,
  target      int default 25,
  status      text not null default 'queued'
              check (status in ('queued','running','done','error')),
  found       int default 0,
  validated   int default 0,
  added       int default 0,
  error       text,
  created_at  timestamptz not null default now(),
  finished_at timestamptz
);

-- live log lines the agent writes as it works (the app streams these)
create table if not exists scrape_logs (
  id      bigint generated always as identity primary key,
  run_id  uuid not null references scrape_runs(id) on delete cascade,
  level   text not null default 'info',   -- info | ok | dim | warn | error | success
  msg     text not null,
  at      timestamptz not null default now()
);
create index if not exists scrape_logs_run_idx on scrape_logs(run_id, id);

-- RLS (personal single-user app — permissive; swap to Auth for teams)
alter table scrape_runs enable row level security;
alter table scrape_logs enable row level security;
drop policy if exists anon_all_runs on scrape_runs;
drop policy if exists anon_all_logs on scrape_logs;
create policy anon_all_runs on scrape_runs for all using (true) with check (true);
create policy anon_all_logs on scrape_logs for all using (true) with check (true);

-- Realtime: let the app stream new log lines live
alter publication supabase_realtime add table scrape_logs;
alter publication supabase_realtime add table scrape_runs;
