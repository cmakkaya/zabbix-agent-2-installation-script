#!/bin/bash
# ============================================================
#  Script Name:    install-zabbix-agent2.sh
#  Version:        1.0
#  Description:    Zabbix Agent 2 v7.4.8 Installer for Ubuntu 24.04
#                  - Fresh install (apt / official Zabbix repo)
#                  - Upgrade from Zabbix Agent 1
#                  - Upgrade from Zabbix Agent 2 old version
#                  - PSK encryption support
#                  - UFW Firewall rule (port 10050)
#                  - Log to /var/log/zabbix/
#  Target OS:      Ubuntu 24.04 LTS (amd64)
#  Zabbix Version: 7.4.8 (Agent 2)
#  References:
#    [1] Zabbix Agent 2 Ubuntu Install:
#        https://www.zabbix.com/download?zabbix=7.4&os_distribution=ubuntu&os_version=24.04&components=agent_2
#    [2] Zabbix Official Repository:
#        https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/
#    [3] Zabbix PSK Encryption:
#        https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys
#    [4] Zabbix Agent 2 Config Parameters:
#        https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2
#    [5] UFW Firewall:
#        https://help.ubuntu.com/community/UFW
#
#  This script was prepared by DevOps Engineer Cumhur M. Akkaya.
#  You can share your feedback and suggestions via:
#  https://www.linkedin.com/in/cumhurakkaya/
#  https://cmakkaya.medium.com/
#  https://github.com/cmakkaya
# ============================================================

# -------------------------------------------------------
# TO INSTALL A DIFFERENT VERSION
# -------------------------------------------------------
# If you want to install a different version, you must update
# both AGENT2_VERSION and ZABBIX_REPO_DEB together.
# Example:
# AGENT2_VERSION="7.0.10"
# ZABBIX_REPO_DEB="https://repo.zabbix.com/zabbix/7.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb"
#
# To check available versions:
# https://repo.zabbix.com/zabbix/

# -------------------------------------------------------
# STATIC VARIABLES - Edit here if needed
# -------------------------------------------------------
AGENT2_VERSION="7.4.8"
ZABBIX_REPO_DEB="https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu24.04_all.deb"
CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
PSK_DIR="/etc/zabbix/psk"
PSK_FILE="$PSK_DIR/zabbix_agent2.psk"
LOG_DIR="/var/log/zabbix"
AGENT2_PORT=10050
SERVICE_NAME="zabbix-agent2"
SERVICE_NAME_A1="zabbix-agent"

# -------------------------------------------------------
# COLOR DEFINITIONS
# -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# -------------------------------------------------------
# HELPER FUNCTION: Print section banner
# -------------------------------------------------------
print_banner() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

# -------------------------------------------------------
# HELPER FUNCTION: Print error and exit
# -------------------------------------------------------
exit_with_error() {
    echo -e "\n${RED}[ERROR] $1${NC}"
    echo -e "${RED}Terminating script...${NC}\n"
    exit 1
}

# -------------------------------------------------------
# HELPER FUNCTION: Print OK message
# -------------------------------------------------------
print_ok() {
    echo -e "${GREEN}[OK] $1${NC}"
}

# -------------------------------------------------------
# HELPER FUNCTION: Print INFO message
# -------------------------------------------------------
print_info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

# -------------------------------------------------------
# HELPER FUNCTION: Print WARNING message
# -------------------------------------------------------
print_warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# -------------------------------------------------------
# ROOT PRIVILEGE CHECK
# Ref: https://www.gnu.org/software/bash/manual/bash.html
# -------------------------------------------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\n${RED}[ERROR] This script requires root privileges.${NC}"
        echo -e "${YELLOW}Please run with 'sudo -s' or 'sudo bash $0'.${NC}\n"
        exit 1
    fi
    print_ok "Root privileges confirmed."
}

# -------------------------------------------------------
# OS CHECK (Ubuntu 24.04 required)
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/requirements
# -------------------------------------------------------
check_os() {
    print_info "Checking operating system..."

    if [ ! -f /etc/os-release ]; then
        exit_with_error "/etc/os-release not found. Ubuntu 24.04 is required."
    fi

    # shellcheck source=/dev/null
    . /etc/os-release

    if [ "$ID" != "ubuntu" ]; then
        exit_with_error "This script is designed for Ubuntu only. Detected: $ID"
    fi

    if [ "$VERSION_ID" != "24.04" ]; then
        print_warn "This script is optimized for Ubuntu 24.04. Current version: $VERSION_ID"
        read -rp "  Do you want to continue anyway? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo -e "${YELLOW}[INFO] Operation cancelled.${NC}"
            exit 0
        fi
    fi

    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ]; then
        exit_with_error "This script only supports x86_64 (amd64) architecture. Detected: $ARCH"
    fi

    print_ok "OS: Ubuntu $VERSION_ID | Architecture: $ARCH"
}

# -------------------------------------------------------
# FUNCTION: Remove Zabbix Agent 1
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages
# -------------------------------------------------------
remove_agent1() {
    print_info "Checking for Zabbix Agent 1..."

    if dpkg -l | grep -q "^ii.*zabbix-agent "; then
        print_info "Zabbix Agent 1 found. Removing..."

        # Stop the service
        # Ref: https://www.freedesktop.org/software/systemd/man/systemctl.html
        systemctl stop "$SERVICE_NAME_A1" 2>/dev/null
        systemctl disable "$SERVICE_NAME_A1" 2>/dev/null
        sleep 2

        # Remove the package
        # Ref: https://manpages.ubuntu.com/manpages/noble/en/man8/apt.8.html
        apt-get remove --purge -y zabbix-agent 2>/dev/null
        apt-get autoremove -y 2>/dev/null

        print_ok "Zabbix Agent 1 removed successfully."
    else
        echo -e "${GRAY}[INFO] Zabbix Agent 1 not found. Continuing.${NC}"
    fi
}

# -------------------------------------------------------
# FUNCTION: Remove Zabbix Agent 2 (old version)
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages
# -------------------------------------------------------
remove_agent2() {
    print_info "Checking for Zabbix Agent 2..."

    if dpkg -l | grep -q "^ii.*zabbix-agent2 "; then
        INSTALLED_VER=$(dpkg -l zabbix-agent2 2>/dev/null | grep "^ii" | awk '{print $3}' | cut -d: -f2 | cut -d- -f1)
        print_info "Zabbix Agent 2 found. Installed version: $INSTALLED_VER"

        # Stop the service
        systemctl stop "$SERVICE_NAME" 2>/dev/null
        systemctl disable "$SERVICE_NAME" 2>/dev/null
        sleep 2

        # Backup existing config file
        if [ -f "$CONFIG_FILE" ]; then
            BACKUP_DATE=$(date +"%d.%m.%Y_%H.%M")
            cp "$CONFIG_FILE" "${CONFIG_FILE}.backup_${BACKUP_DATE}"
            print_info "Existing config backed up: ${CONFIG_FILE}.backup_${BACKUP_DATE}"
        fi

        # Remove the package
        apt-get remove --purge -y zabbix-agent2 2>/dev/null
        apt-get autoremove -y 2>/dev/null

        print_ok "Zabbix Agent 2 ($INSTALLED_VER) removed successfully."
    else
        echo -e "${GRAY}[INFO] Zabbix Agent 2 not found. Continuing.${NC}"
    fi
}

# -------------------------------------------------------
# FUNCTION: Add official Zabbix repo and install package
# Ref: https://www.zabbix.com/download?zabbix=7.4&os_distribution=ubuntu&os_version=24.04&components=agent_2
# -------------------------------------------------------
install_agent2() {
    print_banner "Installing Zabbix Agent 2 v$AGENT2_VERSION"

    local tmp_deb="/tmp/zabbix-release_7.4_ubuntu24.04.deb"

    print_info "Adding official Zabbix repository..."
    print_info "Source: $ZABBIX_REPO_DEB"

    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/wget.1.html
    wget -q --show-progress -O "$tmp_deb" "$ZABBIX_REPO_DEB" || \
        exit_with_error "Failed to download Zabbix repo package. Please check your internet connection."

    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/dpkg.1.html
    dpkg -i "$tmp_deb" || exit_with_error "Failed to install Zabbix repo package."
    rm -f "$tmp_deb"

    print_info "Updating package list (apt update)..."
    apt-get update -q || exit_with_error "apt update failed."

    print_info "Installing Zabbix Agent 2 (apt install zabbix-agent2)..."
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man8/apt.8.html
    DEBIAN_FRONTEND=noninteractive apt-get install -y zabbix-agent2 || \
        exit_with_error "Failed to install zabbix-agent2 package."

    print_ok "Zabbix Agent 2 package installed successfully."

    # Verify installed version
    ACTUAL_VER=$(dpkg -l zabbix-agent2 2>/dev/null | grep "^ii" | awk '{print $3}' | cut -d: -f2 | cut -d- -f1)
    print_info "Installed version: $ACTUAL_VER"
}

# -------------------------------------------------------
# FUNCTION: PSK configuration
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys
# -------------------------------------------------------
setup_psk() {
    local agent_hostname="$1"

    echo ""
    echo -e "${CYAN}[PSK] Starting PSK configuration...${NC}"

    # PSK Identity: auto-generated as PSK_<HOSTNAME>
    PSK_IDENTITY="PSK_${agent_hostname^^}"
    print_ok "PSK Identity generated automatically: $PSK_IDENTITY"

    # PSK Key: prompt user for input
    echo ""
    echo -e "${YELLOW}[PSK] Please enter your 256-bit (64 character) hexadecimal PSK Key.${NC}"
    echo -e "${GRAY}[PSK] Example: a3f1c2...  (must match the value on Zabbix Server/Proxy)${NC}"
    echo -e "${GRAY}[PSK] Ref: https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys${NC}"
    echo ""

    local attempt=0
    while true; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt 3 ]; then
            exit_with_error "3 invalid PSK attempts. Terminating script."
        fi

        read -rp "[PSK] Enter PSK Key (64 hex characters): " PSK_KEY
        PSK_KEY=$(echo "$PSK_KEY" | tr -d '[:space:]')

        # Validate hex format - exactly 64 chars, only 0-9 and a-f/A-F
        # Ref: https://www.gnu.org/software/bash/manual/bash.html#Pattern-Matching
        if echo "$PSK_KEY" | grep -qE '^[0-9a-fA-F]{64}$'; then
            print_ok "PSK Key format is valid."
            break
        else
            echo -e "${RED}[WARNING] Invalid format. Must be exactly 64 hex characters (0-9, a-f only). Please try again.${NC}"
        fi
    done

    # Create PSK directory
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/mkdir.1.html
    mkdir -p "$PSK_DIR"

    # Save PSK Key to file
    echo "$PSK_KEY" > "$PSK_FILE"

    # Set file permissions - only zabbix user should read
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/chmod.1.html
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/chown.1.html
    chmod 640 "$PSK_FILE"
    chown root:zabbix "$PSK_FILE" 2>/dev/null || chmod 600 "$PSK_FILE"

    print_ok "PSK file saved: $PSK_FILE"
    print_ok "PSK file permissions set (640 - root:zabbix)."
}

# -------------------------------------------------------
# FUNCTION: Configure Zabbix Agent 2 config file
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2
# -------------------------------------------------------
configure_agent2() {
    local proxy_ip="$1"
    local agent_hostname="$2"
    local psk_identity="$3"

    print_info "Configuring Zabbix Agent 2: $CONFIG_FILE"

    # Create log directory
    # Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2
    mkdir -p "$LOG_DIR"
    chown zabbix:zabbix "$LOG_DIR" 2>/dev/null || true
    chmod 755 "$LOG_DIR"

    # Backup existing config
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.orig"
        print_info "Original config backed up: ${CONFIG_FILE}.orig"
    fi

    # Update config parameters
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/sed.1.html

    # Server (Passive check - Proxy IP)
    sed -i "s|^Server=.*|Server=$proxy_ip|" "$CONFIG_FILE"
    grep -q "^Server=" "$CONFIG_FILE" || echo "Server=$proxy_ip" >> "$CONFIG_FILE"

    # ServerActive (Active check - Proxy IP)
    sed -i "s|^ServerActive=.*|ServerActive=$proxy_ip|" "$CONFIG_FILE"
    grep -q "^ServerActive=" "$CONFIG_FILE" || echo "ServerActive=$proxy_ip" >> "$CONFIG_FILE"

    # Hostname
    sed -i "s|^Hostname=.*|Hostname=$agent_hostname|" "$CONFIG_FILE"
    grep -q "^Hostname=" "$CONFIG_FILE" || echo "Hostname=$agent_hostname" >> "$CONFIG_FILE"

    # LogFile
    sed -i "s|^LogFile=.*|LogFile=$LOG_DIR/zabbix_agent2.log|" "$CONFIG_FILE"
    grep -q "^LogFile=" "$CONFIG_FILE" || echo "LogFile=$LOG_DIR/zabbix_agent2.log" >> "$CONFIG_FILE"

    # LogFileSize (max log size in MB)
    sed -i "s|^LogFileSize=.*|LogFileSize=100|" "$CONFIG_FILE"
    grep -q "^LogFileSize=" "$CONFIG_FILE" || echo "LogFileSize=100" >> "$CONFIG_FILE"

    # PSK Encryption parameters
    # Ref: https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys
    sed -i "s|^TLSConnect=.*|TLSConnect=psk|" "$CONFIG_FILE"
    grep -q "^TLSConnect=" "$CONFIG_FILE" || echo "TLSConnect=psk" >> "$CONFIG_FILE"

    sed -i "s|^TLSAccept=.*|TLSAccept=psk|" "$CONFIG_FILE"
    grep -q "^TLSAccept=" "$CONFIG_FILE" || echo "TLSAccept=psk" >> "$CONFIG_FILE"

    sed -i "s|^TLSPSKIdentity=.*|TLSPSKIdentity=$psk_identity|" "$CONFIG_FILE"
    grep -q "^TLSPSKIdentity=" "$CONFIG_FILE" || echo "TLSPSKIdentity=$psk_identity" >> "$CONFIG_FILE"

    sed -i "s|^TLSPSKFile=.*|TLSPSKFile=$PSK_FILE|" "$CONFIG_FILE"
    grep -q "^TLSPSKFile=" "$CONFIG_FILE" || echo "TLSPSKFile=$PSK_FILE" >> "$CONFIG_FILE"

    print_ok "Zabbix Agent 2 configuration completed."
}

# -------------------------------------------------------
# FUNCTION: Verify configuration file
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2
# -------------------------------------------------------
verify_config() {
    local proxy_ip="$1"
    local agent_hostname="$2"

    print_info "Verifying configuration file: $CONFIG_FILE"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_warn "Config file not found: $CONFIG_FILE"
        return
    fi

    local all_ok=true
    local params=("Server" "ServerActive" "Hostname" "TLSConnect" "TLSAccept" "TLSPSKIdentity" "TLSPSKFile")

    for param in "${params[@]}"; do
        if grep -qE "^${param}=" "$CONFIG_FILE"; then
            print_ok "Config: $param parameter is present."
        else
            print_warn "Config: $param parameter is missing or commented out!"
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        echo ""
        print_warn "Some parameters appear to be missing."
        print_warn "Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2"
    fi

    # Show actual values
    echo ""
    print_info "Current config values:"
    grep -E "^Server=|^ServerActive=|^Hostname=|^TLSConnect=|^TLSAccept=|^TLSPSKIdentity=|^TLSPSKFile=" "$CONFIG_FILE" | \
        while read -r line; do
            echo -e "  ${GRAY}$line${NC}"
        done
}

# -------------------------------------------------------
# FUNCTION: Add UFW Firewall rule (port 10050 TCP)
# Ref: https://help.ubuntu.com/community/UFW
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages
# -------------------------------------------------------
add_firewall_rule() {
    print_info "Checking UFW Firewall (port $AGENT2_PORT/TCP)..."

    # Check if UFW is installed
    if ! command -v ufw &>/dev/null; then
        print_warn "UFW not found. Firewall rule cannot be added. Please add it manually."
        return
    fi

    # Check if UFW is active
    UFW_STATUS=$(ufw status | head -1)
    if echo "$UFW_STATUS" | grep -q "inactive"; then
        print_warn "UFW is not active. Rule will be added but UFW is currently disabled."
        print_warn "To enable UFW run: ufw enable"
    fi

    # Remove existing rule and add new one
    ufw delete allow "$AGENT2_PORT/tcp" 2>/dev/null || true

    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man8/ufw.8.html
    ufw allow "$AGENT2_PORT/tcp" comment "Zabbix Agent 2 v$AGENT2_VERSION" 2>/dev/null

    print_ok "UFW rule added: TCP/$AGENT2_PORT (inbound allow)"
}

# -------------------------------------------------------
# FUNCTION: Start and verify service
# Ref: https://www.freedesktop.org/software/systemd/man/systemctl.html
# -------------------------------------------------------
verify_service() {
    print_info "Starting Zabbix Agent 2 service..."

    # Enable and start the service
    systemctl enable "$SERVICE_NAME" 2>/dev/null
    systemctl restart "$SERVICE_NAME" 2>/dev/null
    sleep 3

    # Check service status
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        START_TIME=$(systemctl show "$SERVICE_NAME" --property=ActiveEnterTimestamp | cut -d= -f2)
        print_ok "Zabbix Agent 2 service is RUNNING."
        print_ok "Start time: $START_TIME"

        # Show service details
        echo ""
        print_info "Service status:"
        systemctl status "$SERVICE_NAME" --no-pager -l | head -20
    else
        echo -e "${RED}[ERROR] Service failed to start. Details:${NC}"
        systemctl status "$SERVICE_NAME" --no-pager -l
        echo ""
        print_warn "Check the log file: $LOG_DIR/zabbix_agent2.log"
        print_warn "Or run: journalctl -u zabbix-agent2 -n 50"
    fi
}

# -------------------------------------------------------
# FUNCTION: Print installation summary - wait for user to close
# -------------------------------------------------------
write_summary() {
    local agent_hostname="$1"
    local proxy_ip="$2"
    local psk_identity="$3"

    # Get host IP address
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/hostname.1.html
    HOST_IP=$(hostname -I | awk '{print $1}')
    INSTALL_DATE=$(date +"%d.%m.%Y %H:%M")

    clear
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  INSTALLATION COMPLETED SUCCESSFULLY${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${WHITE}  Date         : $INSTALL_DATE${NC}"
    echo -e "${WHITE}  Hostname     : $agent_hostname${NC}"
    echo -e "${WHITE}  Hostname IP  : $HOST_IP${NC}"
    echo -e "${WHITE}  Proxy IP     : $proxy_ip${NC}"
    echo -e "${CYAN}  PSK Identity : $psk_identity${NC}"
    echo ""
    echo -e "${YELLOW}============================================================${NC}"
    echo -e "${YELLOW}  [!] IMPORTANT - ACTION REQUIRED ON PROXY SIDE${NC}"
    echo -e "${YELLOW}============================================================${NC}"
    echo ""
    echo -e "${WHITE}  The agent cannot connect until PSK is configured${NC}"
    echo -e "${WHITE}  on the Zabbix Web UI for this host!${NC}"
    echo ""
    echo -e "${YELLOW}  Steps:${NC}"
    echo -e "${WHITE}  1) Zabbix Web UI -> Configuration -> Hosts${NC}"
    echo -e "${WHITE}  2) Select this host -> [Encryption] tab${NC}"
    echo -e "${WHITE}  3) Enter the following values:${NC}"
    echo ""
    echo -e "${CYAN}     Connections to host   : PSK${NC}"
    echo -e "${CYAN}     Connections from host : PSK${NC}"
    echo -e "${CYAN}     PSK Identity          : $psk_identity${NC}"
    echo -e "${CYAN}     PSK (Key)             : Enter the PSK Key value you provided during installation.${NC}"
    echo ""
    echo -e "${GRAY}  Ref: https://www.zabbix.com/documentation/7.4/en/manual/${NC}"
    echo -e "${GRAY}       encryption/using_pre_shared_keys${NC}"
    echo ""
    echo -e "${CYAN}  This script was prepared by DevOps Engineer Cumhur M. Akkaya.${NC}"
    echo -e "${CYAN}  You can share your feedback and suggestions via:${NC}"
    echo -e "${CYAN}  https://www.linkedin.com/in/cumhurakkaya/${NC}"
    echo -e "${CYAN}  https://cmakkaya.medium.com/${NC}"
    echo -e "${CYAN}  https://github.com/cmakkaya${NC}"
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${WHITE}  Please take note of the information above,${NC}"
    echo -e "${WHITE}  then press ENTER to close this window.${NC}"
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo ""

    # Wait for user to press ENTER before closing
    read -rp "  >> Press ENTER to exit: "
}

# -------------------------------------------------------
# MAIN INSTALLATION FLOW: Install / Upgrade
# -------------------------------------------------------
start_install() {
    local mode="$1"   # fresh | upgrade1 | upgrade2

    case "$mode" in
        fresh)
            print_banner "Zabbix Agent 2 v$AGENT2_VERSION - Fresh Installation"
            remove_agent1
            remove_agent2
            ;;
        upgrade1)
            print_banner "Zabbix Agent 1 -> Agent 2 v$AGENT2_VERSION Upgrade"

            # Check if Agent 1 is installed
            if ! dpkg -l | grep -q "^ii.*zabbix-agent "; then
                print_warn "Zabbix Agent 1 not found."
                read -rp "  Type 'yes' to continue anyway, or anything else to cancel: " confirm
                if [ "$confirm" != "yes" ]; then
                    print_info "Operation cancelled. Returning to main menu..."
                    sleep 2
                    show_menu
                    return
                fi
            fi
            remove_agent1
            remove_agent2
            ;;
        upgrade2)
            print_banner "Zabbix Agent 2 (Old Version) -> v$AGENT2_VERSION Upgrade"

            # Check if Agent 2 is installed
            if ! dpkg -l | grep -q "^ii.*zabbix-agent2 "; then
                print_warn "Zabbix Agent 2 not found."
                read -rp "  Type 'yes' to continue anyway, or anything else to cancel: " confirm
                if [ "$confirm" != "yes" ]; then
                    print_info "Operation cancelled. Returning to main menu..."
                    sleep 2
                    show_menu
                    return
                fi
            else
                INSTALLED_VER=$(dpkg -l zabbix-agent2 2>/dev/null | grep "^ii" | awk '{print $3}' | cut -d: -f2 | cut -d- -f1)
                if [ "$INSTALLED_VER" = "$AGENT2_VERSION" ]; then
                    print_warn "Zabbix Agent 2 v$AGENT2_VERSION is already installed!"
                    read -rp "  Type 'yes' to reinstall, or anything else to cancel: " confirm
                    if [ "$confirm" != "yes" ]; then
                        show_menu
                        return
                    fi
                fi
            fi
            remove_agent2
            ;;
    esac

    # Get Proxy IP from user
    echo -e "${CYAN}[INPUT] Enter the Zabbix Proxy IP address:${NC}"
    PROXY_IP=""
    while ! echo "$PROXY_IP" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; do
        read -rp "  Proxy IP: " PROXY_IP
        PROXY_IP=$(echo "$PROXY_IP" | tr -d '[:space:]')
        if ! echo "$PROXY_IP" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
            echo -e "${RED}  [WARNING] Invalid IP format. Please try again (example: 192.168.1.10)${NC}"
        fi
    done

    # Get hostname automatically
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/hostname.1.html
    AGENT_HOSTNAME=$(hostname)
    print_ok "Hostname detected automatically: $AGENT_HOSTNAME"

    # Install Agent 2
    install_agent2

    # Configure PSK
    setup_psk "$AGENT_HOSTNAME"

    # Configure Agent 2
    configure_agent2 "$PROXY_IP" "$AGENT_HOSTNAME" "$PSK_IDENTITY"

    # Add firewall rule
    add_firewall_rule

    # Verify config
    verify_config "$PROXY_IP" "$AGENT_HOSTNAME"

    # Start and verify service
    verify_service

    # Print summary
    write_summary "$AGENT_HOSTNAME" "$PROXY_IP" "$PSK_IDENTITY"
}

# -------------------------------------------------------
# MAIN MENU
# -------------------------------------------------------
show_menu() {
    clear
    HOSTNAME_VAL=$(hostname)
    ARCH_VAL=$(uname -m)

    echo ""
    echo -e "${YELLOW}============================================================${NC}"
    echo -e "${YELLOW}  Welcome to Zabbix Agent 2 v$AGENT2_VERSION Installation Script.${NC}"
    echo -e "${YELLOW}  Prepared for Ubuntu 24.04 LTS | amd64 | apt.${NC}"
    echo ""
    echo -e "${GRAY}  Ref: https://www.zabbix.com/documentation/7.4/en/manual/${NC}"
    echo -e "${GRAY}       installation/install_from_packages${NC}"
    echo ""
    echo -e "${CYAN}  This script was prepared by DevOps Engineer Cumhur M. Akkaya.${NC}"
    echo -e "${CYAN}  You can share your feedback and suggestions via:${NC}"
    echo -e "${CYAN}  https://www.linkedin.com/in/cumhurakkaya/${NC}"
    echo -e "${CYAN}  https://cmakkaya.medium.com/${NC}"
    echo -e "${CYAN}  https://github.com/cmakkaya${NC}"
    echo -e "${YELLOW}============================================================${NC}"
    echo ""
    echo -e "${CYAN}  Server : $HOSTNAME_VAL${NC}"
    echo -e "${CYAN}  Arch   : $ARCH_VAL${NC}"
    echo ""
    echo -e "${WHITE}  1) Install [Zabbix Agent 2 v$AGENT2_VERSION]${NC}"
    echo -e "${GRAY}     Fresh installation - existing Agent1/Agent2 will be removed${NC}"
    echo ""
    echo -e "${WHITE}  2) Update [Zabbix Agent 1] to [Zabbix Agent 2 v$AGENT2_VERSION]${NC}"
    echo -e "${GRAY}     Removes existing Agent1, installs Agent2 v$AGENT2_VERSION${NC}"
    echo ""
    echo -e "${WHITE}  3) Update [Zabbix Agent 2 old version] to [Zabbix Agent 2 v$AGENT2_VERSION]${NC}"
    echo -e "${GRAY}     Removes old Agent2, installs Agent2 v$AGENT2_VERSION${NC}"
    echo ""
    echo -e "${GRAY}  0) Exit${NC}"
    echo ""
    echo -e "${YELLOW}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}  Pre-requisite:${NC}"
    echo -e "${WHITE}  If you don't have a PSK Key yet, generate one before starting${NC}"
    echo -e "${WHITE}  the installation and copy it for use during setup.${NC}"
    echo ""
    echo -e "${CYAN}  01. To generate a PSK Key:${NC}"
    echo -e "${WHITE}      openssl rand -hex 32${NC}"
    echo ""
    echo -e "${CYAN}  02. Your PSK Key will look similar to this:${NC}"
    echo -e "${GRAY}      34f6889e280e51dda96a4b3fc7732f3cd77f50ec4443271b3dc227dae1938fca${NC}"
    echo ""
    echo -e "${YELLOW}============================================================${NC}"
    echo ""

    local invalid_count=0

    while true; do
        read -rp "  Select Operation [1/2/3/0]: " choice
        case "$choice" in
            1) start_install "fresh";    return ;;
            2) start_install "upgrade1"; return ;;
            3) start_install "upgrade2"; return ;;
            0)
                echo -e "\n${YELLOW}[INFO] Terminating script.${NC}\n"
                exit 0
                ;;
            *)
                invalid_count=$((invalid_count + 1))
                echo -e "${RED}  [WARNING] Invalid selection. Please enter 1, 2, 3 or 0.${NC}"
                if [ "$invalid_count" -ge 3 ]; then
                    exit_with_error "Maximum number of invalid attempts reached."
                fi
                ;;
        esac
    done
}

# -------------------------------------------------------
# ENTRY POINT
# -------------------------------------------------------
check_root
check_os
show_menu
