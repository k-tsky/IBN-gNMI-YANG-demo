# SNMP polling vs gNMI telemetry

A Containerlab demo using a real Nokia SR Linux router, Prometheus's SNMP
exporter, gNMIc, Prometheus and Grafana. There is no custom collector script.

```text
SR Linux ethernet-1/1 ── Alpine peer
       │
       ├── SNMP ── snmp_exporter ── polling every 10s ──┐
       └── gNMI ── gNMIc (started manually) ────────────┴── Prometheus → Grafana
```

SNMP polling starts automatically. The gNMI subscription starts only when you
run it during the demo. Its actual received messages appear in the CLI, and
the same gNMIc process exports the latest received state for Grafana.

## Start the lab

**Codespaces:** open [this repository in Codespaces](https://codespaces.new/k-tsky/IBN-gNMI-YANG-demo?quickstart=1),
choose a 4-core machine and wait for **Lab ready**. Setup is automatic after
these files have been pushed to GitHub.

**Local Windows/macOS:** start Docker Desktop with Linux containers, open this
folder in VS Code, install Microsoft's **Dev Containers** extension, and select
**Dev Containers: Reopen in Container**. Wait for **Lab ready**.

**Local Linux:** with Docker, Docker Compose and Containerlab installed, run:

```bash
bash scripts/start.sh
```

Run all commands below from the repository directory **inside the development
container or Codespace** (or directly on the Linux host). Initial downloads
and router startup can take several minutes.

## Demo playbook

### 1. Show the system and SNMP baseline

```bash
sudo containerlab inspect -t lab.clab.yml
docker compose ps
```

Open Grafana from port **3000** in the VS Code/Codespaces **Ports** tab, or use
[localhost:3000](http://localhost:3000) locally. SNMP polling is preconfigured.
The gNMI panels initially have no data because no gNMI subscription is running.

Prometheus requests `/snmp` from the exporter every ten seconds. Each request
causes real SNMP queries to SR Linux. The exporter reads IF-MIB `ifOperStatus`
and resolves interface names through `ifName`. No traps are configured.

### 2. Terminal 1 — start the gNMI subscription

Show the configuration:

```bash
cat configs/gnmic.yml
```

Point out the interface path, `mode: stream`, and `stream-mode: on-change`.
Then run the standard gNMIc service in the foreground:

```bash
docker compose --profile gnmi run --rm --use-aliases gnmic
```

Wait for the initial `up` value and leave it running. Later JSON messages are
the real updates sent by SR Linux. gNMIc sends them to stdout and its built-in
Prometheus output. `--use-aliases` lets Prometheus reach this process as `gnmic`.
Run only one instance at a time.

Grafana's gNMI panels fill in after Prometheus scrapes the exporter. No separate
background gNMI subscription is started by the lab.

### 3. Terminal 2 — change the interface

After Terminal 1 shows the initial `up`, run:

```bash
bash scripts/gnmi.sh set \
  --update '/interface[name=ethernet-1/1]/admin-state:::string:::disable'
sleep 2
bash scripts/gnmi.sh set \
  --update '/interface[name=ethernet-1/1]/admin-state:::string:::enable'
```

Terminal 1 should show `down` then `up`. Compare Grafana's SNMP and gNMI traces.
SNMP can miss an outage that falls entirely between its ten-second polls;
depending on timing, it may also catch it. Repeat as needed.

`scripts/gnmi.sh` is a convenience wrapper for the real gNMIc CLI. It supplies
the lab network, router address and credentials; it does not create responses.

If interrupted with the interface disabled, restore it:

```bash
bash scripts/gnmi.sh set \
  --update '/interface[name=ethernet-1/1]/admin-state:::string:::enable'
```

To inspect the router directly:

```bash
docker exec -it clab-telemetry-srl sr_cli
```

Enter `show interface ethernet-1/1`, then `quit` to leave.

### 4. Explain the Grafana results

The timeline displays UP as 1 and DOWN as 0. The SNMP exporter converts IF-MIB
state into standard enum state-set metrics; gNMIc exposes the received string
state as metric labels. Grafana's queries normalize them for comparison.
A raw gNMI table shows those labels.

Two counter panels compare the observations:

- **Received SNMP / gNMI observations:** successful SNMP polls in the selected
  time range versus gNMI state updates since the current receiver started.
  gNMI includes the initial state and excludes sync-only messages.
- **Received DOWN observations:** SNMP polls that returned DOWN versus gNMI
  DOWN updates. A long outage may produce several DOWN polls but one gNMI
  change notification. Initial/resynchronization DOWN updates also count.

The gNMI counts use gNMIc's built-in file-output metrics with standard event
filters writing to `/dev/null`; no custom collector script is involved. They
reset when gNMIc restarts. An initial UP followed by DOWN and UP produces
**3 gNMI observations and 1 DOWN observation**.

Prometheus polls SNMP every **10 seconds** and scrapes gNMIc every **1 second**.
gNMIc receives changes as they arrive, but Prometheus still samples its latest
state. Very short transitions can therefore be missing from Grafana even when
the gNMIc CLI received them. The CLI output and native gNMIc counters retain
evidence of received updates even when the state plot misses a brief transition.

An exporter being reachable does not prove that its gNMI connection is healthy.
ON_CHANGE can legitimately be silent. The dashboard displays last received
state; use the CLI messages/errors to assess the actual subscription.

Press **Ctrl+C in Terminal 1** to stop gNMIc and remove its temporary container.
Its state series disappears after Prometheus detects that it is unavailable.
SNMP polling continues. Run the same command again for a fresh subscription.

This demonstrates snapshots versus change reporting. SNMP also supports
notifications, and gNMI can also poll; neither protocol is restricted to the
mode shown here.

## Restart, stop and troubleshoot

```bash
bash scripts/start.sh          # Recreate the lab; SNMP starts, gNMI waits for you
bash scripts/stop.sh           # Remove the lab and monitoring services
docker compose logs --tail=40 snmp-exporter prometheus
docker logs clab-telemetry-srl --tail=40
```

Startup also runs on development-container resume. If Grafana does not open,
forward port 3000 in the **Ports** tab and use its displayed local address.
Only Grafana is published; the SNMP and gNMI exporter ports remain internal.

The SNMPv2c community (`telemetrylab`) and router credentials (`admin` /
`NokiaSrl1!`) are disposable lab credentials. gNMI uses TLS with certificate
verification skipped for the lab's self-signed certificate. Grafana is a
read-only anonymous viewer. Monitoring history resets on recreation.
Stop the Codespace after use to conserve account quota.

Configuration references: [gNMIc Prometheus output](https://gnmic.openconfig.net/user_guide/outputs/prometheus_output/)
and [Prometheus SNMP exporter](https://github.com/prometheus/snmp_exporter).
