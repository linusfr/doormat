#!/usr/bin/env just --justfile
# ==========================================
# DEFAULT
# ==========================================

# Show all available commands
@default:
    just --list

image_name := "doormat"
port := "8080"
# Pinned in package.json, where Dependabot can see it.
impeccable := `jq -r .devDependencies.impeccable package.json`

# ==========================================
# BUILD
# ==========================================

# Caddy with the health plugin, at the version the image uses
build:
    #!/usr/bin/env bash
    set -euo pipefail
    # xcaddy recompiles every time; skip it when nothing it builds from has changed.
    if [ -x dist/caddy ] && [ -z "$(find plugin Dockerfile -newer dist/caddy)" ]; then exit 0; fi
    version=$(sed -n 's/^FROM caddy:\([0-9.]*\)-alpine$/\1/p' Dockerfile)
    xcaddy build "v$version" --output dist/caddy --with github.com/linusfr/doormat/plugin=./plugin

# Vet and unit-test the plugin
plugin-test:
    #!/usr/bin/env bash
    set -euo pipefail
    cd plugin
    unformatted=$(gofmt -l .)
    if [ -n "$unformatted" ]; then echo "needs gofmt:"; echo "$unformatted"; exit 1; fi
    go vet ./...
    go test -race ./...

# ==========================================
# DEV
# ==========================================

# Live reload, every tile visible
dev apps="examples/apps.md" icons="examples/icons": build (_tree "dev/srv" apps icons) (_serve "dev/srv" "off" "" "")

# Live reload, as a user with these groups
dev-as groups="immich:member,grafana:member" name="Ada" apps="examples/apps.md" icons="examples/icons": build (_tree "dev/srv" apps icons) (_serve "dev/srv" "headers" groups name)

# Symlinks, so edits to site/ and apps.md show up live
_tree dir apps icons:
    #!/usr/bin/env bash
    set -euo pipefail
    rm -rf {{dir}} && mkdir -p {{dir}}
    for f in index.html favicon.svg apple-touch-icon.png; do ln -s "$PWD/site/$f" {{dir}}/$f; done
    ln -s "$(cd "$(dirname {{apps}})" && pwd)/$(basename {{apps}})" {{dir}}/apps.md
    ln -s "$(cd {{icons}} && pwd)" {{dir}}/icons

_serve dir auth groups name:
    #!/usr/bin/env bash
    set -euo pipefail
    url=http://localhost:{{port}}
    echo "doormat on $url (auth: {{auth}}) — edits to site/ and apps.md reload the browser"
    ( sleep 1; {{ if os() == "macos" { "open" } else { "xdg-open" } }} "$url" >/dev/null 2>&1 || true ) &
    DOORMAT_DEV=1 DOORMAT_AUTH={{auth}} DOORMAT_ROOT={{dir}} DOORMAT_PORT={{port}} \
      DEV_GROUPS="{{groups}}" DEV_NAME="{{name}}" dist/caddy run --config dev/Caddyfile

# ==========================================
# TEST
# ==========================================

# Smoke test against the local build
test: build (_tree "test/srv" "examples/apps.md" "examples/icons") (_tree "test/health-srv" "test/health/apps.md" "examples/icons")
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill $(jobs -p) 2>/dev/null; rm -rf test/srv test/health-srv' EXIT
    DOORMAT_ROOT=test/srv DOORMAT_PORT=18080 dist/caddy run --config Caddyfile >/dev/null 2>&1 &
    DOORMAT_ROOT=test/srv DOORMAT_PORT=18081 DOORMAT_AUTH=off dist/caddy run --config Caddyfile >/dev/null 2>&1 &
    dist/caddy run --config test/health/targets.Caddyfile >/dev/null 2>&1 &
    # Targets first: doormat checks once at start, and a target not yet listening reads as down.
    for _ in $(seq 50); do curl -fs -o /dev/null localhost:18310 && break; sleep 0.1; done
    DOORMAT_ROOT=test/health-srv DOORMAT_PORT=18083 DOORMAT_AUTH=off DOORMAT_HEALTH_INTERVAL=1s \
      dist/caddy run --config Caddyfile >/dev/null 2>&1 &
    for p in 18080 18081 18083; do
      for _ in $(seq 50); do curl -fs -o /dev/null localhost:$p && break; sleep 0.1; done
    done
    test/smoke.sh http://localhost:18080 http://localhost:18081
    test/health/check.sh http://localhost:18083

# Design lint (impeccable): contrast, text size, touch targets and similar
design: build (_tree "test/design-srv" "examples/apps.md" "examples/icons")
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'kill $(jobs -p) 2>/dev/null; rm -rf test/design-srv' EXIT
    DOORMAT_ROOT=test/design-srv DOORMAT_PORT=18082 DOORMAT_AUTH=off dist/caddy run --config Caddyfile >/dev/null 2>&1 &
    for _ in $(seq 50); do curl -fs -o /dev/null localhost:18082 && break; sleep 0.1; done
    IMPECCABLE_NO_TELEMETRY=1 npx -y impeccable@{{impeccable}} detect http://localhost:18082

# Install the impeccable skill and its edit hooks for Claude Code in this repo
design-setup:
    IMPECCABLE_NO_TELEMETRY=1 npx -y impeccable@{{impeccable}} install --project --providers=claude-code -y

# Build the image
image:
    docker build -t {{image_name}}:dev .

# Smoke test against the image
image-test: image
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'docker rm -f doormat-headers doormat-off >/dev/null 2>&1' EXIT
    mount=(-v "$PWD/examples/apps.md:/srv/apps.md:ro" -v "$PWD/examples/icons:/srv/icons:ro")
    docker run -d --name doormat-headers -p 18080:8080 "${mount[@]}" {{image_name}}:dev >/dev/null
    docker run -d --name doormat-off -p 18081:8080 -e DOORMAT_AUTH=off "${mount[@]}" {{image_name}}:dev >/dev/null
    for p in 18080 18081; do
      for _ in $(seq 50); do curl -fs -o /dev/null localhost:$p && break; sleep 0.1; done
    done
    test/smoke.sh http://localhost:18080 http://localhost:18081

# ==========================================
# QUALITY
# ==========================================

fmt:
    caddy fmt --overwrite Caddyfile
    caddy fmt --overwrite dev/Caddyfile
    caddy fmt --overwrite doormat.caddy

fmt-check:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in Caddyfile dev/Caddyfile doormat.caddy; do
      caddy fmt "$f" | diff -q - "$f" >/dev/null || { echo "needs caddy fmt: $f"; exit 1; }
    done

# Everything CI runs that needs no Docker
check: plugin-test test design
    dist/caddy validate --config Caddyfile
    prek run --all-files

# Install the git hooks
hooks:
    prek install --install-hooks
    prek install --hook-type commit-msg

clean:
    rm -rf dist dev/srv test/srv test/design-srv test/health-srv
