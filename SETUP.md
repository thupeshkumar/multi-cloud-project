# Multi Cloud Deployment and Management with Terraform

Installation and configuration guide • Windows workstation • 22 October 2026

## 1. Read this before creating resources

This is a student demonstration of three cloud web servers, private object storage, local monitoring and DNS failover. It is not a guaranteed zero-cost or production high-availability system. No cloud resources have been created by preparing this package.

**Cloudflare Free provides DNS, but its managed Load Balancing health checks and automatic failover are a paid add-on.** This project uses a Python controller on your laptop to check origins and change a DNS record through the Cloudflare API. Your laptop and internet connection must remain on. This is active-passive routing, not traffic load balancing. If you need managed load balancing to satisfy the original brief, obtain budget for it and describe that as a separate extension. A domain must already be owned; domain registration is not included in free DNS.

### Check your account offers

| Component | Configuration | Free-tier condition and cost exposure |
|---|---|---|
| AWS compute | Ubuntu EC2 t3.micro, 8 GB gp3, us-east-1 | Check your actual account plan and credits. New-account offers changed in July 2025. Do not assume the older 12-month allowance applies. |
| AWS storage and database | Private S3; optional RDS PostgreSQL db.t3.micro | S3 storage, operations, RDS, backups and networking can consume credits or incur charges. Skip RDS if its estimated cost is not covered. |
| Azure compute | Ubuntu Standard_B1s, 30 GB Standard LRS OS disk, East US | Check the VM SKU and disk entitlement in your subscription. B1s availability and free offers differ; do not silently substitute another size. Standard public IPv4 is a separate cost item. |
| Azure database | Optional Azure SQL free offer | Select the explicit free offer and auto-pause when the monthly free limit is reached. Ordinary serverless deployment is not automatically free. |
| Azure storage | Private Standard LRS Blob account | Confirm your account's included amount and operations. An empty account does not reserve 5 GB. |
| GCP compute | e2-micro, us-central1-a, 30 GB pd-standard | Eligible regional compute and disk have monthly limits. External IPv4 and outbound traffic require separate checks. |
| GCP storage | Regional Standard bucket in us-central1 | Free allowance includes 5 GB-months in eligible US regions plus limited operations; this is a quota, not a bucket capacity setting. |
| GCP database | PostgreSQL Docker container on the VM | No managed DB fee, but it shares the VM's small RAM and disk and requires backups. |
| Local tools | Prometheus, blackbox exporter, Grafana, Python | Use your own machine; cloud traffic and your internet connection still apply. |

GCP's published standard VM external IPv4 rate is USD 0.005/hour with only one free hour/month/account: roughly USD 3.65 for 730 hours before credits and taxes. AWS/Azure public IPv4, managed disks, snapshots and cross-cloud transfers also need checking. Budget alerts generally notify; they do not cap spending. Use a short lab session and destroy resources afterwards. Do not upload 5 GB just to prove the quota; use a tiny sample file.

AWS's current Free account plan ends after six months or credit exhaustion, whichever occurs first. Historical free allowances may have expired for an older account. Check Billing before planning. Azure SQL's documented offer includes 100,000 vCore-seconds and 32 GB per database per month; select **Auto-pause the database until next month**, and verify subscription eligibility. GCP's regional e2-micro allowance is shared across eligible instances, not an unlimited allowance per VM.

## 2. Architecture and package scope

```text
Browser -> Cloudflare DNS only A record app.yourdomain.com
                         |
                  currently selected IP
                AWS -> Azure -> GCP priority
                 |       |       |
               Nginx   Nginx   Nginx
                 |       |       |
                S3     Blob     GCS     private backup destinations

Laptop -> direct origin health probes -> Python -> Cloudflare API
Laptop -> blackbox exporter -> Prometheus -> Grafana
Optional independent DB exercises: RDS PostgreSQL / Azure SQL / GCP PostgreSQL
```

Terraform modules create VMs, networks, firewall rules and private storage. They install a static Nginx page with a provider name and `/health`. Managed databases are optional console exercises below, not resources created by this Terraform package. PostgreSQL and Azure SQL use different engines; they cannot be described as native cross-cloud replicas. The demo webpage does not read or write any database. Consequently web failover does not prove database failover, zero data loss, or production disaster recovery.

Files: `terraform/` contains the root and three provider modules; `bootstrap/` contains startup scripts; `failover/` contains the DNS controller; `monitoring/` contains local containers; `database/` contains the optional PostgreSQL container; `.github/workflows/validate.yml` contains credential-free validation. `SUBMISSION.md` is your report template.

## 3. Install workstation tools

Use Windows 10/11 with hardware virtualization and enough RAM for Docker Desktop. Run commands in PowerShell unless explicitly marked **on the Linux VM**. Install only tools you do not already have.

1. Install Git for Windows, Python 3, AWS CLI v2, Azure CLI, Google Cloud CLI and Terraform from official installers. Terraform must be at least 1.6 and below 2.0; the validation workflow uses 1.13.5.
2. In an administrator terminal, run `wsl --install` if WSL2 is missing, then restart Windows when requested. Install Docker Desktop using its WSL2 backend and start it in Linux containers mode.
3. Check the installations in a fresh terminal:

```powershell
git --version
python --version
terraform version
aws --version
az version
gcloud version
docker version
docker compose version
ssh -V
```

`docker version` must show a reachable server. A missing server means Docker Desktop has not started. Use the official installation links in section 16. This package uses public, pinned container version tags; check current release/security guidance before reuse beyond this short lab.

## 4. Accounts credentials and permissions

Enable MFA, avoid root/owner credentials for routine deployment, and create a billing alert in each cloud before deployment. Set low thresholds suited to your budget, such as USD 1 and USD 5, and check daily spending. Record your offer expiry and available credit.

**AWS:** Create/use an IAM Identity Center permission set scoped to the lab. It needs EC2 networking, VM, key-pair and S3 management, plus read access for image discovery. Run:

```powershell
aws configure sso --profile multicloud
aws sso login --profile multicloud
$env:AWS_PROFILE = 'multicloud'
aws sts get-caller-identity
```

If Identity Center is unavailable in your account, use an approved short-lived IAM role/session or a dedicated lab IAM user configured locally with `aws configure --profile multicloud`. Never put access keys into Terraform files or screenshots. Optional RDS needs additional narrowly scoped database permissions.

**Azure:** Use a dedicated resource group/subscription for this lab. The deployer needs resource management rights for networks, VMs and storage; Contributor at the lab subscription is convenient for an isolated student subscription but broader than a production deployment identity. Do not use subscription-wide Owner solely for this exercise.

```powershell
az login
az account list --output table
az account set --subscription 'YOUR_SUBSCRIPTION_ID'
az account show --output table
```

Register `Microsoft.Compute`, `Microsoft.Network` and `Microsoft.Storage` resource providers in the portal if necessary. Optional SQL also needs `Microsoft.Sql`. If your subscription cannot register providers, ask your administrator; don't switch to a paid subscription without checking its terms.

**GCP:** Create a dedicated project, link an eligible billing account, enable Compute Engine and Cloud Storage APIs, and use an identity limited to that project. Compute Admin and Storage Admin are broad lab roles; replace them with narrower roles for real use. Service-account impersonation may require Service Account User as well, but this VM template attaches no service account.

```powershell
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud services enable compute.googleapis.com storage.googleapis.com
gcloud auth application-default login
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

The last two commands set application default credentials used by Terraform; ordinary `gcloud auth login` alone is insufficient. Project API enablement requires Service Usage permissions. If an organization enforces OS Login, adapt the module to that policy instead of disabling the policy; the supplied SSH-key configuration assumes a personal project without that restriction.

For the original brief's Vault requirement, this package uses cloud CLI credential stores as the lab's alternative secret mechanism. Vault is not implemented. Do not claim it is. For CI deployment, use cloud OIDC federation rather than copying these local credentials into repository secrets.

## 5. Configure Terraform

Extract the package into a folder you control and open PowerShell in `multi-cloud-project`.

```powershell
ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/multicloud"
Copy-Item terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Use a passphrase for the key. Edit `terraform.tfvars`:

- `name`: globally unique, 8–18 lowercase letters/digits, starting with a letter. Example: `studentmc26xyz`.
- `admin_cidr`: your current public IPv4 followed by `/32`, obtained from your router or a trusted IP lookup. The example address is deliberately unusable.
- `ssh_public_key_path`: full path to the public `.pub` file, using forward slashes if needed.
- `azure_subscription_id` and `gcp_project_id`: your real values.

The only public application port is 80. SSH port 22 is restricted to `admin_cidr`; database ports are not public. Storage is private. Monitoring interfaces bind to localhost. Public HTTP is used solely for a non-sensitive static demonstration. For HTTPS, add a real hostname/certificate and secured origins before handling credentials or user data. Do not use Cloudflare Flexible TLS as a production substitute for origin TLS.

```powershell
Set-Location terraform
terraform fmt -check -recursive
terraform init
terraform validate
terraform plan -out=lab.tfplan
terraform show lab.tfplan
```

Inspect every planned resource and obtain pricing in the cloud consoles/calculators for the full set, including IP addresses and disks. This root plans all three clouds; it does not have a free-tier safety switch. If any service is ineligible, stop and adapt the plan before applying. Keep `lab.tfplan` private; plans and state can contain sensitive data. Keep `.terraform.lock.hcl` in Git, and keep credentials, variable files and state out of Git. The lab uses local state for one operator; use encrypted, locked remote state for a team.

## 6. Deploy and check each server

These commands create potentially billable resources in your accounts. Execute them only after the cost check above.

```powershell
terraform apply lab.tfplan
terraform output origin_ips
terraform output storage
```

Wait several minutes for package installation. Substitute the real addresses below:

```powershell
curl.exe http://AWS_IP/health
curl.exe http://AZURE_IP/health
curl.exe http://GCP_IP/health
ssh -i "$HOME/.ssh/multicloud" ubuntu@AWS_IP
ssh -i "$HOME/.ssh/multicloud" labadmin@AZURE_IP
ssh -i "$HOME/.ssh/multicloud" labadmin@GCP_IP
```

Expected responses: `healthy aws`, `healthy azure`, `healthy gcp`. Run the SSH commands individually. On a VM, check `sudo systemctl status nginx`, `sudo cloud-init status --wait` and `/var/log/cloud-init-output.log`. GCP startup-script logs are available with `sudo journalctl -u google-startup-scripts.service`. Keep SSH sessions available while demonstrating failover.

The templates create no NAT gateway, load balancer, cross-cloud VPN or managed database. AWS and GCP addresses may change after stop/start or recreation. Re-read Terraform outputs and update DNS, controller targets and Prometheus whenever addresses change. If a particular East US VM size or image is unavailable, check eligible alternatives and their costs before changing the module.

## 7. Configure Cloudflare DNS

1. Add your existing domain to Cloudflare Free and complete the registrar nameserver change. Wait for the zone to be active. Preserve existing email and other DNS records.
2. Add exactly one dedicated A record: name `app`, IPv4 = AWS origin, proxy status **DNS only** (grey cloud), TTL 60 seconds or the lowest supported value. Use a test subdomain, not an existing production name. Remove conflicting test AAAA or CNAME records at this same name.
3. Create a Cloudflare API token with **Zone → DNS → Edit**, limited to this zone. Add zone read only if your discovery method needs it. Store the token locally for the session; never commit it.
4. Copy Zone ID from the zone overview. To discover the record ID, use the API listing below. Keep the token out of screenshots and logs.

```powershell
$env:CF_API_TOKEN = Read-Host 'Paste the scoped API token' -MaskInput
$env:CF_ZONE_ID = 'YOUR_ZONE_ID'
$env:CF_RECORD_NAME = 'app.yourdomain.com'
$headers = @{Authorization = "Bearer $env:CF_API_TOKEN"}
$uri = "https://api.cloudflare.com/client/v4/zones/$env:CF_ZONE_ID/dns_records?type=A&name=$env:CF_RECORD_NAME"
(Invoke-RestMethod -Headers $headers -Uri $uri).result | Select-Object id,name,content,proxied
$env:CF_RECORD_ID = 'YOUR_RECORD_ID'
```

`-MaskInput` requires PowerShell 7; in Windows PowerShell 5.1 use a secure secret-entry method or upgrade to PowerShell 7. Do not replace this with a token literal in a shared terminal transcript. Use the same PowerShell session for running the controller.

From the package root:

```powershell
Copy-Item failover/origins.example.json failover/origins.json
```

Edit every `ip` and `url` to the real direct IPv4 and `http://IP/health`. Keep names `aws`, `azure`, `gcp` and their order. Do not probe the shared DNS name: that would hide which origin is failing.

```powershell
python failover/failover.py --origins failover/origins.json --dry-run
# After observing healthy probes, stop with Ctrl+C and enable API updates:
python failover/failover.py --origins failover/origins.json
```

The controller checks all origins every 30 seconds plus request time. It requires three healthy probes before selecting a destination and three failed probes before abandoning the active origin. It prefers AWS, then Azure, then GCP, and delays changes by a 180-second cooldown. When all origins are unhealthy it leaves DNS unchanged and logs the condition. It reads the DNS record every cycle, rejects a proxied or wrong record, and logs API errors without deleting the record. Run only one controller. The cooldown is in memory and resets if the process restarts.

This controller is a lab process: keep the terminal open and prevent laptop sleep for the demo. A scheduled task/service would need its own secure credential handling and restart policy. Local connectivity loss can make every origin look down. DNS caching means failover is not instant, existing connections may break and some clients may retain an old address beyond TTL. Do not claim a fixed RTO from the probe interval alone.

## 8. Start local Prometheus and Grafana

Edit `monitoring/prometheus.yml`, replacing all three `*_IP` placeholders. Use a second terminal from the package root:

```powershell
$env:GRAFANA_ADMIN_PASSWORD = Read-Host 'Choose a Grafana admin password' -MaskInput
docker compose -f monitoring/compose.yml config --quiet
docker compose -f monitoring/compose.yml up -d
```

Open `http://localhost:9090/targets`; all origins should be UP as scrape jobs. Then query `probe_success`: values of 1 indicate healthy HTTP probes. A scrape being UP alone means the exporter answered, not that the origin is healthy.

Open `http://localhost:3000`, username `admin`, password chosen above. Add a Prometheus data source with URL `http://prometheus:9090`. Create panels for:

| Panel | PromQL | Unit |
|---|---|---|
| Origin health | `probe_success{job="origins"}` | 0 or 1 |
| Request duration | `probe_duration_seconds{job="origins"}` | seconds |
| HTTP status | `probe_http_status_code{job="origins"}` | number |
| Observed availability | `avg_over_time(probe_success{job="origins"}[1h]) * 100` | percent |

Use the `cloud` label in legends. Availability is for the observed window only. Prometheus has a one-minute `OriginUnavailable` alert rule; view it at `/alerts`. No Alertmanager or Slack/PagerDuty delivery is included, so firing alerts are local only. To add notifications, deploy Alertmanager and securely configure an authorized destination. The blackbox configuration measures reachability and response time; it does not measure VM CPU/RAM or cloud billing. Those need node exporters secured by tunnels/private networking and provider billing integrations respectively. Use provider billing consoles for this lab's cost evidence.

## 9. Optional databases matching the original diagram

Complete this only if required by your evaluator and covered by your account offer. These console-created databases are not tracked by this Terraform state and must be deleted separately.

### AWS RDS PostgreSQL

Create a small PostgreSQL RDS database in us-east-1 using `db.t3.micro` only if offered and eligible. Use Single-AZ, the smallest storage shown as eligible (commonly 20 GB), no optional paid monitoring, and **Public access = No**. Use the Terraform VPC. RDS needs a DB subnet group with subnets in at least two availability zones: the template creates only one, so first add a second private subnet, for example `10.10.2.0/24` in us-east-1b, then create the DB subnet group containing the two subnets. No NAT gateway is needed for a VM to connect to RDS inside the VPC. Create a separate DB security group allowing TCP 5432 **only from the EC2 application security group**, not from the internet.

Choose a secure administrator password using a local secret store. If you select managed credentials in Secrets Manager, check its separate cost. Connect from the EC2 VM with `psql` using the RDS endpoint, database name and `sslmode=verify-full` with the current AWS RDS CA bundle installed. Verify `SELECT version();`. Capture an evidence screenshot without secrets. Check backup retention and final-snapshot costs before deletion. Do not enter database passwords into Terraform user data.

### Azure SQL free offer

In the Azure SQL portal, use the explicit **Try for free / free database offer** workflow, choose an eligible server and region, and enable **Auto-pause the database until next month** when the free limit is reached. Confirm the free-offer label and displayed estimate before creating it; ordinary General Purpose serverless is different. Prefer Microsoft Entra authentication. For a short public-endpoint exercise, allow only the Azure VM's public IPv4 in the SQL server firewall; leave **Allow Azure services and resources to access this server** disabled. Use the Azure VM and a current Microsoft `sqlcmd` client with encrypted certificate-validated connections to verify `SELECT @@VERSION;`. Recheck that rule if the source IP changes. For production, use private endpoints and account for their cost.

The web template does not depend on Azure SQL. Serverless auto-pause/resume delays would also affect application health if a future application used it.

### PostgreSQL container on GCP VM

On the GCP Linux VM, install Docker Engine and the Compose plugin using Docker's official Ubuntu instructions. Copy `database/compose.yml` to `~/database/compose.yml` with `scp`. On that VM:

```bash
cd ~/database
read -rsp 'Postgres password: ' POSTGRES_PASSWORD; echo
export POSTGRES_PASSWORD
sudo --preserve-env=POSTGRES_PASSWORD docker compose up -d
sudo --preserve-env=POSTGRES_PASSWORD docker compose exec postgres psql -U projectuser -d projectdb
```

Inside `psql`:

```sql
CREATE TABLE IF NOT EXISTS project_demo (id integer PRIMARY KEY, message text NOT NULL);
INSERT INTO project_demo VALUES (1, 'Multi cloud backup test') ON CONFLICT (id) DO NOTHING;
SELECT * FROM project_demo;
\q
```

Port 5432 binds only to loopback and should never be opened in the cloud firewall. The named volume persists container restarts, but is lost if the underlying VM/disk is deleted. This e2-micro has little RAM; keep the dataset small and inspect memory usage. A password environment variable is acceptable for this disposable lab, while production should use a proper secret mechanism. The `.env` file, if used, must have mode 600 and be ignored by Git.

## 10. Backup restore and database portability

Terraform recreates infrastructure; it does not replicate your database rows. Demonstrate a measured backup-and-restore workflow. The safe scope is a tiny PostgreSQL dataset restored into a separate empty PostgreSQL database. Azure SQL requires its own T-SQL schema and SQL Server-compatible migration/export path; a PostgreSQL dump cannot be restored to Azure SQL.

On the GCP Linux VM with the database running:

```bash
cd ~/database
mkdir -p backups
chmod 700 backups
sudo --preserve-env=POSTGRES_PASSWORD docker compose exec -T postgres pg_dump -U projectuser -d projectdb -Fc > backups/projectdb.dump
sha256sum backups/projectdb.dump > backups/projectdb.dump.sha256
sudo --preserve-env=POSTGRES_PASSWORD docker compose exec -T postgres createdb -U projectuser restorecheck
sudo --preserve-env=POSTGRES_PASSWORD docker compose exec -T postgres pg_restore -U projectuser -d restorecheck < backups/projectdb.dump
sudo --preserve-env=POSTGRES_PASSWORD docker compose exec -T postgres psql -U projectuser -d restorecheck -c 'SELECT * FROM project_demo;'
```

Use a fresh database name if repeating the exercise. Record row count and ordered row contents before/after, backup timestamp, backup checksum and restore duration. A backup-file checksum checks transfer integrity; it alone does not prove the restored rows are correct. This is a same-engine restore exercise, not evidence of cross-cloud recovery until you repeat the restore on an independently provisioned destination in another provider.

Copy the tiny dump and checksum to your laptop with `scp`. From PowerShell, upload copies to all three private storage destinations (replace names from `terraform output storage`):

```powershell
aws s3 cp .\backups\projectdb.dump s3://YOUR_AWS_BUCKET/backups/projectdb.dump
az storage blob upload --auth-mode login --account-name YOUR_AZURE_ACCOUNT --container-name backups --name projectdb.dump --file .\backups\projectdb.dump
gcloud storage cp .\backups\projectdb.dump gs://YOUR_GCP_BUCKET/backups/projectdb.dump
```

Azure upload requires Storage Blob Data Contributor (a control-plane Contributor role alone does not grant data access). Allow role-assignment propagation time. Upload the checksum too, then download one copy to a different local filename and compare `Get-FileHash -Algorithm SHA256`. For sensitive data, encrypt backups before upload and keep the key separately. Use only dummy data here.

For cross-cloud recovery, download a stored dump, provision a separate PostgreSQL target with compatible version/extensions, restore to an empty database and verify contents before any application cutover. You can use the optional RDS PostgreSQL target through its EC2 VM, with its own credentials and CA validation. Measure RPO as the gap between failure and the most recent usable backup, and RTO from failure to verified restored service. Do not label this continuous replication. Copying object storage does not replicate database transactions or guarantee consistency.

## 11. Failover and recovery demonstration

1. Verify direct `/health` on each origin. Start the real DNS controller and local monitoring. Confirm DNS currently resolves to AWS using `Resolve-DnsName app.yourdomain.com`.
2. Record start time and baseline webpage/provider. On AWS over SSH run `sudo systemctl stop nginx`.
3. Watch `probe_success`, local Prometheus alert state and controller logs. After consecutive failed checks and cooldown, the controller should select Azure. Check the Cloudflare record and DNS from a resolver you control; refresh the webpage after cache expiry. Record actual outage-to-Azure time.
4. Stop Nginx on Azure. Verify the controller selects GCP and record the measured delay. If all origins are unavailable, DNS is intentionally left unchanged; record this limitation.
5. Run `sudo systemctl start nginx` on AWS and Azure. After confirmed health and cooldown, observe preferred-primary failback. Record each measured result.
6. Capture direct probes, DNS record before/after, dashboard, alert and controller log. Restore all services and stop the controller before cleanup.

This simulates application-service outages, not real regional outages. Expected outcomes are test criteria, not completed results. If the laptop sleeps, no DNS decisions or monitoring occur. Browser caching, OS resolver caching and open connections can delay what you see; record these factors instead of reporting an invented failover time.

## 12. CI and version control

Push the extracted project to a private repository after reviewing `.gitignore`. The supplied GitHub Actions workflow checks formatting and configuration validation only. It does not run apply and needs no cloud credentials. Commit `.terraform.lock.hcl` after initialization. Check your repository's Actions billing allowance. For a later deployment pipeline, add cloud OIDC federation, encrypted remote state and a reviewed saved plan before apply. These are future work, not delivered features.

## 13. Troubleshooting

| Symptom | Check |
|---|---|
| Terraform authorization error | AWS profile/session, Azure subscription, GCP ADC, required roles and enabled APIs |
| Bucket/account name already exists | Choose a fresh global `name`; recreating resources can change IPs |
| Azure SKU unavailable | Subscription quota, East US availability and eligible free SKU; check cost before substituting |
| Website timeout | Startup logs, port 80 firewall, routing and current public IP |
| SSH timeout | Your current public IPv4 matches `admin_cidr`; correct key/user; no VPN IP change |
| DNS not switching | Laptop awake, API token scoped correctly, DNS-only A record, direct health targets and controller logs |
| Dashboard shows exporter UP but outage persists | Query `probe_success`, not only `up` |
| SQL connection failure | DB endpoint, engine-specific client, TLS CA, credentials and narrow firewall rule |
| Unexpected charge | Public IPs, disk type, managed DBs, snapshots, trial expiry, transfer and lingering resources |
| Storage cannot be deleted | Objects/versions, retention/soft-delete settings and manual databases; inspect before removing data |

## 14. Cleanup

Save your screenshots and dummy test evidence first. Stop the DNS controller with Ctrl+C and remove the dedicated test DNS record so it cannot point at a reassigned public IP. Stop local containers from the package root:

```powershell
docker compose -f monitoring/compose.yml down
Set-Location terraform
terraform plan -destroy -out=cleanup.tfplan
terraform show cleanup.tfplan
terraform apply cleanup.tfplan
```

Terraform intentionally does not force-delete nonempty buckets. Before destroy, list and remove only the dummy objects you uploaded from this lab's exact bucket/container names after reviewing whether you still need them. Empty versioned objects or retained data if applicable. Do not remove unrelated data. Optional console-created RDS/SQL resources can block VPC/resource-group deletion; delete those first, respecting any retained backups/snapshots. Delete the manually added second AWS subnet and DB subnet group. Deleting the Azure resource group removes contained SQL resources too, so export any needed evidence beforehand.

Check all cloud consoles for remaining IPs, disks, storage accounts, snapshots, managed databases and backups, including soft-deleted data. Verify billing the following day. Docker volumes remain after `down`; only add `-v` when you deliberately want to erase local monitoring history. Revoke the Cloudflare token and remove session credentials when finished. Never delete Terraform state before cloud cleanup is verified.

## 15. What to submit

Fill `SUBMISSION.md` with your student details, repository link, version numbers, account eligibility, screenshots and measured test results. Use `Project_Submission.html` as a formatted report: open it in a browser and print to PDF after entering your actual results. Submit the source ZIP, completed report and evidence folder. Clearly list free-tier adaptations against the original brief: local DNS controller, no managed LBs, CLI credential stores rather than Vault, independent databases and backup/restore rather than continuous cross-engine replication, and local health monitoring rather than complete CPU/RAM/cost telemetry.

## 16. Official references and installation links

Account offers and pricing should be rechecked before deployment. Verified 22 October 2026.

- AWS Free Tier: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier.html
- AWS EC2 free-tier eligibility: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html
- Azure free services: https://azure.microsoft.com/en-us/pricing/free-services
- Azure SQL free offer: https://learn.microsoft.com/en-us/azure/azure-sql/database/free-offer?view=azuresql
- GCP Free Tier: https://docs.cloud.google.com/free/docs/free-cloud-features
- GCP external IP pricing: https://cloud.google.com/vpc/network-pricing
- Cloudflare Load Balancing pricing: https://www.cloudflare.com/plans/
- Cloudflare DNS update API: https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/edit/
- Terraform installation: https://developer.hashicorp.com/terraform/install
- Docker Desktop on Windows: https://docs.docker.com/desktop/setup/install/windows-install/
- Docker Engine on Ubuntu: https://docs.docker.com/engine/install/ubuntu/
- AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- Azure CLI: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows
- Google Cloud CLI: https://cloud.google.com/sdk/docs/install
- Python: https://www.python.org/downloads/windows/
- Git: https://git-scm.com/downloads/win
- PowerShell 7: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows
- Prometheus multi-target probing: https://prometheus.io/docs/guides/multi-target-exporter/
- PostgreSQL dump documentation: https://www.postgresql.org/docs/16/app-pgdump.html
