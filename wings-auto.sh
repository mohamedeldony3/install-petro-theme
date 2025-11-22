#!/usr/bin/env bash
# Auto Wings Installer (No user input – receives values from bot)

set -euo pipefail

PANEL_URL="{{PANEL_URL}}"
NODE_FQDN="{{NODE_FQDN}}"
ADMIN_EMAIL="{{ADMIN_EMAIL}}"
WINGS_TOKEN="{{WINGS_TOKEN}}"
NODE_ID="{{NODE_ID}}"

if [[ $EUID -ne 0 ]]; then
  echo "[!] يجب تشغيل السكربت كـ root."
  exit 1
fi

echo "[+] بدء التثبيت..."
echo "Panel: $PANEL_URL"
echo "FQDN : $NODE_FQDN"
echo "Admin: $ADMIN_EMAIL"
echo "Node : $NODE_ID"

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release ufw jq apt-transport-https software-properties-common

echo "[+] Installing Docker..."
curl -fsSL https://get.docker.com | CHANNEL=stable bash
systemctl enable --now docker

mkdir -p /var/lib/docker/tmp
chmod 1777 /var/lib/docker/tmp

docker network create pterodactyl_nw >/dev/null 2>&1 || true

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

echo "[+] Issuing SSL for $NODE_FQDN..."
apt-get install -y certbot
ufw allow 80/tcp || true
ufw allow 443/tcp || true

certbot certonly --standalone -d "${NODE_FQDN}" --non-interactive --agree-tos -m "${ADMIN_EMAIL}" || true

CERT_PATH="/etc/letsencrypt/live/${NODE_FQDN}/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/${NODE_FQDN}/privkey.pem"

echo "[+] Fetching Wings config from panel..."
/usr/local/bin/wings configure \
  --panel-url "${PANEL_URL}" \
  --token "${WINGS_TOKEN}" \
  --node  "${NODE_ID}"

CONFIG="/etc/pterodactyl/config.yml"

echo "[+] Patching config..."
sed -i 's/ssl: false/ssl: true/g' "$CONFIG"
sed -i "s#certificate:.*#certificate: \"$CERT_PATH\"#g" "$CONFIG"
sed -i "s#key:.*/.*#key: \"$KEY_PATH\"#g" "$CONFIG"

cat >/etc/systemd/system/wings.service <<EOF
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

echo
echo "=========================================="
echo "[✔] Wings Installed Successfully!"
echo "Node: ${NODE_FQDN}"
echo "Config: /etc/pterodactyl/config.yml"
echo "Service: systemctl status wings"
echo "=========================================="