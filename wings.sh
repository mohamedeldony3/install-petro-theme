#!/usr/bin/env bash
# Pterodactyl Wings one-shot installer (Ubuntu 22.04/24.04)
# Modified to ask user for values interactively
set -euo pipefail

#####################################
# ======== USER INPUT ===============
#####################################

read -p "Panel URL (مثال: https://panel.example.com): " PANEL_URL
read -p "Node FQDN (مثال: node.example.com): " NODE_FQDN
read -p "Admin Email: " ADMIN_EMAIL
read -p "Wings Token: " WINGS_TOKEN
read -p "Node ID: " NODE_ID

echo
echo "== القيم المدخلة =="
echo "Panel URL : $PANEL_URL"
echo "Node FQDN : $NODE_FQDN"
echo "Admin Email : $ADMIN_EMAIL"
echo "Node ID : $NODE_ID"
echo "Token : $WINGS_TOKEN"
echo

#####################################
# ========== PRECHECKS ==============
#####################################
if [[ $EUID -ne 0 ]]; then
  echo "[!] Please run as root (sudo)."
  exit 1
fi

echo "[+] Updating system and installing base deps..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release ufw jq apt-transport-https software-properties-common

#####################################
# ========== DOCKER CE ==============
#####################################
if dpkg -l | grep -E '^ii\s+docker\.io\b' >/dev/null 2>&1; then
  echo "[i] Removing distro docker.io to avoid conflicts..."
  apt-get remove -y docker docker.io containerd runc || true
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "[+] Installing Docker CE (stable)..."
  curl -fsSL https://get.docker.com | CHANNEL=stable bash
else
  echo "[i] Docker already installed: $(docker --version)"
fi

systemctl enable --now docker

mkdir -p /var/lib/docker/tmp
chmod 1777 /var/lib/docker/tmp

if ! docker network inspect pterodactyl_nw >/dev/null 2>&1; then
  echo "[+] Creating docker network: pterodactyl_nw"
  docker network create pterodactyl_nw
fi

#####################################
# ========== WINGS BINARY ===========
#####################################
echo "[+] Downloading Wings..."
mkdir -p /etc/pterodactyl
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) BINARCH="amd64" ;;
  aarch64|arm64) BINARCH="arm64" ;;
  *) echo "[!] Unsupported arch: $ARCH"; exit 1 ;;
esac

curl -L -o /usr/local/bin/wings \
  "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${BINARCH}"
chmod +x /usr/local/bin/wings

#####################################
# ========== SSL (LE) ===============
#####################################
NEEDS_NGINX_RESTART=0
if systemctl is-active --quiet nginx; then
  echo "[i] Stopping Nginx temporarily for cert issuance..."
  systemctl stop nginx
  NEEDS_NGINX_RESTART=1
fi

ufw allow 80/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true

if ! command -v certbot >/dev/null 2>&1; then
  echo "[+] Installing certbot..."
  apt-get install -y certbot
fi

echo "[+] Issuing/renewing Let's Encrypt certificate for ${NODE_FQDN}..."
if ! certbot certonly --standalone -d "${NODE_FQDN}" --non-interactive --agree-tos -m "${ADMIN_EMAIL}"; then
  echo "[!] Failed to issue certificate."
  [[ $NEEDS_NGINX_RESTART -eq 1 ]] && systemctl start nginx || true
  exit 1
fi

[[ $NEEDS_NGINX_RESTART -eq 1 ]] && systemctl start nginx || true

CERT_PATH="/etc/letsencrypt/live/${NODE_FQDN}/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/${NODE_FQDN}/privkey.pem"

#####################################
# ====== WINGS CONFIG FROM PANEL ====
#####################################
echo "[+] Pulling wings config from Panel (node ${NODE_ID})..."
cd /etc/pterodactyl
/usr/local/bin/wings configure \
  --panel-url "${PANEL_URL}" \
  --token "${WINGS_TOKEN}" \
  --node  "${NODE_ID}"

CONFIG="/etc/pterodactyl/config.yml"
if [[ ! -f "$CONFIG" ]]; then
  echo "[!] ${CONFIG} not found after configure. Check token/node id/panel URL."
  exit 1
fi

#####################################
# ======= PATCH CONFIG (SSL/FQDN) ===
#####################################
echo "[+] Patching SSL & host name in ${CONFIG}..."

if grep -qE '^[[:space:]]*ssl:[[:space:]]*false' "$CONFIG"; then
  sed -i 's/^\([[:space:]]*\)ssl:[[:space:]]*false/\1ssl: true/' "$CONFIG"
fi

awk '
BEGIN{inapi=0; hasssl=0}
(/^api:/){inapi=1; print; next}
(inapi && /^[^[:space:]]/){inapi=0}
(inapi && /ssl:/){hasssl=1}
{print}
END{
  if(!hasssl){
    print "  ssl: true"
  }
}
' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"

sed -i "s#^\([[:space:]]*\)\(certificate:\s*\).*#\1\2\"${CERT_PATH}\"#g" "$CONFIG" || true
sed -i "s#^\([[:space:]]*\)\(cert:\s*\).*#\1\2\"${CERT_PATH}\"#g" "$CONFIG" || true
sed -i "s#^\([[:space:]]*\)\(key:\s*\).*#\1\2\"${KEY_PATH}\"#g" "$CONFIG" || true
sed -i "s#^\([[:space:]]*\)\(key_path:\s*\).*#\1\2\"${KEY_PATH}\"#g" "$CONFIG" || true

if ! grep -qiE "host_name:\s*\"?${NODE_FQDN}\"?" "$CONFIG"; then
  awk -v fqdn="${NODE_FQDN}" '
    BEGIN{inapi=0; done=0}
    /^api:/ {inapi=1; print; next}
    (inapi && /^[^[:space:]]/){ if(!done){print "  host_name: \"" fqdn "\""; done=1} inapi=0 }
    {print}
    END{ if(inapi && !done){ print "  host_name: \"" fqdn "\""} }
  ' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
fi

#####################################
# ====== SYSTEMD SERVICE ============
#####################################
echo "[+] Creating systemd service for Wings..."
cat >/etc/systemd/system/wings.service <<'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wings

#####################################
# ====== FIREWALL (ufw) =============
#####################################
echo "[+] Opening required ports (8080, 2022)..."
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw allow 2022/tcp >/dev/null 2>&1 || true

if ufw status | grep -q "Status: inactive"; then
  echo "[i] UFW is inactive. Enable it yourself if needed: ufw enable"
fi

#####################################
# ====== FINAL SANITY STEPS =========
#####################################
echo "[+] Restarting Docker & Wings in order..."
systemctl restart docker
docker network inspect pterodactyl_nw >/dev/null 2>&1 || docker network create pterodactyl_nw
systemctl restart wings

echo
echo "=========================================="
echo "[✔] Wings installed & started successfully."
echo "Panel URL : ${PANEL_URL}"
echo "Node FQDN : ${NODE_FQDN}"
echo "SSL cert  : ${CERT_PATH}"
echo "SSL key   : ${KEY_PATH}"
echo "Service   : systemctl status wings"
echo "Logs      : journalctl -u wings -f"
echo "NOTE      : Add Allocations in Panel → Nodes → Allocations."
echo "=========================================="