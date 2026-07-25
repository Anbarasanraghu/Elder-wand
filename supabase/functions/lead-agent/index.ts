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
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
  "https://overpass.openstreetmap.fr/api/interpreter",
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

async function overpass(
  search: string,
  area: string,
  cap: number,
  log: (m: string, l?: string) => Promise<unknown>,
) {
  const s = search.replace(/"/g, "");
  const a = area.replace(/"/g, "");
  const q = `[out:json][timeout:50];area["name"="${a}"]->.a;(` +
    `nwr(area.a)[amenity~"${s}",i];nwr(area.a)[shop~"${s}",i];` +
    `nwr(area.a)[office~"${s}",i];nwr(area.a)[craft~"${s}",i];` +
    `nwr(area.a)[leisure~"${s}",i];nwr(area.a)[healthcare~"${s}",i];` +
    `nwr(area.a)[name~"${s}",i];);out center ${cap};`;
  const sleep = (ms: number) => new Promise((x) => setTimeout(x, ms));
  // Public Overpass mirrors are flaky (429/504) — rotate + retry so a busy
  // server doesn't make a run come back empty.
  for (let i = 0; i < 8; i++) {
    const ep = MIRRORS[i % MIRRORS.length];
    try {
      const r = await fetchWithTimeout(ep, 45000, {
        method: "POST",
        body: new URLSearchParams({ data: q }),
      });
      if (r.status === 429 || r.status >= 500) {
        await log(`Server busy (${r.status}), trying another mirror…`, "dim");
        await sleep(2500 + i * 800);
        continue;
      }
      const j = await r.json();
      const els = j.elements ?? [];
      if (els.length) return els;
      await log("A mirror returned nothing, trying another…", "dim");
      await sleep(1500);
    } catch (_) {
      await log("Mirror timed out, trying another…", "dim");
      await sleep(1500);
    }
  }
  return [];
}

async function reverseGeocode(lat: number, lon: number): Promise<string> {
  try {
    const r = await fetchWithTimeout(
      `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lon}`,
      8000,
      { headers: { "User-Agent": "ElderWand-LeadAgent/1.0" } },
    );
    const j = await r.json();
    return j.display_name ?? "";
  } catch (_) {
    return "";
  }
}

function addrFromTags(t: Record<string, string>): string {
  return [
    t["addr:housenumber"],
    t["addr:street"],
    t["addr:suburb"] ?? t["addr:neighbourhood"],
    t["addr:city"],
    t["addr:postcode"],
  ].filter(Boolean).join(", ");
}

function categoryOf(t: Record<string, string>): string {
  for (const k of ["amenity", "shop", "office", "craft", "leisure", "healthcare"]) {
    if (t[k]) return t[k].replace(/_/g, " ");
  }
  return "";
}

async function enrich(url: string) {
  let u = url;
  if (!u.startsWith("http")) u = "http://" + u;
  const out: { email: string; phone: string; socials: Record<string, string> } =
    { email: "", phone: "", socials: {} };
  try {
    const r = await fetchWithTimeout(u, 7000, {
      headers: { "User-Agent": "Mozilla/5.0 (compatible; ElderWand/1.0)" },
    });
    const html = await r.text();
    const m = html.match(EMAIL);
    if (m && !/\.(png|jpg|gif|webp)$/i.test(m[0])) out.email = m[0];
    const tel = html.match(/tel:\s*([+\d][\d\s().-]{6,})/i);
    if (tel) out.phone = tel[1].replace(/[^\d+]/g, "");
    for (const [k, rx] of Object.entries(SOCIALS)) {
      const s = html.match(rx);
      if (s) out.socials[k] = s[0];
    }
  } catch (_) { /* site unreachable */ }
  return out;
}

// Free web search (DuckDuckGo HTML) to find a business's site when OSM has none.
async function webSearch(query: string): Promise<string[]> {
  try {
    const r = await fetchWithTimeout(
      "https://html.duckduckgo.com/html/?q=" + encodeURIComponent(query),
      7000,
      { headers: { "User-Agent": "Mozilla/5.0 (compatible; ElderWand/1.0)" } },
    );
    const html = await r.text();
    const urls: string[] = [];
    const re = /class="result__a"[^>]*href="([^"]+)"/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(html)) !== null && urls.length < 4) {
      let u = m[1];
      const enc = u.match(/uddg=([^&]+)/);
      if (enc) u = decodeURIComponent(enc[1]);
      if (u.startsWith("http")) urls.push(u);
    }
    return urls;
  } catch (_) {
    return [];
  }
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
    const els = await overpass(search, area, target * 4, log);
    await log(`Found ${els.length} candidates.`, els.length ? "ok" : "warn");
    if (!els.length) {
      await log(
        "No results — the map servers may be busy (try again), or this niche "
          + "has little OpenStreetMap data. Physical businesses (dentist, gym, "
          + "cafe, salon, hotel, clinic) work best.",
        "warn",
      );
    }

    const { data: existing } = await sb.from("leads").select("name,phone");
    const seen = new Set(
      (existing ?? []).map((x: any) =>
        `${(x.name ?? "").toLowerCase()}|${x.phone ?? ""}`
      ),
    );

    const rows: any[] = [];
    let validated = 0, skipped = 0;
    const t0 = Date.now();
    const budget = () => Date.now() - t0 < 110000; // stop enriching near timeout
    for (const el of els) {
      if (rows.length >= target) break;
      const t = el.tags ?? {};
      const name = (t.name ?? "").trim();
      if (!name) continue;
      let phone = (t.phone ?? t["contact:phone"] ?? "").trim();
      let website = (t.website ?? t["contact:website"] ?? "").trim();
      let email = (t.email ?? t["contact:email"] ?? "").trim();

      const key = `${name.toLowerCase()}|${phone}`;
      if (seen.has(key)) {
        skipped++;
        continue;
      }
      seen.add(key);

      // If OSM has no website, find one via a free web search.
      if (!website && budget()) {
        await log(`Searching the web for "${name}"…`, "dim");
        const hits = await webSearch(`${name} ${area} contact`);
        website = hits.find((h) =>
          !/facebook|instagram|linkedin|justdial|indiamart|yelp|tripadvisor|youtube/i
            .test(h)
        ) ?? hits[0] ?? "";
        await new Promise((x) => setTimeout(x, 600));
      }
      let socials: Record<string, string> = {};
      if (website && budget()) {
        await log(`Reading ${website.replace(/^https?:\/\//, "").slice(0, 40)}…`, "dim");
        const e = await enrich(website);
        if (!email) email = e.email;
        if (!phone) phone = e.phone;
        socials = e.socials;
      }

      // location + address (reverse-geocode when the POI has no address tags)
      const lat = el.lat ?? el.center?.lat;
      const lon = el.lon ?? el.center?.lon;
      let address = addrFromTags(t);
      if (!address && lat && lon && budget()) {
        address = await reverseGeocode(lat, lon);
        await new Promise((x) => setTimeout(x, 1100)); // Nominatim: 1 req/sec
      }
      const category = categoryOf(t);

      const emailOk = email ? EMAIL.test(email) : false;
      const phoneOk = phone.replace(/\D/g, "").length >= 8;
      if (emailOk) validated++;
      await log(
        `${emailOk || phoneOk ? "✓" : "•"} ${name}` +
          `${category ? " (" + category + ")" : ""}` +
          `${phone ? " · " + phone : ""}${email ? " · " + email : ""}` +
          `${address ? " · " + address.split(",").slice(0, 2).join(",") : ""}`,
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
        address,
        category,
        lat,
        lon,
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
