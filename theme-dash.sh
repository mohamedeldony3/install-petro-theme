#!/bin/bash
# ============================================================
#         🦅 Melsony | Phoenix Theme Installer (Auto-Fix)
# ============================================================

set -e

# ------------- 🌈 Colors -------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------- 🖼️ Header -------------
echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════╗"
echo "║         🦅  Phoenix Theme Installer           ║"
echo "║             by ${YELLOW}Melsony${CYAN}                    ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ------------- 📦 Requirements -------------
echo -e "${BLUE}🔍 Checking and installing required packages...${NC}"

REQUIRED_PKGS=("curl" "unzip" "php" "file")

# Detect package manager
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt-get"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
elif command -v microdnf &> /dev/null; then
    PKG_MANAGER="microdnf"
else
    echo -e "${RED}❌ No supported package manager found (apt, yum, dnf, microdnf).${NC}"
    exit 1
fi

# Update repos
echo -e "${BLUE}🔄 Updating package repositories...${NC}"
if [ "$PKG_MANAGER" = "apt-get" ]; then
    apt-get update -y >/dev/null 2>&1 || true
elif [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ] || [ "$PKG_MANAGER" = "microdnf" ]; then
    $PKG_MANAGER makecache -y >/dev/null 2>&1 || true
fi

# Install missing packages
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! command -v $pkg &> /dev/null; then
        echo -e "${YELLOW}📦 Installing: $pkg${NC}"
        $PKG_MANAGER install -y $pkg >/dev/null 2>&1 || {
            echo -e "${RED}❌ Failed to install $pkg. Please install it manually using:${NC}"
            echo -e "${YELLOW}   sudo $PKG_MANAGER install -y $pkg${NC}"
            exit 100
        }
    fi
done

# ------------- 📁 Paths & URL -------------
INSTALL_PATH="/var/www/ctrlpanel"
ZIP_FILE="$INSTALL_PATH/dash-theme.zip"
ZIP_URL="https://raw.githubusercontent.com/mohamedeldony3/mohamedeldony3/main/dash-theme.zip"
mkdir -p "$INSTALL_PATH"

# ------------- ⬇️ Download -------------
echo -e "${BLUE}⬇️  Downloading Phoenix theme...${NC}"
curl -sSL -o "$ZIP_FILE" "$ZIP_URL"

# ------------- ✅ Validate -------------
echo -e "${BLUE}🔍 Validating ZIP file...${NC}"
if command -v file &> /dev/null && file "$ZIP_FILE" | grep -q "Zip archive data"; then
    echo -e "${GREEN}✅ ZIP file is valid.${NC}"
else
    echo -e "${RED}❌ Invalid or unreadable ZIP file. Aborting.${NC}"
    exit 1
fi

# ------------- 🗂️ Extract -------------
echo -e "${BLUE}📦 Extracting theme to ${YELLOW}$INSTALL_PATH${NC}..."
unzip -o "$ZIP_FILE" -d "$INSTALL_PATH" >/dev/null

# ------------- 🔧 Permissions -------------
echo -e "${BLUE}🔧 Setting file permissions...${NC}"
chown -R www-data:www-data "$INSTALL_PATH" 2>/dev/null || true
chmod -R 755 "$INSTALL_PATH/storage/"* "$INSTALL_PATH/bootstrap/cache/" 2>/dev/null || true

# ------------- ⚙️ Migrations -------------
echo -e "${BLUE}⚙️  Running Laravel migrations...${NC}"
cd "$INSTALL_PATH" || exit 1
php artisan migrate --force || echo -e "${YELLOW}⚠️ Migration skipped (Laravel not found).${NC}"

# ------------- 🧹 Clear Cache -------------
echo -e "${BLUE}🧹 Clearing Laravel cache...${NC}"
php artisan optimize:clear || echo -e "${YELLOW}⚠️ Cache clear skipped (Laravel not found).${NC}"

# ------------- 🧼 Cleanup -------------
echo -e "${BLUE}🧼 Cleaning up...${NC}"
rm -f "$ZIP_FILE"

# ------------- ✅ Done -------------
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════╗"
echo "║       🎉 Phoenix Theme Installed Successfully  ║"
echo "║          Change theme in admin panel          ║"
echo "║          Theme name: ${YELLOW}Phoenix${GREEN}                 ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"