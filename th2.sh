#!/bin/bash

step(){ echo "[STEP] $1"; }
fail(){ echo "[ERROR] $1"; exit 1; }

step "START_NEBULA"

TARGET_DIR="/var/www/pterodactyl"
TEMP="/tmp/nebo-repo"

# ROOT CHECK
step "CHECK_ROOT"
[[ $EUID -ne 0 ]] && fail "Run as root"

# CHECK PANEL
step "CHECK_PANEL_PATH"
[[ ! -d $TARGET_DIR ]] && fail "panel not found"

# CLEAN TEMP
step "CLEAN_TEMP"
rm -rf $TEMP >/dev/null 2>&1

# GIT CLONE
step "CLONE_NEBULA_REPO"
git clone https://github.com/mohamedeldony3/nebo.git $TEMP >/dev/null 2>&1 || fail "clone failed"

# CHECK FILE
step "CHECK_BLUEPRINT_FILE"
[[ ! -f "$TEMP/nebula.blueprint" ]] && fail "nebula.blueprint missing"

# MOVE BLUEPRINT
step "MOVE_BLUEPRINT"
mv "$TEMP/nebula.blueprint" "$TARGET_DIR/" >/dev/null 2>&1 || fail "move failed"

# CLEAN TEMP
step "REMOVE_TEMP"
rm -rf $TEMP >/dev/null 2>&1

# RUN BLUEPRINT
step "RUN_NEBULA_BLUEPRINT"
cd $TARGET_DIR
command -v blueprint >/dev/null 2>&1 || fail "blueprint CLI missing"
blueprint -i nebula.blueprint >/dev/null 2>&1 || fail "nebula install failed"

step "NEBULA_DONE"