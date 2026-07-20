package buildinfo

// Version is injected at build time via:
//
//	-ldflags "-X github.com/ynlea/agent-status/pkg/buildinfo.Version=v0.1.2"
//
// Local `go build` without ldflags keeps "dev".
var Version = "dev"
