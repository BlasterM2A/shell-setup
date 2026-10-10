package cmd

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRootVersion(t *testing.T) {
	root := NewRootCmd()
	var out bytes.Buffer
	root.SetOut(&out)
	root.SetArgs([]string{"--version"})

	require.NoError(t, root.Execute())
	assert.Equal(t, "shell-setup dev (none)\n", out.String())
}

func TestExitErrorMessage(t *testing.T) {
	assert.Equal(t, "exit status 3", (&ExitError{Code: 3}).Error())
}
