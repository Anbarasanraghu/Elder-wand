#!/usr/bin/env python3
"""
Elder Wand — Lead Finder (Phase 1).

Finds businesses from OpenStreetMap (free, legal, no key), enriches each with
email / phone / social links from its website, de-dupes against the CRM, and
inserts new leads into Supabase. Designed to run on GitHub Actions — no server,
no PC.

Inputs come from env vars (set by the workflow):
  SEARCH        e.g. "dentist", "gym", "interior designer"
  AREA          e.g. "Chennai", "Coimbatore"
  LIMIT         max leads to add (default 40)
  SUPABASE_URL  https://xxxx.supabase.co
  SUPABASE_KEY  anon or service_role key
"""
import os
import re
import sys
import time
import json
import urllib.parse
import requests

OVERPASS_MIRRORS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]
EMAIL_RE = re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")
SOCIAL_RE = {
    "Instagram": re.compile(r"https?://(?:www\.)?instagram\.com/[A-Za-z0-9_.]+"),
    "Facebook": re.compile(r"https?://(?:www\.)?facebook\.com/[A-Za-z0-9_.\-/]+"),
    "LinkedIn": re.compile(r"https?://(?:www\.)?linkedin\.com/[A-Za-z0-9_./\-]+"),
    "WhatsApp": re.compile(r"https?://(?:wa\.me|api\.whatsapp\.com)/[A-Za-z0-9_?=&./]+"),
}
UA = {"User-Agent": "ElderWand-LeadFinder/1.0 (+github actions; personal use)"}


def overpass_query(search: str, area: str, cap: int):
    s = search.replace('"', "")
    a = area.replace('"', "")
    # Exact area name (reliable), matched across the tag keys businesses use,
    # plus a name match so non-standard niches (e.g. "interior designer") work.
    q = f"""
    [out:json][timeout:60];
    area["name"="{a}"]->.a;
    (
      nwr(area.a)[amenity~"{s}",i];
      nwr(area.a)[shop~"{s}",i];
      nwr(area.a)[office~"{s}",i];
      nwr(area.a)[craft~"{s}",i];
      nwr(area.a)[leisure~"{s}",i];
      nwr(area.a)[healthcare~"{s}",i];
      nwr(area.a)[name~"{s}",i];
    );
    out center {cap * 3};
    """
    last = None
    for attempt in range(4):
        ep = OVERPASS_MIRRORS[attempt % len(OVERPASS_MIRRORS)]
        try:
            r = requests.post(ep, data={"data": q}, headers=UA, timeout=90)
            if r.status_code == 429:
                last = "429 rate-limited"
                time.sleep(5 * (attempt + 1))
                continue
            r.raise_for_status()
            return r.json().get("elements", [])
        except Exception as ex:  # noqa: BLE001
            last = str(ex)
            time.sleep(3 * (attempt + 1))
    raise RuntimeError(f"Overpass failed after retries: {last}")


def enrich_from_website(url: str):
    """Pull an email and social links from a business homepage (best effort)."""
    out = {"email": "", "socials": {}}
    if not url:
        return out
    if not url.startswith("http"):
        url = "http://" + url
    try:
        html = requests.get(url, headers=UA, timeout=12).text
    except Exception:
        return out
    emails = [e for e in EMAIL_RE.findall(html)
              if not e.lower().endswith((".png", ".jpg", ".gif", ".webp"))]
    if emails:
        out["email"] = emails[0]
    for name, rx in SOCIAL_RE.items():
        m = rx.search(html)
        if m:
            out["socials"][name] = m.group(0)
    return out


def existing_keys(base, headers):
    """Names already in the CRM, to avoid duplicates."""
    try:
        r = requests.get(f"{base}/rest/v1/leads?select=name,phone",
                         headers=headers, timeout=30)
        r.raise_for_status()
        return {f"{x.get('name','').strip().lower()}|{x.get('phone','')}"
                for x in r.json()}
    except Exception:
        return set()


def main():
    search = os.environ.get("SEARCH", "").strip()
    area = os.environ.get("AREA", "").strip()
    limit = int(os.environ.get("LIMIT", "40"))
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_KEY", "")

    if not (search and area and url and key):
        print("Missing SEARCH / AREA / SUPABASE_URL / SUPABASE_KEY", file=sys.stderr)
        sys.exit(1)

    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    print(f"Searching OSM for '{search}' in '{area}'…")
    elements = overpass_query(search, area, limit)
    print(f"OSM returned {len(elements)} candidates.")

    seen = existing_keys(url, headers)
    new_rows = []
    for el in elements:
        if len(new_rows) >= limit:
            break
        tags = el.get("tags", {})
        name = (tags.get("name") or "").strip()
        if not name:
            continue
        phone = (tags.get("phone") or tags.get("contact:phone") or "").strip()
        website = (tags.get("website") or tags.get("contact:website") or "").strip()
        email = (tags.get("email") or tags.get("contact:email") or "").strip()

        key_id = f"{name.lower()}|{phone}"
        if key_id in seen:
            continue
        seen.add(key_id)

        socials = {}
        if website and not email:
            enr = enrich_from_website(website)
            email = enr["email"]
            socials = enr["socials"]
            time.sleep(0.6)  # be polite to their servers

        notes = " ".join(f"{k}: {v}" for k, v in socials.items())
        new_rows.append({
            "name": name,
            "company": name,
            "phone": phone,
            "email": email,
            "website": website,
            "source": f"LeadFinder · {search} · {area}",
            "stage": "new",
            "notes": notes,
        })

    print(f"{len(new_rows)} new leads to add.")
    if new_rows:
        r = requests.post(f"{url}/rest/v1/leads", headers=headers,
                          data=json.dumps(new_rows), timeout=60)
        if r.status_code >= 300:
            print("Insert failed:", r.status_code, r.text, file=sys.stderr)
            sys.exit(1)
        print(f"Added {len(new_rows)} leads to the CRM.")
    else:
        print("Nothing new to add.")


if __name__ == "__main__":
    main()
