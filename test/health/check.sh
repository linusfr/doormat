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

expected=("Plain up" "Locked up" "Login up" "Broken down" "Gone down" "Unchecked none")

# Retry until every state matches: a round that started before a target was ready corrects
# itself one interval later.
for _ in $(seq 50); do
  page=$(tiles)
  all=1
  for want in "${expected[@]}"; do grep -qx "$want" <<<"$page" || all=0; done
  [ $all = 1 ] && break
  sleep 0.2
done

for want in "${expected[@]}"; do
  if grep -qx "$want" <<<"$page"; then
    echo "ok   health: $want"
  else
    echo "FAIL health: want '$want', got '$(grep "^${want%% *} " <<<"$page")'"
    failed=1
  fi
done

page=$(curl -fsS "$url")
if grep -q 'data-label="health-down"[^>]*>Down<' <<<"$page" && ! grep -q 'data-label="health-down"[^>]*hidden' <<<"$page"; then
  echo "ok   health: Down chip shows while apps are down"
else
  echo "FAIL health: Down chip missing or hidden"
  failed=1
fi
if grep -q 'data-labels="[^"]*health-down' <<<"$page"; then
  echo "ok   health: down tiles carry the health-down label"
else
  echo "FAIL health: no tile carries health-down"
  failed=1
fi

if grep -q "class=\"has-background\" style=\"--background: url('/backgrounds/sky.jpg'); --dim: 0\"" <<<"$page"; then
  echo "ok   background path is served from /srv"
else
  echo "FAIL background missing"
  failed=1
fi
if grep -q '<!-- doormat: unknown module nope -->' <<<"$page" && grep -q '<!-- doormat: unknown module  -->' <<<"$page"; then
  echo "ok   unknown and nameless modules are skipped, not fatal"
else
  echo "FAIL unknown module handling"
  failed=1
fi

if grep -q 'id="q"' <<<"$page"; then
  echo "FAIL search: false still renders the search box"
  failed=1
else
  echo "ok   search: false leaves out the search box"
fi

exit $failed
