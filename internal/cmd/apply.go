package cmd

import (
	"context"
	"strings"

	"github.com/BlasterM2A/shell-setup/internal/shellsetup"
	"github.com/BlasterM2A/shell-setup/internal/ui/common"
	"github.com/BlasterM2A/shell-setup/internal/ui/notice"
	"github.com/BlasterM2A/shell-setup/internal/ui/statustable"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

// runApply runs Init or Update with live progress, then shows doctor.
func runApply(ctx context.Context, f *Factory, e *shellsetup.Engine, title string, op operation) error {
	var doctor shellsetup.Report
	summary := func(rep shellsetup.Report, opErr error) string {
		c := f.Common()
		if opErr != nil {
			return notice.Render(c, notice.Props{Status: styles.StatusFail, Text: opErr.Error()}) + "\n"
		}
		var err error
		if doctor, err = e.Doctor(ctx); err != nil {
			return notice.Render(c, notice.Props{Status: styles.StatusFail, Text: err.Error()}) + "\n"
		}
		return renderSummary(c, f.Home, e.Paths.LogFile, rep, doctor)
	}
	res, err := runWithProgress(ctx, f, title, op, summary)
	if err != nil {
		return err
	}
	if res.OpErr != nil || res.Report.Failed() || doctor.Failed() {
		return &ExitError{Code: 1}
	}
	return nil
}

func renderSummary(c common.Common, home, logFile string, rep, doctor shellsetup.Report) string {
	var b strings.Builder
	b.WriteString("\n")
	b.WriteString(statustable.Render(c, statustable.Props{Title: "Status", Rows: checkRows(home, doctor)}))
	b.WriteString("\n")
	if rep.Failed() || doctor.Failed() {
		b.WriteString(notice.Render(c, notice.Props{
			Status: styles.StatusFail,
			Text:   "Some required tools are missing. Details: " + shortPath(home, logFile),
		}))
	} else {
		b.WriteString(notice.Render(c, notice.Props{
			Status: styles.StatusOK,
			Text:   "Done. Log out and back in, then select 'JetBrainsMono Nerd Font' in your terminal.",
		}))
	}
	b.WriteString("\n")
	return b.String()
}
