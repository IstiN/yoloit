package main

// yoloit-hub: a thin Go re-implementation of the yoloitd REST contract.
// See docs/remote-hub.md and remote/contract/README.md.

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type config struct {
	Host        string
	Port        string
	DataDir     string
	Token       string
	Actor       string
	CORSOrigins string
}

func configFromEnv() config {
	home, _ := os.UserHomeDir()
	defaultDataDir := filepath.Join(home, ".local", "share", "yoloit-hub")
	return config{
		Host:        envOr("YOLOIT_HUB_HOST", "127.0.0.1"),
		// Cloud Run injects PORT; YOLOIT_HUB_PORT takes precedence when set.
		Port:        envOr("YOLOIT_HUB_PORT", envOr("PORT", "43111")), // yoloitd uses 43110; 43111 allows side-by-side
		DataDir:     envOr("YOLOIT_HUB_DATA_DIR", defaultDataDir),
		Token:       os.Getenv("YOLOIT_HUB_TOKEN"),
		Actor:       envOr("YOLOIT_HUB_ACTOR", "yoloit-hub"),
		CORSOrigins: envOr("YOLOIT_HUB_CORS_ORIGINS", "*"),
	}
}

func envOr(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func main() {
	cfg := configFromEnv()
	flag.StringVar(&cfg.Host, "host", cfg.Host, "listen host (env YOLOIT_HUB_HOST)")
	flag.StringVar(&cfg.Port, "port", cfg.Port, "listen port (env YOLOIT_HUB_PORT)")
	flag.StringVar(&cfg.DataDir, "data-dir", cfg.DataDir, "data directory (env YOLOIT_HUB_DATA_DIR)")
	flag.StringVar(&cfg.Token, "token", cfg.Token, "shared bearer token; empty = open access (env YOLOIT_HUB_TOKEN)")
	flag.StringVar(&cfg.Actor, "actor", cfg.Actor, "actor id recorded in history events (env YOLOIT_HUB_ACTOR)")
	flag.StringVar(&cfg.CORSOrigins, "cors-origins", cfg.CORSOrigins, "comma-separated allowed origins, * for all (env YOLOIT_HUB_CORS_ORIGINS)")
	flag.Parse()

	store := NewStore(cfg.DataDir, cfg.Actor)
	if err := store.Init(); err != nil {
		log.Fatalf("[yoloit-hub] failed to initialize store at %s: %v", cfg.DataDir, err)
	}

	srv := newServer(store, cfg.Token, cfg.CORSOrigins)
	addr := cfg.Host + ":" + cfg.Port
	log.Printf("[yoloit-hub] listening on http://%s (dataDir=%s, auth=%s)", addr, cfg.DataDir, authMode(cfg.Token))
	if err := http.ListenAndServe(addr, srv); err != nil {
		log.Fatalf("[yoloit-hub] server stopped: %v", err)
	}
}

func authMode(token string) string {
	if strings.TrimSpace(token) == "" {
		return "open"
	}
	return fmt.Sprintf("token (%d chars)", len(token))
}
