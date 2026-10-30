#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose --profile gnmi down --remove-orphans
sudo containerlab destroy -t lab.clab.yml --cleanup
