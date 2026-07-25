-- Elder Wand CRM — Supabase schema (Phase 1 data spine)
-- Run this once in your Supabase project: SQL Editor → New query → paste → Run.
-- Free tier, no credit card. This is the always-on database the app talks to.

-- ---- leads: the core pipeline record ----
create table if not exists leads (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  company     text,
  phone       text,
  email       text,
  website     text,
  source      text,                    -- where the lead came from
  stage       text not null default 'new'
              check (stage in ('new','contacted','qualified','proposal','won','lost')),
  value       numeric default 0,       -- estimated deal value
  tags        text[] default '{}',
  notes       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---- activities: timeline of touches on a lead ----
create table if not exists activities (
  id          uuid primary key default gen_random_uuid(),
  lead_id     uuid not null references leads(id) on delete cascade,
  kind        text not null default 'note'
              check (kind in ('note','call','email','whatsapp','sms','meeting')),
  body        text,
  created_at  timestamptz not null default now()
);

-- ---- followups: reminders/next-steps per lead ----
create table if not exists followups (
  id          uuid primary key default gen_random_uuid(),
  lead_id     uuid not null references leads(id) on delete cascade,
  due_at      timestamptz not null,
  note        text,
  done        boolean not null default false,
  created_at  timestamptz not null default now()
);

create index if not exists leads_stage_idx on leads(stage);
create index if not exists activities_lead_idx on activities(lead_id, created_at desc);
create index if not exists followups_due_idx on followups(due_at) where not done;

-- keep updated_at fresh
create or replace function touch_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;
drop trigger if exists leads_touch on leads;
create trigger leads_touch before update on leads
  for each row execute function touch_updated_at();

-- ---- Row Level Security ----
-- Personal single-user app: allow the anon key full access to YOUR project.
-- (The key lives only in your own app. Swap to Supabase Auth later for teams.)
alter table leads      enable row level security;
alter table activities enable row level security;
alter table followups  enable row level security;

drop policy if exists anon_all_leads on leads;
drop policy if exists anon_all_activities on activities;
drop policy if exists anon_all_followups on followups;
create policy anon_all_leads      on leads      for all using (true) with check (true);
create policy anon_all_activities on activities for all using (true) with check (true);
create policy anon_all_followups  on followups  for all using (true) with check (true);
