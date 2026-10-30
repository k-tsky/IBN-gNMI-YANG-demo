#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .state
exec 9>.state/start.lock
flock 9
for i in $(seq 1 60); do
  if docker info >/dev/null 2>&1; then break; fi
  sleep 2
done
docker info >/dev/null
# Recreate on each Codespace start, including recovery from a partial deploy.
# Starting old containers alone does not recreate Containerlab's veth wiring.
docker compose down
sudo containerlab deploy -t lab.clab.yml --reconfigure
docker compose up -d --build
docker pull ghcr.io/openconfig/gnmic:0.42.1
echo 'Waiting for SNMP and gNMI (router cold boot can take several minutes)...'
for i in $(seq 1 120); do
  metrics=$(docker compose exec -T collector python -c \
    'from urllib.request import urlopen; print(urlopen("http://localhost:8000/metrics", timeout=2).read().decode())' 2>/dev/null || true)
  if grep -q 'demo_interface_up{method="stream"} 1' <<< "$metrics" && \
     grep -q 'demo_interface_up{method="poll"} 1' <<< "$metrics" && \
     grep -q 'demo_collector_healthy{method="stream"} 1' <<< "$metrics" && \
     grep -q 'demo_collector_healthy{method="poll"} 1' <<< "$metrics"; then
    echo 'Lab ready. Follow README.md for the CLI demo. Grafana is on port 3000.'
    exit 0
  fi
  sleep 3
done
echo 'Router did not become ready. Run: docker compose logs collector' >&2
exit 1
