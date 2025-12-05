#!/bin/bash

# ==========================================================
#  FULL AUTO INSTALLER → Blueprint + Nebula
#  By: Melsony (محمد المغوري)
# ==========================================================

set -e

# Colors
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
RED="\033[0;31m"
NC="\033[0m"

log() { echo -e "${CYAN}➡ $1${NC}"; }
ok()  { echo -e "${GREEN}✔ $1${NC}"; }
err() { echo -e "${RED}✖ $1${NC}"; }

clear
echo -e "${CYAN}==============================================="
echo -e "     🔵 Auto Installer → Blueprint + Nebula"
echo -e "===============================================${NC}"
sleep 1

# ============================
# URLs
# ============================
BLUEPRINT_URL="https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/Blueprint2.sh"
NEBULA_URL="https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/th2.sh"

# Temp folder
WORKDIR="/root/auto_install_$(date +%s)"
mkdir -p "$WORKDIR"

log "💾 تحميل سكربت Blueprint…"
curl -fsSL "$BLUEPRINT_URL" -o "$WORKDIR/blueprint.sh"
chmod +x "$WORKDIR/blueprint.sh"
ok "تم تحميل Blueprint"

log "🚀 بدء تثبيت Blueprint (اختيار رقم 1 تلقائيًا)…"
bash "$WORKDIR/blueprint.sh" << 'EOF'
1
EOF
ok "تم تثبيت Blueprint بنجاح"

log "💾 تحميل سكربت Nebula…"
curl -fsSL "$NEBULA_URL" -o "$WORKDIR/nebula.sh"
chmod +x "$WORKDIR/nebula.sh"
ok "تم تحميل Nebula"

log "🚀 بدء تثبيت Nebula…"
bash "$WORKDIR/nebula.sh"
ok "تم تثبيت Nebula بنجاح"

log "🧹 حذف ملفات التثبيت المؤقتة…"
rm -rf "$WORKDIR"

echo ""
echo -e "${GREEN}🎉 تم الانتهاء من تثبيت Blueprint + Nebula بالكامل!${NC}"
echo -e "${CYAN}✔ التثبيت أوتوماتيكي بدون تدخل${NC}"
echo -e "${CYAN}✔ السيرفر جاهز للعمل${NC}"
echo ""
exit 0
