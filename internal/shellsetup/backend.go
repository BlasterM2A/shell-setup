package shellsetup

import "context"

// Env is what backends work with.
type Env struct {
	System  System
	Fetcher Fetcher
	Paths   Paths
	State   *State
}

// Backend installs and updates tools of one kind. Whether a tool is
// installed is decided by its check, never by the backend.
type Backend interface {
	Install(ctx context.Context, env Env, t Tool) error
	Update(ctx context.Context, env Env, t Tool) error
}

// DefaultBackends maps manifest backend names to implementations.
func DefaultBackends() map[string]Backend {
	return map[string]Backend{
		"apt":     aptBackend{},
		"mise":    miseBackend{},
		"script":  scriptBackend{},
		"archive": archiveBackend{},
		"font":    fontBackend{},
	}
}
