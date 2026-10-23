# Multi Cloud Deployment and Management with Terraform

A cost-conscious student project for deploying web infrastructure across **AWS, Microsoft Azure and Google Cloud**, using Terraform, Cloudflare DNS, a local failover controller, Prometheus and Grafana.

The application is a static Nginx website with a provider-specific health endpoint. The project demonstrates repeatable infrastructure provisioning, active-passive DNS failover, centralized HTTP monitoring and PostgreSQL backup procedures.

## Architecture

```text
                     http://app.thupesh.com
                               |
                 Cloudflare DNS-only A record
                               |
                    One selected origin IP
                               |
             +-----------------+-----------------+
             |                 |                 |
            AWS              Azure              GCP
         us-east-1          West US 2         us-central1
         t3.micro       Standard_D2als_v7      e2-micro
           Nginx             Nginx             Nginx
             |                 |                 |
         Private S3       Private Blob      Private GCS
                                               |
                                       PostgreSQL Docker

Local workstation with Docker Desktop
  - Prometheus and blackbox exporter probe each origin
  - Grafana displays health and response-time metrics
  - Python controller checks origins and updates Cloudflare DNS
```

The optional managed database exercises use RDS PostgreSQL and the Azure SQL free offer. They are independent of the static webpage and are not provisioned by the baseline Terraform modules.

## Cloud configuration

| Provider | Region | VM size | Last recorded public IP |
|---|---|---|---|
| AWS | `us-east-1` | `t3.micro` | `184.197.92.35` |
| Azure | `westus2` | `Standard_D2als_v7` | `20.69.109.11` |
| GCP | `us-central1` | `e2-micro` | `34.41.25.119` |

**These addresses can change.** Check `terraform output origin_ips` and the cloud consoles before testing. Update DNS, failover configuration and monitoring targets when an address changes.

### Azure region change

Azure was initially planned for East US with `Standard_B1s`. Deployment was blocked by capacity restrictions. The alternative ARM-based `Standard_B2pts_v2` was blocked by a zero Bpsv2-family CPU quota in East US.

The revised configuration uses **West US 2 and Standard_D2als_v7**, with an **x86-64 Ubuntu image**. The VNet, subnet's parent VNet, NIC, public IP, NSG and VM must be configured consistently for the destination region. A missing subnet must be recreated through Terraform before the NIC can reference it.

`Standard_D2als_v7` is outside the advertised free VM allowance. Check eligible trial credit, quota and the cost estimate before deployment. Availability in a SKU list does not guarantee that quota and physical capacity are sufficient.

## Tools

- Terraform and provider plugins for AWS, Azure and GCP
- AWS CLI, Azure CLI and Google Cloud CLI
- Git and GitHub Actions
- Python 3 and OpenSSH
- Nginx on each cloud VM
- Docker Desktop with Linux containers on the local workstation
- Prometheus, blackbox exporter and Grafana
- PostgreSQL 16 in Docker on the GCP VM for the database exercise
- An existing domain managed through Cloudflare DNS

The commands below use **Linux or WSL Bash**, not PowerShell.

## Repository structure

```text
multi-cloud-project/
├── .github/workflows/validate.yml
├── .gitignore
├── bootstrap/
│   ├── aws.sh
│   ├── azure.sh
│   └── gcp.sh
├── terraform/
│   ├── main.tf
│   ├── versions.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── aws/
│       ├── azure/
│       └── gcp/
├── failover/
│   ├── failover.py
│   └── origins.example.json
├── monitoring/
│   ├── compose.yml
│   ├── prometheus.yml
│   ├── blackbox.yml
│   └── alerts.yml
├── database/
│   └── compose.yml
├── tests/
│   └── test_failover.py
└── README.md
```

Local files such as `terraform.tfvars`, credentials, state and database dumps must remain outside version control.

## 1 Configure cloud access

Authenticate using the relevant CLI before running Terraform:

```bash
# AWS: use your configured SSO profile
aws sso login --profile multicloud
export AWS_PROFILE=multicloud
aws sts get-caller-identity

# Azure
az login
az account set --subscription YOUR_SUBSCRIPTION_ID

# GCP
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

For AWS, first configure the profile with `aws configure sso --profile multicloud` if needed. Use identities with the required lab permissions and enable the necessary cloud APIs/resource providers. Do not put credentials in Terraform source files.

## 2 Configure and deploy Terraform

From the repository root:

```bash
ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/multicloud"
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

If the SSH key already exists, reuse it instead of overwriting it. Edit the variable file with your resource prefix, subscription/project identifiers, public SSH key path and current administrator public IPv4 `/32`.

Before planning, confirm the Azure module matches the revised design:

```hcl
# Azure regional resources
location = "westus2"

# Azure VM
size = "Standard_D2als_v7"

source_image_reference {
  publisher = "Canonical"
  offer     = "ubuntu-24_04-lts"
  sku       = "server"
  version   = "latest"
}
```

Use the size variable instead if your module already has one. For existing resources, a region change can cause replacements; inspect the plan and preserve needed data.

```bash
cd terraform
terraform fmt -recursive
terraform init
terraform validate
terraform plan -out=lab.tfplan
terraform show lab.tfplan
```

Review planned resources, replacements and estimated costs before applying:

```bash
terraform apply lab.tfplan
terraform output origin_ips
terraform output storage
cd ..
```

Keep the existing Terraform working directory and state when retrying a partial deployment. Create a new plan after any configuration change.

## 3 Verify the application

```bash
curl --max-time 10 http://184.197.92.35/health
curl --max-time 10 http://20.69.109.11/health
curl --max-time 10 http://34.41.25.119/health
```

Required response bodies are case-sensitive:

```text
healthy aws
healthy azure
healthy gcp
```

Start the website on a VM if necessary:

```bash
sudo systemctl enable --now nginx
curl http://localhost/health
```

To correct a missing or incorrectly capitalized health file, run the appropriate command **on that provider's VM**:

```bash
# AWS VM
printf 'healthy aws\n' | sudo tee /var/www/html/health

# Azure VM
printf 'healthy azure\n' | sudo tee /var/www/html/health

# GCP VM
printf 'healthy gcp\n' | sudo tee /var/www/html/health
```

Cloud firewalls must allow inbound TCP port 80 for this public HTTP lab. Restrict SSH to your administrator IP. The homepage's provider text is static; use the health response and connected IP to verify routing.

## 4 Configure Cloudflare DNS

1. Add `thupesh.com` to Cloudflare and select the Free plan.
2. Preserve existing DNS records, particularly email records.
3. Configure the registrar with the exact nameservers Cloudflare assigns and wait for the zone to become active. Follow Cloudflare's DNSSEC transition guidance if DNSSEC was already enabled.
4. Create one dedicated project record:

| Setting | Value |
|---|---|
| Type | `A` |
| Name | `app` |
| Initial IPv4 address | `184.197.92.35`, or the current AWS public IP |
| Proxy status | **DNS only**, grey cloud |
| TTL | 60 seconds or the lowest supported value |

Do not create three A records at `app` for this controller. Avoid conflicting AAAA/CNAME records at that test hostname. Leave unrelated domain records unchanged.

Create a Cloudflare API token with **Zone → DNS → Edit**, restricted to **thupesh.com**. Copy the Zone ID from the domain overview.

```bash
read -rsp "Cloudflare API token: " CF_API_TOKEN
echo
export CF_API_TOKEN
export CF_ZONE_ID='YOUR_ZONE_ID'
export CF_RECORD_NAME='app.thupesh.com'
```

Discover the record ID:

```bash
curl --silent --show-error --fail \
  "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&name=app.thupesh.com" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  | python3 -m json.tool
```

Copy the matching record's `id` from `result`:

```bash
export CF_RECORD_ID='YOUR_RECORD_ID'
```

Keep these variables in the same terminal used to run the controller. Never commit the token or include it in screenshots.

## 5 Configure and run failover

Create `failover/origins.json` with the current origin addresses:

```json
[
  {
    "name": "aws",
    "ip": "184.197.92.35",
    "url": "http://184.197.92.35/health"
  },
  {
    "name": "azure",
    "ip": "20.69.109.11",
    "url": "http://20.69.109.11/health"
  },
  {
    "name": "gcp",
    "ip": "34.41.25.119",
    "url": "http://34.41.25.119/health"
  }
]
```

From the repository root, test without DNS changes:

```bash
python3 failover/failover.py --origins failover/origins.json --dry-run
```

Stop with Ctrl+C, then enable DNS updates:

```bash
python3 failover/failover.py --origins failover/origins.json
```

Default behavior:

- Preference order: AWS, Azure, GCP.
- Three consecutive successes qualify an origin.
- Three consecutive failures trigger abandonment of the active origin.
- Checks run every 30 seconds plus request processing time.
- A 180-second cooldown limits frequent switches.
- When every origin is unhealthy, DNS remains unchanged.
- Preferred-primary failback occurs after successful checks and cooldown.

Cloudflare provides DNS; **the local Python controller implements the failover decisions**. This is active-passive routing, not managed load balancing. Keep the controller and workstation running. DNS caching and existing connections can delay client-visible recovery.

### Test failover

Keep Azure and GCP running, then stop Nginx on AWS:

```bash
ssh -i ~/.ssh/multicloud ubuntu@184.197.92.35
sudo systemctl stop nginx
```

Watch for a controller log selecting Azure. From another local terminal:

```bash
nslookup app.thupesh.com 1.1.1.1
curl --max-time 10 -w '\nConnected IP: %{remote_ip}\n' \
  http://app.thupesh.com/health
```

Expected after DNS cache expiry: `healthy azure` and `20.69.109.11`. To test the next destination, stop Azure Nginx while AWS remains down; expect GCP after checks and cooldown. Restore Nginx on both VMs afterwards using `sudo systemctl start nginx` and observe AWS failback.

Record actual failure timestamps, controller DNS-change timestamps and client-visible recovery times separately. Do not treat the configured intervals as guaranteed recovery times.

## 6 Run local monitoring with Docker Desktop

To reduce costs, Prometheus and Grafana run locally in Docker containers using Docker Desktop instead of additional cloud-hosted servers. Monitoring depends on the local computer and Docker Desktop remaining active.

Update `monitoring/prometheus.yml` with the current origin URLs. Retain `job_name: origins` and the labels `cloud: aws`, `cloud: azure` and `cloud: gcp`.

```bash
cd monitoring
read -rsp "Choose a Grafana admin password: " GRAFANA_ADMIN_PASSWORD
echo
export GRAFANA_ADMIN_PASSWORD
docker compose config --quiet
docker compose up -d
docker compose ps
```

Open:

- Prometheus: <http://localhost:9090>
- Grafana: <http://localhost:3000>

Sign in to Grafana as `admin` with the password entered above. Add a Prometheus data source using `http://prometheus:9090`, then select **Save & test**.

Import `Grafana_Multi_Cloud_Dashboard.json` if included in your repository, or create panels using these queries:

| Panel | PromQL |
|---|---|
| Per-cloud HTTP health | `probe_success{job="origins"}` |
| Probe duration | `probe_duration_seconds{job="origins"}` |
| HTTP status | `probe_http_status_code{job="origins"}` |
| Observed availability in the last hour | `100 * avg_over_time(probe_success{job="origins"}[1h])` |
| Prometheus scrape health | `up{job="origins"}` |

Set legends to `{{cloud}}`. For health, map 1 to UP and 0 to DOWN. A successful exporter scrape does not mean the origin is healthy; use `probe_success` for application health. Observed availability includes recorded samples only, not a contractual SLA.

The supplied Prometheus rule can display a local `OriginUnavailable` alert. External notification delivery requires additional configuration. CPU, RAM, disk usage, database health, bucket statistics and billing metrics require additional exporters or integrations. Direct-origin panels do not identify the active DNS destination.

After changing targets:

```bash
docker compose restart prometheus
cd ..
```

## 7 PostgreSQL backup exercise

The GCP database uses a PostgreSQL 16 container. The recorded container name is `database-postgres-1`; confirm it with `sudo docker ps` before use. Commands assume the supplied database name `projectdb` and user `projectuser`.

On the GCP VM:

```bash
mkdir -p ~/backups
chmod 700 ~/backups
sudo docker exec database-postgres-1 \
  pg_dump -U projectuser -d projectdb -Fc \
  > ~/backups/projectdb.dump
```

Proceed only if the dump succeeded. Validate its archive listing and calculate a checksum:

```bash
sudo docker exec -i database-postgres-1 \
  pg_restore --list < ~/backups/projectdb.dump
chmod 600 ~/backups/projectdb.dump
cd ~/backups
sha256sum projectdb.dump > projectdb.dump.sha256
```

On your local workstation, from the repository root:

```bash
mkdir -p backups
scp -i ~/.ssh/multicloud \
  labadmin@34.41.25.119:/home/labadmin/backups/projectdb.dump \
  labadmin@34.41.25.119:/home/labadmin/backups/projectdb.dump.sha256 \
  ./backups/
cd backups
sha256sum -c projectdb.dump.sha256
cd ..
terraform -chdir=terraform output storage
```

Substitute the storage names from Terraform outputs:

```bash
aws s3 cp ./backups/projectdb.dump \
  s3://YOUR_AWS_BUCKET/backups/projectdb.dump

az storage blob upload --auth-mode login \
  --account-name YOUR_AZURE_STORAGE_ACCOUNT \
  --container-name backups --name projectdb.dump \
  --file ./backups/projectdb.dump

gcloud storage cp ./backups/projectdb.dump \
  gs://YOUR_GCP_BUCKET/backups/projectdb.dump
```

Azure data uploads require an appropriate data-plane role, such as Storage Blob Data Contributor. Upload the checksum file alongside the dump. Use dummy data and private storage.

An archive listing and checksum do not prove successful database recovery. Restore into a separate empty PostgreSQL database and compare rows before claiming recovery. A restore on the same VM does not establish recovery after a cloud-provider failure. PostgreSQL backups cannot be directly restored into Azure SQL, which uses a different engine. These uploads are backup copies, not continuous database replication.

## 8 Version control and CI

GitHub stores the Terraform modules, startup scripts, monitoring configuration and failover controller. The supplied `.github/workflows/validate.yml` runs Terraform formatting and validation on pushes and pull requests.

```text
Commit or pull request
        |
Terraform formatting check
        |
Provider initialization without a backend
        |
Terraform configuration validation
```

Deployment is performed from an authenticated workstation after a reviewed plan. This is **continuous integration with manually initiated deployment**; automated cloud deployment is a future enhancement requiring secure cloud authentication and shared remote state.

Commit `.terraform.lock.hcl`. Ignore:

```gitignore
.terraform/
*.tfstate*
*.tfplan
terraform.tfvars
.env
*.pem
*.key
backups/
```

Review staged files before committing. Do not push tokens, private keys, state, plans or database dumps.

## Troubleshooting

| Symptom | Action |
|---|---|
| `SkuNotAvailable` | Check regional capacity and subscription SKU restrictions before choosing an alternative. |
| VM CPU quota exceeded | Check both regional and VM-family quotas; availability alone is insufficient. |
| NIC cannot reference subnet | Confirm the subnet exists and its VNet shares the NIC's region; use a direct Terraform subnet reference. |
| Missing Cloudflare variables | Export all four `CF_*` variables in the controller's terminal. |
| Expected DNS-only record error | Check A-record type, exact hostname, record ID and `proxied: false`. |
| All health streaks remain zero | Test each direct `/health`; return exact lowercase provider text and HTTP 200. |
| Homepage identifies the wrong cloud | Check the connected IP and `/health`; correct the static homepage label if needed. |
| Cloudflare error 521 | Confirm DNS-only setup, origin service, port 80 and cached DNS behavior. |
| Grafana has no data | Confirm Prometheus targets, cloud labels and data-source URL; restart Prometheus after edits. |
| Backup file missing locally | Create the dump on the database VM and copy it to the workstation before uploading. |

## Cost controls and limitations

- Free-tier eligibility depends on account offer, region, service, usage and expiry. Trial-credit coverage is not permanent free usage.
- The revised Azure D-series VM can consume credits or incur charges. Public IPs, disks, snapshots, storage operations and transfers also need review.
- Cloudflare Free DNS does not provide the managed failover service used in paid Load Balancing. The Python controller supplies this lab's decision logic.
- Local monitoring saves additional cloud VM costs but stops when the workstation or Docker Desktop stops.
- Storage allowances are usage limits, not reserved 5 GB capacities. Use small dummy files for demonstrations.
- The baseline has no continuous database replication, cross-engine automatic recovery, production TLS configuration or production availability guarantee.
- Vault is not implemented in the supplied baseline. Use local authenticated CLI sessions and secure secret handling; do not claim a Vault deployment without implementing it.
- Budget alerts notify about spending; do not treat them as hard spending caps.

## Cleanup

Save screenshots and results first. Stop the controller, remove the dedicated test DNS record and revoke its token when the lab is finished. Delete optional manually created databases and preserve any needed data before removing infrastructure.

From the repository root:

```bash
docker compose -f monitoring/compose.yml down
terraform -chdir=terraform plan -destroy -out=cleanup.tfplan
terraform -chdir=terraform show cleanup.tfplan
```

After reviewing the deletion plan:

```bash
terraform -chdir=terraform apply cleanup.tfplan
```

Nonempty buckets may block deletion: inspect and remove only this lab's disposable backup objects after preserving anything needed. Check for remaining disks, IPs, snapshots, backups and manual resources in each console. Keep Terraform state until cleanup is confirmed. Docker volumes remain unless explicitly removed.

## Submission evidence

- Terraform validation, reviewed plan and apply output
- Cloud resource configuration and revised Azure region/size
- Three direct health responses
- Controller logs and DNS changes during failover
- Client-visible recovery timestamps
- Grafana dashboard and local alert evidence
- Backup checksum and verified restore results
- GitHub Actions workflow result
- Account eligibility, actual cost review and cleanup evidence

Record observed results rather than treating expected outcomes as completed tests.

## Official documentation

- [Terraform](https://developer.hashicorp.com/terraform/docs)
- [AWS Free Tier](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier.html)
- [Azure free account](https://azure.microsoft.com/en-us/pricing/purchase-options/azure-account)
- [Azure Dalsv7 specifications](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dalsv7-series)
- [Google Cloud Free Tier](https://docs.cloud.google.com/free/docs/free-cloud-features)
- [Cloudflare DNS setup](https://developers.cloudflare.com/dns/zone-setups/full-setup/setup/)
- [Cloudflare API tokens](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
- [Prometheus](https://prometheus.io/docs/introduction/overview/)
- [Grafana](https://grafana.com/docs/grafana/latest/)
- [PostgreSQL backup utility](https://www.postgresql.org/docs/16/app-pgdump.html)
