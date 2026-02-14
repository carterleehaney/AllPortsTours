#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Removes debugger attachments from Windows accessibility features (Sticky Keys suite).

.DESCRIPTION
    This script removes debugger registry entries attached to accessibility executables,
    effectively removing common persistence/backdoor mechanisms.
    By default, runs in automatic mode without prompts (automation-friendly).
    
.PARAMETER Interactive
    Enable interactive mode with confirmation prompts for each removal.

.NOTES
    Requires Administrator privileges to modify registry keys.
    Default behavior: Automatically removes all debuggers without prompting.
    
.EXAMPLE
    .\Remove-AccessibilityDebuggers.ps1
    Automatically removes all debuggers without prompting (default).
    
.EXAMPLE
    .\Remove-AccessibilityDebuggers.ps1 -Interactive
    Prompts for confirmation before removing each debugger.
    
.EXAMPLE
    .\Remove-AccessibilityDebuggers.ps1 -WhatIf
    Shows what would be removed without making changes.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory=$false)]
    [switch]$Interactive
)

function Remove-AccessibilityDebuggers {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Interactive
    )
    
    Write-Host "`n=== Removing Accessibility Feature Debugger Attachments ===" -ForegroundColor Cyan
    Write-Host "This will remove unauthorized debuggers from accessibility executables`n" -ForegroundColor Gray
    
    # Define the accessibility executables to check
    $accessibilityExes = @(
        'sethc.exe',
        'utilman.exe',
        'osk.exe',
        'Magnify.exe',
        'Narrator.exe',
        'DisplaySwitch.exe',
        'AtBroker.exe'
    )
    
    $removedCount = 0
    $skippedCount = 0
    $removedItems = @()
    
    # Registry path where Image File Execution Options are stored
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    
    # First, scan for debuggers
    Write-Host "Scanning for debuggers..." -ForegroundColor Yellow
    $foundDebuggers = @()
    
    foreach ($exe in $accessibilityExes) {
        $exePath = Join-Path $registryPath $exe
        
        if (Test-Path $exePath) {
            $debugger = Get-ItemProperty -Path $exePath -Name "Debugger" -ErrorAction SilentlyContinue
            
            if ($debugger -and $debugger.Debugger) {
                $foundDebuggers += [PSCustomObject]@{
                    Executable = $exe
                    RegistryPath = $exePath
                    Debugger = $debugger.Debugger
                }
            }
        }
    }
    
    # Display findings
    if ($foundDebuggers.Count -eq 0) {
        Write-Host "`nNo debuggers found attached to accessibility features." -ForegroundColor Green
        Write-Host "System is clean!" -ForegroundColor Green
        return @{
            RemovedCount = 0
            SkippedCount = 0
            RemovedItems = @()
        }
    }
    
    Write-Host "`nFound $($foundDebuggers.Count) debugger(s):" -ForegroundColor Yellow
    $foundDebuggers | Format-Table -AutoSize
    
    # Process removals
    Write-Host "`nProcessing removals..." -ForegroundColor Cyan
    
    foreach ($item in $foundDebuggers) {
        Write-Host "`n[$($item.Executable)]" -ForegroundColor Yellow
        Write-Host "  Registry: $($item.RegistryPath)"
        Write-Host "  Debugger: $($item.Debugger)" -ForegroundColor Red
        
        $shouldRemove = $false
        
        if ($WhatIfPreference) {
            Write-Host "  Action: WOULD REMOVE (WhatIf mode)" -ForegroundColor Cyan
            $skippedCount++
            continue
        }
        
        if ($Interactive) {
            # Ask for confirmation only in interactive mode
            $response = Read-Host "  Remove this debugger? (Y/N)"
            if ($response -eq 'Y' -or $response -eq 'y') {
                $shouldRemove = $true
            }
        } else {
            # Default: automatically remove without prompting
            $shouldRemove = $true
        }
        
        if ($shouldRemove) {
            try {
                # Remove the Debugger property
                Remove-ItemProperty -Path $item.RegistryPath -Name "Debugger" -ErrorAction Stop
                Write-Host "  Status: " -NoNewline
                Write-Host "REMOVED" -ForegroundColor Green
                $removedCount++
                $removedItems += $item
                
                # Check if the registry key is now empty, and if so, remove it
                $remainingProperties = Get-ItemProperty -Path $item.RegistryPath -ErrorAction SilentlyContinue
                if ($remainingProperties) {
                    $propertyCount = ($remainingProperties.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count
                    
                    if ($propertyCount -eq 0) {
                        Remove-Item -Path $item.RegistryPath -Force -ErrorAction Stop
                        Write-Host "  Cleanup: Empty registry key removed" -ForegroundColor Gray
                    }
                }
                
            } catch {
                Write-Host "  Status: " -NoNewline
                Write-Host "FAILED - $($_.Exception.Message)" -ForegroundColor Red
                $skippedCount++
            }
        } else {
            Write-Host "  Status: " -NoNewline
            Write-Host "SKIPPED (user declined)" -ForegroundColor Yellow
            $skippedCount++
        }
    }
    
    # Summary
    Write-Host "`n=== Removal Summary ===" -ForegroundColor Cyan
    
    if ($WhatIfPreference) {
        Write-Host "WhatIf Mode: No changes were made" -ForegroundColor Cyan
        Write-Host "Would have processed: $($foundDebuggers.Count) debugger(s)" -ForegroundColor Yellow
    } else {
        Write-Host "Removed: " -NoNewline
        Write-Host "$removedCount" -ForegroundColor Green -NoNewline
        Write-Host " debugger(s)"
        
        if ($skippedCount -gt 0) {
            Write-Host "Skipped: " -NoNewline
            Write-Host "$skippedCount" -ForegroundColor Yellow -NoNewline
            Write-Host " debugger(s)"
        }
        
        if ($removedCount -gt 0) {
            Write-Host "`nRemoved items:" -ForegroundColor Green
            $removedItems | Format-Table Executable, Debugger -AutoSize
            
            Write-Host "System has been cleaned!" -ForegroundColor Green
            Write-Host "It's recommended to reboot your system." -ForegroundColor Yellow
        }
    }
    
    return @{
        RemovedCount = $removedCount
        SkippedCount = $skippedCount
        RemovedItems = $removedItems
    }
}

# Main execution
try {
    if ($PSBoundParameters.ContainsKey('WhatIf') -and $WhatIf) {
        Write-Host "`n*** RUNNING IN WHATIF MODE - NO CHANGES WILL BE MADE ***`n" -ForegroundColor Cyan
    }
    
    if (-not $Interactive) {
        Write-Host "`n*** AUTOMATIC MODE - ALL DEBUGGERS WILL BE REMOVED ***`n" -ForegroundColor Yellow
        Write-Host "Use -Interactive flag if you want to confirm each removal`n" -ForegroundColor Gray
    }
    
    $results = Remove-AccessibilityDebuggers -Interactive:$Interactive
    
    # Exit codes
    if ($PSBoundParameters.ContainsKey('WhatIf') -and $WhatIf) {
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
