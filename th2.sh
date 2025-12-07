#!/bin/bash

step(){ echo "[STEP] $1"; }
error(){ echo "[ERROR] $1"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

step "START_NEBULA"

TARGET="/var/www/pterodactyl"
TEMP="/tmp/nebula_repo"

# Root check
step "CHECK_ROOT"
[[ $EUID -ne 0 ]] && error "run as root"

# Check panel directory
step "CHECK_PANEL_PATH"
[[ ! -d $TARGET ]] && error "panel path missing"

# Clean temp dir
step "CLEAN_TEMP"
rm -rf $TEMP

# Clone repo
step "CLONE_REPO"
git clone https://github.com/mohamedeldony3/nebo.git "$TEMP" || error "clone failed"

# Check blueprint file
step "CHECK_BLUEPRINT_FILE"
[[ ! -f "$TEMP/nebula.blueprint" ]] && error "nebula.blueprint missing"

# Move file
step "MOVE_FILE"
mv "$TEMP/nebula.blueprint" "$TARGET/" || error "move failed"

# Clean temp
step "REMOVE_TEMP"
rm -rf "$TEMP"

# Run Nebula through blueprint
step "RUN_NEBULA"
cd "$TARGET" || error "cd failed"
command -v blueprint >/dev/null || error "blueprint CLI not installed"
blueprint -i nebula.blueprint || error "nebula install failed"

step "NEBULA_DONE"