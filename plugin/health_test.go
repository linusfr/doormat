package doormat

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/caddyserver/caddy/v2"
)

func TestResolve(t *testing.T) {
	tests := []struct {
		health any
		appURL string
		want   string
	}{
		{true, "https://photos.example.com", "https://photos.example.com"},
		{false, "https://photos.example.com", ""},
		{nil, "https://photos.example.com", ""},
		{"/api/ping", "https://photos.example.com/albums?x=1", "https://photos.example.com/api/ping"},
		{"http://immich:2283/ping", "https://photos.example.com", "http://immich:2283/ping"},
		{"/ping", "not a url", ""},
		{"ping", "https://photos.example.com", ""},
	}
	for _, tt := range tests {
		if got := resolve(tt.health, tt.appURL); got != tt.want {
			t.Errorf("resolve(%#v, %q) = %q, want %q", tt.health, tt.appURL, got, tt.want)
		}
	}
}

func TestCheck(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/ok":
		case "/login":
			http.Redirect(w, r, "https://auth.example.com/", http.StatusFound)
		case "/locked":
			w.WriteHeader(http.StatusUnauthorized)
		case "/broken":
			w.WriteHeader(http.StatusBadGateway)
		}
	}))
	defer srv.Close()
	closed := httptest.NewServer(http.NotFoundHandler())
	closed.Close()

	h := &Health{}
	ctx, cancel := caddy.NewContext(caddy.Context{Context: context.Background()})
	defer cancel()
	if err := h.Provision(ctx); err != nil {
		t.Fatal(err)
	}

	tests := map[string]bool{
		srv.URL + "/ok":     true,
		srv.URL + "/login":  true,
		srv.URL + "/locked": true,
		srv.URL + "/broken": false,
		closed.URL:          false,
	}
	for target, want := range tests {
		if got, err := check(ctx, h.client, target); got != want {
			t.Errorf("check(%s) = %v (%v), want %v", target, got, err, want)
		}
	}
}

func TestRoundAndStatus(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/down" {
			w.WriteHeader(http.StatusInternalServerError)
		}
	}))
	defer srv.Close()

	apps := filepath.Join(t.TempDir(), "apps.md")
	err := os.WriteFile(apps, []byte(`---
categories:
  - name: Test
    apps:
      - name: Up
        url: `+srv.URL+`
        health: true
      - name: Down
        url: `+srv.URL+`
        health: /down
      - name: Unchecked
        url: `+srv.URL+`
---
`), 0o644)
	if err != nil {
		t.Fatal(err)
	}

	h := &Health{Apps: apps, Interval: caddy.Duration(time.Hour)}
	ctx, cancel := caddy.NewContext(caddy.Context{Context: context.Background()})
	defer cancel()
	if err := h.Provision(ctx); err != nil {
		t.Fatal(err)
	}
	h.round(ctx)

	if got := h.status(true, srv.URL); got != "up" {
		t.Errorf("up target: %q", got)
	}
	if got := h.status("/down", srv.URL); got != "down" {
		t.Errorf("down target: %q", got)
	}
	if got := h.status(nil, srv.URL); got != "" {
		t.Errorf("no health key: %q", got)
	}
	if got := h.status("http://elsewhere.invalid/", srv.URL); got != "unknown" {
		t.Errorf("target not in apps.md: %q", got)
	}
}
