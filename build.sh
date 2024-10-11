#!/bin/bash

set -e

# Build src/Dockerfile in context of src/
tag="git-rclone-backup"
docker build -t "$tag" src/
