#  ============================================================
#  Script Name:    Install-ZabbixAgent2.ps1
#  Version:        1.1
#  Description:    Zabbix Agent 2 v7.4.8 Silent Installer
#                  - Fresh install (MSI)
#                  - Upgrade from Zabbix Agent 1 (ZIP-based)
#                  - Upgrade from Zabbix Agent 2 old version (MSI or ZIP)
#                  - PSK encryption support
#                  - Multiple Proxy IP support (comma-separated)
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
#    [3] Zabbix Agent 2 Config Parameters (Server/ServerActive multi-value):
#        https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2_win
#    [4] MSI Silent Install (msiexec):
#        https://learn.microsoft.com/en-us/windows/win32/msi/command-line-options
#    [5] Windows Firewall via PowerShell:
#        https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule
#
#  This script was prepared by DevOps Engineer Cumhur M. Akkaya.
#  You can share your feedback and suggestions via:
#  https://www.linkedin.com/in/cumhurakkaya/
#  https://cmakkaya.medium.com/
#  https://github.com/cmakkaya
#  ============================================================

# -------------------------------------------------------
# TO INSTALL A DIFFERENT VERSION
# -------------------------------------------------------
# If you want to install a different version, you must update
# both AGENT2_VERSION and AGENT2_MSI_URL together in the
# "STATIC VARIABLES" section below.
# Example:
# $AGENT2_VERSION = "7.0.24"
# $AGENT2_MSI_URL = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/7.0.24/zabbix_agent-7.0.24-windows-amd64-openssl.msi"
#
# To check available versions:
# https://cdn.zabbix.com/zabbix/binaries/stable/

# -------------------------------------------------------
# STATIC VARIABLES - Edit here if needed
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
# ADMIN PRIVILEGE CHECK & AUTO RELAUNCH
# Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/
# -------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "`nAdministrator privileges required. Relaunching as Administrator...`n" -ForegroundColor Yellow
    Start-Process PowerShell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Definition)`"" -Verb RunAs
    exit
}

# Bug Fix - Prevent symbolic link issue for TEMP path
# Ref: https://github.com/PowerShell/PowerShell/issues/17359
$envTEMP = (Get-Item -LiteralPath $env:TEMP).FullName

Clear-Host

# -------------------------------------------------------
# POWERSHELL VERSION CHECK (minimum 5.1)
# Ref: https://learn.microsoft.com/en-us/powershell/scripting/windows-powershell/
# -------------------------------------------------------
$minPS = [Version]"5.1"
if ($PSVersionTable.PSVersion -lt $minPS) {
    Write-Host "`n[ERROR] This script requires PowerShell $minPS or later.`n" -ForegroundColor Red
    Write-Host "Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host "`nTerminating in 5 seconds...`n" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

# -------------------------------------------------------
# ARCHITECTURE CHECK (AMD64 only)
# -------------------------------------------------------
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -ne "AMD64") {
    Write-Host "`n[ERROR] This script only supports AMD64 (x64) architecture.`n" -ForegroundColor Red
    Write-Host "Detected architecture: $arch" -ForegroundColor Red
    Write-Host "`nTerminating in 5 seconds...`n" -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

# -------------------------------------------------------
# HELPER FUNCTION: Print colored section banner
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
# HELPER FUNCTION: Print error message and exit
# -------------------------------------------------------
function Exit-WithError {
    param([string]$Message)
    Write-Host "`n[ERROR] $Message`n" -ForegroundColor Red
    Write-Host "Terminating in 5 seconds..." -ForegroundColor Red
    Start-Sleep -Seconds 5
    exit 1
}

# -------------------------------------------------------
# HELPER FUNCTION: Enable TLS protocols
# Ref: https://learn.microsoft.com/en-us/dotnet/api/system.net.servicepointmanager.securityprotocol
# -------------------------------------------------------
function Enable-TLS {
    $protocols = 'Tls12,Tls13' -split ',' | Where-Object {
        [System.Enum]::IsDefined([System.Net.SecurityProtocolType], $_)
    }
    [System.Net.ServicePointManager]::SecurityProtocol = $protocols -join ','
    Write-Host "[INFO] Active security protocols: $([System.Net.ServicePointManager]::SecurityProtocol)" -ForegroundColor DarkGray
}

# -------------------------------------------------------
# HELPER FUNCTION: Create directory if not exists
# -------------------------------------------------------
function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "[INFO] Directory created: $Path" -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# HELPER FUNCTION: Validate comma-separated Proxy IP list
# Supports single IP or multiple IPs: 192.168.1.10,192.168.1.11
# Zabbix Agent 2 natively supports comma-separated values
# for both Server and ServerActive parameters.
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2_win#server
# -------------------------------------------------------
function Get-ValidProxyIP {
    Write-Host ""
    Write-Host "[INPUT] Enter the Zabbix Proxy IP address(es):" -ForegroundColor Cyan
    Write-Host "        Single proxy    : 192.168.1.10" -ForegroundColor DarkGray
    Write-Host "        Multiple proxies: 192.168.1.10,192.168.1.11" -ForegroundColor DarkGray
    Write-Host ""

    while ($true) {
        $raw = (Read-Host "  Proxy IP(s)").Trim()

        # Remove all spaces around commas
        $raw = $raw -replace '\s*,\s*', ','

        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Host "  [WARNING] IP address cannot be empty. Please try again." -ForegroundColor Red
            continue
        }

        $ipList   = $raw -split ','
        $allValid = $true

        foreach ($ip in $ipList) {
            $ip = $ip.Trim()
            if ([string]::IsNullOrWhiteSpace($ip)) {
                Write-Host "  [WARNING] Empty IP entry detected. Remove extra commas and try again." -ForegroundColor Red
                $allValid = $false
                break
            }
            if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
                Write-Host "  [WARNING] Invalid IP format: '$ip'" -ForegroundColor Red
                Write-Host "            Single proxy    : 192.168.1.10" -ForegroundColor Red
                Write-Host "            Multiple proxies: 192.168.1.10,192.168.1.11" -ForegroundColor Red
                $allValid = $false
                break
            }
        }

        if ($allValid) {
            if ($ipList.Count -gt 1) {
                Write-Host "[OK] $($ipList.Count) Proxy IPs accepted: $raw" -ForegroundColor Green
            } else {
                Write-Host "[OK] Proxy IP accepted: $raw" -ForegroundColor Green
            }
            return $raw
        }
    }
}

# -------------------------------------------------------
# FUNCTION: Remove Zabbix Agent 1 (ZIP-based)
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi#uninstalling
# -------------------------------------------------------
function Remove-Agent1 {
    Write-Host "[INFO] Checking for Zabbix Agent 1..." -ForegroundColor Yellow

    $proc    = Get-WmiObject -Class Win32_Process -Filter 'Name="zabbix_agentd.exe"' -ErrorAction SilentlyContinue
    $service = Get-WmiObject -Class Win32_Service  -Filter "Name=`"$SERVICE_NAME_A1`"" -ErrorAction SilentlyContinue

    if ($proc) {
        $exePath  = $proc.ExecutablePath
        $agentDir = Split-Path (Split-Path $exePath)
        $confPath = "$agentDir\conf\zabbix_agentd.conf"

        Write-Host "[INFO] Stopping Zabbix Agent 1 service..." -ForegroundColor Yellow
        & $exePath --config $confPath --stop 2>$null
        Start-Sleep -Seconds 3

        Write-Host "[INFO] Uninstalling Zabbix Agent 1..." -ForegroundColor Yellow
        & $exePath --config $confPath --uninstall 2>$null
        Start-Sleep -Seconds 3

        if (Test-Path $agentDir) {
            Remove-Item $agentDir -Force -Recurse -ErrorAction SilentlyContinue
        }
        Write-Host "[OK] Zabbix Agent 1 removed successfully." -ForegroundColor Green
    }
    elseif ($service) {
        Write-Host "[INFO] Stopping and removing Zabbix Agent 1 service..." -ForegroundColor Yellow
        $null = $service.StopService()
        Start-Sleep -Seconds 2
        $null = $service.Delete()
        Write-Host "[OK] Zabbix Agent 1 service removed." -ForegroundColor Green
    }
    else {
        Write-Host "[INFO] Zabbix Agent 1 not found. Continuing." -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# FUNCTION: Remove Zabbix Agent 2 (MSI or ZIP)
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi#uninstalling
# Ref: https://learn.microsoft.com/en-us/windows/win32/msi/command-line-options (MsiExec /x)
# -------------------------------------------------------
function Remove-Agent2 {
    Write-Host "[INFO] Checking for Zabbix Agent 2..." -ForegroundColor Yellow

    # --- Remove MSI-based Agent 2 if present ---
    # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-wmiobject
    $msiProduct = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -like "*Zabbix Agent 2*" }

    if ($msiProduct) {
        $installedVer = $msiProduct.Version
        Write-Host "[INFO] MSI-installed Zabbix Agent 2 found: v$installedVer" -ForegroundColor Yellow
        Write-Host "[INFO] Removing via MSI (msiexec /x)..." -ForegroundColor Yellow

        # Stop the service first
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
            Write-Host "[WARNING] MSI removal exit code: $($proc.ExitCode) - Manual check recommended." -ForegroundColor Yellow
        } else {
            Write-Host "[OK] Zabbix Agent 2 MSI removed successfully." -ForegroundColor Green
        }
    }

    # --- Remove ZIP (legacy) based Agent 2 if present ---
    $proc2    = Get-WmiObject -Class Win32_Process -Filter 'Name="zabbix_agent2.exe"' -ErrorAction SilentlyContinue
    $service2 = Get-WmiObject -Class Win32_Service  -Filter "Name=`"$SERVICE_NAME_A2`"" -ErrorAction SilentlyContinue

    if ($proc2) {
        $exePath2  = $proc2.ExecutablePath
        $agentDir2 = Split-Path (Split-Path $exePath2)
        $confPath2 = "$agentDir2\conf\zabbix_agent2.conf"

        Write-Host "[INFO] Stopping ZIP-based Zabbix Agent 2..." -ForegroundColor Yellow
        & $exePath2 --config $confPath2 --stop 2>$null
        Start-Sleep -Seconds 3
        & $exePath2 --config $confPath2 --uninstall 2>$null
        Start-Sleep -Seconds 3

        if (Test-Path $agentDir2) {
            Remove-Item $agentDir2 -Force -Recurse -ErrorAction SilentlyContinue
        }
        Write-Host "[OK] ZIP-based Zabbix Agent 2 removed." -ForegroundColor Green
    }
    elseif ($service2) {
        Write-Host "[INFO] Removing remaining Zabbix Agent 2 service..." -ForegroundColor Yellow
        $null = $service2.StopService()
        Start-Sleep -Seconds 2
        $null = $service2.Delete()

        # Clean up registry leftovers
        # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/remove-item
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application\$SERVICE_NAME_A2"
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Registry key cleaned up." -ForegroundColor Green
        }
        Write-Host "[OK] Zabbix Agent 2 service removed." -ForegroundColor Green
    }

    # Remove leftover install directory (if MSI left it behind)
    if (Test-Path $INSTALL_DIR) {
        Remove-Item $INSTALL_DIR -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "[INFO] Old installation directory cleaned: $INSTALL_DIR" -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# FUNCTION: Download MSI
# Ref: https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.8/
# -------------------------------------------------------
function Download-Agent2MSI {
    $msiPath = "$envTEMP\zabbix_agent2_748.msi"

    Write-Host "[INFO] Downloading Zabbix Agent 2 v$AGENT2_VERSION..." -ForegroundColor Yellow
    Write-Host "[INFO] Source: $AGENT2_MSI_URL" -ForegroundColor DarkGray
    Enable-TLS

    try {
        # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($AGENT2_MSI_URL, $msiPath)
    }
    catch {
        Exit-WithError "MSI download failed: $_"
    }

    if (-not (Test-Path $msiPath)) {
        Exit-WithError "MSI file not found after download: $msiPath"
    }

    $fileSize = (Get-Item $msiPath).Length
    Write-Host "[OK] Download complete. File size: $([math]::Round($fileSize/1MB,2)) MB" -ForegroundColor Green
    return $msiPath
}

# -------------------------------------------------------
# FUNCTION: PSK configuration
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys
# -------------------------------------------------------
function Setup-PSK {
    param([string]$AgentHostname)

    Write-Host ""
    Write-Host "[PSK] Starting PSK configuration..." -ForegroundColor Cyan

    # PSK Identity: auto-generated as PSK_<HOSTNAME>
    $pskIdentity = "PSK_$($AgentHostname.ToUpper())"
    Write-Host "[PSK] PSK Identity generated automatically: $pskIdentity" -ForegroundColor Green

    # PSK Key: prompt user for input
    Write-Host ""
    Write-Host "[PSK] Please enter your 256-bit (64 character) hexadecimal PSK Key." -ForegroundColor Yellow
    Write-Host "[PSK] Example: a3f1c2...  (must match the value on Zabbix Server/Proxy)" -ForegroundColor DarkGray
    Write-Host "[PSK] Ref: https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys" -ForegroundColor DarkGray
    Write-Host ""

    $pskKey  = ""
    $attempt = 0
    while ($true) {
        $attempt++
        if ($attempt -gt 3) {
            Exit-WithError "3 invalid PSK attempts. Terminating script."
        }
        $pskKey = Read-Host "[PSK] Enter PSK Key (64 hex characters)"
        $pskKey = $pskKey.Trim()

        # Validate hex format - exactly 64 chars, only 0-9 and a-f/A-F
        if ($pskKey -match '^[0-9a-fA-F]{64}$') {
            Write-Host "[OK] PSK Key format is valid." -ForegroundColor Green
            break
        }
        else {
            Write-Host "[WARNING] Invalid format. Must be exactly 64 hex characters (0-9, a-f only). Please try again." -ForegroundColor Red
        }
    }

    # Create PSK directory and save to file
    Ensure-Directory $PSK_DIR

    # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/set-content
    Set-Content -Path $PSK_FILE -Value $pskKey -Encoding ASCII -Force
    Write-Host "[OK] PSK file saved: $PSK_FILE" -ForegroundColor Green

    # Secure PSK file - only LocalSystem and Administrators can read
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
        Write-Host "[OK] PSK file permissions secured (LocalSystem + Administrators)." -ForegroundColor Green
    }
    catch {
        Write-Host "[WARNING] Could not set PSK file permissions: $_ - Please check manually." -ForegroundColor Yellow
    }

    return @{
        Identity = $pskIdentity
        KeyFile  = $PSK_FILE
    }
}

# -------------------------------------------------------
# FUNCTION: MSI silent installation
# Supports multiple Proxy IPs (comma-separated) for
# SERVER and SERVERACTIVE parameters natively.
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi
# Ref: https://learn.microsoft.com/en-us/windows/win32/msi/command-line-options
# -------------------------------------------------------
function Install-Agent2MSI {
    param(
        [string]$MsiPath,
        [string]$ProxyIP,       # accepts comma-separated IPs: 192.168.1.10,192.168.1.11
        [string]$AgentHostname,
        [string]$PskIdentity,
        [string]$PskKeyFile
    )

    Write-Host "[INFO] Installing Zabbix Agent 2 v$AGENT2_VERSION via MSI..." -ForegroundColor Yellow
    Write-Host "[INFO] Target directory: $INSTALL_DIR" -ForegroundColor DarkGray

    Ensure-Directory $LOG_DIR

    # MSI parameter reference:
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

    Write-Host "[INFO] MSI installation parameters prepared." -ForegroundColor DarkGray
    Write-Host "[INFO] Installation starting, please wait..." -ForegroundColor Yellow

    # Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process
    $proc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
    Start-Sleep -Seconds 5

    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        # 3010 = installation successful, reboot required - this is normal
        Exit-WithError "MSI installation failed. Exit code: $($proc.ExitCode). Log: $LOG_DIR\msi_install.log"
    }

    if ($proc.ExitCode -eq 3010) {
        Write-Host "[WARNING] Installation successful. System reboot required (ExitCode: 3010)." -ForegroundColor Yellow
    }

    Write-Host "[OK] Zabbix Agent 2 v$AGENT2_VERSION installation completed." -ForegroundColor Green
}

# -------------------------------------------------------
# FUNCTION: Verify config file and PSK parameters
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2_win
# -------------------------------------------------------
function Verify-Config {
    param([string]$ProxyIP, [string]$AgentHostname)

    Write-Host "[INFO] Verifying configuration file: $CONFIG_FILE" -ForegroundColor Yellow

    if (-not (Test-Path $CONFIG_FILE)) {
        Write-Host "[WARNING] Config file not found: $CONFIG_FILE" -ForegroundColor Yellow
        Write-Host "[WARNING] MSI may have written the config to a different location." -ForegroundColor Yellow
        return
    }

    $confContent = Get-Content $CONFIG_FILE -Raw

    # Check critical parameters
    $checks = @{
        "Server"         = $ProxyIP
        "ServerActive"   = $ProxyIP
        "Hostname"       = $AgentHostname
        "TLSConnect"     = "psk"
        "TLSAccept"      = "psk"
        "TLSPSKIdentity" = ""   # only check presence
        "TLSPSKFile"     = ""   # only check presence
    }

    $allOk = $true
    foreach ($key in $checks.Keys) {
        if ($confContent -match "(?m)^$key=") {
            Write-Host "[OK] Config: $key parameter is present." -ForegroundColor Green
        } else {
            Write-Host "[WARNING] Config: $key parameter is missing or commented out!" -ForegroundColor Yellow
            $allOk = $false
        }
    }

    if (-not $allOk) {
        Write-Host ""
        Write-Host "[WARNING] Some parameters appear to be missing." -ForegroundColor Yellow
        Write-Host "[WARNING] Ref: https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2_win" -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# FUNCTION: Add Windows Firewall rule (port 10050 TCP)
# Ref: https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule
# Ref: https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi#firewall
# -------------------------------------------------------
function Add-FirewallRule {
    Write-Host "[INFO] Checking Windows Firewall rule (port $AGENT2_PORT/TCP)..." -ForegroundColor Yellow

    # Remove existing rule if present (refresh)
    $existingRule = Get-NetFirewallRule -DisplayName $FW_RULE_NAME -ErrorAction SilentlyContinue
    if ($existingRule) {
        Remove-NetFirewallRule -DisplayName $FW_RULE_NAME -ErrorAction SilentlyContinue
        Write-Host "[INFO] Existing firewall rule refreshed..." -ForegroundColor DarkGray
    }

    # Add new rule
    # Ref: https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule
    try {
        New-NetFirewallRule `
            -DisplayName $FW_RULE_NAME `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $AGENT2_PORT `
            -Action Allow `
            -Profile Any `
            -Description "Zabbix Agent 2 v$AGENT2_VERSION - Auto created" `
            -ErrorAction Stop | Out-Null

        Write-Host "[OK] Firewall rule added: '$FW_RULE_NAME' (TCP/$AGENT2_PORT inbound allow)" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARNING] Firewall rule could not be added: $_ - Please add it manually." -ForegroundColor Yellow
    }
}

# -------------------------------------------------------
# FUNCTION: Verify service after installation
# Ref: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-service
# -------------------------------------------------------
function Verify-Service {
    Write-Host "[INFO] Checking Zabbix Agent 2 service..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3

    $service = Get-Service -Name $SERVICE_NAME_A2 -ErrorAction SilentlyContinue

    if (-not $service) {
        Write-Host "[WARNING] '$SERVICE_NAME_A2' service not found. Please verify the installation." -ForegroundColor Yellow
        return
    }

    if ($service.Status -ne "Running") {
        Write-Host "[WARNING] Service is not running ($($service.Status)). Attempting to start..." -ForegroundColor Yellow
        try {
            Start-Service -Name $SERVICE_NAME_A2 -ErrorAction Stop
            Start-Sleep -Seconds 3
            $service.Refresh()
        }
        catch {
            Write-Host "[ERROR] Failed to start service: $_" -ForegroundColor Red
            Write-Host "[ERROR] Check Windows Event Log or $LOG_FILE" -ForegroundColor Red
            return
        }
    }

    $service.Refresh()
    if ($service.Status -eq "Running") {
        $startTime = (Get-Process -Name "zabbix_agent2" -ErrorAction SilentlyContinue | Select-Object -First 1).StartTime
        if ($startTime) {
            Write-Host "[OK] Zabbix Agent 2 service is RUNNING. Start time: $startTime" -ForegroundColor Green
        } else {
            Write-Host "[OK] Zabbix Agent 2 service is RUNNING." -ForegroundColor Green
        }
    } else {
        Write-Host "[ERROR] Service is still not running. Status: $($service.Status)" -ForegroundColor Red
    }
}

# -------------------------------------------------------
# FUNCTION: Print installation summary
# Window stays open until user presses ENTER
# -------------------------------------------------------
function Write-Summary {
    param(
        [string]$AgentHostname,
        [string]$ProxyIP,
        [string]$PskIdentity
    )

    # Get local IP address of the host
    # Ref: https://learn.microsoft.com/en-us/dotnet/api/system.net.dns.gethostaddresses
    $hostIP = "Unavailable"
    try {
        $addr = [System.Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
                Where-Object { $_.AddressFamily -eq "InterNetwork" } |
                Select-Object -First 1
        if ($addr) { $hostIP = $addr.IPAddressToString }
    } catch {}

    $installDate = Get-Date -Format "dd.MM.yyyy HH:mm"

    Clear-Host
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host "  INSTALLATION COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host ""
    Write-Host "  Date         : $installDate" -ForegroundColor White
    Write-Host "  Hostname     : $AgentHostname" -ForegroundColor White
    Write-Host "  Hostname IP  : $hostIP" -ForegroundColor White
    Write-Host "  Proxy IP(s)  : $ProxyIP" -ForegroundColor White
    Write-Host "  PSK Identity : $PskIdentity" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host "  [!] IMPORTANT - ACTION REQUIRED ON PROXY SIDE" -ForegroundColor Yellow
    Write-Host ("=" * 60) -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  The agent cannot connect until PSK is configured" -ForegroundColor White
    Write-Host "  on the Zabbix Web UI for this host!" -ForegroundColor White
    Write-Host ""
    Write-Host "  Steps:" -ForegroundColor Yellow
    Write-Host "  1) Zabbix Web UI -> Configuration -> Hosts" -ForegroundColor White
    Write-Host "  2) Select this host -> [Encryption] tab" -ForegroundColor White
    Write-Host "  3) Enter the following values:" -ForegroundColor White
    Write-Host ""
    Write-Host "     Connections to host   : PSK" -ForegroundColor Cyan
    Write-Host "     Connections from host : PSK" -ForegroundColor Cyan
    Write-Host "     PSK Identity          : $PskIdentity" -ForegroundColor Cyan
    Write-Host "     PSK (Key)             : Enter the PSK Key value you provided during installation." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Ref: https://www.zabbix.com/documentation/7.4/en/manual/" -ForegroundColor DarkGray
    Write-Host "       encryption/using_pre_shared_keys" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  This script was prepared by DevOps Engineer Cumhur M. Akkaya." -ForegroundColor Cyan
    Write-Host "  You can share your feedback and suggestions via:" -ForegroundColor Cyan
    Write-Host "  https://www.linkedin.com/in/cumhurakkaya/" -ForegroundColor Cyan
    Write-Host "  https://cmakkaya.medium.com/" -ForegroundColor Cyan
    Write-Host "  https://github.com/cmakkaya" -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host ""
    Write-Host "  Please take note of the information above," -ForegroundColor White
    Write-Host "  then press ENTER to close this window." -ForegroundColor White
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    Write-Host ""

    # Flush any buffered keystrokes (yes/no inputs etc.) so they do not
    # auto-close the summary screen before the user reads it.
    # Ref: https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.host.pshostrawuserinterface.flushinputbuffer
    $host.UI.RawUI.FlushInputBuffer()

    # Wait for user to press ENTER - window will NOT close automatically
    Read-Host "  >> Press ENTER to exit"
}

# -------------------------------------------------------
# HELPER FUNCTION: Clean up temp MSI file
# -------------------------------------------------------
function Cleanup-Temp {
    param([string]$MsiPath)
    if ($MsiPath -and (Test-Path $MsiPath)) {
        Remove-Item $MsiPath -Force -ErrorAction SilentlyContinue
        Write-Host "[INFO] Temporary MSI file cleaned up." -ForegroundColor DarkGray
    }
}

# -------------------------------------------------------
# MAIN FLOW: Fresh Install
# -------------------------------------------------------
function Start-FreshInstall {
    Write-Banner "Zabbix Agent 2 v$AGENT2_VERSION - Fresh Installation"

    $proxyIP       = Get-ValidProxyIP
    $agentHostname = $env:COMPUTERNAME
    Write-Host "[INFO] Hostname detected automatically: $agentHostname" -ForegroundColor Green

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
    Verify-Config  -ProxyIP $proxyIP -AgentHostname $agentHostname
    Verify-Service
    Cleanup-Temp   -MsiPath $msiPath
    Write-Summary  -AgentHostname $agentHostname -ProxyIP $proxyIP -PskIdentity $psk.Identity
}

# -------------------------------------------------------
# MAIN FLOW: Upgrade from Agent 1 to Agent 2
# -------------------------------------------------------
function Start-UpgradeFrom1 {
    Write-Banner "Zabbix Agent 1 -> Agent 2 v$AGENT2_VERSION Upgrade"

    $proc    = Get-WmiObject -Class Win32_Process -Filter 'Name="zabbix_agentd.exe"' -ErrorAction SilentlyContinue
    $service = Get-WmiObject -Class Win32_Service  -Filter "Name=`"$SERVICE_NAME_A1`"" -ErrorAction SilentlyContinue

    if (-not $proc -and -not $service) {
        Write-Host "[WARNING] Zabbix Agent 1 not found." -ForegroundColor Yellow
        $confirm = Read-Host "  Type 'yes' to continue anyway, or anything else to cancel"
        if ($confirm -ne "yes") {
            Write-Host "[INFO] Operation cancelled. Returning to main menu..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            Show-Menu
            return
        }
    }

    $proxyIP       = Get-ValidProxyIP
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
    Verify-Config  -ProxyIP $proxyIP -AgentHostname $agentHostname
    Verify-Service
    Cleanup-Temp   -MsiPath $msiPath
    Write-Summary  -AgentHostname $agentHostname -ProxyIP $proxyIP -PskIdentity $psk.Identity
}

# -------------------------------------------------------
# MAIN FLOW: Upgrade from old Agent 2 to v7.4.8
# -------------------------------------------------------
function Start-UpgradeFrom2Old {
    Write-Banner "Zabbix Agent 2 (Old Version) -> v$AGENT2_VERSION Upgrade"

    $proc    = Get-WmiObject -Class Win32_Process -Filter 'Name="zabbix_agent2.exe"' -ErrorAction SilentlyContinue
    $service = Get-WmiObject -Class Win32_Service  -Filter "Name=`"$SERVICE_NAME_A2`"" -ErrorAction SilentlyContinue
    $msiProd = Get-WmiObject -Class Win32_Product  -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -like "*Zabbix Agent 2*" }

    if (-not $proc -and -not $service -and -not $msiProd) {
        Write-Host "[WARNING] Zabbix Agent 2 not found." -ForegroundColor Yellow
        $confirm = Read-Host "  Type 'yes' to continue anyway, or anything else to cancel"
        if ($confirm -ne "yes") {
            Write-Host "[INFO] Operation cancelled. Returning to main menu..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
            Show-Menu
            return
        }
    }

    if ($msiProd) {
        Write-Host "[INFO] Currently installed version: $($msiProd.Version)" -ForegroundColor Yellow
        if ($msiProd.Version -eq $AGENT2_VERSION) {
            Write-Host "[WARNING] Zabbix Agent 2 v$AGENT2_VERSION is already installed!" -ForegroundColor Yellow
            $confirm = Read-Host "  Type 'yes' to reinstall, or anything else to cancel"
            if ($confirm -ne "yes") {
                Show-Menu
                return
            }
        }
    }

    $proxyIP       = Get-ValidProxyIP
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
    Verify-Config  -ProxyIP $proxyIP -AgentHostname $agentHostname
    Verify-Service
    Cleanup-Temp   -MsiPath $msiPath
    Write-Summary  -AgentHostname $agentHostname -ProxyIP $proxyIP -PskIdentity $psk.Identity
}

# -------------------------------------------------------
# MAIN MENU
# -------------------------------------------------------
function Show-Menu {
    Clear-Host
    $hostname = $env:COMPUTERNAME

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "  Welcome to Zabbix Agent 2 v$AGENT2_VERSION Installation Script." -ForegroundColor Yellow
    Write-Host "  Prepared for Windows Server 2016+ | AMD64 | OpenSSL | MSI." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Ref: https://www.zabbix.com/documentation/7.4/en/manual/" -ForegroundColor DarkGray
    Write-Host "       installation/install_from_packages/win_msi" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  This script was prepared by DevOps Engineer Cumhur M. Akkaya." -ForegroundColor Cyan
    Write-Host "  You can share your feedback and suggestions via:" -ForegroundColor Cyan
    Write-Host "  https://www.linkedin.com/in/cumhurakkaya/" -ForegroundColor Cyan
    Write-Host "  https://cmakkaya.medium.com/" -ForegroundColor Cyan
    Write-Host "  https://github.com/cmakkaya" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Server : $hostname" -ForegroundColor Cyan
    Write-Host "  Arch   : $arch" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1) Install [Zabbix Agent 2 v$AGENT2_VERSION]" -ForegroundColor White
    Write-Host "     Fresh installation - existing Agent1/Agent2 will be removed" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  2) Update [Zabbix Agent 1] to [Zabbix Agent 2 v$AGENT2_VERSION]" -ForegroundColor White
    Write-Host "     Removes existing Agent1, installs Agent2 v$AGENT2_VERSION" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  3) Update [Zabbix Agent 2 old version] to [Zabbix Agent 2 v$AGENT2_VERSION]" -ForegroundColor White
    Write-Host "     Removes old Agent2, installs Agent2 v$AGENT2_VERSION" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  0) Exit" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Pre-requisite:" -ForegroundColor Yellow
    Write-Host "  If you don't have a PSK Key yet, generate one before starting" -ForegroundColor White
    Write-Host "  the installation and copy it for use during setup." -ForegroundColor White
    Write-Host ""
    Write-Host "  a. To generate a PSK Key:" -ForegroundColor Cyan
    Write-Host '      $psk = -join ((1..32) | ForEach-Object { ''{0:x2}'' -f (Get-Random -Max 256) })' -ForegroundColor White
    Write-Host ""
    Write-Host "  b. To display the generated PSK Key:" -ForegroundColor Cyan
    Write-Host '      $psk' -ForegroundColor White
    Write-Host ""
    Write-Host "  c. Your PSK Key will look similar to this:" -ForegroundColor Cyan
    Write-Host "      34f6889e280e51dda96a4b3fc7732f3cd77f50ec4443271b3dc227dae1938fca" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""

    $invalidCount = 0

    while ($true) {
        $choice = Read-Host "  Select Operation [1/2/3/0]"
        switch ($choice.Trim()) {
            "1" { Start-FreshInstall;    return }
            "2" { Start-UpgradeFrom1;    return }
            "3" { Start-UpgradeFrom2Old; return }
            "0" {
                Write-Host "`n[INFO] Terminating script.`n" -ForegroundColor Yellow
                exit 0
            }
            default {
                $invalidCount++
                Write-Host "  [WARNING] Invalid selection. Please enter 1, 2, 3 or 0." -ForegroundColor Red
                if ($invalidCount -ge 3) {
                    Exit-WithError "Maximum number of invalid attempts reached."
                }
            }
        }
    }
}

# -------------------------------------------------------
# ENTRY POINT
# -------------------------------------------------------
Show-Menu
