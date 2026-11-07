#!/usr/bin/env bash
# Pins couchfin-universes in the Umbrel app to the digest of a published version,
# then copies the app into a checkout of the Couchfin Umbrel store.
#
#   Companion/umbrel/pin-image.sh 1.0.0 ../umbrel-apps
#
# Needs the image to be public on GHCR (Package settings -> Change visibility).
set -euo pipefail

version="${1:?usage: pin-image.sh <version> [path to umbrel-apps checkout]}"
store="${2:-}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="${here}/couchfin-universes"
image="ghcr.io/sam-apostel/couchfin-universes"

token="$(curl -fsSL "https://ghcr.io/token?scope=repository:sam-apostel/couchfin-universes:pull" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
digest="$(curl -fsSI \
  -H "Authorization: Bearer ${token}" \
  -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json" \
  "https://ghcr.io/v2/sam-apostel/couchfin-universes/manifests/${version}" \
  | tr -d '\r' | sed -n 's/^docker-content-digest: //Ip')"

if [[ ! "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "Could not read the digest of ${image}:${version}. Is it published and public?" >&2
  exit 1
fi

sed -i.bak -E "s#image: ${image}:[^@]+@sha256:[0-9a-f]{64}#image: ${image}:${version}@${digest}#" "${app}/docker-compose.yml"
sed -i.bak -E "s#^version: \"[^\"]+\"#version: \"${version}\"#" "${app}/umbrel-app.yml"
rm -f "${app}/docker-compose.yml.bak" "${app}/umbrel-app.yml.bak"
echo "Pinned ${image}:${version}@${digest}"

if [[ -n "${store}" ]]; then
  rsync -a --delete "${app}/" "${store}/couchfin-universes/"
  echo "Copied to ${store}/couchfin-universes"
fi
