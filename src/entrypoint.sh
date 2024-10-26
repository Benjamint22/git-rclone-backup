#!/bin/bash

set -e

# Check if `--backup-immediately` flag is passed
backup_immediately=false
if [ "$1" == "--backup-immediately" ]; then
	backup_immediately=true
	shift
fi

vars_file="$HOME/.config/git-rclone-backup/vars.sh"
mkdir -p "$(dirname "$vars_file")"
{
	echo "export BACKUP_BRANCH_NAME=${BACKUP_BRANCH_NAME:-backup}"
	echo "export BACKUP_COMMIT_MESSAGE=${BACKUP_COMMIT_MESSAGE:-Backup}"
	echo "export GIT_ORIGIN_NAME=${GIT_ORIGIN_NAME:-remote-backup}"
	echo "export GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL:-git-rclone-backup@localhost}"
	echo "export GIT_COMMITTER_EMAIL=${GIT_AUTHOR_EMAIL:-git-rclone-backup@localhost}"
	echo "export GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME:-Git Rclone Backup}"
	echo "export GIT_COMMITTER_NAME=${GIT_AUTHOR_NAME:-Git Rclone Backup}"
} >> "$vars_file"
echo "source $vars_file" >> "$HOME/.profile"
chmod +x "$vars_file"
source "$vars_file"

remote_url="$(mktemp -d)"
directory_to_backup="/source"

echo "Currently running as: $(whoami) ($(id -u):$(id -g))"
echo "Owner of /source: $(stat -c '%U:%G' /source)"
echo "Owner of /config/rclone/rclone.conf:ro: $(stat -c '%U:%G' /config/rclone/rclone.conf:ro)"

start_rclone
wait_for_remote "$remote_url"
env --ignore-environment initialize_git_remote_in_directory "$remote_url"
initialize_git_repository "$directory_to_backup" "$remote_url"

if [ "$backup_immediately" = true ]; then
	backup
	echo "Backup completed successfully!"
fi
