#!/bin/bash

set -e

export BACKUP_BRANCH_NAME=${BACKUP_BRANCH_NAME:-backup}
export BACKUP_COMMIT_MESSAGE=${BACKUP_COMMIT_MESSAGE:-Backup}
export GIT_ORIGIN_NAME=${GIT_ORIGIN_NAME:-remote-backup}
export GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL:-git-rclone-backup@localhost}
export GIT_COMMITTER_EMAIL=${GIT_AUTHOR_EMAIL:-git-rclone-backup@localhost}
export GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME:-Git Rclone Backup}
export GIT_COMMITTER_NAME=${GIT_AUTHOR_NAME:-Git Rclone Backup}

cache_directory="$(mktemp -d)"

start_rclone() {
  echo "Starting rclone..."
  nohup \
    rclone rcd \
    --cache-dir "$cache_directory" \
    --rc-no-auth \
    &
  echo "Waiting for rclone to start..."
  while ! rclone rc core/pid | jq '.pid' &>/dev/null; do
    sleep 1
  done
  echo "Rclone started successfully!"
}

wait_for_remote() {
  remote_url=$1
  echo "Mounting remote $remote_url..."
  timeout=5
  rclone rc mount/mount \
    fs="backup_remote:" \
    mountPoint="$remote_url" \
    mountOpt="{\"AllowOther\": true}" \
    vfsOpt="{\"CacheMode\": 3, \"WriteBack\": \"100ms\"}"
  echo "Waiting for remote $remote_url..."
  timeout=60
  while [ "$(rclone rc mount/listmounts | jq '.mountPoints | length')" != "1" ]; do
    if [ "$timeout" -eq 0 ]; then
      echo "Timed out waiting for remote $remote_url." >&2
      exit 1
    fi
    echo "Remote $remote_url not found, retrying..."
    sleep 1
    timeout=$((timeout - 1))
  done
  echo "Remote $remote_url found!"
  echo "Listing contents of remote:"
  ls -la "$remote_url"
}

initialize_git_remote_in_directory() {
  directory=$1
  cd "$directory"
  if [ -z "$(ls -A)" ]; then
    echo "Initializing git remote in $directory..."
    git init --bare
  else
    if [ -f HEAD ] && [ -d refs ]; then
      echo "Directory $directory is not empty and contains a git repository."
    else
      echo "Directory $directory is not empty and does not contain a git repository." >&2
      exit 1
    fi
  fi
}

initialize_git_repository() {
  directory=$1
  remote_url=$2
  cd "$directory"
  if ! [ -d .git ]; then
    echo "Initializing git repository in $directory..."
    git init
  fi
  echo "Ensuring remote $GIT_ORIGIN_NAME points to $remote_url..."
  if git remote get-url "$GIT_ORIGIN_NAME" &>/dev/null; then
    git remote set-url "$GIT_ORIGIN_NAME" "$remote_url"
  else
    git remote add "$GIT_ORIGIN_NAME" "$remote_url"
  fi
}

pull_without_affecting_local_files() {
  directory=$1
  cd "$directory"
  echo "Pulling changes from $BACKUP_BRANCH_NAME..."
  if git fetch "$GIT_ORIGIN_NAME" "$BACKUP_BRANCH_NAME" &>/dev/null; then
    git reset --soft "$GIT_ORIGIN_NAME/$BACKUP_BRANCH_NAME"
  fi
}

commit_directory() {
  directory=$1
  cd "$directory"
  echo "Staging changes in $directory..."
  git add .
  if ! git diff --cached --no-patch --exit-code; then
    echo "Changes detected in $directory, committing..."
    git commit -m "$BACKUP_COMMIT_MESSAGE"
  else
    echo "No changes detected in $directory."
  fi
}

try_pushing_changes() {
  directory=$1
  cd "$directory"
  echo "Pushing changes to $BACKUP_BRANCH_NAME..."
  if git push "$GIT_ORIGIN_NAME" HEAD:"$BACKUP_BRANCH_NAME"; then
    echo "Changes pushed to branch '$BACKUP_BRANCH_NAME'."
  else
    echo "Failed to push changes to branch '$BACKUP_BRANCH_NAME'." >&2
    exit 1
  fi
}

wait_for_cache() {
  echo "Waiting for cache to be written..."
  timeout=120
  sleep 0.25
  while [ "$(rclone rc vfs/queue | jq '.queue | length')" != "0" ]; do
    if [ "$timeout" -eq 0 ]; then
      echo "Timed out waiting for cache to be written." >&2
      exit 1
    fi
    echo "Cache not written, retrying..."
    sleep 1
    timeout=$((timeout - 1))
  done
  echo "Cache written successfully!"
}

main() {
  remote_url="$(mktemp -d)"
  directory_to_backup="/source"

  echo "Currently running as: $(whoami) ($(id -u):$(id -g))"
  echo "Owner of /source: $(stat -c '%U:%G' /source)"
  echo "Owner of /config/rclone/rclone.conf: $(stat -c '%U:%G' /config/rclone/rclone.conf)"

  start_rclone
  wait_for_remote "$remote_url"
  initialize_git_remote_in_directory "$remote_url"
  initialize_git_repository "$directory_to_backup" "$remote_url"
  pull_without_affecting_local_files "$directory_to_backup"
  commit_directory "$directory_to_backup"
  try_pushing_changes "$directory_to_backup"
  wait_for_cache
}

main
