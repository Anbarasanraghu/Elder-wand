// Elder Wand — serve a lead's demo site as real HTML (so it renders in a
// browser). Deploy PUBLIC so the link opens without a key:
//   supabase functions deploy demo --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const id = new URL(req.url).searchParams.get("id");
  if (!id) return new Response("Missing id", { status: 400 });

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data } = await sb.from("demos").select("html").eq("id", id)
    .maybeSingle();
  if (!data) return new Response("Demo not found", { status: 404 });

  return new Response(data.html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "public, max-age=60",
    },
  });
});
