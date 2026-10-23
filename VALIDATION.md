# Validation record

Prepared 22 October 2026.

- Terraform HCL parsing and recursive formatting check passed using the locally available Terraform command.
- Seven simulated Python controller tests passed: failover to Azure, failover to GCP, no update when all origins fail, tolerance of a short failure, preferred-primary failback, rejection of a proxied record and no write when the API fails. These use mocked probes and API calls; they do not demonstrate real DNS recovery.
- Docker Compose structural checks passed for monitoring and PostgreSQL with temporary dummy password environment values. No containers were started by these checks.
- HTML outputs were structurally checked for titles, tables, placeholder content and self-contained styling. No DOCX or PDF is included.
- Terraform initialization was attempted but failed because registry.terraform.io could not be resolved from this environment. Provider schema validation, planning and cloud deployment were not performed. Re-run init and validate before using the configuration. No provider lock file was generated.
- No cloud accounts, credentials or Cloudflare tokens were used. No real failover, restore, billing or cleanup outcome is claimed.

Run `python tests/test_failover.py` to repeat the simulated controller tests. Run `terraform fmt -check -recursive`, `terraform init` and `terraform validate` from `terraform/` to complete local validation with registry access. Follow SETUP.md for reviewed deployment and real evidence collection.
