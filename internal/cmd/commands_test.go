package cmd

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestUpdateForceFlag(t *testing.T) {
	f, _ := newTestFactory(t)
	var got *UpdateOptions
	cmd := newUpdateCmd(f, func(_ context.Context, o *UpdateOptions) error { got = o; return nil })
	cmd.SetArgs([]string{"--force"})

	require.NoError(t, cmd.Execute())
	assert.True(t, got.Force)
}

func TestInitRejectsArguments(t *testing.T) {
	f, _ := newTestFactory(t)
	cmd := newInitCmd(f, func(context.Context, *InitOptions) error { return nil })
	cmd.SetArgs([]string{"extra"})
	assert.Error(t, cmd.Execute())
}
