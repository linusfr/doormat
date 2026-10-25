# Built on the build platform and cross-compiled, so arm64 needs no emulation.
FROM --platform=$BUILDPLATFORM caddy:2.11.7-builder-alpine AS build
ARG TARGETOS TARGETARCH
COPY plugin /src/plugin
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH xcaddy build --with github.com/linusfr/doormat/plugin=/src/plugin

FROM caddy:2.11.7-alpine
COPY --from=build /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile doormat.caddy /etc/caddy/
COPY site/ /srv/

# Caddy needs no state here (no admin API, no certificates), so it can run as nobody. The XDG
# paths point somewhere writable in case a module still reaches for them.
ENV XDG_CONFIG_HOME=/tmp/caddy XDG_DATA_HOME=/tmp/caddy
USER nobody
EXPOSE 8080
