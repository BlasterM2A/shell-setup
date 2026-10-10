package main

import (
	"os"

	"github.com/BlasterM2A/shell-setup/internal/cmd"
)

func main() {
	os.Exit(cmd.Execute())
}
