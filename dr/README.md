# Sprint 4 Disaster Recovery and Backup Replication

This package extends the existing multi-cloud Terraform project. It uses PostgreSQL 16 on GCP as the source, an independent PostgreSQL 16 container on the existing AWS VM as the recovery target, and private AWS S3, Azure Blob and GCS for backup copies.

## Scope

The scripts automate scheduled logical snapshots and cross-cloud backup copies. They do not implement continuous row-level replication, managed database promotion or application cutover. Azure SQL uses a different engine and cannot consume PostgreSQL dumps as native replicas. If continuous database replication is mandatory, an additional same-engine replication implementation is required.

Terraform manages VMs, networks and private storage. Bash scripts perform backup and restoration; terraform apply alone does not preserve database rows. Managed RDS, Azure SQL and Cloud SQL are not created by this kit. The static Nginx application does not use the database.

## 1 Install and configure

Extract the package into ~/multi-cloud-project/dr on the local WSL workstation. Use Bash, not PowerShell.

```bash
cd ~/multi-cloud-project
cp dr/dr.env.example dr/dr.env
terraform -chdir=terraform output origin_ips
terraform -chdir=terraform output storage
```

Edit dr/dr.env with real storage names and current source/target IPs. The supplied IPs are last-reported values, not newly verified addresses. The Azure value is its storage account name. Keep secrets out of this file and Git.

Required local tools: AWS CLI, Azure CLI, Google Cloud CLI, Python 3, SSH, flock, sha256sum and cmp. Authenticate all three CLIs. AWS credentials loaded from Vault can be used; temporary credentials also need a session token. Azure ARM_* variables used by Terraform do not automatically log the az CLI in. GCP GOOGLE_CREDENTIALS used by Terraform does not automatically authenticate gcloud. Use az login and gcloud auth login, or separately configured approved service identities.

```bash
aws sts get-caller-identity
az account show --output table
gcloud auth list
```

Azure uploads/downloads require Storage Blob Data Contributor or equivalent scoped data permissions. The runner does not fetch/renew Vault or cloud credentials. Do not use the Vault administrator token for scheduling. Short-lived credentials must remain valid or be renewed.

Load the SSH key into an agent, verify host keys in normal SSH connections, then test noninteractive access:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/multicloud
ssh -i ~/.ssh/multicloud -o BatchMode=yes labadmin@34.41.25.119 'sudo -n docker ps'
ssh -i ~/.ssh/multicloud -o BatchMode=yes ubuntu@184.197.92.35 'sudo -n docker ps'
```

The scripts require noninteractive Docker access through sudo -n. If your identity cannot do this, use an administrator-approved service arrangement rather than granting broad privileges to bypass the error.

## 2 Prepare source evidence

From the local project root:

```bash
ssh -i ~/.ssh/multicloud labadmin@34.41.25.119 \
  'sudo docker exec -i database-postgres-1 psql -X -v ON_ERROR_STOP=1 -U projectuser -d projectdb' \
  < dr/prepare-source.sql
```

This adds a dummy public.dr_evidence table with two rows. Freeze writes to this test table during the backup. pg_dump creates an internally consistent snapshot, but expected.csv is collected by a separate query; concurrent edits could invalidate the comparison. Real applications need shared-snapshot or application-level consistency verification. The dummy-row comparison does not validate every row in every table.

## 3 Prepare an independent AWS recovery target

Install Docker Engine and the Compose plugin on the AWS Ubuntu VM if absent, following https://docs.docker.com/engine/install/ubuntu/. Keep Nginx running. Check free disk and memory before adding this container.

From your laptop:

```bash
ssh -i ~/.ssh/multicloud ubuntu@184.197.92.35 'mkdir -p ~/dr-target'
scp -i ~/.ssh/multicloud dr/target/compose.yml ubuntu@184.197.92.35:/home/ubuntu/dr-target/compose.yml
ssh -i ~/.ssh/multicloud ubuntu@184.197.92.35
```

On AWS:

```bash
cd ~/dr-target
read -rsp 'Recovery database password: ' DR_POSTGRES_PASSWORD
echo
export DR_POSTGRES_PASSWORD
sudo --preserve-env=DR_POSTGRES_PASSWORD docker compose up -d
sudo docker exec postgres-dr pg_isready -U dradmin -d postgres
```

Wait for readiness, then exit back to the laptop. The separate named volume holds the target data. Only localhost port 5433 is published; do not open a public database firewall port. The 256 MB limit is for the tiny demonstration dataset. Larger restores may need more memory. Existing VM usage, disk, backup operations and transfers can incur costs.

## 4 Create and replicate the first backup

From the local project root:

```bash
bash dr/backup.sh
```

The runner creates a timestamped directory under dr/backups with a custom-format database dump, archive listing, ordered dummy rows, backup-start time and SHA256 checksums. It uploads each file to all three providers under sprint4/RUN_ID/. A COMPLETE marker is uploaded last in each destination. A partial copy does not receive that marker. All destinations are attempted; any failure makes the overall job fail. last-successful-run.txt is updated only after all three copies succeed.

Record the RUN_ID. Confirm payloads and markers in the cloud consoles, or use:

```bash
source dr/dr.env
RUN_ID="$(cat dr/last-successful-run.txt)"
aws s3 ls "s3://$AWS_BUCKET/sprint4/$RUN_ID/"
az storage blob list --auth-mode login --account-name "$AZURE_STORAGE_ACCOUNT" --container-name "$AZURE_CONTAINER" --prefix "sprint4/$RUN_ID/" --output table
gcloud storage ls "gs://$GCP_BUCKET/sprint4/$RUN_ID/"
```

Use dummy data and private storage. The database-only dump does not preserve cluster-global roles or external dependencies. The restore uses no-owner and no-acl for this disposable test; production access controls require a separate recovery plan.

## 5 Schedule automated backup replication

In the same authenticated local terminal:

```bash
bash dr/schedule.sh
```

It runs immediately, then waits 900 seconds after each cycle. The actual start-to-start interval is 15 minutes plus job duration, not exactly 15 minutes. Inspect logs in another terminal:

```bash
tail -f ~/multi-cloud-project/dr/logs/backup.log
```

Keep the laptop, WSL, Docker Desktop, SSH agent and cloud sessions available. Failed jobs are logged but no external notification is configured. Monitor the age of the last successful backup, not only whether a process is running. Stop with Ctrl+C before the controlled outage test.

This kit does not prune backups. Keep the demonstration short. Before unattended operation, define and test local retention and cloud object lifecycle policies, preserving known-good copies. A stale credential or sleeping laptop can break the intended recovery-point target.

## 6 Test recovery with the source unavailable

Confirm a completed remote backup exists. Record the UTC failure time. On the GCP VM stop only the PostgreSQL container:

```bash
sudo docker stop database-postgres-1
date -u
```

Do not delete the database volume or VM. This simulates a database-service outage, not a full provider outage.

From the local project root:

```bash
RUN_ID="$(cat dr/last-successful-run.txt)"
bash dr/restore.sh aws "$RUN_ID"
```

The script downloads a completed backup from S3 without contacting the source database, checks SHA256 values, creates a NEW uniquely named database on the AWS target and restores it. It exits on restore errors and compares the ordered recovered dummy rows to the expected rows. It never drops or overwrites an existing database.

Success writes result.txt under dr/recovered with the target database, verification timestamp and restore-workflow duration. A failed attempt can leave a new database and staging directory for diagnosis; do not silently promote an incomplete restore.

To prove the Azure copy is independently usable while the source is stopped:

```bash
bash dr/restore.sh azure "$RUN_ID"
```

This restores into another new AWS database. GCS can also be tested:

```bash
bash dr/restore.sh gcp "$RUN_ID"
```

A GCS restore is not independent of GCP if GCP storage itself is unavailable. Use an AWS or Azure copy for that scenario. Checksums detect file transfer corruption; they do not authenticate a maliciously replaced backup.

## 7 Measure RPO and RTO

Record the last usable backup snapshot/start time, destination completion time, simulated failure time, restore start and verification completion.

- Observed data-loss window: failure time minus usable backup snapshot time. The recorded start time approximates the snapshot; use more precise evidence for formal measurements.
- The script duration measures download/restore/verification only.
- Full service RTO begins at the failure and ends after the application uses recovered data successfully.

A 15-minute schedule does not guarantee a 15-minute RPO. Backup duration, failed jobs and upload delay can extend the window. The Nginx page is static, so its DNS failover does not demonstrate database cutover. Do not modify a health file to claim a working database-backed application.

For a future real application: fence the former writer, verify the recovered database, update application connection settings, test transactions, then route traffic. Avoid two active writers. This kit leaves application cutover manual and separate.

## 8 Restore normal operation and retain evidence

On GCP:

```bash
sudo docker start database-postgres-1
sudo docker exec database-postgres-1 pg_isready -U projectuser -d projectdb
```

The controlled restore exercise does not change source data. In a real incident, if the recovered system accepted new writes, do not fail back to a stale source without reconciliation.

Collect backup logs, markers from each provider, checksums, source/target dummy rows, outage timestamps and result.txt. Remove temporary target dump directories only after reviewing what must be retained. Docker Compose down preserves its named volume; removing volumes deletes database data. Terraform infrastructure destruction can also remove the VM disk containing recovery data. Preserve remote backups first.

## Sprint deliverables

| Task | Lab mechanism | Remaining limitation |
|---|---|---|
| Automated cross-cloud data replication | Scheduled logical snapshots copied to three object stores | Not continuous database replication |
| Terraform-supported backup infrastructure | Existing Terraform-managed VMs networks and private storage | Data jobs run outside Terraform |
| Recovery in a secondary provider | Restore GCP PostgreSQL data into new AWS PostgreSQL database | Manual target setup and application cutover |
| Integrity verification | SHA256, successful pg_restore and ordered dummy-row comparison | Extend checks for real schemas and concurrent writes |
| DR plan | This runbook and measured evidence | Execute tests before claiming results |

## References

- https://www.postgresql.org/docs/16/app-pgdump.html
- https://www.postgresql.org/docs/16/app-pgrestore.html
- https://www.postgresql.org/docs/16/backup-dump.html
- https://www.postgresql.org/docs/16/high-availability.html
- https://developer.hashicorp.com/terraform/language/provisioners
- https://docs.docker.com/engine/install/ubuntu/
