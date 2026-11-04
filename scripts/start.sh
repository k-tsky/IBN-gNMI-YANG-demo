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
# Check the local Cisco image before disturbing an already-running lab.
bash scripts/load-xrd.sh
# Build once, before stopping an existing lab; later starts use the local image.
if ! docker image inspect ibn-yang-push-receiver:netcalyx-0.3.0-telegraf-1.36.4 >/dev/null 2>&1; then
  docker compose build yang-push
fi
sudo sysctl -w fs.inotify.max_user_instances=64000 fs.inotify.max_user_watches=64000
# Recreate on each Codespace start, including recovery from a partial deploy.
# Starting old containers alone does not recreate Containerlab's veth wiring.
docker compose down --remove-orphans
# Containerlab only reconfigures nodes in the current topology. Remove the
# previous SR Linux node when upgrading this checkout to the XRd topology.
old_router=$(docker ps -aq --filter 'name=^/clab-telemetry-srl$' \
  --filter label=containerlab=telemetry --filter label=clab-node-kind=nokia_srlinux \
  --filter "label=clab-topo-file=$PWD/lab.clab.yml")
if [ -n "$old_router" ]; then
  docker rm -f "$old_router"
fi
sudo containerlab deploy -t lab.clab.yml --reconfigure
docker compose up -d --pull missing --wait --wait-timeout 60
echo 'Waiting for gNMI and YANG Push interface updates...'
for i in $(seq 1 120); do
  gnmi_metrics=$(docker compose exec -T prometheus wget -qO- http://gnmic:9804/metrics 2>/dev/null || true)
  yang_push_metrics=$(docker compose exec -T prometheus wget -qO- http://yang-push:9273/metrics 2>/dev/null || true)
  yang_push_messages=$(docker compose logs --no-log-prefix yang-push 2>/dev/null || true)
  if grep '^openconfig_interfaces_interfaces_interface_state_oper_status{' <<< "$gnmi_metrics" | \
       grep 'interface_name="GigabitEthernet0/0/0/0"' | grep -q 'oper_status="UP"' && \
     grep -q '"oper-status": "UP"' <<< "$yang_push_messages" && \
     grep '^yang_push_interface_state{' <<< "$yang_push_metrics" | \
       grep 'interface_name="GigabitEthernet0/0/0/0"' | grep -q ' 1$'; then
    echo 'Lab ready. Open the router CLI and receiver logs using README.md. Grafana is on port 3000.'
    exit 0
  fi
  sleep 3
done
echo 'Router did not become ready. Check: docker logs clab-telemetry-xrd --tail=60' >&2
echo 'Then check: docker compose logs --tail=80 gnmic yang-push' >&2
exit 1
