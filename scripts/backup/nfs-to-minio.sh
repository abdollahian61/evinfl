#!/usr/bin/env bash
# Whole NFS data backup to a dedicated encrypted restic repository in MinIO.
# Run on nfs01 (192.168.1.24), as root. Source data must be on DATA_MOUNT.
# Install: apt install restic ca-certificates util-linux
# Config: /etc/nfs-backup.env (root:root, mode 600), for example:
#   BACKUP_SOURCE='/srv/nfs'
#   DATA_MOUNT='/srv/nfs'
#   BACKUP_HOST='nfs01'
#   RESTIC_REPOSITORY='s3:http://192.168.1.28:9000/nfs-backup'
#   AWS_ACCESS_KEY_ID='CHANGE_ME'
#   AWS_SECRET_ACCESS_KEY='CHANGE_ME'
#   AWS_DEFAULT_REGION='us-east-1'
#   RESTIC_PASSWORD_FILE='/etc/nfs-backup.password'
# Create the nfs-backup bucket and a key limited to that bucket in MinIO.
# Keep the repository password separately off this server for disaster recovery.
# Retention is managed by restic, not a MinIO age-based object deletion rule.
# The first backup uploads all data; subsequent snapshots reuse unchanged chunks.
# This is a file-level backup of live files, not an atomic filesystem snapshot.
# Usage:
#   nfs-to-minio.sh init       # once, for a NEW repository only
#   nfs-to-minio.sh            # backup, then apply 14-day retention and prune
#   nfs-to-minio.sh snapshots
#   nfs-to-minio.sh check
#   nfs-to-minio.sh restore /absolute/empty/recovery-directory
# Suggested root cron (02:00 in the server's configured timezone):
#   0 2 * * * /usr/local/sbin/nfs-to-minio.sh >> /var/log/nfs-backup.log 2>&1

set -Eeuo pipefail
umask 077
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

die() { printf '%s\n' "$*" >&2; exit 1; }
(( EUID == 0 )) || die 'Run this script as root.'

CONFIG=/etc/nfs-backup.env
[[ -f "$CONFIG" && ! -L "$CONFIG" ]] || die 'Missing regular config: /etc/nfs-backup.env'
[[ "$(stat -c '%u:%a' "$CONFIG")" == '0:600' ]] || die 'Config must be owned by root with mode 600.'

set -a
# shellcheck source=/dev/null
source "$CONFIG"
set +a

: "${BACKUP_SOURCE:?Set BACKUP_SOURCE in the config}"
: "${DATA_MOUNT:?Set DATA_MOUNT in the config}"
: "${BACKUP_HOST:?Set BACKUP_HOST in the config}"
: "${RESTIC_REPOSITORY:?Set RESTIC_REPOSITORY in the config}"
: "${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID in the config}"
: "${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY in the config}"
: "${RESTIC_PASSWORD_FILE:?Set RESTIC_PASSWORD_FILE in the config}"
[[ "$AWS_ACCESS_KEY_ID" != CHANGE_ME && "$AWS_SECRET_ACCESS_KEY" != CHANGE_ME ]] || die 'Replace the MinIO credential placeholders.'
[[ -f "$RESTIC_PASSWORD_FILE" && ! -L "$RESTIC_PASSWORD_FILE" && -s "$RESTIC_PASSWORD_FILE" ]] || die 'Repository password file is missing or empty.'
[[ "$(stat -c '%u:%a' "$RESTIC_PASSWORD_FILE")" == '0:600' ]] || die 'Password file must be owned by root with mode 600.'
command -v restic >/dev/null || die 'Install restic first.'

export RESTIC_CACHE_DIR=/var/cache/restic/nfs-backup
mkdir -p "$RESTIC_CACHE_DIR"
exec 9>/run/lock/nfs-to-minio.lock
flock -n 9 || { printf '%s\n' 'Another NFS backup operation is running; skipped.'; exit 0; }

case "${1:-backup}" in
    init)
        restic init
        ;;
    backup)
        [[ "$BACKUP_SOURCE" == /* && "$DATA_MOUNT" == /* ]] || die 'Source and mount paths must be absolute.'
        mountpoint -q "$DATA_MOUNT" || die 'NFS data disk is not mounted; backup stopped.'
        [[ -d "$BACKUP_SOURCE" ]] || die 'NFS source directory does not exist.'
        source_path=$(realpath -e "$BACKUP_SOURCE")
        data_mount_path=$(realpath -e "$DATA_MOUNT")
        [[ "$data_mount_path" != / ]] || die 'DATA_MOUNT must be the separate NFS data disk, not /.'
        [[ "$source_path" == "$data_mount_path" || "$source_path" == "$data_mount_path/"* ]] || die 'NFS source is outside the configured data mount.'
        [[ "$(findmnt -n -o TARGET --target "$source_path")" == "$data_mount_path" ]] || die 'Source is not on the expected data mount.'
        printf '[%s] NFS backup started\n' "$(date -Is)"
        # Exit code 3 (unreadable files) also stops the script, before retention.
        restic backup --host "$BACKUP_HOST" --tag nfs-full --one-file-system "$source_path"
        restic forget --host "$BACKUP_HOST" --tag nfs-full \
            --group-by host,paths --keep-within 14d --keep-last 1 --prune
        printf '[%s] NFS backup completed\n' "$(date -Is)"
        ;;
    snapshots)
        restic snapshots --host "$BACKUP_HOST" --tag nfs-full
        ;;
    check)
        restic check
        ;;
    restore)
        [[ $# == 2 && "$2" == /* && "$2" != / ]] || die 'Usage: nfs-to-minio.sh restore /absolute/empty/recovery-directory'
        target_path=$2
        [[ ! -L "$target_path" ]] || die 'Restore target must not be a symlink.'
        if [[ -e "$target_path" ]]; then
            [[ -d "$target_path" ]] || die 'Restore target must be a directory.'
            [[ -z "$(find "$target_path" -mindepth 1 -maxdepth 1 -print -quit)" ]] || die 'Restore target must be empty.'
        else
            mkdir -p "$target_path"
        fi
        restic restore latest --host "$BACKUP_HOST" --tag nfs-full --target "$target_path"
        ;;
    *)
        die 'Usage: nfs-to-minio.sh [init|backup|snapshots|check|restore /absolute/empty/directory]'
        ;;
esac
