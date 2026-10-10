package cmd

import (
	"bytes"
	"context"
	"path/filepath"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/BlasterM2A/shell-setup/internal/shellsetup"
)

func fakeOp(events ...shellsetup.Event) operation {
	return func(_ context.Context, ch chan<- shellsetup.Event) (shellsetup.Report, error) {
		defer close(ch)
		for _, ev := range events {
			ch <- ev
		}
		return shellsetup.Report{Tools: []shellsetup.ToolReport{{ID: "starship", Result: shellsetup.ResultOK}}}, nil
	}
}

func staticSummary(shellsetup.Report, error) string { return "SUMMARY\n" }

func TestRunPlainWhenNotTTY(t *testing.T) {
	f, out := newTestFactory(t)
	op := fakeOp(
		shellsetup.PhaseStarted{Phase: shellsetup.PhaseTools},
		shellsetup.ToolFinished{ID: "starship", Result: shellsetup.ResultOK, Version: "1.0"},
		shellsetup.FileFinished{Path: filepath.Join(f.Home, ".zshrc"), Result: shellsetup.ResultModified},
	)

	res, err := runWithProgress(context.Background(), f, "Setting up", op, staticSummary)
	require.NoError(t, err)
	require.NoError(t, res.OpErr)
	assert.Len(t, res.Report.Tools, 1)
	assert.Equal(t, "Setting up\n"+
		"• Installing tools\n"+
		"  ✓ starship  1.0\n"+
		"  ! ~/.zshrc  modified\n"+
		"SUMMARY\n", out.String())
}

func TestRunTUIReturnsReport(t *testing.T) {
	f, _ := newTestFactory(t)
	var screen bytes.Buffer
	op := fakeOp(shellsetup.ToolFinished{ID: "starship", Result: shellsetup.ResultOK})

	res, err := runTUI(context.Background(), f, "Setting up", op, staticSummary,
		tea.WithInput(nil), tea.WithOutput(&screen), tea.WithWindowSize(80, 24))
	require.NoError(t, err)
	assert.Len(t, res.Report.Tools, 1)
	assert.Contains(t, screen.String(), "SUMMARY")
}
