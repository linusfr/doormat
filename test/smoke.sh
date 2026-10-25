#!/usr/bin/env bash
# Expects two instances serving examples/apps.md: DOORMAT_AUTH=headers at $1, off at $2.
set -euo pipefail

headers_url=${1:?usage: smoke.sh <headers-url> <off-url>}
off_url=${2:?usage: smoke.sh <headers-url> <off-url>}
failed=0

page() {
  local url=$1
  shift
  curl -fsS "$@" "$url"
}

expect() {
  local desc=$1 body=$2 needle=$3
  if grep -qF -- "$needle" <<<"$body"; then
    echo "ok   $desc"
  else
    echo "FAIL $desc: missing '$needle'"
    failed=1
  fi
}

reject() {
  local desc=$1 body=$2 needle=$3
  if grep -qF -- "$needle" <<<"$body"; then
    echo "FAIL $desc: found '$needle'"
    failed=1
  else
    echo "ok   $desc"
  fi
}

body=$(page "$headers_url" -H "Remote-Groups: immich:member, grafana:member" -H "Remote-Name: Ada")
expect "granted app shows" "$body" 'href="https://photos.example.com"'
expect "second grant shows" "$body" 'href="https://grafana.example.com"'
reject "ungranted app is not in the HTML" "$body" 'paperless.example.com'
reject "category without granted apps is dropped" "$body" '<h2>Home</h2>'
expect "greets by name" "$body" ', Ada</h1>'
expect "footer links render" "$body" 'href="https://auth.example.com/logout"'

body=$(page "$headers_url" -H "Remote-Groups: jellyfin:member")
reject "label requirement hides the app" "$body" '192.168.1.10:8096'
body=$(page "$headers_url" -H "Remote-Groups: jellyfin:member,lan:member")
expect "label requirement met shows the app" "$body" '192.168.1.10:8096'
expect "badge label renders" "$body" 'class="badge"'

body=$(page "$headers_url")
expect "missing header explains itself" "$body" 'No groups arrived in the Remote-Groups header'
reject "missing header shows nothing" "$body" 'class="tile"'

body=$(page "$headers_url" -H "Remote-Groups: immich:member" -H 'Remote-Name: <script>x</script>')
reject "name is escaped" "$body" '<script>x</script>'

body=$(page "$headers_url/apps.md" -H "Remote-Groups: immich:member")
reject "apps.md is never served" "$body" 'categories:'

body=$(page "$off_url")
expect "weather module renders its parameters" "$body" 'data-postcode="10115" data-country="de" data-city="" data-latitude="" data-longitude="" data-unit="celsius" data-name=""'
expect "search box by default" "$body" 'id="q"'
reject "no background unless configured" "$body" 'class="has-background"'
expect "auth off shows every app" "$body" 'href="https://paperless.example.com"'
expect "auth off ignores label requirements" "$body" '192.168.1.10:8096'

status=$(curl -s -o /dev/null -w '%{http_code}' "$off_url/icons/router.svg")
[ "$status" = 200 ] && echo "ok   own icons are served" || { echo "FAIL own icons: HTTP $status"; failed=1; }

exit $failed
