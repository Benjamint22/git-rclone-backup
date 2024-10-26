#!/bin/bash

set -e

docker_image="$1"

if [ -z "$docker_image" ]; then
	echo "Usage: $0 <docker_image>"
	exit 1
fi

directory="$(mktemp -d)"
git_directory="$(mktemp -d)"
remote="$(mktemp -d)"
rclone_config_path="$(mktemp)"
cat > "$rclone_config_path" <<-"EOF"
[backup_remote]
type = alias
remote = /fake_remote
EOF
empty_backup_file="$(mktemp)"
chmod +x "$empty_backup_file"

docker run \
	--interactive \
    --tty \
	--rm \
	--privileged \
	--device /dev/fuse \
	--cap-add SYS_ADMIN \
	--security-opt apparmor:unconfined \
	--user "$(id -u):$(id -g)" \
	--env GIT_DIR="/git" \
	--env GIT_WORK_TREE=/source \
	--volume /etc/passwd:/etc/passwd:ro --volume /etc/group:/etc/group:ro \
	--volume "$directory:/source:ro" \
	--volume "$git_directory:/git" \
	--volume "$remote:/fake_remote" \
	--volume "$rclone_config_path:/config/rclone/rclone.conf:ro" \
	--volume "$empty_backup_file:/usr/local/bin/backup" \
	--entrypoint "/bin/bash" \
	"$docker_image"
