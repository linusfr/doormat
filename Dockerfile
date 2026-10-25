FROM caddy:2.11.7-alpine

COPY Caddyfile doormat.caddy /etc/caddy/
COPY site/ /srv/

# Caddy needs no state here (no admin API, no certificates), so it can run as nobody. The XDG
# paths point somewhere writable in case a module still reaches for them.
ENV XDG_CONFIG_HOME=/tmp/caddy XDG_DATA_HOME=/tmp/caddy
USER nobody
EXPOSE 8080
