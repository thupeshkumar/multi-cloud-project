# Estimated Cloud Costs in Grafana

This runs a small open-source Python exporter locally in Docker Desktop. It reads a normalized Infracost estimate, publishes AWS/Azure/GCP gauges to Prometheus and supplies a Grafana dashboard. It has no cloud API credentials and does not change Terraform state or resources.

The report shows priced-resource MONTHLY ESTIMATES in USD, not actual charges. It may omit unsupported resources and usage. Account credits, taxes, discounts and free-tier eligibility can make actual bills differ. Never label these gauges as actual spending.

## 1 Put the files in your project

Extract Cost_Exporter.zip so the folder is:

    ~/multi-cloud-project/monitoring/cost-exporter/

It contains exporter.py, refresh.py, Dockerfile, compose.cost.yml, prometheus-job.yml, alerts-group.yml, Grafana_Estimated_Costs.json and data/. Keep your existing monitoring compose.yml, prometheus.yml, Grafana database and .env.

All commands below run in your LOCAL Linux/WSL terminal. Keep Docker Desktop running in Linux-container mode.

## 2 Check Infracost

```bash
cd ~/multi-cloud-project
infracost version
infracost --help
```

Install the current CLI from https://www.infracost.io/docs/ if absent. Configure it:

```bash
infracost setup
```

The refresh adapter targets the CURRENT documented scan/inspect CLI, not the older breakdown CLI. It expects monthly_cost or summary.monthly_cost numeric summary fields. If your CLI lacks scan or emits a different JSON schema, stop and adapt it from the actual output rather than guessing cloud totals. Do not pin an old CLI merely to ignore an unsupported current VM size.

This service uses the hosted Infracost pricing service, which requires its own authentication/account. The exporter itself has no paid cloud service dependency. Current product limits can change; review your Infracost account terms.

## 3 Generate and publish a real report

Verify your Terraform configuration reflects actual intended resources: notably Azure westus2 and Standard_D2als_v7. Resources created manually outside Terraform will not appear automatically.

```bash
cd ~/multi-cloud-project
mkdir -p monitoring/cost-exporter/data
chmod 755 monitoring/cost-exporter/data
python3 monitoring/cost-exporter/refresh.py --terraform terraform
```

The script:

1. Runs an Infracost scan in USD.
2. Retrieves provider-filtered summary reports for aws, azurerm and google.
3. Checks that all summaries are numeric and reconcile with the overall scan total within USD 0.05.
4. Writes raw report evidence and atomically replaces data/costs.json only after successful validation.

Review the Infracost scan and provider reports for unsupported resources and missing usage. Numeric totals alone do not establish complete cost coverage. The adapter does not silently reinterpret an unknown schema, convert currency or fill a missing value with zero.

Verify the normalized data locally:

```bash
python3 -m json.tool monitoring/cost-exporter/data/costs.json
```

Compare it to Infracost's human-readable provider summaries:

```bash
infracost inspect ./terraform --provider aws --summary
infracost inspect ./terraform --provider azurerm --summary
infracost inspect ./terraform --provider google --summary
```

No sample cost report with invented amounts is included. An empty data folder is intentional until your real report is generated. Raw and normalized reports are ignored by the supplied local .gitignore. Review metadata before publishing report evidence.

## 4 Add the Compose service

From the LOCAL monitoring folder:

```bash
cd ~/multi-cloud-project/monitoring
docker compose --env-file .env -f compose.yml -f cost-exporter/compose.cost.yml config --quiet
docker compose --env-file .env -f compose.yml -f cost-exporter/compose.cost.yml up -d --build cost-exporter
```

This assumes your existing monitoring/.env supplies GRAFANA_ADMIN_PASSWORD as before. The override shares the base Compose project's network. If you also manage infrastructure tunnels through another override, include that -f file when managing the full stack.

Only localhost port 9400 is published for inspection. The data DIRECTORY is mounted read-only rather than a single file, allowing atomic report replacement to become visible without restarting the exporter. The container runs as a non-root user, so the data directory must be traversable (755) and the generated report readable (644). The script applies 644 to generated files; keep cloud secrets out of these reports.

## 5 Verify the exporter

From the laptop:

```bash
curl -fsS http://localhost:9400/metrics
```

Expected status metrics after a valid fresh report:

    cost_exporter_report_valid 1
    cost_exporter_report_stale 0

Three cloud_estimated_monthly_cost_usd series should carry values from YOUR report, with cloud labels aws, azure and gcp. A real numeric zero is preserved. A missing, invalid, non-USD or stale report does not produce a misleading zero-dollar cost.

The default freshness limit is 86400 seconds (24 hours). After that, cost gauges disappear and the stale gauge becomes 1. Change MAX_REPORT_AGE_SECONDS in compose.cost.yml if you require another explicit policy. The /healthz endpoint means only the HTTP exporter is running, not that estimates are valid.

## 6 Configure Prometheus

Edit monitoring/prometheus.yml and append this job under the EXISTING scrape_configs list:

```yaml
  - job_name: infracost
    scrape_interval: 60s
    static_configs:
      - targets: ["cost-exporter:9400"]
```

Do not create a second scrape_configs key or a duplicate infracost job. Keep the existing origins, node and postgres jobs.

Validate:

```bash
docker compose --env-file .env -f compose.yml exec -T prometheus promtool check config /etc/prometheus/prometheus.yml
```

Only after validation passes:

```bash
docker compose --env-file .env -f compose.yml restart prometheus
```

Open http://localhost:9090/targets and check the infracost job. Then query:

```promql
cloud_estimated_monthly_cost_usd{job="infracost"}
```

The exporter scrape up metric can be 1 while report_valid is 0; these describe different conditions.

## 7 Import Grafana dashboard

Open http://localhost:3000, then Dashboards > New > Import. Upload Grafana_Estimated_Costs.json and choose your existing Prometheus data source, whose URL is http://prometheus:9090 within Compose.

The ten panels show:

- AWS, Azure and GCP priced monthly estimates.
- Their combined estimate only when three fresh cloud series exist.
- Report age and validity/freshness.
- Estimate history, provider availability and exporter scrape health.
- The estimate scope and billing limitations.

Stat panels use instant queries so stale values cannot appear merely because a previous range sample still exists. A No fresh estimate message means investigate the report or data path, not assume free usage.

## 8 Refresh after Terraform changes

The exporter rereads the file every scrape, but DOES NOT run Infracost. Generate a new report after changes and at least once within the freshness limit:

```bash
cd ~/multi-cloud-project
python3 monitoring/cost-exporter/refresh.py --terraform terraform
```

No container restart is required. Check raw reports before treating a changed estimate as a real cost change. A failed refresh preserves the preceding report and timestamp; it will age out rather than masquerade as a new successful estimate.

You can later run refresh.py in Jenkins after installing/authenticating Infracost there and providing a shared persistent report directory. A Jenkins workspace-local file is not automatically the laptop's mounted file. Keep tokens in Jenkins Credentials or Vault and archive report evidence privately. No automated Jenkins report refresh is configured by this kit.

## 9 Alerts and test cases

Optionally append alerts-group.yml under the existing groups in monitoring/alerts.yml. It contains Prometheus rules for missing/invalid data, stale reports and a failed exporter scrape. These do not automatically route through Grafana's Slack contact point.

For Grafana-managed Slack alerts use the same status gauges and your existing contact point. Set appropriate No Data/Error handling. Budget thresholds against estimated monthly cost are planning warnings, not spending caps.

Test with your real report first. To test report loss safely, temporarily rename data/costs.json, confirm report_valid becomes 0 and cost series disappear, then restore the file and check recovery. Do not publish fake provider costs as real submission results. Keep report timestamps and the date/currency of actual billing exports separately.

## Troubleshooting

- cost-exporter target DOWN: check Compose network, target name, running container and logs.
- report_valid 0: no file, unreadable file, unknown schema, invalid number, missing timezone or non-USD currency.
- report_stale 1: refresh is overdue or the report is invalid/missing.
- No scan command: the installed Infracost CLI differs from the current adapter. Use current documented CLI or implement a verified format adapter.
- Provider sums do not reconcile: verify provider filters and JSON output. The script intentionally does not publish ambiguous totals.
- Permission denied reading costs.json: chmod 755 data and chmod 644 its non-secret report files.
- Costs differ from billing: check runtime, usage, omitted resources, credits and free-tier limits. Estimates are not invoices.

## Validation

Eleven automated tests passed for valid reports, real zero, missing clouds/files, stale data, wrong currency, future timestamps, invalid numbers and unknown schema. Additional adapter tests check summary shapes and provider reconciliation as recorded in VALIDATION.md. Dashboard JSON and Compose structure were checked. No real Infracost account/report, cloud credentials or running Grafana instance was accessed. First live report generation remains to be verified against your installed CLI.

References:
- https://www.infracost.io/docs/features/cli_commands/
- https://www.infracost.io/docs/faq/
- https://prometheus.io/docs/instrumenting/exposition_formats/
- https://grafana.com/docs/grafana/latest/datasources/prometheus/
