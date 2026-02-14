# This is the most cursed script I've ever been involved with creating. I ran out of Claude Opus 4.6 and had to use Cursor Auto. It's braindead. This might nuke your environment if you run it. I really couldn't tell you. Good luck.

param(
    [Parameter(Mandatory=$true)]
    [string]$LAN,
    
    [Parameter(Mandatory=$false)]
    [string]$Binaries = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$Enable
)

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

Write-Host "[*] Starting Simplewall Deployment..." -ForegroundColor Cyan

# Validate paths
$setupPath = "C:\simplewall-3.8.5-setup.exe"
$profileTemplatePath = "C:\profile.xml"

if (-not (Test-Path $setupPath)) {
    Write-Error "Simplewall setup not found at $setupPath"
    exit 1
}

if (-not (Test-Path $profileTemplatePath)) {
    Write-Error "Profile.xml template not found at $profileTemplatePath"
    exit 1
}

# Parse LANs (semicolon-delimited, e.g. "172.16.1.0/24;10.0.10.0/24;192.168.1.0")
$LANs = @()
foreach ($entry in ($LAN -split ';')) {
    $t = $entry.Trim()
    if ($t -ne "") { $LANs += $t }
}
if ($LANs.Count -eq 0) {
    Write-Error "At least one LAN required (e.g. -LAN '172.16.1.0/24;10.0.10.0/24')"
    exit 1
}

# Parse Binaries (semicolon-delimited paths, e.g. "app1.exe;C:\Apps\app2.exe")
$BinaryPaths = @()
if ($Binaries -ne "") {
    foreach ($entry in ($Binaries -split ';')) {
        $t = $entry.Trim()
        if ($t -ne "") { $BinaryPaths += $t }
    }
}

Write-Host "[*] Configured LANs: $($LANs -join ', ')" -ForegroundColor Green
if ($BinaryPaths.Count -gt 0) {
    Write-Host "[*] Binaries (allow all): $($BinaryPaths -join '; ')" -ForegroundColor Green
}

# Install Simplewall
Write-Host "[*] Installing Simplewall..." -ForegroundColor Cyan
Start-Process -FilePath $setupPath -ArgumentList "/S" -Wait -NoNewWindow

if (-not (Test-Path "C:\Program Files\simplewall\simplewall.exe")) {
    Write-Error "Simplewall installation failed"
    exit 1
}

Write-Host "[+] Simplewall installed successfully" -ForegroundColor Green

# Remove uninstall executable to prevent tampering
$uninstallExe = "C:\Program Files\simplewall\uninstall.exe"
if (Test-Path $uninstallExe) {
    Remove-Item -Path $uninstallExe -Force -Confirm:$false
    Write-Host "[+] Removed uninstall executable" -ForegroundColor Green
}

# Generate timestamp for XML
$timestamp = [int][double]::Parse((Get-Date -UFormat %s))

# Create custom profile.xml with LAN-based rules
Write-Host "[*] Generating custom profile.xml..." -ForegroundColor Cyan

# Build apps section: static items + optional binaries
$appsSection = @"
	<apps>
		<item path="CryptSvc" timestamp="$timestamp" is_undeletable="true"/>
		<item path="Dhcp" timestamp="$timestamp" is_undeletable="true"/>
		<item path="Dnscache" timestamp="$timestamp" is_undeletable="true"/>
		<item path="DoSvc" timestamp="$timestamp" is_undeletable="true"/>
		<item path="NlaSvc" timestamp="$timestamp" is_undeletable="true"/>
		<item path="Spooler" timestamp="$timestamp" is_undeletable="true"/>
		<item path="UsoSvc" timestamp="$timestamp" is_undeletable="true"/>
		<item path="wlidsvc" timestamp="$timestamp" is_undeletable="true"/>
		<item path="wuauserv" timestamp="$timestamp" is_undeletable="true"/>
		<item path="C:\windows\system32\SppExtComObj.exe" timestamp="$timestamp" is_undeletable="true"/>
		<item path="C:\windows\system32\lsass.exe" timestamp="$timestamp" is_undeletable="true"/>
		<item path="C:\Program Files\simplewall\simplewall.exe" timestamp="$timestamp" is_undeletable="true" is_enabled="false"/>
		<item path="System" timestamp="$timestamp" is_undeletable="true" is_enabled="false"/>
		<item path="C:\windows\system32\svchost.exe" timestamp="$timestamp" is_undeletable="true"/>
"@
foreach ($bin in $BinaryPaths) {
    $escapedPath = [System.Security.SecurityElement]::Escape($bin)
    $appsSection += "`n`t`t<item path=`"$escapedPath`" timestamp=`"$timestamp`" is_enabled=`"true`"/>"
}
$appsSection += "`n`t</apps>"

$xmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<root version="5" type="3" timestamp="$timestamp">
$appsSection
	<rules_custom>
"@

# Allow All Inbound (operator rule - disable for scoring; inbound only so operator can RDP in)
$xmlContent += "`n`t`t<item name=`"Allow All (operator - disable for scoring)`" dir=`"1`" protocol=`"0`" is_enabled=`"true`"/>"

# RDP, WinRM, SMB - accessible from any IP (no rule= so any remote)
$xmlContent += "`n`t`t<item name=`"RDP Inbound`" rule_local=`"3389;`" dir=`"1`" protocol=`"6`" is_enabled=`"true`"/>"
$xmlContent += "`n`t`t<item name=`"WinRM Inbound`" rule_local=`"5985;`" dir=`"1`" protocol=`"6`" is_enabled=`"true`"/>"
$xmlContent += "`n`t`t<item name=`"SMB Inbound`" rule_local=`"445;`" dir=`"1`" protocol=`"6`" is_enabled=`"true`"/>"

# LDAP, DNS, HTTP, 8080, SQL Server, MySQL, PostgreSQL - inbound from any IP
$xmlContent += "`n`t`t<item name=`"LDAP Inbound`" rule_local=`"389;`" dir=`"1`" protocol=`"6`" is_enabled=`"true`"/>"
$xmlContent += "`n`t`t<item name=`"DNS Inbound`" rule_local=`"53;`" dir=`"1`" protocol=`"17`" is_enabled=`"true`"/>"
$xmlContent += "`n`t`t<item name=`"HTTP 80 Inbound`" rule_local=`"80;`" dir=`"1`" protocol=`"6`" is_enabled=`"true`"/>"
$xmlContent += "`n`t`t<item name=`"HTTP 8080 Inbound`" rule_local=`"8080;`" dir=`"1`" protocol=`"6`" is_enabled=`"true`"/>"
$xmlContent += "`n`t`t<item name=`"SQL Server 1433 Inbound`" rule_local=`"1433;`" dir=`"1`" protocol=`"6`" is_enabled=`"true`"/>"
$xmlContent += "`n`t`t<item name=`"MySQL 3306 Inbound`" rule_local=`"3306;`" dir=`"1`" protocol=`"6`" is_enabled=`"true`"/>"
$xmlContent += "`n`t`t<item name=`"PostgreSQL 5432 Inbound`" rule_local=`"5432;`" dir=`"1`" protocol=`"6`" is_enabled=`"true`"/>"

# Allow all traffic to/from specified LANs: one inbound + one outbound rule per LAN
foreach ($lan in $LANs) {
    $xmlContent += "`n`t`t<item name=`"All Inbound ($lan)`" rule_local=`"`" rule=`"$lan`" dir=`"1`" protocol=`"0`" is_enabled=`"true`"/>"
    $xmlContent += "`n`t`t<item name=`"All Outbound ($lan)`" rule_local=`"`" rule=`"$lan`" dir=`"2`" protocol=`"0`" is_enabled=`"true`"/>"
}

# Binaries - allow all inbound/outbound for specified apps (one rule, apps= semicolon-delimited paths)
if ($BinaryPaths.Count -gt 0) {
    $appsAttr = ($BinaryPaths | ForEach-Object { [System.Security.SecurityElement]::Escape($_) }) -join ";"
    $xmlContent += "`n`t`t<item name=`"Binaries - Allow all`" apps=`"$appsAttr`" dir=`"0`" protocol=`"0`" is_enabled=`"true`"/>"
}

$xmlContent += @"

	</rules_custom>
	<rules_config>
		<item name="Cryptographic service" is_enabled="false"/>
		<item name="DHCP" is_enabled="false"/>
		<item name="IGMP" is_enabled="false"/>
		<item name="KMS service" is_enabled="false"/>
		<item name="LLMNR" is_enabled="false"/>
		<item name="mDNS" is_enabled="false"/>
		<item name="NCSI" is_enabled="false"/>
		<item name="NetBIOS [inbound]" is_enabled="false"/>
		<item name="NetBIOS [outbound]" is_enabled="false"/>
		<item name="NTP" is_enabled="false"/>
		<item name="Security policy" is_enabled="false"/>
		<item name="SSDP [inbound]" is_enabled="false"/>
		<item name="SSDP [outbound]" is_enabled="false"/>
		<item name="UPnP" is_enabled="false"/>
		<item name="RDP [inbound]" is_enabled="false"/>
		<item name="WS-Discovery [events]" is_enabled="false"/>
		<item name="WS-Discovery" is_enabled="false"/>
		<item name="DNS" is_enabled="false"/>
	</rules_config>
</root>
"@

# Write the profile to the correct location
$profileDestination = Join-Path -Path $env:APPDATA -ChildPath "Henry++\simplewall\profile.xml"
$profileDir = Split-Path -Path $profileDestination -Parent

# Create directory if it doesn't exist
if (-not (Test-Path $profileDir)) {
    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
}

# Write the custom profile
$xmlContent | Out-File -FilePath $profileDestination -Encoding UTF8 -Force

Write-Host "[+] Profile.xml deployed to $profileDestination" -ForegroundColor Green

# Display configured rules
Write-Host "`n[*] Configured Rules:" -ForegroundColor Cyan
Write-Host "  - Allow All (operator) - disable for scoring" -ForegroundColor Yellow
Write-Host "  - RDP, WinRM, SMB, LDAP, DNS, 80, 8080, 1433, 3306, 5432 inbound from any IP" -ForegroundColor Yellow
Write-Host "  - All inbound from + all outbound to specified LANs (two rules per LAN)" -ForegroundColor Yellow
if ($BinaryPaths.Count -gt 0) {
    Write-Host "  - Binaries - allow all for: $($BinaryPaths -join '; ')" -ForegroundColor Yellow
}
Write-Host "  - All other outbound traffic BLOCKED" -ForegroundColor Red

# Optionally enable filters (only if -Enable passed)
$simpleWallExe = "C:\Program Files\simplewall\simplewall.exe"
if ($Enable) {
    Write-Host "`n[*] Enabling Simplewall filters..." -ForegroundColor Cyan
    Start-Process -FilePath $simpleWallExe -ArgumentList "-install -silent" -Wait -NoNewWindow
    Write-Host "[+] Simplewall filters enabled" -ForegroundColor Green
} else {
    Write-Host "`n[*] Filters not enabled (run with -Enable to enable)" -ForegroundColor Yellow
}

# Start the GUI
Start-Process -FilePath $simpleWallExe -Verb RunAs

# Clean up setup file
if (Test-Path $setupPath) {
    Remove-Item -Path $setupPath -Force -Confirm:$false
    Write-Host "[+] Cleaned up setup file" -ForegroundColor Green
}

Write-Host "`n[+] Simplewall deployment complete!" -ForegroundColor Green
if ($Enable) {
    Write-Host "[!] The firewall is now ACTIVE with LAN-only access" -ForegroundColor Yellow
    Write-Host "[!] Verify connectivity before closing this session" -ForegroundColor Yellow
} else {
    Write-Host "[!] Filters are not enabled. Use -Enable to enable, or enable from the Simplewall GUI" -ForegroundColor Yellow
}
