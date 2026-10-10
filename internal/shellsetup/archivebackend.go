package shellsetup

import (
	"context"
	"errors"
)

// Temporary stub; Task 12 replaces it.
type archiveBackend struct{}

func (archiveBackend) Install(context.Context, Env, Tool) error {
	return errors.New("archive backend: not implemented")
}
func (archiveBackend) Update(context.Context, Env, Tool) error {
	return errors.New("archive backend: not implemented")
}
