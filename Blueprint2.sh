#!/bin/bash

step(){ echo "[STEP] $1"; }
fail(){
    echo "[ERROR] $1"
    echo "========== LAST 40 LINES =========="
    tail -n 40 blueprint_debug.log 2>/dev/null
    exit 1
}

step "START_BLUEPRINT_INSTALL"

# ROOT CHECK
step "CHECK_ROOT"
[[ $EUID -ne 0 ]] && fail "Run as root"

# DEPENDENCIES
step "INSTALL_DEPENDENCIES"
apt-get update -y 
apt-get install -y ca-certificates curl gnupg unzip git wget || fail "dependencies failed"

# NODE 20
step "INSTALL_NODEJS"
mkdir -p /etc/apt/keyrings

curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
 | gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg || fail "node gpg failed"

echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
 > /etc/apt/sources.list.d/nodesource.list

apt-get update -y
apt-get install -y nodejs || fail "nodejs failed"

# YARN
step "INSTALL_YARN"
npm install -g yarn || fail "yarn failed"

# PANEL PATH
step "CHECK_PANEL_PATH"
[[ ! -d /var/www/pterodactyl ]] && fail "panel not found"
cd /var/www/pterodactyl

chmod -R 775 /var/www/pterodactyl || true

# YARN INSTALL
step "INSTALL_PANEL_DEPENDENCIES"
yarn --network-timeout 600000 || fail "yarn install failed"

# DOWNLOAD NOBITA
step "DOWNLOAD_NOBITA"
URL=$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest \
 | grep browser_download_url | head -1 | cut -d '"' -f 4)

wget "$URL" -O release.zip || fail "download failed"
unzip -o release.zip || fail "extract failed"

# RUN BLUEPRINT INSTALLER
step "RUN_BLUEPRINT_INSTALLER"
chmod +x blueprint.sh

# نُسجل كل مخرجات البلوبرنت
bash -x blueprint.sh --no-tty 2>&1 | tee blueprint_debug.log
status=${PIPESTATUS[0]}

[[ $status -ne 0 ]] && fail "blueprint install failed"

step "BLUEPRINT_DONE"