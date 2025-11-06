#!/bin/bash
# ============================================================
#         🦅 Melsony | Phoenix Theme Installer (Public)
# ============================================================

set -e

# ------------- 🌈 Colors -------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ------------- 🖼️ Header -------------
echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════╗"
echo "║         🦅  Phoenix Theme Installer           ║"
echo "║             by ${YELLOW}Melsony${CYAN}                    ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ------------- 📦 Requirements -------------
echo -e "${BLUE}🔍 Checking required packages...${NC}"
for pkg in curl unzip php; do
    if ! command -v $pkg &> /dev/null; then
        echo -e "${YELLOW}📦 Installing: $pkg${NC}"
        apt-get install -y $pkg >/dev/null 2>&1 || yum install -y $pkg >/dev/null 2>&1
    fi
done

# ------------- 📁 Paths & URL -------------
INSTALL_PATH="/var/www/ctrlpanel"
ZIP_FILE="$INSTALL_PATH/dash-theme.zip"
ZIP_URL="https://raw.githubusercontent.com/mohamedeldony3/mohamedeldony3/main/dash-theme.zip"

# ------------- ⬇️ Download -------------
echo -e "${BLUE}⬇️  Downloading Phoenix theme...${NC}"
curl -sSL -o "$ZIP_FILE" "$ZIP_URL"

# ------------- ✅ Validate -------------
echo -e "${BLUE}🔍 Validating ZIP file...${NC}"
if file "$ZIP_FILE" | grep -q "Zip archive data"; then
    echo -e "${GREEN}✅ ZIP file is valid.${NC}"
else
    echo -e "${RED}❌ Invalid ZIP file. Aborting.${NC}"
    exit 1
fi

# ------------- 🗂️ Extract -------------
echo -e "${BLUE}📦 Extracting theme to ${YELLOW}$INSTALL_PATH${NC}..."
unzip -o "$ZIP_FILE" -d "$INSTALL_PATH" >/dev/null

# ------------- 🔧 Permissions -------------
echo -e "${BLUE}🔧 Setting file permissions...${NC}"
chown -R www-data:www-data "$INSTALL_PATH"
chmod -R 755 "$INSTALL_PATH/storage/"* "$INSTALL_PATH/bootstrap/cache/"

# ------------- ⚙️ Migrations -------------
echo -e "${BLUE}⚙️  Running Laravel migrations...${NC}"
cd "$INSTALL_PATH"
php artisan migrate --force

# ------------- 🧹 Clear Cache -------------
echo -e "${BLUE}🧹 Clearing Laravel cache...${NC}"
php artisan optimize:clear

# ------------- 🧼 Cleanup -------------
echo -e "${BLUE}🧼 Cleaning up...${NC}"
rm -f "$ZIP_FILE"

# ------------- ✅ Done -------------
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════╗"
echo "║       🎉 Phoenix Theme Installed             ║"
echo "║          Change theme in admin panel         ║"
echo "║          Theme name: ${YELLOW}Phoenix${GREEN}                   ║"
echo "╚═══════════════════════════════════════════════╝"
echo -e "${NC}"