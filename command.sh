#!/usr/bin/env bash
set -euo pipefail
echo "Before:"
docker image ls --all --format '{{.ID}} {{.Repository}}:{{.Tag}} {{.Size}}'
docker ps -a --format '{{.ID}} {{.Image}} {{.Status}} {{.Names}}'
echo "Removing stopped container..."
docker rm piper-colab-runtime
echo "Removing image..."
docker image rm us-docker.pkg.dev/colab-images/public/runtime:latest
echo "After:"
docker system df
df -h /
