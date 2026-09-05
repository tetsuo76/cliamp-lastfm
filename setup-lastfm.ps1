<#
.SYNOPSIS
    Last.fm OAuth Setup Script for cliamp (Windows PowerShell)

.DESCRIPTION
    This script guides users through Last.fm authentication and saves
    credentials directly into the cliamp config.toml file.
#>

[CmdletBinding()]
param(
    [string]$ConfigFile = $(
        if ($env:APPDATA -and (Test-Path (Join-Path $env:APPDATA "cliamp\config.toml"))) {
            Join-Path $env:APPDATA "cliamp\config.toml"
        } elseif (Test-Path "$HOME\.config\cliamp\config.toml") {
            "$HOME\.config\cliamp\config.toml"
        } elseif ($env:APPDATA) {
            Join-Path $env:APPDATA "cliamp\config.toml"
        } else {
            "$HOME\.config\cliamp\config.toml"
        }
    )
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ApiUrl = "https://ws.audioscrobbler.com/2.0/"
$SectionName = "plugins.cliamp-lastfm"

function Print-Header {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Last.fm OAuth Setup for cliamp" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Print-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Print-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Print-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Cyan
}

function Print-Step {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Get-Md5Hash {
    param([string]$InputString)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $hashBytes = $md5.ComputeHash($bytes)
    return -join ($hashBytes | ForEach-Object { '{0:x2}' -f $_ })
}

function Get-ApiSig {
    param(
        [string]$ApiSecret,
        [hashtable]$Params
    )
    $sortedKeys = $Params.Keys | Where-Object { $_ -ne "format" } | Sort-Object
    $sigStr = ""
    foreach ($key in $sortedKeys) {
        $sigStr += "$key$($Params[$key])"
    }
    $sigStr += $ApiSecret
    return Get-Md5Hash $sigStr
}

function Open-Browser {
    param([string]$Url)
    try {
        Start-Process $Url
        return $true
    }
    catch {
        Print-Info "Please open this URL in your browser: $Url"
        return $false
    }
}

function Invoke-LastFmGet {
    param([string]$Uri)
    try {
        $data = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 30
        return @{ Success = $true; Data = $data }
    }
    catch {
        $errMsg = $_.Exception.Message
        $errJson = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            try { $errJson = $_.ErrorDetails.Message | ConvertFrom-Json } catch {}
        }
        if (-not $errJson -and $_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $body = $reader.ReadToEnd()
                $errJson = $body | ConvertFrom-Json
            } catch {}
        }
        return @{ Success = $false; Error = $errMsg; Json = $errJson }
    }
}

function Check-ConfigFile {
    if (-not (Test-Path -Path $ConfigFile -PathType Leaf)) {
        Print-Error "Config file not found: $ConfigFile"
        Print-Info "Please create $ConfigFile first"
        exit 1
    }
}

function Setup-ConfigSection {
    $content = Get-Content -Path $ConfigFile -Encoding utf8 -Raw
    if ($content -notmatch "(?m)^\s*\[plugins\.cliamp-lastfm\]") {
        Print-Step "Adding [plugins.cliamp-lastfm] section to config..."
        $rawLines = Get-Content -Path $ConfigFile -Encoding utf8 -ErrorAction SilentlyContinue
        [System.Collections.Generic.List[string]]$lines = [System.Collections.Generic.List[string]]::new()
        if ($rawLines) {
            $lines.AddRange([string[]]$rawLines)
        }
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne "") {
            $lines.Add("")
        }
        $lines.Add("[plugins.cliamp-lastfm]")
        [System.IO.File]::WriteAllLines($ConfigFile, $lines, [System.Text.UTF8Encoding]::new($false))
        Print-Success "Section added"
    }
}

function Update-Config {
    param(
        [string]$Key,
        [string]$Value
    )
    $rawLines = Get-Content -Path $ConfigFile -Encoding utf8 -ErrorAction SilentlyContinue
    [System.Collections.Generic.List[string]]$lines = [System.Collections.Generic.List[string]]::new()
    if ($rawLines) {
        $lines.AddRange([string[]]$rawLines)
    }

    $escapedValue = $Value.Replace('\', '\\').Replace('"', '\"')
    $newLine = "$Key = `"$escapedValue`""

    $sectionIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -match "^\[\s*plugins\.cliamp-lastfm\s*\]$") {
            $sectionIndex = $i
            break
        }
    }

    if ($sectionIndex -eq -1) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne "") {
            $lines.Add("")
        }
        $lines.Add("[plugins.cliamp-lastfm]")
        $lines.Add($newLine)
        [System.IO.File]::WriteAllLines($ConfigFile, $lines, [System.Text.UTF8Encoding]::new($false))
        return
    }

    # Find section end (next section header or EOF)
    $nextSectionIndex = $lines.Count
    for ($j = $sectionIndex + 1; $j -lt $lines.Count; $j++) {
        if ($lines[$j].Trim() -match "^\[.*\]$") {
            $nextSectionIndex = $j
            break
        }
    }

    # Search for existing key within this section
    $keyIndex = -1
    for ($k = $sectionIndex + 1; $k -lt $nextSectionIndex; $k++) {
        if ($lines[$k] -match "^\s*$([regex]::Escape($Key))\s*=") {
            $keyIndex = $k
            break
        }
    }

    if ($keyIndex -ne -1) {
        $lines[$keyIndex] = $newLine
    } else {
        $lines.Insert($sectionIndex + 1, $newLine)
    }

    [System.IO.File]::WriteAllLines($ConfigFile, $lines, [System.Text.UTF8Encoding]::new($false))
}

# --- Main Flow ---

Print-Header

# Step 1: Get API credentials
Print-Step "Step 1: Last.fm API Credentials"
Print-Info "Opening Last.fm API registration page..."
[void](Open-Browser "https://www.last.fm/api/account/create")
Write-Host ""
Print-Info "Register a new application with any app name (ignore callback URL)"
Print-Info "Copy your API Key and Secret"
Write-Host ""

$apiKey = (Read-Host "Enter your API Key").Trim().Trim('"').Trim("'")
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Print-Error "API Key cannot be empty"
    exit 1
}

$apiSecret = (Read-Host "Enter your API Secret").Trim().Trim('"').Trim("'")
if ([string]::IsNullOrWhiteSpace($apiSecret)) {
    Print-Error "API Secret cannot be empty"
    exit 1
}

Print-Success "API credentials received"
Write-Host ""

# Step 2: Get username
Print-Step "Step 2: Last.fm Username"
$username = (Read-Host "Enter your Last.fm username").Trim().Trim('"').Trim("'")
if ([string]::IsNullOrWhiteSpace($username)) {
    Print-Error "Username cannot be empty"
    exit 1
}
Print-Success "Username: $username"
Write-Host ""

# Step 3: Get auth token
Print-Step "Step 3: Getting authorization token..."
$encodedApiKey = [System.Uri]::EscapeDataString($apiKey)
$tokenUri = "${ApiUrl}?method=auth.getToken&api_key=$encodedApiKey&format=json"
$tokenResult = Invoke-LastFmGet -Uri $tokenUri

$authToken = $null
if ($tokenResult.Success -and $tokenResult.Data -and $tokenResult.Data.token) {
    $authToken = $tokenResult.Data.token
}

if ([string]::IsNullOrWhiteSpace($authToken)) {
    Print-Error "Failed to get auth token"
    if ($tokenResult.Json -and $tokenResult.Json.message) {
        Print-Info "Response: $($tokenResult.Json.message)"
    } elseif ($tokenResult.Error) {
        Print-Info "Response: $($tokenResult.Error)"
    }
    exit 1
}

Print-Success "Auth token received: $authToken"
Write-Host ""

# Step 4: Open browser for authorization
Print-Step "Step 4: Authorization"
$encodedToken = [System.Uri]::EscapeDataString($authToken)
$authUrl = "https://www.last.fm/api/auth/?api_key=$encodedApiKey&token=$encodedToken"

Print-Info "Opening Last.fm authorization page..."
Print-Info "You'll need to click the 'ALLOW' button"
Print-Info ""

if (-not (Open-Browser $authUrl)) {
    Write-Host "Auth URL: $authUrl"
}

Write-Host ""
[void](Read-Host "Press Enter after you've authorized the application...")
Write-Host ""

# Step 5: Exchange token for session key
Print-Step "Step 5: Getting session key..."

# Build signature
$sig = Get-ApiSig -ApiSecret $apiSecret -Params @{
    "api_key" = $apiKey
    "method"  = "auth.getSession"
    "token"   = $authToken
}

$encodedSig = [System.Uri]::EscapeDataString($sig)
$sessionUri = "${ApiUrl}?method=auth.getSession&api_key=$encodedApiKey&token=$encodedToken&api_sig=$encodedSig&format=json"
$sessionResult = Invoke-LastFmGet -Uri $sessionUri

$sessionKey = $null
$usernameFromApi = $null
if ($sessionResult.Success -and $sessionResult.Data -and $sessionResult.Data.session) {
    $sessionKey = $sessionResult.Data.session.key
    $usernameFromApi = $sessionResult.Data.session.name
}

if ([string]::IsNullOrWhiteSpace($sessionKey)) {
    $errorMsg = if ($sessionResult.Json -and $sessionResult.Json.message) {
        $sessionResult.Json.message
    } elseif ($sessionResult.Error) {
        $sessionResult.Error
    } else {
        "Unknown error"
    }

    Print-Error "Failed to get session key: $errorMsg"
    Print-Info "Make sure you clicked 'ALLOW' on the Last.fm page"
    if ($sessionResult.Json) {
        Print-Info "Response: $($sessionResult.Json | ConvertTo-Json -Compress)"
    }
    exit 1
}

Print-Success "Session key received"
Print-Success "Authenticated as: $usernameFromApi"
Write-Host ""

# Step 6: Save to config file
Print-Step "Step 6: Saving credentials to config..."
Check-ConfigFile
Setup-ConfigSection

Update-Config -Key "api_key" -Value $apiKey
Update-Config -Key "api_secret" -Value $apiSecret
Update-Config -Key "session_key" -Value $sessionKey
Update-Config -Key "username" -Value $usernameFromApi

Print-Success "Credentials saved to $ConfigFile"
Write-Host ""

# Summary
Print-Header
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Configuration saved:"
$maskedKey = if ($apiKey.Length -ge 10) { $apiKey.Substring(0, 10) + "..." } else { $apiKey }
Write-Host "  API Key:      $maskedKey"
Write-Host "  Username:     $usernameFromApi"
Write-Host "  Config file:  $ConfigFile"
Write-Host ""
Print-Info "Restart cliamp to start scrobbling!"
Write-Host ""
