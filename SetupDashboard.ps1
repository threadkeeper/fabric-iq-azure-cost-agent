#
# SetupDashboard.ps1 - Configure Power BI project with Lakehouse connection from .env
#
# Usage:
#   .\SetupDashboard.ps1
#
# Reads LAKEHOUSE_SQL_ENDPOINT and LAKEHOUSE_DATABASE from .env,
# updates the semantic model parameters in model.bim.
# After running, open AzureBillingDashboard.pbip in Power BI Desktop.
# Sign in once with your Entra ID (Azure AD) account - credentials are cached.
#

$ErrorActionPreference = "Stop"

$EnvFile   = Join-Path $PSScriptRoot ".env"
$ModelFile = Join-Path $PSScriptRoot "dashboard\AzureBillingDashboard.SemanticModel\model.bim"

# --- Parse .env file ----------------------------------------------------------
$endpoint = $null
$database = $null

if (Test-Path $EnvFile) {
    Get-Content $EnvFile | ForEach-Object {
        if ($_ -match '^\s*LAKEHOUSE_SQL_ENDPOINT\s*=\s*(.+?)\s*$') {
            $endpoint = $Matches[1]
        }
        if ($_ -match '^\s*LAKEHOUSE_DATABASE\s*=\s*(.+?)\s*$') {
            $database = $Matches[1]
        }
    }
}

# --- Prompt for missing values -----------------------------------------------
if (-not $endpoint) {
    Write-Host ""
    Write-Host "  LAKEHOUSE_SQL_ENDPOINT not found in .env" -ForegroundColor Yellow
    Write-Host "  To find it: Fabric Portal -> Lakehouse -> Settings -> SQL analytics endpoint -> Server"
    Write-Host ""
    $endpoint = Read-Host "  Enter your Lakehouse SQL Endpoint (e.g. xxxx.datawarehouse.fabric.microsoft.com)"
    if (-not $endpoint) {
        Write-Host "[ERROR] SQL endpoint is required." -ForegroundColor Red
        exit 1
    }
}

if (-not $database) {
    $database = Read-Host "  Enter your Lakehouse Database name (default: CostManagementLakehouse)"
    if (-not $database) { $database = "CostManagementLakehouse" }
}

# --- Save to .env if not already there ---------------------------------------
if (Test-Path $EnvFile) {
    $envContent = Get-Content $EnvFile -Raw
    $updated = $false
    if ($envContent -notmatch 'LAKEHOUSE_SQL_ENDPOINT\s*=\s*\S') {
        Add-Content $EnvFile "`nLAKEHOUSE_SQL_ENDPOINT=$endpoint"
        $updated = $true
    }
    if ($envContent -notmatch 'LAKEHOUSE_DATABASE\s*=\s*\S') {
        Add-Content $EnvFile "`nLAKEHOUSE_DATABASE=$database"
        $updated = $true
    }
    if ($updated) {
        Write-Host "[INFO] Lakehouse settings saved to .env" -ForegroundColor Green
    }
} else {
    @"
# Fabric Lakehouse connection (added by SetupDashboard.ps1)
LAKEHOUSE_SQL_ENDPOINT=$endpoint
LAKEHOUSE_DATABASE=$database
"@ | Set-Content $EnvFile -Encoding UTF8
    Write-Host "[INFO] Created .env with Lakehouse settings" -ForegroundColor Green
}

# --- Update model.bim --------------------------------------------------------
if (-not (Test-Path $ModelFile)) {
    Write-Host "[ERROR] model.bim not found at: $ModelFile" -ForegroundColor Red
    exit 1
}

$content = Get-Content $ModelFile -Raw

# Replace the endpoint parameter value using regex (preserves JSON formatting)
$endpointPattern = '("name":\s*"Lakehouse SQL Endpoint"[\s\S]*?"expression":\s*)"[^"]*"\s*(meta\s*\[IsParameterQuery)'
$endpointReplace = "`$1`"$endpoint`" `$2"
$newContent = [regex]::Replace($content, $endpointPattern, $endpointReplace)

# Replace the database parameter value using regex
$dbPattern = '("name":\s*"Lakehouse Database"[\s\S]*?"expression":\s*)"[^"]*"\s*(meta\s*\[IsParameterQuery)'
$dbReplace = "`$1`"$database`" `$2"
$newContent = [regex]::Replace($newContent, $dbPattern, $dbReplace)

if ($content -eq $newContent) {
    Write-Host "[WARN] No parameter expressions were updated - check model.bim format" -ForegroundColor Yellow
} else {
    [System.IO.File]::WriteAllText($ModelFile, $newContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[INFO] Set Lakehouse SQL Endpoint: $endpoint" -ForegroundColor Green
    Write-Host "[INFO] Set Lakehouse Database:     $database" -ForegroundColor Green
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Dashboard Ready" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "    1. Open dashboard\AzureBillingDashboard.pbip in Power BI Desktop"
Write-Host "    2. When prompted for credentials, choose 'Microsoft account'"
Write-Host "       and sign in with your Entra ID account (one time only)"
Write-Host "    3. Click 'Apply changes' if prompted to refresh"
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
