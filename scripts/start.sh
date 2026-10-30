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
docker compose --profile gnmi down --remove-orphans
sudo containerlab deploy -t lab.clab.yml --reconfigure
docker compose --profile gnmi pull
docker compose up -d
echo 'Waiting for the router and automatic SNMP polling...'
for i in $(seq 1 120); do
  metrics=$(docker compose exec -T prometheus wget -qO- \
    'http://snmp-exporter:9116/snmp?target=clab-telemetry-srl&module=interfaces&auth=lab_v2' 2>/dev/null || true)
  if grep '^ifOperStatus{' <<< "$metrics" | grep 'ifName="ethernet-1/1"' | grep 'ifOperStatus="up"' | grep -q ' 1$'; then
    echo 'Lab ready. SNMP is active; start gNMIc using README.md. Grafana is on port 3000.'
    exit 0
  fi
  sleep 3
done
echo 'Router did not become ready. Run: docker compose logs snmp-exporter' >&2
exit 1
