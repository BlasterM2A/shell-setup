package cmd

import (
	"context"

	"github.com/spf13/cobra"
)

// InitOptions are the inputs of init.
type InitOptions struct {
	Factory *Factory
}

func newInitCmd(f *Factory, runF func(context.Context, *InitOptions) error) *cobra.Command {
	opts := &InitOptions{Factory: f}
	return &cobra.Command{
		Use:   "init",
		Short: "Install what is missing and write the shell config",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if runF != nil {
				return runF(cmd.Context(), opts)
			}
			return runInit(cmd.Context(), opts)
		},
	}
}

func runInit(ctx context.Context, opts *InitOptions) error {
	e, err := opts.Factory.Engine()
	if err != nil {
		return err
	}
	return runApply(ctx, opts.Factory, e, "Setting up your shell", e.Init)
}
