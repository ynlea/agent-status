package main

import (
	"flag"
	"log"
	"net/http"
	"os"

	"github.com/ynlea/agent-status/internal/server"
	"github.com/ynlea/agent-status/internal/store"
)

func main() {
	addr := flag.String("addr", envOr("AGENT_STATUS_ADDR", ":8080"), "listen address")
	key := flag.String("key", envOr("AGENT_STATUS_KEY", "dev-secret"), "pre-shared key")
	flag.Parse()

	srv := &server.Server{
		Key:   *key,
		Store: store.NewMemory(50),
		Hub:   server.NewHub(),
	}
	// mock uses memory store only

	log.Printf("agent-status mock listening on %s (key from -key / AGENT_STATUS_KEY)", *addr)
	if err := http.ListenAndServe(*addr, srv.Routes()); err != nil {
		log.Fatal(err)
	}
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
