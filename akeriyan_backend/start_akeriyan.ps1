# AKERIYAN backend launcher — started automatically at logon by Task Scheduler.
# Ensures Ollama is up, then runs the FastAPI backend (blocks so the task stays
# alive; Task Scheduler restarts it if it ever crashes).
$ErrorActionPreference = "SilentlyContinue"

$root = "C:\Users\anbar\Desktop\My_Projects\Akeriyan\akeriyan_backend"
Set-Location $root
New-Item -ItemType Directory -Force "$root\logs" | Out-Null

# 1. Make sure the Ollama server (AI brain) is running.
$ollamaApp = "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe"
$up = $false
try { Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 2 -UseBasicParsing | Out-Null; $up = $true } catch {}
if (-not $up -and (Test-Path $ollamaApp)) {
    Start-Process $ollamaApp
    Start-Sleep -Seconds 6
}

# 2. Run the backend, auto-restarting it if it ever stops.
while ($true) {
    "[$(Get-Date -Format 'u')] starting backend" *>> "$root\logs\backend.log"
    & "$root\venv\Scripts\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 *>> "$root\logs\backend.log"
    "[$(Get-Date -Format 'u')] backend exited; restarting in 5s" *>> "$root\logs\backend.log"
    Start-Sleep -Seconds 5
}
