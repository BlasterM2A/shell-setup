package cmd

import (
	"errors"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/stretchr/testify/assert"

	"github.com/BlasterM2A/shell-setup/internal/shellsetup"
	"github.com/BlasterM2A/shell-setup/internal/ui/statustable"
	"github.com/BlasterM2A/shell-setup/internal/ui/steplist"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

func TestEventMsg(t *testing.T) {
	cases := []struct {
		ev   shellsetup.Event
		want tea.Msg
		ok   bool
	}{
		{shellsetup.PhaseStarted{Phase: shellsetup.PhaseTools}, nil, false},
		{
			shellsetup.ToolStarted{ID: "starship", Action: shellsetup.ActionInstall},
			steplist.StepStarted{ID: "tool:starship", Label: "starship (install)"}, true,
		},
		{
			shellsetup.ToolFinished{ID: "starship", Action: shellsetup.ActionInstall, Result: shellsetup.ResultOK, Version: "1.0"},
			steplist.StepFinished{ID: "tool:starship", Label: "starship (install)", Status: styles.StatusOK, Detail: "1.0"}, true,
		},
		{
			shellsetup.ToolFinished{ID: "claude", Result: shellsetup.ResultWarned, Err: errors.New("claude: boom")},
			steplist.StepFinished{ID: "tool:claude", Label: "claude", Status: styles.StatusWarn, Detail: "claude: boom"}, true,
		},
		{
			shellsetup.FileFinished{Path: "/h/.zshrc", Result: shellsetup.ResultModified},
			steplist.StepFinished{ID: "file:/h/.zshrc", Label: "~/.zshrc", Status: styles.StatusWarn, Detail: "modified"}, true,
		},
	}
	for _, tc := range cases {
		got, ok := eventMsg("/h", tc.ev)
		assert.Equal(t, tc.ok, ok, "%#v", tc.ev)
		assert.Equal(t, tc.want, got, "%#v", tc.ev)
	}
}

func TestCheckRows(t *testing.T) {
	rep := shellsetup.Report{Checks: []shellsetup.CheckResult{
		{Name: "zsh", Status: shellsetup.CheckOK, Detail: "zsh 5.9"},
		{Name: "/h/.zshrc", Status: shellsetup.CheckWarn, Detail: "modified"},
		{Name: "antidote", Status: shellsetup.CheckFail, Detail: "not installed"},
		{Name: "version", Status: shellsetup.CheckSkip},
	}}
	assert.Equal(t, []statustable.Row{
		{Status: styles.StatusOK, Name: "zsh", Detail: "zsh 5.9"},
		{Status: styles.StatusWarn, Name: "~/.zshrc", Detail: "modified"},
		{Status: styles.StatusFail, Name: "antidote", Detail: "not installed"},
		{Status: styles.StatusSkip, Name: "version"},
	}, checkRows("/h", rep))
}
