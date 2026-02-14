#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Checks for suspicious password filters in the Windows Notification Packages registry key.

.DESCRIPTION
    This script examines the LSA Notification Packages registry key to detect
    unauthorized password filters - a common credential theft technique.
    Excludes legitimate Microsoft components (scecli and rassfm).
    
.NOTES
    Requires Administrator privileges to read registry keys.
    Password filters can intercept password changes and steal credentials.
#>

function Check-PasswordFilters {
    [CmdletBinding()]
    param()
    
    Write-Host "`n=== Checking for Suspicious Password Filters ===" -ForegroundColor Cyan
    Write-Host "This checks for unauthorized password filter DLLs in Notification Packages`n" -ForegroundColor Gray
    
    # Registry path for LSA Notification Packages
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    $valueName = "Notification Packages"
    
    # Legitimate Microsoft notification packages (whitelist)
    $legitimatePackages = @(
        'scecli',
        'rassfm'
    )
    
    $findings = @()
    $issuesFound = $false
    
    Write-Host "Registry Path: $registryPath" -ForegroundColor Gray
    Write-Host "Value Name: $valueName`n" -ForegroundColor Gray
    
    try {
        # Check if the registry path exists
        if (-not (Test-Path $registryPath)) {
            Write-Host "ERROR: Registry path not found!" -ForegroundColor Red
            Write-Host "Path: $registryPath" -ForegroundColor Red
            return $null
        }
        
        # Get the Notification Packages value
        $notificationPackages = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction Stop
        
        if (-not $notificationPackages.$valueName) {
            Write-Host "WARNING: Notification Packages value is empty or missing." -ForegroundColor Yellow
            return @()
        }
        
        # Get the array of packages
        $packages = $notificationPackages.$valueName
        
        # Ensure it's an array
        if ($packages -isnot [array]) {
            $packages = @($packages)
        }
        
        Write-Host "Found $($packages.Count) notification package(s):`n" -ForegroundColor Yellow
        
        # Check each package
        foreach ($package in $packages) {
            # Skip empty entries
            if ([string]::IsNullOrWhiteSpace($package)) {
                continue
            }
            
            $isLegitimate = $legitimatePackages -contains $package.Trim()
            
            if ($isLegitimate) {
                Write-Host "  [OK] " -NoNewline -ForegroundColor Green
                Write-Host "$package" -ForegroundColor Green -NoNewline
                Write-Host " - Legitimate Microsoft component" -ForegroundColor Gray
            } else {
                $issuesFound = $true
                Write-Host "  [!] " -NoNewline -ForegroundColor Red
                Write-Host "$package" -ForegroundColor Red -NoNewline
                Write-Host " - SUSPICIOUS!" -ForegroundColor Red
                
                # Try to locate the DLL
                $possiblePaths = @(
                    "$env:SystemRoot\System32\$package.dll",
                    "$env:SystemRoot\SysWOW64\$package.dll"
                )
                
                $dllFound = $false
                $dllPath = $null
                
                foreach ($path in $possiblePaths) {
                    if (Test-Path $path) {
                        $dllFound = $true
                        $dllPath = $path
                        
                        # Get file information
                        $fileInfo = Get-Item $path
                        $fileVersion = $fileInfo.VersionInfo
                        
                        Write-Host "      Location: $path" -ForegroundColor Yellow
                        Write-Host "      Created: $($fileInfo.CreationTime)" -ForegroundColor Yellow
                        Write-Host "      Modified: $($fileInfo.LastWriteTime)" -ForegroundColor Yellow
                        Write-Host "      Size: $($fileInfo.Length) bytes" -ForegroundColor Yellow
                        
                        if ($fileVersion.FileDescription) {
                            Write-Host "      Description: $($fileVersion.FileDescription)" -ForegroundColor Yellow
                        }
                        if ($fileVersion.CompanyName) {
                            Write-Host "      Company: $($fileVersion.CompanyName)" -ForegroundColor Yellow
                        }
                        
                        break
                    }
                }
                
                if (-not $dllFound) {
                    Write-Host "      Location: DLL not found in System32 or SysWOW64" -ForegroundColor Red
                }
                
                $finding = [PSCustomObject]@{
                    PackageName = $package
                    Status = "SUSPICIOUS"
                    DLLFound = $dllFound
                    DLLPath = $dllPath
                }
                
                $findings += $finding
            }
        }
        
        # Summary
        Write-Host "`n=== Summary ===" -ForegroundColor Cyan
        
        if ($issuesFound) {
            Write-Host "WARNING: " -NoNewline -ForegroundColor Red
            Write-Host "Found $($findings.Count) suspicious password filter(s)!" -ForegroundColor Red        
        } else {
            Write-Host "All notification packages are legitimate Microsoft components." -ForegroundColor Green
            Write-Host "No suspicious password filters detected." -ForegroundColor Green
        }
        
        # Return findings for further processing if needed
        return $findings
        
    } catch {
        Write-Host "`nERROR: Failed to read registry value" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Execute the check
try {
    $results = Check-PasswordFilters
    
    # Exit code: 0 = clean, 1 = issues found, 2 = error
    if ($null -eq $results) {
        exit 2
    } elseif ($results.Count -gt 0) {
        exit 1
    } else {
        exit 0
    }
} catch {
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure you're running this script as Administrator." -ForegroundColor Yellow
    exit 2
}
