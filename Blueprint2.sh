#!/bin/bash

step(){ echo "[STEP] $1"; }
error(){ echo "[ERROR] $1"; exit 1; }

export DEBIAN_FRONTEND=noninteractive
export GPG_TTY=/dev/null

step "START_BLUEPRINT_INSTALL"

# ROOT CHECK
step "CHECK_ROOT"
[[ $EUID -ne 0 ]] && error "Run this script as root"

# DEPENDENCIES
step "INSTALL_DEPENDENCIES"
apt update -y || error "apt update failed"
apt install -y ca-certificates curl gnupg unzip git wget software-properties-common lsb-release || error "dependencies failed"

# FIX NODEJS (Official Ubuntu Repo)
step "INSTALL_NODEJS"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || error "nodesource setup failed"
apt install -y nodejs || error "nodejs failed"

# YARN
step "INSTALL_YARN"
npm install -g yarn || error "yarn failed"

# PANEL PATH
step "CHECK_PANEL_PATH"
[[ ! -d /var/www/pterodactyl ]] && error "pterodactyl panel not found"
cd /var/www/pterodactyl || error "cannot cd panel"

# INSTALL PANEL DEPENDENCIES
step "INSTALL_PANEL_DEPENDENCIES"
yarn install || error "yarn install failed"

# DOWNLOAD BLUEPRINT NOBITA
step "DOWNLOAD_NOBITA"
URL=$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest \
 | grep browser_download_url | grep ".zip" | head -1 | cut -d '"' -f 4)

[[ -z "$URL" ]] && error "failed to fetch release"
wget "$URL" -O release.zip || error "download failed"
unzip -o release.zip || error "extract failed"

# BLUEPRINT INSTALLER
step "RUN_BLUEPRINT_INSTALLER"
chmod +x blueprint.sh || error "chmod failed"
bash blueprint.sh || error "blueprint install failed"

step "BLUEPRINT_DONE"