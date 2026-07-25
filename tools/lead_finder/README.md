# Lead Finder (Phase 1)

Finds businesses from OpenStreetMap (free, legal, no API key), enriches each
with email / social links from its website, de-dupes against your CRM, and adds
new leads to Supabase. Runs on **GitHub Actions** — no server, no PC.

## One-time setup
1. Your repo is already on GitHub (`Anbarasanraghu/Elder-wand`).
2. GitHub → your repo → **Settings → Secrets and variables → Actions → New
   repository secret**. Add two:
   - `SUPABASE_URL` = your project URL (`https://xxxx.supabase.co`)
   - `SUPABASE_KEY` = your Supabase key (anon works; `service_role` is fine too)

## Run it
GitHub → **Actions** tab → **Lead Finder** → **Run workflow** → fill:
- **search**: `dentist` (or gym, cafe, interior designer, …)
- **area**: `Chennai`
- **limit**: `40`

New leads appear in the app under **Explore → CRM → New** within a minute.

## Notes
- Uses OpenStreetMap/Overpass (open data) — no Google Maps scraping (that's
  against Google's ToS).
- Website enrichment is best-effort and rate-limited to be polite.
- To run automatically every morning, uncomment the `schedule` block in
  `.github/workflows/lead-finder.yml`.
