param(
    [String]$ScriptArgs = ""
)

$ArgumentsArray = $ScriptArgs -split ";"
if ($ArgumentsArray.Length -lt 1) {
    Write-Host "Not enough arguments provided." -ForegroundColor Red
    break
}
$Manager = $ArgumentsArray[0]
if ($ArgumentsArray[1]) {
    $RegistrationPassword = $ArgumentsArray[1]
} else {
    $RegistrationPassword = ""
}

$ErrorActionPreference = "Continue"
$WazuhSuccess = $false
$SysmonSuccess = $false

# Check if Wazuh is already installed
if (Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue) {
    Write-Host "Wazuh Agent is already installed. Skipping installation." -ForegroundColor Green
    $WazuhSuccess = $true
} else {
    # Download and Install Wazuh Agent
    Write-Host "Downloading Wazuh Agent..." -ForegroundColor Yellow
    $DownloadPath = "$env:tmp\wazuh-agent.msi"
    try {
        Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.1-1.msi" -OutFile $DownloadPath -UseBasicParsing
        Write-Host "Wazuh Agent downloaded successfully." -ForegroundColor Green
        
        Write-Host "Installing Wazuh Agent..." -ForegroundColor Yellow
        $InstallCommand = "msiexec.exe /i `"$DownloadPath`" /q WAZUH_MANAGER=$Manager"
        if ($RegistrationPassword -ne "") {
            $InstallCommand += " WAZUH_REGISTRATION_PASSWORD=$RegistrationPassword"
        }
        
        cmd.exe /c $InstallCommand
        Start-Sleep -Seconds 5
        
        sc.exe config WazuhSvc start= auto
        sc.exe start WazuhSvc
        Start-Sleep -Seconds 3
        
        if (sc.exe query WazuhSvc | Select-String "RUNNING") {
            Write-Host "Wazuh agent is running." -ForegroundColor Green
            $WazuhSuccess = $true
        } else {
            Write-Host "Wazuh agent is NOT running." -ForegroundColor Red
        }
    } catch {
        Write-Host "Error downloading/installing Wazuh Agent: $_" -ForegroundColor Red
    }
}

# Check if Sysmon is already installed
$SysmonService = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
if (-not $SysmonService) {
    $SysmonService = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue
}

if ($SysmonService) {
    Write-Host "`nSysmon is already installed. Skipping installation." -ForegroundColor Green
    $SysmonSuccess = $true
} else {
    # Download and Install Sysmon
    Write-Host "`nDownloading Sysmon..." -ForegroundColor Cyan
    $workDir = "$env:tmp\sysmon_install"
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    
    try {
        $sysmonZip = "$workDir\Sysmon.zip"
        Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile $sysmonZip -UseBasicParsing
        Write-Host "Extracting Sysmon..." -ForegroundColor Yellow
        
        # Extract Sysmon
        Expand-Archive -Path $sysmonZip -DestinationPath "$workDir\Sysmon" -Force
        
        # Determine which Sysmon executable to use (64-bit or 32-bit)
        $sysmonExe = "$workDir\Sysmon\Sysmon64.exe"
        if (-not (Test-Path $sysmonExe)) {
            $sysmonExe = "$workDir\Sysmon\Sysmon.exe"
        }
        
        if (Test-Path $sysmonExe) {
            Write-Host "Installing Sysmon..." -ForegroundColor Yellow
            
            # Find sysmon.xml
            $sysmonXml = "C:\sysmon.xml"
            
            if (Test-Path $sysmonXml) {
                Write-Host "Found sysmon.xml at: $sysmonXml" -ForegroundColor Green
                # Install Sysmon with the configuration file
                $installArgs = "-accepteula -i `"$sysmonXml`""
                Start-Process -FilePath $sysmonExe -ArgumentList $installArgs -Wait -NoNewWindow
                Write-Host "Sysmon installed successfully with configuration." -ForegroundColor Green
                $SysmonSuccess = $true
            } else {
                Write-Host "Warning: sysmon.xml not found at C:\sysmon.xml" -ForegroundColor Yellow
                # Install Sysmon without config
                Start-Process -FilePath $sysmonExe -ArgumentList "-accepteula -i" -Wait -NoNewWindow
                Write-Host "Sysmon installed (please configure manually)." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Error: Sysmon executable not found after extraction." -ForegroundColor Red
        }
    } catch {
        Write-Host "Error downloading/installing Sysmon: $_" -ForegroundColor Red
    }
}


try {
    Restart-Service -Name "wazuh" -ErrorAction SilentlyContinue
    Write-Host "Wazuh service restarted." -ForegroundColor Green
} catch {
    Write-Host "Could not restart Wazuh service." -ForegroundColor Red
}

Write-Host "`nInstallation Summary:" -ForegroundColor Cyan
if ($WazuhSuccess) {
    Write-Host "  - Wazuh Agent: OK" -ForegroundColor Green
} else {
    Write-Host "  - Wazuh Agent: FAILED" -ForegroundColor Red
}
if ($SysmonSuccess) {
    Write-Host "  - Sysmon: OK" -ForegroundColor Green
} else {
    Write-Host "  - Sysmon: FAILED" -ForegroundColor Red
}
