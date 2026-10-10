// Package cmd wires the cobra commands: it binds UI components to the
// shellsetup domain and holds no business logic of its own.
package cmd

import (
	"errors"
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

// Set via -ldflags at release time (see .goreleaser.yml).
var (
	version  = "dev"
	commit   = "none"
	repoSlug = "BlasterM2A/shell-setup"
)

// ExitError ends the process with Code without printing anything else;
// commands return it after they have already reported the problem.
type ExitError struct{ Code int }

func (e *ExitError) Error() string { return fmt.Sprintf("exit status %d", e.Code) }

// NewRootCmd builds the command tree.
func NewRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:           "shell-setup",
		Short:         "Bootstrap and maintain your zsh environment",
		Version:       fmt.Sprintf("%s (%s)", version, commit),
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.SetVersionTemplate("shell-setup {{.Version}}\n")
	return root
}

// Execute runs the CLI and returns the process exit code.
func Execute() int {
	if err := NewRootCmd().Execute(); err != nil {
		var exitErr *ExitError
		if errors.As(err, &exitErr) {
			return exitErr.Code
		}
		fmt.Fprintln(os.Stderr, "Error:", err)
		return 1
	}
	return 0
}
