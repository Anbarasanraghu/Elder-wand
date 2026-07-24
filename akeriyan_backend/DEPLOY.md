# Host the Elder Wand backend for FREE (no laptop needed)

The heavy AI now runs on your **phone** (Gemma LLM + speech-to-text + voice),
so this backend is small — just the feature-skills (weather, news, markets,
email, CRM…). That means it fits a **free cloud host**, and Elder Wand works
anywhere without your PC on.

## What's on the phone vs the backend

| Runs on the phone (no PC) | Runs on the hosted backend |
|---|---|
| Wake word, speech-to-text, text-to-speech | Weather, news, web search |
| Chat / thinking (on-device Gemma) | Markets, alerts, briefings |
| — | Email, CRM, projects, documents |

## Deploy on Render (easiest, free)

1. Push this repo to GitHub (already done).
2. Go to **render.com** → sign up (free) → **New +** → **Blueprint**.
3. Connect this GitHub repo. Render reads **`render.yaml`** and sets everything up:
   - builds `akeriyan_backend`, installs the light `requirements.txt`
   - starts `uvicorn app.main:app` on the port Render gives it
   - generates a strong **DEVICE_TOKEN** and sets **LLM_ENABLED=false**
4. Click **Apply**. Wait for the first build (~2–3 min). You'll get a URL like
   `https://elder-wand-backend.onrender.com`.
5. In Render → your service → **Environment**, copy the generated **DEVICE_TOKEN**.

## Point the app at it

In the Elder Wand app's connection screen:
- **Backend URL:** your Render URL, e.g. `https://elder-wand-backend.onrender.com`
- **Device Token:** the DEVICE_TOKEN from Render

Tap **Connect**. Done — the backend now works from anywhere, no laptop.

## Notes

- **Free tier sleeps** after ~15 min idle and takes ~30 s to wake on the next
  request (first action after a while is slow, then fast). Fine for personal use.
- **Understanding without Ollama:** the host has no LLM, so commands are matched
  by fast keyword rules (weather, reminders, news, briefing, email, markets…
  all work). The phone's Gemma handles free conversation. Later we can have the
  phone classify commands and send the backend a clean action.
- **Optional credentials** (set as env vars in Render if you use them):
  `GMAIL_USER`, `GMAIL_APP_PASSWORD`, `OWNER_NAME`, `DEFAULT_CITY`.
- **Other free hosts:** Railway / Fly.io work too — a `Procfile` and
  `runtime.txt` are included. Set the service root to `akeriyan_backend`.

## Security

The backend is now on the public internet, protected by the **DEVICE_TOKEN**
(every protected endpoint requires it). Keep the token secret; rotate it in
Render's Environment tab if it ever leaks.
