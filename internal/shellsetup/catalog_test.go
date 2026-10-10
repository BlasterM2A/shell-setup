package shellsetup

import (
	"testing"
	"testing/fstest"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func toolIDs(tools []Tool) []string {
	ids := make([]string, len(tools))
	for i, t := range tools {
		ids[i] = t.ID
	}
	return ids
}

func TestDefaultCatalogOrder(t *testing.T) {
	cat, err := DefaultCatalog()
	require.NoError(t, err)
	assert.Equal(t, []string{
		"mise", "zsh", // built-ins first
		"agy", "antidote", "claude", "copilot", "fzf", "junie", "nerdfont", "starship", "zoxide",
	}, toolIDs(cat.Tools()))
}

func TestDefaultCatalogFilesExist(t *testing.T) {
	cat, err := DefaultCatalog()
	require.NoError(t, err)
	for _, t2 := range cat.Tools() {
		for _, f := range t2.Files {
			_, err := cat.File(f.Src)
			assert.NoError(t, err, "%s: %s", t2.ID, f.Src)
		}
	}
	for _, src := range []string{"files/profile/zshrc", "files/profile/zshrc-stub", "files/profile/20-core.zsh", "files/profile/70-aliases.zsh"} {
		_, err := cat.File(src)
		assert.NoError(t, err, src)
	}
}

func manifest(body string) *fstest.MapFile { return &fstest.MapFile{Data: []byte(body)} }

const minimal = `
kind = "plugin"
[install]
backend = "fake"
[check]
cmd = ["x"]
`

func TestLoadCatalogErrors(t *testing.T) {
	cases := map[string]struct {
		fs   fstest.MapFS
		want string
	}{
		"id mismatch": {
			fstest.MapFS{"a.toml": manifest(`id = "b"` + minimal)},
			`id "b" must match file name "a"`,
		},
		"unknown field": {
			fstest.MapFS{"a.toml": manifest(`id = "a"` + "\nbogus = 1" + minimal)},
			"bogus",
		},
		"unknown dependency": {
			fstest.MapFS{"a.toml": manifest(`id = "a"` + "\ndepends = [\"ghost\"]" + minimal)},
			`unknown dependency "ghost"`,
		},
		"cycle": {
			fstest.MapFS{
				"a.toml": manifest(`id = "a"` + "\ndepends = [\"b\"]" + minimal),
				"b.toml": manifest(`id = "b"` + "\ndepends = [\"a\"]" + minimal),
			},
			"dependency cycle between: a, b",
		},
		"missing file": {
			fstest.MapFS{"a.toml": manifest(`id = "a"` + minimal + "\n[[files]]\nsrc = \"files/nope\"\ndest = \"~/x\"\n")},
			"files/nope",
		},
		"check needs one of cmd or path": {
			fstest.MapFS{"a.toml": manifest("id = \"a\"\nkind = \"plugin\"\n[install]\nbackend = \"fake\"\n[check]\n")},
			"check needs exactly one of cmd or path",
		},
		"empty post_install command": {
			fstest.MapFS{"a.toml": manifest("id = \"a\"\npost_install = [[]]" + minimal)},
			"post_install",
		},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := LoadCatalog(tc.fs)
			assert.ErrorContains(t, err, tc.want)
		})
	}
}
