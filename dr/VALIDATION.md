# Validation record

Prepared 24 October 2026.

- Docker Compose configuration check passed with a temporary dummy password. No container was started.
- UTF-8 and LF line endings were normalized for Linux/WSL use.
- Bash syntax checks were attempted, but Git Bash could not start due to a Windows sandbox permission error. Bash syntax and live execution are not independently verified here.
- No cloud credentials were accessed and no cloud backup, restore, deployment or data deletion was executed.
- The source table comparison is limited to the controlled dr_evidence fixture. The dump itself captures the database; global roles and external dependencies require separate recovery work.

Before using the scripts, run from WSL:

    bash -n dr/common.sh
    bash -n dr/backup.sh
    bash -n dr/schedule.sh
    bash -n dr/restore.sh

Then follow README.md for the first backup and restore. Treat the first execution as a controlled test on dummy data. No completed recovery outcome is claimed by this package.
