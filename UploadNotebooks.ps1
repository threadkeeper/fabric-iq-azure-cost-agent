<#
.SYNOPSIS
    Uploads (or updates) all notebooks and dashboard assets to the Fabric workspace.

.DESCRIPTION
    1. Reads local .ipynb files, injects Lakehouse connection metadata, and
       creates or updates them in the Fabric workspace.
    2. Uploads the dashboard/ folder and data_agent_instructions.md to
       Lakehouse Files via the OneLake DFS API so that deploy/agent notebooks
       can read them at runtime.

    Notebooks uploaded:
      - 00_clear_cost_deltafiles
      - 01_download_cost_data
      - 02_deploy_dashboard
      - 03_create_cost_ontology
      - 04_create_data_agent

.PARAMETER WorkspaceName
    Fabric workspace name. Default: workspace-public-001

.PARAMETER FolderName
    Folder inside the workspace. Default: notebooks

.PARAMETER LakehouseName
    Lakehouse to attach. Default: dbAzureCostLakeHouse

.EXAMPLE
    .\UploadNotebooks.ps1
    .\UploadNotebooks.ps1 -WorkspaceName "my-workspace" -LakehouseName "myLakehouse"
#>
[CmdletBinding()]
param(
    [string]$WorkspaceName = "workspace-public-001",
    [string]$FolderName    = "notebooks",
    [string]$LakehouseName = "dbAzureCostLakeHouse"
)

$ErrorActionPreference = 'Stop'

$NotebookFiles = @(
    "notebooks\00_clear_cost_deltafiles.ipynb",
    "notebooks\01_download_cost_data.ipynb",
    "notebooks\02_deploy_dashboard.ipynb",
    "notebooks\03_create_cost_ontology.ipynb",
    "notebooks\04_create_data_agent.ipynb"
)

# ── Helpers ──────────────────────────────────────────────────────────────────
function Get-FabricToken {
    $json = az account get-access-token --resource https://api.fabric.microsoft.com -o json
    if (-not $json) { throw "Failed to acquire Fabric token. Run 'az login' first." }
    return ($json | ConvertFrom-Json).accessToken
}

function Invoke-Fabric {
    param([string]$Method, [string]$Uri, [string]$Body)
    $hdrs = @{ Authorization = "Bearer $script:token"; 'Content-Type' = 'application/json' }
    if ($Body) {
        return Invoke-WebRequest -Method $Method -Uri $Uri -Headers $hdrs -Body $Body -UseBasicParsing
    }
    return Invoke-WebRequest -Method $Method -Uri $Uri -Headers $hdrs -UseBasicParsing
}

function Wait-FabricOp {
    param([string]$OperationId, [string]$Label, [int]$MaxWaitSec = 120)
    $elapsed = 0
    while ($elapsed -lt $MaxWaitSec) {
        $hdrs = @{ Authorization = "Bearer $script:token" }
        $state = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/operations/$OperationId" -Headers $hdrs
        if ($state.status -eq 'Succeeded') { return $state }
        if ($state.status -eq 'Failed') { throw "$Label failed: $($state.error | ConvertTo-Json -Depth 10)" }
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    throw "$Label timed out after ${MaxWaitSec}s. OperationId: $OperationId"
}

# ── Main ─────────────────────────────────────────────────────────────────────
Write-Host "`n=== UploadNotebooks.ps1 ===" -ForegroundColor Cyan
Write-Host "Workspace : $WorkspaceName"
Write-Host "Folder    : $FolderName"
Write-Host "Lakehouse : $LakehouseName"

$script:token = Get-FabricToken

# 1. Resolve workspace
Write-Host "`n[1/5] Resolving workspace..."
$ws = (Invoke-RestMethod -Uri 'https://api.fabric.microsoft.com/v1/workspaces' `
    -Headers @{ Authorization = "Bearer $script:token" }).value |
    Where-Object { $_.displayName -eq $WorkspaceName } | Select-Object -First 1
if (-not $ws) { throw "Workspace '$WorkspaceName' not found." }
$wid = $ws.id
Write-Host "  $($ws.displayName) ($wid)"

# 2. Resolve folder
Write-Host "[2/5] Resolving folder..."
$folders = (Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$wid/folders" `
    -Headers @{ Authorization = "Bearer $script:token" }).value
$folder = $folders | Where-Object { $_.displayName -eq $FolderName } |
    Sort-Object @{ Expression = { if ($_.parentFolderId) { 1 } else { 0 } } } |
    Select-Object -First 1
$folderId = if ($folder) { $folder.id } else { $null }
if ($folderId) { Write-Host "  $FolderName ($folderId)" }
else           { Write-Host "  Folder '$FolderName' not found -- using workspace root" }

# 3. Resolve Lakehouse + SQL endpoint
Write-Host "[3/5] Resolving Lakehouse..."
$lakehouses = (Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$wid/items?type=Lakehouse" `
    -Headers @{ Authorization = "Bearer $script:token" }).value
$lh = $lakehouses | Where-Object { $_.displayName -eq $LakehouseName } | Select-Object -First 1
if (-not $lh) { throw "Lakehouse '$LakehouseName' not found in workspace '$WorkspaceName'." }
$lhId = $lh.id
Write-Host "  Lakehouse: $($lh.displayName) ($lhId)"

$sqlEndpoints = (Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$wid/items?type=SQLEndpoint" `
    -Headers @{ Authorization = "Bearer $script:token" }).value
$sqlEp = $sqlEndpoints | Where-Object { $_.displayName -eq $LakehouseName } | Select-Object -First 1
$sqlEpId = if ($sqlEp) { $sqlEp.id } else { $null }
if ($sqlEpId) { Write-Host "  SQL Endpoint: $sqlEpId" }

# Build the Lakehouse metadata to inject into each notebook
$lakehouseMeta = [ordered]@{
    kernel_info = [ordered]@{
        name = "synapse_pyspark"
    }
    dependencies = [ordered]@{
        lakehouse = [ordered]@{
            default_lakehouse              = $lhId
            default_lakehouse_name         = $LakehouseName
            default_lakehouse_workspace_id = $wid
            known_lakehouses               = @(@{ id = $lhId })
        }
    }
}
if ($sqlEpId) {
    $lakehouseMeta.dependencies.warehouse = [ordered]@{
        default_warehouse = $sqlEpId
        known_warehouses  = @(@{ id = $sqlEpId; type = "Lakewarehouse" })
    }
}

# 4. Get existing notebooks for update detection
Write-Host "[4/5] Checking existing notebooks..."
$existingItems = (Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$wid/items?type=Notebook" `
    -Headers @{ Authorization = "Bearer $script:token" }).value

# 5. Upload each notebook
Write-Host "[5/5] Uploading notebooks..."
foreach ($nbFile in $NotebookFiles) {
    $fullPath = Join-Path $PSScriptRoot $nbFile
    if (-not (Test-Path $fullPath)) {
        Write-Warning "  Skipping $nbFile -- file not found"
        continue
    }

    $displayName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
    Write-Host "`n  Processing: $displayName"

    # Read and parse the notebook
    $nbJson = Get-Content -Raw -Encoding UTF8 $fullPath
    $nbObj  = $nbJson | ConvertFrom-Json

    # Inject Lakehouse metadata
    # Preserve existing language_info if present
    $langInfo = $nbObj.metadata.language_info
    $newMeta = $lakehouseMeta | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    if ($langInfo) {
        $newMeta | Add-Member -NotePropertyName 'language_info' -NotePropertyValue $langInfo -Force
    }
    # Replace metadata on the notebook object
    $nbObj.PSObject.Properties.Remove('metadata')
    $nbObj | Add-Member -NotePropertyName 'metadata' -NotePropertyValue $newMeta -Force

    # Serialize back to JSON and base64
    $updatedJson = $nbObj | ConvertTo-Json -Depth 100
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($updatedJson))
    $defParts = @(@{ path = 'artifact.content.ipynb'; payload = $b64; payloadType = 'InlineBase64' })

    $existing = $existingItems | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1

    # Refresh token for each upload in case of long runs
    $script:token = Get-FabricToken

    if ($existing) {
        # Update existing
        $nid = $existing.id
        $body = @{ definition = @{ format = 'ipynb'; parts = $defParts } } | ConvertTo-Json -Depth 20
        $resp = Invoke-Fabric -Method Post `
            -Uri "https://api.fabric.microsoft.com/v1/workspaces/$wid/items/$nid/updateDefinition" `
            -Body $body
        if ([int]$resp.StatusCode -eq 202) {
            Wait-FabricOp -OperationId $resp.Headers['x-ms-operation-id'] -Label "Update $displayName" | Out-Null
        }
        Write-Host "    Updated ($nid)" -ForegroundColor Green
    } else {
        # Create new
        $createBody = @{
            displayName = $displayName
            description = "Uploaded from repo"
            definition  = @{ format = 'ipynb'; parts = $defParts }
        }
        if ($folderId) { $createBody.folderId = $folderId }
        $body = $createBody | ConvertTo-Json -Depth 20
        $resp = Invoke-Fabric -Method Post `
            -Uri "https://api.fabric.microsoft.com/v1/workspaces/$wid/notebooks" `
            -Body $body
        if ([int]$resp.StatusCode -eq 201) {
            $created = $resp.Content | ConvertFrom-Json
            Write-Host "    Created ($($created.id))" -ForegroundColor Green
        } elseif ([int]$resp.StatusCode -eq 202) {
            $opId = $resp.Headers['x-ms-operation-id']
            Wait-FabricOp -OperationId $opId -Label "Create $displayName" | Out-Null
            Write-Host "    Created (provisioning completed)" -ForegroundColor Green
        }
    }
}

Write-Host "`n=== All notebooks uploaded with Lakehouse '$LakehouseName' pre-attached ===" -ForegroundColor Cyan

# ── Upload dashboard assets and supporting files to Lakehouse Files ──────────
Write-Host "`n=== Uploading assets to Lakehouse Files ===" -ForegroundColor Cyan

# Get a storage-scoped token for OneLake
$storageToken = (az account get-access-token --resource https://storage.azure.com -o json | ConvertFrom-Json).accessToken
if (-not $storageToken) { throw "Failed to acquire OneLake storage token." }
$onelakeBase = "https://onelake.dfs.fabric.microsoft.com/$wid/$lhId"

function Upload-OneLakeFile {
    param([string]$LocalPath, [string]$RemotePath)

    $fileBytes = [System.IO.File]::ReadAllBytes($LocalPath)
    $uri = "$onelakeBase/$RemotePath"

    # Create file
    $createUri = "${uri}?resource=file"
    $hdrs = @{ Authorization = "Bearer $storageToken"; 'Content-Length' = '0' }
    try {
        Invoke-WebRequest -Method Put -Uri $createUri -Headers $hdrs -UseBasicParsing | Out-Null
    } catch {
        # 409 is OK — file already exists, we'll overwrite with append+flush
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -ne 409) { throw }
    }

    # Append data
    $appendUri = "${uri}?action=append&position=0"
    $hdrs = @{
        Authorization    = "Bearer $storageToken"
        'Content-Length' = $fileBytes.Length.ToString()
        'Content-Type'   = 'application/octet-stream'
    }
    Invoke-WebRequest -Method Patch -Uri $appendUri -Headers $hdrs -Body $fileBytes -UseBasicParsing | Out-Null

    # Flush (commit)
    $flushUri = "${uri}?action=flush&position=$($fileBytes.Length)"
    $hdrs = @{ Authorization = "Bearer $storageToken"; 'Content-Length' = '0' }
    Invoke-WebRequest -Method Patch -Uri $flushUri -Headers $hdrs -UseBasicParsing | Out-Null

    $sizeKB = [math]::Round($fileBytes.Length / 1024, 1)
    Write-Host "    $RemotePath (${sizeKB} KB)" -ForegroundColor Green
}

# Files to upload to Lakehouse Files/
$assetsToUpload = @(
    # dashboard folder
    @{ Local = "dashboard\AzureBillingDashboard.SemanticModel\model.bim";       Remote = "Files/dashboard/AzureBillingDashboard.SemanticModel/model.bim" }
    @{ Local = "dashboard\AzureBillingDashboard.SemanticModel\definition.pbism"; Remote = "Files/dashboard/AzureBillingDashboard.SemanticModel/definition.pbism" }
    @{ Local = "dashboard\AzureBillingDashboard.Report\report.json";            Remote = "Files/dashboard/AzureBillingDashboard.Report/report.json" }
    @{ Local = "dashboard\AzureBillingDashboard.Report\definition.pbir";        Remote = "Files/dashboard/AzureBillingDashboard.Report/definition.pbir" }
    # data agent instructions
    @{ Local = "data_agent_instructions.md"; Remote = "Files/data_agent_instructions.md" }
)

foreach ($asset in $assetsToUpload) {
    $localFile = Join-Path $PSScriptRoot $asset.Local
    if (-not (Test-Path $localFile)) {
        Write-Warning "  Skipping $($asset.Local) -- file not found"
        continue
    }
    Upload-OneLakeFile -LocalPath $localFile -RemotePath $asset.Remote
}

Write-Host "`n=== All assets uploaded to Lakehouse Files ===" -ForegroundColor Cyan
