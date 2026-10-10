package notice_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/BlasterM2A/shell-setup/internal/ui/common"
	"github.com/BlasterM2A/shell-setup/internal/ui/notice"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

func TestRenderPlain(t *testing.T) {
	c := common.New(styles.New(false))
	got := notice.Render(c, notice.Props{Status: styles.StatusWarn, Text: "careful"})
	assert.Equal(t, "! careful", got)
}
