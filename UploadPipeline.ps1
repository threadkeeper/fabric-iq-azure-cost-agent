<#
.SYNOPSIS
    Creates or updates the pipeline-azurecost Data Pipeline in Fabric and
    applies the daily schedule.

.DESCRIPTION
    1. Reads pipeline/pipeline-content.json (template with placeholders).
    2. Resolves the target workspace and notebook IDs.
    3. Patches the template with real IDs.
    4. Creates or updates the pipeline item in Fabric.
    5. Reads pipeline/schedule.json and creates or updates the schedule.

.PARAMETER WorkspaceName
    Fabric workspace name. Default: workspace-public-001

.PARAMETER PipelineName
    Display name for the pipeline. Default: pipeline-azurecost

.PARAMETER FolderName
    Folder inside the workspace to place the pipeline. Default: notebooks

.EXAMPLE
    .\UploadPipeline.ps1
    .\UploadPipeline.ps1 -WorkspaceName "my-workspace"
#>
[CmdletBinding()]
param(
    [string]$WorkspaceName = "workspace-public-001",
    [string]$PipelineName  = "pipeline-azurecost",
    [string]$FolderName    = "notebooks"
)

$ErrorActionPreference = 'Stop'

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
Write-Host "`n=== UploadPipeline.ps1 ===" -ForegroundColor Cyan
Write-Host "Workspace : $WorkspaceName"
Write-Host "Pipeline  : $PipelineName"
Write-Host "Folder    : $FolderName"

$script:token = Get-FabricToken
$apiBase = "https://api.fabric.microsoft.com/v1"

# 1. Resolve workspace
Write-Host "`n[1/6] Resolving workspace..."
$ws = (Invoke-RestMethod -Uri "$apiBase/workspaces" `
    -Headers @{ Authorization = "Bearer $script:token" }).value |
    Where-Object { $_.displayName -eq $WorkspaceName } | Select-Object -First 1
if (-not $ws) { throw "Workspace '$WorkspaceName' not found." }
$wid = $ws.id
Write-Host "  $($ws.displayName) ($wid)"

# 2. Resolve folder
Write-Host "[2/6] Resolving folder..."
$folders = (Invoke-RestMethod -Uri "$apiBase/workspaces/$wid/folders" `
    -Headers @{ Authorization = "Bearer $script:token" }).value
$folder = $folders | Where-Object { $_.displayName -eq $FolderName } |
    Sort-Object @{ Expression = { if ($_.parentFolderId) { 1 } else { 0 } } } |
    Select-Object -First 1
$folderId = if ($folder) { $folder.id } else { $null }
if ($folderId) { Write-Host "  $FolderName ($folderId)" }
else           { Write-Host "  Folder '$FolderName' not found -- using workspace root" }

# 3. Resolve notebook IDs
Write-Host "[3/6] Resolving notebook IDs..."
$notebooks = (Invoke-RestMethod -Uri "$apiBase/workspaces/$wid/items?type=Notebook" `
    -Headers @{ Authorization = "Bearer $script:token" }).value

$notebookMap = @{
    "__NOTEBOOK_01_download_cost_data__"   = "01_download_cost_data"
    "__NOTEBOOK_03_create_cost_ontology__" = "03_create_cost_ontology"
    "__NOTEBOOK_04_create_data_agent__"    = "04_create_data_agent"
}

$resolvedIds = @{}
foreach ($placeholder in $notebookMap.Keys) {
    $nbName = $notebookMap[$placeholder]
    $nb = $notebooks | Where-Object { $_.displayName -eq $nbName } | Select-Object -First 1
    if (-not $nb) { throw "Notebook '$nbName' not found in workspace. Run UploadNotebooks.ps1 first." }
    $resolvedIds[$placeholder] = $nb.id
    Write-Host "  $nbName = $($nb.id)"
}

# 4. Build pipeline definition
Write-Host "[4/6] Building pipeline definition..."

$templatePath = Join-Path $PSScriptRoot "pipeline\pipeline-content.json"
if (-not (Test-Path $templatePath)) { throw "pipeline-content.json not found at $templatePath" }
$pipelineJson = Get-Content -Raw -Encoding UTF8 $templatePath

# Replace placeholders
$pipelineJson = $pipelineJson -replace '__WORKSPACE_ID__', $wid
foreach ($placeholder in $resolvedIds.Keys) {
    $pipelineJson = $pipelineJson -replace [regex]::Escape($placeholder), $resolvedIds[$placeholder]
}

# Verify no placeholders remain
if ($pipelineJson -match '__\w+__') {
    throw "Unresolved placeholders remain in pipeline definition: $($Matches[0])"
}

$pipelineB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pipelineJson))

$defParts = @(
    @{ path = 'pipeline-content.json'; payload = $pipelineB64; payloadType = 'InlineBase64' }
)

# 5. Create or update the pipeline
Write-Host "[5/6] Deploying pipeline..."
$script:token = Get-FabricToken

$existingPipelines = (Invoke-RestMethod -Uri "$apiBase/workspaces/$wid/items?type=DataPipeline" `
    -Headers @{ Authorization = "Bearer $script:token" }).value
$existing = $existingPipelines | Where-Object { $_.displayName -eq $PipelineName } | Select-Object -First 1

if ($existing) {
    $pipeId = $existing.id
    $body = @{ definition = @{ parts = $defParts } } | ConvertTo-Json -Depth 20
    $resp = Invoke-Fabric -Method Post `
        -Uri "$apiBase/workspaces/$wid/items/$pipeId/updateDefinition" `
        -Body $body
    if ([int]$resp.StatusCode -eq 202) {
        Wait-FabricOp -OperationId $resp.Headers['x-ms-operation-id'] -Label "Update pipeline" | Out-Null
    }
    Write-Host "  Updated pipeline '$PipelineName' ($pipeId)" -ForegroundColor Green
} else {
    $createBody = @{
        displayName = $PipelineName
        description = "this pipeline pulls the azure costs, updates the ontology and updates the data agent"
        type        = "DataPipeline"
        definition  = @{ parts = $defParts }
    }
    if ($folderId) { $createBody.folderId = $folderId }
    $body = $createBody | ConvertTo-Json -Depth 20
    $resp = Invoke-Fabric -Method Post `
        -Uri "$apiBase/workspaces/$wid/items" `
        -Body $body
    if ([int]$resp.StatusCode -eq 201) {
        $created = $resp.Content | ConvertFrom-Json
        $pipeId = $created.id
        Write-Host "  Created pipeline '$PipelineName' ($pipeId)" -ForegroundColor Green
    } elseif ([int]$resp.StatusCode -eq 202) {
        $opId = $resp.Headers['x-ms-operation-id']
        Wait-FabricOp -OperationId $opId -Label "Create pipeline" | Out-Null
        # Re-fetch to get the ID
        $existingPipelines = (Invoke-RestMethod -Uri "$apiBase/workspaces/$wid/items?type=DataPipeline" `
            -Headers @{ Authorization = "Bearer $script:token" }).value
        $created = $existingPipelines | Where-Object { $_.displayName -eq $PipelineName } | Select-Object -First 1
        $pipeId = $created.id
        Write-Host "  Created pipeline '$PipelineName' ($pipeId)" -ForegroundColor Green
    }
}

# 6. Apply schedule
Write-Host "[6/6] Applying schedule..."
$schedulePath = Join-Path $PSScriptRoot "pipeline\schedule.json"
if (-not (Test-Path $schedulePath)) {
    Write-Host "  No schedule.json found -- skipping schedule setup" -ForegroundColor Yellow
} else {
    $scheduleBody = Get-Content -Raw -Encoding UTF8 $schedulePath
    $script:token = Get-FabricToken
    $scheduleUri = "$apiBase/workspaces/$wid/items/$pipeId/jobs/Pipeline/schedules"

    # Check for existing schedules
    $hasExisting = $false
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Method GET -Uri $scheduleUri `
            -Headers @{ Authorization = "Bearer $script:token" }
        $schedules = ($resp.Content | ConvertFrom-Json).value
        if ($schedules -and $schedules.Count -gt 0) {
            $hasExisting = $true
            $existingSchedule = $schedules[0]
        }
    } catch {
        # List may fail for data pipelines -- proceed to create
    }

    if ($hasExisting) {
        # Update existing schedule
        $schedId = $existingSchedule.id
        try {
            Invoke-Fabric -Method Patch `
                -Uri "$scheduleUri/$schedId" `
                -Body $scheduleBody | Out-Null
            Write-Host "  Updated schedule ($schedId)" -ForegroundColor Green
        } catch {
            Write-Host "  Could not update existing schedule -- deleting and recreating" -ForegroundColor Yellow
            try { Invoke-Fabric -Method Delete -Uri "$scheduleUri/$schedId" | Out-Null } catch {}
            $hasExisting = $false
        }
    }

    if (-not $hasExisting) {
        # Create new schedule
        try {
            $resp = Invoke-Fabric -Method Post -Uri $scheduleUri -Body $scheduleBody
            if ([int]$resp.StatusCode -eq 201) {
                $newSched = $resp.Content | ConvertFrom-Json
                Write-Host "  Created schedule ($($newSched.id))" -ForegroundColor Green
            } else {
                Write-Host "  Schedule creation returned status $($resp.StatusCode)" -ForegroundColor Yellow
            }
        } catch {
            $errBody = ""
            if ($_.Exception.Response) {
                $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errBody = $sr.ReadToEnd()
            }
            Write-Host "  Schedule API error: $errBody" -ForegroundColor Yellow
            Write-Host "  The pipeline was deployed successfully. You may need to configure the schedule in the Fabric portal." -ForegroundColor Yellow
        }
    }
}

Write-Host "`n=== Pipeline deployment complete ===" -ForegroundColor Cyan
Write-Host "Pipeline: $PipelineName ($pipeId)"
Write-Host "Activities: 01_download_cost_data -> 03_create_cost_ontology -> 04_create_data_agent"
