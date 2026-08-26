#!/usr/bin/env bash
set -euo pipefail

echo 'Bridge test'
echo "host: $(hostname)"
echo "user: $(whoami)"
uname -a
free -h
