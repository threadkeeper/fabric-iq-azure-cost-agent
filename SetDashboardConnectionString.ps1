#
# SetDashboardConnectionString.ps1 - Configure Power BI project with Lakehouse connection from .env
#
# Usage:
#   .\SetDashboardConnectionString.ps1
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
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match '^\s*LAKEHOUSE_SQL_ENDPOINT\s*=\s*(.+?)\s*$') {
            $endpoint = $Matches[1]
        }
        if ($line -match '^\s*LAKEHOUSE_DATABASE\s*=\s*(.+?)\s*$') {
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
# Fabric Lakehouse connection (added by SetDashboardConnectionString.ps1)
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

# Replace the parameter expressions. The expression values are JSON strings that
# contain escaped quotes, so build valid JSON string literals before replacing.
function ConvertTo-JsonStringLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ($Value | ConvertTo-Json -Compress)
}

function Set-ModelParameterExpression {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$ParameterName,
        [Parameter(Mandatory = $true)][string]$Expression
    )

    $pattern = '("name":\s*"' + [regex]::Escape($ParameterName) + '"[\s\S]*?"expression":\s*)"(?:\\.|[^"\\])*"'
    $replacement = "`$1" + (ConvertTo-JsonStringLiteral $Expression)
    return [regex]::Replace($Content, $pattern, $replacement)
}

$endpointExpression = "`"$endpoint`" meta [IsParameterQuery=true, Type=`"Text`", IsParameterQueryRequired=true]"
$databaseExpression = "`"$database`" meta [IsParameterQuery=true, Type=`"Text`", IsParameterQueryRequired=true]"

$newContent = Set-ModelParameterExpression -Content $content -ParameterName "Lakehouse SQL Endpoint" -Expression $endpointExpression
$newContent = Set-ModelParameterExpression -Content $newContent -ParameterName "Lakehouse Database" -Expression $databaseExpression

if ($content -eq $newContent) {
    $model = $newContent | ConvertFrom-Json
    $configuredEndpoint = ($model.model.expressions | Where-Object { $_.name -eq "Lakehouse SQL Endpoint" }).expression
    $configuredDatabase = ($model.model.expressions | Where-Object { $_.name -eq "Lakehouse Database" }).expression

    if (($configuredEndpoint -eq $endpointExpression) -and ($configuredDatabase -eq $databaseExpression)) {
        Write-Host "[INFO] Lakehouse parameters are already configured" -ForegroundColor Green
    } else {
        Write-Host "[WARN] No parameter expressions were updated - check model.bim format" -ForegroundColor Yellow
    }
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
