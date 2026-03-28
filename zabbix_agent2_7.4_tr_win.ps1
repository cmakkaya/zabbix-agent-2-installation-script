#  ============================================================
#  Script Name:    Install-ZabbixAgent2.ps1
#  Version:        1.0
#  Description:    Zabbix Agent 2 v7.4.8 Silent Installer
#                  - Fresh install (MSI)
#                  - Upgrade from Zabbix Agent 1 (ZIP-based)
#                  - Upgrade from Zabbix Agent 2 old version (MSI or ZIP)
#                  - PSK encryption support
#                  - Windows Firewall rule (port 10050)
#                  - Log to C:\Zabbix\Logs
#  Target OS:      Windows Server 2016+ (amd64)
#  Zabbix Version: 7.4.8 (Agent 2, OpenSSL, MSI)
#  Download URL:   https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.8/
#                  zabbix_agent2-7.4.8-windows-amd64-openssl.msi
#  References:
#    [1] Zabbix Agent 2 Windows Install:
#        https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi
#    [2] Zabbix PSK Encryption:
#        https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys
#    [3] Zabbix Agent 2 Config Parameters:
#        https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2_win
#    [4] MSI Silent Install (msiexec):
#        https://learn.microsoft.com/en-us/windows/win32/msi/command-line-options
#    [5] Windows Firewall via PowerShell:
#        https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule
#  ============================================================

# -------------------------------------------------------
# ZABBIX AGENT2'NIN FARKLI BIR VERSIYONUNU YÜKLEMEK ICIN
# -------------------------------------------------------
# Farklı bir versiyon kurmak istersenniz hem AGENT2_VERSION hem de AGENT2_MSI_URL satırının birlikte güncellenmesi gerekir,alttaki "SABIT DEGISKENLER" bölümünde.
# Örnek:
# $AGENT2_VERSION     = "7.0.24"
# $AGENT2_MSI_URL     = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/7.0.24/zabbix_agent-7.0.24-windows-amd64-openssl.msi"

# Güncel Versiyonları bu sayfadan kontrol edebilirsiniz:
# https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.8/zabbix_agent-7.4.8-windows-amd64-openssl.msi

# -------------------------------------------------------
# SABIT DEGISKENLER - Gerekirse buradan duzenleyebilirsiniz:
# -------------------------------------------------------
$AGENT2_VERSION     = "7.4.8"
$AGENT2_MSI_URL     = "https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.8/zabbix_agent2-7.4.8-windows-amd64-openssl.msi"
$INSTALL_DIR        = "C:\Program Files\Zabbix Agent 2"
$CONFIG_FILE        = "$INSTALL_DIR\zabbix_agent2.conf"
$LOG_DIR            = "C:\Zabbix\Logs"
$LOG_FILE           = "$LOG_DIR\zabbix_agent2.log"
$PSK_DIR            = "C:\Zabbix\PSK"
$PSK_FILE           = "$PSK_DIR\zabbix_agent.psk"
$AGENT2_PORT        = 10050
$AGENT2_EXE         = "$INSTALL_DIR\bin\zabbix_agent2.exe"
$SERVICE_NAME_A1    = "Zabbix Agent"
$SERVICE_NAME_A2    = "Zabbix Agent 2"
$FW_RULE_NAME       = "Zabbix Agent 2 - Port $AGENT2_PORT"

# -------------------------------------------------------
# ADMIN YETKI KONTROLU & OTOMATIK YENIDEN BASLATMA
# Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/
# -------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "`nYonetici yetkisi gerekli. Script yeniden baslatiliyor (Run as Administrator)...`n" -ForegroundColor Yellow
    Start-Process PowerShell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`"" -Verb RunAs
    exit
}

# Bug Fix - TEMP path icin sembolik link sorununu onle
# Ref: https://github.com/PowerShell/PowerShell/issues/17359
$envTEMP = (Get-Item -LiteralPath $env:TEMP).FullName

Clear-Host

# -------------------------------------------------------
# POWERSHELL SURUM KONTROLU (minimum 5.1)
# Ref: https://learn.microsoft.com/en-us/powershell/scripting/windows-powershell/
# -------------------------------------------------------
$minPS = [Version]"5.1"
if ($PSVersionTable.PSVersion -lt $minPS) {
    Write-Host "`n[HATA] Bu script PowerShell $minPS veya uzeri gerektirir.`n" -ForegroundColor Red
    Write-Host "Mevcut surum: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host "`nScript 5 saniye icinde sonlanacak...`n" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

# -------------------------------------------------------
# MIMARI KONTROLU (sadece amd64 destekleniyor)
# -------------------------------------------------------
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -ne "AMD64") {
    Write-Host "`n[HATA] Bu script yalnizca AMD64 (x64) mimarisini destekler.`n" -ForegroundColor Red
    Write-Host "Algilanan mimari: $arch" -ForegroundColor Red
    Write-Host "`nScript 5 saniye icinde sonlanacak...`n" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

# -------------------------------------------------------
# YARDIMCI FONKSIYON: Renkli baslik satiri yaz
# -------------------------------------------------------
function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host ("=" * 60) -ForegroundColor $Color
    Write-Host ""
}

# -------------------------------------------------------
# YARDIMCI FONKSIYON: Yuksek etkili hata mesaji & cikis
# -------------------------------------------------------
function Exit-WithError {
    param([string]$Message)
    Write-Host "`n[HATA] $Message`n" -ForegroundColor Red
    Write-Host "Script 5 saniye icinde sonlanacak..." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

# -------------------------------------------------------
# YARDIMCI FONKSIYON: TLS protokollerini etkinlestir
# Ref: https://learn.microsoft.com/en-us/dotnet/api/system.net.servicepointmanager.securityprotocol
# -------------------------------------------------------
function Enable-TLS {
    $protocols = 'Tls12,Tls13' -split ',' | Where-Object {
        [System.Enum]::IsDefined([System.Net.SecurityProtocolType], $_)
    }
    [System.Net.ServicePointManager]::SecurityProtocol = $protocols -join ','
    Write-Host "[INFO] Aktif guvenlik protokolleri: $([System.Net.ServicePointManager]::SecurityProtocol)" -ForegroundColor DarkGray
}

# -------------------------------------------------------
# YARDIMCI FONKSIYON: Klasor olustur (yoksa)
# -------------------------------------------------------
function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "[INFO] Klasor olusturuldu: $Path" -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# FONKSIYON: Zabbix Agent 1 (ZIP tabanli) kaldir
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi#uninstalling
# -------------------------------------------------------
function Remove-Agent1 {
    Write-Host "[INFO] Zabbix Agent 1 kontrol ediliyor..." -ForegroundColor Yellow

    $proc    = Get-WmiObject -Class Win32_Process -Filter 'Name="zabbix_agentd.exe"' -ErrorAction SilentlyContinue
    $service = Get-WmiObject -Class Win32_Service  -Filter "Name=`"$SERVICE_NAME_A1`"" -ErrorAction SilentlyContinue

    if ($proc) {
        $exePath    = $proc.ExecutablePath
        $agentDir   = Split-Path (Split-Path $exePath)
        $confPath   = "$agentDir\conf\zabbix_agentd.conf"

        Write-Host "[INFO] Zabbix Agent 1 servisi durduruluyor..." -ForegroundColor Yellow
        & $exePath --config $confPath --stop 2>$null
        Start-Sleep -Seconds 3

        Write-Host "[INFO] Zabbix Agent 1 kaldiriliyor..." -ForegroundColor Yellow
        & $exePath --config $confPath --uninstall 2>$null
        Start-Sleep -Seconds 3

        if (Test-Path $agentDir) {
            Remove-Item $agentDir -Force -Recurse -ErrorAction SilentlyContinue
        }
        Write-Host "[OK] Zabbix Agent 1 basariyla kaldirildi." -ForegroundColor Green
    }
    elseif ($service) {
        Write-Host "[INFO] Zabbix Agent 1 servisi durduruluyor ve siliniyor..." -ForegroundColor Yellow
        $null = $service.StopService()
        Start-Sleep -Seconds 2
        $null = $service.Delete()
        Write-Host "[OK] Zabbix Agent 1 servisi silindi." -ForegroundColor Green
    }
    else {
        Write-Host "[INFO] Zabbix Agent 1 bulunamadi, devam ediliyor." -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# FONKSIYON: Zabbix Agent 2 (MSI veya ZIP) kaldir
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi#uninstalling
# Ref: https://learn.microsoft.com/en-us/windows/win32/msi/command-line-options (MsiExec /x)
# -------------------------------------------------------
function Remove-Agent2 {
    Write-Host "[INFO] Zabbix Agent 2 kontrol ediliyor..." -ForegroundColor Yellow

    # --- MSI ile kurulmus Agent 2 varsa kaldir ---
    # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-wmiobject
    $msiProduct = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -like "*Zabbix Agent 2*" }

    if ($msiProduct) {
        $installedVer = $msiProduct.Version
        Write-Host "[INFO] MSI ile kurulmus Zabbix Agent 2 bulundu: v$installedVer" -ForegroundColor Yellow
        Write-Host "[INFO] MSI kaldirilıyor (msiexec /x)..." -ForegroundColor Yellow

        # Servisi once durdur
        $svc = Get-Service -Name $SERVICE_NAME_A2 -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            Stop-Service -Name $SERVICE_NAME_A2 -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }

        # MSI silent uninstall
        # Ref: https://learn.microsoft.com/en-us/windows/win32/msi/command-line-options
        $uninstallArgs = "/x `"$($msiProduct.IdentifyingNumber)`" /quiet /norestart"
        $proc = Start-Process "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru -NoNewWindow
        Start-Sleep -Seconds 5

        if ($proc.ExitCode -ne 0) {
            Write-Host "[UYARI] MSI kaldirma cikis kodu: $($proc.ExitCode) - Manuel kontrol onerilir." -ForegroundColor Yellow
        } else {
            Write-Host "[OK] Zabbix Agent 2 MSI basariyla kaldirildi." -ForegroundColor Green
        }
    }

    # --- ZIP (legacy) tabanli Agent 2 varsa kaldir ---
    $proc2   = Get-WmiObject -Class Win32_Process -Filter 'Name="zabbix_agent2.exe"' -ErrorAction SilentlyContinue
    $service2 = Get-WmiObject -Class Win32_Service -Filter "Name=`"$SERVICE_NAME_A2`"" -ErrorAction SilentlyContinue

    if ($proc2) {
        $exePath2  = $proc2.ExecutablePath
        $agentDir2 = Split-Path (Split-Path $exePath2)
        $confPath2 = "$agentDir2\conf\zabbix_agent2.conf"

        Write-Host "[INFO] ZIP tabanli Zabbix Agent 2 durduruluyor..." -ForegroundColor Yellow
        & $exePath2 --config $confPath2 --stop 2>$null
        Start-Sleep -Seconds 3
        & $exePath2 --config $confPath2 --uninstall 2>$null
        Start-Sleep -Seconds 3

        if (Test-Path $agentDir2) {
            Remove-Item $agentDir2 -Force -Recurse -ErrorAction SilentlyContinue
        }
        Write-Host "[OK] ZIP tabanli Zabbix Agent 2 kaldirildi." -ForegroundColor Green
    }
    elseif ($service2) {
        Write-Host "[INFO] Kalan Zabbix Agent 2 servisi siliniyor..." -ForegroundColor Yellow
        $null = $service2.StopService()
        Start-Sleep -Seconds 2
        $null = $service2.Delete()

        # Registry kalintisini temizle
        # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/remove-item
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\$SERVICE_NAME_A2"
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Registry anahtari temizlendi." -ForegroundColor Green
        }
        Write-Host "[OK] Zabbix Agent 2 servisi silindi." -ForegroundColor Green
    }

    # Eski kurulum dizinini temizle (MSI birakmissa)
    if (Test-Path $INSTALL_DIR) {
        Remove-Item $INSTALL_DIR -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "[INFO] Eski kurulum dizini temizlendi: $INSTALL_DIR" -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# FONKSIYON: MSI indir
# Ref: https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.8/
# -------------------------------------------------------
function Download-Agent2MSI {
    $msiPath = "$envTEMP\zabbix_agent2_748.msi"

    Write-Host "[INFO] Zabbix Agent 2 v$AGENT2_VERSION indiriliyor..." -ForegroundColor Yellow
    Write-Host "[INFO] Kaynak: $AGENT2_MSI_URL" -ForegroundColor DarkGray
    Enable-TLS

    try {
        # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($AGENT2_MSI_URL, $msiPath)
    }
    catch {
        Exit-WithError "MSI indirme basarisiz: $_"
    }

    if (-not (Test-Path $msiPath)) {
        Exit-WithError "MSI dosyasi bulunamadi: $msiPath"
    }

    $fileSize = (Get-Item $msiPath).Length
    Write-Host "[OK] Indirme tamamlandi. Dosya boyutu: $([math]::Round($fileSize/1MB,2)) MB" -ForegroundColor Green
    return $msiPath
}

# -------------------------------------------------------
# FONKSIYON: PSK olustur / kullanicidan al
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys
# -------------------------------------------------------
function Setup-PSK {
    param([string]$AgentHostname)

    Write-Host ""
    Write-Host "[PSK] PSK yapilandirmasi baslatiliyor..." -ForegroundColor Cyan

    # PSK Identity: PSK_<HOSTNAME> formatinda otomatik olustur
    $pskIdentity = "PSK_$($AgentHostname.ToUpper())"
    Write-Host "[PSK] PSK Identity otomatik olusturuldu: $pskIdentity" -ForegroundColor Green

    # PSK Key: kullanicidan al
    Write-Host ""
    Write-Host "[PSK] Lutfen 256-bit (64 karakter) hexadecimal PSK Key degerini girin." -ForegroundColor Yellow
    Write-Host "[PSK] Ornek: a3f1c2...  (Zabbix Server/Proxy uzerindeki degerle ayni olmali)" -ForegroundColor DarkGray
    Write-Host "[PSK] Ref: https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys" -ForegroundColor DarkGray
    Write-Host ""

    $pskKey = ""
    $attempt = 0
    while ($true) {
        $attempt++
        if ($attempt -gt 3) {
            Exit-WithError "3 hatali PSK denemesi. Script sonlandiriliyor."
        }
        $pskKey = Read-Host "[PSK] PSK Key girin (64 hex karakter)"
        $pskKey = $pskKey.Trim()

        # Hex dogrulama - tam 64 karakter, sadece 0-9 ve a-f/A-F
        if ($pskKey -match '^[0-9a-fA-F]{64}$') {
            Write-Host "[OK] PSK Key formati gecerli." -ForegroundColor Green
            break
        }
        else {
            Write-Host "[UYARI] Gecersiz format. Tam 64 hex karakter olmali (sadece 0-9, a-f). Tekrar deneyin." -ForegroundColor Red
        }
    }

    # PSK klasorunu olustur ve dosyaya kaydet
    Ensure-Directory $PSK_DIR

    # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-content
    Set-Content -Path $PSK_FILE -Value $pskKey -Encoding ASCII -Force
    Write-Host "[OK] PSK dosyasi kaydedildi: $PSK_FILE" -ForegroundColor Green

    # PSK dosyasini koruma altina al (sadece LocalSystem okuyabilsin)
    # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-acl
    try {
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $acl.SetAccessRuleProtection($true, $false)

        $sidSystem = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        $sidAdmins = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)

        $ruleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule($sidSystem, "FullControl", "Allow")
        $ruleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule($sidAdmins, "FullControl", "Allow")

        $acl.AddAccessRule($ruleSystem)
        $acl.AddAccessRule($ruleAdmins)
        Set-Acl -Path $PSK_FILE -AclObject $acl
        Write-Host "[OK] PSK dosyasi izinleri guvence altina alindi (LocalSystem + Administrators)." -ForegroundColor Green
    }
    catch {
        Write-Host "[UYARI] PSK dosyasi izinleri ayarlanamadi: $_ - Manuel olarak kontrol edin." -ForegroundColor Yellow
    }

    return @{
        Identity = $pskIdentity
        KeyFile  = $PSK_FILE
    }
}

# -------------------------------------------------------
# FONKSIYON: MSI silent kurulumu yap
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi
# Ref: https://learn.microsoft.com/en-us/windows/win32/msi/command-line-options
# -------------------------------------------------------
function Install-Agent2MSI {
    param(
        [string]$MsiPath,
        [string]$ProxyIP,
        [string]$AgentHostname,
        [string]$PskIdentity,
        [string]$PskKeyFile
    )

    Write-Host "[INFO] Zabbix Agent 2 v$AGENT2_VERSION MSI ile kuruluyor..." -ForegroundColor Yellow
    Write-Host "[INFO] Hedef dizin: $INSTALL_DIR" -ForegroundColor DarkGray

    Ensure-Directory $LOG_DIR

    # MSI parametre referansi:
    # Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi#installation-parameters
    $msiArgs = @(
        "/i", "`"$MsiPath`"",
        "/quiet",
        "/norestart",
        "/l*v", "`"$LOG_DIR\msi_install.log`"",
        "INSTALLDIR=`"$INSTALL_DIR`"",
        "SERVER=`"$ProxyIP`"",
        "SERVERACTIVE=`"$ProxyIP`"",
        "HOSTNAME=`"$AgentHostname`"",
        "LOGFILE=`"$LOG_FILE`"",
        "ENABLEPATH=1",
        "TLSCONNECT=psk",
        "TLSACCEPT=psk",
        "TLSPSKIDENTITY=`"$PskIdentity`"",
        "TLSPSKFILE=`"$PskKeyFile`""
    )

    Write-Host "[INFO] MSI kurulum parametreleri hazirlandı." -ForegroundColor DarkGray
    Write-Host "[INFO] Kurulum basliyor, lutfen bekleyin..." -ForegroundColor Yellow

    # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process
    $proc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
    Start-Sleep -Seconds 5

    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        # 3010 = kurulum basarili, yeniden baslatma gerekiyor (reboot required) - bu normal
        Exit-WithError "MSI kurulumu basarisiz. Cikis kodu: $($proc.ExitCode). Log: $LOG_DIR\msi_install.log"
    }

    if ($proc.ExitCode -eq 3010) {
        Write-Host "[UYARI] Kurulum basarili. Sistem yeniden baslatilmali (ExitCode: 3010)." -ForegroundColor Yellow
    }

    Write-Host "[OK] Zabbix Agent 2 v$AGENT2_VERSION kurulumu tamamlandi." -ForegroundColor Green
}

# -------------------------------------------------------
# FONKSIYON: Config dosyasini dogrula ve PSK satirlarini kontrol et
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2_win
# -------------------------------------------------------
function Verify-Config {
    param([string]$ProxyIP, [string]$AgentHostname)

    Write-Host "[INFO] Yapilandirma dosyasi dogrulaniyor: $CONFIG_FILE" -ForegroundColor Yellow

    if (-not (Test-Path $CONFIG_FILE)) {
        Write-Host "[UYARI] Config dosyasi bulunamadi: $CONFIG_FILE" -ForegroundColor Yellow
        Write-Host "[UYARI] MSI kurulumu config dosyasini farkli bir konuma yazmiş olabilir." -ForegroundColor Yellow
        return
    }

    $confContent = Get-Content $CONFIG_FILE -Raw

    # Kritik parametreleri kontrol et
    $checks = @{
        "Server"          = $ProxyIP
        "ServerActive"    = $ProxyIP
        "Hostname"        = $AgentHostname
        "TLSConnect"      = "psk"
        "TLSAccept"       = "psk"
        "TLSPSKIdentity"  = ""  # sadece varligini kontrol et
        "TLSPSKFile"      = ""  # sadece varligini kontrol et
    }

    $allOk = $true
    foreach ($key in $checks.Keys) {
        if ($confContent -match "(?m)^$key=") {
            Write-Host "[OK] Config: $key parametresi mevcut." -ForegroundColor Green
        } else {
            Write-Host "[UYARI] Config: $key parametresi eksik veya yorumlu!" -ForegroundColor Yellow
            $allOk = $false
        }
    }

    if (-not $allOk) {
        Write-Host ""
        Write-Host "[UYARI] Config bazi parametreler eksik gorunuyor." -ForegroundColor Yellow
        Write-Host "[UYARI] Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2_win" -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# FONKSIYON: Windows Firewall kurali ekle (port 10050 TCP)
# Ref: https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi#firewall
# -------------------------------------------------------
function Add-FirewallRule {
    Write-Host "[INFO] Windows Firewall kurali kontrol ediliyor (port $AGENT2_PORT/TCP)..." -ForegroundColor Yellow

    # Mevcut kural varsa sil (guncelle)
    $existingRule = Get-NetFirewallRule -DisplayName $FW_RULE_NAME -ErrorAction SilentlyContinue
    if ($existingRule) {
        Remove-NetFirewallRule -DisplayName $FW_RULE_NAME -ErrorAction SilentlyContinue
        Write-Host "[INFO] Mevcut firewall kurali guncelleniyor..." -ForegroundColor DarkGray
    }

    # Yeni kural ekle
    # Ref: https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule
    try {
        New-NetFirewallRule `
            -DisplayName $FW_RULE_NAME `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $AGENT2_PORT `
            -Action Allow `
            -Profile Any `
            -Description "Zabbix Agent 2 v$AGENT2_VERSION - Otomatik olusturuldu" `
            -ErrorAction Stop | Out-Null

        Write-Host "[OK] Firewall kurali eklendi: '$FW_RULE_NAME' (TCP/$AGENT2_PORT inbound allow)" -ForegroundColor Green
    }
    catch {
        Write-Host "[UYARI] Firewall kurali eklenemedi: $_ - Manuel olarak ekleyin." -ForegroundColor Yellow
    }
}

# -------------------------------------------------------
# FONKSIYON: Servis baslatildiktan sonra dogrula
# Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-service
# -------------------------------------------------------
function Verify-Service {
    Write-Host "[INFO] Zabbix Agent 2 servisi kontrol ediliyor..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3

    $service = Get-Service -Name $SERVICE_NAME_A2 -ErrorAction SilentlyContinue

    if (-not $service) {
        Write-Host "[UYARI] '$SERVICE_NAME_A2' servisi bulunamadi. Kurulum kontrolunu gerceklestirin." -ForegroundColor Yellow
        return
    }

    if ($service.Status -ne "Running") {
        Write-Host "[UYARI] Servis calısmiyor ($($service.Status)). Baslatiliyor..." -ForegroundColor Yellow
        try {
            Start-Service -Name $SERVICE_NAME_A2 -ErrorAction Stop
            Start-Sleep -Seconds 3
            $service.Refresh()
        }
        catch {
            Write-Host "[HATA] Servis baslatılamadi: $_" -ForegroundColor Red
            Write-Host "[HATA] Windows Event Log veya $LOG_FILE dosyasini kontrol edin." -ForegroundColor Red
            return
        }
    }

    $service.Refresh()
    if ($service.Status -eq "Running") {
        $startTime = (Get-Process -Name "zabbix_agent2" -ErrorAction SilentlyContinue | Select-Object -First 1).StartTime
        if ($startTime) {
            Write-Host "[OK] Zabbix Agent 2 servisi CALISIYOR. Baslangic zamani: $startTime" -ForegroundColor Green
        } else {
            Write-Host "[OK] Zabbix Agent 2 servisi CALISIYOR." -ForegroundColor Green
        }
    } else {
        Write-Host "[HATA] Servis hala calısmiyor. Durum: $($service.Status)" -ForegroundColor Red
    }
}

# -------------------------------------------------------
# FONKSIYON: Kurulum ozeti yazdir - kullanici kapatana kadar bekle
# -------------------------------------------------------
function Write-Summary {
    param(
        [string]$AgentHostname,
        [string]$ProxyIP,
        [string]$PskIdentity
    )

    # Hostname'e ait yerel IP adresini al
    # Ref: https://learn.microsoft.com/en-us/dotnet/api/system.net.dns.gethostaddresses
    $hostIP = "Alinamadi"
    try {
        $addr = [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
                Where-Object { $_.AddressFamily -eq "InterNetwork" } |
                Select-Object -First 1
        if ($addr) { $hostIP = $addr.IPAddressToString }
    } catch {}

    $tarih = Get-Date -Format "dd.MM.yyyy HH:mm"

    Clear-Host
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "  KURULUM BASARIYLA TAMAMLANDI" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host ""
    Write-Host "  Tarih        : $tarih" -ForegroundColor White
    Write-Host "  Hostname     : $AgentHostname" -ForegroundColor White
    Write-Host "  Hostname IP  : $hostIP" -ForegroundColor White
    Write-Host "  Proxy IP     : $ProxyIP" -ForegroundColor White
    Write-Host "  PSK Identity : $PskIdentity" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host "  [!] ONEMLI - PROXY TARAFINDA YAPILMASI GEREKENLER" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Zabbix Web UI uzerinde bu host icin PSK tanimlamasi" -ForegroundColor White
    Write-Host "  yapilmadan agent baglanti kuramaz!" -ForegroundColor White
    Write-Host ""
    Write-Host "  Adimlar:" -ForegroundColor Yellow
    Write-Host "  1) Zabbix Web UI -> Configuration -> Hosts" -ForegroundColor White
    Write-Host "  2) Bu sunucuyu secin -> [Encryption] sekmesi" -ForegroundColor White
    Write-Host "  3) Asagidaki degerleri girin:" -ForegroundColor White
    Write-Host ""
    Write-Host "     Connections to host   : PSK" -ForegroundColor Cyan
    Write-Host "     Connections from host : PSK" -ForegroundColor Cyan
    Write-Host "     PSK Identity          : $PskIdentity" -ForegroundColor Cyan
    Write-Host "     PSK (Key)             : Kurulum esnasinda verdiginiz PSK Key degerini giriniz." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Ref: https://www.zabbix.com/documentation/7.4/en/manual/" -ForegroundColor DarkGray
    Write-Host "       encryption/using_pre_shared_keys" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Bu script DevOps Engineer Cumhur M. Akkaya tarafindan hazirlandi." -ForegroundColor Cyan
    Write-Host "  Script hakkindaki onerilerinizi asagidaki adreslerden iletebilirsiniz:" -ForegroundColor Cyan
    Write-Host "  https://www.linkedin.com/in/cumhurakkaya/" -ForegroundColor Cyan
    Write-Host "  https://cmakkaya.medium.com/" -ForegroundColor Cyan
    Write-Host "  https://github.com/cmakkaya" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host ""
    Write-Host "  Yukardaki bilgileri not aldiktan sonra" -ForegroundColor White
    Write-Host "  ENTER'a basarak bu pencereyi kapatabilirsiniz." -ForegroundColor White
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host ""

    # Kullanici ENTER'a basana kadar ekrani kapama
    # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/read-host
    Read-Host "  >> ENTER'a basin"
}

# -------------------------------------------------------
# FONKSIYON: Temp dosyasini temizle
# -------------------------------------------------------
function Cleanup-Temp {
    param([string]$MsiPath)
    if ($MsiPath -and (Test-Path $MsiPath)) {
        Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue
        Write-Host "[INFO] Gecici MSI dosyasi temizlendi." -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# ANA KURULUM AKISI: Install Agent 2
# -------------------------------------------------------
function Start-FreshInstall {
    Write-Banner "Zabbix Agent 2 v$AGENT2_VERSION - Yeni Kurulum"

    # Proxy IP al
    Write-Host "[INPUT] Zabbix Proxy IP adresini girin:" -ForegroundColor Cyan
    $proxyIP = ""
    while ($proxyIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        $proxyIP = (Read-Host "  Proxy IP").Trim()
        if ($proxyIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
            Write-Host "  [UYARI] Gecersiz IP formati, tekrar deneyin (ornek: 192.168.1.10)" -ForegroundColor Red
        }
    }

    # Hostname otomatik al
    $agentHostname = $env:COMPUTERNAME
    Write-Host "[INFO] Hostname otomatik alindi: $agentHostname" -ForegroundColor Green

    # Mevcut agent varsa temizle
    Remove-Agent1
    Remove-Agent2

    # MSI indir
    $msiPath = Download-Agent2MSI

    # PSK kur
    $psk = Setup-PSK -AgentHostname $agentHostname

    # MSI kur
    Install-Agent2MSI `
        -MsiPath       $msiPath `
        -ProxyIP       $proxyIP `
        -AgentHostname $agentHostname `
        -PskIdentity   $psk.Identity `
        -PskKeyFile    $psk.KeyFile

    # Firewall
    Add-FirewallRule

    # Config dogrula
    Verify-Config -ProxyIP $proxyIP -AgentHostname $agentHostname

    # Servis dogrula
    Verify-Service

    # Temizlik
    Cleanup-Temp -MsiPath $msiPath

    # Ozet
    Write-Summary `
        -AgentHostname $agentHostname `
        -ProxyIP       $proxyIP `
        -PskIdentity   $psk.Identity
}

# -------------------------------------------------------
# ANA KURULUM AKISI: Agent 1 -> Agent 2 Guncelleme
# -------------------------------------------------------
function Start-UpgradeFrom1 {
    Write-Banner "Zabbix Agent 1 -> Agent 2 v$AGENT2_VERSION Guncelleme"

    # Agent 1 kurulu mu kontrol et
    $proc    = Get-WmiObject -Class Win32_Process -Filter 'Name="zabbix_agentd.exe"' -ErrorAction SilentlyContinue
    $service = Get-WmiObject -Class Win32_Service  -Filter "Name=`"$SERVICE_NAME_A1`"" -ErrorAction SilentlyContinue

    if (-not $proc -and -not $service) {
        Write-Host "[UYARI] Zabbix Agent 1 bulunamadi. Devam edilecek mi?" -ForegroundColor Yellow
        $confirm = Read-Host "  Devam etmek icin 'evet' yazin, iptal icin baska bir sey"
        if ($confirm -ne "evet") {
            Write-Host "[INFO] Islem iptal edildi. Ana menuye donuluyor..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            Show-Menu
            return
        }
    }

    # Proxy IP al
    Write-Host "[INPUT] Zabbix Proxy IP adresini girin:" -ForegroundColor Cyan
    $proxyIP = ""
    while ($proxyIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        $proxyIP = (Read-Host "  Proxy IP").Trim()
        if ($proxyIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
            Write-Host "  [UYARI] Gecersiz IP formati, tekrar deneyin." -ForegroundColor Red
        }
    }

    $agentHostname = $env:COMPUTERNAME
    Write-Host "[INFO] Hostname: $agentHostname" -ForegroundColor Green

    Remove-Agent1
    Remove-Agent2

    $msiPath = Download-Agent2MSI
    $psk     = Setup-PSK -AgentHostname $agentHostname

    Install-Agent2MSI `
        -MsiPath       $msiPath `
        -ProxyIP       $proxyIP `
        -AgentHostname $agentHostname `
        -PskIdentity   $psk.Identity `
        -PskKeyFile    $psk.KeyFile

    Add-FirewallRule
    Verify-Config   -ProxyIP $proxyIP -AgentHostname $agentHostname
    Verify-Service
    Cleanup-Temp    -MsiPath $msiPath
    Write-Summary `
        -AgentHostname $agentHostname `
        -ProxyIP       $proxyIP `
        -PskIdentity   $psk.Identity
}

# -------------------------------------------------------
# ANA KURULUM AKISI: Agent 2 eski surum -> v7.4.8 Guncelleme
# -------------------------------------------------------
function Start-UpgradeFrom2Old {
    Write-Banner "Zabbix Agent 2 (Eski Surum) -> v$AGENT2_VERSION Guncelleme"

    # Agent 2 kurulu mu kontrol et
    $proc    = Get-WmiObject -Class Win32_Process -Filter 'Name="zabbix_agent2.exe"' -ErrorAction SilentlyContinue
    $service = Get-WmiObject -Class Win32_Service  -Filter "Name=`"$SERVICE_NAME_A2`"" -ErrorAction SilentlyContinue
    $msiProd = Get-WmiObject -Class Win32_Product  -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like "*Zabbix Agent 2*" }

    if (-not $proc -and -not $service -and -not $msiProd) {
        Write-Host "[UYARI] Zabbix Agent 2 bulunamadi. Devam edilecek mi?" -ForegroundColor Yellow
        $confirm = Read-Host "  Devam etmek icin 'evet' yazin, iptal icin baska bir sey"
        if ($confirm -ne "evet") {
            Write-Host "[INFO] Islem iptal edildi. Ana menuye donuluyor..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            Show-Menu
            return
        }
    }

    if ($msiProd) {
        Write-Host "[INFO] Mevcut kurulmus surum: $($msiProd.Version)" -ForegroundColor Yellow
        if ($msiProd.Version -eq $AGENT2_VERSION) {
            Write-Host "[UYARI] Zabbix Agent 2 v$AGENT2_VERSION zaten kurulu!" -ForegroundColor Yellow
            $confirm = Read-Host "  Yeniden kurmak icin 'evet' yazin, iptal icin baska bir sey"
            if ($confirm -ne "evet") {
                Show-Menu
                return
            }
        }
    }

    # Proxy IP al
    Write-Host "[INPUT] Zabbix Proxy IP adresini girin:" -ForegroundColor Cyan
    $proxyIP = ""
    while ($proxyIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        $proxyIP = (Read-Host "  Proxy IP").Trim()
        if ($proxyIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
            Write-Host "  [UYARI] Gecersiz IP formati, tekrar deneyin." -ForegroundColor Red
        }
    }

    $agentHostname = $env:COMPUTERNAME
    Write-Host "[INFO] Hostname: $agentHostname" -ForegroundColor Green

    Remove-Agent2

    $msiPath = Download-Agent2MSI
    $psk     = Setup-PSK -AgentHostname $agentHostname

    Install-Agent2MSI `
        -MsiPath       $msiPath `
        -ProxyIP       $proxyIP `
        -AgentHostname $agentHostname `
        -PskIdentity   $psk.Identity `
        -PskKeyFile    $psk.KeyFile

    Add-FirewallRule
    Verify-Config   -ProxyIP $proxyIP -AgentHostname $agentHostname
    Verify-Service
    Cleanup-Temp    -MsiPath $msiPath
    Write-Summary `
        -AgentHostname $agentHostname `
        -ProxyIP       $proxyIP `
        -PskIdentity   $psk.Identity
}

# -------------------------------------------------------
# ANA MENU
# -------------------------------------------------------
function Show-Menu {
    Clear-Host
    $hostname = $env:COMPUTERNAME

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "  Zabbix Agent 2 v$AGENT2_VERSION Kurulum Scriptine Hosgeldiniz." -ForegroundColor Yellow
    Write-Host "  Windows Server 2016+ | AMD64 | OpenSSL | MSI | icin hazirlandi." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Ref: https://www.zabbix.com/documentation/7.4/en/manual/" -ForegroundColor DarkGray
    Write-Host "       installation/install_from_packages/win_msi" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Bu script DevOps Engineer Cumhur M. Akkaya tarafindan hazirlandi." -ForegroundColor Cyan
    Write-Host "  Script hakkindaki onerilerinizi asagidaki adreslerden iletebilirsiniz:" -ForegroundColor Cyan
    Write-Host "  https://www.linkedin.com/in/cumhurakkaya/" -ForegroundColor Cyan
    Write-Host "  https://cmakkaya.medium.com/" -ForegroundColor Cyan
    Write-Host "  https://github.com/cmakkaya" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Sunucu : $hostname" -ForegroundColor Cyan
    Write-Host "  Mimari : $arch" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Install [Zabbix Agent 2 v$AGENT2_VERSION]" -ForegroundColor White
    Write-Host "     Temiz kurulum - Agent1/Agent2 varsa kaldirilir" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  2) Update [Zabbix Agent 1] to [Zabbix Agent 2 v$AGENT2_VERSION]" -ForegroundColor White
    Write-Host "     Mevcut Agent1 kaldirilir, Agent2 v$AGENT2_VERSION kurulur" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3) Update [Zabbix Agent 2] to [Zabbix Agent 2 v$AGENT2_VERSION]" -ForegroundColor White
    Write-Host "     Eski Agent2 kaldirilir, Agent2 v$AGENT2_VERSION kurulur" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  0) Cikis" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  On Hazirlik:" -ForegroundColor Yellow
    Write-Host "  Eger bir PSK Key'iniz yoksa, kuruluma baslamadan once" -ForegroundColor White
    Write-Host "  powershell'de asagidaki komutlarla olusturup, kurulumda kullanmak uzere kopyalayiniz." -ForegroundColor White
    Write-Host ""
    Write-Host "  a. PSK Key olusturmak icin:" -ForegroundColor Cyan
    Write-Host '      $psk = -join ((1..32) | ForEach-Object { ''{0:x2}'' -f (Get-Random -Max 256) })' -ForegroundColor White
    Write-Host ""
    Write-Host "  b. Olusan PSK Key'i gormek icin:" -ForegroundColor Cyan
    Write-Host '      $psk' -ForegroundColor White
    Write-Host ""
    Write-Host "  c. PSK Key'iniz alttakine benzer bir formatta gozukecektir:" -ForegroundColor Cyan
    Write-Host "      34f6889e280e51dda96a4b3fc7732f3cd77f50ec4443271b3dc227dae1938fca" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""

    $invalidCount = 0

    while ($true) {
        $choice = Read-Host "  Islem Seciniz [1/2/3/0]"
        switch ($choice.Trim()) {
            "1" { Start-FreshInstall;     return }
            "2" { Start-UpgradeFrom1;     return }
            "3" { Start-UpgradeFrom2Old;  return }
            "0" { Write-Host "`n[INFO] Script sonlandiriliyor.`n" -ForegroundColor Yellow; exit 0 }
            default {
                $invalidCount++
                Write-Host "  [UYARI] Gecersiz secim. Lutfen 1, 2, 3 veya 0 girin." -ForegroundColor Red
                if ($invalidCount -ge 3) {
                    Exit-WithError "Maksimum gecersiz deneme sayisina ulasildi."
                }
            }
        }
    }
}

# -------------------------------------------------------
# BASLANGIÇ NOKTASI
# -------------------------------------------------------
Show-Menu
