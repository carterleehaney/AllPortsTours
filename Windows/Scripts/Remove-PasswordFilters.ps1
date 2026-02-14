#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Removes suspicious password filters from the Windows Notification Packages registry key.

.DESCRIPTION
    This script removes unauthorized password filter DLLs from the LSA Notification Packages,
    effectively removing credential theft mechanisms.
    By default, runs in automatic mode without prompts (automation-friendly).
    Preserves legitimate Microsoft components (scecli and rassfm).
    
.PARAMETER Interactive
    Enable interactive mode with confirmation prompts for each removal.

.NOTES
    Requires Administrator privileges to modify registry keys.
    Default behavior: Automatically removes all suspicious packages without prompting.
    System restart is recommended after removal.
    
.EXAMPLE
    .\Remove-PasswordFilters.ps1
    Automatically removes all suspicious password filters without prompting (default).
    
.EXAMPLE
    .\Remove-PasswordFilters.ps1 -Interactive
    Prompts for confirmation before removing each suspicious package.
    
.EXAMPLE
    .\Remove-PasswordFilters.ps1 -WhatIf
    Shows what would be removed without making changes.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [switch]$Interactive
)

function Remove-PasswordFilters {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Interactive
    )
    
    Write-Host "`n=== Removing Suspicious Password Filters ===" -ForegroundColor Cyan
    Write-Host "This will remove unauthorized password filter DLLs from Notification Packages`n" -ForegroundColor Gray
    
    # Registry path for LSA Notification Packages
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    $valueName = "Notification Packages"
    
    # Legitimate Microsoft notification packages (whitelist)
    $legitimatePackages = @(
        'scecli',
        'rassfm'
    )
    
    $removedCount = 0
    $skippedCount = 0
    $removedItems = @()
    
    Write-Host "Registry Path: $registryPath" -ForegroundColor Gray
    Write-Host "Value Name: $valueName`n" -ForegroundColor Gray
    
    try {
        # Check if the registry path exists
        if (-not (Test-Path $registryPath)) {
            Write-Host "ERROR: Registry path not found!" -ForegroundColor Red
            Write-Host "Path: $registryPath" -ForegroundColor Red
            return @{
                RemovedCount = 0
                SkippedCount = 0
                RemovedItems = @()
            }
        }
        
        # Get the current value using .NET registry methods for proper MULTI_SZ handling
        $regKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control\Lsa", $true)
        
        if (-not $regKey) {
            Write-Host "ERROR: Cannot open registry key for writing!" -ForegroundColor Red
            return @{
                RemovedCount = 0
                SkippedCount = 0
                RemovedItems = @()
            }
        }
        
        $packages = $regKey.GetValue($valueName)
        
        if (-not $packages -or $packages.Count -eq 0) {
            Write-Host "No notification packages found." -ForegroundColor Green
            Write-Host "System is clean!" -ForegroundColor Green
            $regKey.Close()
            return @{
                RemovedCount = 0
                SkippedCount = 0
                RemovedItems = @()
            }
        }
        
        # Ensure it's an array
        if ($packages -isnot [array]) {
            $packages = @($packages)
        }
        
        # Find suspicious packages
        $suspiciousPackages = @()
        $legitimateFound = @()
        
        foreach ($package in $packages) {
            # Skip empty entries
            if ([string]::IsNullOrWhiteSpace($package)) {
                continue
            }
            
            $trimmedPackage = $package.Trim()
            $isLegitimate = $legitimatePackages -contains $trimmedPackage
            
            if ($isLegitimate) {
                $legitimateFound += $trimmedPackage
            } else {
                # Try to locate the DLL
                $possiblePaths = @(
                    "$env:SystemRoot\System32\$trimmedPackage.dll",
                    "$env:SystemRoot\SysWOW64\$trimmedPackage.dll"
                )
                
                $dllPath = $null
                foreach ($path in $possiblePaths) {
                    if (Test-Path $path) {
                        $dllPath = $path
                        break
                    }
                }
                
                $suspiciousPackages += [PSCustomObject]@{
                    PackageName = $trimmedPackage
                    DLLPath = $dllPath
                }
            }
        }
        
        # Display findings
        Write-Host "Scan Results:" -ForegroundColor Yellow
        Write-Host "  Legitimate packages: $($legitimateFound.Count)" -ForegroundColor Green
        if ($legitimateFound.Count -gt 0) {
            foreach ($pkg in $legitimateFound) {
                Write-Host "    - $pkg" -ForegroundColor Green
            }
        }
        
        Write-Host "  Suspicious packages: $($suspiciousPackages.Count)" -ForegroundColor $(if ($suspiciousPackages.Count -gt 0) { "Red" } else { "Green" })
        if ($suspiciousPackages.Count -gt 0) {
            foreach ($pkg in $suspiciousPackages) {
                Write-Host "    - $($pkg.PackageName)" -ForegroundColor Red
                if ($pkg.DLLPath) {
                    Write-Host "      DLL: $($pkg.DLLPath)" -ForegroundColor Yellow
                }
            }
        }
        
        if ($suspiciousPackages.Count -eq 0) {
            Write-Host "`nNo suspicious password filters found." -ForegroundColor Green
            Write-Host "System is clean!" -ForegroundColor Green
            $regKey.Close()
            return @{
                RemovedCount = 0
                SkippedCount = 0
                RemovedItems = @()
            }
        }
        
        # Process removals
        Write-Host "`nProcessing removals..." -ForegroundColor Cyan
        
        # Build the new package list
        $packagesToKeep = @($legitimateFound)
        
        foreach ($item in $suspiciousPackages) {
            Write-Host "`n[$($item.PackageName)]" -ForegroundColor Yellow
            if ($item.DLLPath) {
                Write-Host "  DLL Location: $($item.DLLPath)" -ForegroundColor Red
            } else {
                Write-Host "  DLL Location: Not found in System32 or SysWOW64" -ForegroundColor Yellow
            }
            
            $shouldRemove = $false
            
            if ($WhatIfPreference) {
                Write-Host "  Action: WOULD REMOVE (WhatIf mode)" -ForegroundColor Cyan
                $skippedCount++
                continue
            }
            
            if ($Interactive) {
                # Ask for confirmation only in interactive mode
                $response = Read-Host "  Remove this password filter? (Y/N)"
                if ($response -eq 'Y' -or $response -eq 'y') {
                    $shouldRemove = $true
                }
            } else {
                # Default: automatically remove without prompting
                $shouldRemove = $true
            }
            
            if ($shouldRemove) {
                Write-Host "  Status: " -NoNewline
                Write-Host "REMOVING..." -ForegroundColor Yellow
                $removedCount++
                $removedItems += $item
                
                # Don't add to packagesToKeep (effectively removing it)
                
                # Move the DLL file to quarantine
                if ($item.DLLPath -and (Test-Path $item.DLLPath)) {
                    try {
                        $quarantineDir = "C:\stuff\bad"
                        
                        # Create quarantine directory if it doesn't exist
                        if (-not (Test-Path $quarantineDir)) {
                            New-Item -Path $quarantineDir -ItemType Directory -Force | Out-Null
                            Write-Host "  Created quarantine directory: $quarantineDir" -ForegroundColor Gray
                        }
                        
                        # Use original filename
                        $fileName = Split-Path $item.DLLPath -Leaf
                        $quarantinePath = Join-Path $quarantineDir $fileName
                        
                        # Move the file
                        Move-Item -Path $item.DLLPath -Destination $quarantinePath -Force -ErrorAction Stop
                        Write-Host "  Quarantine: Moved to $quarantinePath" -ForegroundColor Green
                    } catch {
                        Write-Host "  Quarantine: Failed to move DLL - $($_.Exception.Message)" -ForegroundColor Yellow
                        Write-Host "              Source: $($item.DLLPath)" -ForegroundColor Yellow
                        Write-Host "              Manual action recommended" -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "  Status: " -NoNewline
                Write-Host "SKIPPED (user declined)" -ForegroundColor Yellow
                $skippedCount++
                # Add back to the list to keep
                $packagesToKeep += $item.PackageName
            }
        }
        
        # Update the registry with the new list
        if ($removedCount -gt 0 -and -not $WhatIfPreference) {
            try {
                # Remove empty entries
                $packagesToKeep = @($packagesToKeep | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                
                if ($packagesToKeep.Count -eq 0) {
                    # If nothing left, set to empty array
                    $packagesToKeep = @('')
                }
                
                # Write the new value using .NET methods for proper MULTI_SZ handling
                $regKey.SetValue($valueName, [string[]]$packagesToKeep, [Microsoft.Win32.RegistryValueKind]::MultiString)
                Write-Host "`n  Registry updated successfully!" -ForegroundColor Green
                
            } catch {
                Write-Host "`n  ERROR: Failed to update registry - $($_.Exception.Message)" -ForegroundColor Red
                $regKey.Close()
                return @{
                    RemovedCount = 0
                    SkippedCount = $skippedCount + $removedCount
                    RemovedItems = @()
                }
            }
        }
        
        $regKey.Close()
        
        # Summary
        Write-Host "`n=== Removal Summary ===" -ForegroundColor Cyan
        
        if ($WhatIfPreference) {
            Write-Host "WhatIf Mode: No changes were made" -ForegroundColor Cyan
            Write-Host "Would have processed: $($suspiciousPackages.Count) package(s)" -ForegroundColor Yellow
        } else {
            Write-Host "Removed: " -NoNewline
            Write-Host "$removedCount" -ForegroundColor Green -NoNewline
            Write-Host " password filter(s)"
            
            if ($skippedCount -gt 0) {
                Write-Host "Skipped: " -NoNewline
                Write-Host "$skippedCount" -ForegroundColor Yellow -NoNewline
                Write-Host " password filter(s)"
            }
            
            if ($removedCount -gt 0) {
                Write-Host "`nRemoved packages:" -ForegroundColor Green
                $removedItems | Format-Table PackageName, DLLPath -AutoSize
                
                Write-Host "IMPORTANT: " -NoNewline -ForegroundColor Yellow
                Write-Host "A system restart is REQUIRED for changes to take effect!" -ForegroundColor Yellow
                Write-Host "Password filters are loaded at system boot.`n" -ForegroundColor Gray
                
                Write-Host "Remaining legitimate packages:" -ForegroundColor Green
                if ($packagesToKeep.Count -gt 0) {
                    foreach ($pkg in $packagesToKeep) {
                        if (-not [string]::IsNullOrWhiteSpace($pkg)) {
                            Write-Host "  - $pkg" -ForegroundColor Green
                        }
                    }
                } else {
                    Write-Host "  (none)" -ForegroundColor Gray
                }
            }
        }
        
        return @{
            RemovedCount = $removedCount
            SkippedCount = $skippedCount
            RemovedItems = $removedItems
        }
        
    } catch {
        Write-Host "`nERROR: Failed to process registry" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            RemovedCount = 0
            SkippedCount = 0
            RemovedItems = @()
        }
    }
}

# Main execution
try {
    if ($PSBoundParameters.ContainsKey('WhatIf') -and $WhatIf) {
        Write-Host "`n*** RUNNING IN WHATIF MODE - NO CHANGES WILL BE MADE ***`n" -ForegroundColor Cyan
    }
    
    if (-not $Interactive) {
        Write-Host "`n*** AUTOMATIC MODE - ALL SUSPICIOUS PACKAGES WILL BE REMOVED ***`n" -ForegroundColor Yellow
        Write-Host "Use -Interactive flag if you want to confirm each removal`n" -ForegroundColor Gray
    }
    
    $results = Remove-PasswordFilters -Interactive:$Interactive
    
    # Exit codes
    if ($WhatIfPreference) {
        exit 0  # WhatIf always returns 0
    } elseif ($results.RemovedCount -gt 0) {
        exit 0  # Success
    } elseif ($results.SkippedCount -gt 0) {
        exit 2  # Some items skipped
    } else {
        exit 0  # Nothing found (clean system)
    }
    
} catch {
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure you're running this script as Administrator." -ForegroundColor Yellow
    exit 1
}
