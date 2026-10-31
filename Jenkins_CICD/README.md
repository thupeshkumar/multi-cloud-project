# Jenkins CI and Application Delivery for the Multi Cloud Project

This integrates Jenkins with the existing repository at https://github.com/thupeshkumar/multi-cloud-project.

## Scope

CI checks Terraform formatting and provider-schema validity, plus deployment-script syntax. CD deploys a versioned static Nginx page and the expected health text to the existing AWS, Azure and GCP VMs after explicit approval. The page displays the Git revision and provider for viva evidence.

This pipeline does not run terraform plan/apply, alter DNS, restart databases or move Terraform state. Automated infrastructure deployment requires a separately configured state backend, cloud authentication and change review. An empty Jenkins workspace must not apply this project without its existing state, or Terraform may attempt to recreate resources.

The workflow implements continuous integration and approval-based continuous delivery. It does not deploy every commit automatically without review.

## Package installation

Copy the package contents into the ROOT of ~/multi-cloud-project, preserving your existing terraform/, monitoring/, failover/ and dr/ folders. Added files:

- Jenkinsfile
- jenkins/Dockerfile
- jenkins/compose.yml
- jenkins/targets.txt
- scripts/jenkins-deploy.sh
- app/index.html.template

Review existing files before replacing any file with the same name. The application deployment deliberately updates /var/www/html/index.html and /health on each VM. It does not deploy a database-backed application.

## 1 Review target servers

Edit jenkins/targets.txt. The defaults reflect the latest supplied IPs:

    aws ubuntu 184.197.92.35
    azure labadmin 20.80.177.122
    gcp sivamcomz 34.56.109.225

Use current Terraform outputs and working SSH usernames. Keep ports 22 restricted to your administrator public IP and port 80 available for the public dummy webpage.

Before deployment, all three VMs must already have Nginx running. Test from the laptop:

```bash
ssh -i ~/.ssh/multicloud ubuntu@184.197.92.35 'sudo -n nginx -t'
ssh -i ~/.ssh/multicloud labadmin@20.80.177.122 'sudo -n nginx -t'
ssh -i ~/.ssh/multicloud sivamcomz@34.56.109.225 'sudo -n nginx -t'
```

Jenkins needs a deployment identity permitted to validate Nginx and install the two application files. This disposable lab uses the existing VM administrator key and sudo. For shared/production use, use a dedicated deploy account with narrowly controlled commands. Never reuse the restricted metrics-tunnel key: that key intentionally cannot run deployment commands.

## 2 Start local Jenkins through Docker Desktop

Ensure Docker Desktop runs Linux containers. From the project root:

```bash
docker compose -f jenkins/compose.yml up -d --build
```

The custom image installs Terraform 1.13.5, Git, SSH client, shellcheck and the required Jenkins plugins. It downloads Terraform from the official release service and checks the published SHA256 checksum. The first build needs internet access.

Jenkins listens on laptop localhost port 8080, with a persistent named volume. No cloud VM or Docker socket mount is required. If 8080 is occupied, change only the host mapping, for example 127.0.0.1:8082:8080.

Open http://localhost:8080. Obtain the initial setup password locally:

```bash
docker exec multicloud-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Use it in the setup wizard, create your own administrator account, and complete setup. Do not share this password or include it in screenshots.

Under Manage Jenkins > Plugins, confirm Pipeline, Git, Credentials Binding and SSH Agent are installed. The Dockerfile requests them; restart Jenkins if the UI asks. For this local single-user lab, configure one executor on the built-in node if it has zero executors. A shared deployment should use a separate agent rather than executing arbitrary builds on the controller.

## 3 Configure repository and SSH credentials

Open Manage Jenkins > Credentials > System > Global credentials. Restrict access to this Jenkins instance and the trusted job.

### GitHub repository credential

For a private repository, add a GitHub read credential usable by the Git plugin, such as a username and fine-grained personal access token with repository contents read access. Use ID github-read. This is for checkout only, not a credential to deploy cloud resources. A public repository can be checked out without this credential.

### VM SSH credential

Add kind SSH Username with private key:

- ID: cloud-vm-ssh
- Username: ubuntu (the deployment script explicitly selects the correct username per host)
- Private key: the key whose public key is authorized on all three VMs
- Passphrase: enter it if the private key is encrypted

For the current lab that is normally ~/.ssh/multicloud. Enter it only in Jenkins Credentials, never in the repository, console output or a screenshot. If the three clouds use different keys, adapt the pipeline to separate per-cloud credential bindings before deployment. SSH Agent supports credentials for pipeline SSH commands.

### Verified host keys

Use your normal SSH client to verify the fingerprint of each current VM through a trusted cloud-console channel. In particular, resolve any changed-host-key warnings before continuing. Do not accept unverified ssh-keyscan results as proof of server identity.

Upload the resulting trusted ~/.ssh/known_hosts as a Jenkins Secret file:

- ID: cloud-known-hosts

The script enables strict host-key checking and uses this file. Re-upload the verified file if a VM is legitimately replaced. Keep all known_hosts entries for the target IPs, including newly verified keys.

## 4 Commit the pipeline code

Review git status and the ignore rules. Keep .env, cloud credentials, private keys, tfvars, state, plans and backups out of Git. Commit the new pipeline/app files and the Terraform lock file if already generated. Push to the intended main branch after reviewing the staged diff.

The workflow executes code from your repository. Use only a trusted protected branch for this credential-bearing job. Do not run untrusted pull-request Jenkinsfiles with VM credentials.

## 5 Create the Jenkins job

1. New Item > name multi-cloud-project > Pipeline.
2. Pipeline definition: Pipeline script from SCM.
3. SCM: Git.
4. Repository URL: https://github.com/thupeshkumar/multi-cloud-project.git
5. Credentials: github-read if the repository is private.
6. Branch specifier: */main, or your actual trusted branch.
7. Script Path: Jenkinsfile.
8. Save, then Build Now for the first run.

The first build registers the deployment parameter. CI stages:

    Checkout
    Terraform format
    Terraform validate
    Deployment script check

No cloud API credentials are required for these validation stages. terraform init still needs internet to download providers. Commit .terraform.lock.hcl for repeatable provider selection. A fmt failure should be fixed locally with terraform fmt -recursive, reviewed and committed.

The pipeline polls Git every five minutes while Jenkins runs. This avoids exposing local Jenkins to the internet for GitHub webhooks. Polling checks for source changes; it does not mean a deployment happens every five minutes. Approved application delivery remains a separate stage.

## 6 Run application delivery

Choose Build with Parameters, check DEPLOY_APP, then build. After CI passes, review the selected Git revision and targets and click Deploy at the approval stage. The approval expires after ten minutes.

The deployment script:

1. Preflights Nginx on all three VMs.
2. Renders the checked-out webpage with provider and Git revision.
3. Uploads files to a unique temporary directory through SSH.
4. Installs the new files and renames them into the Nginx document root.
5. Checks each public origin's homepage and exact health text.
6. Archives deployment-evidence in the Jenkins build.

It does not change Nginx configuration, so a reload is unnecessary for static file updates. The two file renames are separate operations, not a distributed atomic deployment. If a later VM fails, earlier VMs may already serve the new revision. There is no automatic multi-cloud rollback in this baseline. Review logs and recover the affected targets deliberately.

Do not perform this deployment during a failover outage simulation: direct-origin verification intentionally fails if a target Nginx service is stopped. Ensure current firewall settings allow the laptop's Docker Desktop SSH egress.

## 7 Verify and collect viva evidence

On your laptop:

```bash
curl --max-time 10 http://184.197.92.35/health
curl --max-time 10 http://20.80.177.122/health
curl --max-time 10 http://34.56.109.225/health
```

Expected bodies: healthy aws, healthy azure and healthy gcp. Open each homepage and show the deployed Git revision. The shared domain shows whichever origin the failover controller selects; it does not prove deployment to all three origins.

Capture the Jenkins stage view, approval, public pages and archived result.txt. Do not capture credentials. The pipeline does not automatically notify Slack; Grafana's existing Slack contact point does not configure Jenkins notifications.

## 8 Rollback and infrastructure deployment

For application rollback, revert the application change in Git, review the resulting commit and run the same approved delivery workflow. This creates an auditable new revision. Do not reset or delete Terraform state to roll back a webpage.

For later Jenkins infrastructure CD, first configure:

- Existing state migrated to an encrypted remote backend with locking, plus a tested state backup.
- Appropriate AWS, Azure and GCP authentication for the Jenkins agent, preferably short-lived/federated identities.
- Terraform variables and SSH public key input available on the agent.
- Reviewed saved plan bound to the exact source revision and an approval gate before apply.
- Restricted branch/job permissions, concurrency control and private plan handling.

Keep running your current Terraform plan/apply from its existing authenticated workspace until that work is complete. Never apply from a fresh checkout with empty local state.

## Troubleshooting

- Permission denied publickey: correct SSH key/passphrase, target username and cloud SSH access rules.
- Host key verification failed: verify replacement VM fingerprint and update cloud-known-hosts.
- sudo requires a password: deployment identity lacks the required approved noninteractive commands.
- Missing SSH Agent step: install the SSH Agent plugin and verify openssh-client is in the image.
- Terraform provider download failure: check Docker Desktop network/DNS/proxy access.
- Missing Jenkinsfile or template: ensure files are committed to the configured branch at repository root.
- Approvals or credentials exposed to unintended users: restrict the job/repository and rotate any compromised credentials.

## Validation status

Compose structural validation and file/line-ending checks were performed for the supplied package. Jenkins was not started and the image was not built here. No VM credentials, remote deployment or cloud resources were accessed. Jenkinsfile execution, shellcheck and the deployment need their first controlled run in your local environment. No successful pipeline outcome is claimed by this package.

## Documentation

- https://www.jenkins.io/doc/book/installing/docker/
- https://www.jenkins.io/doc/book/pipeline/syntax/
- https://www.jenkins.io/doc/pipeline/steps/ssh-agent/
