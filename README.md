# Multi-cloud infrastructure with Terraform

A training portfolio project combining AWS, Azure and Google Cloud infrastructure, a Python DNS failover controller, local monitoring and PostgreSQL backup tooling. The web workload is a static Nginx site with a provider-specific health endpoint.

## What this project demonstrates

- Provider-specific Terraform modules for compute, networking and private object storage.
- Active-passive origin selection through a single Cloudflare DNS-only A record.
- Health probes with success/failure thresholds, preferred-origin failback and a switch cooldown.
- Prometheus and blackbox exporter monitoring, with Grafana running locally through Docker Compose.
- Separate PostgreSQL logical backup, cross-cloud copy and restore procedures.
- Terraform validation in GitHub Actions and seven simulated Python controller tests.

## Architecture

```text
Client -> Cloudflare DNS-only A record -> one selected Nginx origin
                                         AWS / Azure / GCP

Local Python controller -> checks each /health -> updates the A record
Local Prometheus + blackbox exporter -> probes origins -> Grafana

Separate database exercise:
PostgreSQL source on GCP -> backup copies in S3 / Azure Blob / GCS
                        -> independent PostgreSQL recovery target on AWS
```

The static website does not use PostgreSQL. Website failover and database recovery are separate exercises. DNS failover is not load balancing or continuous database replication.

## Repository map

| Path | Purpose |
| --- | --- |
| `terraform/` | Root configuration and AWS, Azure and GCP modules |
| `bootstrap/` | Nginx startup scripts and provider health responses |
| `failover/failover.py` | Python standard-library controller |
| `tests/test_failover.py` | Simulated probes and Cloudflare API tests |
| `monitoring/` | Prometheus, blackbox exporter, alert rules and Grafana Compose stack |
| `database/` | PostgreSQL container configuration |
| `dr/` | Backup, scheduling, restore and recovery documentation |
| `vault/` | Optional Vault lab configuration |
| `.github/workflows/validate.yml` | Terraform format, initialization and validation workflow |

## Validation and evidence

The project owner reports completion of the training project. Published validation records have a narrower scope:

- [VALIDATION.md](VALIDATION.md) records simulated controller tests and structural checks. Its October 22 record did not include cloud deployment or real DNS recovery.
- [dr/VALIDATION.md](dr/VALIDATION.md) records configuration checks, not a completed cloud restore.
- Seven simulated controller tests were rerun successfully during the October 27, 2026 documentation review. No cloud resources or DNS records were changed during that review.

No production uptime, measured RTO/RPO, cost savings or zero-data-loss result is claimed here. Add dated, sanitized logs and measurements when recording live exercises. The presence of a workflow file does not establish a successful hosted CI run.

## Start with local checks

Prerequisites: Git, Python 3, Terraform matching `terraform/versions.tf`, and registry connectivity for provider downloads. Deployment additionally requires cloud CLIs, authenticated accounts, SSH keys, suitable quotas and a Cloudflare zone/token. Monitoring requires Docker with Compose. The DR scripts require Bash/WSL and the tools listed in [dr/README.md](dr/README.md).

```bash
git clone https://github.com/thupeshkumar/multi-cloud-project.git
cd multi-cloud-project
python tests/test_failover.py
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
```

The Python tests simulate external services. Terraform initialization downloads providers; these commands do not provision cloud infrastructure.

## Provision a lab

1. Copy `terraform/terraform.tfvars.example` to a private `terraform/terraform.tfvars` and set the required IDs, unique name, SSH public key path and administrator CIDR.
2. Configure provider authentication without committing credentials. Review resource sizes, regions and account costs.
3. Run `terraform -chdir=terraform plan -out=lab.tfplan` and inspect the plan. Apply only after reviewing it with `terraform -chdir=terraform apply lab.tfplan`.
4. Read `terraform -chdir=terraform output origin_ips` and `terraform -chdir=terraform output storage`. Use current values throughout the lab.
5. Verify each origin returns HTTP 200 with exactly `healthy aws`, `healthy azure` or `healthy gcp` from `/health`.

**Configuration precedence:** the reviewed Azure module uses **West US 2 / Standard_D2als_v7**. Older setup notes refer to East US / Standard_B1s. Inspect the current module and plan; do not assume older region, SKU, IP or free-tier notes remain applicable. [SETUP.md](SETUP.md) contains the extended walkthrough but includes historical configuration details.

## DNS failover

Create one dedicated DNS-only A record for the lab. Configure `failover/origins.json` from current origin IPs, in priority order. First run:

```bash
python failover/failover.py --origins failover/origins.json --dry-run
```

Dry-run mode still probes the configured HTTP endpoints, but does not write DNS. Stop with Ctrl+C. To enable DNS updates, set `CF_API_TOKEN`, `CF_ZONE_ID`, `CF_RECORD_ID` and `CF_RECORD_NAME` in the process environment, then rerun without `--dry-run`. Use a zone-scoped DNS-edit token and keep it out of files and logs.

Defaults are three consecutive checks, a 30-second interval plus processing time, and a 180-second cooldown. If all origins fail, the controller leaves DNS unchanged. The workstation/controller must remain running; DNS caches and existing connections affect recovery time.

For a controlled failover exercise, stop Nginx on the preferred lab origin, observe the selected origin and DNS answer, then restore Nginx and observe failback. Record failure time, DNS update time and client-visible recovery separately. Configuration intervals are not measured recovery guarantees.

## Monitoring and database recovery

Update `monitoring/prometheus.yml` with current targets. Set `GRAFANA_ADMIN_PASSWORD` privately, then run:

```bash
docker compose -f monitoring/compose.yml config --quiet
docker compose -f monitoring/compose.yml up -d
```

Prometheus is bound to `127.0.0.1:9090`; Grafana is bound to `127.0.0.1:3000`. Configure Grafana against the Prometheus service. Alert-rule definitions alone do not establish working external notifications.

Follow [dr/README.md](dr/README.md) and [dr/DR_PLAN.md](dr/DR_PLAN.md) for the separate backup/restore exercise. Use disposable test data first. Logical snapshots do not provide continuous replication; fixture comparison does not validate every production table or external dependency.

## Limitations and cleanup

This lab uses public HTTP, a single local failover controller and local monitoring. It does not establish production high availability. Managed database services are not part of the baseline Terraform configuration.

Stop local services with `docker compose -f monitoring/compose.yml down`. This preserves named volumes. Before removing infrastructure, retain required data and review `terraform -chdir=terraform plan -destroy`; run `terraform -chdir=terraform destroy` only for the intended lab. Review non-empty storage, manually created resources and the dedicated DNS record separately, and confirm cleanup in each provider account.
