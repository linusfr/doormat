---
# doormat reads only this front matter; the file is never served.
#
# title:    page and home-screen title (default: Start).
# links:    footer links, e.g. your auth portal's account and logout pages.
# background: optional page background, a URL or a path under /srv (backgrounds/sky.jpg).
# modules:  optional widgets under the date, in this order. Each names its module and takes
#           that module's parameters:
#           weather: where, as postcode + country, city (+ country), or latitude + longitude;
#           locate: browser to use each viewer's own position once they allow it, the place above
#           being the fallback; name (label of that place, default: the place found); unit
#           (celsius or fahrenheit). Fetched by the browser from open-meteo.com; places are looked
#           up once at OpenStreetMap.
# search:   false leaves out the search box.
# labels:   filter chips. badge: true also shows the label on the tile. requires: a group the
#           user needs on top of the app's own group before the tile shows (DOORMAT_AUTH=headers).
# apps:
#   slug:   with DOORMAT_AUTH=headers, the tile shows when the groups header holds
#           DOORMAT_GROUP_FORMAT applied to the slug (default: <slug>:member).
#   icon:   a slug from https://github.com/homarr-labs/dashboard-icons, a path under /srv
#           (icons/foo.png), or a full URL. Without one, the tile shows the first letter.
#   health: marks the tile when the app is down. true checks url, a path checks that path on url's host, or a
#           full URL (e.g. an internal address). Any response below HTTP 500 counts as up.
title: Start

modules:
  - module: weather
    locate: browser
    postcode: "10115"
    country: de

links:
  - name: Account
    url: https://auth.example.com/settings
  - name: Sign out
    url: https://auth.example.com/logout

labels:
  daily:
    title: Daily
    description: Used day to day
  media:
    title: Media
    description: Photos, video and audio
  admin:
    title: Admin
    description: Monitoring and configuration
  lan:
    title: LAN
    description: Only reachable at home
    badge: true
    requires: lan:member

categories:
  - name: Media
    apps:
      - name: Immich
        slug: immich
        description: Photos and videos
        url: https://photos.example.com
        icon: immich
        labels: [daily, media]
      - name: Jellyfin
        slug: jellyfin
        description: Movies and TV
        url: http://192.168.1.10:8096
        icon: jellyfin
        labels: [daily, media, lan]
      - name: Audiobookshelf
        slug: audiobookshelf
        description: Audiobooks and podcasts
        url: https://books.example.com
        icon: audiobookshelf
        labels: [media]

  - name: Home
    apps:
      - name: Home Assistant
        slug: home-assistant
        description: Home automation
        url: http://192.168.1.20:8123
        icon: home-assistant
        labels: [daily, lan]
      - name: Paperless
        slug: paperless
        description: Document archive
        url: https://paperless.example.com
        icon: paperless-ngx
        labels: [daily]
      - name: Recipes
        slug: recipes
        description: What's for dinner
        url: https://recipes.example.com

  - name: Homelab
    apps:
      - name: Grafana
        slug: grafana
        description: Metrics and dashboards
        url: https://grafana.example.com
        icon: grafana
        labels: [admin]
      - name: Status
        slug: gatus
        description: Uptime of all services
        url: https://status.example.com
        icon: https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/gatus.svg
        labels: [admin]
      - name: Router
        slug: router
        description: Network and firewall
        url: http://192.168.1.1
        icon: icons/router.svg
        labels: [admin, lan]
---
