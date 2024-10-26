#!/bin/bash

set -e

docker_image="$1"
directory="$(mktemp -d)"
git_directory="$(mktemp -d)"
remote="$(mktemp -d)"

# Set up git config
export GIT_CONFIG_GLOBAL="$(mktemp)"
cat > "$GIT_CONFIG_GLOBAL" <<-"EOF"
[safe]
		directory = *

[pager]
		branch = false
EOF

arrange() {
	echo -e "\e[36m[ARRANGE]\e[0m"
	echo_prefix="\e[34marrange:\e[0m"

	cd "$directory"
	echo -e "$echo_prefix Creating test content in $directory..."
	printf "Test content" > test.txt
	mkdir some_directory
	printf "Test contents 2" > some_directory/test2.txt
}

act() {
	echo -e "\e[36m[ACT]\e[0m"
	echo_prefix="\e[34mact:\e[0m"

	echo -e "$echo_prefix Creating rclone configuration..."
	rclone_config_path="$(mktemp)"
	cat > "$rclone_config_path" <<-"EOF"
	[backup_remote]
	type = alias
	remote = /fake_remote
	EOF

	echo -e "$echo_prefix Running docker image..."
	docker run \
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
		"$docker_image"
}

assert() {
	echo -e "\e[36m[ASSERT]\e[0m"
	echo_prefix="\e[34massert:\e[0m"
	success_prefix="\e[32massert pass:\e[0m"
	fail_prefix="\e[31massert fail:\e[0m"

	expected_backup_branch_name="backup"
	cd "$remote"
	echo -e "$echo_prefix Contents of $remote:"
	ls -la "$remote"
	echo -e "$echo_prefix Branches in $remote:"
	git branch --list

	# Test: Git repository found in remote
	clone_dir="$(mktemp -d)"
	if git clone "$remote" "$clone_dir" --branch "$expected_backup_branch_name"; then
		echo -e "$success_prefix Git repository found in remote with branch $expected_backup_branch_name."
	else
		echo -e "$fail_prefix No git repository found in remote." >&2
		exit 1
	fi

	# Test: Backed up files found in branch backup
	if [ "$(cat "$clone_dir/test.txt")" = "Test content" ]; then
		echo -e "$success_prefix File test.txt was pushed to branch $expected_backup_branch_name."
	else
		echo -e "$fail_prefix File test.txt was not pushed to branch $expected_backup_branch_name." >&2
		exit 1
	fi
	if [ "$(cat "$clone_dir/some_directory/test2.txt")" = "Test contents 2" ]; then
		echo -e "$success_prefix File some_directory/test2.txt was pushed to branch $expected_backup_branch_name."
	else
		echo -e "$fail_prefix File some_directory/test2.txt was not pushed to branch $expected_backup_branch_name." >&2
		exit 1
	fi

	# Test: refs directory in remote has correct ownership
	expected_owner="$(id -u):$(id -g)"
	actual_owner="$(stat -c %u:%g "$remote/refs")"
	if [ "$actual_owner" = "$expected_owner" ]; then
		echo -e "$success_prefix refs directory in remote has correct ownership."
	else
		echo -e "$fail_prefix refs directory in remote has incorrect ownership." >&2
		echo -e "$fail_prefix Expected: $expected_owner, Actual: $actual_owner" >&2
		exit 1
	fi
}

arrange
act
assert
