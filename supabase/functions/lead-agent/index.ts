// Elder Wand — Lead Agent (Supabase Edge Function).
// Scrapes businesses (OpenStreetMap, free/legal), enriches + validates contacts
// from their websites, de-dupes against the CRM, inserts new leads, and writes
// LIVE log lines to scrape_logs so the app can stream them. No PC, no server.
//
// Deploy: Supabase → Edge Functions → deploy `lead-agent`. It uses the built-in
// SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY env vars (no keys to manage).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MIRRORS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
];
const EMAIL = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/;
const SOCIALS: Record<string, RegExp> = {
  Instagram: /https?:\/\/(?:www\.)?instagram\.com\/[A-Za-z0-9_.]+/,
  Facebook: /https?:\/\/(?:www\.)?facebook\.com\/[A-Za-z0-9_.\-/]+/,
  WhatsApp: /https?:\/\/(?:wa\.me|api\.whatsapp\.com)\/[A-Za-z0-9_?=&./]+/,
};
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
};

async function fetchWithTimeout(url: string, ms: number, init?: RequestInit) {
  const c = new AbortController();
  const t = setTimeout(() => c.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: c.signal });
  } finally {
    clearTimeout(t);
  }
}

async function overpass(search: string, area: string, cap: number) {
  const s = search.replace(/"/g, "");
  const a = area.replace(/"/g, "");
  const q = `[out:json][timeout:60];area["name"="${a}"]->.a;(` +
    `nwr(area.a)[amenity~"${s}",i];nwr(area.a)[shop~"${s}",i];` +
    `nwr(area.a)[office~"${s}",i];nwr(area.a)[craft~"${s}",i];` +
    `nwr(area.a)[leisure~"${s}",i];nwr(area.a)[healthcare~"${s}",i];` +
    `nwr(area.a)[name~"${s}",i];);out center ${cap};`;
  for (let i = 0; i < 4; i++) {
    try {
      const r = await fetchWithTimeout(MIRRORS[i % MIRRORS.length], 90000, {
        method: "POST",
        body: new URLSearchParams({ data: q }),
      });
      if (r.status === 429) {
        await new Promise((x) => setTimeout(x, 4000));
        continue;
      }
      const j = await r.json();
      const els = j.elements ?? [];
      if (els.length) return els;
    } catch (_) { /* try next mirror */ }
    await new Promise((x) => setTimeout(x, 2000));
  }
  return [];
}

async function enrich(url: string) {
  let u = url;
  if (!u.startsWith("http")) u = "http://" + u;
  const out: { email: string; socials: Record<string, string> } = {
    email: "",
    socials: {},
  };
  try {
    const r = await fetchWithTimeout(u, 8000);
    const html = await r.text();
    const m = html.match(EMAIL);
    if (m && !/\.(png|jpg|gif|webp)$/i.test(m[0])) out.email = m[0];
    for (const [k, rx] of Object.entries(SOCIALS)) {
      const s = html.match(rx);
      if (s) out.socials[k] = s[0];
    }
  } catch (_) { /* site unreachable */ }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { run_id, search, area, target = 25 } = await req.json();
  const log = (msg: string, level = "info") =>
    sb.from("scrape_logs").insert({ run_id, msg, level });

  try {
    await sb.from("scrape_runs").update({ status: "running" }).eq("id", run_id);
    await log(`Searching OpenStreetMap for "${search}" in "${area}"…`);
    const els = await overpass(search, area, target * 4);
    await log(`Found ${els.length} candidates.`, "ok");

    const { data: existing } = await sb.from("leads").select("name,phone");
    const seen = new Set(
      (existing ?? []).map((x: any) =>
        `${(x.name ?? "").toLowerCase()}|${x.phone ?? ""}`
      ),
    );

    const rows: any[] = [];
    let validated = 0, skipped = 0;
    for (const el of els) {
      if (rows.length >= target) break;
      const t = el.tags ?? {};
      const name = (t.name ?? "").trim();
      if (!name) continue;
      let phone = (t.phone ?? t["contact:phone"] ?? "").trim();
      const website = (t.website ?? t["contact:website"] ?? "").trim();
      let email = (t.email ?? t["contact:email"] ?? "").trim();

      const key = `${name.toLowerCase()}|${phone}`;
      if (seen.has(key)) {
        skipped++;
        continue;
      }
      seen.add(key);

      let socials: Record<string, string> = {};
      if (website && !email) {
        await log(`Checking website: ${website}`, "dim");
        const e = await enrich(website);
        email = e.email;
        socials = e.socials;
      }
      const emailOk = email ? EMAIL.test(email) : false;
      const phoneOk = phone.replace(/\D/g, "").length >= 8;
      if (emailOk) validated++;
      await log(
        `${emailOk || phoneOk ? "✓" : "•"} ${name}` +
          `${email ? " · " + email : ""}${phone ? " · " + phone : ""}` +
          `${email && !emailOk ? " (email unverified)" : ""}`,
        emailOk || phoneOk ? "ok" : "dim",
      );
      const notes = Object.entries(socials).map(([k, v]) => `${k}: ${v}`).join(
        "  ",
      );
      rows.push({
        name,
        company: name,
        phone,
        email,
        website,
        source: `LeadAgent · ${search} · ${area}`,
        stage: "new",
        notes,
      });
    }

    await log(
      `${rows.length} new leads, ${validated} with valid email, ${skipped} skipped (already in CRM).`,
    );
    if (rows.length) {
      const { error } = await sb.from("leads").insert(rows);
      if (error) throw error;
    }
    await log(`Done — added ${rows.length} leads to your CRM.`, "success");
    await sb.from("scrape_runs").update({
      status: "done",
      found: els.length,
      validated,
      added: rows.length,
      finished_at: new Date().toISOString(),
    }).eq("id", run_id);

    return new Response(
      JSON.stringify({ ok: true, added: rows.length, validated }),
      { headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    await log(`Error: ${e instanceof Error ? e.message : e}`, "error");
    await sb.from("scrape_runs").update({
      status: "error",
      error: String(e),
      finished_at: new Date().toISOString(),
    }).eq("id", run_id);
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
