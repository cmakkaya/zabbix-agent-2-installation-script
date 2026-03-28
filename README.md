# Zabbix Agent 2 installation script

This script installs Zabbix Agent 2.
<img width="900" height="815" alt="image" src="https://github.com/user-attachments/assets/466a44d5-b22f-4941-884e-b63835b5c818" />

----------

## Hi there, <img src = "https://github.com/cmakkaya/cmakkaya/blob/main/wavehand.gif" width = "40" align="center"> Nice to see you. <img src="https://emojis.slackmojis.com/emojis/images/1531849430/4246/blob-sunglasses.gif?1531849430" width="40"/>  

✏️ Don't forget to follow [my LinkedIn account](https://www.linkedin.com/in/cumhurakkaya/) or [my Medium account](https://cmakkaya.medium.com/)  to be informed about new updates in the repository.

I hope they are useful to you.

🙏 I wish you growing success.


-------------------------------------------------------
## USING THE SCRİPT
-------------------------------------------------------

### FOR WİNDOWS

Run the script by specifying its location in the following command to launch the script.

```sh
& "C:\zabbix_agent2_7.4_tr_win.ps1"
```

<img width="896" height="70" alt="image" src="https://github.com/user-attachments/assets/8955ea28-d5d7-44e2-84da-67f971bea575" />


#### CAUTION FOR WİNDOWS 11

In Windows 11, PowerShell blocks script execution by default. If the script is opening and closing, that's most likely the reason.

To fix this error:
<img width="1137" height="206" alt="image" src="https://github.com/user-attachments/assets/46384075-75de-46fb-8a61-042017aa75a6" />

1) Open PowerShell as "Run as Administrator."

2) Run the following command:

```sh
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

3) Then run the script:

```sh
& "C:\zabbix_agent2_7.4_tr_win.ps1"Z
```

### FOR LİNUX 

<img width="610" height="67" alt="image" src="https://github.com/user-attachments/assets/a4767f5f-d168-49df-b99d-cd371cae6fc9" />

Get root access

```sh
sudo -s
```

First, grant executable permissions using

```sh
chmod +x zabbix-agent2_7.4_tr_ubuntu.sh
```

To launch the script:

```sh
./zabbix-agent2_7.4_tr_ubuntu.sh
OR
bash zabbix-agent2_7.4_tr_ubuntu.sh
```

<img width="949" height="668" alt="image" src="https://github.com/user-attachments/assets/177a737f-264d-4d59-b215-77388d72b668" />


-------------------------------------------------------
## TO INSTALL A DIFFERENT VERSION OF ZABBIX AGENT 2
-------------------------------------------------------

If you want to install a different version, both the AGENT2_VERSION and AGENT2_MSI_URL lines need to be updated together in the "CONSTANT VARIABLES" section of the script.

For Example:

$AGENT2_VERSION     = "7.0.24"

$AGENT2_MSI_URL     = "https://cdn.zabbix.com/zabbix/binaries/stable/7.0/7.0.24/zabbix_agent-7.0.24-windows-amd64-openssl.msi"

You can check the latest versions of Zabbix Agent 2 on this page:

https://cdn.zabbix.com/zabbix/binaries/stable/7.4/7.4.8/zabbix_agent-7.4.8-windows-amd64-openssl.msi

-------------------------------------------------------
## CONSTANT VARIABLES - You can also adjust these values ​​if necessary:
-------------------------------------------------------

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

-------------------------------------------------------
##  CONTROL:
-------------------------------------------------------

Is there a new line in the agent log? 


```sh
Get-Content "C:\Program Files\Zabbix Agent 2\zabbix_agent2.log" -Wait -Tail 5
```

-------------------------------------------------------
##  References:
-------------------------------------------------------
    [1] Zabbix Agent 2 Windows Install:
        https://www.zabbix.com/documentation/7.4/en/manual/installation/install_from_packages/win_msi
    [2] Zabbix PSK Encryption:
        https://www.zabbix.com/documentation/7.4/en/manual/encryption/using_pre_shared_keys
    [3] Zabbix Agent 2 Config Parameters:
        https://www.zabbix.com/documentation/7.4/en/manual/appendix/config/zabbix_agent2_win
    [4] MSI Silent Install (msiexec):
        https://learn.microsoft.com/en-us/windows/win32/msi/command-line-options
    [5] Windows Firewall via PowerShell:
        https://learn.microsoft.com/en-us/powershell/module/netsecurity/new-netfirewallrule

-------------------------------------------------------

## Connect with me 📫 You can learn more about me

- 🌐 [LinkedIn](https://www.linkedin.com/in/cumhurakkaya/)
- ✏️ [Medium Articles](https://cmakkaya.medium.com/)  100+ Articles
- 🌐 [GitHub](https://github.com/cmakkaya/)
