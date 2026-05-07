# Designer Notes: Power BI Dashboard vs Azure Cost Dashboard

These notes compare the current Power BI dashboard screenshot (`PowerBICostDashboard.PNG`) with the Azure Cost Management dashboard screenshot (`AzureCostDashboard.png`). The differences are ordered from largest visual/functional impact to smallest.

## 1. Data scope and totals do not match

### Difference
- The Azure Cost dashboard shows **Apr 7-May 6** with **Actual Cost $1,407.21** and **Forecast $1,459.96**.
- The current Power BI dashboard appears to show a shorter range around **Apr 22-May 1** with **Total Cost $922.35** and **Forecast Cost $956.94**.
- This is the largest mismatch because the dashboard will never feel visually equivalent if the date window and totals are different.

### Steps to correct
1. Set the default date filter to the same rolling window as Azure Cost Management: last 30 days, e.g. `Apr 7-May 6` in the screenshot.
2. Verify the model contains all daily cost rows for the full range and not only the most recent downloaded subset.
3. Make the main actual-cost measure use the same grain and filters as Azure:
   - Include all services and resource groups by default.
   - Use `usageDate` as the billing day.
   - Avoid filtering out zero/low-cost services unless Azure also hides them.
4. Update the forecast measure so it follows Azure’s style: actual cost to date plus projected remaining-period spend.
5. Add a QA check: after refresh, compare the Power BI `Total Cost` and `Forecast Cost` cards against Azure Cost Management for the same date range.

## 2. Chart grouping is too granular

### Difference
- Azure groups the stacked columns by **Service name**.
- Power BI currently groups by **resourceName**, creating many tiny segments and a long, cluttered legend.
- This makes the Power BI dashboard look much more technical and less like Azure Cost Management.

### Steps to correct
1. Change the stacked column chart legend field from `resourceName` to `serviceName`.
2. Use service-level categories such as:
   - Microsoft Fabric
   - Azure Bastion
   - Azure DNS
   - SQL Managed Instance
   - Microsoft Purview
   - Azure Database for PostgreSQL
   - Virtual Machines
   - Virtual Network
   - Foundry Tools
   - Others
3. Add an `Others` grouping for small services to reduce visual noise.
4. Keep `resourceName` available as a drill-through or tooltip field, not as the default legend.
5. Rename the chart control/label to match Azure wording: **Group by: Service name**.

## 3. Overall page layout and aspect ratio are not Azure-like

### Difference
- Azure uses a compact, wide layout with controls and KPIs at the top and a relatively short chart area underneath.
- Power BI uses a taller canvas with large whitespace and a very tall chart, so it feels like a generic report page rather than an Azure portal blade.

### Steps to correct
1. Resize the report page to a wide dashboard ratio similar to the Azure screenshot, approximately **16:4** or a custom wide canvas such as **1600 x 370-420 px**.
2. Reduce the top filter area height.
3. Move the KPI cards closer to the top and align them horizontally.
4. Reduce the stacked column chart height so it resembles Azure’s compressed cost chart.
5. Keep most page elements within a single horizontal viewport; avoid requiring vertical scanning.
6. Use minimal margins: Azure has tight spacing between top controls, KPIs, and chart.

## 4. Top control bar does not match Azure Cost Management

### Difference
- Azure has a light grey command/filter strip with a date-range pill and **Add filter** button.
- Power BI currently shows separate slicers for `usageDate`, `subscriptionName`, `serviceName`, and `resourceGroupName` directly on the white canvas.
- The Power BI filters look like report slicers, while Azure’s controls look like portal command controls.

### Steps to correct
1. Add a thin light-grey header band across the top of the report.
2. Replace the two separate date boxes with a single date-range display such as **Apr 7-May 6**.
3. Add a small **Add filter** button visual next to the date range.
4. Move detailed filters into a collapsible filter pane, a bookmark panel, or compact dropdowns below the main header.
5. Keep only Azure-like high-level controls visible by default.
6. Style controls with rounded corners, subtle borders, and small icons to mimic Azure portal buttons.

## 5. KPI card styling and labels differ

### Difference
- Azure KPI labels are compact, uppercase, and placed above the values:
  - **ACTUAL COST (USD)**
  - **FORECAST: CHART VIEW OFF**
  - **BUDGET: NONE**
- Power BI labels are softer and placed below the values:
  - `Total Cost`
  - `Forecast Cost`
  - `Budget Display`
- Azure also shows small info icons and dropdown chevrons beside KPI values.

### Steps to correct
1. Restyle the KPI cards so labels appear above the values.
2. Use uppercase Azure-style labels:
   - `ACTUAL COST (USD)`
   - `FORECAST: CHART VIEW OFF`
   - `BUDGET: NONE`
3. Use a bold, dark, Segoe UI-like font for the values.
4. Make the numbers slightly smaller than the current Power BI card numbers if needed so they sit closer to Azure’s proportions.
5. Add small chevron glyphs next to Actual Cost and Forecast values.
6. Display budget as `--` with a chevron, not as `Budget Display` below the value.

## 6. Chart scale, density, and column spacing are different

### Difference
- Azure shows many narrow daily columns across the full date range, with a y-axis around **$0-$180**.
- Power BI shows fewer, wider daily columns with a y-axis around **$0-$140**.
- Azure’s daily trend feels denser and flatter; Power BI’s bars dominate too much vertical space.

### Steps to correct
1. Ensure the x-axis contains every day in the selected 30-day range.
2. Set the x-axis type to categorical or continuous daily display, whichever gives daily bars without gaps.
3. Reduce column inner padding so more daily bars fit across the width.
4. Set the y-axis maximum to a fixed or dynamically padded value close to Azure’s scale, e.g. max daily spend rounded up to the next `$20` increment.
5. Use lighter horizontal gridlines.
6. Reduce chart title prominence or remove the Power BI-style title so the visual looks closer to Azure.

## 7. Legend placement and color palette differ

### Difference
- Azure places the legend under the chart in two clean rows and uses a recognizable Azure service palette.
- Power BI places a very long legend across the top of the chart, with many truncated resource names and small segments.
- This is mainly caused by resource-level grouping but also by legend layout and colors.

### Steps to correct
1. Move the legend to the bottom of the chart.
2. Use service-level legend values only.
3. Limit visible categories to top services plus `Others`.
4. Assign stable Azure-like colors:
   - Microsoft Fabric: bright cyan/blue
   - Azure Bastion: dark navy
   - Azure DNS: purple
   - SQL Managed Instance: teal/green
   - Microsoft Purview: green
   - Azure Database: lime
   - Virtual Machines: yellow/orange
   - Virtual Network: red/orange
   - Foundry Tools: red
   - Others: grey
5. Keep colors consistent across refreshes by explicitly setting data colors in the report theme or visual formatting.

## 8. Azure portal interaction affordances are missing

### Difference
- Azure includes small controls above the chart:
  - **Group by: Service name**
  - **Granularity: Daily**
  - **Column (stacked)**
  - **Pin to dashboard**
- Power BI currently only has regular slicers and the chart, so it lacks the Azure portal command feel.

### Steps to correct
1. Add a compact control row above the chart, aligned to the right.
2. Create button/dropdown-like visuals for:
   - `Group by: Service name`
   - `Granularity: Daily`
   - `Column (stacked)`
3. Add a small `Pin to dashboard` text/button with an icon for visual similarity, even if it is decorative.
4. Use thin borders and blue focus styling on the active dropdown to mimic Azure.
5. If real interactivity is desired, wire these controls to field parameters for grouping and chart-type selection.

## Recommended implementation order

1. Fix the date scope and total/forecast parity.
2. Change chart grouping from resource to service and add `Others`.
3. Resize the report canvas and compact the layout.
4. Rebuild the top control bar to look like Azure.
5. Restyle KPI cards and labels.
6. Tune chart axis scale, bar density, and gridlines.
7. Move legend to bottom and apply Azure-like colors.
8. Add Azure portal-style chart controls and interaction affordances.
