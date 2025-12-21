<#
.SYNOPSIS
    Window Manager for GSPconnect - Minimizes connector window and focuses ProTee Labs.

.DESCRIPTION
    This script waits for GSPconnect.exe to start, then:
    1. Minimizes the GSPconnect window to reduce visual clutter
    2. Brings ProTee Labs window to the foreground
    
    Designed to run after ProTee Labs is launched, giving a clean simulator experience.

.NOTES
    Author: Janne
    Repository: https://github.com/YOUR_USERNAME/protee-gspro-startup
    
    This script uses Windows API calls to manipulate window visibility.
    It polls for the GSPconnect process since it may take time to start.

.PARAMETER ConfigPath
    Optional path to config.json. If not specified, looks for config.json in script directory.

.EXAMPLE
    .\hide-gspconnect.ps1
    
    Runs with default settings.

.EXAMPLE
    .\hide-gspconnect.ps1 -ConfigPath "C:\MyConfig\config.json"
    
    Runs with custom configuration.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

#region Configuration

# Default settings (can be overridden by config.json)
$Settings = @{
    LogPath              = "C:\Scripts\hide-gspconnect.log"
    ProcessTimeoutSeconds = 60
    PollIntervalSeconds  = 1
}

# Load config if available
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $ScriptDir "config.json"
}

if (Test-Path $ConfigPath) {
    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        
        if ($config.paths.logDir) {
            $Settings.LogPath = Join-Path $config.paths.logDir "hide-gspconnect.log"
        }
        if ($config.window.processTimeoutSeconds) {
            $Settings.ProcessTimeoutSeconds = $config.window.processTimeoutSeconds
        }
        if ($config.window.pollIntervalSeconds) {
            $Settings.PollIntervalSeconds = $config.window.pollIntervalSeconds
        }
    }
    catch {
        # Config parsing failed, use defaults
    }
}

#endregion

#region Logging

$LogPath = $Settings.LogPath
$LogDir = Split-Path $LogPath -Parent

if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp [$Level] $Message" | Out-File -FilePath $LogPath -Encoding UTF8 -Append
}

# Start logging
Write-Log "----- Window Manager Started -----" "INFO"
Write-Log "Script path: $($MyInvocation.MyCommand.Path)" "DEBUG"
Write-Log "PID: $PID" "DEBUG"

#endregion

#region Diagnostics

try {
    $procSelf = Get-Process -Id $PID -ErrorAction Stop
    Write-Log "SessionId: $($procSelf.SessionId)" "DEBUG"
}
catch {
    Write-Log "Could not read current process info: $_" "WARN"
}

try {
    $isInteractive = [System.Environment]::UserInteractive
    Write-Log "UserInteractive: $isInteractive" "DEBUG"
    
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isElevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Log "IsElevated: $isElevated" "DEBUG"
}
catch {
    Write-Log "Failed to determine interactive/elevation state: $_" "WARN"
}

#endregion

#region Windows API

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class WindowsAPI {
    public const int SW_MINIMIZE = 6;
    
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@ -ErrorAction Stop

function Invoke-ShowWindow {
    <#
    .SYNOPSIS
        Safely calls ShowWindow API with logging.
    #>
    param(
        [IntPtr]$WindowHandle,
        [int]$Command
    )
    
    try {
        $result = [WindowsAPI]::ShowWindow($WindowHandle, $Command)
        Write-Log "ShowWindow returned: $result for hwnd $WindowHandle cmd $Command" "DEBUG"
        return $result
    }
    catch {
        Write-Log "ShowWindow exception for hwnd $WindowHandle : $_" "ERROR"
        return $false
    }
}

function Invoke-SetForegroundWindow {
    <#
    .SYNOPSIS
        Safely calls SetForegroundWindow API with logging.
    #>
    param(
        [IntPtr]$WindowHandle
    )
    
    try {
        $result = [WindowsAPI]::SetForegroundWindow($WindowHandle)
        Write-Log "SetForegroundWindow returned: $result for hwnd $WindowHandle" "DEBUG"
        return $result
    }
    catch {
        Write-Log "SetForegroundWindow exception for hwnd $WindowHandle : $_" "ERROR"
        return $false
    }
}

#endregion

#region Process Management

function Wait-ForProcess {
    <#
    .SYNOPSIS
        Waits for a process to start and have a main window.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcessName,
        
        [int]$TimeoutSeconds = 60,
        [int]$PollIntervalSeconds = 1
    )
    
    $waited = 0
    
    # Wait for process to exist
    Write-Log "Waiting for $ProcessName process to start..." "INFO"
    while (-not (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)) {
        Start-Sleep -Seconds $PollIntervalSeconds
        $waited += $PollIntervalSeconds
        
        if ($waited -ge $TimeoutSeconds) {
            Write-Log "Timeout waiting for $ProcessName to appear (>$TimeoutSeconds s)." "WARN"
            return $null
        }
    }
    Write-Log "$ProcessName process detected after $waited s." "INFO"
    
    # Wait for main window
    $waited = 0
    Write-Log "Waiting for $ProcessName main window..." "INFO"
    
    do {
        $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($proc -and $proc.MainWindowHandle -ne 0) {
            Write-Log "$ProcessName window detected after $waited s (hwnd=$($proc.MainWindowHandle))." "INFO"
            return $proc
        }
        
        Start-Sleep -Seconds $PollIntervalSeconds
        $waited += $PollIntervalSeconds
        
        if ($waited -ge $TimeoutSeconds) {
            Write-Log "Timeout waiting for $ProcessName main window (>$TimeoutSeconds s)." "WARN"
            return $proc  # Return process anyway, might be minimized
        }
    } while ($true)
}

function Get-ProcessByPath {
    <#
    .SYNOPSIS
        Finds a process by matching its executable path.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathPattern
    )
    
    return Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path -like $PathPattern
    } | Select-Object -First 1
}

#endregion

#region Main Execution

# Step 1: Wait for GSPconnect and minimize it
$gspProcess = Wait-ForProcess `
    -ProcessName "GSPconnect" `
    -TimeoutSeconds $Settings.ProcessTimeoutSeconds `
    -PollIntervalSeconds $Settings.PollIntervalSeconds

if ($gspProcess) {
    Write-Log "Found GSPconnect (Id=$($gspProcess.Id), Name=$($gspProcess.ProcessName))" "INFO"
    
    $hwnd = $gspProcess.MainWindowHandle
    Write-Log "GSPconnect MainWindowHandle = $hwnd" "DEBUG"
    
    if ($hwnd -ne 0) {
        Invoke-ShowWindow -WindowHandle $hwnd -Command ([WindowsAPI]::SW_MINIMIZE) | Out-Null
        Write-Log "GSPconnect window minimized." "INFO"
    }
    else {
        Write-Log "GSPconnect has no MainWindowHandle (0). Possibly non-interactive or already minimized." "WARN"
    }
}
else {
    Write-Log "GSPconnect process not found within timeout." "INFO"
}

# Step 2: Bring ProTee Labs to foreground
try {
    $proteeProcess = Get-ProcessByPath -PathPattern "*ProTee Labs.exe"
    
    if ($proteeProcess) {
        Write-Log "Found ProTee Labs (Id=$($proteeProcess.Id), Path=$($proteeProcess.Path))" "INFO"
        
        $hwnd = $proteeProcess.MainWindowHandle
        Write-Log "ProTee Labs MainWindowHandle = $hwnd" "DEBUG"
        
        if ($hwnd -ne 0) {
            Invoke-SetForegroundWindow -WindowHandle $hwnd | Out-Null
            Write-Log "ProTee Labs window brought to foreground." "INFO"
        }
        else {
            Write-Log "ProTee Labs has no MainWindowHandle (0). Possibly running in another session." "WARN"
        }
    }
    else {
        Write-Log "ProTee Labs process not found." "INFO"
    }
}
catch {
    Write-Log "Error while processing ProTee Labs: $_" "ERROR"
}

Write-Log "----- Window Manager Finished -----" "INFO"

#endregion
