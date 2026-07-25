// Elder Wand — demo site renderer (Cloudflare Worker).
// Supabase force-serves HTML as text/plain (anti-phishing), so demo links show
// source. This tiny worker proxies your public Supabase `demo` function and
// re-serves the HTML as text/html — so it RENDERS. Free, no card.
//
// Deploy (dashboard, ~3 min):
//   1. dash.cloudflare.com → sign up (free, no card)
//   2. Workers & Pages → Create → Worker → name it e.g. "elder-demo" → Deploy
//   3. Edit code → paste THIS file → Deploy
//   4. Copy the worker URL (https://elder-demo.<you>.workers.dev)
//   5. In the app, when generating a demo, paste that URL as the Demo host
//
// The Supabase function URL is already correct for your project.

const SUPABASE_FN =
  "https://qdnuflnnwliktddnmbia.supabase.co/functions/v1/demo";

export default {
  async fetch(request) {
    const id = new URL(request.url).searchParams.get("id");
    if (!id) return new Response("Missing id", { status: 400 });

    const r = await fetch(`${SUPABASE_FN}?id=${encodeURIComponent(id)}`);
    const html = await r.text();
    return new Response(html, {
      status: r.status,
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "public, max-age=60",
      },
    });
  },
};
