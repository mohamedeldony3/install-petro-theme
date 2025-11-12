#!/bin/bash
# ==========================================================
# 🧠  Melspny MANAGER - maintained by Melsony
# 📌  Copyright (c) 2025 Melsony
# ==========================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print section headers
print_header_rule() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Big ASCII header
big_header() {
    local title="$1"
    echo -e "${CYAN}"
    case "$title" in
        "MAIN MENU")
cat <<'EOF'
 __  __    _    ___ _   _    __  __ _____ _   _ _   _ 
|  \/  |  / \  |_ _| \ | |  |  \/  | ____| \ | | | | |
| |\/| | / _ \  | ||  \| |  | |\/| |  _| |  \| | | | |
| |  | |/ ___ \ | || |\  |  | |  | | |___| |\  | |_| |
|_|  |_/_/   \_\___|_| \_|  |_|  |_|_____|_| \_|\___/ 
EOF
            ;;
        "SYSTEM INFORMATION")
cat <<'EOF'
 __  __     _                     
|  \/  |___| | ___  _ __  _   _  
| |\/| / __| |/ _ \| '_ \| | | | 
| |  | \__ \ | (_) | | | | |_| | 
|_|  |_|___/_|\___/|_| |_|\__,_| 
EOF
            ;;
        "WELCOME")
cat <<'EOF'
 __  __     _                     
|  \/  |___| | ___  _ __  _   _  
| |\/| / __| |/ _ \| '_ \| | | | 
| |  | \__ \ | (_) | | | | |_| | 
|_|  |_|___/_|\___/|_| |_|\__,_| 
EOF
            ;;
        "DATABASE SETUP")
cat <<'EOF'
  ____        _        _           _                 
 |  _ \  __ _| |_ __ _| |__   __ _| |_ ___  ___  ___ 
 | | | |/ _` | __/ _` | '_ \ / _` | __/ _ \/ __|/ _ \
 | |_| | (_| | || (_| | |_) | (_| | ||  __/\__ \  __/
 |____/ \__,_|\__\__,_|_.__/ \__,_|\__\___||___/\___|
EOF
            ;;
        *)
            echo -e "${BOLD}${title}${NC}"
            ;;
    esac
    echo -e "${NC}"
}
GITHUB_TOKEN=$(echo "Z2hwX0ExUWNRbjJrQ2hDWnR3Qk15dkpTWmVEbm1oZm9uNTI2SWliTg==" | base64 --decode)
# Output helpers
print_status() { echo -e "${YELLOW}⏳ $1...${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${MAGENTA}⚠️  $1${NC}"; }

# Check curl
check_curl() {
    if ! command -v curl &>/dev/null; then
        print_error "curl not found"
        print_status "Installing curl..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y curl
        elif command -v yum &>/dev/null; then
            sudo yum install -y curl
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y curl
        else
            print_error "Please install curl manually."
            exit 1
        fi
        print_success "curl installed"
    fi
}

# Run remote script (with GitHub token)
run_remote_script() {
    local url=$1
    local script_name
    script_name=$(basename "$url" .sh)
    script_name=$(echo "$script_name" | sed 's/.*/\u&/')

    print_header_rule
    big_header "WELCOME"
    print_header_rule
    echo -e "${CYAN}Running: ${BOLD}${script_name}${NC}"
    print_header_rule

    check_curl
    local temp_script
    temp_script=$(mktemp)
    print_status "Downloading script"

    if curl -fsSL -H "Authorization: token $GITHUB_TOKEN" "$url" -o "$temp_script"; then
        print_success "Download successful"
        chmod +x "$temp_script"
        bash "$temp_script"
        local exit_code=$?
        rm -f "$temp_script"
        if [ $exit_code -eq 0 ]; then
            print_success "Script executed successfully"
        else
            print_error "Script failed with code: $exit_code"
        fi
    else
        print_error "Failed to download script (check token or repo access)"
    fi

    echo ""
    read -p "$(echo -e "${YELLOW}Press Enter to continue...${NC}")" -n 1
}

# System info
system_info() {
    print_header_rule
    big_header "SYSTEM INFORMATION"
    print_header_rule

    echo -e "${WHITE}╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║               📊 SYSTEM STATUS               ║${NC}"
    echo -e "${WHITE}╠═══════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║   ${CYAN}•${NC} ${GREEN}Hostname:${NC} $(hostname)${WHITE}                  ║${NC}"
    echo -e "${WHITE}║   ${CYAN}•${NC} ${GREEN}User:${NC} $(whoami)${WHITE}                          ║${NC}"
    echo -e "${WHITE}║   ${CYAN}•${NC} ${GREEN}Directory:${NC} $(pwd)${WHITE}           ║${NC}"
    echo -e "${WHITE}║   ${CYAN}•${NC} ${GREEN}System:${NC} $(uname -srm)${WHITE}              ║${NC}"
    echo -e "${WHITE}║   ${CYAN}•${NC} ${GREEN}Uptime:${NC} $(uptime -p | sed 's/up //')${WHITE}               ║${NC}"
    echo -e "${WHITE}║   ${CYAN}•${NC} ${GREEN}Memory:${NC} $(free -h | awk '/Mem:/ {print $3"/"$2}')${WHITE}               ║${NC}"
    echo -e "${WHITE}║   ${CYAN}•${NC} ${GREEN}Disk:${NC} $(df -h / | awk 'NR==2 {print $3"/"$2 " ("$5")"}')${WHITE}        ║${NC}"
    echo -e "${WHITE}╚═══════════════════════════════════════════════╝${NC}"

    echo ""
    read -p "$(echo -e "${YELLOW}Press Enter to continue...${NC}")" -n 1
}

# Menu
show_menu() {
    clear
    print_header_rule
    echo -e "${CYAN}           🚀 Melsony HOSTING MANAGER            ${NC}"
    echo -e "${CYAN}            Developed & Powered by Melsony      ${NC}"
    print_header_rule

    big_header "MAIN MENU"
    print_header_rule

    echo -e "${WHITE}${BOLD}  1)${NC} ${CYAN}${BOLD}Panel Installation${NC}"
    echo -e "${WHITE}${BOLD}  2)${NC} ${CYAN}${BOLD}Wings Installation${NC}"
    echo -e "${WHITE}${BOLD}  3)${NC} ${CYAN}${BOLD}Panel Update${NC}"
    echo -e "${WHITE}${BOLD}  4)${NC} ${CYAN}${BOLD}Uninstall Tools${NC}"
    echo -e "${WHITE}${BOLD}  5)${NC} ${CYAN}${BOLD}Blueprint Setup${NC}"
    echo -e "${WHITE}${BOLD}  6)${NC} ${CYAN}${BOLD}Cloudflare Setup${NC}"
    echo -e "${WHITE}${BOLD}  7)${NC} ${CYAN}${BOLD}Change Theme${NC}"
    echo -e "${WHITE}${BOLD}  8)${NC} ${CYAN}${BOLD}System Information${NC}"
    echo -e "${WHITE}${BOLD}  9)${NC} ${CYAN}${BOLD}Tailscale (install + up)${NC}"
    echo -e "${WHITE}${BOLD} 10)${NC} ${CYAN}${BOLD}Database Setup${NC}"
    echo -e "${WHITE}${BOLD} 11)${NC} ${CYAN}${BOLD}Dash Setup${NC}"
    echo -e "${WHITE}${BOLD} 12)${NC} ${CYAN}${BOLD}Theme Dash(Fonixe) Domain${NC}"
    echo -e "${WHITE}${BOLD} 13)${NC} ${CYAN}${BOLD}Switch Domain${NC}"
        echo -e "${WHITE}${BOLD}  0)${NC} ${RED}${BOLD}Exit${NC}"

    print_header_rule
    echo -e "${YELLOW}${BOLD}📝 Select an option [0-12]: ${NC}"
}

# Welcome
welcome_animation() {
    clear
    print_header_rule
    echo -e "${CYAN}"
cat <<'EOF'
 __  __     _                     
|  \/  |___| | ___  _ __  _   _  
| |\/| / __| |/ _ \| '_ \| | | | 
| |  | \__ \ | (_) | | | | |_| | 
|_|  |_|___/_|\___/|_| |_|\__,_| 
EOF
    echo -e "${NC}"
    echo -e "${CYAN}     🚀 Hosting Manager by Melsony ${NC}"
    print_header_rule
    sleep 1.2
}

# Main loop
welcome_animation

while true; do
    show_menu
    read -r choice
    case $choice in
        1) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/panel2.sh" ;;
        2) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/wing2.sh" ;;
        3) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/update2.sh" ;;
        4) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/uninstall2.sh" ;;
        5) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/Blueprint2.sh" ;;
        6) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/cloudflare.sh" ;;
        7) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/th2.sh" ;;
        8) system_info ;;
        9) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/tailscale.sh" ;;
        10) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/dbsetup.sh" ;;
        11) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/dash.sh" ;;
        12) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/theme-dash.sh" ;;
        13) run_remote_script "https://raw.githubusercontent.com/mohamedeldony3/install-petro-theme/refs/heads/main/switch_domains.sh" ;;
        0)
            echo -e "${GREEN}Exiting Melsony Hosting Manager...${NC}"
            print_header_rule
            echo -e "${CYAN}      💎 Managed & Powered by Melsony      ${NC}"
            print_header_rule
            sleep 1
            exit 0
            ;;
        *)
            print_error "Invalid option! Please choose between 0-12"
            sleep 1.2
            ;;
    esac
done