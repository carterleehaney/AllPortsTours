# Splunk Universal Forwarder Installer for Windows
# CraniacCombo CCDC | Merged from MSU-BlueScripts + TTU CCDC
# Deploy via Tomoe:
#   python tomoe.py smb -i hosts.txt -u Admin -p Pass --source ./splunk-configs --dest "C:\Windows\Temp\splunk-configs"
#   python tomoe.py smb -i hosts.txt -u Admin -p Pass -s ./Splunk.ps1 -a "-ip 10.0.0.5 -password SplunkPass -type member"
#
# Offline/Local Install:
#   .\Splunk.ps1 -ip 10.0.0.5 -password SplunkPass -localFolder "C:\offline\splunk-configs"
#   Expected folder structure:
#     C:\offline\splunk-configs\
#       splunk-configs\           # Config files (.conf, .xml, .tgz)
#       splunkforwarder.msi       # Pre-downloaded installer

param (
    [Parameter(Mandatory = $true)]
    [string]$ip,

    [Parameter(Mandatory = $true)]
    [string]$password,

    [Parameter(Mandatory = $false)]
    [ValidateSet("dc", "member", "auto")]
    [string]$type = "auto",

    [Parameter(Mandatory = $false)]
    [string]$version = "",

    [Parameter(Mandatory = $false)]
    [int]$arch = 64,

    [Parameter(Mandatory = $false)]
    [string]$configPath = "C:\",

    [Parameter(Mandatory = $false)]
    [string]$githubUrl = "https://raw.githubusercontent.com/Jmilton42/SOC-scripts/main",

    [Parameter(Mandatory = $false)]
    [string]$localFolder = ""
)

################### DOWNLOAD URLS ###################
$9_2_5_x64 = "https://download.splunk.com/products/universalforwarder/releases/9.2.5/windows/splunkforwarder-9.2.5-7bfc9a4ed6ba-x64-release.msi"
$9_2_5_x86 = "https://download.splunk.com/products/universalforwarder/releases/9.2.5/windows/splunkforwarder-9.2.5-7bfc9a4ed6ba-x86-release.msi"
$9_1_6_x64 = "https://download.splunk.com/products/universalforwarder/releases/9.1.6/windows/splunkforwarder-9.1.6-a28f08fac354-x64-release.msi"
$9_1_6_x86 = "https://download.splunk.com/products/universalforwarder/releases/9.1.6/windows/splunkforwarder-9.1.6-a28f08fac354-x86-release.msi"
$7_3_9_x64 = "https://download.splunk.com/products/universalforwarder/releases/7.3.9/windows/splunkforwarder-7.3.9-39a78bf1bc5b-x64-release.msi"
$7_3_9_x86 = "https://download.splunk.com/products/universalforwarder/releases/7.3.9/windows/splunkforwarder-7.3.9-39a78bf1bc5b-x86-release.msi"
$newest_x64 = $9_2_5_x64
$newest_x86 = $9_2_5_x86

$SPLUNKDIR = "C:\Program Files\SplunkUniversalForwarder"
#####################################################

##################### FUNCTIONS #####################
function Print-Info {
    param ([string]$msg)
    Write-Host "[*] $msg"
}

function Print-Error {
    param ([string]$msg)
    Write-Host "[X] ERROR: $msg" -ForegroundColor Red
}

function Print-Banner {
    param ([string]$msg)
    Write-Host ""
    Write-Host "######################################" -ForegroundColor Yellow
    Write-Host "#  $msg" -ForegroundColor Yellow
    Write-Host "######################################" -ForegroundColor Yellow
    Write-Host ""
}

function Download-File {
    param (
        [string]$url,
        [string]$path
    )

    if (Test-Path $path) {
        Remove-Item $path -Force
    }

    # Check localFolder first for offline installs
    if ($localFolder -ne "") {
        # Extract filename from URL
        $filename = Split-Path $url -Leaf
        
        # Try multiple possible locations in localFolder
        $localPaths = @(
            "$localFolder\$filename",
            "$localFolder\splunk-configs\$filename",
            "$localFolder\Windows\Scripts\splunk-configs\$filename"
        )
        
        foreach ($localPath in $localPaths) {
            if (Test-Path $localPath) {
                Print-Info "Using local file: $localPath"
                Copy-Item -Path $localPath -Destination $path -Force
                return
            }
        }
    }

    # Check if it's a local file path (pre-staged via Tomoe)
    if (Test-Path $url) {
        Print-Info "Using pre-staged file: $url"
        Copy-Item -Path $url -Destination $path -Force
        return
    }

    # Download from URL
    Print-Info "Downloading $url"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $path -ErrorAction Stop
    }
    catch {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($url, $path)
        }
        catch {
            Print-Error "Download failed: $($_.Exception.Message)"
            throw
        }
    }
}

function Detect-WindowsVersion {
    if ($version -ne "") {
        return $version
    }

    # Auto-detect Windows version
    $os = Get-CimInstance Win32_OperatingSystem
    $osVersion = $os.Version
    $caption = $os.Caption

    Print-Info "Detected: $caption ($osVersion)"

    if ($caption -match "Server 2022|Server 2019") { return "2019" }
    if ($caption -match "Server 2016") { return "2016" }
    if ($caption -match "Server 2012") { return "2012" }
    if ($caption -match "Windows 11|Windows 10") { return "10" }
    if ($caption -match "Windows 8") { return "8" }
    if ($caption -match "Windows 7") { return "7" }

    # Fallback based on major version
    $major = [int]($osVersion.Split('.')[0])
    if ($major -ge 10) { return "10" }
    if ($major -ge 6) { return "8" }
    return "7"
}

function Get-InstallerUrl {
    param ([string]$detectedVersion)

    if ($arch -eq 64) {
        switch ($detectedVersion) {
            "7" { return $7_3_9_x64 }
            "8" { return $7_3_9_x64 }
            "2012" { return $9_1_6_x64 }
            "2016" { return $9_2_5_x64 }
            { $_ -in "10", "11", "2019", "2022" } { return $newest_x64 }
            default { Print-Error "Unknown version: $detectedVersion"; return $newest_x64 }
        }
    }
    else {
        switch ($detectedVersion) {
            "7" { return $7_3_9_x86 }
            "8" { return $7_3_9_x86 }
            "2012" { return $9_1_6_x86 }
            "2016" { return $9_2_5_x86 }
            { $_ -in "10", "11", "2019", "2022" } { return $newest_x86 }
            default { Print-Error "Unknown version: $detectedVersion"; return $newest_x86 }
        }
    }
}

function Install-Splunk {
    Print-Banner "Installing Splunk Universal Forwarder"

    if (Test-Path "$SPLUNKDIR\bin\splunk.exe") {
        Print-Info "Splunk already installed at $SPLUNKDIR"
        return
    }

    # Check for pre-staged installer (including localFolder)
    $installer_path = "$pwd\splunk.msi"
    $preStaged = @(
        "C:\splunkforwarder.msi",
        "$pwd\splunkforwarder.msi",
        "C:\Windows\Temp\splunkforwarder.msi"
    )
    
    # Add localFolder paths if specified
    if ($localFolder -ne "") {
        $preStaged = @(
            "$localFolder\splunkforwarder.msi",
            "$localFolder\splunk.msi"
        ) + $preStaged
    }
    
    foreach ($path in $preStaged) {
        if (Test-Path $path) {
            Print-Info "Found pre-staged installer at $path"
            $installer_path = $path
            break
        }
    }

    if (-not (Test-Path $installer_path)) {
        $detectedVersion = Detect-WindowsVersion
        Print-Info "Windows version: $detectedVersion (arch: $arch-bit)"

        $msiUrl = Get-InstallerUrl $detectedVersion
        Download-File $msiUrl $installer_path
    }

    Print-Info "Installing Splunk (this may take a few minutes)..."
    Start-Process msiexec.exe -ArgumentList "/i `"$installer_path`" SPLUNKUSERNAME=splunk SPLUNKPASSWORD=$password USE_LOCAL_SYSTEM=1 RECEIVING_INDEXER=`"$ip`:9997`" AGREETOLICENSE=yes LAUNCHSPLUNK=1 SERVICESTARTTYPE=auto /L*v C:\Windows\Temp\splunk_install.log /quiet" -Wait -NoNewWindow

    if (Test-Path "$SPLUNKDIR\bin\splunk.exe") {
        Print-Info "Splunk installed successfully"
    }
    else {
        Print-Error "Splunk installation failed. Check C:\Windows\Temp\splunk_install.log"
        exit 1
    }
}

function Install-Sysmon {
    Print-Banner "Installing Sysmon"

    $sysmonZipPath = "$env:TEMP\Sysmon.zip"
    $sysmonConfigPath = "$env:TEMP\sysmon.xml"
    $sysmonExtract = "$env:TEMP\Sysmon"

    # Check for pre-staged sysmon config (localFolder first)
    if ($localFolder -ne "" -and (Test-Path "$localFolder\sysmon.xml")) {
        Print-Info "Using local sysmon config from $localFolder\sysmon.xml"
        $sysmonConfigPath = "$localFolder\sysmon.xml"
    }
    elseif ($localFolder -ne "" -and (Test-Path "$localFolder\splunk-configs\sysmon.xml")) {
        Print-Info "Using local sysmon config from $localFolder\splunk-configs\sysmon.xml"
        $sysmonConfigPath = "$localFolder\splunk-configs\sysmon.xml"
    }
    elseif (Test-Path "$configPath\sysmon.xml") {
        Print-Info "Using pre-staged sysmon config from $configPath\sysmon.xml"
        $sysmonConfigPath = "$configPath\sysmon.xml"
    }
    elseif (Test-Path "$PSScriptRoot\sysmon.xml") {
        Print-Info "Using local sysmon.xml"
        $sysmonConfigPath = "$PSScriptRoot\sysmon.xml"
    }
    else {
        Print-Info "Downloading sysmon config..."
        Download-File "$githubUrl/Windows/Scripts/splunk-configs/sysmon.xml" $sysmonConfigPath
    }

    # Check for pre-staged Sysmon.zip in localFolder
    if (-not (Test-Path "$sysmonExtract\Sysmon.exe")) {
        $sysmonFound = $false
        
        if ($localFolder -ne "") {
            $localSysmonPaths = @(
                "$localFolder\Sysmon.zip",
                "$localFolder\splunk-configs\Sysmon.zip"
            )
            foreach ($localPath in $localSysmonPaths) {
                if (Test-Path $localPath) {
                    Print-Info "Using local Sysmon.zip from $localPath"
                    Copy-Item $localPath $sysmonZipPath -Force
                    $sysmonFound = $true
                    break
                }
            }
        }
        
        if (-not $sysmonFound) {
            Download-File "https://download.sysinternals.com/files/Sysmon.zip" $sysmonZipPath
        }
        Expand-Archive -Path $sysmonZipPath -DestinationPath $sysmonExtract -Force
    }

    if (Test-Path "$sysmonExtract\Sysmon.exe") {
        Print-Info "Installing Sysmon with config..."
        Start-Process -FilePath "$sysmonExtract\Sysmon.exe" -ArgumentList "-accepteula -i $sysmonConfigPath" -Wait -NoNewWindow
        Print-Info "Sysmon installed"
    }
    elseif (Test-Path "$sysmonExtract\Sysmon64.exe") {
        Start-Process -FilePath "$sysmonExtract\Sysmon64.exe" -ArgumentList "-accepteula -i $sysmonConfigPath" -Wait -NoNewWindow
        Print-Info "Sysmon64 installed"
    }
    else {
        Print-Error "Sysmon executable not found"
    }
}

function Install-WindowsTA {
    Print-Banner "Installing Windows TA"

    $taTgz = "$env:TEMP\windows-ta.tgz"
    Download-File "$githubUrl/Windows/Scripts/splunk-configs/splunk-add-on-for-microsoft-windows_901.tgz" $taTgz
    & "$SPLUNKDIR\bin\splunk.exe" install app $taTgz -update 1 -auth "splunk:$password" 2>$null

    # Deploy inputs config
    $taLocalDir = "$SPLUNKDIR\etc\apps\Splunk_TA_windows\local"
    New-Item -Path $taLocalDir -ItemType Directory -Force | Out-Null

    if (Test-Path "$configPath\windows-ta-inputs.conf") {
        Print-Info "Using pre-staged windows-ta-inputs.conf"
        Copy-Item "$configPath\windows-ta-inputs.conf" "$taLocalDir\inputs.conf" -Force
    }
    else {
        Download-File "$githubUrl/Windows/Scripts/splunk-configs/windows-ta-inputs.conf" "$taLocalDir\inputs.conf"
    }

    # Enable AD monitoring for domain controllers
    if ($type -eq "dc") {
        Print-Info "Enabling Active Directory monitoring for DC"
        "`n[admon://default]`ndisabled=0`nmonitorSubtree=1" | Out-File -Append -Encoding ascii "$taLocalDir\inputs.conf"
    }

    # Ensure WinNetMon captures ALL outbound connections (not just private IPs)
    $inputsContent = Get-Content "$taLocalDir\inputs.conf" -Raw
    if ($inputsContent -match 'remoteAddress\s*=.*Private IPs') {
        $inputsContent = $inputsContent -replace 'remoteAddress\s*=.*', 'remoteAddress = .*'
        Set-Content "$taLocalDir\inputs.conf" $inputsContent
        Print-Info "WinNetMon: expanded to monitor ALL outbound IPs"
    }

    Print-Info "Windows TA installed"
}

function Install-SysmonTA {
    Print-Banner "Installing Sysmon TA"

    $taTgz = "$env:TEMP\sysmon-ta.tgz"
    Download-File "$githubUrl/Windows/Scripts/splunk-configs/splunk-add-on-for-sysmon_402.tgz" $taTgz
    & "$SPLUNKDIR\bin\splunk.exe" install app $taTgz -update 1 -auth "splunk:$password" 2>$null

    $taLocalDir = "$SPLUNKDIR\etc\apps\Splunk_TA_microsoft_sysmon\local"
    New-Item -Path $taLocalDir -ItemType Directory -Force | Out-Null

    if (Test-Path "$configPath\sysmon-ta-inputs.conf") {
        Print-Info "Using pre-staged sysmon-ta-inputs.conf"
        Copy-Item "$configPath\sysmon-ta-inputs.conf" "$taLocalDir\inputs.conf" -Force
    }
    else {
        Download-File "$githubUrl/Windows/Scripts/splunk-configs/sysmon-ta-inputs.conf" "$taLocalDir\inputs.conf"
    }

    Print-Info "Sysmon TA installed"
}

function Install-IISTA {
    Print-Banner "Installing IIS TA"

    # Only install if IIS is present
    if (-not (Test-Path "C:\inetpub")) {
        Print-Info "IIS not detected, skipping IIS TA"
        return
    }

    $taTgz = "$env:TEMP\iis-ta.tgz"
    Download-File "$githubUrl/Windows/Scripts/splunk-configs/splunk-add-on-for-microsoft-iis_200.tgz" $taTgz
    & "$SPLUNKDIR\bin\splunk.exe" install app $taTgz -update 1 -auth "splunk:$password" 2>$null

    # Enable IIS log monitoring
    $taLocalDir = "$SPLUNKDIR\etc\apps\Splunk_TA_microsoft_iis\local"
    New-Item -Path $taLocalDir -ItemType Directory -Force | Out-Null

    $iisInputs = @"
[monitor://C:\inetpub\logs\LogFiles]
disabled = 0
sourcetype = iis
index = web
"@
    $iisInputs | Out-File -Encoding ascii "$taLocalDir\inputs.conf"
    Print-Info "IIS TA installed with log monitoring"
}

function Install-ADTA {
    Print-Banner "Installing AD Supporting TA"

    $taTgz = "$env:TEMP\ad-ta.tgz"
    Download-File "$githubUrl/Windows/Scripts/splunk-configs/splunk-supporting-add-on-for-active-directory_320.tgz" $taTgz
    & "$SPLUNKDIR\bin\splunk.exe" install app $taTgz -update 1 -auth "splunk:$password" 2>$null

    Print-Info "AD Supporting TA installed (configure LDAP searches in Splunk Web)"
}

function Install-CustomInputs {
    # Fallback for older Windows versions that don't support TAs
    Print-Banner "Installing custom inputs (legacy)"

    if (Test-Path "$configPath\custom-inputs.conf") {
        Copy-Item "$configPath\custom-inputs.conf" "$SPLUNKDIR\etc\apps\SplunkUniversalForwarder\local\inputs.conf" -Force
    }
    else {
        Download-File "$githubUrl/Splunk/windows/custom-inputs.conf" "$SPLUNKDIR\etc\apps\SplunkUniversalForwarder\local\inputs.conf"
    }

    Print-Info "Custom inputs installed"
}

function Enable-DNSClientLog {
    Print-Banner "Enabling DNS Client event log"

    # Enable DNS Client operational log for C2 detection
    try {
        wevtutil set-log "Microsoft-Windows-DNS-Client/Operational" /enabled:true 2>$null
        Print-Info "DNS Client operational log enabled"
    }
    catch {
        Print-Info "DNS Client log may already be enabled or not available"
    }

    # Add DNS Client event log monitor if not already in TA config
    $dnsMonitor = @"

[WinEventLog://Microsoft-Windows-DNS-Client/Operational]
disabled = 0
start_from = oldest
current_only = 0
checkpointInterval = 5
renderXml = false
index = windows
"@
    $taInputs = "$SPLUNKDIR\etc\apps\Splunk_TA_windows\local\inputs.conf"
    if (Test-Path $taInputs) {
        $content = Get-Content $taInputs -Raw
        if ($content -notmatch "DNS-Client") {
            Add-Content $taInputs $dnsMonitor
            Print-Info "DNS Client monitor added to Windows TA inputs"
        }
    }
}

function Add-WebLogs {
    Print-Banner "Adding web server logs"

    if (Test-Path "C:\inetpub\logs\LogFiles\") {
        & "$SPLUNKDIR\bin\splunk.exe" add monitor "C:\inetpub\logs\LogFiles\" -index web -auth "splunk:$password" 2>$null
        Print-Info "IIS logs added"
    }
    else {
        Print-Info "No IIS logs found (C:\inetpub\logs\LogFiles\ does not exist)"
    }
}

function Add-RedBaronLogs {
    Print-Banner "Adding RedBaron logs"
    
    # GoodRedBaron (Windows) log paths - set via RB_PATH1/RB_PATH2 at compile time
    # Default recommended paths:
    $rbPaths = @(
        "C:\ProgramData\RedBaron\redbaron.log",
        "C:\ProgramData\redbaron.log",
        "C:\RedBaron\redbaron.log",
        "C:\ProgramData\RedBaron\",
        "C:\RedBaron\"
    )
    
    $foundLogs = $false
    foreach ($path in $rbPaths) {
        if (Test-Path $path) {
            & "$SPLUNKDIR\bin\splunk.exe" add monitor "$path" -index edr -sourcetype "redbaron:yara" -auth "splunk:$password" 2>$null
            Print-Info "RedBaron log added: $path"
            $foundLogs = $true
        }
    }
    
    if (-not $foundLogs) {
        # Pre-create directories for when RedBaron is deployed
        Print-Info "No RedBaron logs found. Creating directories for future use..."
        New-Item -Path "C:\ProgramData\RedBaron" -ItemType Directory -Force | Out-Null
        
        # Pre-configure monitor (will activate when logs appear)
        & "$SPLUNKDIR\bin\splunk.exe" add monitor "C:\ProgramData\RedBaron\" -index edr -sourcetype "redbaron:yara" -auth "splunk:$password" 2>$null
        Print-Info "RedBaron monitors pre-configured (logs will appear when RedBaron is deployed)"
    }
}

function Enable-FirewallLogging {
    Print-Banner "Enabling Windows Firewall logging"

    netsh advfirewall set allprofiles logging allowedconnections enable 2>$null
    netsh advfirewall set allprofiles logging droppedconnections enable 2>$null

    & "$SPLUNKDIR\bin\splunk.exe" add monitor "C:\Windows\System32\LogFiles\Firewall\pfirewall.log" -index network -auth "splunk:$password" 2>$null
    Print-Info "Firewall logging enabled and monitored"
}

function Enable-PowerShellLogging {
    Print-Banner "Enabling PowerShell script block logging"

    # Enable script block logging via registry
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1 -Type DWord

    # Enable module logging
    $regPath2 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
    if (-not (Test-Path $regPath2)) {
        New-Item -Path $regPath2 -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath2 -Name "EnableModuleLogging" -Value 1 -Type DWord

    # Enable transcription
    $regPath3 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription"
    if (-not (Test-Path $regPath3)) {
        New-Item -Path $regPath3 -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath3 -Name "EnableTranscripting" -Value 1 -Type DWord
    Set-ItemProperty -Path $regPath3 -Name "OutputDirectory" -Value "C:\PSTranscripts" -Type String

    # Monitor PowerShell event logs
    & "$SPLUNKDIR\bin\splunk.exe" add monitor "C:\PSTranscripts" -index windows -sourcetype "powershell:transcript" -auth "splunk:$password" 2>$null

    Print-Info "PowerShell logging enabled (script block, module, transcription)"
}
#####################################################

######################## MAIN #######################
Print-Banner "Splunk Forwarder Deployment for Windows"
Print-Info "Indexer: $ip | Type: $type | Config: $configPath"
if ($localFolder -ne "") {
    Print-Info "Local Folder: $localFolder (offline mode)"
}

# Set TLS 1.2 for older systems
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Validate IP
$regex = '\b(([01]?\d?\d|2[0-4]\d|25[0-5])\.){3}([01]?\d?\d|2[0-4]\d|25[0-5])\b'
if (-not ($ip -match $regex)) {
    Print-Error "Invalid IP address: $ip"
    exit 1
}

# Auto-detect DC role if type is 'auto'
if ($type -eq "auto") {
    $domainRole = (Get-WmiObject -Class Win32_ComputerSystem).DomainRole
    if ($domainRole -eq 4 -or $domainRole -eq 5) {
        $type = "dc"
        $roleLabel = if ($domainRole -eq 5) { "Primary DC" } else { "Backup DC" }
        Print-Info "Auto-detected: $roleLabel (DomainRole=$domainRole) -> type=dc"
    }
    else {
        $type = "member"
        Print-Info "Auto-detected: Member server (DomainRole=$domainRole) -> type=member"
    }
}

# Install Splunk
Install-Splunk

# Install Sysmon
Install-Sysmon

# Detect version for TA compatibility
$detectedVersion = Detect-WindowsVersion
Print-Info "Detected Windows version: $detectedVersion"

if ($detectedVersion -eq "7" -or $detectedVersion -eq "8") {
    # Older Windows - use custom inputs (TAs not fully supported)
    Install-CustomInputs
    Enable-FirewallLogging
}
else {
    # Modern Windows - use TAs
    Install-WindowsTA
    Install-SysmonTA
    Install-IISTA
    Enable-DNSClientLog
    Enable-FirewallLogging
    Enable-PowerShellLogging

    # Install AD TA on domain controllers
    if ($type -eq "dc") {
        Install-ADTA
    }
}

# Add web logs
Add-WebLogs

# Add RedBaron logs
Add-RedBaronLogs

# Restart Splunk to apply
Print-Banner "Restarting Splunk Forwarder"
Restart-Service SplunkForwarder -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

if (Get-Service SplunkForwarder -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Running" }) {
    Print-Info "Splunk Forwarder is running"
}
else {
    Print-Info "Starting Splunk Forwarder..."
    Start-Service SplunkForwarder -ErrorAction SilentlyContinue
}

Print-Banner "Deployment Complete"
Write-Host "  Indexer:   $ip`:9997"
Write-Host "  Home:      $SPLUNKDIR"
Write-Host "  Type:      $type"
Write-Host "  Sysmon:    Installed"
Write-Host "  PS Logging: Enabled"
Write-Host ""
Print-Info "DONE"
#####################################################
