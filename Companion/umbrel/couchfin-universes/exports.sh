# Zero-touch Seerr: read the API key the official Seerr app (id "jellyseerr")
# generated, so ghost entries get posters and request status without pasting
# anything. Same approach as couchfin-maintainerr.
#
# umbrelOS sources this file with `set -euo pipefail`, so every step that may
# fail is guarded and a missing file simply yields an empty value.

couchfin_universes_data_root() {
  local app="${1}"
  local root=""
  root="$(printf '%s' "${SCRIPT_APP_DATA_ROOTS:-}" | jq --raw-output --arg app "${app}" '.[$app] // empty' 2>/dev/null)" || root=""
  if [[ -z "${root}" ]]; then
    root="${UMBREL_ROOT}/app-data/${app}/data"
  fi
  printf '%s' "${root}"
}

couchfin_universes_seerr_api_key() {
  local file=""
  file="$(couchfin_universes_data_root jellyseerr)/config/settings.json"
  if [[ -f "${file}" ]]; then
    jq --raw-output '.main.apiKey // empty' "${file}" 2>/dev/null || true
  fi
}

APP_COUCHFIN_UNIVERSES_SEERR_API_KEY="$(couchfin_universes_seerr_api_key)"
export APP_COUCHFIN_UNIVERSES_SEERR_API_KEY
if [[ -n "${APP_COUCHFIN_UNIVERSES_SEERR_API_KEY}" ]]; then
  export APP_COUCHFIN_UNIVERSES_SEERR_URL="http://jellyseerr_server_1:5055"
else
  export APP_COUCHFIN_UNIVERSES_SEERR_URL=""
fi
