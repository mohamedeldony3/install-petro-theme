#!/bin/bash

step(){
    echo
    echo "=============================="
    echo "[STEP] $1"
    echo "=============================="
}

fail(){
    echo
    echo "[ERROR] $1"
    echo
    exit 1
}

step "START_NEBULA"

TARGET_DIR="/var/www/pterodactyl"
TEMP="/tmp/nebo-repo"

# ROOT CHECK
step "CHECK_ROOT"
[[ $EUID -ne 0 ]] && fail "Run as root"

# CHECK PANEL PATH
step "CHECK_PANEL_PATH"
[[ ! -d "$TARGET_DIR" ]] && fail "panel not found"

# CLEAN TEMP
step "CLEAN_TEMP"
rm -rf "$TEMP"

# GIT CLONE REPO
step "CLONE_NEBULA_REPO"
git clone https://github.com/mohamedeldony3/nebo.git "$TEMP" || fail "clone failed"

# CHECK FILE
step "CHECK_BLUEPRINT_FILE"
[[ ! -f "$TEMP/nebula.blueprint" ]] && fail "nebula.blueprint missing"

# MOVE BLUEPRINT
step "MOVE_BLUEPRINT"
mv "$TEMP/nebula.blueprint" "$TARGET_DIR/" || fail "move failed"

rm -rf "$TEMP"

cd "$TARGET_DIR" || fail "Failed to enter panel directory"

# RUN NEBULA BLUEPRINT
step "RUN_NEBULA_BLUEPRINT"
echo "[INFO] Running blueprint with auto-enter..."

# FULL LOG MODE + AUTO ENTER
# يعرض كل التنفيذ… كل خطوة… كل خط… كل خطأ
printf "\n\n\n" | blueprint -i nebula.blueprint 2>&1 | tee nebula-full.log

STATUS=${PIPESTATUS[0]}

# CHECK STATUS
if [[ $STATUS -ne 0 ]]; then
    echo
    echo "❌ INSTALL FAILED"
    echo "------------ LAST 40 LINES ------------"
    tail -n 40 nebula-full.log
    fail "Nebula install failed"
fi

step "NEBULA_DONE"
echo "✨ Nebula installed successfully!"
echo "📄 Log saved: $TARGET_DIR/nebula-full.log"