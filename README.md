# Azure Cost Management Ontology for Microsoft Fabric

Build a Fabric Ontology and graph database from Azure cost data — per resource, per day, automated end to end.

## What This Does

1. **`GetKeys.ps1`** — Creates a Service Principal and populates `.env` (one command)
2. **`01_download_cost_data.ipynb`** — Downloads cost data at **per-resource per-day** granularity and writes Lakehouse tables
3. **`02_create_cost_ontology.ipynb`** — Creates the Ontology and graph database via the Fabric REST API

No pipelines to configure. No portal clicking beyond creating a workspace and Lakehouse.

---

## Files

| File | What it Does |
|------|-------------|
| [GetKeys.ps1](GetKeys.ps1) | Creates SPN, assigns Cost Management Reader, writes `.env` |
| [notebooks/01_download_cost_data.ipynb](notebooks/01_download_cost_data.ipynb) | Downloads MTD cost CSV, writes 6 Delta tables |
| [notebooks/02_create_cost_ontology.ipynb](notebooks/02_create_cost_ontology.ipynb) | Builds ontology from tables via REST API |
| [cost-management-ontology.rdf](cost-management-ontology.rdf) | RDF file for Ontology Playground (optional) |
| [dashboard/](dashboard/) | Power BI project (PBIP) — source-of-truth dashboard |
| [.env](.env) | Credentials (gitignored) |

---

## Quick Start

### 1. Create the Service Principal (local machine)

```powershell
az login
.\GetKeys.ps1
```

This creates `CostManagement-Fabric-SPN`, assigns **Cost Management Reader**, and writes all credentials to `.env`.

### 2. Set Up Fabric (portal — one-time)

1. Open [Microsoft Fabric](https://app.fabric.microsoft.com)
2. **Create a workspace**: Workspaces → + New workspace → name it (e.g. `CostManagement-Demo`) → select a capacity → Apply
3. **Create a Lakehouse**: + New item → Lakehouse → name it `CostManagementLakehouse` → Create
4. **Upload `.env`**: In the Lakehouse, click Files → Upload → select your `.env` file
5. **Upload notebooks**: Workspaces → your workspace → + New item → Import notebook → upload both notebooks from `notebooks/`

### 3. Run Notebook 1 — Download Cost Data

1. Open `01_download_cost_data` in Fabric
2. Attach the Lakehouse: left pane → Lakehouses → Add → select `CostManagementLakehouse`
3. Click **Run all**
4. Wait for the cost report to generate (~5 min), download, and write tables
5. Verify tables appear in the Lakehouse: `subscription`, `resource_group`, `resource`, `meter_category`, `service`, `cost_record`

### 4. Run Notebook 2 — Create the Ontology

1. Open `02_create_cost_ontology` in Fabric
2. Attach the same Lakehouse
3. Click **Run all**
4. The notebook detects which tables/columns exist, builds the ontology definition, and POSTs it to the Fabric API
5. Wait for graph DB creation (~10-15 min)
6. The ontology appears in your workspace

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

1. In your workspace → **+ New item** → **Data pipeline** → name it `CostOntology-Refresh`
2. From the **Activities** pane, drag a **Notebook** activity onto the canvas
3. In the **Settings** tab:
   - **Notebook**: select `01_download_cost_data`
   - **Lakehouse**: select `CostManagementLakehouse`
4. Drag a second **Notebook** activity onto the canvas
5. In its **Settings** tab:
   - **Notebook**: select `02_create_cost_ontology`
   - **Lakehouse**: select `CostManagementLakehouse`
6. **Connect them**: drag the green ✓ arrow from the first activity to the second (this ensures notebook 2 only runs after notebook 1 succeeds)
7. Click **Save**
8. Click **Schedule** (top toolbar):
   - Toggle **Scheduled run** to **On**
   - **Repeat**: Every `6` **Hours**
   - **Start time**: pick a start (e.g. `00:00`)
   - **Time zone**: select your time zone
   - **Start date / End date**: set as needed (or leave open-ended)
9. Click **Apply**

The pipeline will now run every 6 hours:
- Notebook 1 downloads fresh cost data and overwrites the Lakehouse tables
- Notebook 2 deletes the existing ontology and recreates it with the latest data

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
2. **Open the project**: File → Open report → Browse → navigate to `dashboard/AzureBillingDashboard.pbip`
3. **Set connection parameters**:
   - In the model pane (or Home → Transform data → Edit parameters), update:
     - `Lakehouse SQL Endpoint` — your Lakehouse SQL analytics endpoint URL
     - `Lakehouse Database` — your Lakehouse name (e.g. `CostManagementLakehouse`)
   - To find your SQL endpoint: Fabric Portal → Lakehouse → Settings → SQL analytics endpoint → copy the **Server** value
4. **Apply changes** → Power BI will connect and load the tables
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
└────────────────────┬─────────────────────────────┘
                     │ upload .env + notebooks
                     ▼
┌──────────────────────────────────────────────────┐
│  01_download_cost_data.ipynb (Fabric)            │
│  Auth → Cost Details Report API → CSV → 6 tables │
└────────────────────┬─────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────┐
│  02_create_cost_ontology.ipynb (Fabric)          │
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
| Schema mismatch on table write | Table schema changed between runs | Already handled — notebooks use `overwriteSchema=true` |
| `TABLE_OR_VIEW_NOT_FOUND` | Dimension table missing (CSV lacked columns) | Notebook skips missing tables gracefully |
| `AMBIGUOUS_REFERENCE` | Duplicate column names after join | Already handled — lookup columns use `_` prefix aliases |
| Ontology `ALMOperationImportFailed` | sourceKeyRef must be entity's primary key | Already fixed — uses entity `entityIdParts` for key refs |
| Spark 430 capacity error | Fabric capacity exhausted | Stop sessions in Monitoring hub, wait, or upgrade capacity |

---

## References

- [Generate Cost Details Report API](https://learn.microsoft.com/en-us/rest/api/cost-management/generate-cost-details-report)
- [Cost Details Field Reference](https://learn.microsoft.com/en-us/azure/cost-management-billing/automate/understand-usage-details-fields)
- [Create Ontology REST API](https://learn.microsoft.com/en-us/rest/api/fabric/ontology/items/create-ontology)
- [Fabric GQL Language Guide](https://learn.microsoft.com/en-us/fabric/graph/gql-language-guide)
- [Query Fabric Graph Database](https://learn.microsoft.com/en-us/fabric/graph/tutorial-query-code-editor)
- [Ontology Playground](https://microsoft.github.io/Ontology-Playground/)
- [build-fabric-ontology-demo (Healthcare example)](https://github.com/microsoft/build-fabric-ontology-demo)
