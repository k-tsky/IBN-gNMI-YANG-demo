#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

image=xrd-control-plane:26.2.1
if docker image inspect "$image" >/dev/null 2>&1; then
  exit 0
fi

# Cisco supplies an outer release bundle containing a Docker image archive.
# Accept that bundle, or the extracted Docker archive, without renaming it.
shopt -s nullglob
archives=(xrd-control-plane*.tgz xrd-control-plane*.tar.gz xrd-control-plane*.tar)
if [ "${#archives[@]}" -ne 1 ]; then
  echo 'Place exactly one XRd 26.2.1 control-plane archive in the repository root, then run bash scripts/start.sh.' >&2
  echo 'Alternatively, load your image and tag it xrd-control-plane:26.2.1 in this Docker daemon.' >&2
  exit 1
fi
archive=${archives[0]}
echo "Checking XRd archive: $archive"
if ! contents=$(tar -tf "$archive"); then
  echo 'XRd archive is incomplete or invalid. Replace it with a complete download; do not extract it manually.' >&2
  exit 1
fi

if grep -qxE '(\./)?manifest.json' <<< "$contents"; then
  docker_archive=$archive
else
  nested=$(grep -E '(^|/)xrd-control-plane-container-x64\.dockerv1\.tgz$' <<< "$contents" || true)
  if [ -z "$nested" ] || [ "$(wc -l <<< "$nested")" -ne 1 ]; then
    echo 'No single XRd control-plane Docker image archive found in the release bundle.' >&2
    exit 1
  fi
  mkdir -p .state
  docker_archive=.state/xrd-docker-image.tgz
  tar -xOf "$archive" "$nested" > "$docker_archive"
fi
echo 'Loading XRd into the lab Docker daemon...'
load_output=$(docker load --input "$docker_archive")
printf '%s\n' "$load_output"
loaded_image=$(sed -nE 's/^Loaded image( ID)?: //p' <<< "$load_output" | tail -n1)
if [ -z "$loaded_image" ]; then
  echo 'Docker did not report a loaded image.' >&2
  exit 1
fi
docker tag "$loaded_image" "$image"
if [ "$docker_archive" = .state/xrd-docker-image.tgz ]; then
  rm -- "$docker_archive"
fi
