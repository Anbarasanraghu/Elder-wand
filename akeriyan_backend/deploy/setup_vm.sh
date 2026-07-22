#!/usr/bin/env bash
# ============================================================================
# AKERIYAN — one-shot deploy on an Oracle Cloud "Always Free" Ubuntu VM (ARM).
# Run this ON THE VM after copying the akeriyan_backend folder to it.
#
#   scp -r akeriyan_backend ubuntu@<VM_IP>:~           # from your PC
#   ssh ubuntu@<VM_IP>                                 # then on the VM:
#   cd ~/akeriyan_backend && bash deploy/setup_vm.sh
# ============================================================================
set -e

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"
echo "==> App dir: $APP_DIR"

echo "==> Installing system packages..."
sudo apt-get update -y
sudo apt-get install -y python3 python3-venv python3-pip ffmpeg curl

echo "==> Creating Python venv + installing backend deps..."
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

echo "==> Installing Ollama (AI brain)..."
curl -fsSL https://ollama.com/install.sh | sh
sleep 3
echo "==> Pulling the model (this downloads ~2GB, be patient)..."
ollama pull llama3.2 || echo "   (model pull failed — run 'ollama pull llama3.2' manually later)"

echo "==> Ensuring a device token exists..."
if [ ! -f .env ]; then
  TOKEN="akeriyan-$(head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9')"
  echo "device_token=$TOKEN" > .env
  echo "   Generated token (SAVE THIS — enter it in the app):"
  echo "   >>> $TOKEN"
fi

echo "==> Opening OS firewall for port 8000..."
sudo iptables -I INPUT -p tcp --dport 8000 -j ACCEPT || true
sudo netfilter-persistent save 2>/dev/null || \
  (sudo apt-get install -y iptables-persistent && sudo netfilter-persistent save) || true

echo "==> Installing systemd service (auto-start + auto-restart)..."
sudo tee /etc/systemd/system/akeriyan.service >/dev/null <<EOF
[Unit]
Description=AKERIYAN Backend
After=network-online.target ollama.service
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now akeriyan

echo ""
echo "============================================================"
echo " DONE. AKERIYAN is live 24/7 on this VM."
IP=$(curl -s ifconfig.me || echo "<VM_PUBLIC_IP>")
echo " Backend URL for the app:  http://$IP:8000"
echo " Token: see the .env line printed above (or: cat $APP_DIR/.env)"
echo ""
echo " Check status:  sudo systemctl status akeriyan"
echo " View logs:     journalctl -u akeriyan -f"
echo " Health test:   curl http://localhost:8000/v1/health"
echo "============================================================"
