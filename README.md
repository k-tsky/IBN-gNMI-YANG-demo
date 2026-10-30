# SNMP polling vs gNMI telemetry

A small Containerlab demo with real Nokia SR Linux, SNMPv2c polling and gNMI
STREAM/ON_CHANGE. Both protocols observe `ethernet-1/1`. Grafana displays the
observations collected in the background; the demonstration runs from the CLI.

```text
SR Linux ethernet-1/1 ── Alpine peer
       │
       ├── SNMP Get every 10 seconds ──┐
       └── gNMI ON_CHANGE stream ──────┴── Collector → Prometheus → Grafana
```

## Start

**Codespaces:** open [this repository in Codespaces](https://codespaces.new/k-tsky/IBN-gNMI-YANG-demo?quickstart=1),
select a 4-core machine and wait for **Lab ready**. Setup runs automatically.
The repository files must be on GitHub before Codespaces can use them.

**Local Windows/macOS:** start Docker Desktop with Linux containers, open this
folder in VS Code, install Microsoft's **Dev Containers** extension, then run
**Dev Containers: Reopen in Container** from the command palette. Wait for
**Lab ready**. No separate installation of Containerlab or protocol clients is needed.

**Local Linux:** with Docker, Docker Compose and Containerlab installed, run:

```bash
bash scripts/start.sh
```

First startup downloads images and can take several minutes. All commands
below run from the repository directory **inside the development container or
Codespace** (or directly on the Linux host).

## Demo playbook

### 1. Show the system

```bash
sudo containerlab inspect -t lab.clab.yml
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

Point out the router, Linux peer and monitoring services. Open three terminals.

### 2. Terminal 1 — SNMP polling

Discover the interface index through the router's actual SNMP `ifName` table:

```bash
docker compose exec -T collector snmpwalk -m '' -v2c -c telemetrylab \
  -On -OQ clab-telemetry-srl .1.3.6.1.2.1.31.1.1.1.1
```

Resolve the index and poll `ifOperStatus`:

```bash
IFINDEX=$(docker compose exec -T collector snmpwalk -m '' -v2c -c telemetrylab \
  -On -OQ clab-telemetry-srl .1.3.6.1.2.1.31.1.1.1.1 |
  awk '/= "ethernet-1\/1"$/ {n=split($1,oid,"."); print oid[n]}')
test -n "$IFINDEX" || { echo 'Interface index not found'; exit 1; }
echo "ethernet-1/1 has ifIndex $IFINDEX"

while true; do
  date -u '+%H:%M:%S UTC - sending SNMP Get'
  docker compose exec -T collector snmpget -m '' -v2c -c telemetrylab \
    -t 2 -r 0 -On clab-telemetry-srl ".1.3.6.1.2.1.2.2.1.8.$IFINDEX"
  sleep 10
done
```

`INTEGER: 1` means UP; `INTEGER: 2` means DOWN. Each reading is a new SNMP
request. The loop waits ten seconds after each response. Press Ctrl+C to stop.

### 3. Terminal 2 — gNMI subscription

```bash
bash scripts/gnmi.sh subscribe \
  --path '/interface[name=ethernet-1/1]/oper-state' \
  --mode stream --stream-mode on-change
```

Wait for the initial UP value and leave this running. The router sends later
changes over the same subscription. Press Ctrl+C to stop.

`scripts/gnmi.sh` launches the real gNMIc CLI in a temporary container on the
lab network and supplies the router address and credentials. It does not
generate responses.

### 4. Terminal 3 — change the interface

Immediately after Terminal 1 prints an UP poll, run:

```bash
bash scripts/gnmi.sh set \
  --update '/interface[name=ethernet-1/1]/admin-state:::string:::disable'
sleep 2
bash scripts/gnmi.sh set \
  --update '/interface[name=ethernet-1/1]/admin-state:::string:::enable'
```

Terminal 2 should show DOWN then UP. Terminal 1 can miss the outage if it falls
entirely between requests. If a poll catches it, repeat just after the next UP
poll. The result depends on timing, not fabricated data.

If interrupted while the interface is disabled, restore it:

```bash
bash scripts/gnmi.sh set \
  --update '/interface[name=ethernet-1/1]/admin-state:::string:::enable'
```

To inspect the device directly:

```bash
docker exec -it clab-telemetry-srl sr_cli
```

Enter `show interface ethernet-1/1`, then `quit` to leave.

### 5. Show Grafana

Open port **3000** from the VS Code/Codespaces **Ports** tab, or open
[localhost:3000](http://localhost:3000) locally. The dashboard is provisioned
automatically and uses read-only anonymous access.

Compare the state timeline, DOWN-event counters, observation counts and collector
health. The background SNMP collector has its own ten-second polling schedule,
so its observations need not coincide with Terminal 1. Prometheus scrapes every
second; the event counters can retain evidence of a transition even if a scrape
misses its brief state. ON_CHANGE silence can be normal; consult transport health
and observation age separately.

The point of the demo is periodic snapshots versus change reporting. SNMP also
supports notifications, and gNMI also supports polling; neither protocol is
restricted to the collection mode shown here.

## Restart, stop and troubleshoot

```bash
bash scripts/start.sh                 # Recreate a clean lab and monitoring history
bash scripts/stop.sh                  # Remove this lab and its monitoring services
docker compose logs --tail=40 collector
docker logs clab-telemetry-srl --tail=40
```

Startup also runs when the development container resumes. Keep Docker running
and allow time for the router and SNMP agent to initialize. If Grafana does not
open, forward port 3000 in the **Ports** tab and use its displayed local address.

The SNMP community (`telemetrylab`) and router credentials (`admin` /
`NokiaSrl1!`) are disposable lab credentials. SNMP uses the internal management
network; device management and collector ports are not published. gNMI uses TLS
with certificate verification skipped for the lab's self-signed certificate.
Grafana data and collector counters reset when their containers are recreated.
Stop the Codespace after use to conserve account quota.
