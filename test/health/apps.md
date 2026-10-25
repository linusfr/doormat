---
background: backgrounds/sky.jpg
search: false
modules:
  - module: nope
  - latitude: 1
categories:
  - name: Health
    apps:
      - name: Plain
        url: http://localhost:18310
        health: true
      - name: Locked
        url: http://localhost:18310/app
        health: /locked
      - name: Login
        url: http://localhost:18310/app
        health: /login
      - name: Broken
        url: http://localhost:18310/app
        health: http://localhost:18310/fail
      - name: Gone
        url: http://localhost:18399
        health: true
      - name: Unchecked
        url: http://localhost:18310
---
