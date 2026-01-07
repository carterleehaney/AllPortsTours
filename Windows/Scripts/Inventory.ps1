# Windows Inventory Script
# Comprehensive system inventory and security audit for Windows Server 2008 - Windows 11
# Modeled after Inventory.sh

#Requires -Version 2.0

# ============================================================================
# CONFIGURATION AND SETUP
# ============================================================================

# Debug mode - set $env:DEBUG = 1 to enable verbose error output
$Script:DebugMode = $env:DEBUG -eq "1"

# Color configuration
$Script:Colors = @{
    Green  = "Green"
    Blue   = "Cyan"
    Yellow = "Yellow"
    Red    = "Red"
    Orange = "DarkYellow"
}

function Write-Banner {
    param([string]$Text)
    Write-Host ""
    Write-Host "##################################" -ForegroundColor $Script:Colors.Green
    Write-Host "#                                #" -ForegroundColor $Script:Colors.Green
    Write-Host ("#" + $Text.PadLeft(17 + [math]::Floor($Text.Length/2)).PadRight(32) + "#") -ForegroundColor $Script:Colors.Green
    Write-Host "#                                #" -ForegroundColor $Script:Colors.Green
    Write-Host "##################################" -ForegroundColor $Script:Colors.Green
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host ("#############" + $Text + "############") -ForegroundColor $Script:Colors.Green
    Write-Host ""
}

function Write-Info {
    param(
        [string]$Label,
        [string]$Value
    )
    Write-Host "[+] ${Label}: " -ForegroundColor $Script:Colors.Blue -NoNewline
    Write-Host $Value -ForegroundColor $Script:Colors.Yellow
}

function Write-Label {
    param([string]$Text)
    Write-Host "[+] $Text" -ForegroundColor $Script:Colors.Blue
}

function Write-Data {
    param([string]$Text)
    if ($Text) {
        Write-Host $Text -ForegroundColor $Script:Colors.Yellow
    }
}

function Write-Warning-Custom {
    param([string]$Text)
    Write-Host "[!] $Text" -ForegroundColor $Script:Colors.Red
}

function Write-ServiceFound {
    param([string]$ServiceName)
    Write-Host ""
    Write-Host "[+] $ServiceName is on this machine" -ForegroundColor $Script:Colors.Blue
    Write-Host ""
}

# Wrapper for commands - suppresses errors in non-debug mode
function Invoke-SafeCommand {
    param(
        [scriptblock]$Command
    )
    try {
        if ($Script:DebugMode) {
            & $Command
        } else {
            & $Command 2>$null
        }
    } catch {
        if ($Script:DebugMode) {
            Write-Host "Error: $_" -ForegroundColor Red
        }
        return $null
    }
}

# Check if running as Administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Detect OS version for compatibility
function Get-OSVersion {
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $version = [System.Version]$os.Version
    return @{
        Major = $version.Major
        Minor = $version.Minor
        Build = $version.Build
        Caption = $os.Caption
        Architecture = $os.OSArchitecture
        IsServer = $os.Caption -match "Server"
        # Windows 8/Server 2012 = 6.2, Windows 7/2008R2 = 6.1, Windows Vista/2008 = 6.0
        IsModern = ($version.Major -gt 6) -or ($version.Major -eq 6 -and $version.Minor -ge 2)
    }
}

$Script:OSInfo = Get-OSVersion
$Script:IsAdmin = Test-Administrator

# ============================================================================
# COMPATIBILITY HELPER FUNCTIONS
# ============================================================================

# Get network connections - works on all Windows versions
function Get-NetworkConnections {
    param(
        [switch]$Listening,
        [switch]$Established
    )
    
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        if ($Listening) {
            Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | 
                Select-Object LocalAddress, LocalPort, OwningProcess
        } elseif ($Established) {
            Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
                Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess
        }
    } else {
        # Fallback to netstat parsing
        $netstat = netstat -ano 2>$null
        $connections = @()
        foreach ($line in $netstat) {
            if ($line -match '^\s*(TCP|UDP)\s+(\S+):(\d+)\s+(\S+):(\S+)\s+(\w+)?\s*(\d+)?') {
                $proto = $Matches[1]
                $localAddr = $Matches[2]
                $localPort = $Matches[3]
                $remoteAddr = $Matches[4]
                $remotePort = $Matches[5]
                $state = $Matches[6]
                $pid = $Matches[7]
                
                $obj = [PSCustomObject]@{
                    Protocol = $proto
                    LocalAddress = $localAddr
                    LocalPort = $localPort
                    RemoteAddress = $remoteAddr
                    RemotePort = $remotePort
                    State = $state
                    OwningProcess = $pid
                }
                
                if ($Listening -and $state -eq "LISTENING") {
                    $connections += $obj
                } elseif ($Established -and $state -eq "ESTABLISHED") {
                    $connections += $obj
                } elseif (-not $Listening -and -not $Established) {
                    $connections += $obj
                }
            }
        }
        return $connections
    }
}

# Get network adapters - works on all Windows versions
function Get-NetworkAdaptersCompat {
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" }
    } else {
        Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True"
    }
}

# Get IP configuration - works on all Windows versions
function Get-IPConfigCompat {
    $adapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True"
    foreach ($adapter in $adapters) {
        [PSCustomObject]@{
            Description = $adapter.Description
            IPAddress = ($adapter.IPAddress -join ", ")
            SubnetMask = ($adapter.IPSubnet -join ", ")
            Gateway = ($adapter.DefaultIPGateway -join ", ")
            MACAddress = $adapter.MACAddress
            DNSServers = ($adapter.DNSServerSearchOrder -join ", ")
            DHCPEnabled = $adapter.DHCPEnabled
        }
    }
}

# Get local users - works on all Windows versions
function Get-LocalUsersCompat {
    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        Get-LocalUser | Select-Object Name, Enabled, Description
    } else {
        # Use net user command
        $output = net user 2>$null
        $users = @()
        $inUserList = $false
        foreach ($line in $output) {
            if ($line -match "^-+$") {
                $inUserList = $true
                continue
            }
            if ($inUserList -and $line -match "\S") {
                if ($line -notmatch "The command completed") {
                    $lineUsers = $line -split '\s{2,}' | Where-Object { $_ -match '\S' }
                    $users += $lineUsers
                }
            }
        }
        return $users
    }
}

# Get local group members - works on all Windows versions
function Get-LocalGroupMembersCompat {
    param([string]$GroupName)
    
    if (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue) {
        Get-LocalGroupMember -Group $GroupName -ErrorAction SilentlyContinue | 
            Select-Object Name, ObjectClass, PrincipalSource
    } else {
        $output = net localgroup "$GroupName" 2>$null
        $members = @()
        $inMemberList = $false
        foreach ($line in $output) {
            if ($line -match "^-+$") {
                $inMemberList = $true
                continue
            }
            if ($inMemberList -and $line -match "\S" -and $line -notmatch "The command completed") {
                $members += $line.Trim()
            }
        }
        return $members
    }
}

# Get SMB shares - works on all Windows versions  
function Get-SmbSharesCompat {
    if (Get-Command Get-SmbShare -ErrorAction SilentlyContinue) {
        Get-SmbShare -ErrorAction SilentlyContinue | Select-Object Name, Path, Description
    } else {
        $output = net share 2>$null
        return $output
    }
}

# Get firewall status - works on all Windows versions
function Get-FirewallStatusCompat {
    $output = netsh advfirewall show allprofiles 2>$null
    return $output
}

# Get routing table - works on all Windows versions
function Get-RoutingTableCompat {
    if (Get-Command Get-NetRoute -ErrorAction SilentlyContinue) {
        Get-NetRoute -ErrorAction SilentlyContinue | 
            Where-Object { $_.DestinationPrefix -ne "ff00::/8" } |
            Select-Object DestinationPrefix, NextHop, InterfaceAlias, RouteMetric |
            Format-Table -AutoSize | Out-String
    } else {
        route print 2>$null
    }
}

# Get ARP table - works on all Windows versions
function Get-ArpTableCompat {
    if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
        Get-NetNeighbor -ErrorAction SilentlyContinue | 
            Where-Object { $_.State -ne "Unreachable" } |
            Select-Object IPAddress, LinkLayerAddress, State, InterfaceAlias |
            Format-Table -AutoSize | Out-String
    } else {
        arp -a 2>$null
    }
}

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

Write-Banner "INVENTORY TIME"

if (-not $Script:IsAdmin) {
    Write-Warning-Custom "Script is not running as Administrator. Some checks may be limited."
}

# ============================================================================
# HOST INFORMATION
# ============================================================================

Write-Section "HOST INFORMATION"

# Get computer system info
$computerSystem = Get-WmiObject -Class Win32_ComputerSystem
$operatingSystem = Get-WmiObject -Class Win32_OperatingSystem
$processor = Get-WmiObject -Class Win32_Processor | Select-Object -First 1

Write-Info "Hostname" $env:COMPUTERNAME

if ($computerSystem.PartOfDomain) {
    Write-Info "Domain" $computerSystem.Domain
} else {
    Write-Info "Workgroup" $computerSystem.Workgroup
}

Write-Info "OS" $operatingSystem.Caption
Write-Info "OS Version" $operatingSystem.Version
Write-Info "Architecture" $operatingSystem.OSArchitecture

# RAM
$ramGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
Write-Info "RAM" "$ramGB GB"

# Storage
Write-Label "Storage"
$disks = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3"
foreach ($disk in $disks) {
    $sizeGB = [math]::Round($disk.Size / 1GB, 2)
    $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
    Write-Data "  $($disk.DeviceID) - Total: ${sizeGB}GB, Free: ${freeGB}GB"
}

# Network Information
Write-Label "IP Addresses and Interfaces"
$ipConfig = Get-IPConfigCompat
foreach ($adapter in $ipConfig) {
    Write-Data "  $($adapter.Description)"
    Write-Data "    IP: $($adapter.IPAddress)"
    Write-Data "    Subnet: $($adapter.SubnetMask)"
    Write-Data "    Gateway: $($adapter.Gateway)"
    Write-Data "    MAC: $($adapter.MACAddress)"
    Write-Data "    DNS: $($adapter.DNSServers)"
}

# ============================================================================
# LISTENING PORTS
# ============================================================================

Write-Section "LISTENING PORTS"

$listeningPorts = Get-NetworkConnections -Listening
if ($listeningPorts) {
    $processes = @{}
    Get-WmiObject -Class Win32_Process | ForEach-Object { $processes[$_.ProcessId] = $_.Name }
    
    Write-Host ("{0,-8} {1,-25} {2,-8} {3}" -f "Proto", "Local Address", "Port", "Process") -ForegroundColor $Script:Colors.Blue
    Write-Host ("-" * 60) -ForegroundColor $Script:Colors.Blue
    
    foreach ($conn in $listeningPorts) {
        $procName = $processes[[int]$conn.OwningProcess]
        if (-not $procName) { $procName = "Unknown" }
        $proto = if ($conn.Protocol) { $conn.Protocol } else { "TCP" }
        Write-Data ("{0,-8} {1,-25} {2,-8} {3} ({4})" -f $proto, $conn.LocalAddress, $conn.LocalPort, $procName, $conn.OwningProcess)
    }
} else {
    # Fallback to raw netstat
    Write-Label "Listening Ports (netstat)"
    $netstat = netstat -ano 2>$null | Select-String "LISTENING"
    Write-Data ($netstat | Out-String)
}

# ============================================================================
# SERVICE INFORMATION
# ============================================================================

Write-Section "SERVICE INFORMATION"

# Get all running services
$runningServices = Get-Service | Where-Object { $_.Status -eq "Running" }

# IIS Check
$iisService = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
if ($iisService -and $iisService.Status -eq "Running") {
    Write-ServiceFound "IIS (W3SVC)"
    
    # Try to get IIS sites
    $appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        Write-Label "IIS Sites"
        $sites = & $appcmd list site 2>$null
        Write-Data ($sites | Out-String)
        
        Write-Label "IIS Application Pools"
        $pools = & $appcmd list apppool 2>$null
        Write-Data ($pools | Out-String)
    }
}

# SQL Server Check
$sqlServices = Get-Service -Name "MSSQL*" -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Running" }
if ($sqlServices) {
    foreach ($sql in $sqlServices) {
        Write-ServiceFound "SQL Server ($($sql.Name))"
    }
    
    # Check for SQL instances in registry
    $sqlInstances = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server" -ErrorAction SilentlyContinue
    if ($sqlInstances.InstalledInstances) {
        Write-Label "SQL Server Instances"
        Write-Data ($sqlInstances.InstalledInstances -join ", ")
    }
}

# RDP Check
$rdpEnabled = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections
if ($rdpEnabled -eq 0) {
    Write-ServiceFound "RDP (Remote Desktop)"
    
    $rdpPort = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "PortNumber" -ErrorAction SilentlyContinue).PortNumber
    if ($rdpPort) {
        Write-Info "RDP Port" $rdpPort
    }
    
    # Check NLA requirement
    $nla = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -ErrorAction SilentlyContinue).UserAuthentication
    if ($nla -eq 1) {
        Write-Data "  Network Level Authentication: Enabled"
    } else {
        Write-Warning-Custom "Network Level Authentication: DISABLED"
    }
}

# WinRM Check
$winrmService = Get-Service -Name "WinRM" -ErrorAction SilentlyContinue
if ($winrmService -and $winrmService.Status -eq "Running") {
    Write-ServiceFound "WinRM (Windows Remote Management)"
    
    $winrmConfig = winrm get winrm/config/service 2>$null
    if ($winrmConfig) {
        $allowUnencrypted = $winrmConfig | Select-String "AllowUnencrypted"
        $basicAuth = $winrmConfig | Select-String "Basic"
        Write-Data ($allowUnencrypted | Out-String).Trim()
        Write-Data ($basicAuth | Out-String).Trim()
    }
}

# SMB Shares
Write-Label "SMB Shares"
$shares = Get-SmbSharesCompat
if ($shares -is [string]) {
    Write-Data $shares
} else {
    foreach ($share in $shares) {
        Write-Data "  $($share.Name) -> $($share.Path)"
    }
}

# DNS Server Check
$dnsService = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
if ($dnsService -and $dnsService.Status -eq "Running") {
    Write-ServiceFound "DNS Server"
}

# DHCP Server Check
$dhcpService = Get-Service -Name "DHCPServer" -ErrorAction SilentlyContinue
if ($dhcpService -and $dhcpService.Status -eq "Running") {
    Write-ServiceFound "DHCP Server"
}

# Docker Check
$dockerService = Get-Service -Name "docker" -ErrorAction SilentlyContinue
if ($dockerService -and $dockerService.Status -eq "Running") {
    Write-ServiceFound "Docker"
    
    $containers = docker ps 2>$null
    if ($containers) {
        Write-Label "Running Containers"
        Write-Data ($containers | Out-String)
    }
}

# SSH Server Check (Windows 10+/Server 2019+)
$sshService = Get-Service -Name "sshd" -ErrorAction SilentlyContinue
if ($sshService -and $sshService.Status -eq "Running") {
    Write-ServiceFound "OpenSSH Server"
}

# ============================================================================
# USER INFORMATION
# ============================================================================

Write-Section "USER INFORMATION"

# Local Users
Write-Label "Local Users"
$localUsers = Get-LocalUsersCompat
if ($localUsers -is [array] -and $localUsers[0] -is [string]) {
    Write-Data ($localUsers -join ", ")
} else {
    foreach ($user in $localUsers) {
        $status = if ($user.Enabled) { "Enabled" } else { "Disabled" }
        Write-Data "  $($user.Name) - $status"
    }
}

# Administrators Group
Write-Label "Local Administrators"
$admins = Get-LocalGroupMembersCompat -GroupName "Administrators"
if ($admins -is [array] -and $admins[0] -is [string]) {
    foreach ($admin in $admins) {
        Write-Data "  $admin"
    }
} else {
    foreach ($admin in $admins) {
        Write-Data "  $($admin.Name)"
    }
}

# Remote Desktop Users
Write-Label "Remote Desktop Users"
$rdpUsers = Get-LocalGroupMembersCompat -GroupName "Remote Desktop Users"
if ($rdpUsers) {
    if ($rdpUsers -is [array] -and $rdpUsers[0] -is [string]) {
        foreach ($user in $rdpUsers) {
            Write-Data "  $user"
        }
    } else {
        foreach ($user in $rdpUsers) {
            Write-Data "  $($user.Name)"
        }
    }
} else {
    Write-Data "  (none)"
}

# Currently Logged In Users
Write-Label "Currently Logged In Users"
$loggedOn = query user 2>$null
if ($loggedOn) {
    Write-Data ($loggedOn | Out-String)
} else {
    # Fallback to WMI
    $sessions = Get-WmiObject -Class Win32_LoggedOnUser -ErrorAction SilentlyContinue | 
        Select-Object -ExpandProperty Antecedent -Unique |
        ForEach-Object { 
            if ($_ -match 'Name="([^"]+)"') { $Matches[1] }
        } | Select-Object -Unique
    Write-Data ($sessions -join ", ")
}

# Password Policy
Write-Label "Password Policy"
$netAccounts = net accounts 2>$null
Write-Data ($netAccounts | Out-String)

# ============================================================================
# PROCESS INFORMATION
# ============================================================================

Write-Section "PROCESS INFORMATION"

Write-Label "Running Processes with Owners"

$processes = Get-WmiObject -Class Win32_Process
$processInfo = @()

foreach ($proc in $processes) {
    $owner = Invoke-SafeCommand { $proc.GetOwner() }
    $ownerName = if ($owner -and $owner.User) { 
        if ($owner.Domain) { "$($owner.Domain)\$($owner.User)" } else { $owner.User }
    } else { 
        "N/A" 
    }
    
    $processInfo += [PSCustomObject]@{
        PID = $proc.ProcessId
        Name = $proc.Name
        Owner = $ownerName
        Path = $proc.ExecutablePath
    }
}

# Display process table
Write-Host ("{0,-8} {1,-30} {2,-25}" -f "PID", "Name", "Owner") -ForegroundColor $Script:Colors.Blue
Write-Host ("-" * 70) -ForegroundColor $Script:Colors.Blue

foreach ($p in $processInfo | Sort-Object Name) {
    Write-Data ("{0,-8} {1,-30} {2,-25}" -f $p.PID, $p.Name, $p.Owner)
}

# Processes from non-standard paths
Write-Host ""
Write-Label "Processes from Non-Standard Paths"
$suspiciousProcs = $processInfo | Where-Object { 
    $_.Path -and 
    $_.Path -notmatch "^C:\\Windows" -and 
    $_.Path -notmatch "^C:\\Program Files" 
}

if ($suspiciousProcs) {
    foreach ($p in $suspiciousProcs) {
        Write-Data "  $($p.Name) (PID: $($p.PID)) - $($p.Path)"
    }
} else {
    Write-Data "  (none found)"
}

# ============================================================================
# ACTIVE DIRECTORY ENUMERATION
# ============================================================================

Write-Section "ACTIVE DIRECTORY"

$computerSystem = Get-WmiObject -Class Win32_ComputerSystem
if ($computerSystem.PartOfDomain) {
    Write-Info "Domain" $computerSystem.Domain
    
    # Domain Controllers
    Write-Label "Domain Controllers"
    $dcList = nltest /dclist:$($computerSystem.Domain) 2>$null
    if ($dcList) {
        Write-Data ($dcList | Out-String)
    }
    
    # Domain Admins
    Write-Label "Domain Admins"
    $domainAdmins = net group "Domain Admins" /domain 2>$null
    if ($domainAdmins) {
        Write-Data ($domainAdmins | Out-String)
    }
    
    # Domain Trusts
    Write-Label "Domain Trusts"
    $trusts = nltest /domain_trusts 2>$null
    if ($trusts) {
        Write-Data ($trusts | Out-String)
    }
    
    # Kerberos Tickets
    Write-Label "Kerberos Tickets"
    $tickets = klist 2>$null
    if ($tickets) {
        Write-Data ($tickets | Out-String)
    }
} else {
    Write-Data "This machine is not domain-joined (Workgroup: $($computerSystem.Workgroup))"
}

# ============================================================================
# EXTRA NETWORK INFORMATION
# ============================================================================

Write-Section "EXTRA NETWORK INFORMATION"

Write-Label "Routing Table"
$routes = Get-RoutingTableCompat
Write-Data $routes

Write-Label "ARP Table"
$arp = Get-ArpTableCompat
Write-Data $arp

Write-Label "Firewall Status"
$firewall = Get-FirewallStatusCompat
Write-Data ($firewall | Out-String)

# ============================================================================
# ESTABLISHED CONNECTIONS
# ============================================================================

Write-Section "ESTABLISHED CONNECTIONS"

$established = Get-NetworkConnections -Established
if ($established) {
    $processes = @{}
    Get-WmiObject -Class Win32_Process | ForEach-Object { $processes[$_.ProcessId] = $_.Name }
    
    Write-Host ("{0,-20} {1,-8} {2,-20} {3,-8} {4}" -f "Local", "LPort", "Remote", "RPort", "Process") -ForegroundColor $Script:Colors.Blue
    Write-Host ("-" * 75) -ForegroundColor $Script:Colors.Blue
    
    foreach ($conn in $established) {
        $procName = $processes[[int]$conn.OwningProcess]
        if (-not $procName) { $procName = "Unknown" }
        Write-Data ("{0,-20} {1,-8} {2,-20} {3,-8} {4}" -f $conn.LocalAddress, $conn.LocalPort, $conn.RemoteAddress, $conn.RemotePort, $procName)
    }
} else {
    # Fallback to raw netstat
    Write-Label "Established Connections (netstat)"
    $netstat = netstat -ano 2>$null | Select-String "ESTABLISHED"
    Write-Data ($netstat | Out-String)
}

# ============================================================================
# END OF OUTPUT
# ============================================================================

Write-Host ""
Write-Host "##########################End of Output#########################" -ForegroundColor $Script:Colors.Green
Write-Host ""

