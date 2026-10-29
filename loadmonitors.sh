#!/usr/bin/env bash
# Usage:
#   read -rs KENER_API_KEY && export KENER_API_KEY
#   KENER_URL=https://pdc-status-test.opentechstrategies.com ./load-monitors.sh monitors.json
#
# Creates or updates each monitor in the file, then sets the home page to show
# exactly those monitors, in file order.
set -euo pipefail
: "${KENER_URL:?}" "${KENER_API_KEY:?}"
file="${1:-monitors.json}"
auth=(-H "Authorization: Bearer $KENER_API_KEY" -H "Content-Type: application/json")
curl_() { curl -s --fail-with-body "${auth[@]}" "$@"; }   # print Kener's error body on failure

jq -c '.[]' "$file" | while read -r m; do
  tag=$(jq -r .tag <<<"$m")
  if curl -s -o /dev/null --fail "${auth[@]}" "$KENER_URL/api/v4/monitors/$tag"; then
    curl_ -X PATCH "$KENER_URL/api/v4/monitors/$tag" -d "$m" >/dev/null && echo "updated $tag"
  else
    curl_ -X POST "$KENER_URL/api/v4/monitors" -d "$m" >/dev/null && echo "created $tag"
  fi
done

jq '{monitors: map(.tag)}' "$file" \
  | curl_ -X PATCH "$KENER_URL/api/v4/pages/~home" -d @- && echo "home page updated"