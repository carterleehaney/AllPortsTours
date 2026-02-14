#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Checks for debugger attachments to Windows accessibility features (Sticky Keys suite).

.DESCRIPTION
    This script examines registry keys for common accessibility executables to detect
    if debuggers have been attached - a common persistence/backdoor technique.
    
.NOTES
    Requires Administrator privileges to read registry keys.
#>

function Check-AccessibilityDebuggers {
    [CmdletBinding()]
    param()
    
    Write-Host "`n=== Checking for Accessibility Feature Debugger Attachments ===" -ForegroundColor Cyan
    Write-Host "This checks for unauthorized debuggers attached to accessibility executables`n" -ForegroundColor Gray
    
    # Define the accessibility executables to check
    $accessibilityExes = @(
        'sethc.exe',      # Sticky Keys
        'utilman.exe',    # Utility Manager
        'osk.exe',        # On-Screen Keyboard
        'Magnify.exe',    # Magnifier
        'Narrator.exe',   # Narrator
        'DisplaySwitch.exe', # Display Switch
        'AtBroker.exe'    # Assistive Technology Manager
    )
    
    $findings = @()
    $issuesFound = $false
    
    # Registry path where Image File Execution Options are stored
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    
    foreach ($exe in $accessibilityExes) {
        $exePath = Join-Path $registryPath $exe
        
        Write-Host "Checking: " -NoNewline
        Write-Host $exe -ForegroundColor Yellow -NoNewline
        
        # Check if registry key exists for this executable
        if (Test-Path $exePath) {
            # Check for Debugger value
            $debugger = Get-ItemProperty -Path $exePath -Name "Debugger" -ErrorAction SilentlyContinue
            
            if ($debugger -and $debugger.Debugger) {
                $issuesFound = $true
                Write-Host " - " -NoNewline
                Write-Host "DEBUGGER FOUND!" -ForegroundColor Red
                
                $finding = [PSCustomObject]@{
                    Executable = $exe
                    RegistryPath = $exePath
                    Debugger = $debugger.Debugger
                    Status = "SUSPICIOUS"
                }
                
                $findings += $finding
                
                Write-Host "  Registry Path: $exePath" -ForegroundColor Red
                Write-Host "  Debugger Value: $($debugger.Debugger)" -ForegroundColor Red
                Write-Host ""
            } else {
                Write-Host " - " -NoNewline
                Write-Host "Registry key exists but no debugger value" -ForegroundColor Yellow
            }
        } else {
            Write-Host " - " -NoNewline
            Write-Host "Clean (no registry key)" -ForegroundColor Green
        }
    }
    
    # Summary
    Write-Host "`n=== Summary ===" -ForegroundColor Cyan
    
    if ($issuesFound) {
        Write-Host "WARNING: " -NoNewline -ForegroundColor Red
        Write-Host "Found $($findings.Count) debugger attachment(s)!" -ForegroundColor Red
    } else {
        Write-Host "All accessibility executables are clean - no debuggers found." -ForegroundColor Green
    }
    
    # Return findings for further processing if needed
    return $findings
}

# Execute the check
try {
    $results = Check-AccessibilityDebuggers
    
    # Exit code: 0 = clean, 1 = issues found
    if ($results.Count -gt 0) {
        exit 1
    } else {
        exit 0
    }
} catch {
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure you're running this script as Administrator." -ForegroundColor Yellow
    exit 2
}
