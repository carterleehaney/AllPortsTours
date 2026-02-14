param(
    [string[]]$e,
    [string[]]$u,
    [switch]$h,
    [string]$s,
    [switch]$a
)

if ($h) {
    Write-Host "Author: @carterleehaney https://www.linkedin.com/in/carterhaney/" -ForegroundColor Yellow
    Write-Host "Usage: .\Passwords.ps1 [-e user1,user2,...] [-u user1,user2,...] [-h] [-s]"
    Write-Host ""
    Write-Host "This script changes passwords for all users on the system (domain and/or local)."
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -e    Comma-separated list of usernames (samAccountName) to exclude from password changes"
    Write-Host "  -u    Comma-separated list of usernames (samAccountName) to include (only change these users)"
    Write-Host "  -h    Show this help message"
    Write-Host "  -s    Set this password for all users (overrides random password generation)"
    Write-Host "  -a    Set all users to the same password (uses the admin password for all users)"
    Write-Host ""
    Write-Host "Note: -e and -u cannot be used together."
    Write-Host ""
    exit
}

# Validate that conflicting parameters are not used together
if ($e -and $u) {
    Write-Host "[X] Parameters -e (exclude) and -u (include) cannot be used together." -ForegroundColor Red
    Write-Host "[X] Use -e to exclude specific users, or -u to only include specific users, but not both." -ForegroundColor Yellow
    exit
}

$ErrorActionPreference = "SilentlyContinue"
$DomainController = $False

Write-Host "Author: @carterleehaney https://www.linkedin.com/in/carterhaney/" -ForegroundColor Yellow

# If -s is provided, skip the interactive prompt (non-interactive mode)
if ($s) {
    $AdminPassword = $s
}
else {
    Write-Host "Enter password for Administrator/Domain Admin accounts: " -NoNewline
    $AdminPassword = Read-Host
}

# Array of usernames to exclude from password changes.
$Exclude = @()

if ($e) {
    $Exclude += $e
}

# Array of usernames to include (only change these users if specified).
$Include = @()

if ($u) {
    $Include += $u
}

$CSVArray = @()

# Function to generate a random password.
Add-Type -AssemblyName System.Web
function Get-Password {
    do {
        $p = [System.Web.Security.Membership]::GeneratePassword(14, 4)
    } while ($p -match '[,;:|iIlLoO0]')
    return $p + "1!"
}

if (Get-WmiObject -Query "select * from Win32_OperatingSystem where ProductType='2'") {
    $DomainController = $True
    Write-Host "`n$env:ComputerName - Domain Controller" -ForegroundColor Yellow

    if ((Get-WmiObject Win32_ComputerSystem).DomainRole -eq 4) {
        Write-Host "[INFO] Secondary Domain Controller Detected." -ForegroundColor Yellow 
        exit
    }
}
else {
    Write-Host "`n$env:ComputerName" -ForegroundColor Yellow
}

if ($DomainController) {
    Import-Module ActiveDirectory
    
    # Process Domain Users
    Write-Host "[*] Processing Domain Users..." -ForegroundColor Cyan
    $Users = Get-ADUser -Filter * | Select-Object -ExpandProperty sAMAccountName
    foreach ($User in $Users) {
        if ($Include.Count -gt 0 -and $Include -notcontains $User) {
            continue
        }
        if ($Exclude -contains $User) {
            Write-Host "[!] Skipped changing $User's password." -ForegroundColor Gray
            continue
        }
        if (($User -match "seccdc") -or ($User -match "blackteam")) {
            Write-Host "[!] Skipped changing $User's password." -ForegroundColor Gray
            continue
        }
        
        $IsDomainAdmin = $false
        try {
            $UserGroups = Get-ADPrincipalGroupMembership -Identity $User | Select-Object -ExpandProperty Name
            if ($UserGroups -contains "Domain Admins") {
                $IsDomainAdmin = $true
            }
        }
        catch {}
        
        if ($IsDomainAdmin -or $a) {
            Set-AdAccountPassword -Identity "$User" -NewPassword (ConvertTo-SecureString -AsPlainText $AdminPassword -Force) -Reset -ErrorAction Stop
            Write-Host "[*] Successfully changed $User's password." -ForegroundColor Green
            $CSVArray += "$User,$AdminPassword"
        }
        elseif ($s) {
            Set-AdAccountPassword -Identity "$User" -NewPassword (ConvertTo-SecureString -AsPlainText $s -Force) -Reset -ErrorAction Stop
            Write-Host "[*] Successfully changed $User's password." -ForegroundColor Green
            $CSVArray += "$User,$s"
        }
        else {
            $RandomPassword = Get-Password
            try {
                Set-AdAccountPassword -Identity "$User" -NewPassword (ConvertTo-SecureString -AsPlainText $RandomPassword -Force) -Reset -ErrorAction Stop
                Write-Host "[*] Successfully changed $User's password." -ForegroundColor Green
                $CSVArray += "$User,$RandomPassword"
            }
            catch {
                Write-Host "[X] Failed to change $User's password." -ForegroundColor Red
            }
        }
    }
}
else {
    try {
        $Users = Get-LocalUser | Select-Object -ExpandProperty Name
        foreach ($User in $Users) {
            if ($Include.Count -gt 0 -and $Include -notcontains $User) {
                continue
            }
            if ($Exclude -contains $User) {
                Write-Host "[!] Skipped changing $User's password." -ForegroundColor Gray
                continue
            }
            if (($User -match "seccdc") -or ($User -match "blackteam")) {
                Write-Host "[!] Skipped changing $User's password." -ForegroundColor Gray
                continue
            }
            
            $IsAdmin = $false
            try {
                $AdminGroup = Get-LocalGroup -Name "Administrators"
                $AdminMembers = Get-LocalGroupMember -Group $AdminGroup | Select-Object -ExpandProperty Name
                if ($AdminMembers -contains "$env:COMPUTERNAME\$User" -or $AdminMembers -contains $User) {
                    $IsAdmin = $true
                }
            }
            catch {}
            
            if ($IsAdmin -or $a) {
                Set-LocalUser -Name "$User" -Password (ConvertTo-SecureString -AsPlainText $AdminPassword -Force) -AccountNeverExpires -ErrorAction Stop
                Write-Host "[*] Successfully changed $User's password." -ForegroundColor Green
                $CSVArray += "$User,$AdminPassword"
            }
            elseif ($s) {
                Set-LocalUser -Name "$User" -Password (ConvertTo-SecureString -AsPlainText $s -Force) -AccountNeverExpires -ErrorAction Stop
                Write-Host "[*] Successfully changed $User's password." -ForegroundColor Green
                $CSVArray += "$User,$s"
            }
            else {
                $RandomPassword = Get-Password
                try {
                    Set-LocalUser -Name "$User" -Password (ConvertTo-SecureString -AsPlainText $RandomPassword -Force) -AccountNeverExpires -ErrorAction Stop
                    Write-Host "[*] Successfully changed $User's password." -ForegroundColor Green
                    $CSVArray += "$User,$RandomPassword"
                } 
                catch {
                    Write-Host "[X] Failed to change $User's password." -ForegroundColor Red
                }
            }
        }
    }
    catch {
        $Users = Get-WmiObject -Class Win32_UserAccount | Select-Object -ExpandProperty Name
        foreach ($User in $Users) {
            if ($Include.Count -gt 0 -and $Include -notcontains $User) {
                continue
            }
            if ($Exclude -contains $User) {
                Write-Host "[!] Skipped changing $User's password." -ForegroundColor Gray
                continue
            }
            if (($User -match "seccdc") -or ($User -match "blackteam")) {
                Write-Host "[!] Skipped changing $User's password." -ForegroundColor Gray
                continue
            }
            
            if ($User -eq "Administrator" -or $a) {
                net user $User $AdminPassword
                Write-Host "[*] Successfully changed $User's password." -ForegroundColor Green
                $CSVArray += "$User,$AdminPassword"
            }
            elseif ($s) {
                net user $User $s
                Write-Host "[*] Successfully changed $User's password." -ForegroundColor Green
                $CSVArray += "$User,$s"
            }
            else {
                $RandomPassword = Get-Password
                try {
                    net user $User $RandomPassword
                    Write-Host "[*] Successfully changed $User's password." -ForegroundColor Green
                    $CSVArray += "$User,$RandomPassword"
                }
                catch {
                    Write-Host "[X] Failed to change $User's password." -ForegroundColor Red
                }
            }
        }
    }
    

}

# Output the password changes to the console.
Write-Host "`nPassword Changes" -ForegroundColor Cyan
foreach ($Entry in ($CSVArray | Sort-Object)) {
    Write-Output "$Entry"
}