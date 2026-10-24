# Disaster Recovery Plan

## Purpose and scope

Recover the project's PostgreSQL database after a simulated loss of its GCP database service by restoring a completed backup onto an independent AWS PostgreSQL target. Preserve redundant copies in AWS S3, Azure Blob Storage and Google Cloud Storage.

This is a backup-based educational recovery procedure. It does not provide continuous database replication, automatic database promotion or an automatic application cutover. Terraform manages the supporting VM, network and storage infrastructure; data operations are executed by the supplied scripts.

## Responsibility

Project owners: Thupeshkumar and Jilan. Assign one operator to execute recovery and one observer to record timestamps and verify results. Use a single designated writer in a real application incident.

## Preparation

Verify cloud quota and cost, source/target readiness, SSH access, valid credentials and private storage permissions. Run the initial backup, confirm COMPLETE markers in each destination and perform an initial test restore. Maintain the inventory of current IPs, bucket names, database versions and extension dependencies without recording credentials.

## Recovery objectives

The demonstration schedules a new snapshot after each 15-minute waiting interval. The actual interval also includes backup and upload duration. This is a scheduling target, not a guaranteed RPO. Record the age of the latest usable completed backup at failure time. Set the acceptable RTO with the evaluator and measure the actual time; no recovery-time result is assumed.

## Incident procedure

1. Record UTC failure time and confirm whether the problem is the database, host, network or monitoring.
2. Stop the scheduler during the controlled test and confirm the primary cannot accept writes if a real cutover is needed.
3. Select a completed backup from an unaffected provider. Confirm the marker, files and checksum.
4. Restore into a new database on the independent target using restore.sh.
5. Require successful restore and expected dummy-row comparison before accepting the test as passed. Preserve failed attempts for diagnosis.
6. For a real application, update its database connection, verify transactions and only then restore user traffic. The present static webpage cannot demonstrate this step.
7. Record timestamps, checks and observed loss/recovery windows.

## Failback

Restart the GCP container after the controlled test. If the secondary accepted writes during a real incident, reconcile changes and conduct a planned failback before restoring the original writer. Do not switch to a stale primary merely because it is reachable again.

## Evidence

Record run ID, selected backup provider, backup time, remote-copy completion, failure time, restore start, validation completion, restored database name and comparison result. Store screenshots and logs without passwords or tokens. Report archive SHA256 checks separately from row-level checks and full application validation.

## Retention and review

The supplied scripts retain generations and do not delete backups. Define a retention schedule and test object lifecycle rules before unattended use. Preserve at least one verified recovery generation before deleting old data or destroying infrastructure. Review credentials, restore compatibility and recovery tests after configuration changes.
