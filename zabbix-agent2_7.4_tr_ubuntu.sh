#!/bin/bash
# ============================================================
#  Script Name:    install-zabbix-agent2.sh
#  Version:        2.0
#  Description:    Zabbix Agent 2 7.4.x Installer for all Ubuntu versions
#                  - Fresh install (apt/official Zabbix repo)
#                  - Upgrade from Zabbix Agent 1
#                  - Upgrade from Zabbix Agent 2 old version
#                  - PSK encryption support
#                  - UFW Firewall rule (port 10050)
#                  - Log to /var/log/zabbix/
#                  - Auto-detects Ubuntu version and validates official repo support
#                  - Multiple proxy IP / proxy group support
#  Target OS:      Ubuntu versions supported by the official Zabbix 7.4 repo
#  Zabbix Version: Latest available 7.4.x (Agent 2)
#  References:
#    [1] Zabbix Agent 2 Ubuntu Install:
#        https://www.zabbix.com/download?zabbix=7.4&os_distribution=ubuntu&os_version=24.04&components=agent_2
#        https://www.zabbix.com/download?zabbix=7.4&os_distribution=ubuntu&os_version=22.04&components=agent_2
#        https://www.zabbix.com/download?zabbix=7.4&os_distribution=ubuntu&os_version=20.04&components=agent_2
#    [2] Zabbix Official Repository:
#        https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/
#    [3] Zabbix PSK Encryption:
#        https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys
#    [4] Zabbix Agent 2 Config Parameters:
#        https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2
#    [5] UFW Firewall:
#        https://help.ubuntu.com/community/UFW
#
#__ATTR_START__
#  This script was prepared by DevOps Engineer Cumhur M. Akkaya.
#  You can share your feedback and suggestions via:
#  https://www.linkedin.com/in/cumhurakkaya/
#  https://cmakkaya.medium.com/
#  https://github.com/cmakkaya
# ============================================================
#__ATTR_END__

# -------------------------------------------------------
# TO USE A DIFFERENT ZABBIX BRANCH
# -------------------------------------------------------
# Update ZABBIX_BRANCH and AGENT2_VERSION together.
# Example for the 7.0 LTS branch:
# ZABBIX_BRANCH="7.0"
# AGENT2_VERSION="7.0.x"
#
# The repository package URL is generated automatically from
# the detected Ubuntu VERSION_ID.
# -------------------------------------------------------

# -------------------------------------------------------
# STATIC VARIABLES - Edit here if needed
# -------------------------------------------------------
ZABBIX_BRANCH="7.4"
AGENT2_VERSION="7.4.x"
ZABBIX_REPO_BASE="https://repo.zabbix.com/zabbix/${ZABBIX_BRANCH}/release/ubuntu"
ZABBIX_REPO_DEB=""
CONFIG_FILE="/etc/zabbix/zabbix_agent2.conf"
PSK_DIR="/etc/zabbix/psk"
PSK_FILE="$PSK_DIR/zabbix_agent2.psk"
LOG_DIR="/var/log/zabbix"
AGENT2_PORT=10050
SERVICE_NAME="zabbix-agent2"
SERVICE_NAME_A1="zabbix-agent"
APT_WAIT_SECONDS=180
# -------------------------------------------------------
# INTEGRITY CHECK - Author Attribution Protection
# -------------------------------------------------------
# Verifies that the author credit section has not been
# removed or altered. Any modification to the lines
# between #__ATTR_START__ / #__ATTR_END__ markers
# will cause the script to refuse execution.
#
# Protected sections (3 blocks, 16 lines total):
#   1) Header comment block
#   2) show_summary attribution lines
#   3) show_menu attribution lines
# -------------------------------------------------------
INTEGRITY_HASH="0eaf15bcfa8e70434bacc0127606e021e66ff82aa9003c273cb675aa1e563d43"

check_integrity() {
    local script_path
    # Resolve actual script path (works with bash, sh, source)
    if [ -n "${BASH_SOURCE[0]}" ]; then
        script_path="${BASH_SOURCE[0]}"
    else
        script_path="$0"
    fi

    # Resolve to absolute path
    script_path="$(cd "$(dirname "$script_path")" 2>/dev/null && pwd)/$(basename "$script_path")"

    if [ ! -f "$script_path" ]; then
        echo "[WARNING] Integrity check skipped: script file not found at $script_path" >&2
        return
    fi

    local mark_start="#__ATTR_START__"
    local mark_end="#__ATTR_END__"
    local inside=0
    local collected=""
    local first=1

    while IFS= read -r ln; do
        trimmed="${ln%"${ln##*[![:space:]]}"}"  # rtrim
        if [ "$trimmed" = "$mark_start" ]; then
            inside=1
            continue
        fi
        if [ "$trimmed" = "$mark_end" ]; then
            inside=0
            continue
        fi
        if [ "$inside" -eq 1 ]; then
            if [ "$first" -eq 1 ]; then
                collected="$trimmed"
                first=0
            else
                collected="$collected
$trimmed"
            fi
        fi
    done < "$script_path"

    if [ -z "$collected" ]; then
        echo "" >&2
        echo "============================================================" >&2
        echo "  [INTEGRITY ERROR] Attribution markers not found!" >&2
        echo "============================================================" >&2
        echo "  The script has been tampered with and cannot run." >&2
        echo "  Restore the original author attribution section." >&2
        echo "" >&2
        sleep 3
        exit 99
    fi

    # Compute SHA256 of collected lines
    local computed_hash
    computed_hash="$(printf '%s' "$collected" | sha256sum | awk '{print $1}')"

    if [ "$computed_hash" != "$INTEGRITY_HASH" ]; then
        echo "" >&2
        echo "============================================================" >&2
        echo "  [INTEGRITY ERROR] Script integrity check FAILED!" >&2
        echo "============================================================" >&2
        echo "" >&2
        echo "  The author attribution section has been modified." >&2
        echo "  This script will not run in its current state." >&2
        echo "" >&2
        echo "  This script was originally authored by:" >&2
        echo "  DevOps Engineer Cumhur M. Akkaya" >&2
        echo "  Restore all attribution lines to run this script." >&2
        echo "" >&2
        sleep 3
        exit 99
    fi
}

check_integrity
# -------------------------------------------------------


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
        echo -e "
${RED}[ERROR] This script requires root privileges.${NC}"
        echo -e "${YELLOW}Please run with 'sudo bash $0'.${NC}
"
        exit 1
    fi
    print_ok "Root privileges confirmed."
}

# -------------------------------------------------------
# APT/DPKG LOCK HANDLING
# -------------------------------------------------------
wait_for_apt() {
    local waited=0
    local lock_files=(
        /var/lib/dpkg/lock-frontend
        /var/lib/dpkg/lock
        /var/cache/apt/archives/lock
        /var/lib/apt/lists/lock
    )

    if ! command -v fuser >/dev/null 2>&1; then
        return 0
    fi

    while true; do
        local locked=0
        local lock
        for lock in "${lock_files[@]}"; do
            if [ -e "$lock" ] && fuser "$lock" >/dev/null 2>&1; then
                locked=1
                break
            fi
        done

        if [ "$locked" -eq 0 ]; then
            return 0
        fi

        if [ "$waited" -ge "$APT_WAIT_SECONDS" ]; then
            exit_with_error "APT/DPKG is still locked after ${APT_WAIT_SECONDS} seconds. Stop the running package process and retry."
        fi

        if [ "$waited" -eq 0 ]; then
            print_warn "APT/DPKG is being used by another process. Waiting for the lock..."
        fi
        sleep 3
        waited=$((waited + 3))
    done
}

prepare_apt() {
    export DEBIAN_FRONTEND=noninteractive
    wait_for_apt

    print_info "Checking interrupted package operations..."
    dpkg --configure -a >/dev/null 2>&1 || true

    print_info "Installing required tools..."
    apt-get -o Acquire::Retries=3 update -q || \
        print_warn "Initial apt update returned an error. The Zabbix repository will be refreshed next."

    apt-get install -y --no-install-recommends \
        ca-certificates wget gnupg lsb-release procps psmisc >/dev/null || \
        exit_with_error "Required packages could not be installed. Check Ubuntu repositories and network access."
}

# -------------------------------------------------------
# OS CHECK & VERSION DETECTION
# Supports every Ubuntu release for which the official Zabbix 7.4
# repository publishes a zabbix-release package.
# -------------------------------------------------------
detect_ubuntu_version() {
    print_info "Detecting Ubuntu version..."

    if [ ! -r /etc/os-release ]; then
        exit_with_error "/etc/os-release not found. This script requires Ubuntu."
    fi

    # shellcheck source=/dev/null
    . /etc/os-release

    if [ "${ID:-}" != "ubuntu" ]; then
        exit_with_error "This script is designed for Ubuntu only. Detected: ${ID:-unknown}"
    fi

    if [ -z "${VERSION_ID:-}" ]; then
        exit_with_error "Ubuntu VERSION_ID could not be detected."
    fi

    UBUNTU_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    if [ -z "$UBUNTU_CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
        UBUNTU_CODENAME="$(lsb_release -sc 2>/dev/null || true)"
    fi

    if [ -z "$UBUNTU_CODENAME" ]; then
        exit_with_error "Ubuntu codename could not be detected."
    fi

    ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
    case "$ARCH" in
        amd64|arm64)
            ;;
        *)
            exit_with_error "Unsupported architecture: $ARCH. Supported architectures: amd64, arm64."
            ;;
    esac

    ZABBIX_REPO_DEB="${ZABBIX_REPO_BASE}/pool/main/z/zabbix-release/zabbix-release_latest_${ZABBIX_BRANCH}+ubuntu${VERSION_ID}_all.deb"
    ZABBIX_DIST_RELEASE="${ZABBIX_REPO_BASE}/dists/${UBUNTU_CODENAME}/Release"

    print_ok "OS: Ubuntu $VERSION_ID ($UBUNTU_CODENAME) | Architecture: $ARCH"
    print_info "Repository package: $ZABBIX_REPO_DEB"
}

check_os() {
    detect_ubuntu_version
}

# -------------------------------------------------------
# HELPER: Check whether a Debian package is installed
# -------------------------------------------------------
is_package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'
}

# -------------------------------------------------------
# FUNCTION: Remove Zabbix Agent 1
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages
# -------------------------------------------------------
remove_agent1() {
    print_info "Checking for Zabbix Agent 1..."

    if is_package_installed zabbix-agent; then
        print_info "Zabbix Agent 1 found. Removing..."

        # Stop the service
        # Ref: https://www.freedesktop.org/software/systemd/man/systemctl.html
        systemctl stop "$SERVICE_NAME_A1" 2>/dev/null
        systemctl disable "$SERVICE_NAME_A1" 2>/dev/null
        sleep 2

        # Remove the package
        # Ref: https://manpages.ubuntu.com/manpages/noble/en/man8/apt.8.html
        wait_for_apt
        apt-get remove --purge -y zabbix-agent || \
            exit_with_error "Zabbix Agent 1 could not be removed."
        apt-get autoremove -y >/dev/null 2>&1 || true

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

    if is_package_installed zabbix-agent2; then
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
        wait_for_apt
        apt-get remove --purge -y zabbix-agent2 || \
            exit_with_error "Zabbix Agent 2 could not be removed. Existing config backup was preserved."
        apt-get autoremove -y >/dev/null 2>&1 || true

        print_ok "Zabbix Agent 2 ($INSTALLED_VER) removed successfully."
    else
        echo -e "${GRAY}[INFO] Zabbix Agent 2 not found. Continuing.${NC}"
    fi
}

# -------------------------------------------------------
# FUNCTION: Prepare official Zabbix repository
# The repository is validated before any installed agent is removed.
# -------------------------------------------------------
prepare_zabbix_repository() {
    print_banner "Preparing Zabbix ${ZABBIX_BRANCH} Repository"

    local tmp_deb="/tmp/zabbix-release_${ZABBIX_BRANCH}_ubuntu${VERSION_ID}.deb"

    # Remove stale Zabbix repository definitions before the first apt update.
    # This prevents release/codename conflicts left by older installations.
    dpkg -r zabbix-release >/dev/null 2>&1 || true
    rm -f /etc/apt/sources.list.d/zabbix.list \
          /etc/apt/sources.list.d/zabbix-agent2-plugins.list \
          /etc/apt/sources.list.d/zabbix.sources

    prepare_apt
    wait_for_apt

    print_info "Checking whether the official Zabbix repository supports this Ubuntu release..."
    if ! wget -q --spider --tries=3 --timeout=20 "$ZABBIX_DIST_RELEASE"; then
        exit_with_error "The official Zabbix ${ZABBIX_BRANCH} repository does not publish packages for Ubuntu ${VERSION_ID} (${UBUNTU_CODENAME}). No installed agent was removed."
    fi

    print_info "Downloading the official Zabbix repository package..."
    if ! wget --tries=3 --timeout=30 -q --show-progress -O "$tmp_deb" "$ZABBIX_REPO_DEB"; then
        rm -f "$tmp_deb"
        exit_with_error "Failed to download: $ZABBIX_REPO_DEB. No installed agent was removed."
    fi

    if ! dpkg-deb --info "$tmp_deb" >/dev/null 2>&1; then
        rm -f "$tmp_deb"
        exit_with_error "Downloaded Zabbix repository package is invalid or incomplete. No installed agent was removed."
    fi

    print_info "Installing the repository package..."
    if ! dpkg -i "$tmp_deb" >/dev/null; then
        rm -f "$tmp_deb"
        exit_with_error "Failed to install the Zabbix repository package. No installed agent was removed."
    fi
    rm -f "$tmp_deb"

    wait_for_apt
    print_info "Refreshing package lists..."
    apt-get -o Acquire::Retries=3 update || \
        exit_with_error "apt update failed after adding the Zabbix repository. No installed agent was removed."

    AGENT2_CANDIDATE="$(apt-cache policy zabbix-agent2 | awk '/Candidate:/ {print $2; exit}')"
    if [ -z "$AGENT2_CANDIDATE" ] || [ "$AGENT2_CANDIDATE" = "(none)" ]; then
        exit_with_error "No zabbix-agent2 package candidate was found for Ubuntu ${VERSION_ID} (${ARCH}). No installed agent was removed."
    fi

    print_ok "Repository is ready. Package candidate: $AGENT2_CANDIDATE"
}

# -------------------------------------------------------
# FUNCTION: Install Zabbix Agent 2 package
# -------------------------------------------------------
install_agent2() {
    print_banner "Installing Zabbix Agent 2 $AGENT2_VERSION"
    wait_for_apt

    print_info "Installing package candidate: ${AGENT2_CANDIDATE:-latest available}"
    apt-get install -y --no-install-recommends zabbix-agent2 || \
        exit_with_error "Failed to install zabbix-agent2 package."

    if ! is_package_installed zabbix-agent2; then
        exit_with_error "Package installation completed without an installed zabbix-agent2 package."
    fi

    ACTUAL_VER="$(dpkg-query -W -f='${Version}' zabbix-agent2 2>/dev/null || echo unknown)"
    print_ok "Zabbix Agent 2 installed successfully. Version: $ACTUAL_VER"
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
# FUNCTION: Read and validate one or more proxy addresses
# Comma = independent proxies; semicolon = proxy group/HA members.
# -------------------------------------------------------
validate_ipv4() {
    local ip="$1"
    local IFS='.'
    local -a octets
    read -r -a octets <<< "$ip"

    [ "${#octets[@]}" -eq 4 ] || return 1

    local octet
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
        [ "$octet" -ge 0 ] 2>/dev/null || return 1
        [ "$octet" -le 255 ] 2>/dev/null || return 1
    done
}

read_proxy_addresses() {
    local raw delimiter endpoint ip port
    local -a endpoints

    while true; do
        echo -e "${CYAN}[INPUT] Enter one or more Zabbix Proxy IP addresses:${NC}"
        echo -e "${GRAY}  Single proxy          : 172.31.0.8${NC}"
        echo -e "${GRAY}  Independent proxies   : 172.31.0.8,172.31.0.9${NC}"
        echo -e "${GRAY}  Proxy group / HA      : 172.31.0.8;172.31.0.9${NC}"
        echo -e "${GRAY}  Optional custom port  : 172.31.0.8:10051${NC}"
        read -rp "  Proxy address(es): " raw

        raw="$(printf '%s' "$raw" | tr -d '[:space:]')"
        if [ -z "$raw" ]; then
            echo -e "${RED}  [WARNING] At least one proxy address is required.${NC}"
            continue
        fi

        if [[ "$raw" == *","* && "$raw" == *";"* ]]; then
            echo -e "${RED}  [WARNING] Do not mix comma and semicolon separators.${NC}"
            continue
        fi

        if [[ "$raw" == *";"* ]]; then
            delimiter=';'
        else
            delimiter=','
        fi

        IFS="$delimiter" read -r -a endpoints <<< "$raw"
        if [ "${#endpoints[@]}" -eq 0 ]; then
            echo -e "${RED}  [WARNING] Invalid proxy list.${NC}"
            continue
        fi

        local valid=1
        local active_list=""
        local allow_list=""
        local -A seen_active=()
        local -A seen_allow=()

        for endpoint in "${endpoints[@]}"; do
            if [ -z "$endpoint" ]; then
                valid=0
                break
            fi

            ip="$endpoint"
            port=""
            if [[ "$endpoint" == *":"* ]]; then
                ip="${endpoint%%:*}"
                port="${endpoint#*:}"
                if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                    valid=0
                    break
                fi
            fi

            if ! validate_ipv4 "$ip"; then
                valid=0
                break
            fi

            if [ -z "${seen_active[$endpoint]+x}" ]; then
                [ -n "$active_list" ] && active_list+="$delimiter"
                active_list+="$endpoint"
                seen_active[$endpoint]=1
            fi

            if [ -z "${seen_allow[$ip]+x}" ]; then
                [ -n "$allow_list" ] && allow_list+="," 
                allow_list+="$ip"
                seen_allow[$ip]=1
            fi
        done

        if [ "$valid" -eq 0 ]; then
            echo -e "${RED}  [WARNING] Invalid IPv4 address or port. Example: 192.168.1.10 or 192.168.1.10:10051${NC}"
            continue
        fi

        PROXY_ACTIVE="$active_list"
        PROXY_ALLOWLIST="$allow_list"
        PROXY_DISPLAY="$active_list"
        print_ok "Proxy address list accepted: $PROXY_DISPLAY"
        return 0
    done
}

# -------------------------------------------------------
# FUNCTION: Configure Zabbix Agent 2 config file
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2
# -------------------------------------------------------
configure_agent2() {
    local proxy_allowlist="$1"
    local proxy_active="$2"
    local agent_hostname="$3"
    local psk_identity="$4"

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

    if [ ! -f "$CONFIG_FILE" ]; then
        install -o root -g zabbix -m 0644 /dev/null "$CONFIG_FILE" || \
            exit_with_error "Configuration file could not be created: $CONFIG_FILE"
    fi

    # Update config parameters
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/sed.1.html

    # Server (Passive check - Proxy IP)
    sed -i "s|^Server=.*|Server=$proxy_allowlist|" "$CONFIG_FILE"
    grep -q "^Server=" "$CONFIG_FILE" || echo "Server=$proxy_allowlist" >> "$CONFIG_FILE"

    # ServerActive (Active check - Proxy IP)
    sed -i "s|^ServerActive=.*|ServerActive=$proxy_active|" "$CONFIG_FILE"
    grep -q "^ServerActive=" "$CONFIG_FILE" || echo "ServerActive=$proxy_active" >> "$CONFIG_FILE"

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
    local agent_hostname="$1"

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

    if ! grep -Fxq "Hostname=$agent_hostname" "$CONFIG_FILE"; then
        print_warn "Configured Hostname does not exactly match the detected hostname: $agent_hostname"
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
    local proxy_allowlist="$1"
    print_info "Checking UFW Firewall (port $AGENT2_PORT/TCP)..."

    if ! command -v ufw >/dev/null 2>&1; then
        print_warn "UFW not found. Firewall rules were not added."
        return 0
    fi

    local ufw_state
    ufw_state="$(ufw status 2>/dev/null | head -1 || true)"
    if echo "$ufw_state" | grep -qi "inactive"; then
        print_warn "UFW is inactive. Source-restricted rules will be stored but not enforced until UFW is enabled."
    fi

    # Remove the old unrestricted rule created by previous script versions.
    ufw --force delete allow "$AGENT2_PORT/tcp" >/dev/null 2>&1 || true

    local ip
    local -a proxy_ips
    local IFS=','
    read -r -a proxy_ips <<< "$proxy_allowlist"
    for ip in "${proxy_ips[@]}"; do
        ufw allow from "$ip" to any port "$AGENT2_PORT" proto tcp >/dev/null 2>&1 || \
            print_warn "UFW rule could not be added for proxy $ip."
    done

    print_ok "UFW rules added for proxy source(s): $proxy_allowlist -> TCP/$AGENT2_PORT"
}

# -------------------------------------------------------
# FUNCTION: Start and verify service
# Ref: https://www.freedesktop.org/software/systemd/man/systemctl.html
# -------------------------------------------------------
verify_service() {
    print_info "Starting Zabbix Agent 2 service..."

    # Validate configuration before starting the service
    if ! zabbix_agent2 -c "$CONFIG_FILE" -t agent.ping >/dev/null 2>&1; then
        print_warn "Agent configuration test returned an error. Service logs will be shown if startup fails."
    fi

    # Enable and start the service
    systemctl daemon-reload >/dev/null 2>&1 || true
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
    local proxy_display="$2"
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
    echo -e "${WHITE}  Agent Version: ${ACTUAL_VER:-unknown}${NC}"
    echo -e "${WHITE}  Hostname     : $agent_hostname${NC}"
    echo -e "${WHITE}  Hostname IP  : $HOST_IP${NC}"
    echo -e "${WHITE}  Proxy(s)     : $proxy_display${NC}"
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
#__ATTR_START__
    echo -e "${CYAN}  This script was prepared by DevOps Engineer Cumhur M. Akkaya.${NC}"
    echo -e "${CYAN}  You can share your feedback and suggestions via:${NC}"
    echo -e "${CYAN}  https://www.linkedin.com/in/cumhurakkaya/${NC}"
    echo -e "${CYAN}  https://cmakkaya.medium.com/${NC}"
    echo -e "${CYAN}  https://github.com/cmakkaya${NC}"
#__ATTR_END__
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

    # Collect required values before changing the installed system.
    read_proxy_addresses
    AGENT_HOSTNAME="$(hostname)"
    print_ok "Hostname detected automatically: $AGENT_HOSTNAME"

    # Validate Ubuntu/repository/package availability before removing an agent.
    prepare_zabbix_repository

    case "$mode" in
        fresh)
            print_banner "Zabbix Agent 2 $AGENT2_VERSION - Fresh Installation"
            remove_agent1
            remove_agent2
            ;;
        upgrade1)
            print_banner "Zabbix Agent 1 -> Agent 2 $AGENT2_VERSION Upgrade"

            # Check if Agent 1 is installed
            if ! is_package_installed zabbix-agent; then
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
            print_banner "Zabbix Agent 2 (Old Version) -> $AGENT2_VERSION Upgrade"

            # Check if Agent 2 is installed
            if ! is_package_installed zabbix-agent2; then
                print_warn "Zabbix Agent 2 not found."
                read -rp "  Type 'yes' to continue anyway, or anything else to cancel: " confirm
                if [ "$confirm" != "yes" ]; then
                    print_info "Operation cancelled. Returning to main menu..."
                    sleep 2
                    show_menu
                    return
                fi
            else
                INSTALLED_VER="$(dpkg-query -W -f='${Version}' zabbix-agent2 2>/dev/null || echo unknown)"
                print_info "Installed Zabbix Agent 2 version: $INSTALLED_VER"
                print_info "The package will be reinstalled or upgraded to the current ${ZABBIX_BRANCH}.x repository candidate."
            fi
            remove_agent2
            ;;
    esac


    # Install Agent 2
    install_agent2

    # Configure PSK
    setup_psk "$AGENT_HOSTNAME"

    # Configure Agent 2
    configure_agent2 "$PROXY_ALLOWLIST" "$PROXY_ACTIVE" "$AGENT_HOSTNAME" "$PSK_IDENTITY"

    # Add firewall rule
    add_firewall_rule "$PROXY_ALLOWLIST"

    # Verify config
    verify_config "$AGENT_HOSTNAME"

    # Start and verify service
    verify_service

    # Print summary
    write_summary "$AGENT_HOSTNAME" "$PROXY_DISPLAY" "$PSK_IDENTITY"
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
    echo -e "${YELLOW}  Welcome to Zabbix Agent 2 $AGENT2_VERSION Installation Script.${NC}"
    echo -e "${YELLOW}  Prepared for Ubuntu releases supported by Zabbix 7.4 | amd64/arm64 | apt.${NC}"
    echo ""
    echo -e "${GRAY}  Ref: https://www.zabbix.com/documentation/7.4/en/manual/${NC}"
    echo -e "${GRAY}       installation/install_from_packages${NC}"
    echo ""
#__ATTR_START__
    echo -e "${CYAN}  This script was prepared by DevOps Engineer Cumhur M. Akkaya.${NC}"
    echo -e "${CYAN}  You can share your feedback and suggestions via:${NC}"
    echo -e "${CYAN}  https://www.linkedin.com/in/cumhurakkaya/${NC}"
    echo -e "${CYAN}  https://cmakkaya.medium.com/${NC}"
    echo -e "${CYAN}  https://github.com/cmakkaya${NC}"
#__ATTR_END__
    echo -e "${YELLOW}============================================================${NC}"
    echo ""
    echo -e "${CYAN}  Server : $HOSTNAME_VAL${NC}"
    echo -e "${CYAN}  Arch   : $ARCH_VAL${NC}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release 2>/dev/null
        echo -e "${CYAN}  Ubuntu : $VERSION_ID${NC}"
    fi
    echo ""
    echo -e "${WHITE}  1) Install [Zabbix Agent 2 $AGENT2_VERSION]${NC}"
    echo -e "${GRAY}     Fresh installation - existing Agent1/Agent2 will be removed${NC}"
    echo ""
    echo -e "${WHITE}  2) Update [Zabbix Agent 1] to [Zabbix Agent 2 $AGENT2_VERSION]${NC}"
    echo -e "${GRAY}     Removes existing Agent1, installs the latest Agent2 $AGENT2_VERSION package${NC}"
    echo ""
    echo -e "${WHITE}  3) Update [Zabbix Agent 2 old version] to [Zabbix Agent 2 $AGENT2_VERSION]${NC}"
    echo -e "${GRAY}     Removes old Agent2, installs the latest Agent2 $AGENT2_VERSION package${NC}"
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
