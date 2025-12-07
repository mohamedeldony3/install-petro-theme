#!/usr/bin/env bash
set -euo pipefail

log(){ echo -e "\033[1;32m[+] $*\033[0m"; }
err(){ echo -e "\033[1;31m[✗] $*\033[0m"; }
trap 'err "حدث خطأ غير متوقع أثناء التثبيت!"' ERR

PANEL_URL="{{PANEL_URL}}"
NODE_FQDN="{{NODE_FQDN}}"
ADMIN_EMAIL="{{ADMIN_EMAIL}}"
WINGS_TOKEN="{{WINGS_TOKEN}}"
NODE_ID="{{NODE_ID}}"

echo "[+] بدء التثبيت..."
echo "Panel: $PANEL_URL"
echo "FQDN : $NODE_FQDN"
echo "Admin: $ADMIN_EMAIL"
echo "Node : $NODE_ID"

export DEBIAN_FRONTEND=noninteractive

# ===============================
# STEP 1 — UPDATE SYSTEM
# ===============================
log "Updating server packages..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release jq ufw apt-transport-https software-properties-common

# ===============================
# STEP 2 — INSTALL DOCKER
# ===============================
log "Installing Docker..."

curl -fsSL https://get.docker.com -o /tmp/docker.sh
chmod +x /tmp/docker.sh
bash /tmp/docker.sh || {
    err "فشل تثبيت Docker — سيتم المحاولة مرة أخرى"
    apt-get remove docker docker.io containerd runc -y || true
    bash /tmp/docker.sh
}

command -v docker >/dev/null 2>&1 || {
    err "Docker غير موجود بعد التثبيت!"
    exit 1
}

systemctl enable --now docker
mkdir -p /var/lib/docker/tmp
chmod 1777 /var/lib/docker/tmp

# ===============================
# STEP 3 — CLEAN OLD N8N DOCKER
# ===============================
docker rm -f n8n-compose-file-traefik-1 n8n-compose-file-n8n-1 2>/dev/null || true
docker rmi -f n8nio/n8n traefik 2>/dev/null || true
docker network rm n8n-compose-file_default 2>/dev/null || true

# ===============================
# STEP 4 — INSTALL WINGS BINARY
# ===============================
log "Downloading Wings binary..."

mkdir -p /etc/pterodactyl

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) BINARCH="amd64" ;;
  aarch64|arm64) BINARCH="arm64" ;;
  *) err "Architecture not supported: $ARCH" ;;
esac

curl -L -o /usr/local/bin/wings \
  "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_${BINARCH}"

chmod +x /usr/local/bin/wings

# ===============================
# STEP 5 — FIREWALL + SSL
# ===============================
log "Configuring Firewall & SSL..."

ufw allow 80/tcp || true
ufw allow 443/tcp || true
ufw allow 8080/tcp || true
ufw allow 22/tcp || true
ufw allow 2022/tcp || true
ufw --force enable || true

apt-get install -y certbot
sudo systemctl stop nginx
certbot certonly --standalone \
  -d "${NODE_FQDN}" \
  -m "${ADMIN_EMAIL}" \
  --agree-tos --non-interactive || true
sudo systemctl start nginx
CERT_PATH="/etc/letsencrypt/live/${NODE_FQDN}/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/${NODE_FQDN}/privkey.pem"

# ===============================
# STEP 6 — FETCH WINGS CONFIG
# ===============================
log "Fetching Wings config from panel..."

wings configure \
  --panel-url "${PANEL_URL}" \
  --token "${WINGS_TOKEN}" \
  --node "${NODE_ID}"

CONFIG="/etc/pterodactyl/config.yml"

# ===============================
# STEP 7 — ENABLE SSL IN CONFIG
# ===============================
log "Enabling SSL inside config..."

sed -i 's/ssl: false/ssl: true/g' "$CONFIG"
sed -i "s#certificate:.*#certificate: \"$CERT_PATH\"#g" "$CONFIG"
sed -i "s#key:.*#key: \"$KEY_PATH\"#g" "$CONFIG"

# ===============================
# STEP 8 — SYSTEMD SERVICE
# ===============================
log "Creating systemd service..."

cat >/etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=on-failure
LimitNOFILE=4096
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now wings

echo ""
echo "==============================================="
echo "[✔] Wings Installed Successfully!"
echo "Node FQDN : ${NODE_FQDN}"
echo "Service   : systemctl status wings"
echo "Config    : /etc/pterodactyl/config.yml"
echo "==============================================="