#!/bin/bash

set -e

docker_image="$1"

if [ -z "$docker_image" ]; then
  echo "Usage: $0 <docker_image>"
  exit 1
fi

./tests/test_backup_new_directory_to_blank_remote.sh "$docker_image"
./tests/test_backup_outdated_directory_to_updated_remote.sh "$docker_image"
