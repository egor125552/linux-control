#!/usr/bin/env bash
set -euo pipefail
mkdir -p /root/docker-recovery
OUT=/root/docker-recovery/docker-image-info.txt
{
  echo "Date: $(date -Is)"
  echo "Host: $(hostname)"
  echo
  echo "Images:"
  docker image ls --all --digests --no-trunc
  echo
  echo "Containers:"
  docker ps -a --no-trunc
  echo
  echo "Image details:"
  docker image ls -q --no-trunc | sort -u | while read -r id; do
    [ -n "$id" ] || continue
    echo
    echo "IMAGE $id"
    docker image inspect "$id"
    echo "HISTORY $id"
    docker history --no-trunc "$id"
  done
} > "$OUT"
chmod 600 "$OUT"
echo "Saved: $OUT"
wc -c "$OUT"
sha256sum "$OUT"
docker image ls --all --format '{{.ID}} {{.Repository}}:{{.Tag}} {{.Size}}'
docker ps -a --format '{{.ID}} {{.Image}} {{.Status}} {{.Names}}'
