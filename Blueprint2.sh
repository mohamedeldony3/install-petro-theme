#!/bin/bash

# ================================
#   Nobita Hosting Fresh Installer
#   Auto Mode — No Menu / No Input
# ================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

step() { 
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}STEP: $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

ok()   { echo -e "${GREEN}✔ $1${NC}"; }
fail() { echo -e "${RED}✘ $1${NC}"; exit 1; }

log()  { echo -e "${YELLOW}⏳ $1...${NC}"; }

# ================================
# شروع التثبيت
# ================================
clear
echo -e "${CYAN}🚀 Starting Automatic Nobita Hosting Installation...${NC}"

# ================================
# STEP 1 — تحقق من الصلاحيات
# ================================
step "Checking root"
if [ "$EUID" -ne 0 ]; then
    fail "You must run this script as root."
else
    ok "Running as root"
fi

# ================================
# STEP 2 — تثبيت المتطلبات
# ================================
step "Installing Dependencies"

log "Installing base packages"
apt-get install -y ca-certificates curl gnupg unzip git wget > /dev/null 2>&1 || fail "Failed installing dependencies"
ok "Base packages installed"

# ================================
# STEP 3 — تثبيت Node.js 20
# ================================
step "Installing Node.js 20.x"

log "Adding Node.js repo"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg || fail "Failed adding Node repo"

echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
> /etc/apt/sources.list.d/nodesource.list
ok "Node.js repo added"

log "Updating system"
apt-get update > /dev/null 2>&1
ok "System updated"

log "Installing Node.js"
apt-get install -y nodejs > /dev/null 2>&1 || fail "Failed installing Node.js"
ok "Node.js installed"

# ================================
# STEP 4 — تثبيت Yarn
# ================================
step "Installing Yarn"

log "Installing yarn globally"
npm i -g yarn > /dev/null 2>&1 || fail "Yarn install failed"
ok "Yarn installed"

# ================================
# STEP 5 — تجهيز مسار لوحة Pterodactyl
# ================================
step "Preparing Pterodactyl Directory"

if [ ! -d "/var/www/pterodactyl" ]; then
    fail "/var/www/pterodactyl NOT FOUND! Install panel first."
else
    ok "Panel directory detected"
fi

cd /var/www/pterodactyl || fail "Cannot enter panel directory"

# ================================
# STEP 6 — تثبيت Dependencies
# ================================
step "Installing panel dependencies (Yarn)"

log "Running yarn"
yarn > /dev/null 2>&1 || fail "Yarn failed installing dependencies"
ok "Panel dependencies installed"

# ================================
# STEP 7 — تحميل أحدث إصدار Nobita Hosting
# ================================
step "Downloading Nobita Hosting"

LATEST_URL=$(curl -s https://api.github.com/repos/BlueprintFramework/framework/releases/latest | grep 'browser_download_url' | head -1 | cut -d '"' -f 4)

if [ -z "$LATEST_URL" ]; then
    fail "Could not fetch latest release"
fi

log "Downloading release"
wget "$LATEST_URL" -O release.zip > /dev/null 2>&1 || fail "Download failed"
ok "Download complete"

log "Extracting release"
unzip -o release.zip > /dev/null 2>&1 || fail "Extraction failed"
ok "Files extracted"

# ================================
# STEP 8 — تشغيل Blueprint Installer
# ================================
step "Running Blueprint Installer"

if [ ! -f "blueprint.sh" ]; then
    fail "blueprint.sh NOT FOUND in release!"
fi

log "Making blueprint executable"
chmod +x blueprint.sh
ok "Executable set"

log "Executing blueprint installer"
bash blueprint.sh || fail "Blueprint installation failed"
ok "Blueprint installation completed"

# ================================
# STEP 9 — انتهاء التثبيت
# ================================
step "Installation Complete"

ok "Nobita Hosting Installed Successfully 🎉"
echo -e "${CYAN}You may now restart your panel if required.${NC}"