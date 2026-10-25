// Package doormat adds tile health checks to doormat's template.
package doormat

import (
	"bytes"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"text/template"
	"time"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/caddyconfig/caddyfile"
	"github.com/caddyserver/caddy/v2/modules/caddyhttp/templates"
	"go.uber.org/zap"
	"gopkg.in/yaml.v3"
)

const (
	timeout = 5 * time.Second
	// Enough to see a response is a response; a heavy page costs no more than this.
	maxBody     = 64 << 10
	concurrency = 8
)

func init() {
	caddy.RegisterModule(Health{})
}

// Health checks every tile's health target in the background and gives the template
// {{ health .health .url }}, which returns "up", "down", "unknown" (not checked yet) or ""
// (no health key).
type Health struct {
	// Path of apps.md. It is re-read every round, so edits apply without a restart.
	Apps     string         `json:"apps,omitempty"`
	Interval caddy.Duration `json:"interval,omitempty"`

	client *http.Client
	logger *zap.Logger
	// Behind a pointer because Caddy copies the module value; a lock must not be copied.
	state *state
}

// state holds the outcome of the latest round: target URL -> up.
type state struct {
	mu      sync.RWMutex
	results map[string]bool
}

// CaddyModule returns the Caddy module information.
func (Health) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "http.handlers.templates.functions.doormat_health",
		New: func() caddy.Module { return new(Health) },
	}
}

// Provision starts the checks. They stop when ctx is cancelled, which Caddy does when this
// config is unloaded.
func (h *Health) Provision(ctx caddy.Context) error {
	h.logger = ctx.Logger()
	if h.Interval <= 0 {
		h.Interval = caddy.Duration(time.Minute)
	}
	h.state = &state{results: map[string]bool{}}
	h.client = &http.Client{
		Timeout: timeout,
		// A login redirect already proves the app answers; following it would check the auth server.
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	go h.run(ctx)
	return nil
}

func (h *Health) run(ctx caddy.Context) {
	ticker := time.NewTicker(time.Duration(h.Interval))
	defer ticker.Stop()
	for {
		h.round(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (h *Health) round(ctx caddy.Context) {
	targets, err := readTargets(h.Apps)
	if err != nil {
		h.logger.Error("reading apps", zap.String("file", h.Apps), zap.Error(err))
		return
	}

	results := make(map[string]bool, len(targets))
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, concurrency)
	for _, target := range targets {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-sem }()
			up, err := check(ctx, h.client, target)
			mu.Lock()
			results[target] = up
			mu.Unlock()
			h.logChange(target, up, err)
		}()
	}
	wg.Wait()

	h.state.mu.Lock()
	h.state.results = results
	h.state.mu.Unlock()
}

func (h *Health) logChange(target string, up bool, err error) {
	h.state.mu.RLock()
	was, known := h.state.results[target]
	h.state.mu.RUnlock()
	if known && was == up {
		return
	}
	if up {
		h.logger.Info("target up", zap.String("target", target))
	} else {
		h.logger.Warn("target down", zap.String("target", target), zap.Error(err))
	}
}

// check counts any HTTP response below 500 as up: a 401 or a login redirect means the app answers.
func check(ctx caddy.Context, client *http.Client, target string) (bool, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return false, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()
	_, _ = io.CopyN(io.Discard, resp.Body, maxBody)
	if resp.StatusCode >= 500 {
		return false, &statusError{resp.StatusCode}
	}
	return true, nil
}

type statusError struct{ code int }

func (e *statusError) Error() string { return "HTTP " + http.StatusText(e.code) }

// CustomTemplateFunctions implements templates.CustomFunctions.
func (h *Health) CustomTemplateFunctions() template.FuncMap {
	return template.FuncMap{"health": h.status}
}

func (h *Health) status(health any, appURL string) string {
	target := resolve(health, appURL)
	if target == "" {
		return ""
	}
	h.state.mu.RLock()
	up, known := h.state.results[target]
	h.state.mu.RUnlock()
	switch {
	case !known:
		return "unknown"
	case up:
		return "up"
	default:
		return "down"
	}
}

// resolve turns an app's health key into the URL to check: true checks the app's url, a path
// is taken relative to the app's host, anything else must be a full URL.
func resolve(health any, appURL string) string {
	switch v := health.(type) {
	case bool:
		if v {
			return appURL
		}
	case string:
		if strings.HasPrefix(v, "/") {
			u, err := url.Parse(appURL)
			if err != nil || u.Host == "" {
				return ""
			}
			return u.Scheme + "://" + u.Host + v
		}
		if strings.Contains(v, "://") {
			return v
		}
	}
	return ""
}

func readTargets(file string) ([]string, error) {
	raw, err := os.ReadFile(file)
	if err != nil {
		return nil, err
	}
	var doc struct {
		Categories []struct {
			Apps []struct {
				URL    string `yaml:"url"`
				Health any    `yaml:"health"`
			} `yaml:"apps"`
		} `yaml:"categories"`
	}
	if err := yaml.Unmarshal(frontMatter(raw), &doc); err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	var targets []string
	for _, c := range doc.Categories {
		for _, a := range c.Apps {
			if t := resolve(a.Health, a.URL); t != "" && !seen[t] {
				seen[t] = true
				targets = append(targets, t)
			}
		}
	}
	return targets, nil
}

// frontMatter returns the YAML between the leading "---" lines, as Caddy's splitFrontMatter does.
func frontMatter(raw []byte) []byte {
	raw = bytes.TrimPrefix(raw, []byte("\xef\xbb\xbf"))
	rest, ok := bytes.CutPrefix(raw, []byte("---"))
	if !ok {
		return nil
	}
	if i := bytes.Index(rest, []byte("\n---")); i >= 0 {
		return rest[:i]
	}
	return rest
}

// UnmarshalCaddyfile sets up the module from Caddyfile tokens:
//
//	doormat_health {
//		apps     <path>
//		interval <duration>
//	}
func (h *Health) UnmarshalCaddyfile(d *caddyfile.Dispenser) error {
	d.Next()
	for d.NextBlock(0) {
		switch d.Val() {
		case "apps":
			if !d.Args(&h.Apps) {
				return d.ArgErr()
			}
		case "interval":
			var s string
			if !d.Args(&s) {
				return d.ArgErr()
			}
			dur, err := caddy.ParseDuration(s)
			if err != nil {
				return d.Errf("interval: %v", err)
			}
			h.Interval = caddy.Duration(dur)
		default:
			return d.Errf("unknown option %q", d.Val())
		}
	}
	return nil
}

var (
	_ caddy.Provisioner         = (*Health)(nil)
	_ caddyfile.Unmarshaler     = (*Health)(nil)
	_ templates.CustomFunctions = (*Health)(nil)
)
