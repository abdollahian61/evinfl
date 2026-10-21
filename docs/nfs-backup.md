# Backing Up All NFS Data to MinIO

This script runs on `nfs01` (`192.168.1.24`). It reads every file in the share, including PVC data not currently mounted by an active Pod, from local storage. The destination is a Restic repository in the dedicated MinIO bucket `nfs-backup`. Velero backs up Kubernetes resources separately.

Assumption: the NFS data disk is mounted at `/srv/nfs`, with all required data beneath that path. Verify `BACKUP_SOURCE` and `DATA_MOUNT` against the actual installation. The script uses `--one-file-system` and will not cross into other filesystems; adjust the backup scope if data resides on additional mounts.

## Install on the NFS Server

From the root of the cloned repository:

```bash
sudo apt update
sudo apt install -y restic openssl ca-certificates util-linux
sudo install -m 700 scripts/backup/nfs-to-minio.sh /usr/local/sbin/nfs-to-minio.sh
```

In MinIO, create the `nfs-backup` bucket and a dedicated access key with read, write, and delete permissions restricted to that bucket. Keep the Velero bucket separate.

Copy the example configuration only on first installation. On subsequent installations, edit the existing configuration to avoid losing keys:

```bash
sudo install -o root -g root -m 600 config/backup/nfs-backup.env.example /etc/nfs-backup.env
sudo nano /etc/nfs-backup.env
```

Replace `CHANGE_ME` with the dedicated MinIO credentials. The example endpoint `http://192.168.1.28:9000` uses the private network. If MinIO TLS is enabled, update the URL and trusted CA accordingly.

Generate a repository password once. This command refuses to overwrite an existing file:

```bash
sudo bash -c 'umask 077; set -o noclobber; openssl rand -base64 48 > /etc/nfs-backup.password'
```

Keep a secure copy of the password and recovery configuration outside this VM. Encrypted data cannot be recovered without the repository password. Never commit the password or access keys to Git.

Initialize the repository only once, then run a backup:

```bash
sudo /usr/local/sbin/nfs-to-minio.sh init
sudo /usr/local/sbin/nfs-to-minio.sh
sudo /usr/local/sbin/nfs-to-minio.sh snapshots
```

## Schedule with Cron

The example runs at 02:00 in the server's configured timezone; the schedule is not yet a final project decision. After a successful manual run, install the system cron file:

```bash
sudo install -o root -g root -m 644 config/cron/nfs-backup /etc/cron.d/nfs-backup
```

This file includes the `root` user column required by `/etc/cron.d/`. If using `sudo crontab -e`, omit that column:

```cron
0 2 * * * umask 077; /usr/local/sbin/nfs-to-minio.sh >> /var/log/nfs-backup.log 2>&1
```

Enable only one scheduling method. Manage the log with the server's logrotate policy.

## Retention and Failure Behavior

- Each snapshot represents the full covered file set; repository contents are deduplicated and encrypted.
- After a successful backup, retention runs with `--keep-within 14d --keep-last 1 --prune`. The 14-day window is measured relative to the latest snapshot.
- If the data disk is not mounted or source reading is incomplete, the script stops without running retention.
- `flock` prevents overlapping executions of this script on the same server.
- Manage repository object deletion through Restic. MinIO age-based lifecycle deletion can corrupt the repository; do not configure it for this bucket.
- Monitor backup success and errors. A cron entry alone does not guarantee successful backups.
- Backing up live files is not an atomic snapshot and does not guarantee application consistency. Use quiescing or application-specific backup hooks where required.
- The initial 100 GB MinIO disk has not yet been validated against actual data volume or change rate.

## Verification and Test Restore

```bash
sudo /usr/local/sbin/nfs-to-minio.sh check
sudo /usr/local/sbin/nfs-to-minio.sh restore /srv/restore-test
```

The restore destination must be new or empty. Original paths are recreated beneath it. For source `/srv/nfs`, files normally appear under `/srv/restore-test/srv/nfs`. Check available disk space and restored contents before planning a production migration. Large restores may require a separate disk.

`check` verifies repository structure; full data verification and restore testing must be performed separately according to the operational plan.

## References

- [Restic: preparing a repository / S3-compatible storage](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html)
- [Restic: retention and prune](https://restic.readthedocs.io/en/stable/060_forget.html)
- [Restic: scripting and exit codes](https://restic.readthedocs.io/en/stable/075_scripting.html)

This script has not been run on the project's production servers. Local validation does not replace real connectivity and recovery tests.
