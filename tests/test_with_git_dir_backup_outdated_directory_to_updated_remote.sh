#!/bin/bash

set -e

docker_image="$1"
directory_1="$(mktemp -d)"
git_directory_1="$(mktemp -d)"
directory_2="$(mktemp -d)"
git_directory_2="$(mktemp -d)"
remote="$(mktemp -d)"

# Set up git config
export GIT_CONFIG_GLOBAL="$(mktemp)"
cat > "$GIT_CONFIG_GLOBAL" <<-"EOF"
[safe]
	directory = *

[pager]
		branch = false
EOF

recursive_hash() {
	directory="$1"
	local hash=""
	for child in "$directory"/*; do
		child_basename="$(basename "$child")"
		[[ -e "$child" ]] || break
		# If child is a directory, recurse
		if [ -d "$child" ]; then
			contents_hash="$(recursive_hash "$child")"
			hash="$(printf "%s%s%s" "$hash" "$child_basename" "$contents_hash" | md5sum | awk '{print $1}')"
		fi
		# If child is a file, hash it
		if [ -f "$child" ]; then
			content_hash="$(md5sum < "$child" | awk '{print $1}')"
			hash="$(printf "%s%s%s" "$hash" "$child_basename" "$content_hash" | md5sum | awk '{print $1}')"
		fi
	done
	printf "%s" "$hash"
}

arrange() {
	echo -e "\e[36m[ARRANGE]\e[0m"
	echo_prefix="\e[34marrange:\e[0m"
	error_prefix="\e[31marrange error:\e[0m"

	# Create initial directory
	cd "$directory_1"
	echo -e "$echo_prefix Creating test content in $directory_1..."
	printf "Test content" > test.txt
	mkdir some_directory
	printf "Test contents 2" > some_directory/test2.txt

	# Backup once
	echo -e "$echo_prefix Creating rclone configuration..."
	rclone_config_path="$(mktemp)"
	cat > "$rclone_config_path" <<-"EOF"
	[backup_remote]
	type = alias
	remote = /fake_remote
	EOF
	echo -e "$echo_prefix Creating initial backup..."
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
		--volume "$directory_1:/source:ro" \
		--volume "$git_directory_1:/git" \
		--volume "$remote:/fake_remote" \
		--volume "$rclone_config_path:/config/rclone/rclone.conf:ro" \
		"$docker_image"

	# Create updated directory
	cd "$directory_2"
	rsync -a "$directory_1/" "$directory_2/"
	printf "Newer test content" > test.txt
	printf "Test contents 3" > some_directory/test3.txt

	# Backup again
	echo -e "$echo_prefix Creating updated backup..."
	directory_2_hash="$(recursive_hash "$directory_2")"
	if ! [ "$directory_2_hash" = "03e0e4fca94b7cf287272423bce9962f" ]; then
		echo -e "$error_prefix Hash of directory_2 changed after backup." >&2
		echo -e "$error_prefix New hash is: $directory_2_hash" >&2
		exit 1
	fi
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
		--volume "$directory_2:/source:ro" \
		--volume "$git_directory_2:/git" \
		--volume "$remote:/fake_remote" \
		--volume "$rclone_config_path:/config/rclone/rclone.conf:ro" \
		"$docker_image"

	# Update something else in directory 1
	cd "$directory_1"
	echo -e "$echo_prefix Updating test content in $directory_1..."
	printf "Newest test content" > test.txt
	directory_1_hash="$(recursive_hash "$directory_1")"
	if ! [ "$directory_1_hash" = "20d3dc0ced0a84615cc62022a8151820" ]; then
		echo -e "$error_prefix Hash of directory_1 changed since tests were written." >&2
		echo -e "$error_prefix New hash is: $directory_1_hash" >&2
		exit 1
	fi
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
		--volume "$directory_1:/source:ro" \
		--volume "$git_directory_1:/git" \
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

	# Test: Files match contents of directory_1 but not directory_2
	if [ "$(cat "$clone_dir/test.txt")" = "Newest test content" ]; then
		echo -e "$success_prefix File 'test.txt' matches contents of directory_1."
	else
		echo -e "$fail_prefix File 'test.txt' does not match contents of directory_1." >&2
		exit 1
	fi
	if [ "$(cat "$clone_dir/some_directory/test2.txt")" = "Test contents 2" ]; then
		echo -e "$success_prefix File 'some_directory/test2.txt' matches contents of directory_1."
	else
		echo -e "$fail_prefix File 'some_directory/test2.txt' does not match contents of directory_1." >&2
		exit 1
	fi
	if [ ! -f "$clone_dir/some_directory/test3.txt" ]; then
		echo -e "$success_prefix File 'some_directory/test3.txt' does not exist in directory_1."
	else
		echo -e "$fail_prefix File 'some_directory/test3.txt' exists in directory_1." >&2
		exit 1
	fi

	# Test: Keeps a backup of the previous version
	clone_dir_2="$(mktemp -d)"
	if git clone "$remote" "$clone_dir_2" --branch "$expected_backup_branch_name" && cd "$clone_dir_2" && git checkout "$expected_backup_branch_name^"; then
		echo -e "$success_prefix Git repository found in remote with reference $expected_backup_branch_name^."
	else
		echo -e "$fail_prefix No git repository found in remote with reference $expected_backup_branch_name^." >&2
		exit 1
	fi
	if [ "$(cat "$clone_dir_2/test.txt")" = "Newer test content" ]; then
		echo -e "$success_prefix File 'test.txt' on $expected_backup_branch_name^ matches contents of directory_2 from previous backup."
	else
		echo -e "$fail_prefix File 'test.txt' on $expected_backup_branch_name^ does not match contents of directory_2 from previous backup." >&2
		exit 1
	fi
	if [ "$(cat "$clone_dir_2/some_directory/test2.txt")" = "Test contents 2" ]; then
		echo -e "$success_prefix File 'some_directory/test2.txt' on $expected_backup_branch_name^ matches contents of directory_2 from previous backup."
	else
		echo -e "$fail_prefix File 'some_directory/test2.txt' on $expected_backup_branch_name^ does not match contents of directory_2 from previous backup." >&2
		exit 1
	fi
	if [ "$(cat "$clone_dir_2/some_directory/test3.txt")" = "Test contents 3" ]; then
		echo -e "$success_prefix File 'some_directory/test3.txt' on $expected_backup_branch_name^ matches contents of directory_2 from previous backup."
	else
		echo -e "$fail_prefix File 'some_directory/test3.txt' on $expected_backup_branch_name^ does not match contents of directory_2 from previous backup." >&2
		exit 1
	fi

	# Test: There are three commits in the backup branch
	actual_commit_count="$(cd "$clone_dir" && git rev-list --count "$expected_backup_branch_name")"
	if [ "$actual_commit_count" = "3" ]; then
		echo -e "$success_prefix Backup branch has three commits."
	else
		echo -e "$fail_prefix Backup branch does not have three commits." >&2
		echo -e "$fail_prefix Actual: $actual_commit_count" >&2
		exit 1
	fi

	# Test: Hash of directory_1 hasn't changed
	expected_hash="20d3dc0ced0a84615cc62022a8151820"
	actual_hash="$(recursive_hash "$directory_1")"
	if [ "$actual_hash" = "$expected_hash" ]; then
		echo -e "$success_prefix Hash of first directory matches expected value."
	else
		echo -e "$fail_prefix Hash of first directory does not match expected value." >&2
		echo -e "$fail_prefix Expected: $expected_hash" >&2
		echo -e "$fail_prefix Actual: $actual_hash" >&2
		exit 1
	fi

	# Test: Hash of directory_2 has changed
	expected_hash="03e0e4fca94b7cf287272423bce9962f"
	actual_hash="$(recursive_hash "$directory_2")"
	if [ "$actual_hash" = "$expected_hash" ]; then
		echo -e "$success_prefix Hash of second directory matches expected value."
	else
		echo -e "$fail_prefix Hash of second directory does not match expected value." >&2
		echo -e "$fail_prefix Expected: $expected_hash" >&2
		echo -e "$fail_prefix Actual: $actual_hash" >&2
		exit 1
	fi
}

arrange
act
assert
