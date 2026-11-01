#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pdk_cache="${PDK_ROOT:-${HOME}/.volare}"
mkdir -p "$pdk_cache"
pdk_storage="${OPENLANE_PDK_VOLUME:-$pdk_cache}"

# OpenLane 2.3.10, pinned multi-architecture image (Linux ARM64 and AMD64).
image="ghcr.io/efabless/openlane2@sha256:37c3bd4ea0534a276cb2deb88d601044857bad2807b9bc5b36efe9d02c62624e"
exec docker run --rm --init \
    --user "$(id -u):$(id -g)" \
    --env HOME=/tmp --env PDK_ROOT=/pdk \
    --volume "$repo_root:/work" --volume "$pdk_storage:/pdk" \
    --workdir /work "$image" "$@"
