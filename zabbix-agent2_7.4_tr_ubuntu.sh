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
#  Bu script DevOps Engineer Cumhur M. Akkaya tarafindan hazirlandi.
#  Script hakkindaki onerilerinizi asagidaki adreslerden iletebilirsiniz:
#  https://www.linkedin.com/in/cumhurakkaya/
#  https://cmakkaya.medium.com/
#  https://github.com/cmakkaya
# ============================================================

# -------------------------------------------------------
# FARKLI BIR VERSIYON ICIN
# -------------------------------------------------------
# Farklı bir versiyon kurmak isterseniz hem AGENT2_VERSION
# hem de ZABBIX_REPO_DEB satırının birlikte güncellenmesi gerekir.
# Örnek:
# AGENT2_VERSION="7.0.10"
# ZABBIX_REPO_DEB="https://repo.zabbix.com/zabbix/7.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.0+ubuntu24.04_all.deb"
#
# Güncel versiyonları kontrol etmek için:
# https://repo.zabbix.com/zabbix/

# -------------------------------------------------------
# SABIT DEGISKENLER - Gerekirse buradan duzenleyebilirsiniz
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
# RENK TANIMLARI
# -------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# -------------------------------------------------------
# YARDIMCI FONKSIYON: Baslik satiri yaz
# -------------------------------------------------------
print_banner() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

# -------------------------------------------------------
# YARDIMCI FONKSIYON: Hata mesaji yazdir ve cik
# -------------------------------------------------------
exit_with_error() {
    echo -e "\n${RED}[HATA] $1${NC}"
    echo -e "${RED}Script sonlandiriliyor...${NC}\n"
    exit 1
}

# -------------------------------------------------------
# YARDIMCI FONKSIYON: OK mesaji
# -------------------------------------------------------
print_ok() {
    echo -e "${GREEN}[OK] $1${NC}"
}

# -------------------------------------------------------
# YARDIMCI FONKSIYON: INFO mesaji
# -------------------------------------------------------
print_info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

# -------------------------------------------------------
# YARDIMCI FONKSIYON: UYARI mesaji
# -------------------------------------------------------
print_warn() {
    echo -e "${YELLOW}[UYARI] $1${NC}"
}

# -------------------------------------------------------
# ROOT YETKI KONTROLU
# Ref: https://www.gnu.org/software/bash/manual/bash.html
# -------------------------------------------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "\n${RED}[HATA] Bu script root yetkisi gerektirir.${NC}"
        echo -e "${YELLOW}Lutfen 'sudo -s' veya 'sudo bash $0' ile calistirin.${NC}\n"
        exit 1
    fi
    print_ok "Root yetkisi dogrulandi."
}

# -------------------------------------------------------
# OS KONTROLU (Ubuntu 24.04 olmali)
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/requirements
# -------------------------------------------------------
check_os() {
    print_info "Isletim sistemi kontrol ediliyor..."

    if [ ! -f /etc/os-release ]; then
        exit_with_error "/etc/os-release dosyasi bulunamadi. Ubuntu 24.04 gereklidir."
    fi

    # shellcheck source=/dev/null
    . /etc/os-release

    if [ "$ID" != "ubuntu" ]; then
        exit_with_error "Bu script yalnizca Ubuntu icin tasarlanmistir. Algilanan: $ID"
    fi

    if [ "$VERSION_ID" != "24.04" ]; then
        print_warn "Bu script Ubuntu 24.04 icin optimize edilmistir. Mevcut surum: $VERSION_ID"
        read -rp "  Devam etmek istiyor musunuz? (evet/hayir): " confirm
        if [ "$confirm" != "evet" ]; then
            echo -e "${YELLOW}[INFO] Islem iptal edildi.${NC}"
            exit 0
        fi
    fi

    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ]; then
        exit_with_error "Bu script yalnizca x86_64 (amd64) mimarisini destekler. Algilanan: $ARCH"
    fi

    print_ok "OS: Ubuntu $VERSION_ID | Mimari: $ARCH"
}

# -------------------------------------------------------
# FONKSIYON: Zabbix Agent 1 kaldir
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages
# -------------------------------------------------------
remove_agent1() {
    print_info "Zabbix Agent 1 kontrol ediliyor..."

    if dpkg -l | grep -q "^ii.*zabbix-agent "; then
        print_info "Zabbix Agent 1 bulundu, kaldiriliyor..."

        # Servisi durdur
        # Ref: https://www.freedesktop.org/software/systemd/man/systemctl.html
        systemctl stop "$SERVICE_NAME_A1" 2>/dev/null
        systemctl disable "$SERVICE_NAME_A1" 2>/dev/null
        sleep 2

        # Paketi kaldir
        # Ref: https://manpages.ubuntu.com/manpages/noble/en/man8/apt.8.html
        apt-get remove --purge -y zabbix-agent 2>/dev/null
        apt-get autoremove -y 2>/dev/null

        print_ok "Zabbix Agent 1 basariyla kaldirildi."
    else
        echo -e "${GRAY}[INFO] Zabbix Agent 1 bulunamadi, devam ediliyor.${NC}"
    fi
}

# -------------------------------------------------------
# FONKSIYON: Zabbix Agent 2 eski versiyon kaldir
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages
# -------------------------------------------------------
remove_agent2() {
    print_info "Zabbix Agent 2 kontrol ediliyor..."

    if dpkg -l | grep -q "^ii.*zabbix-agent2 "; then
        INSTALLED_VER=$(dpkg -l zabbix-agent2 2>/dev/null | grep "^ii" | awk '{print $3}' | cut -d: -f2 | cut -d- -f1)
        print_info "Zabbix Agent 2 bulundu. Kurulu versiyon: $INSTALLED_VER"

        # Servisi durdur
        systemctl stop "$SERVICE_NAME" 2>/dev/null
        systemctl disable "$SERVICE_NAME" 2>/dev/null
        sleep 2

        # Config dosyasini yedekle
        if [ -f "$CONFIG_FILE" ]; then
            BACKUP_DATE=$(date +"%d.%m.%Y_%H.%M")
            cp "$CONFIG_FILE" "${CONFIG_FILE}.backup_${BACKUP_DATE}"
            print_info "Mevcut config yedeklendi: ${CONFIG_FILE}.backup_${BACKUP_DATE}"
        fi

        # Paketi kaldir
        apt-get remove --purge -y zabbix-agent2 2>/dev/null
        apt-get autoremove -y 2>/dev/null

        print_ok "Zabbix Agent 2 ($INSTALLED_VER) basariyla kaldirildi."
    else
        echo -e "${GRAY}[INFO] Zabbix Agent 2 bulunamadi, devam ediliyor.${NC}"
    fi
}

# -------------------------------------------------------
# FONKSIYON: Zabbix resmi repo ekle ve paketi kur
# Ref: https://www.zabbix.com/download?zabbix=7.4&os_distribution=ubuntu&os_version=24.04&components=agent_2
# -------------------------------------------------------
install_agent2() {
    print_banner "Zabbix Agent 2 v$AGENT2_VERSION Kuruluyor"

    # Gecici dizine deb indir
    local tmp_deb="/tmp/zabbix-release_7.4_ubuntu24.04.deb"

    print_info "Zabbix resmi deposu ekleniyor..."
    print_info "Kaynak: $ZABBIX_REPO_DEB"

    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/wget.1.html
    wget -q --show-progress -O "$tmp_deb" "$ZABBIX_REPO_DEB" || \
        exit_with_error "Zabbix repo paketi indirilemedi. Internet baglantinizi kontrol edin."

    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/dpkg.1.html
    dpkg -i "$tmp_deb" || exit_with_error "Zabbix repo paketi kurulamadi."
    rm -f "$tmp_deb"

    print_info "Paket listesi guncelleniyor (apt update)..."
    apt-get update -q || exit_with_error "apt update basarisiz."

    print_info "Zabbix Agent 2 kuruluyor (apt install zabbix-agent2)..."
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man8/apt.8.html
    DEBIAN_FRONTEND=noninteractive apt-get install -y zabbix-agent2 || \
        exit_with_error "zabbix-agent2 paketi kurulamadi."

    print_ok "Zabbix Agent 2 paketi basariyla kuruldu."

    # Kurulu versiyonu dogrula
    ACTUAL_VER=$(dpkg -l zabbix-agent2 2>/dev/null | grep "^ii" | awk '{print $3}' | cut -d: -f2 | cut -d- -f1)
    print_info "Kurulu versiyon: $ACTUAL_VER"
}

# -------------------------------------------------------
# FONKSIYON: PSK yapilandirmasi
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys
# -------------------------------------------------------
setup_psk() {
    local agent_hostname="$1"

    echo ""
    echo -e "${CYAN}[PSK] PSK yapilandirmasi baslatiliyor...${NC}"

    # PSK Identity: PSK_<HOSTNAME> formatinda otomatik olustur
    PSK_IDENTITY="PSK_${agent_hostname^^}"
    print_ok "PSK Identity otomatik olusturuldu: $PSK_IDENTITY"

    # PSK Key: kullanicidan al
    echo ""
    echo -e "${YELLOW}[PSK] Lutfen 256-bit (64 karakter) hexadecimal PSK Key degerini girin.${NC}"
    echo -e "${GRAY}[PSK] Ornek: a3f1c2...  (Zabbix Server/Proxy uzerindeki degerle ayni olmali)${NC}"
    echo -e "${GRAY}[PSK] Ref: https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys${NC}"
    echo ""

    local attempt=0
    while true; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt 3 ]; then
            exit_with_error "3 hatali PSK denemesi. Script sonlandiriliyor."
        fi

        read -rp "[PSK] PSK Key girin (64 hex karakter): " PSK_KEY
        PSK_KEY=$(echo "$PSK_KEY" | tr -d '[:space:]')

        # Hex dogrulama - tam 64 karakter, sadece 0-9 ve a-f/A-F
        # Ref: https://www.gnu.org/software/bash/manual/bash.html#Pattern-Matching
        if echo "$PSK_KEY" | grep -qE '^[0-9a-fA-F]{64}$'; then
            print_ok "PSK Key formati gecerli."
            break
        else
            echo -e "${RED}[UYARI] Gecersiz format. Tam 64 hex karakter olmali (sadece 0-9, a-f). Tekrar deneyin.${NC}"
        fi
    done

    # PSK klasorunu olustur
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/mkdir.1.html
    mkdir -p "$PSK_DIR"

    # PSK Key dosyaya kaydet
    echo "$PSK_KEY" > "$PSK_FILE"

    # Dosya izinlerini ayarla - sadece zabbix kullanicisi okuyabilsin
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/chmod.1.html
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/chown.1.html
    chmod 640 "$PSK_FILE"
    chown root:zabbix "$PSK_FILE" 2>/dev/null || chmod 600 "$PSK_FILE"

    print_ok "PSK dosyasi kaydedildi: $PSK_FILE"
    print_ok "PSK dosyasi izinleri ayarlandi (640 - root:zabbix)."
}

# -------------------------------------------------------
# FONKSIYON: Zabbix Agent 2 config dosyasini yapilandir
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2
# -------------------------------------------------------
configure_agent2() {
    local proxy_ip="$1"
    local agent_hostname="$2"
    local psk_identity="$3"

    print_info "Zabbix Agent 2 yapilandiriliyor: $CONFIG_FILE"

    # Log dizinini olustur
    # Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2
    mkdir -p "$LOG_DIR"
    chown zabbix:zabbix "$LOG_DIR" 2>/dev/null || true
    chmod 755 "$LOG_DIR"

    # Mevcut config'i yedekle
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.orig"
        print_info "Orijinal config yedeklendi: ${CONFIG_FILE}.orig"
    fi

    # Config parametrelerini guncelle
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

    # LogFileSize (MB cinsinden max log boyutu)
    sed -i "s|^LogFileSize=.*|LogFileSize=100|" "$CONFIG_FILE"
    grep -q "^LogFileSize=" "$CONFIG_FILE" || echo "LogFileSize=100" >> "$CONFIG_FILE"

    # PSK Encryption parametreleri
    # Ref: https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys
    sed -i "s|^TLSConnect=.*|TLSConnect=psk|" "$CONFIG_FILE"
    grep -q "^TLSConnect=" "$CONFIG_FILE" || echo "TLSConnect=psk" >> "$CONFIG_FILE"

    sed -i "s|^TLSAccept=.*|TLSAccept=psk|" "$CONFIG_FILE"
    grep -q "^TLSAccept=" "$CONFIG_FILE" || echo "TLSAccept=psk" >> "$CONFIG_FILE"

    sed -i "s|^TLSPSKIdentity=.*|TLSPSKIdentity=$psk_identity|" "$CONFIG_FILE"
    grep -q "^TLSPSKIdentity=" "$CONFIG_FILE" || echo "TLSPSKIdentity=$psk_identity" >> "$CONFIG_FILE"

    sed -i "s|^TLSPSKFile=.*|TLSPSKFile=$PSK_FILE|" "$CONFIG_FILE"
    grep -q "^TLSPSKFile=" "$CONFIG_FILE" || echo "TLSPSKFile=$PSK_FILE" >> "$CONFIG_FILE"

    print_ok "Zabbix Agent 2 yapilandirmasi tamamlandi."
}

# -------------------------------------------------------
# FONKSIYON: Config dogrulama
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2
# -------------------------------------------------------
verify_config() {
    local proxy_ip="$1"
    local agent_hostname="$2"

    print_info "Yapilandirma dosyasi dogrulaniyor: $CONFIG_FILE"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_warn "Config dosyasi bulunamadi: $CONFIG_FILE"
        return
    fi

    local all_ok=true
    local params=("Server" "ServerActive" "Hostname" "TLSConnect" "TLSAccept" "TLSPSKIdentity" "TLSPSKFile")

    for param in "${params[@]}"; do
        if grep -qE "^${param}=" "$CONFIG_FILE"; then
            print_ok "Config: $param parametresi mevcut."
        else
            print_warn "Config: $param parametresi eksik veya yorumlu!"
            all_ok=false
        fi
    done

    if [ "$all_ok" = false ]; then
        echo ""
        print_warn "Bazi parametreler eksik gorunuyor."
        print_warn "Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2"
    fi

    # Gercek degerlerle dogrula
    echo ""
    print_info "Config degerleri:"
    grep -E "^Server=|^ServerActive=|^Hostname=|^TLSConnect=|^TLSAccept=|^TLSPSKIdentity=|^TLSPSKFile=" "$CONFIG_FILE" | \
        while read -r line; do
            echo -e "  ${GRAY}$line${NC}"
        done
}

# -------------------------------------------------------
# FONKSIYON: UFW Firewall kurali ekle (port 10050 TCP)
# Ref: https://help.ubuntu.com/community/UFW
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages
# -------------------------------------------------------
add_firewall_rule() {
    print_info "UFW Firewall kontrol ediliyor (port $AGENT2_PORT/TCP)..."

    # UFW kurulu mu kontrol et
    if ! command -v ufw &>/dev/null; then
        print_warn "UFW bulunamadi. Firewall kurali eklenemiyor. Manuel olarak ekleyin."
        return
    fi

    # UFW aktif mi kontrol et
    UFW_STATUS=$(ufw status | head -1)
    if echo "$UFW_STATUS" | grep -q "inactive"; then
        print_warn "UFW aktif degil. Kural ekleniyor ancak UFW etkin degildir."
        print_warn "UFW'yi etkinlestirmek icin: ufw enable"
    fi

    # Mevcut kural varsa sil, yenisini ekle
    ufw delete allow "$AGENT2_PORT/tcp" 2>/dev/null || true

    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man8/ufw.8.html
    ufw allow "$AGENT2_PORT/tcp" comment "Zabbix Agent 2 v$AGENT2_VERSION" 2>/dev/null

    print_ok "UFW kurali eklendi: TCP/$AGENT2_PORT (inbound allow)"
}

# -------------------------------------------------------
# FONKSIYON: Servisi baslat ve dogrula
# Ref: https://www.freedesktop.org/software/systemd/man/systemctl.html
# -------------------------------------------------------
verify_service() {
    print_info "Zabbix Agent 2 servisi baslatiliyor..."

    # Servisi etkinlestir ve baslat
    systemctl enable "$SERVICE_NAME" 2>/dev/null
    systemctl restart "$SERVICE_NAME" 2>/dev/null
    sleep 3

    # Servis durumunu kontrol et
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        START_TIME=$(systemctl show "$SERVICE_NAME" --property=ActiveEnterTimestamp | cut -d= -f2)
        print_ok "Zabbix Agent 2 servisi CALISIYOR."
        print_ok "Baslangic zamani: $START_TIME"

        # Servis detaylarini goster
        echo ""
        print_info "Servis durumu:"
        systemctl status "$SERVICE_NAME" --no-pager -l | head -20
    else
        echo -e "${RED}[HATA] Servis baslamiyor. Detaylar:${NC}"
        systemctl status "$SERVICE_NAME" --no-pager -l
        echo ""
        print_warn "Log dosyasini kontrol edin: $LOG_DIR/zabbix_agent2.log"
        print_warn "Veya: journalctl -u zabbix-agent2 -n 50"
    fi
}

# -------------------------------------------------------
# FONKSIYON: Kurulum ozeti yazdir - kullanici kapatana kadar bekle
# -------------------------------------------------------
write_summary() {
    local agent_hostname="$1"
    local proxy_ip="$2"
    local psk_identity="$3"

    # Hostname IP adresini al
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/hostname.1.html
    HOST_IP=$(hostname -I | awk '{print $1}')
    TARIH=$(date +"%d.%m.%Y %H:%M")

    clear
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}  KURULUM BASARIYLA TAMAMLANDI${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${WHITE}  Tarih        : $TARIH${NC}"
    echo -e "${WHITE}  Hostname     : $agent_hostname${NC}"
    echo -e "${WHITE}  Hostname IP  : $HOST_IP${NC}"
    echo -e "${WHITE}  Proxy IP     : $proxy_ip${NC}"
    echo -e "${CYAN}  PSK Identity : $psk_identity${NC}"
    echo ""
    echo -e "${YELLOW}============================================================${NC}"
    echo -e "${YELLOW}  [!] ONEMLI - PROXY TARAFINDA YAPILMASI GEREKENLER${NC}"
    echo -e "${YELLOW}============================================================${NC}"
    echo ""
    echo -e "${WHITE}  Zabbix Web UI uzerinde bu host icin PSK tanimlamasi${NC}"
    echo -e "${WHITE}  yapilmadan agent baglanti kuramaz!${NC}"
    echo ""
    echo -e "${YELLOW}  Adimlar:${NC}"
    echo -e "${WHITE}  1) Zabbix Web UI -> Configuration -> Hosts${NC}"
    echo -e "${WHITE}  2) Bu sunucuyu secin -> [Encryption] sekmesi${NC}"
    echo -e "${WHITE}  3) Asagidaki degerleri girin:${NC}"
    echo ""
    echo -e "${CYAN}     Connections to host   : PSK${NC}"
    echo -e "${CYAN}     Connections from host : PSK${NC}"
    echo -e "${CYAN}     PSK Identity          : $psk_identity${NC}"
    echo -e "${CYAN}     PSK (Key)             : Kurulum esnasinda verdiginiz PSK Key degerini giriniz.${NC}"
    echo ""
    echo -e "${GRAY}  Ref: https://www.zabbix.com/documentation/7.4/en/manual/${NC}"
    echo -e "${GRAY}       encryption/using_pre_shared_keys${NC}"
    echo ""
    echo -e "${CYAN}  Bu script DevOps Engineer Cumhur M. Akkaya tarafindan hazirlandi.${NC}"
    echo -e "${CYAN}  Script hakkindaki onerilerinizi asagidaki adreslerden iletebilirsiniz:${NC}"
    echo -e "${CYAN}  https://www.linkedin.com/in/cumhurakkaya/${NC}"
    echo -e "${CYAN}  https://cmakkaya.medium.com/${NC}"
    echo -e "${CYAN}  https://github.com/cmakkaya${NC}"
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${WHITE}  Yukardaki bilgileri not aldiktan sonra${NC}"
    echo -e "${WHITE}  ENTER'a basarak bu pencereyi kapatabilirsiniz.${NC}"
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo ""

    # Kullanici ENTER'a basana kadar bekle
    read -rp "  >> ENTER'a basin: "
}

# -------------------------------------------------------
# ANA KURULUM AKISI: Install / Upgrade
# -------------------------------------------------------
start_install() {
    local mode="$1"   # fresh | upgrade1 | upgrade2

    case "$mode" in
        fresh)
            print_banner "Zabbix Agent 2 v$AGENT2_VERSION - Yeni Kurulum"
            remove_agent1
            remove_agent2
            ;;
        upgrade1)
            print_banner "Zabbix Agent 1 -> Agent 2 v$AGENT2_VERSION Guncelleme"

            # Agent 1 kurulu mu kontrol et
            if ! dpkg -l | grep -q "^ii.*zabbix-agent "; then
                print_warn "Zabbix Agent 1 bulunamadi."
                read -rp "  Devam etmek icin 'evet' yazin, iptal icin baska bir sey: " confirm
                if [ "$confirm" != "evet" ]; then
                    print_info "Islem iptal edildi. Ana menuye donuluyor..."
                    sleep 2
                    show_menu
                    return
                fi
            fi
            remove_agent1
            remove_agent2
            ;;
        upgrade2)
            print_banner "Zabbix Agent 2 (Eski Surum) -> v$AGENT2_VERSION Guncelleme"

            # Agent 2 kurulu mu kontrol et
            if ! dpkg -l | grep -q "^ii.*zabbix-agent2 "; then
                print_warn "Zabbix Agent 2 bulunamadi."
                read -rp "  Devam etmek icin 'evet' yazin, iptal icin baska bir sey: " confirm
                if [ "$confirm" != "evet" ]; then
                    print_info "Islem iptal edildi. Ana menuye donuluyor..."
                    sleep 2
                    show_menu
                    return
                fi
            else
                INSTALLED_VER=$(dpkg -l zabbix-agent2 2>/dev/null | grep "^ii" | awk '{print $3}' | cut -d: -f2 | cut -d- -f1)
                if [ "$INSTALLED_VER" = "$AGENT2_VERSION" ]; then
                    print_warn "Zabbix Agent 2 v$AGENT2_VERSION zaten kurulu!"
                    read -rp "  Yeniden kurmak icin 'evet' yazin, iptal icin baska bir sey: " confirm
                    if [ "$confirm" != "evet" ]; then
                        show_menu
                        return
                    fi
                fi
            fi
            remove_agent2
            ;;
    esac

    # Proxy IP al
    echo -e "${CYAN}[INPUT] Zabbix Proxy IP adresini girin:${NC}"
    PROXY_IP=""
    while ! echo "$PROXY_IP" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; do
        read -rp "  Proxy IP: " PROXY_IP
        PROXY_IP=$(echo "$PROXY_IP" | tr -d '[:space:]')
        if ! echo "$PROXY_IP" | grep -qE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'; then
            echo -e "${RED}  [UYARI] Gecersiz IP formati, tekrar deneyin (ornek: 192.168.1.10)${NC}"
        fi
    done

    # Hostname otomatik al
    # Ref: https://manpages.ubuntu.com/manpages/noble/en/man1/hostname.1.html
    AGENT_HOSTNAME=$(hostname)
    print_ok "Hostname otomatik alindi: $AGENT_HOSTNAME"

    # Agent 2 kur
    install_agent2

    # PSK yapilandir
    setup_psk "$AGENT_HOSTNAME"

    # Config yapilandir
    configure_agent2 "$PROXY_IP" "$AGENT_HOSTNAME" "$PSK_IDENTITY"

    # Firewall
    add_firewall_rule

    # Config dogrula
    verify_config "$PROXY_IP" "$AGENT_HOSTNAME"

    # Servisi baslat ve dogrula
    verify_service

    # Ozet
    write_summary "$AGENT_HOSTNAME" "$PROXY_IP" "$PSK_IDENTITY"
}

# -------------------------------------------------------
# ANA MENU
# -------------------------------------------------------
show_menu() {
    clear
    HOSTNAME_VAL=$(hostname)
    ARCH_VAL=$(uname -m)

    echo ""
    echo -e "${YELLOW}============================================================${NC}"
    echo -e "${YELLOW}  Zabbix Agent 2 v$AGENT2_VERSION Kurulum Scriptine Hosgeldiniz.${NC}"
    echo -e "${YELLOW}  Ubuntu 24.04 LTS | amd64 | apt | icin hazirlandi.${NC}"
    echo ""
    echo -e "${GRAY}  Ref: https://www.zabbix.com/download?zabbix=7.4&os_distribution=ubuntu&os_version=24.04&components=agent_2&db=&ws="
    echo ""
    echo -e "${CYAN}  Bu script DevOps Engineer Cumhur M. Akkaya tarafindan hazirlandi.${NC}"
    echo -e "${CYAN}  Script hakkindaki onerilerinizi asagidaki adreslerden iletebilirsiniz:${NC}"
    echo -e "${CYAN}  https://www.linkedin.com/in/cumhurakkaya/${NC}"
    echo -e "${CYAN}  https://cmakkaya.medium.com/${NC}"
    echo -e "${CYAN}  https://github.com/cmakkaya${NC}"
    echo -e "${YELLOW}============================================================${NC}"
    echo ""
    echo -e "${CYAN}  Sunucu : $HOSTNAME_VAL${NC}"
    echo -e "${CYAN}  Mimari : $ARCH_VAL${NC}"
    echo ""
    echo -e "${WHITE}  1) Install [Zabbix Agent 2 v$AGENT2_VERSION]${NC}"
    echo -e "${GRAY}     Temiz kurulum - Agent1/Agent2 varsa kaldirilir${NC}"
    echo ""
    echo -e "${WHITE}  2) Update [Zabbix Agent 1] to [Zabbix Agent 2 v$AGENT2_VERSION]${NC}"
    echo -e "${GRAY}     Mevcut Agent1 kaldirilir, Agent2 v$AGENT2_VERSION kurulur${NC}"
    echo ""
    echo -e "${WHITE}  3) Update [Zabbix Agent 2] to [Zabbix Agent 2 v$AGENT2_VERSION]${NC}"
    echo -e "${GRAY}     Eski Agent2 kaldirilir, Agent2 v$AGENT2_VERSION kurulur${NC}"
    echo ""
    echo -e "${GRAY}  0) Cikis${NC}"
    echo ""
    echo -e "${YELLOW}============================================================${NC}"
    echo ""
    echo -e "${YELLOW}  On Hazirlik:${NC}"
    echo -e "${WHITE}  Eger bir PSK Key'iniz yoksa, kuruluma baslamadan once${NC}"
    echo -e "${WHITE}  asagidaki komutlarla olusturup, kurulumda kullanmak uzere kopyalayiniz.${NC}"
    echo ""
    echo -e "${CYAN}  01. PSK Key olusturmak icin:${NC}"
    echo -e "${WHITE}      openssl rand -hex 32${NC}"
    echo ""
    echo -e "${CYAN}  02. PSK Key'iniz alttakine benzer bir formatta gozukecektir:${NC}"
    echo -e "${GRAY}      34f6889e280e51dda96a4b3fc7732f3cd77f50ec4443271b3dc227dae1938fca${NC}"
    echo ""
    echo -e "${YELLOW}============================================================${NC}"
    echo ""

    local invalid_count=0

    while true; do
        read -rp "  Islem Seciniz [1/2/3/0]: " choice
        case "$choice" in
            1) start_install "fresh";    return ;;
            2) start_install "upgrade1"; return ;;
            3) start_install "upgrade2"; return ;;
            0)
                echo -e "\n${YELLOW}[INFO] Script sonlandiriliyor.${NC}\n"
                exit 0
                ;;
            *)
                invalid_count=$((invalid_count + 1))
                echo -e "${RED}  [UYARI] Gecersiz secim. Lutfen 1, 2, 3 veya 0 girin.${NC}"
                if [ "$invalid_count" -ge 3 ]; then
                    exit_with_error "Maksimum gecersiz deneme sayisina ulasildi."
                fi
                ;;
        esac
    done
}

# -------------------------------------------------------
# BASLANGIC NOKTASI
# -------------------------------------------------------
check_root
check_os
show_menu
