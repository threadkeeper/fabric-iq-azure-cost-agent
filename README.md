# Azure Cost Management Ontology for Microsoft Fabric

<p align="center">
  <img src="https://img.shields.io/badge/Built%20with-GitHub%20Copilot-8957e5?style=for-the-badge&logo=githubcopilot&logoColor=white" alt="GitHub Copilot" />
  <img src="https://img.shields.io/badge/Powered%20by-Claude%20Opus%204.6-d97706?style=for-the-badge&logo=anthropic&logoColor=white" alt="Claude" />
</p>

Build a Fabric Ontology, Power BI dashboard, and AI Data Agent from Azure cost data — per resource, per day, fully automated.

## What This Does

Three local scripts + five Fabric notebooks handle everything:

| Step | Where | Script / Notebook | What it Does |
|------|-------|-------------------|-------------|
| 1 | Local | `GetKeys.ps1` | Creates SPN, assigns Cost Management Reader, writes `.env`, optionally provisions Key Vault |
| 2 | Local | `SetDashboardConnectionString.ps1` | Injects Lakehouse connection into the local PBI project (for local dev only) |
| 3 | Local | `UploadNotebooks.ps1` | Uploads all notebooks + dashboard assets to Fabric with Lakehouse pre-attached |
| 4 | Fabric | `01_download_cost_data` | Downloads cost CSVs in ≤30-day chunks, writes 6 Delta tables |
| 5 | Fabric | `02_deploy_dashboard` | Patches connection string, deploys Semantic Model + Report, saves IDs to `.env` |
| 6 | Fabric | `03_create_cost_ontology` | Builds ontology + graph DB via Fabric REST API |
| 7 | Fabric | `04_create_data_agent` | Creates/updates Data Agent with ontology + dashboard link |
| — | Fabric | `00_clear_cost_deltafiles` | Drops all tables + staging CSVs (on-demand utility) |

---

## Files

| File | Purpose |
|------|---------|
| [GetKeys.ps1](GetKeys.ps1) | Creates SPN, assigns roles, writes `.env` (optionally provisions Key Vault) |
| [SetDashboardConnectionString.ps1](SetDashboardConnectionString.ps1) | Injects Lakehouse connection into local PBIP (for Power BI Desktop dev) |
| [UploadNotebooks.ps1](UploadNotebooks.ps1) | Uploads notebooks + dashboard files to Fabric Lakehouse with Lakehouse pre-attached |
| [notebooks/](notebooks/) | All Fabric notebooks (00–04) |
| [dashboard/](dashboard/) | Power BI project (PBIP) — source-of-truth dashboard definition |
| [data_agent_instructions.md](data_agent_instructions.md) | AI instructions for the Data Agent |
| [cost-management-ontology.rdf](cost-management-ontology.rdf) | RDF file for Ontology Playground (optional) |

---

## Quick Start

### Prerequisites

#### Software

| Tool | Version | Purpose |
|------|---------|---------|
| **Azure CLI** (`az`) | 2.50+ | Authentication, SPN creation, role assignments, token acquisition |
| **PowerShell** | 5.1+ (ships with Windows) | Running local scripts (`GetKeys`, `UploadNotebooks`, `UploadPipeline`, `SetDashboardConnectionString`) |
| **Power BI Desktop** | Latest (optional) | Local dashboard editing via `.pbip` files (requires Developer Mode enabled in preview features) |

> Install Azure CLI: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

#### Azure / Fabric Resources

| Resource | Notes |
|----------|-------|
| **Azure subscription** | With cost data to analyse |
| **Microsoft Fabric workspace** | On a Fabric capacity (trial or paid) |
| **Lakehouse** in that workspace | Created manually in the portal (one-time) |

#### Azure RBAC / IAM Permissions

The **logged-in user** (the person running `az login`) needs:

| Permission | Scope | Why |
|------------|-------|-----|
| **Cloud Application Administrator** (Entra role) or `Application.ReadWrite.All` | Entra ID tenant | `GetKeys.ps1` creates an App Registration and Service Principal |
| **Owner** or **User Access Administrator** | Azure subscription | `GetKeys.ps1` assigns the *Cost Management Reader* role to the SPN |
| **Contributor** (optional) | Resource group `rg-cost-management-keys` | Only if using `GetKeys.ps1 -KeyVaultName` to create a Key Vault |

The **Service Principal** (`CostManagement-Fabric-SPN`, created by `GetKeys.ps1`):

| Role | Scope | Why |
|------|-------|-----|
| **Cost Management Reader** | Azure subscription | `01_download_cost_data` calls the Cost Details Report API |

#### Fabric Workspace Permissions

| Role | Who | Why |
|------|-----|-----|
| **Contributor** (minimum) | Logged-in user | Upload scripts create/update notebooks, pipelines, semantic models, reports, ontologies, and data agents via the Fabric REST API. OneLake file uploads also require contributor-level access. |
| **Admin** | Logged-in user (optional) | Only needed to create a Workspace Identity for Key Vault integration in scheduled pipelines |

#### Key Vault Permissions (optional — only with `-KeyVaultName`)

| Role | Who | Scope | Why |
|------|-----|-------|-----|
| **Key Vault Secrets User** | Fabric Workspace Identity | Key Vault | Notebooks use `mssparkutils.credentials.getSecret()` at pipeline runtime |

> Create the workspace identity: Workspace Settings → Workspace identity → + Workspace identity. Then assign **Key Vault Secrets User** to it on your vault's IAM page.

#### API Token Resources Used

| Token Resource | Used By |
|----------------|---------|
| `https://api.fabric.microsoft.com` | `UploadNotebooks.ps1`, `UploadPipeline.ps1` (via `az account get-access-token`) |
| `https://storage.azure.com` | `UploadNotebooks.ps1` — OneLake DFS file uploads |
| `https://management.azure.com` | `01_download_cost_data` — Cost Management API (SPN client credentials) |
| `pbi` | `02_deploy_dashboard`, `04_create_data_agent` — notebook runtime identity (`mssparkutils.credentials.getToken`) |

---

### 1. Create Service Principal + `.env` (local)

```powershell
az login
.\GetKeys.ps1
```

This creates `CostManagement-Fabric-SPN`, assigns **Cost Management Reader**, and writes credentials to `.env`.

To store secrets in Key Vault (recommended for shared/pipeline use):

```powershell
.\GetKeys.ps1 -KeyVaultName "kv-costmgmt-yourname"
```

### 2. Configure Lakehouse connection

Edit `.env` and set your Lakehouse details:

```ini
LAKEHOUSE_SQL_ENDPOINT=your-endpoint.datawarehouse.fabric.microsoft.com
LAKEHOUSE_DATABASE=your-lakehouse-name
```

> **Finding your Lakehouse SQL endpoint:** Fabric portal → your workspace → open Lakehouse → Settings → SQL analytics endpoint → copy the **Server** value.

### 3. Upload everything to Fabric (local)

```powershell
.\UploadNotebooks.ps1
```

This single command:
- Uploads all 5 notebooks to the `notebooks` folder in your workspace
- Injects Lakehouse connection metadata so notebooks are ready to run (no manual attachment needed)
- Uploads the `dashboard/` folder and `data_agent_instructions.md` to Lakehouse Files

### 4. Run notebooks in Fabric

Open each notebook in the Fabric portal and click **Run all**, in order:

| Order | Notebook | Time | What Happens |
|-------|----------|------|-------------|
| 1 | `01_download_cost_data` | ~5 min | Downloads cost data, writes 6 Delta tables |
| 2 | `02_deploy_dashboard` | ~1 min | Deploys PBI Semantic Model + Report, saves report ID to `.env` |
| 3 | `03_create_cost_ontology` | ~10 min | Creates ontology + graph database |
| 4 | `04_create_data_agent` | ~1 min | Creates Data Agent with ontology + dashboard link |

### 5. Configure Semantic Model credentials (one-time)

After `02_deploy_dashboard` runs for the first time, the Semantic Model needs an explicit cloud connection before it can refresh data:

1. Open your workspace in the Fabric portal
2. Find **AzureBillingDashboard** (Semantic Model) → click **...** → **Settings**
3. Scroll to **Gateway and cloud connections**
4. Click the dropdown next to the SQL connection → **Create a new connection**
5. Set **Authentication method** to **OAuth2** → click **Sign in** → authenticate with your Entra ID
6. Set **Privacy level** to **Organizational**
7. Click **Apply**
8. Back on the Semantic Model page, click **Refresh now**

This only needs to be done once. Subsequent refreshes (manual, scheduled, or from the pipeline) will reuse the saved connection.

That's it. No other manual portal clicks beyond creating the workspace and Lakehouse.

---

## Scheduling (optional)

Create a pipeline that runs the notebooks sequentially on a schedule:

1. In your workspace → **+ New item** → **Data pipeline** → name it `CostManagement-Refresh`
2. Add 4 **Notebook** activities in sequence: `01` → `02` → `03` → `04`
3. Connect them with success arrows (green ✓)
4. Click **Schedule** → Every `6` Hours → **Apply**

> **Key Vault setup for pipelines:** Create a workspace identity (Workspace Settings → Workspace identity), then grant it **Key Vault Secrets User** on your vault. Notebooks auto-detect Key Vault via `KEY_VAULT_URL` in `.env`.

---

## Local Power BI Development (optional)

To edit the dashboard locally in Power BI Desktop:

```powershell
.\SetDashboardConnectionString.ps1
```

Then open `dashboard/AzureBillingDashboard.pbip` in Power BI Desktop (requires Developer Mode enabled in preview features).

---

## Ontology Design

```
Subscription ──has_resource_group──▶ ResourceGroup
ResourceGroup ──contains_resource──▶ Resource
Resource ──incurs_cost──▶ CostRecord
CostRecord ──billed_under──▶ MeterCategory
CostRecord ──consumed_by──▶ Service
Subscription ──billed_by──▶ CostRecord
```

### Entity Types

| Entity | Table | Key | Description |
|--------|-------|-----|-------------|
| Subscription | `subscription` | subscriptionId | Azure subscription (billing root) |
| ResourceGroup | `resource_group` | resourceGroupId | Logical container for resources |
| Resource | `resource` | resourceId | Individual Azure resource (VM, storage, etc.) |
| CostRecord | `cost_record` | costRecordId | Daily cost per resource (fact table) |
| MeterCategory | `meter_category` | meterId | Billing meter: category → subcategory → name |
| Service | `service` | serviceId | Consumed Azure service + charge type |

### Relationships

| Relationship | Source → Target | Meaning |
|-------------|----------------|---------|
| `has_resource_group` | Subscription → ResourceGroup | Subscription owns resource groups |
| `contains_resource` | ResourceGroup → Resource | Resource group contains resources |
| `incurs_cost` | Resource → CostRecord | Resource generates cost records |
| `billed_under` | CostRecord → MeterCategory | Cost classified under a billing meter |
| `consumed_by` | CostRecord → Service | Cost emitted by an Azure service |
| `billed_by` | Subscription → CostRecord | Direct link for subscription-level aggregation |

---

## Sample Graph Queries

**Total cost by resource group:**
```gql
GRAPH CostManagementOntology
MATCH (s:Subscription)-[:has_resource_group]->(rg:ResourceGroup)
      -[:contains_resource]->(r:Resource)
      -[:incurs_cost]->(c:CostRecord)
RETURN rg.resourceGroupName, SUM(c.preTaxCost) AS totalCost
ORDER BY totalCost DESC
```

**Top 10 most expensive resources:**
```gql
GRAPH CostManagementOntology
MATCH (r:Resource)-[:incurs_cost]->(c:CostRecord)
RETURN r.resourceId, r.resourceType, SUM(c.preTaxCost) AS totalCost
ORDER BY totalCost DESC
LIMIT 10
```

**Cost by meter category:**
```gql
GRAPH CostManagementOntology
MATCH (c:CostRecord)-[:billed_under]->(m:MeterCategory)
RETURN m.meterCategory, SUM(c.preTaxCost) AS totalCost
ORDER BY totalCost DESC
```

**Daily spend trend:**
```gql
GRAPH CostManagementOntology
MATCH (s:Subscription)-[:billed_by]->(c:CostRecord)
RETURN c.usageDate AS date, SUM(c.preTaxCost) AS dailyCost, c.Currency
ORDER BY date ASC
```

---

## Architecture

```
┌──────────────────────────────────────────────────┐
│  Local Machine                                   │
│  az login → GetKeys.ps1 → .env                   │
│  UploadNotebooks.ps1 → notebooks + assets        │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  01_download_cost_data (Fabric)                  │
│  Cost Details API → CSV → 6 Delta tables         │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  02_deploy_dashboard (Fabric)                    │
│  Patch connection → Semantic Model + Report      │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  03_create_cost_ontology (Fabric)                │
│  Tables → Ontology REST API → Graph DB           │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  04_create_data_agent (Fabric)                   │
│  Ontology + Dashboard link → Data Agent          │
└──────────────────────────────────────────────────┘
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| 429 Too Many Requests | Cost API rate limit | Built-in retry handles this automatically |
| Tables not found | Notebook 01 hasn't run | Run `01_download_cost_data` first |
| Ontology not found | Notebook 03 hasn't run | Run `03_create_cost_ontology` first |
| PBI report not rendering | Missing Lakehouse connection | Check `LAKEHOUSE_SQL_ENDPOINT` and `LAKEHOUSE_DATABASE` in `.env` |
| Data Agent missing dashboard link | Notebook 02 hasn't run | Run `02_deploy_dashboard` before `04_create_data_agent` |

---

## Security Notes

- **Without Key Vault**: `.env` contains `AZURE_CLIENT_SECRET` in plain text on Lakehouse Files. Acceptable for local dev, not recommended for shared workspaces.
- **With Key Vault**: Notebooks auto-detect `KEY_VAULT_URL` in `.env` and pull secrets via `mssparkutils.credentials.getSecret()`. The secret never leaves the vault.
- No secrets are stored in notebooks or committed to the repo.
# Azure Cost Management Ontology for Microsoft Fabric

Build a Fabric Ontology and graph database from Azure cost data — per resource, per day, automated end to end.

## What This Does

1. **`GetKeys.ps1`** -- Creates a Service Principal, populates `.env`, optionally provisions Azure Key Vault
2. **`01_download_cost_data.ipynb`** -- Downloads cost data at **per-resource per-day** granularity and writes Lakehouse tables
3. **`03_create_cost_ontology.ipynb`** -- Creates the Ontology and graph database via the Fabric REST API

No pipelines to configure. No portal clicking beyond creating a workspace and Lakehouse.

---

## Files

| File | What it Does |
|------|-------------|
| [GetKeys.ps1](GetKeys.ps1) | Creates SPN, assigns Cost Management Reader, writes `.env` (optionally provisions Key Vault) |
| [SetDashboardConnectionString.ps1](SetDashboardConnectionString.ps1) | Injects Lakehouse connection into PBI project from `.env` |
| [notebooks/01_download_cost_data.ipynb](notebooks/01_download_cost_data.ipynb) | Downloads cost CSVs in ≤30-day chunks, writes 6 Delta tables |
| [notebooks/03_create_cost_ontology.ipynb](notebooks/03_create_cost_ontology.ipynb) | Builds ontology from tables via REST API |
| [cost-management-ontology.rdf](cost-management-ontology.rdf) | RDF file for Ontology Playground (optional) |
| [dashboard/](dashboard/) | Power BI project (PBIP) — source-of-truth dashboard |
| [.env](.env) | Credentials + config (gitignored). Secrets are optional here when using Key Vault |

---

## Quick Start

### 1. Create the Service Principal (local machine)

```powershell
az login
.\GetKeys.ps1
```

This creates `CostManagement-Fabric-SPN`, assigns **Cost Management Reader**, and writes all credentials to `.env`.

#### (Recommended) Store secrets in Azure Key Vault for pipeline use

```powershell
.\GetKeys.ps1 -KeyVaultName "kv-costmgmt-yourname"
```

This additionally creates a Key Vault, stores the SPN secrets, and sets `KEY_VAULT_URL` in `.env`. Notebooks auto-detect Key Vault and pull secrets via `mssparkutils.credentials.getSecret()` at runtime — no plain-text secrets on the Lakehouse.

> **Security:** Without Key Vault, the `.env` file contains `AZURE_CLIENT_SECRET` in plain text on Lakehouse Files. This is acceptable for local dev but **not recommended for shared workspaces or automated pipelines**. With Key Vault, the secret never leaves the vault.

### 2. Set Up Fabric (portal — one-time)

1. Open [Microsoft Fabric](https://app.fabric.microsoft.com)
2. **Create a workspace**: Workspaces → + New workspace → name it (e.g. `CostManagement-Demo`) → select a capacity → Apply
3. **Create a Lakehouse**: + New item → Lakehouse → name it `CostManagementLakehouse` → Create
4. **Upload `.env`**: In the Lakehouse, click Files → Upload → select your `.env` file
5. **Upload notebooks**: Workspaces → your workspace → + New item → Import notebook → upload both notebooks from `notebooks/`

### 3. Run Notebook 1 — Download Cost Data

1. Open `01_download_cost_data` in Fabric
2. Attach the Lakehouse: left pane → Lakehouses → Add → select `CostManagementLakehouse`
3. Click **Save** — this persists the Lakehouse attachment so pipeline runs and future opens use it automatically
4. Click **Run all**
5. Wait for the cost report to generate (~5 min), download, and write tables
6. Verify tables appear in the Lakehouse: `subscription`, `resource_group`, `resource`, `meter_category`, `service`, `cost_record`

**Incremental refresh:** The notebook fetches the last N days (set by `COST_LOOKBACK_DAYS` in `.env`, default 7). Existing data outside that window is preserved. On subsequent runs, only the fetched date range is replaced — dimension tables merge new rows without losing existing ones.

### 4. Run Notebook 2 — Create the Ontology

1. Open `03_create_cost_ontology` in Fabric
2. Attach the same Lakehouse
3. Click **Save** — same as above, persists the attachment for pipeline runs
4. Click **Run all**
5. The notebook detects which tables/columns exist, builds the ontology definition, and POSTs it to the Fabric API
6. Wait for graph DB creation (~10-15 min)
7. The ontology appears in your workspace

### 5. Query the Graph

Open the ontology in the Fabric portal → graph query editor:

```gql
GRAPH CostManagementOntology
MATCH (s:Subscription)-[:has_resource_group]->(rg:ResourceGroup)
      -[:contains_resource]->(r:Resource)
      -[:incurs_cost]->(c:CostRecord)
RETURN rg.resourceGroupName, SUM(c.preTaxCost) AS totalCost
ORDER BY totalCost DESC
```

### 6. Schedule Automatic Refresh (every 6 hours)

Create a pipeline that runs both notebooks sequentially on a schedule.

> **Authentication in pipelines:** If you ran `GetKeys.ps1 -KeyVaultName`, notebooks automatically pull secrets from Key Vault via `mssparkutils.credentials.getSecret()`. No plain-text secrets needed on the Lakehouse. If you didn't set up Key Vault, notebooks fall back to reading `AZURE_CLIENT_SECRET` from the `.env` file in Lakehouse Files.
>
> **Notebook 2 does not need SPN credentials** -- it uses `mssparkutils.credentials.getToken()` for the Fabric API and `sempy.fabric` for workspace/lakehouse resolution.

**Key Vault pipeline prerequisites:**
1. **Create a workspace identity** (one-time): Workspace Settings → **Workspace identity** tab → **+ Workspace identity**. This creates a managed service principal for your workspace ([docs](https://learn.microsoft.com/en-us/fabric/security/workspace-identity))
2. **Grant Key Vault access**: Azure Portal → your Key Vault → **Access control (IAM)** → Add role assignment → **Key Vault Secrets User** → search for your workspace name (it appears as the workspace identity service principal) → Assign
3. If the Key Vault has public network access disabled, create a **managed private endpoint** from your Fabric workspace to the vault (Workspace Settings → Network Security → Managed private endpoints), then approve it on the Key Vault side
4. Upload `.env` to Lakehouse Files (contains `KEY_VAULT_URL` and non-secret config)

**Create the pipeline:**

1. In your workspace → **+ New item** → **Data pipeline** → name it `CostOntology-Refresh`
2. From the **Activities** pane, drag a **Notebook** activity onto the canvas
3. In the **Settings** tab:
   - **Notebook**: select `01_download_cost_data`
4. Drag a second **Notebook** activity onto the canvas
5. In its **Settings** tab:
   - **Notebook**: select `03_create_cost_ontology`
6. **Connect them**: drag the green ✓ arrow from the first activity to the second (this ensures notebook 2 only runs after notebook 1 succeeds)
7. Click **Save**
8. Click **Schedule** (top toolbar):
   - Toggle **Scheduled run** to **On**
   - **Schedule type**: select **Interval based**
   - **Repeat**: Every `6` **Hours**
   - **Max concurrent runs**: `1` (prevents overlapping runs if a previous run is still in progress)
   - **Start date / End date**: set as needed (or leave open-ended)
9. Click **Apply**

The pipeline will now run every 6 hours:
- Notebook 1 downloads fresh cost data and overwrites the Lakehouse tables
- Notebook 2 updates the existing ontology definition in-place (preserving the ontology ID so Data Agent references remain valid)

---

## Ontology Design

```
Subscription ──has_resource_group──▶ ResourceGroup
ResourceGroup ──contains_resource──▶ Resource
Resource ──incurs_cost──▶ CostRecord
CostRecord ──billed_under──▶ MeterCategory
CostRecord ──consumed_by──▶ Service
Subscription ──billed_by──▶ CostRecord
```

### Entity Types

| Entity | Table | Key | Description |
|--------|-------|-----|-------------|
| Subscription | `subscription` | subscriptionId | Azure subscription (billing root) |
| ResourceGroup | `resource_group` | resourceGroupId | Logical container for resources |
| Resource | `resource` | resourceId | Individual Azure resource (VM, storage, etc.) |
| CostRecord | `cost_record` | costRecordId | Daily cost per resource (fact table) |
| MeterCategory | `meter_category` | meterId | Billing meter: category → subcategory → name |
| Service | `service` | serviceId | Consumed Azure service + charge type |

### Relationships

| Relationship | Source → Target | Meaning |
|-------------|----------------|---------|
| `has_resource_group` | Subscription → ResourceGroup | Subscription owns resource groups |
| `contains_resource` | ResourceGroup → Resource | Resource group contains resources |
| `incurs_cost` | Resource → CostRecord | Resource generates cost records |
| `billed_under` | CostRecord → MeterCategory | Cost classified under a billing meter |
| `consumed_by` | CostRecord → Service | Cost emitted by an Azure service |
| `billed_by` | Subscription → CostRecord | Direct link for subscription-level aggregation |

### Field Reference

| Field | Meaning |
|-------|---------|
| `subscriptionId` | Azure subscription GUID |
| `subscriptionName` | Subscription display name |
| `resourceGroupId` | Composite key: subscriptionId/resourceGroupName |
| `resourceId` | Full ARM resource path |
| `resourceType` | Provider type (e.g. `Microsoft.Compute/virtualMachines`) |
| `location` | Azure region (e.g. `eastus`) |
| `meterCategory` | Top-level billing class (e.g. `Virtual Machines`) |
| `meterSubCategory` | Sub-class (e.g. `D-Series`) |
| `meterName` | Specific meter (e.g. `D4s v3`) |
| `preTaxCost` | Cost before tax/credits |
| `quantity` | Units consumed |
| `chargeType` | Usage, Purchase, or Refund |
| `serviceName` | Azure service that emitted usage (e.g. `Microsoft.Compute`) |

---

## Sample Graph Queries

**Daily cost per resource (primary view):**
```gql
GRAPH CostManagementOntology
MATCH (r:Resource)-[:incurs_cost]->(c:CostRecord)
RETURN r.resourceId, r.resourceType, c.usageDate,
       SUM(c.preTaxCost) AS dailyCost, c.Currency
ORDER BY c.usageDate DESC, dailyCost DESC
```

**Cost by meter category:**
```gql
GRAPH CostManagementOntology
MATCH (c:CostRecord)-[:billed_under]->(m:MeterCategory)
RETURN m.meterCategory, SUM(c.preTaxCost) AS totalCost
ORDER BY totalCost DESC
```

**Full traversal — Subscription → RG → Resource → Daily Cost → Meter:**
```gql
GRAPH CostManagementOntology
MATCH (s:Subscription)-[:has_resource_group]->(rg:ResourceGroup)
      -[:contains_resource]->(r:Resource)
      -[:incurs_cost]->(c:CostRecord)
      -[:billed_under]->(m:MeterCategory)
RETURN s.subscriptionName, rg.resourceGroupName, r.resourceId,
       c.usageDate, m.meterCategory, SUM(c.preTaxCost) AS dailyCost
ORDER BY c.usageDate DESC, dailyCost DESC
```

**Top 10 most expensive resources (total):**
```gql
GRAPH CostManagementOntology
MATCH (r:Resource)-[:incurs_cost]->(c:CostRecord)
RETURN r.resourceId, r.resourceType, SUM(c.preTaxCost) AS totalCost
ORDER BY totalCost DESC
LIMIT 10
```

**Daily spend trend per resource group:**
```gql
GRAPH CostManagementOntology
MATCH (rg:ResourceGroup)-[:contains_resource]->(r:Resource)
      -[:incurs_cost]->(c:CostRecord)
RETURN rg.resourceGroupName, c.usageDate,
       SUM(c.preTaxCost) AS dailyCost, c.Currency
ORDER BY rg.resourceGroupName, c.usageDate
```

**Cost by service and charge type:**
```gql
GRAPH CostManagementOntology
MATCH (c:CostRecord)-[:consumed_by]->(svc:Service)
RETURN svc.serviceName, svc.chargeType, SUM(c.preTaxCost) AS totalCost
ORDER BY totalCost DESC
```

---

## Optional: Create a Data Agent

1. In your workspace → + New item → **Data Agent**
2. Add the **CostManagementOntology** as a data source
3. Paste these AI instructions:

> *You are a cost analysis assistant. Translate natural-language questions about Azure spending into GQL queries against the CostManagementOntology graph. The graph has 6 entity types: Subscription, ResourceGroup, Resource, CostRecord, MeterCategory, Service. Connected by: has_resource_group, contains_resource, incurs_cost, billed_under, consumed_by, billed_by. Aggregate costs with SUM(c.preTaxCost). When users say "service" they mean MeterCategory.*

**Important disclaimers for any reports or agents built on this data:**

> AI-generated results can contain errors. Cost figures are derived from automated API queries and may not reflect final invoiced amounts.

> Please validate all agent responses against the Azure billing portal or Power BI report.

---

## 7. Power BI Dashboard — Source of Truth

The `dashboard/` folder contains a Power BI Project (PBIP) that creates a daily cost breakdown dashboard matching the Azure Cost Management portal view. Use this dashboard to **verify any claims** made by the Data Agent.

### Dashboard Features

| Visual | Description |
|--------|-------------|
| **Stacked Column Chart** | Daily (or monthly) cost breakdown, stacked by resource / resource group / meter category / service |
| **Actual Cost Card** | KPI card showing total pre-tax cost for the filtered period |
| **Subscription Slicer** | Filter by Azure subscription |
| **Date Period Slicer** | Select a date range (between filter) |
| **Group By Slicer** | Dynamically switch the chart legend: Resource, Resource Group, Meter Category, or Service |
| **Granularity Slicer** | Switch the X-axis between Daily and Monthly |

### Data Model

The semantic model connects directly to the 6 Lakehouse tables via the SQL analytics endpoint:

```
subscription ──1:M──▶ resource_group ──1:M──▶ resource ──1:M──▶ cost_record
                                                            ◀──M:1── meter_category
                                                            ◀──M:1── service
```

**Field Parameters** (`Group By`, `Granularity`) allow dynamic axis/legend switching without DAX gymnastics.

### Option A — Open in Power BI Desktop (recommended)

1. **Enable Developer Mode** in Power BI Desktop:
   - File → Options and Settings → Options → Preview features → ✅ **Power BI Project (.pbip) save format**
   - Restart Power BI Desktop
2. **Configure connection** (one-time):
   ```powershell
   .\SetDashboardConnectionString.ps1
   ```
   This reads `LAKEHOUSE_SQL_ENDPOINT` and `LAKEHOUSE_DATABASE` from `.env` (prompts if missing) and writes them into the semantic model.
3. **Open the project**: File → Open report → Browse → navigate to `dashboard/AzureBillingDashboard.pbip`
4. **Sign in**: When prompted, choose **Microsoft account** and sign in with your Entra ID — credentials are cached for future opens
5. **Apply changes** → Power BI will connect and load the tables
5. **Build/adjust visuals** (if needed):
   - The report definition pre-configures the chart layout. If visuals don't render automatically:
     - Add a **Stacked Column Chart**: X-axis = `Granularity` field parameter, Y-axis = `Total Cost` measure, Legend = `Group By` field parameter
     - Add a **Card** visual: Value = `Total Cost` measure
     - Add **Slicers** for `subscription[subscriptionName]`, `cost_record[usageDate]` (Between mode), `Group By[Group By Fields]`, `Granularity[Granularity Fields]`
6. **Save as .pbix**: File → Save as → choose `.pbix` format
7. **Publish to Fabric**: Home → Publish → select your Fabric workspace

### Option B — Fabric Git Integration

1. Connect your Fabric workspace to this Git repo (Workspace settings → Git integration)
2. The `dashboard/` folder structure is PBIP-compatible — Fabric will automatically create the semantic model and report
3. Update the connection parameters in the Fabric semantic model settings to point to your Lakehouse

### Finding Your Lakehouse SQL Endpoint

1. Open [Microsoft Fabric](https://app.fabric.microsoft.com)
2. Navigate to your workspace → open **CostManagementLakehouse**
3. Click the **Settings** gear icon (or `...` → Settings)
4. Under **SQL analytics endpoint**, copy the **Server** value
   - It looks like: `xxxxxx.datawarehouse.fabric.microsoft.com`
5. The **Database** name is your Lakehouse name: `CostManagementLakehouse`

### Verifying Data Agent Claims

When the Data Agent returns cost figures, cross-reference against this dashboard:

1. Apply the same filters (subscription, date range) in the dashboard
2. Compare the **Actual Cost** KPI card with the agent's total
3. Use the **Group By** slicer to drill into the same dimension the agent queried
4. If figures differ significantly, the agent's GQL query may be aggregating incorrectly — check the query logic

---

## How It Works

```
┌──────────────────────────────────────────────────┐
│  GetKeys.ps1 (local)                             │
│  az login → create SPN → assign role → .env      │
│  (optional) → create Key Vault → store secrets   │
└────────────────────┬─────────────────────────────┘
                     │ upload .env + notebooks
                     ▼
┌──────────────────────────────────────────────────┐
│  01_download_cost_data.ipynb (Fabric)            │
│  Auth (Key Vault or .env) → Cost Details API →   │
│  CSV → 6 Delta tables                            │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  03_create_cost_ontology.ipynb (Fabric)          │
│  Auth: Fabric workspace identity (no SPN)        │
│  Detect tables → Build entities/bindings →       │
│  POST to Ontology REST API → Graph DB            │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  Graph Queries / Data Agent                      │
│  GQL in Fabric graph editor or via Data Agent    │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  Power BI Dashboard (dashboard/)                 │
│  Source-of-truth report for verifying agent      │
│  claims. PBIP project → open in PBI Desktop →    │
│  publish to Fabric workspace                     │
└──────────────────────────────────────────────────┘
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| 429 Too Many Requests | Query API rate limit | Use the Cost Details Report API (notebook already does this) |
| 400 Bad Request | `TheLastMonth` not supported on MCA | Use `MonthToDate` or `Custom` with explicit dates |
| 401 Unauthorized on token endpoint | SPN client secret expired or rotated | Re-run `GetKeys.ps1` (resets secret), re-upload `.env`. With Key Vault: `GetKeys.ps1 -KeyVaultName` updates both |
| Schema mismatch on table write | Table schema changed between runs | Already handled -- notebooks use `overwriteSchema=true` |
| `TABLE_OR_VIEW_NOT_FOUND` | Dimension table missing (CSV lacked columns) | Notebook skips missing tables gracefully |
| `AMBIGUOUS_REFERENCE` | Duplicate column names after join | Already handled -- lookup columns use `_` prefix aliases |
| Duplicate key in PBI relationship | Mixed-case GUIDs in dimension tables | Already handled -- M queries lowercase all key columns and group by primary key |
| `resourceType` column missing | CSV doesn't have ResourceType (MCA accounts) | Already handled -- extracted from ARM resourceId path via regex |
| Ontology `ALMOperationImportFailed` | sourceKeyRef must be entity's primary key | Already fixed -- uses entity `entityIdParts` for key refs |
| Spark 430 capacity error | Fabric capacity exhausted | Stop sessions in Monitoring hub, wait, or upgrade capacity |
| Key Vault access denied in pipeline | Workspace identity lacks vault permissions | Add **Key Vault Secrets User** role on the vault for the workspace identity (Azure Portal → Key Vault → Access control → Add role assignment) |
| Key Vault 403 Forbidden / `ForbiddenByConnection` | Key Vault has public access disabled | Create a managed private endpoint from the Fabric workspace to the vault (Workspace Settings → Network Security), then approve it on the Key Vault side |

---

## References

- [Generate Cost Details Report API](https://learn.microsoft.com/en-us/rest/api/cost-management/generate-cost-details-report)
- [Cost Details Field Reference](https://learn.microsoft.com/en-us/azure/cost-management-billing/automate/understand-usage-details-fields)
- [Create Ontology REST API](https://learn.microsoft.com/en-us/rest/api/fabric/ontology/items/create-ontology)
- [Fabric GQL Language Guide](https://learn.microsoft.com/en-us/fabric/graph/gql-language-guide)
- [Query Fabric Graph Database](https://learn.microsoft.com/en-us/fabric/graph/tutorial-query-code-editor)
- [Ontology Playground](https://microsoft.github.io/Ontology-Playground/)
- [build-fabric-ontology-demo (Healthcare example)](https://github.com/microsoft/build-fabric-ontology-demo)
- [Azure Key Vault + Fabric mssparkutils](https://learn.microsoft.com/en-us/fabric/data-engineering/microsoft-spark-utilities#credentials-utilities)
