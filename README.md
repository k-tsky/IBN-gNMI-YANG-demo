# Show a real interface event with gNMI and YANG Push

Log in to a Cisco XRd control-plane router, shut down an interface, and watch
gNMI and YANG Push report the change. Enable it again and watch both report UP.
Grafana compares both streams' received state and observation counters. All protocol
messages and interface states come from the real router.

![Demo network](assets/demo-topology.svg)

## Start before presenting

You need the **Cisco XRd control-plane 26.2.1 image** from Cisco. Place the
downloaded `xrd-control-plane*.tgz` release bundle in the repository root.
Leave it compressed; startup extracts the nested Docker archive, loads it into
the lab's Docker daemon, and tags it `xrd-control-plane:26.2.1` automatically.
The image is excluded from Git and is not supplied by this repository.

**Codespaces:** [open the repository in Codespaces](https://codespaces.new/k-tsky/IBN-gNMI-YANG-demo?quickstart=1)
and choose a 4-core machine. Upload your Cisco archive into the repository root
in the Codespace, then run `bash scripts/start.sh`. The first automatic startup
will ask for the missing archive. Wait for **Lab ready** before presenting.

**Local Windows/macOS:** start Docker Desktop with Linux containers, open this
folder in VS Code, and choose **Dev Containers: Reopen in Container** using
Microsoft's Dev Containers extension. Place the archive in the folder before
opening the container. Wait for **Lab ready**.

**Local Linux:** with Docker, Docker Compose and Containerlab installed, run:

```bash
bash scripts/start.sh
```

Setup automatically starts six containers: the router, its Linux peer, gNMIc,
the YANG Push receiver, Prometheus and Grafana. The receiver is the upstream
NetCalyx 0.3.0 `udp-notif-print-decoded` example, built automatically from pinned
source, with Telegraf 1.36.4 exporting metrics in the same container. No manual
Rust or Telegraf installation is needed. Do this before class; the
first download/build and router startup can take several minutes.

If you already loaded the image manually, tag it `xrd-control-plane:26.2.1`
inside the development container's Docker daemon. Loading it only into Docker
Desktop does not make it available to the nested lab daemon.

Run the commands below in three terminals inside the development container or
Codespace, from this repository's directory. On local Linux, use the host terminals.

## Demo — 3–4 minutes

### 1. Show the received messages — prepare before presenting

Prepare this in Terminal 1 and leave it visible:

```bash
docker compose logs --follow --tail=60 --no-log-prefix gnmic
```

Prepare Terminal 2 alongside it:

```bash
docker compose logs --follow --tail=60 --no-log-prefix yang-push
```

These show the real messages received by gNMIc and NetCalyx. Initial state
updates describe the current state, rather than a new interface failure.

Say: **“Both subscriptions monitor the same interface. gNMIc subscribes over
gRPC; the router has a configured YANG Push subscription that sends UDP
notifications to NetCalyx.”**

### 2. Show the running lab and log in

In Terminal 3:

```bash
sudo containerlab inspect -t lab.clab.yml
```

Spend about ten seconds pointing to the XRd router and Linux peer, their
running status and management addresses.

Say: **“These are our two running network nodes: the Cisco XRd router and its
Linux peer. The collectors and Grafana run alongside them.”**

Then log in to the router:

```bash
ssh clab@clab-telemetry-xrd
```

Password: `clab@123`

Show the interface:

```text
show interfaces brief
```

Say: **“The interface is currently up. I'll shut it down on the router.”**

### 3. Shut down the interface

In the router CLI:

```text
configure
interface GigabitEthernet0/0/0/0
 shutdown
commit
end
```

Pause about five seconds and point to the DOWN state in both receiver panes.

Say: **“One interface change caused both subscriptions to publish an update.
I did not send another request for its state.”**

`shutdown` changes the candidate configuration. `commit` applies it to the
router; `end` returns to the operational prompt.

#### Explain the received messages — about 45 seconds

Use the live DOWN message in Terminal 1. This is an abridged notification
captured from XRd 26.2.1; additional interface-state fields are omitted here:

```json
{
  "source": "clab-telemetry-xrd:9339",
  "subscription-name": "interface-state",
  "timestamp": 1793817512110495711,
  "time": "2026-11-04T18:38:32.110495711Z",
  "prefix": "openconfig-interfaces:",
  "updates": [
    {
      "Path": "interfaces/interface[name=GigabitEthernet0/0/0/0]/state",
      "values": {
        "interfaces/interface/state": {
          "admin-status": "DOWN",
          "name": "GigabitEthernet0/0/0/0",
          "oper-status": "DOWN"
        }
      }
    }
  ]
}
```

Point out four things:

| Field | What to say |
|---|---|
| `source` | “This identifies the router and its gNMI port.” |
| `timestamp` / `time` | “The notification has a timestamp; this is its readable UTC form.” |
| `prefix` / `Path` | “This identifies the OpenConfig model and interface state.” |
| `values` → `oper-status` | “The router reported DOWN.” |

Say: **“The update tells us which device, which interface, what state, and when.”**

gNMI messages travel as Protocol Buffers over gRPC. This is gNMIc's JSON
presentation of the received message, with client metadata such as `source`
and `subscription-name`; it is not the literal wire encoding.

XRd returns the surrounding `state` container for this leaf subscription.
One shutdown can produce several notifications, including repeated `DOWN`
values as related state fields update. These are real router updates; the
observation counter counts messages containing `oper-status`, not unique outages.

Now point to the live YANG Push message in Terminal 2:

| Field | What to say |
|---|---|
| `ietf-yang-push:push-change-update` | “This reports a change to the subscribed datastore.” |
| `id: 100` | “This identifies the subscription configured on the router.” |
| `yang-patch` → `edit` → `target` | “This identifies the interface state being replaced.” |
| `value` → `openconfig-interfaces:state` → `oper-status` | “This also reports DOWN for the same interface.” |

Say: **“gNMIc renders the received Protobuf message as JSON. Here, XRd sent
a YANG Push JSON payload over UDP-Notif. Both carry real state from the same
OpenConfig model, but their envelopes differ.”**

### 4. Bring it back up

In the router CLI:

```text
configure
interface GigabitEthernet0/0/0/0
 no shutdown
commit
end
```

Point to the UP state in both receiver panes.

Close with: **“Both mechanisms pushed the changes. Their subscription setup,
transport and message envelopes differ.”**

### 5. Optional Grafana recap

Open port **3000** in the VS Code/Codespaces **Ports** tab, or
[localhost:3000](http://localhost:3000) locally. Show the interface timeline and
the observation counters. Keep this brief; the CLI messages are the main demo.

Grafana shows both protocols on the same timeline, with separate last-state,
total-observation and DOWN-observation values. Prometheus samples the latest
received state every second, so very brief transitions can be absent from the
plot even when the receiver logs and counters captured them.

The YANG Push metrics come from the received JSON notifications. NetCalyx
decodes UDP-Notif; Telegraf's standard JSON parser and processors expose the
latest state and cumulative counters on internal port **9273**. Prometheus
scrapes that endpoint, just as it scrapes gNMIc.

## How the subscriptions are prepared

- [configs/gnmic.yml](configs/gnmic.yml) makes gNMIc establish a STREAM /
  ON_CHANGE subscription over gRPC on port 9339.
- [configs/xrd.cfg](configs/xrd.cfg) creates YANG Push subscription **100**
  with on-change updates and initial synchronization. XRd sends JSON using
  UDP-Notif to NetCalyx at **172.20.20.10:9999**, inside the lab network.
- Both select `GigabitEthernet0/0/0/0`'s OpenConfig `oper-status`. XRd can send
  the surrounding state container and several notifications for one transition.
- The YANG Push source is the management interface, so the demo's data-interface
  shutdown leaves both telemetry transports available.

The UDP receiver is NetCalyx's unmodified [upstream example](https://github.com/network-analytics/NetCalyx/blob/f1175e46a6164bfa103ef108385ba9beeff3d753/crates/udp-notif-service/examples/udp-notif-print-decoded.rs).
The receiver image is built once; your XRd archive is imported with `docker load`.
This XRd implementation uses UDP-Notif rather than NETCONF for YANG Push
delivery. See [Cisco's YANG Push documentation](https://www.cisco.com/c/en/us/td/docs/routers/asr9000/software/26xx/programmability/configuration/guide/b-programmability-cg-asr9000-26xx/enhancements-to-data-models-enhancements.html).

## Useful notes

- No client configuration, Docker profiles, or gNMI Set commands are needed
  during the presentation. Only the router CLI changes the interface.
- If SSH is unavailable, enter the same router CLI with
  `docker exec -it clab-telemetry-xrd /pkg/bin/xr_cli.sh`, then use the same login.
- Ctrl+C in Terminal 1 stops viewing logs; it does **not** stop the subscription.
  The same applies to Terminal 2. Use `docker compose stop gnmic yang-push`
  if you want to stop collection.
- If interrupted with the interface down, repeat the `no shutdown` block above.
- Observation counters cover the receiver's current run, including the initial
  state but excluding sync-only messages. DOWN observations are not unique
  failures: XRd can send several notifications for one interface transition.
- YANG Push counters include initial `push-update` and subsequent
  `push-change-update` messages for subscription 100 and the monitored
  interface. Subscription lifecycle messages do not count. Telegraf's native
  cumulative counters reset when its agent restarts; scrapes do not increase them.
- The receiver uses standard gNMIc outputs and filters. There is no custom
  Python collector. NetCalyx decodes and reassembles YANG Push UDP notifications;
  standard command-line formatters display the actual UTF-8 JSON payload.
  [configs/yang-push.toml](configs/yang-push.toml) configures Telegraf's JSON
  parsing, state mapping, cumulative counters and Prometheus output.
- `show yang-push subscriptions` on the router shows subscription 100 as
  **Valid**, with receiver `demo` **Active**. This checks configuration and
  publisher status; the receiver logs prove that messages arrived.

## Restart, stop and troubleshoot

```bash
bash scripts/start.sh       # Recreate the lab and reset monitoring history
bash scripts/stop.sh        # Remove the lab and monitoring services
docker compose logs --tail=40 gnmic yang-push prometheus
docker logs clab-telemetry-xrd --tail=40
```

Startup runs automatically when the development container resumes. If Grafana
does not open, forward port 3000 in the **Ports** tab. Only Grafana is published;
metrics and management ports remain internal.

The router login uses disposable lab credentials. gNMI uses unencrypted gRPC
(`no-tls` / `insecure`) inside the lab network; use TLS in a real deployment.
Grafana provides read-only anonymous access. Stop the Codespace after use to
conserve account quota.
