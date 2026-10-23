# Multi Cloud Deployment and Management with Terraform

## Student and project details

Student name: [Enter name]  
Registration number: [Enter number]  
Department and institution: [Enter details]  
Guide or supervisor: [Enter name]  
Submission date: [Enter date]  
Source repository: [Enter URL]  
Demonstration video: [Enter URL if required]

## Abstract

This project studies infrastructure deployment across Amazon Web Services, Microsoft Azure and Google Cloud using Terraform. Provider-specific modules define virtual machines, networks, access rules and private object storage. A common startup procedure installs a small Nginx website with an origin-specific health endpoint. Local Prometheus and Grafana configurations observe HTTP health and response time. A Python controller probes the origins and updates a Cloudflare DNS record to demonstrate active-passive recovery from a web-service outage.

The design targets a student laboratory using eligible account allowances and trial credits. Managed load balancers and production database replication are outside the baseline. Optional database exercises use Amazon RDS PostgreSQL, Azure SQL and PostgreSQL in a GCP virtual machine. Backup and restore are tested separately from web routing, with actual measurements entered in the results section after execution.

## Problem statement

Manual configuration across different cloud providers can create inconsistent networks, access controls and application deployments. Recovery procedures are difficult to repeat when infrastructure and application state are undocumented. The project investigates how reusable infrastructure definitions, explicit health probes and a recorded recovery procedure can make a small multi-cloud deployment easier to reproduce and assess.

## Objectives

1. Define repeatable VM, networking and storage configurations for three cloud providers.
2. Deploy a common demonstration webpage and identify the responding provider.
3. Demonstrate application-service failover with direct health probes and a DNS update.
4. Observe HTTP availability and latency locally and demonstrate a local alert.
5. Demonstrate a PostgreSQL backup and verified restore with private backup copies.
6. Record account eligibility, cost controls, results, limitations and cleanup evidence.

## Proposed architecture

Cloudflare hosts a dedicated DNS-only A record. It points to one origin at a time, in AWS us-east-1, Azure East US or GCP us-central1. The local controller prefers AWS, then Azure, then GCP. Three consecutive failures are required before abandoning the active origin; three consecutive successes qualify a destination. A cooldown reduces frequent changes. Local blackbox probes supply Prometheus metrics, which Grafana displays. Private S3, Blob and Cloud Storage destinations hold small dummy backup files.

The local machine is a dependency for monitoring and failover decisions. DNS changes are subject to caching and do not move existing connections. HTTP serves only a public demonstration page. Database engines are independent of the static webpage.

## Technology and resource configuration

| Layer | Configuration |
|---|---|
| Infrastructure | Terraform root configuration and separate AWS Azure and GCP modules |
| AWS | Ubuntu t3.micro, 8 GB gp3 boot disk, VPC subnet route and internet gateway, private S3 bucket |
| Azure | Ubuntu Standard_B1s, 30 GB Standard LRS OS disk, VNet subnet NSG NIC and Standard public IP, private Blob container |
| GCP | Ubuntu e2-micro, 30 GB pd-standard disk, custom VPC subnet and firewall, regional Standard Cloud Storage bucket |
| Application | Nginx static page and provider-specific health text |
| Routing | Cloudflare free DNS and a local Python API controller |
| Monitoring | Prometheus blackbox exporter and Grafana on the workstation |
| Optional databases | RDS PostgreSQL Azure SQL free offer and PostgreSQL Docker on GCP |
| Version control | Git and GitHub Actions formatting and configuration validation |

Record installed tool versions and resolved provider versions here: [Enter actual versions]. Commit the provider lock file. Public images and cloud image versions should be recorded alongside test evidence because image families can change.

## Relationship to the original project brief

| Original requirement | Student lab adaptation | Completion evidence |
|---|---|---|
| Terraform deployment across three clouds | Three provider modules for web infrastructure and storage | [Plan apply outputs and console screenshots] |
| Load balancing and automatic failover | Active-passive DNS controller; no managed traffic balancing | [Outage logs and DNS changes] |
| Vault or similar credential handling | Local CLI credential stores and short-lived sessions; Vault not implemented | [Redacted identity verification] |
| Database replication and disaster recovery | Same-engine backup and restore exercise; no PostgreSQL to Azure SQL replication | [Dump checksum and restored row evidence] |
| Monitoring usage alerts and costs | HTTP health and latency plus local alert; provider consoles for cost review | [Dashboards local alert and billing views] |
| Deployment automation and CI | Startup scripts and validation-only workflow; apply is manually reviewed | [Workflow result and apply evidence] |
| Production readiness | Educational prototype requiring further engineering | [Documented limitations] |

Obtain the evaluator's acceptance of these cost-driven scope adaptations. If managed load balancing, Vault, continuous replication, CPU/RAM monitoring, external notifications or CI apply are mandatory, implement and demonstrate them separately before claiming completion.

## Implementation methodology

### Phase 1 Workstation and cloud access

Install the required command-line tools and Docker Desktop. Enable MFA, choose dedicated project resources and inspect account offers. Authenticate each CLI without storing credentials in source files. Generate a passphrase-protected SSH key and restrict SSH access to the workstation's current public IP. Initialize the repository and review ignore rules.

### Phase 2 Infrastructure and application

Set the unique resource prefix, subscription and project identifiers and SSH key path. Run formatting, initialization, validation and plan review. Check the price of every resource, including external IPs and disks. Apply the reviewed plan and wait for startup scripts. Verify the provider-specific webpage and health endpoint for every VM. Record startup failures and corrective actions where applicable.

### Phase 3 DNS routing

Create the dedicated DNS-only A record and a scoped Cloudflare API token. Configure direct origin addresses in the controller. Run a dry demonstration before enabling API writes. Check the actual record and origin webpage. Run one controller and keep the workstation awake throughout testing.

### Phase 4 Monitoring

Replace the monitoring IP placeholders and start the local containers. Confirm successful probes, configure the Grafana Prometheus data source and add health and latency panels. Trigger an application outage and observe the local alert. External notification delivery and billing metrics are not part of the baseline configuration.

### Phase 5 Data recovery

Create a tiny dummy PostgreSQL table, record its rows and take a custom-format dump. Save the checksum and copy the backup to private object storage. Download a copy, verify its checksum and restore into a fresh PostgreSQL database. Compare restored contents with the source. Report separately whether the restore destination was local to the source or in a different cloud.

### Phase 6 Testing documentation and cleanup

Perform controlled service outages with timestamps. Restore each service, observe failback and collect evidence. Update the report with actual results. Delete optional databases and dummy backup objects before destroying managed infrastructure. Remove test DNS, revoke the API token and confirm that no unintended resources remain.

## Security controls

The baseline uses MFA-enabled accounts, local authenticated CLI sessions, passphrase-protected SSH keys, a workstation-only SSH ingress rule, private object storage, required AWS IMDSv2 and localhost-only monitoring ports. Database ports remain closed to the public internet. The optional RDS security group permits only the EC2 application security group; the optional Azure SQL exercise permits only the required source IP.

Terraform state, plans, tokens, key files and secret variable files must remain private. Redact secrets and identifying account information in screenshots. HTTP is limited to dummy demonstration content. Production work would require secured origin TLS, a stronger controller deployment, locked encrypted remote state, more precise IAM and a managed secret lifecycle.

## Test plan and recorded results

The following are acceptance criteria. Enter measurements only after executing each test; blank cells do not indicate success.

| ID | Test and expected observation | Actual result and evidence |
|---|---|---|
| T01 | Formatting and provider validation complete successfully | [Enter result versions and log] |
| T02 | All three direct health endpoints return the correct provider | [Enter response and screenshot] |
| T03 | Baseline DNS points to AWS and webpage identifies AWS | [Enter DNS evidence] |
| T04 | Stop AWS Nginx and observe Azure selection | [Start time switch time elapsed and evidence] |
| T05 | Stop Azure Nginx while AWS is down and observe GCP selection | [Start time switch time elapsed and evidence] |
| T06 | Restore AWS and observe preferred-primary failback | [Health confirmation change time and evidence] |
| T07 | All origins unhealthy causes no new DNS destination selection | [Log and existing DNS record] |
| T08 | Local health metric becomes zero and alert fires during outage | [Dashboard and alert screenshot] |
| T09 | Downloaded backup checksum matches source backup | [Checksum and location] |
| T10 | Restore to empty PostgreSQL database preserves expected rows | [Rows count and duration] |
| T11 | Repository CI checks pass without cloud credentials | [Workflow URL] |
| T12 | Cloud resources and test DNS are cleaned up | [Console and billing review] |

## Recovery measurements

Failure simulation: [Application service stopped on provider and exact UTC time].  
Confirmed service recovery: [Provider and exact UTC time].  
Measured web recovery time: [Seconds and measurement method].  
Latest usable backup time: [UTC time].  
Data recovery point objective observation: [Failure time minus latest usable backup time].  
Data restore completion time: [UTC time and validation performed].  
Measured data recovery duration: [Seconds or minutes].  
Recovery destination: [Cloud provider database and version].

Report application DNS recovery separately from data recovery. Probe timing plus TTL is an estimate, not an observed guarantee. A same-VM restore demonstrates the backup procedure but does not by itself demonstrate disaster recovery after a provider outage.

## Cost review

| Provider | Offer and expiry | Planned covered usage | Uncovered items | Actual spend after test |
|---|---|---|---|---|
| AWS | [Enter] | [Enter] | [IP storage DB transfer] | [Enter] |
| Azure | [Enter] | [Enter] | [IP disk SQL operations] | [Enter] |
| GCP | [Enter] | [Enter] | [External IPv4 transfer] | [Enter] |
| Cloudflare | Free DNS | DNS | [Domain registration if applicable] | [Enter] |

Eligible allowances and credits are account-specific. The architecture must not be described as permanently free. Budget notifications do not guarantee that charges are blocked. Include screenshots showing remaining credit and resource deletion without exposing payment details.

## Sprint schedule

| Sprint | Planned workload | Output |
|---|---|---|
| 1 | 20 hours | Repository tools accounts access and secret handling |
| 2 | 20 hours | Terraform networks VMs storage and common webpage |
| 3 | 20 hours | Cloudflare record controller and outage demonstration |
| 4 | 20 hours | Optional database and verified backup restore |
| 5 | 20 hours | Local dashboards alert and cost review |
| 6 | 20 hours | Validation workflow test evidence report and cleanup |

Total planned effort is 120 hours, matching the six-sprint brief. Record actual effort separately if required by the institution.

## Limitations and future work

The system has one VM per cloud, a local decision-maker and DNS caching delays. It has no within-cloud autoscaling or managed load balancing. The static website is independent of databases. It does not provide continuous cross-cloud database replication, transaction consistency or automated database promotion. Local HTTP probing does not provide full VM performance or cost telemetry. Optional manual database resources are not fully managed by the supplied Terraform state.

Future work includes approved managed health-based routing, remote controller supervision, origin TLS, same-engine database replication with explicit consistency and promotion rules, encrypted locked remote state, OIDC-based deployment workflows, private monitoring, external alert delivery and measured recovery under more realistic failure conditions.

## Conclusion

The proposed laboratory provides a repeatable framework for deploying and observing web infrastructure across three cloud providers. Its evaluation depends on measured deployment, outage and restore evidence. After testing, summarize the observed recovery behavior, actual cost and remaining gaps here: [Enter the conclusion supported by your results].

## Evidence index

E01 Tool versions and redacted identity checks  
E02 Terraform plan and apply summary  
E03 Three provider resource views  
E04 Three direct health responses  
E05 DNS record baseline and changes  
E06 Controller timestamps  
E07 Grafana dashboard and Prometheus alert  
E08 Database source data backup checksum and restored data  
E09 CI workflow result  
E10 Budget eligibility actual spend and cleanup proof

Store these in an `evidence/` folder with matching labels. Include no tokens, private keys, database passwords or payment details.

## References

Official sources consulted on 22 October 2026. Recheck offers before execution.

1. AWS Free Tier: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier.html
2. AWS EC2 eligibility: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html
3. Azure free services: https://azure.microsoft.com/en-us/pricing/free-services
4. Azure SQL free offer: https://learn.microsoft.com/en-us/azure/azure-sql/database/free-offer?view=azuresql
5. GCP Free Tier: https://docs.cloud.google.com/free/docs/free-cloud-features
6. GCP network pricing: https://cloud.google.com/vpc/network-pricing
7. Cloudflare plans: https://www.cloudflare.com/plans/
8. Cloudflare DNS API: https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/edit/
9. Terraform installation: https://developer.hashicorp.com/terraform/install
10. Prometheus multi-target exporter: https://prometheus.io/docs/guides/multi-target-exporter/
