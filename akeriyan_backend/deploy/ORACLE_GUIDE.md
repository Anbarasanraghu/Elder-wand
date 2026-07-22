# AKERIYAN — 24/7 free hosting on Oracle Cloud (Always Free)

Goal: run the backend on a free Oracle VM so it's live even when your PC is off.
Time: ~30–45 min. Cost: ₹0 (Always Free tier). You need a debit/credit card
for identity verification (it is NOT charged).

---

## STEP 1 — Create the Oracle Cloud account
1. Go to https://www.oracle.com/cloud/free/  → **Start for free**.
2. Sign up (email + phone + card verification). Pick your **Home Region** close
   to you (e.g. India South (Hyderabad) or Mumbai). ⚠️ You can't change region
   later, so choose well.
3. Wait for the account to be provisioned (a few minutes to ~30 min).

## STEP 2 — Create the free ARM VM (the powerful free one)
1. Console → hamburger menu → **Compute → Instances → Create instance**.
2. Name: `akeriyan`.
3. **Image and shape → Change shape → Ampere (ARM)** →
   `VM.Standard.A1.Flex`. Set **4 OCPUs** and **24 GB RAM** (all free-tier).
   - Image: **Canonical Ubuntu 22.04**.
   - (If it says "out of capacity", try again later or pick 1 OCPU / 6 GB.)
4. **Networking:** leave defaults (creates a VCN). Make sure
   "Assign a public IPv4 address" is **Yes**.
5. **SSH keys:** choose **Generate a key pair** and **download BOTH** the
   private and public keys. Keep the private key safe — you need it to log in.
6. Click **Create**. When it's running, copy the **Public IP address**.

## STEP 3 — Open port 8000 in Oracle's firewall (Security List)
1. Console → **Networking → Virtual Cloud Networks →** your VCN →
   **Security Lists →** Default Security List.
2. **Add Ingress Rule:**
   - Source CIDR: `0.0.0.0/0`
   - IP Protocol: **TCP**
   - Destination Port Range: `8000`
   - Save.

## STEP 4 — Copy the backend to the VM and deploy
On **your PC** (PowerShell), from the project root:

```powershell
# fix key permissions once (replace path with where you saved the key)
icacls "$HOME\Downloads\ssh-key.key" /inheritance:r /grant:r "$($env:USERNAME):(R)"

# copy the backend folder to the VM (replace <VM_IP>)
scp -i "$HOME\Downloads\ssh-key.key" -r `
  "C:\Users\anbar\Desktop\My_Projects\Akeriyan\akeriyan_backend" `
  ubuntu@<VM_IP>:~

# log in to the VM
ssh -i "$HOME\Downloads\ssh-key.key" ubuntu@<VM_IP>
```

Then **on the VM**:
```bash
cd ~/akeriyan_backend
bash deploy/setup_vm.sh
```
It installs everything, generates a **device token** (it prints it — SAVE IT),
and starts the backend as an always-on service. Note the printed URL:
`http://<VM_IP>:8000`.

## STEP 5 — Point the app at the VM
On your phone's AKERIYAN pairing screen:
- **Backend URL:** `http://<VM_IP>:8000`
- **Token:** the one the script printed (`cat ~/akeriyan_backend/.env` to see it)
- Tap **CONNECT** → should go green.

Now the assistant + trading terminal work from anywhere, even with your PC off. 🎉

---

## Useful commands (on the VM)
```bash
sudo systemctl status akeriyan     # is it running?
journalctl -u akeriyan -f          # live logs
sudo systemctl restart akeriyan    # restart after code changes
curl http://localhost:8000/v1/health
```

## Notes & security
- The LLM (llama3.2) runs slower on the free ARM VM than on your PC — Pro
  decisions may take longer. Everything else is snappy.
- Plain HTTP over the internet sends your token in clear text. For real
  security, add HTTPS later: a free **DuckDNS** subdomain + **Caddy** reverse
  proxy (auto Let's Encrypt), or a **Cloudflare Tunnel**. Ask AKERIYAN to set
  this up when you're ready.
- To update the code later: re-`scp` the folder and
  `sudo systemctl restart akeriyan`.
