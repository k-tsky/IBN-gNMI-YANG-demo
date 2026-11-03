#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down --remove-orphans
sudo containerlab destroy -t lab.clab.yml --cleanup
