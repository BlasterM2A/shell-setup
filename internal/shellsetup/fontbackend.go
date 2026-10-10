package shellsetup

import (
	"context"
	"errors"
)

// Temporary stub; Task 12 replaces it.
type fontBackend struct{}

func (fontBackend) Install(context.Context, Env, Tool) error {
	return errors.New("font backend: not implemented")
}
func (fontBackend) Update(context.Context, Env, Tool) error {
	return errors.New("font backend: not implemented")
}
