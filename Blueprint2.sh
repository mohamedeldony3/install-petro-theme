#!/bin/bash

step(){ echo "[STEP] $1"; }
fail(){ echo "[ERROR] $1"; exit 1; }

clear
step "START_BLUEPRINT_INSTALL"

# ROOT CHECK
step "CHECK_ROOT"
[[ $EUID -ne 0 ]] && fail "Run as root"

# DEPENDENCIES
step "INSTALL_DEPENDENCIES"
apt-get update -y >/dev/null 2>&1
apt-get install -y ca-certificates curl gnupg unzip git wget >/dev/null 2>&1 || fail "dependencies failed"

# NODE 20
step "INSTALL_NODEJS"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
 | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
 > /etc/apt/sources.list.d/nodesource.list

apt-get update -y >/dev/null 2>&1
apt-get install -y nodejs >/dev/null 2>&1 || fail "nodejs failed"

# YARN
step "INSTALL_YARN"
npm install -g yarn >/dev/null 2>&1 || fail "yarn failed"

# PANEL PATH
step "CHECK_PANEL_PATH"
[[ ! -d /var/www/pterodactyl ]] && fail "panel not found"
cd /var/www/pterodactyl

# YARN INSTALL
step "INSTALL_PANEL_DEPENDENCIES"
yarn >/dev/null 2>&1 || fail "yarn install failed"

# DOWNLOAD NOBITA
step "DOWNLOAD_NOBITA"
URL=$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest \
 | grep browser_download_url | head -1 | cut -d '"' -f 4)

wget "$URL" -O release.zip >/dev/null 2>&1 || fail "download failed"
unzip -o release.zip >/dev/null 2>&1 || fail "extract failed"

# RUN BLUEPRINT INSTALLER
step "RUN_BLUEPRINT_INSTALLER"
chmod +x blueprint.sh
bash blueprint.sh >/dev/null 2>&1 || fail "blueprint install failed"

step "BLUEPRINT_DONE"