#!/usr/bin/env bash
# Run the real gNMIc CLI on the lab network without installing it locally.
set -euo pipefail
exec docker run --rm --network clab ghcr.io/openconfig/gnmic:0.42.1 \
  -a clab-telemetry-srl:57400 -u admin -p 'NokiaSrl1!' \
  --skip-verify -e json_ietf "$@"
