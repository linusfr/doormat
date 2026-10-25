#!/usr/bin/env bash
# Expects doormat at $1 serving test/health/apps.md, test/health/targets.Caddyfile running, and
# DOORMAT_HEALTH_INTERVAL short enough that the first round is done within a few seconds.
set -euo pipefail

url=${1:?usage: check.sh <url>}
failed=0

# One line per tile: its name and dot state ("none" without a dot).
tiles() {
  curl -fsS "$url" | tr -d '\n' | awk 'BEGIN { RS = "</a>" } /class="tile"/ {
    $0 = substr($0, index($0, "<a class=\"tile\""))
    state = "none"
    if (match($0, /data-health="[a-z]+"/)) state = substr($0, RSTART + 13, RLENGTH - 14)
    match($0, /<div class="name">[^<]*/)
    print substr($0, RSTART + 18, RLENGTH - 18), state
  }'
}

for _ in $(seq 50); do
  page=$(tiles)
  grep -q unknown <<<"$page" || break
  sleep 0.2
done

for want in "Plain up" "Locked up" "Login up" "Broken down" "Gone down" "Unchecked none"; do
  if grep -qx "$want" <<<"$page"; then
    echo "ok   health: $want"
  else
    echo "FAIL health: want '$want', got '$(grep "^${want%% *} " <<<"$page")'"
    failed=1
  fi
done

exit $failed
