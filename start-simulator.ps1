<#
.SYNOPSIS
    Golf Simulator Startup Script for ProTee Labs + GSPro

.DESCRIPTION
    Automated startup script that:
    1. Waits for network connectivity
    2. Optionally powers on Samsung TV via SmartThings
    3. Launches ProTee Labs (which starts GSPro)
    4. Minimizes the GSPconnect window for a clean setup

.NOTES
    Author: Janne Seppänen
    Repository: https://github.com/jannesep/protee-gspro-startup
    
    Configuration:
    - Copy config.example.json to config.json and fill in your values
    - Copy samsung_auth.example.json to samsung_auth.json with your OAuth tokens
    - Set smartThings.enabled to false if you don't need TV control

.EXAMPLE
    .\start-simulator.ps1
    
    Runs with default config.json in the script directory.

.EXAMPLE
    .\start-simulator.ps1 -ConfigPath "C:\MyConfig\config.json"
    
    Runs with a custom configuration file path.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

#region Configuration

function Get-ScriptConfig {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path`nPlease copy config.example.json to config.json and fill in your values."
    }
    
    try {
        $config = Get-Content $Path -Raw | ConvertFrom-Json
        return $config
    }
    catch {
        throw "Failed to parse configuration file: $_"
    }
}

# Determine config path
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $ScriptDir "config.json"
}

$Config = Get-ScriptConfig -Path $ConfigPath

#endregion

#region Logging

$LogFile = Join-Path $Config.paths.logDir "startup-log-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"

# Ensure log directory exists
$logDir = Split-Path $LogFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path $LogFile

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN" { Write-Host $logMessage -ForegroundColor Yellow }
        "DEBUG" { Write-Host $logMessage -ForegroundColor Gray }
        default { Write-Host $logMessage }
    }
}

Write-Log "===== Golf Simulator Startup Script ====="
Write-Log "Script directory: $ScriptDir"
Write-Log "Configuration: $ConfigPath"

#endregion

#region Network Functions

function Test-InternetConnection {
    <#
    .SYNOPSIS
        Tests for active internet connectivity.
    #>
    try {
        $ping = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet
        return $ping
    }
    catch {
        return $false
    }
}

function Wait-ForInternet {
    <#
    .SYNOPSIS
        Polls for internet connection with configurable retry settings.
    #>
    param(
        [int]$MaxAttempts = 10,
        [int]$RetryIntervalSeconds = 2
    )
    
    $attempt = 0
    $connected = $false
    
    while (-not $connected -and $attempt -lt $MaxAttempts) {
        $connected = Test-InternetConnection
        if (-not $connected) {
            Write-Log "No internet connection. Retrying in $RetryIntervalSeconds seconds... (Attempt $($attempt + 1)/$MaxAttempts)" -Level "WARN"
            Start-Sleep -Seconds $RetryIntervalSeconds
        }
        $attempt++
    }
    
    return $connected
}

#endregion

#region SmartThings Functions

function Update-SmartThingsToken {
    <#
    .SYNOPSIS
        Refreshes the SmartThings OAuth token using the refresh token.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$AuthFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientId,
        
        [Parameter(Mandatory = $true)]
        [string]$ClientSecret
    )
    
    if (-not (Test-Path $AuthFilePath)) {
        Write-Log "Auth file not found: $AuthFilePath" -Level "ERROR"
        return $null
    }
    
    $auth = Get-Content $AuthFilePath | ConvertFrom-Json
    
    # Create Base64 encoded credentials
    $credentials = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${ClientId}:${ClientSecret}"))
    
    try {
        $curlArgs = @(
            "--silent", "--show-error",
            "--location", "https://api.smartthings.com/oauth/token",
            "--header", "Content-Type: application/x-www-form-urlencoded",
            "--header", "Authorization: Basic $credentials",
            "--data-urlencode", "grant_type=refresh_token",
            "--data-urlencode", "client_id=$ClientId",
            "--data-urlencode", "client_secret=$ClientSecret",
            "--data-urlencode", "refresh_token=$($auth.refresh_token)"
        )
        
        $responseJson = & curl.exe @curlArgs 2>$null
        
        if ($responseJson) {
            $responseJson = $responseJson.Trim()
            $response = $responseJson | ConvertFrom-Json
            
            if ($response.access_token) {
                $auth.access_token = $response.access_token
                
                if ($response.PSObject.Properties.Name -contains "refresh_token") {
                    $auth.refresh_token = $response.refresh_token
                }
                
                $auth | ConvertTo-Json -Depth 5 | Set-Content -Path $AuthFilePath -Encoding UTF8
                Write-Log "SmartThings token refreshed and saved."
                return $auth
            }
            else {
                Write-Log "Token refresh failed. Response: $responseJson" -Level "WARN"
            }
        }
        else {
            Write-Log "No response from SmartThings token endpoint." -Level "WARN"
        }
    }
    catch {
        Write-Log "Exception during token refresh: $($_.Exception.Message)" -Level "WARN"
    }
    
    Write-Log "Using existing token." -Level "WARN"
    return $auth
}

function Start-SamsungTV {
    <#
    .SYNOPSIS
        Powers on the Samsung TV via SmartThings API.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeviceId,
        
        [Parameter(Mandatory = $true)]
        [string]$AccessToken,
        
        [Parameter(Mandatory = $true)]
        [string]$CliPath
    )
    
    if (-not (Test-Path $CliPath)) {
        Write-Log "SmartThings CLI not found at: $CliPath" -Level "ERROR"
        return $false
    }
    
    try {
        Write-Log "Powering on Samsung TV (Device: $DeviceId)..."
        $env:SMARTTHINGS_TOKEN = $AccessToken
        & $CliPath devices:commands $DeviceId main:switch:on
        Write-Log "Samsung TV power command sent."
        return $true
    }
    catch {
        Write-Log "Failed to send TV power command: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

#endregion

#region Application Functions

function Start-ProTeeLabs {
    <#
    .SYNOPSIS
        Launches ProTee Labs application.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExePath
    )
    
    if (-not (Test-Path $ExePath)) {
        throw "ProTee Labs not found at: $ExePath"
    }
    
    Write-Log "Starting ProTee Labs..."
    
    $process = Start-Process -FilePath $ExePath -PassThru
    
    if (-not $process) {
        throw "Start-Process returned null for ProTee Labs"
    }
    
    Write-Log "ProTee Labs started successfully. PID: $($process.Id)"
    return $process
}

function Start-WindowManager {
    <#
    .SYNOPSIS
        Runs the hide-gspconnect.ps1 script to manage window visibility.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$ScriptPath
    )
    
    if (-not $ScriptPath) {
        $ScriptPath = Join-Path $ScriptDir "hide-gspconnect.ps1"
    }
    
    if (-not (Test-Path $ScriptPath)) {
        Write-Log "Window manager script not found: $ScriptPath" -Level "WARN"
        return $false
    }
    
    try {
        Write-Log "Running window manager script..."
        powershell.exe -ExecutionPolicy Bypass -File $ScriptPath -ConfigPath $ConfigPath
        Write-Log "Window manager script completed."
        return $true
    }
    catch {
        Write-Log "Error running window manager: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

#endregion

#region Main Execution

try {
    # Step 1: Wait for internet connection
    Write-Log "Checking internet connectivity..."
    $connected = Wait-ForInternet `
        -MaxAttempts $Config.network.maxRetries `
        -RetryIntervalSeconds $Config.network.retryIntervalSeconds
    
    if (-not $connected) {
        throw "Failed to establish internet connection after $($Config.network.maxRetries) attempts."
    }
    Write-Log "Internet connection established."
    
    # Step 2: SmartThings TV control (optional)
    if ($Config.smartThings.enabled) {
        Write-Log "SmartThings integration enabled. Preparing TV..."
        
        $authFilePath = $Config.paths.authFile
        if (-not [System.IO.Path]::IsPathRooted($authFilePath)) {
            $authFilePath = Join-Path $ScriptDir $authFilePath
        }
        
        $auth = Update-SmartThingsToken `
            -AuthFilePath $authFilePath `
            -ClientId $Config.smartThings.clientId `
            -ClientSecret $Config.smartThings.clientSecret
        
        if ($auth) {
            Start-SamsungTV `
                -DeviceId $Config.smartThings.deviceId `
                -AccessToken $auth.access_token `
                -CliPath $Config.smartThings.cliPath | Out-Null
        }
    }
    else {
        Write-Log "SmartThings integration disabled. Skipping TV control."
    }
    
    # Step 3: Launch ProTee Labs
    Start-ProTeeLabs -ExePath $Config.paths.proteeLabsExe
    
    # Step 4: Manage windows (minimize GSPconnect, focus ProTee Labs)
    Start-WindowManager | Out-Null
    
    Write-Log "===== Startup sequence completed successfully ====="
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" -Level "ERROR"
    Write-Log $_.ScriptStackTrace -Level "ERROR"
    
    # Keep window open for debugging when run interactively
    if ([Environment]::UserInteractive) {
        Write-Host "`nPress ENTER to exit..." -ForegroundColor Yellow
        Read-Host
    }
    
    Stop-Transcript
    exit 1
}

Stop-Transcript

#endregion
