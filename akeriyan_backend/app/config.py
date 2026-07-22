from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "Elder Wand Backend"
    version: str = "0.2.0"

    # Security token — your phone must send this to talk to the backend.
    # CHANGE this to your own long random text.
    device_token: str = "akeriyan-CHANGE-ME-to-something-long-and-random"

    host: str = "0.0.0.0"   # listen on all interfaces so your phone can reach it
    port: int = 8000

    # ---- The AI brain (100% free, runs on your own PC) --------------------
    # Install Ollama from https://ollama.com then run:  ollama pull llama3.2
    # If Ollama isn't running, AKERIYAN gracefully falls back to fast rules.
    ollama_url: str = "http://localhost:11434"
    ollama_model: str = "llama3.2"          # small + fast; try "qwen2.5" for smarter
    vision_model: str = "moondream"         # local camera-vision model (free)
    llm_enabled: bool = True

    # ---- Who I am talking to (used in replies) ----------------------------
    owner_name: str = "Anbarasan"

    # ---- Location for weather (free Open-Meteo, no key needed) -------------
    default_city: str = "Chennai"

    # ---- Gmail via IMAP/SMTP (free, no API key). Use a Gmail App Password ---
    # 1) Enable 2-Step Verification on your Google account.
    # 2) myaccount.google.com/apppasswords -> create one -> paste it below
    #    (or in a .env file as GMAIL_USER / GMAIL_APP_PASSWORD).
    gmail_user: str = ""
    gmail_app_password: str = ""

    class Config:
        env_file = ".env"


settings = Settings()
