# shell-setup CLI — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sustituir el script `install.sh` por un binario Go `shell-setup` (CLI + TUI) con los comandos `init`, `update`, `doctor` y `self-update`, distribuido por GitHub Releases y arrancado por un `install.sh` mínimo.

**Architecture:** Un único módulo Go. `main.go` → `internal/cmd` (cobra, capa fina de integración) → `internal/shellsetup` (todo el dominio en un paquete, estilo `internal/chezmoi`). Las herramientas se describen con manifiestos TOML embebidos (`registry/*.toml`) y se instalan mediante backends (`apt`, `mise`, `script`, `archive`, `font`). Todo el I/O pasa por la interfaz `System`. El dominio publica eventos por un canal; `cmd` los conecta a componentes de `internal/ui` (bubbletea/lipgloss) o a salida plana (`internal/iostreams`). `ui/styles` es la única fuente de estilo.

**Tech Stack:** Go 1.27.2, cobra v1.10.2, charm.land/bubbletea/v2 v2.1.0, charm.land/lipgloss/v2 v2.0.6, charm.land/log/v2 v2.0.1, knadh/koanf v2.3.8, pelletier/go-toml/v2 v2.4.3, hashicorp/go-retryablehttp v0.7.8, creativeprojects/go-selfupdate v1.6.0, testify v1.12.1, rogpeppe/go-internal v1.15.0 (testscript), charmbracelet/x/exp/golden, golang.org/x/term. Toolchain: mise + Task v3.54.0, goreleaser v2.18.3, golangci-lint v2.14.0.

**Spec:** `docs/superpowers/specs/2026-10-10-shell-setup-cli-design.md`

## Global Constraints

- Ruta del módulo: `github.com/BlasterM2A/shell-setup`. Un solo `go.mod`, sin `pkg/`; todo el código en `internal/`.
- Solo Debian/Ubuntu, linux amd64/arm64. `CGO_ENABLED=0`.
- Versiones fijadas en `mise.toml`: go `1.27.2`, task `3.54.0`, goreleaser `2.18.3`, golangci-lint `2.14.0`.
- Reglas de dependencia (verificadas con depguard en la Task 19):
  - `ui/**`, `iostreams` y `log` nunca importan `shellsetup` ni `cmd`.
  - `shellsetup`, `selfupdate` y `config` nunca importan `ui`, `iostreams`, `cmd` ni `charm.land/*`.
  - Solo `cmd` integra.
- `ui/styles` es el único paquete que define colores o iconos.
- Los textos que ve el usuario (mensajes, etiquetas) van en inglés, como en el `install.sh` actual. Identificadores y comentarios de código, también en inglés.
- Rutas en tiempo de ejecución:
  - binario: `~/.local/bin/shell-setup`
  - config: `~/.config/shell-setup/config.toml`
  - generados: `~/.config/shell-setup/zshrc`, `~/.config/shell-setup/zsh.d/NN-<id>.zsh`, `~/.config/shell-setup/plugins.txt`
  - state y logs: `~/.local/state/shell-setup/state.toml`, `shell-setup.log`, `lock` y `tmp/`
  - stub: `~/.zshrc`
  - del usuario (nunca se toca su contenido): `~/.config/zsh/{env,functions,aliases,custom}.d`
- **Nunca** ejecutes `shell-setup init` ni `shell-setup update` contra tu propio `$HOME` mientras desarrollas: instalan paquetes, descargan fuentes y hacen `chsh`. Verifica con `go test`. Para pruebas manuales, solo `--version` o `doctor`, y con `HOME=$(mktemp -d)`.
- Ni Docker ni shellcheck. La verificación se hace con `task test` y `task lint`.
- Las APIs de terceros se comprobaron el 2026-10-10 contra las versiones de arriba. Si algo no compila por una diferencia de API, consulta `go doc <paquete>.<símbolo>`, adapta lo mínimo manteniendo el comportamiento y anótalo en el mensaje del commit.

## Desviaciones respecto a la spec (decididas al planificar)

- **Preflight con sudo durante la TUI.**
  - La spec pedía hacerlo antes de mostrarla. En su lugar, el `Engine` corre dentro de la TUI y los comandos interactivos (sudo, chsh) la suspenden con `ReleaseTerminal`/`RestoreTerminal`.
  - El usuario obtiene lo mismo (un prompt limpio) y así `cmd` no tiene que conocer las fases del dominio.
- **`git` como `system_packages` de antidote.**
  - La spec decía que `git` dejaba de ser dependencia. Lo es para la herramienta, pero `antidote load` clona los plugins de zsh con git.
- **Shell de login leído con `getent passwd`** (con `$SHELL` como respaldo). `$SHELL` solo cambia tras un nuevo login, así que sin esto `init` volvería a pedir `chsh` en cada ejecución hasta reiniciar la sesión.
- **`--dry-run` no se expone.** `DryRunSystem` existe y tiene tests, tal como prevé la spec ("base de un futuro `--dry-run`").

## Review Focus

1. **Sin terminal:** `curl | bash` sin `/dev/tty`, CI o salida redirigida a un pipe. Debe usarse salida plana y nunca quedarse esperando a una TUI. Lo prueban la Task 17 (`TestRunPlainWhenNotTTY`) y la Task 18 (`main` cae a `init --plain`).
2. **Re-ejecutar `init` en una máquina ya configurada:** sin prompt de sudo, sin reinstalar y sin backups nuevos. Lo prueban la Task 14 (`TestInitIsIdempotent`) y la Task 13 (`TestApplyTwiceIsIdempotent`).
3. **`~/.zshrc` previo, no gestionado, en el primer `init`:** se respalda y nunca se pierde. Lo prueban la Task 10 (fila "first run") y la Task 13 (`TestApplyBacksUpUnmanagedZshrc`).
4. **Ejecución como root (contenedores, sin sudo):** los comandos privilegiados se ejecutan sin el prefijo `sudo`. Lo prueba la Task 14 (`TestAptPreflightWithoutSudoWhenRoot`).
5. **Dos ejecuciones simultáneas:** la segunda falla con un error claro (`ErrLocked`) sin modificar nada. Lo prueba la Task 14 (`TestInitFailsWhenLocked`).

## Mapa de archivos

```
main.go
mise.toml  Taskfile.yml  .goreleaser.yml  .golangci.yml  go.mod  go.sum
install.sh                                  # Task 18 (reescrito)
tests/test_install.sh                       # Task 18 (reescrito)
.github/workflows/ci.yml  release.yml       # Task 19
internal/
├── cmd/
│   ├── root.go        # Task 1, reescrito en Task 17
│   ├── factory.go  bindings.go  runner.go  apply.go
│   ├── init.go  update.go  doctor.go  selfupdate.go       # Task 17
│   └── testdata/scripts/*.txtar                           # Task 17
├── shellsetup/
│   ├── system.go  realsystem.go  dryrunsystem.go  paths.go   # Task 8
│   ├── tool.go  catalog.go                                   # Task 9
│   ├── event.go  report.go  state.go  managed.go             # Task 10
│   ├── fetch.go  backend.go  aptbackend.go  misebackend.go  scriptbackend.go   # Task 11
│   ├── archivebackend.go  fontbackend.go                     # Task 12
│   ├── shellrc.go                                            # Task 13
│   ├── shellsetup.go                                         # Task 14
│   ├── doctor.go                                             # Task 15
│   └── registry/  *.toml  files/{profile,starship,antidote}/ # Task 9
├── config/config.go            # Task 6
├── log/log.go                  # Task 7
├── selfupdate/selfupdate.go    # Task 16
├── iostreams/iostreams.go      # Task 5
└── ui/
    ├── styles/styles.go        # Task 2
    ├── common/common.go  notice/notice.go  statustable/statustable.go   # Task 3
    ├── steplist/steplist.go  model/progress.go                          # Task 4
```

---

### Task 1: Esqueleto del proyecto y comando raíz

**Files:**
- Create: `mise.toml`, `Taskfile.yml`, `go.mod`, `main.go`, `internal/cmd/root.go`, `internal/cmd/root_test.go`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `cmd.Execute() int`, `cmd.NewRootCmd() *cobra.Command` (en la Task 17 pasa a `NewRootCmd(f *Factory)`), `cmd.ExitError{Code int}`, variables `version`, `commit` y `repoSlug` (en `internal/cmd`, se inyectan por ldflags).

- [ ] **Step 1: Crear `mise.toml` e instalar la toolchain**

```toml
[tools]
go = "1.27.2"
task = "3.54.0"
goreleaser = "2.18.3"
golangci-lint = "2.14.0"
```

Run: `mise trust && mise install && mise exec -- go version`
Expected: `go version go1.27.2 linux/amd64` (o arm64)

A partir de aquí, todos los comandos se ejecutan con la toolchain de mise: anteponles `mise exec --` o activa mise en tu shell.

- [ ] **Step 2: Inicializar el módulo y las dependencias**

```bash
go mod init github.com/BlasterM2A/shell-setup
go get github.com/spf13/cobra@v1.10.2 github.com/stretchr/testify@v1.12.1
```

- [ ] **Step 3: Escribir el test que falla**

`internal/cmd/root_test.go`:

```go
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
```

- [ ] **Step 4: Ejecutarlo para verificar que falla**

Run: `go test ./internal/cmd/...`
Expected: FAIL, `undefined: NewRootCmd`

- [ ] **Step 5: Implementación mínima**

`internal/cmd/root.go`:

```go
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
```

`main.go`:

```go
package main

import (
	"os"

	"github.com/BlasterM2A/shell-setup/internal/cmd"
)

func main() {
	os.Exit(cmd.Execute())
}
```

- [ ] **Step 6: `Taskfile.yml` y `.gitignore`**

`Taskfile.yml`:

```yaml
version: "3"

tasks:
  build:
    desc: Build ./bin/shell-setup
    cmds:
      - go build -o bin/shell-setup .
  run:
    desc: "Run the CLI: task run -- doctor"
    cmds:
      - go run . {{.CLI_ARGS}}
  test:
    desc: Go tests + bootstrap script tests
    cmds:
      - go test ./...
      - bash tests/test_install.sh
  lint:
    cmds:
      - golangci-lint run
  fmt:
    cmds:
      - gofmt -w .
  tidy:
    cmds:
      - go mod tidy
  snapshot:
    desc: Local release build into ./dist (no publishing)
    cmds:
      - goreleaser release --snapshot --clean
```

Añade al final de `.gitignore`:

```gitignore

# Go build output
bin/
dist/
```

- [ ] **Step 7: Ejecutar los tests**

Run: `go test ./... && go run . --version`
Expected: PASS y `shell-setup dev (none)`

- [ ] **Step 8: Commit**

```bash
git add mise.toml Taskfile.yml go.mod go.sum main.go internal/cmd .gitignore
git commit -m "Scaffold Go module, toolchain and root command"
```

---

### Task 2: `ui/styles`, la única fuente de estilo

**Files:**
- Create: `internal/ui/styles/styles.go`, `internal/ui/styles/styles_test.go`

**Interfaces:**
- Produces:
  - `type Status int` con las constantes `StatusInfo, StatusOK, StatusWarn, StatusFail, StatusSkip, StatusRunning`.
  - `func Glyph(Status) string`.
  - `type Palette struct{ Text, Muted, Accent, Success, Warning, Error color.Color }`, `func DefaultPalette() Palette`.
  - `type Styles struct{ Title, Text, Muted lipgloss.Style }`, con los métodos `Status(Status) lipgloss.Style` e `Icon(Status) string`.
  - `func New(color bool) Styles`.

- [ ] **Step 1: Añadir la dependencia**

Run: `go get charm.land/lipgloss/v2@v2.0.6`

- [ ] **Step 2: Escribir el test que falla**

`internal/ui/styles/styles_test.go`:

```go
package styles_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

var all = []styles.Status{
	styles.StatusInfo, styles.StatusOK, styles.StatusWarn,
	styles.StatusFail, styles.StatusSkip, styles.StatusRunning,
}

func TestEveryStatusHasAGlyph(t *testing.T) {
	for _, st := range all {
		assert.NotEmpty(t, styles.Glyph(st), "status %d", st)
	}
}

func TestPlainStylesRenderNoEscapes(t *testing.T) {
	s := styles.New(false)
	for _, st := range all {
		assert.Equal(t, styles.Glyph(st), s.Icon(st))
	}
	assert.Equal(t, "title", s.Title.Render("title"))
	assert.Equal(t, "muted", s.Muted.Render("muted"))
}

func TestColorStylesEmitANSI(t *testing.T) {
	got := styles.New(true).Icon(styles.StatusOK)
	assert.Contains(t, got, "✓")
	assert.Contains(t, got, "\x1b[")
}
```

- [ ] **Step 3: Ejecutarlo para verificar que falla**

Run: `go test ./internal/ui/styles/...`
Expected: FAIL, `undefined: styles.New` (o el paquete no existe)

- [ ] **Step 4: Implementación**

`internal/ui/styles/styles.go`:

```go
// Package styles is the single source of truth for colors, icons and text
// styles. TUI components, plain output and console logs all render with it;
// no other package defines colors.
package styles

import (
	"image/color"

	"charm.land/lipgloss/v2"
)

// Status is the semantic state shared by every component and log line.
type Status int

const (
	StatusInfo Status = iota
	StatusOK
	StatusWarn
	StatusFail
	StatusSkip
	StatusRunning
)

var glyphs = map[Status]string{
	StatusInfo:    "•",
	StatusOK:      "✓",
	StatusWarn:    "!",
	StatusFail:    "✗",
	StatusSkip:    "-",
	StatusRunning: "…",
}

// Glyph returns the unstyled icon for a status.
func Glyph(s Status) string { return glyphs[s] }

// Palette holds the semantic colors of the theme.
type Palette struct {
	Text, Muted, Accent, Success, Warning, Error color.Color
}

// DefaultPalette is the shell-setup theme.
func DefaultPalette() Palette {
	return Palette{
		Text:    lipgloss.Color("#C0CAF5"),
		Muted:   lipgloss.Color("#737AA2"),
		Accent:  lipgloss.Color("#7AA2F7"),
		Success: lipgloss.Color("#9ECE6A"),
		Warning: lipgloss.Color("#E0AF68"),
		Error:   lipgloss.Color("#F7768E"),
	}
}

// Styles are the lipgloss styles every component renders with.
type Styles struct {
	Title  lipgloss.Style
	Text   lipgloss.Style
	Muted  lipgloss.Style
	status map[Status]lipgloss.Style
}

// New builds the styles. With color=false every style renders plain text,
// which is what non-terminal output and NO_COLOR use.
func New(color bool) Styles {
	s := Styles{
		Title:  lipgloss.NewStyle(),
		Text:   lipgloss.NewStyle(),
		Muted:  lipgloss.NewStyle(),
		status: make(map[Status]lipgloss.Style, len(glyphs)),
	}
	for st := range glyphs {
		s.status[st] = lipgloss.NewStyle()
	}
	if !color {
		return s
	}
	p := DefaultPalette()
	s.Title = s.Title.Bold(true).Foreground(p.Accent)
	s.Text = s.Text.Foreground(p.Text)
	s.Muted = s.Muted.Foreground(p.Muted)
	s.status[StatusInfo] = s.status[StatusInfo].Foreground(p.Accent)
	s.status[StatusOK] = s.status[StatusOK].Foreground(p.Success)
	s.status[StatusWarn] = s.status[StatusWarn].Foreground(p.Warning)
	s.status[StatusFail] = s.status[StatusFail].Foreground(p.Error)
	s.status[StatusSkip] = s.status[StatusSkip].Foreground(p.Muted)
	s.status[StatusRunning] = s.status[StatusRunning].Foreground(p.Accent)
	return s
}

// Status returns the style for a status.
func (s Styles) Status(st Status) lipgloss.Style { return s.status[st] }

// Icon renders the status glyph with its style.
func (s Styles) Icon(st Status) string { return s.status[st].Render(Glyph(st)) }
```

- [ ] **Step 5: Ejecutar los tests**

Run: `go test ./internal/ui/styles/...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum internal/ui/styles
git commit -m "Add ui/styles: single source of colors, icons and styles"
```

---

### Task 3: Componentes sin estado: `common`, `notice` y `statustable`

**Files:**
- Create: `internal/ui/common/common.go`, `internal/ui/notice/notice.go`, `internal/ui/notice/notice_test.go`, `internal/ui/statustable/statustable.go`, `internal/ui/statustable/statustable_test.go`, `internal/ui/statustable/testdata/TestRenderColor.golden` (generado)

**Interfaces:**
- Consumes: `styles.Styles`, `styles.Status` (Task 2).
- Produces:
  - `common.Common{Styles styles.Styles}`, `common.New(styles.Styles) Common`.
  - `notice.Props{Status styles.Status; Text string}`, `notice.Render(common.Common, Props) string`. Devuelve una línea, sin `\n` final.
  - `statustable.Row{Status styles.Status; Name, Detail string}`, `statustable.Props{Title string; Rows []Row}`, `statustable.Render(common.Common, Props) string`. Cada fila termina en `\n`.

- [ ] **Step 1: Añadir la dependencia de golden**

Run: `go get github.com/charmbracelet/x/exp/golden@latest`

- [ ] **Step 2: Escribir los tests que fallan**

`internal/ui/notice/notice_test.go`:

```go
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
```

`internal/ui/statustable/statustable_test.go`:

```go
package statustable_test

import (
	"testing"

	"github.com/charmbracelet/x/exp/golden"
	"github.com/stretchr/testify/assert"

	"github.com/BlasterM2A/shell-setup/internal/ui/common"
	"github.com/BlasterM2A/shell-setup/internal/ui/statustable"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

var props = statustable.Props{
	Title: "Doctor",
	Rows: []statustable.Row{
		{Status: styles.StatusOK, Name: "starship", Detail: "1.20.0"},
		{Status: styles.StatusFail, Name: "zoxide", Detail: "not installed"},
		{Status: styles.StatusSkip, Name: "claude"},
	},
}

func TestRenderPlain(t *testing.T) {
	got := statustable.Render(common.New(styles.New(false)), props)
	want := "Doctor\n" +
		"  ✓ starship  1.20.0\n" +
		"  ✗ zoxide    not installed\n" +
		"  - claude\n"
	assert.Equal(t, want, got)
}

func TestRenderWithoutTitle(t *testing.T) {
	got := statustable.Render(common.New(styles.New(false)), statustable.Props{
		Rows: []statustable.Row{{Status: styles.StatusOK, Name: "mise", Detail: "2026.10.6"}},
	})
	assert.Equal(t, "  ✓ mise  2026.10.6\n", got)
}

func TestRenderColor(t *testing.T) {
	golden.RequireEqual(t, []byte(statustable.Render(common.New(styles.New(true)), props)))
}
```

- [ ] **Step 3: Ejecutarlos para verificar que fallan**

Run: `go test ./internal/ui/...`
Expected: FAIL, los paquetes `common`, `notice` y `statustable` no existen

- [ ] **Step 4: Implementación**

`internal/ui/common/common.go`:

```go
// Package common carries what every UI component receives.
package common

import "github.com/BlasterM2A/shell-setup/internal/ui/styles"

// Common is passed to every component.
type Common struct {
	Styles styles.Styles
}

// New returns the Common for a set of styles.
func New(s styles.Styles) Common { return Common{Styles: s} }
```

`internal/ui/notice/notice.go`:

```go
// Package notice renders a single status message line.
package notice

import (
	"github.com/BlasterM2A/shell-setup/internal/ui/common"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

// Props are the inputs of a notice.
type Props struct {
	Status styles.Status
	Text   string
}

// Render returns the notice as one line, without a trailing newline.
func Render(c common.Common, p Props) string {
	return c.Styles.Icon(p.Status) + " " + c.Styles.Status(p.Status).Render(p.Text)
}
```

`internal/ui/statustable/statustable.go`:

```go
// Package statustable renders rows of "icon name detail" with aligned names.
package statustable

import (
	"strings"

	"charm.land/lipgloss/v2"

	"github.com/BlasterM2A/shell-setup/internal/ui/common"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

// Row is one line of the table.
type Row struct {
	Status styles.Status
	Name   string
	Detail string
}

// Props are the inputs of the table.
type Props struct {
	Title string
	Rows  []Row
}

// Render returns the table; every row ends with a newline.
func Render(c common.Common, p Props) string {
	var b strings.Builder
	if p.Title != "" {
		b.WriteString(c.Styles.Title.Render(p.Title))
		b.WriteByte('\n')
	}
	width := 0
	for _, r := range p.Rows {
		width = max(width, lipgloss.Width(r.Name))
	}
	for _, r := range p.Rows {
		b.WriteString("  ")
		b.WriteString(c.Styles.Icon(r.Status))
		b.WriteByte(' ')
		b.WriteString(c.Styles.Text.Render(r.Name))
		if r.Detail != "" {
			b.WriteString(strings.Repeat(" ", width-lipgloss.Width(r.Name)+2))
			b.WriteString(c.Styles.Muted.Render(r.Detail))
		}
		b.WriteByte('\n')
	}
	return b.String()
}
```

- [ ] **Step 5: Generar el golden y ejecutar los tests**

Run: `go test ./internal/ui/statustable/ -run TestRenderColor -update && go test ./internal/ui/...`
Expected: PASS. Revisa `internal/ui/statustable/testdata/TestRenderColor.golden`: debe contener las mismas tres filas con secuencias ANSI (`\x1b[`).

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum internal/ui
git commit -m "Add ui common, notice and statustable components"
```

---

### Task 4: Componentes con estado: `steplist` y `model.Progress`

**Files:**
- Create: `internal/ui/steplist/steplist.go`, `internal/ui/steplist/steplist_test.go`, `internal/ui/model/progress.go`, `internal/ui/model/progress_test.go`

**Interfaces:**
- Consumes: `common.Common`, `statustable.Render` y `notice.Render` (Task 3).
- Produces:
  - `steplist.StepStarted{ID, Label string}`.
  - `steplist.StepFinished{ID, Label string; Status styles.Status; Detail string}`.
  - `steplist.Props{Title string}`, `steplist.New(common.Common, Props) Model`.
  - Métodos de `Model`: `Update(msg any) Model` y `View() string`.
  - `model.Done{Summary string}`, `model.NewProgress(c common.Common, title string, onInterrupt func()) Progress`.
  - `Progress` implementa `tea.Model` y tiene `Render() string`.

- [ ] **Step 1: Añadir bubbletea**

Run: `go get charm.land/bubbletea/v2@v2.1.0`

- [ ] **Step 2: Escribir los tests que fallan**

`internal/ui/steplist/steplist_test.go`:

```go
package steplist_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/BlasterM2A/shell-setup/internal/ui/common"
	"github.com/BlasterM2A/shell-setup/internal/ui/steplist"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

func TestStepsKeepOrderAndUpdateInPlace(t *testing.T) {
	m := steplist.New(common.New(styles.New(false)), steplist.Props{Title: "Updating"})
	m = m.Update(steplist.StepStarted{ID: "mise", Label: "mise"})
	m = m.Update(steplist.StepStarted{ID: "starship", Label: "starship"})
	m = m.Update(steplist.StepFinished{ID: "mise", Status: styles.StatusOK, Detail: "2026.10.6"})

	want := "Updating\n" +
		"  ✓ mise      2026.10.6\n" +
		"  … starship\n"
	assert.Equal(t, want, m.View())
}

func TestFinishedWithoutStartIsAppended(t *testing.T) {
	m := steplist.New(common.New(styles.New(false)), steplist.Props{})
	m = m.Update(steplist.StepFinished{ID: "f1", Label: "~/.zshrc", Status: styles.StatusWarn, Detail: "modified"})
	assert.Equal(t, "  ! ~/.zshrc  modified\n", m.View())
}

func TestUnknownMessagesAreIgnored(t *testing.T) {
	m := steplist.New(common.New(styles.New(false)), steplist.Props{})
	m = m.Update("noise")
	assert.Equal(t, "", m.View())
}
```

`internal/ui/model/progress_test.go`:

```go
package model_test

import (
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/BlasterM2A/shell-setup/internal/ui/common"
	"github.com/BlasterM2A/shell-setup/internal/ui/model"
	"github.com/BlasterM2A/shell-setup/internal/ui/steplist"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

func newProgress(onInterrupt func()) model.Progress {
	return model.NewProgress(common.New(styles.New(false)), "Setting up", onInterrupt)
}

func TestProgressForwardsStepMessages(t *testing.T) {
	var m tea.Model = newProgress(nil)
	m, _ = m.Update(steplist.StepFinished{ID: "mise", Label: "mise", Status: styles.StatusOK})
	assert.Equal(t, "Setting up\n  ✓ mise\n", m.(model.Progress).Render())
}

func TestDoneShowsSummaryAndQuits(t *testing.T) {
	var m tea.Model = newProgress(nil)
	m, cmd := m.Update(model.Done{Summary: "all good\n"})
	require.NotNil(t, cmd)
	assert.IsType(t, tea.QuitMsg{}, cmd())
	assert.Equal(t, "Setting up\n\nall good\n", m.(model.Progress).Render())
}

func TestCtrlCInterruptsOnce(t *testing.T) {
	calls := 0
	var m tea.Model = newProgress(func() { calls++ })
	key := tea.KeyPressMsg{Code: 'c', Mod: tea.ModCtrl}
	m, _ = m.Update(key)
	m, _ = m.Update(key)
	assert.Equal(t, 1, calls)
	assert.Contains(t, m.(model.Progress).Render(), "Interrupted")
}
```

- [ ] **Step 3: Ejecutarlos para verificar que fallan**

Run: `go test ./internal/ui/...`
Expected: FAIL, los paquetes `steplist` y `model` no existen

- [ ] **Step 4: Implementación**

`internal/ui/steplist/steplist.go`:

```go
// Package steplist renders the live progress of a sequence of steps.
package steplist

import (
	"github.com/BlasterM2A/shell-setup/internal/ui/common"
	"github.com/BlasterM2A/shell-setup/internal/ui/statustable"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

// StepStarted marks a step as running, adding it if new.
type StepStarted struct {
	ID    string
	Label string
}

// StepFinished sets a step's final status, adding it if new.
type StepFinished struct {
	ID     string
	Label  string
	Status styles.Status
	Detail string
}

// Props are the inputs of the list.
type Props struct {
	Title string
}

type step struct {
	label  string
	detail string
	status styles.Status
}

// Model is the step list. It has a single owner: copies share state.
type Model struct {
	c     common.Common
	props Props
	order []string
	steps map[string]step
}

// New returns an empty list.
func New(c common.Common, p Props) Model {
	return Model{c: c, props: p, steps: map[string]step{}}
}

// Update applies StepStarted/StepFinished; other messages are ignored.
func (m Model) Update(msg any) Model {
	switch msg := msg.(type) {
	case StepStarted:
		m.upsert(msg.ID, msg.Label, func(s *step) { s.status = styles.StatusRunning })
	case StepFinished:
		m.upsert(msg.ID, msg.Label, func(s *step) {
			s.status = msg.Status
			s.detail = msg.Detail
		})
	}
	return m
}

func (m *Model) upsert(id, label string, apply func(*step)) {
	s, ok := m.steps[id]
	if !ok {
		m.order = append(m.order, id)
		s.label = id
	}
	if label != "" {
		s.label = label
	}
	apply(&s)
	m.steps[id] = s
}

// View renders the steps in the order they first appeared.
func (m Model) View() string {
	rows := make([]statustable.Row, 0, len(m.order))
	for _, id := range m.order {
		s := m.steps[id]
		rows = append(rows, statustable.Row{Status: s.status, Name: s.label, Detail: s.detail})
	}
	if len(rows) == 0 && m.props.Title == "" {
		return ""
	}
	return statustable.Render(m.c, statustable.Props{Title: m.props.Title, Rows: rows})
}
```

`internal/ui/model/progress.go`:

```go
// Package model holds the top-level bubbletea models run by commands.
package model

import (
	tea "charm.land/bubbletea/v2"

	"github.com/BlasterM2A/shell-setup/internal/ui/common"
	"github.com/BlasterM2A/shell-setup/internal/ui/notice"
	"github.com/BlasterM2A/shell-setup/internal/ui/steplist"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

// Done ends the progress view; Summary is shown below the steps.
type Done struct {
	Summary string
}

// Progress shows a step list while an operation runs, then its summary.
type Progress struct {
	c           common.Common
	steps       steplist.Model
	summary     string
	interrupted bool
	onInterrupt func()
}

// NewProgress returns the view. onInterrupt is called once on ctrl+c; the
// view keeps running until Done arrives so the last step can finish.
func NewProgress(c common.Common, title string, onInterrupt func()) Progress {
	return Progress{
		c:           c,
		steps:       steplist.New(c, steplist.Props{Title: title}),
		onInterrupt: onInterrupt,
	}
}

func (m Progress) Init() tea.Cmd { return nil }

func (m Progress) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case Done:
		m.summary = msg.Summary
		return m, tea.Quit
	case tea.KeyPressMsg:
		if msg.String() == "ctrl+c" && !m.interrupted {
			m.interrupted = true
			if m.onInterrupt != nil {
				m.onInterrupt()
			}
		}
		return m, nil
	}
	m.steps = m.steps.Update(msg)
	return m, nil
}

// Render returns the view's text (View wraps it for bubbletea).
func (m Progress) Render() string {
	s := m.steps.View()
	if m.interrupted && m.summary == "" {
		s += "\n" + notice.Render(m.c, notice.Props{
			Status: styles.StatusWarn,
			Text:   "Interrupted, finishing the current step…",
		}) + "\n"
	}
	if m.summary != "" {
		s += "\n" + m.summary
	}
	return s
}

func (m Progress) View() tea.View { return tea.NewView(m.Render()) }
```

- [ ] **Step 5: Ejecutar los tests**

Run: `go test ./internal/ui/...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum internal/ui
git commit -m "Add steplist component and Progress model"
```

---

### Task 5: `iostreams`: salida, TTY y color

**Files:**
- Create: `internal/iostreams/iostreams.go`, `internal/iostreams/iostreams_test.go`

**Interfaces:**
- Consumes: `styles.New` (Task 2).
- Produces:
  - `type IOStreams struct{ In io.Reader; Out, ErrOut io.Writer }`.
  - `System() *IOStreams` y `Test() (*IOStreams, *bytes.Buffer, *bytes.Buffer)`.
  - Métodos: `IsTTY() bool`, `ColorEnabled() bool`, `Styles() styles.Styles`.

- [ ] **Step 1: Añadir la dependencia**

Run: `go get golang.org/x/term@latest`

- [ ] **Step 2: Escribir el test que falla**

`internal/iostreams/iostreams_test.go`:

```go
package iostreams

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

func env(vars map[string]string) func(string) (string, bool) {
	return func(k string) (string, bool) { v, ok := vars[k]; return v, ok }
}

func TestColorRequiresTTY(t *testing.T) {
	assert.False(t, colorEnabled(false, env(nil)))
	assert.True(t, colorEnabled(true, env(map[string]string{"TERM": "xterm-256color"})))
}

func TestNoColorAndDumbTermDisableColor(t *testing.T) {
	assert.False(t, colorEnabled(true, env(map[string]string{"NO_COLOR": ""})))
	assert.False(t, colorEnabled(true, env(map[string]string{"TERM": "dumb"})))
}

func TestTestStreamsArePlain(t *testing.T) {
	ios, out, _ := Test()
	assert.False(t, ios.IsTTY())
	assert.Equal(t, styles.Glyph(styles.StatusOK), ios.Styles().Icon(styles.StatusOK))
	_, _ = ios.Out.Write([]byte("hi"))
	assert.Equal(t, "hi", out.String())
}
```

- [ ] **Step 3: Ejecutarlo para verificar que falla**

Run: `go test ./internal/iostreams/...`
Expected: FAIL, `undefined: colorEnabled`

- [ ] **Step 4: Implementación**

`internal/iostreams/iostreams.go`:

```go
// Package iostreams wraps stdin/stdout/stderr with TTY and color detection.
// Output written outside the TUI uses Styles() so it matches the TUI.
package iostreams

import (
	"bytes"
	"io"
	"os"

	"golang.org/x/term"

	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

// IOStreams are the process streams.
type IOStreams struct {
	In     io.Reader
	Out    io.Writer
	ErrOut io.Writer

	tty   bool
	color bool
}

// System returns the real process streams.
func System() *IOStreams {
	tty := term.IsTerminal(int(os.Stdin.Fd())) && term.IsTerminal(int(os.Stdout.Fd()))
	return &IOStreams{
		In:     os.Stdin,
		Out:    os.Stdout,
		ErrOut: os.Stderr,
		tty:    tty,
		color:  colorEnabled(tty, os.LookupEnv),
	}
}

// Test returns non-TTY streams backed by buffers.
func Test() (*IOStreams, *bytes.Buffer, *bytes.Buffer) {
	out, errOut := &bytes.Buffer{}, &bytes.Buffer{}
	return &IOStreams{In: &bytes.Buffer{}, Out: out, ErrOut: errOut}, out, errOut
}

func colorEnabled(tty bool, lookup func(string) (string, bool)) bool {
	if !tty {
		return false
	}
	if _, ok := lookup("NO_COLOR"); ok {
		return false
	}
	term, _ := lookup("TERM")
	return term != "dumb"
}

// IsTTY reports whether both stdin and stdout are terminals.
func (s *IOStreams) IsTTY() bool { return s.tty }

// ColorEnabled reports whether output may use colors.
func (s *IOStreams) ColorEnabled() bool { return s.color }

// Styles returns the shared styles, plain when color is disabled.
func (s *IOStreams) Styles() styles.Styles { return styles.New(s.color) }
```

- [ ] **Step 5: Ejecutar los tests**

Run: `go test ./internal/iostreams/...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum internal/iostreams
git commit -m "Add iostreams with TTY and NO_COLOR detection"
```

---

### Task 6: `config` con koanf

**Files:**
- Create: `internal/config/config.go`, `internal/config/config_test.go`

**Interfaces:**
- Produces:
  - `type Config struct{ LogLevel string }`, con clave koanf `log_level`. Valores: `debug|info|warn|error`; por defecto `info`.
  - `Load(path string, overrides map[string]any) (Config, error)`.
  - `DefaultPath(home string) string`, que devuelve `~/.config/shell-setup/config.toml`.
  - Precedencia: valores por defecto → archivo → variables `SHELL_SETUP_*` → `overrides`.

- [ ] **Step 1: Añadir las dependencias**

```bash
go get github.com/knadh/koanf/v2@v2.3.8 github.com/knadh/koanf/providers/file@latest \
  github.com/knadh/koanf/providers/env/v2@latest github.com/knadh/koanf/providers/confmap@latest \
  github.com/knadh/koanf/parsers/toml/v2@latest
```

- [ ] **Step 2: Escribir el test que falla**

`internal/config/config_test.go`:

```go
package config_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/BlasterM2A/shell-setup/internal/config"
)

func writeConfig(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "config.toml")
	require.NoError(t, os.WriteFile(path, []byte(body), 0o644))
	return path
}

func TestDefaultsWhenFileIsMissing(t *testing.T) {
	cfg, err := config.Load(filepath.Join(t.TempDir(), "missing.toml"), nil)
	require.NoError(t, err)
	assert.Equal(t, "info", cfg.LogLevel)
}

func TestPrecedence(t *testing.T) {
	path := writeConfig(t, `log_level = "warn"`)

	cfg, err := config.Load(path, nil)
	require.NoError(t, err)
	assert.Equal(t, "warn", cfg.LogLevel, "file overrides default")

	t.Setenv("SHELL_SETUP_LOG_LEVEL", "error")
	cfg, err = config.Load(path, nil)
	require.NoError(t, err)
	assert.Equal(t, "error", cfg.LogLevel, "env overrides file")

	cfg, err = config.Load(path, map[string]any{"log_level": "debug"})
	require.NoError(t, err)
	assert.Equal(t, "debug", cfg.LogLevel, "overrides win")
}

func TestInvalidLevel(t *testing.T) {
	_, err := config.Load(writeConfig(t, `log_level = "loud"`), nil)
	assert.ErrorContains(t, err, `invalid log_level "loud"`)
}

func TestDefaultPath(t *testing.T) {
	assert.Equal(t, "/h/.config/shell-setup/config.toml", config.DefaultPath("/h"))
}
```

- [ ] **Step 3: Ejecutarlo para verificar que falla**

Run: `go test ./internal/config/...`
Expected: FAIL, el paquete no existe

- [ ] **Step 4: Implementación**

`internal/config/config.go`:

```go
// Package config loads what the user wants (intent). Facts the tool writes
// about the machine live in shellsetup's state, not here.
package config

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/knadh/koanf/parsers/toml/v2"
	"github.com/knadh/koanf/providers/confmap"
	"github.com/knadh/koanf/providers/env/v2"
	"github.com/knadh/koanf/providers/file"
	"github.com/knadh/koanf/v2"
)

const envPrefix = "SHELL_SETUP_"

var levels = []string{"debug", "info", "warn", "error"}

// Config is the user's configuration.
type Config struct {
	LogLevel string `koanf:"log_level"`
}

// DefaultPath is where the config file lives.
func DefaultPath(home string) string {
	return filepath.Join(home, ".config", "shell-setup", "config.toml")
}

// Load merges defaults, the file at path (optional), SHELL_SETUP_* env vars
// and overrides, in that order.
func Load(path string, overrides map[string]any) (Config, error) {
	k := koanf.New(".")
	if err := k.Load(confmap.Provider(map[string]any{"log_level": "info"}, "."), nil); err != nil {
		return Config{}, err
	}
	if _, err := os.Stat(path); err == nil {
		if err := k.Load(file.Provider(path), toml.Parser()); err != nil {
			return Config{}, fmt.Errorf("reading %s: %w", path, err)
		}
	} else if !errors.Is(err, fs.ErrNotExist) {
		return Config{}, err
	}
	err := k.Load(env.Provider(".", env.Opt{
		Prefix: envPrefix,
		TransformFunc: func(key, value string) (string, any) {
			return strings.ToLower(strings.TrimPrefix(key, envPrefix)), value
		},
	}), nil)
	if err != nil {
		return Config{}, err
	}
	if len(overrides) > 0 {
		if err := k.Load(confmap.Provider(overrides, "."), nil); err != nil {
			return Config{}, err
		}
	}
	var cfg Config
	if err := k.Unmarshal("", &cfg); err != nil {
		return Config{}, err
	}
	if !slices.Contains(levels, cfg.LogLevel) {
		return Config{}, fmt.Errorf("invalid log_level %q (want one of %s)", cfg.LogLevel, strings.Join(levels, ", "))
	}
	return cfg, nil
}
```

- [ ] **Step 5: Ejecutar los tests**

Run: `go test ./internal/config/...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum internal/config
git commit -m "Add config package (koanf: defaults, file, env, overrides)"
```

---

### Task 7: `log`: slog con archivo y consola estilada

**Files:**
- Create: `internal/log/log.go`, `internal/log/log_test.go`

**Interfaces:**
- Consumes: `styles.Styles`, `styles.Glyph` y `styles.Status*` (Task 2).
- Produces:
  - `type Options struct{ File string; Level slog.Level; Console io.Writer; Styles styles.Styles }`.
  - `New(Options) (*slog.Logger, func() error, error)`.
  - Comportamiento: el archivo siempre recibe nivel debug, en texto plano. La consola es opcional y respeta `Level`, con iconos de `styles`.

- [ ] **Step 1: Añadir la dependencia**

Run: `go get charm.land/log/v2@v2.0.1`

- [ ] **Step 2: Escribir el test que falla**

`internal/log/log_test.go`:

```go
package log_test

import (
	"bytes"
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/BlasterM2A/shell-setup/internal/log"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

func TestFileGetsEverythingConsoleRespectsLevel(t *testing.T) {
	file := filepath.Join(t.TempDir(), "state", "shell-setup.log")
	var console bytes.Buffer
	logger, closeFn, err := log.New(log.Options{
		File: file, Level: slog.LevelInfo, Console: &console, Styles: styles.New(false),
	})
	require.NoError(t, err)

	logger.Debug("debug detail", "cmd", "mise --version")
	logger.Warn("careful")
	require.NoError(t, closeFn())

	data, err := os.ReadFile(file)
	require.NoError(t, err)
	assert.Contains(t, string(data), "debug detail")
	assert.Contains(t, string(data), "careful")

	assert.NotContains(t, console.String(), "debug detail")
	assert.Contains(t, console.String(), styles.Glyph(styles.StatusWarn)+" careful")
}

func TestWithoutConsoleOrFile(t *testing.T) {
	logger, closeFn, err := log.New(log.Options{Level: slog.LevelInfo, Styles: styles.New(false)})
	require.NoError(t, err)
	logger.Info("nowhere")
	require.NoError(t, closeFn())
}
```

- [ ] **Step 3: Ejecutarlo para verificar que falla**

Run: `go test ./internal/log/...`
Expected: FAIL, el paquete no existe

- [ ] **Step 4: Implementación**

`internal/log/log.go`:

```go
// Package log builds the slog logger: a plain-text debug log file plus an
// optional console handler styled with ui/styles, so console log lines look
// like the rest of the output.
package log

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"

	charmlog "charm.land/log/v2"

	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

// Options configure New.
type Options struct {
	// File receives every record (debug and up). Empty disables it.
	File string
	// Level filters the console.
	Level slog.Level
	// Console receives styled records at Level and up. Nil disables it.
	Console io.Writer
	Styles  styles.Styles
}

// New returns the logger and a function that closes the log file.
func New(o Options) (*slog.Logger, func() error, error) {
	var handlers []slog.Handler
	closeFn := func() error { return nil }
	if o.File != "" {
		if err := os.MkdirAll(filepath.Dir(o.File), 0o755); err != nil {
			return nil, nil, err
		}
		f, err := os.OpenFile(o.File, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
		if err != nil {
			return nil, nil, err
		}
		handlers = append(handlers, slog.NewTextHandler(f, &slog.HandlerOptions{Level: slog.LevelDebug}))
		closeFn = f.Close
	}
	if o.Console != nil {
		console := charmlog.NewWithOptions(o.Console, charmlog.Options{Level: charmlog.Level(o.Level)})
		console.SetStyles(consoleStyles(o.Styles))
		handlers = append(handlers, console)
	}
	return slog.New(slog.NewMultiHandler(handlers...)), closeFn, nil
}

// consoleStyles maps log levels to the shared status icons and colors.
func consoleStyles(s styles.Styles) *charmlog.Styles {
	cs := charmlog.DefaultStyles()
	cs.Levels[charmlog.DebugLevel] = s.Muted.SetString(styles.Glyph(styles.StatusInfo))
	cs.Levels[charmlog.InfoLevel] = s.Status(styles.StatusInfo).SetString(styles.Glyph(styles.StatusInfo))
	cs.Levels[charmlog.WarnLevel] = s.Status(styles.StatusWarn).SetString(styles.Glyph(styles.StatusWarn))
	cs.Levels[charmlog.ErrorLevel] = s.Status(styles.StatusFail).SetString(styles.Glyph(styles.StatusFail))
	cs.Levels[charmlog.FatalLevel] = s.Status(styles.StatusFail).SetString(styles.Glyph(styles.StatusFail))
	return cs
}
```

- [ ] **Step 5: Ejecutar los tests**

Run: `go test ./internal/log/...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum internal/log
git commit -m "Add log package: debug log file + styled console handler"
```

---

### Task 8: `shellsetup`: `System`, `RealSystem`, `DryRunSystem` y `Paths`

**Files:**
- Create:
  - `internal/shellsetup/system.go`
  - `internal/shellsetup/realsystem.go`
  - `internal/shellsetup/dryrunsystem.go`
  - `internal/shellsetup/paths.go`
  - `internal/shellsetup/system_test.go`
  - `internal/shellsetup/helpers_test.go`

**Interfaces:**
- Produces:
  - `type Cmd struct{ Name string; Args []string; Interactive bool }` con `String()`.
  - `var ErrLocked`.
  - `type System interface` con: `HomeDir`, `Getenv`, `ReadFile`, `WriteFile`, `Rename`, `Remove`, `RemoveAll`, `MkdirAll`, `Stat`, `Glob`, `LookPath`, `Run` y `Lock`. Las firmas exactas están más abajo.
  - `NewRealSystem(home string, logger *slog.Logger) *RealSystem` y `(*RealSystem).SetTerminalHandoff(TerminalHandoff)`.
  - `type TerminalHandoff func(fn func() error) error`.
  - `type DryRunSystem struct{ Base System; Ops []string }`.
  - `type Paths struct{...}`, `NewPaths(home string) Paths`, `(Paths).Expand(string) string`.
  - Helpers de test (en `helpers_test.go`, los usan las Tasks 9–15):
    - `newTestSystem(t) (*RealSystem, *recorder)`.
    - Métodos de `recorder`: `out map[string]string`, `setFail(cmd string, err error)`, `commands() []string`.
    - `errExit`.
    - `writeExecutable(t, path)`.

- [ ] **Step 1: Escribir los helpers de test y los tests que fallan**

`internal/shellsetup/helpers_test.go`:

```go
package shellsetup

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"sync"
	"testing"

	"github.com/stretchr/testify/require"
)

var errExit = errors.New("exit status 1")

// recorder replaces command execution: it records every command and
// answers from out/fail, keyed by Cmd.String().
type recorder struct {
	mu   sync.Mutex
	cmds []string
	out  map[string]string
	fail map[string]error
}

func newRecorder() *recorder {
	return &recorder{out: map[string]string{}, fail: map[string]error{}}
}

func (r *recorder) exec(_ context.Context, c Cmd) ([]byte, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	s := c.String()
	r.cmds = append(r.cmds, s)
	return []byte(r.out[s]), r.fail[s]
}

// setFail makes cmd fail with err; a nil err makes it succeed again.
func (r *recorder) setFail(cmd string, err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if err == nil {
		delete(r.fail, cmd)
		return
	}
	r.fail[cmd] = err
}

func (r *recorder) commands() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.cmds)
}

// newTestSystem is a RealSystem on a temporary HOME whose commands are
// recorded instead of executed.
func newTestSystem(t *testing.T) (*RealSystem, *recorder) {
	t.Helper()
	sys := NewRealSystem(t.TempDir(), slog.New(slog.DiscardHandler))
	rec := newRecorder()
	sys.execFn = rec.exec
	return sys, rec
}

func writeExecutable(t *testing.T, path string, body ...string) {
	t.Helper()
	require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o755))
	content := "#!/bin/sh\n"
	for _, line := range body {
		content += line + "\n"
	}
	require.NoError(t, os.WriteFile(path, []byte(content), 0o755))
}
```

`internal/shellsetup/system_test.go`:

```go
package shellsetup

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func realSystem(t *testing.T) *RealSystem {
	return NewRealSystem(t.TempDir(), slog.New(slog.DiscardHandler))
}

func TestWriteFileIsAtomicAndCreatesDirs(t *testing.T) {
	sys := realSystem(t)
	path := filepath.Join(sys.HomeDir(), "a", "b", "file.txt")

	require.NoError(t, sys.WriteFile(path, []byte("hello"), 0o600))

	data, err := os.ReadFile(path)
	require.NoError(t, err)
	assert.Equal(t, "hello", string(data))
	info, err := os.Stat(path)
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0o600), info.Mode().Perm())
	leftovers, err := filepath.Glob(filepath.Join(filepath.Dir(path), ".*.tmp-*"))
	require.NoError(t, err)
	assert.Empty(t, leftovers)
}

func TestRunPrefersUserBin(t *testing.T) {
	sys := realSystem(t)
	writeExecutable(t, filepath.Join(sys.HomeDir(), ".local", "bin", "hello"), "echo from-home")

	out, err := sys.Run(context.Background(), Cmd{Name: "hello"})
	require.NoError(t, err)
	assert.Equal(t, "from-home\n", string(out))
}

func TestRunErrorIncludesOutputTail(t *testing.T) {
	sys := realSystem(t)
	writeExecutable(t, filepath.Join(sys.HomeDir(), ".local", "bin", "boom"), "echo exploded", "exit 3")

	_, err := sys.Run(context.Background(), Cmd{Name: "boom"})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "exploded")
}

func TestRunMissingCommand(t *testing.T) {
	_, err := realSystem(t).Run(context.Background(), Cmd{Name: "definitely-not-a-command-xyz"})
	assert.Error(t, err)
}

func TestInteractiveRunGoesThroughHandoff(t *testing.T) {
	sys := realSystem(t)
	writeExecutable(t, filepath.Join(sys.HomeDir(), ".local", "bin", "ok"), "exit 0")
	called := false
	sys.SetTerminalHandoff(func(fn func() error) error { called = true; return fn() })

	_, err := sys.Run(context.Background(), Cmd{Name: "ok", Interactive: true})
	require.NoError(t, err)
	assert.True(t, called)
}

func TestLockIsExclusive(t *testing.T) {
	sys := realSystem(t)
	path := filepath.Join(sys.HomeDir(), "state", "lock")

	unlock, err := sys.Lock(path)
	require.NoError(t, err)
	_, err = sys.Lock(path)
	assert.ErrorIs(t, err, ErrLocked)

	unlock()
	unlock2, err := sys.Lock(path)
	require.NoError(t, err)
	unlock2()
}

func TestDryRunRecordsWithoutTouching(t *testing.T) {
	base := realSystem(t)
	d := &DryRunSystem{Base: base}
	path := filepath.Join(base.HomeDir(), "x.txt")

	require.NoError(t, d.WriteFile(path, []byte("x"), 0o644))
	_, err := d.Run(context.Background(), Cmd{Name: "apt-get", Args: []string{"install", "-y", "zsh"}})
	require.NoError(t, err)

	assert.Equal(t, []string{"write " + path, "run apt-get install -y zsh"}, d.Ops)
	_, err = os.Stat(path)
	assert.ErrorIs(t, err, os.ErrNotExist)
}

func TestPaths(t *testing.T) {
	p := NewPaths("/h")
	assert.Equal(t, "/h/.zshrc", p.Stub)
	assert.Equal(t, "/h/.config/shell-setup/zsh.d", p.ZshD)
	assert.Equal(t, "/h/.local/state/shell-setup/state.toml", p.StateFile)
	assert.Equal(t, "/h/.antidote", p.Expand("~/.antidote"))
	assert.Equal(t, "/etc/x", p.Expand("/etc/x"))
}
```

- [ ] **Step 2: Ejecutarlos para verificar que fallan**

Run: `go test ./internal/shellsetup/...`
Expected: FAIL, `undefined: NewRealSystem` y similares

- [ ] **Step 3: Implementación**

`internal/shellsetup/system.go`:

```go
// Package shellsetup is the domain: the tool catalog, how tools are
// installed and updated, the managed shell config, and doctor. It never
// prints; it reports through events and return values.
package shellsetup

import (
	"context"
	"errors"
	"io/fs"
	"strings"
)

// ErrLocked is returned when another shell-setup run holds the lock.
var ErrLocked = errors.New("another shell-setup run is in progress")

// Cmd describes a command to execute.
type Cmd struct {
	Name string
	Args []string
	// Interactive commands (sudo, chsh) get the user's terminal so they can
	// prompt for a password.
	Interactive bool
}

func (c Cmd) String() string {
	return strings.Join(append([]string{c.Name}, c.Args...), " ")
}

// System is every side effect shell-setup has on the machine. The domain
// never uses os, os/exec or the filesystem directly.
type System interface {
	HomeDir() string
	Getenv(key string) string
	ReadFile(path string) ([]byte, error)
	// WriteFile writes atomically (temp file + rename), creating parent dirs.
	WriteFile(path string, data []byte, perm fs.FileMode) error
	Rename(oldpath, newpath string) error
	Remove(path string) error
	RemoveAll(path string) error
	MkdirAll(path string, perm fs.FileMode) error
	Stat(path string) (fs.FileInfo, error)
	Glob(pattern string) ([]string, error)
	// LookPath searches the same PATH that Run uses.
	LookPath(file string) (string, error)
	Run(ctx context.Context, c Cmd) ([]byte, error)
	// Lock takes an exclusive, non-blocking lock; ErrLocked if it is held.
	Lock(path string) (unlock func(), err error)
}
```

`internal/shellsetup/realsystem.go`:

```go
package shellsetup

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

// TerminalHandoff runs fn while the caller's UI has released the terminal.
type TerminalHandoff func(fn func() error) error

// RealSystem is the System backed by the real machine.
type RealSystem struct {
	home    string
	logger  *slog.Logger
	handoff TerminalHandoff
	// execFn replaces command execution in tests.
	execFn func(ctx context.Context, c Cmd) ([]byte, error)
}

var (
	_ System = (*RealSystem)(nil)
	_ System = (*DryRunSystem)(nil)
)

// NewRealSystem returns the real System for the user whose home is home.
func NewRealSystem(home string, logger *slog.Logger) *RealSystem {
	return &RealSystem{home: home, logger: logger}
}

// SetTerminalHandoff sets how interactive commands get the terminal; nil
// runs them directly.
func (s *RealSystem) SetTerminalHandoff(h TerminalHandoff) { s.handoff = h }

func (s *RealSystem) HomeDir() string                         { return s.home }
func (s *RealSystem) Getenv(key string) string                { return os.Getenv(key) }
func (s *RealSystem) ReadFile(p string) ([]byte, error)       { return os.ReadFile(p) }
func (s *RealSystem) Rename(oldpath, newpath string) error    { return os.Rename(oldpath, newpath) }
func (s *RealSystem) Remove(p string) error                   { return os.Remove(p) }
func (s *RealSystem) RemoveAll(p string) error                { return os.RemoveAll(p) }
func (s *RealSystem) MkdirAll(p string, perm fs.FileMode) error { return os.MkdirAll(p, perm) }
func (s *RealSystem) Stat(p string) (fs.FileInfo, error)      { return os.Stat(p) }
func (s *RealSystem) Glob(pattern string) ([]string, error)   { return filepath.Glob(pattern) }

func (s *RealSystem) WriteFile(path string, data []byte, perm fs.FileMode) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(tmp.Name()) }() // no-op after a successful rename
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Chmod(perm); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}

// searchPath is PATH as commands see it: user binaries and mise shims first,
// so tools installed during this run are found without a new shell.
func (s *RealSystem) searchPath() string {
	return strings.Join([]string{
		filepath.Join(s.home, ".local", "bin"),
		filepath.Join(s.home, ".local", "share", "mise", "shims"),
		os.Getenv("PATH"),
	}, string(os.PathListSeparator))
}

func (s *RealSystem) LookPath(file string) (string, error) {
	for _, dir := range filepath.SplitList(s.searchPath()) {
		if dir == "" {
			continue
		}
		p := filepath.Join(dir, file)
		if info, err := os.Stat(p); err == nil && !info.IsDir() && info.Mode()&0o111 != 0 {
			return p, nil
		}
	}
	return "", fmt.Errorf("%s: %w", file, exec.ErrNotFound)
}

func (s *RealSystem) Run(ctx context.Context, c Cmd) ([]byte, error) {
	if s.execFn != nil {
		return s.execFn(ctx, c)
	}
	name := c.Name
	if !strings.Contains(name, "/") {
		p, err := s.LookPath(name)
		if err != nil {
			return nil, err
		}
		name = p
	}
	cmd := exec.CommandContext(ctx, name, c.Args...)
	cmd.Env = append(os.Environ(), "PATH="+s.searchPath())
	if c.Interactive {
		cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
		s.logger.Debug("exec (interactive)", "cmd", c.String())
		if s.handoff != nil {
			return nil, s.handoff(cmd.Run)
		}
		return nil, cmd.Run()
	}
	out, err := cmd.CombinedOutput()
	s.logger.Debug("exec", "cmd", c.String(), "output", string(out), "err", err)
	if err != nil {
		return out, fmt.Errorf("%s: %w%s", c, err, tail(out))
	}
	return out, nil
}

// tail returns the last lines of a command's output for error messages.
func tail(out []byte) string {
	trimmed := strings.TrimSpace(string(out))
	if trimmed == "" {
		return ""
	}
	lines := strings.Split(trimmed, "\n")
	if len(lines) > 3 {
		lines = lines[len(lines)-3:]
	}
	return ": " + strings.Join(lines, " | ")
}

func (s *RealSystem) Lock(path string) (func(), error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		_ = f.Close()
		if errors.Is(err, syscall.EWOULDBLOCK) {
			return nil, ErrLocked
		}
		return nil, err
	}
	return func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		_ = f.Close()
	}, nil
}
```

`internal/shellsetup/dryrunsystem.go`:

```go
package shellsetup

import (
	"context"
	"io/fs"
)

// DryRunSystem reads through Base but only records mutations and commands,
// returning success for them. It backs tests and a future --dry-run.
type DryRunSystem struct {
	Base System
	Ops  []string
}

func (d *DryRunSystem) record(op string) { d.Ops = append(d.Ops, op) }

func (d *DryRunSystem) HomeDir() string                    { return d.Base.HomeDir() }
func (d *DryRunSystem) Getenv(key string) string           { return d.Base.Getenv(key) }
func (d *DryRunSystem) ReadFile(p string) ([]byte, error)  { return d.Base.ReadFile(p) }
func (d *DryRunSystem) Stat(p string) (fs.FileInfo, error) { return d.Base.Stat(p) }
func (d *DryRunSystem) Glob(pattern string) ([]string, error) { return d.Base.Glob(pattern) }
func (d *DryRunSystem) LookPath(file string) (string, error)  { return d.Base.LookPath(file) }

func (d *DryRunSystem) WriteFile(p string, _ []byte, _ fs.FileMode) error {
	d.record("write " + p)
	return nil
}

func (d *DryRunSystem) Rename(oldpath, newpath string) error {
	d.record("rename " + oldpath + " -> " + newpath)
	return nil
}

func (d *DryRunSystem) Remove(p string) error    { d.record("remove " + p); return nil }
func (d *DryRunSystem) RemoveAll(p string) error { d.record("remove-all " + p); return nil }

func (d *DryRunSystem) MkdirAll(p string, _ fs.FileMode) error {
	d.record("mkdir " + p)
	return nil
}

func (d *DryRunSystem) Run(_ context.Context, c Cmd) ([]byte, error) {
	d.record("run " + c.String())
	return nil, nil
}

func (d *DryRunSystem) Lock(p string) (func(), error) {
	d.record("lock " + p)
	return func() {}, nil
}
```

`internal/shellsetup/paths.go`:

```go
package shellsetup

import (
	"path/filepath"
	"strings"
)

// Paths are the locations shell-setup reads and writes.
type Paths struct {
	Home           string
	ConfigDir      string // ~/.config/shell-setup
	ZshD           string // ~/.config/shell-setup/zsh.d
	GeneratedZshrc string // ~/.config/shell-setup/zshrc
	Stub           string // ~/.zshrc
	UserZshDir     string // ~/.config/zsh
	StateDir       string // ~/.local/state/shell-setup
	StateFile      string
	LockFile       string
	LogFile        string
	TmpDir         string
	// Legacy are binaries left by the old install.sh that mise now provides.
	Legacy []string
}

// NewPaths returns the paths for a home directory.
func NewPaths(home string) Paths {
	config := filepath.Join(home, ".config", "shell-setup")
	state := filepath.Join(home, ".local", "state", "shell-setup")
	return Paths{
		Home:           home,
		ConfigDir:      config,
		ZshD:           filepath.Join(config, "zsh.d"),
		GeneratedZshrc: filepath.Join(config, "zshrc"),
		Stub:           filepath.Join(home, ".zshrc"),
		UserZshDir:     filepath.Join(home, ".config", "zsh"),
		StateDir:       state,
		StateFile:      filepath.Join(state, "state.toml"),
		LockFile:       filepath.Join(state, "lock"),
		LogFile:        filepath.Join(state, "shell-setup.log"),
		TmpDir:         filepath.Join(state, "tmp"),
		Legacy: []string{
			filepath.Join(home, ".local", "bin", "starship"),
			filepath.Join(home, ".local", "bin", "zoxide"),
			"/usr/bin/fzf",
		},
	}
}

// Expand replaces a leading "~/" with the home directory.
func (p Paths) Expand(s string) string {
	if rest, ok := strings.CutPrefix(s, "~/"); ok {
		return filepath.Join(p.Home, rest)
	}
	return s
}
```

- [ ] **Step 4: Ejecutar los tests**

Run: `go test ./internal/shellsetup/...`
Expected: PASS. `gofmt -w internal/shellsetup` alinea los métodos de una línea.

- [ ] **Step 5: Commit**

```bash
git add internal/shellsetup
git commit -m "Add shellsetup System abstraction: real, dry-run, paths"
```

---

### Task 9: Manifiestos y catálogo de herramientas

**Files:**
- Create:
  - `internal/shellsetup/tool.go`
  - `internal/shellsetup/catalog.go`
  - `internal/shellsetup/catalog_test.go`
  - `internal/shellsetup/registry/{zsh,mise,antidote,starship,fzf,zoxide,nerdfont,claude,copilot,junie,agy}.toml`
  - `internal/shellsetup/registry/files/profile/{zshrc,zshrc-stub,20-core.zsh,70-aliases.zsh}`
- Move (git mv):
  - `starship/starship.toml` → `internal/shellsetup/registry/files/starship/starship.toml`
  - `zsh/plugins.txt` → `internal/shellsetup/registry/files/antidote/plugins.txt`

**Interfaces:**
- Produces:
  - Tipos `Tool`, `Kind`, `InstallSpec`, `CheckSpec`, `ShellSpec` y `FileSpec`, con los campos exactos que aparecen abajo.
  - `LoadCatalog(fs.FS) (*Catalog, error)` y `DefaultCatalog() (*Catalog, error)`.
  - Métodos de `Catalog`: `Tools() []Tool` (orden topológico, con los built-ins primero y el resto por id), `Get(id) (Tool, bool)` y `File(src) ([]byte, error)`.
  - `var registryFS embed.FS`.

- [ ] **Step 1: Mover los archivos de configuración existentes**

```bash
mkdir -p internal/shellsetup/registry/files/{starship,antidote,profile}
git mv starship/starship.toml internal/shellsetup/registry/files/starship/starship.toml
git mv zsh/plugins.txt internal/shellsetup/registry/files/antidote/plugins.txt
```

- [ ] **Step 2: Crear los archivos de perfil**

`internal/shellsetup/registry/files/profile/zshrc-stub`:

```zsh
# ~/.zshrc — managed by shell-setup. Personal config: ~/.config/zsh/*.d
source "$HOME/.config/shell-setup/zshrc"
```

`internal/shellsetup/registry/files/profile/zshrc`:

```zsh
# Generated by shell-setup — changes here are overwritten by `shell-setup update`.
# Personal config goes in ~/.config/zsh/{env,functions,aliases,custom}.d/*.zsh

export PATH="$HOME/.local/bin:$PATH"

_shell_setup_source_dir() {
    local f
    for f in "$1"/*.zsh(N); do source "$f"; done
}

_shell_setup_source_dir "$HOME/.config/zsh/env.d"
_shell_setup_source_dir "$HOME/.config/shell-setup/zsh.d"
_shell_setup_source_dir "$HOME/.config/zsh/functions.d"
_shell_setup_source_dir "$HOME/.config/zsh/aliases.d"
_shell_setup_source_dir "$HOME/.config/zsh/custom.d"
unfunction _shell_setup_source_dir
```

`internal/shellsetup/registry/files/profile/20-core.zsh`:

```zsh
# managed by shell-setup (profile: core)
autoload -Uz compinit && compinit

HISTFILE="$HOME/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
```

`internal/shellsetup/registry/files/profile/70-aliases.zsh`:

```zsh
# managed by shell-setup (profile: aliases)
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
```

- [ ] **Step 3: Crear los manifiestos**

`registry/zsh.toml`:

```toml
id = "zsh"
kind = "builtin"

[install]
backend = "apt"
package = "zsh"

[check]
cmd = ["zsh", "--version"]
```

`registry/mise.toml`:

```toml
id = "mise"
kind = "builtin"
post_install = [["mise", "settings", "set", "auto_update", "true"]]

[install]
backend = "script"
url = "https://mise.run"
interpreter = "sh"
update_cmd = ["mise", "self-update", "--yes"]

[check]
cmd = ["mise", "--version"]

[shell]
priority = 10
snippet = 'eval "$(mise activate zsh)"'
```

`registry/antidote.toml`. Lleva `git` como paquete de sistema porque `antidote load` clona los plugins de zsh con git:

```toml
id = "antidote"
kind = "plugin"
depends = ["zsh"]
system_packages = ["git"]

[install]
backend = "archive"
repo = "mattmc3/antidote"
dest = "~/.antidote"

[check]
path = "~/.antidote/antidote.zsh"

[shell]
priority = 30
snippet = '''
source "$HOME/.antidote/antidote.zsh"
antidote load "$HOME/.config/shell-setup/plugins.txt"
'''

[[files]]
src = "files/antidote/plugins.txt"
dest = "~/.config/shell-setup/plugins.txt"
```

`registry/starship.toml`:

```toml
id = "starship"
kind = "plugin"
depends = ["mise"]

[install]
backend = "mise"
package = "starship"

[check]
cmd = ["starship", "--version"]

[shell]
priority = 50
snippet = 'eval "$(starship init zsh)"'

[[files]]
src = "files/starship/starship.toml"
dest = "~/.config/starship.toml"
```

`registry/fzf.toml`:

```toml
id = "fzf"
kind = "plugin"
depends = ["mise"]

[install]
backend = "mise"
package = "fzf"

[check]
cmd = ["fzf", "--version"]

[shell]
priority = 60
snippet = 'source <(fzf --zsh)'
```

`registry/zoxide.toml`:

```toml
id = "zoxide"
kind = "plugin"
depends = ["mise"]

[install]
backend = "mise"
package = "zoxide"

[check]
cmd = ["zoxide", "--version"]

[shell]
priority = 60
snippet = '''
eval "$(zoxide init zsh)"
alias cd="z"
'''
```

`registry/nerdfont.toml`:

```toml
id = "nerdfont"
kind = "plugin"
system_packages = ["fontconfig"]

[install]
backend = "font"
repo = "ryanoasis/nerd-fonts"
asset = "JetBrainsMono.zip"
dest = "~/.local/share/fonts/JetBrainsMonoNerdFont"

[check]
path = "~/.local/share/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf"
```

`registry/claude.toml`:

```toml
id = "claude"
kind = "plugin"
optional = true

[install]
backend = "script"
url = "https://claude.ai/install.sh"
update_cmd = ["claude", "update"]

[check]
cmd = ["claude", "--version"]
```

`registry/copilot.toml`:

```toml
id = "copilot"
kind = "plugin"
optional = true

[install]
backend = "script"
url = "https://gh.io/copilot-install"

[check]
cmd = ["copilot", "--version"]
```

`registry/junie.toml`:

```toml
id = "junie"
kind = "plugin"
optional = true

[install]
backend = "script"
url = "https://junie.jetbrains.com/install.sh"

[check]
cmd = ["junie", "--version"]
```

`registry/agy.toml`:

```toml
id = "agy"
kind = "plugin"
optional = true

[install]
backend = "script"
url = "https://antigravity.google/cli/install.sh"

[check]
cmd = ["agy", "--version"]
```

- [ ] **Step 4: Escribir el test que falla**

`internal/shellsetup/catalog_test.go`:

```go
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
```

- [ ] **Step 5: Ejecutarlo para verificar que falla**

Run: `go get github.com/pelletier/go-toml/v2@v2.4.3 && go test ./internal/shellsetup/ -run Catalog`
Expected: FAIL, `undefined: DefaultCatalog`

- [ ] **Step 6: Implementación**

`internal/shellsetup/tool.go`:

```go
package shellsetup

// Kind separates the tool's own runtime dependencies from user tools.
type Kind string

const (
	// KindBuiltin tools are always installed and never user-selectable.
	KindBuiltin Kind = "builtin"
	// KindPlugin tools are the user's third-party tools.
	KindPlugin Kind = "plugin"
)

// Tool is one third-party tool, loaded from registry/<id>.toml.
type Tool struct {
	ID       string   `toml:"id"`
	Kind     Kind     `toml:"kind"`
	Optional bool     `toml:"optional"` // a failure is a warning, not an error
	Depends  []string `toml:"depends"`
	// SystemPackages are apt packages installed in the preflight.
	SystemPackages []string `toml:"system_packages"`
	// PostInstall commands run after every successful Install or Update.
	PostInstall [][]string  `toml:"post_install"`
	Install     InstallSpec `toml:"install"`
	Check       CheckSpec   `toml:"check"`
	Shell       *ShellSpec  `toml:"shell"`
	Files       []FileSpec  `toml:"files"`
}

// InstallSpec selects a backend and its parameters.
type InstallSpec struct {
	Backend     string   `toml:"backend"`     // apt | mise | script | archive | font
	Package     string   `toml:"package"`     // apt, mise
	URL         string   `toml:"url"`         // script: official installer
	Interpreter string   `toml:"interpreter"` // script: default "bash"
	UpdateCmd   []string `toml:"update_cmd"`  // script: tool's own updater
	Repo        string   `toml:"repo"`        // archive, font: GitHub owner/name
	Asset       string   `toml:"asset"`       // font: release asset name
	Dest        string   `toml:"dest"`        // archive, font: install directory
}

// CheckSpec tells whether a tool is installed: exactly one of Cmd or Path.
type CheckSpec struct {
	Cmd  []string `toml:"cmd"`  // installed if it exits 0; version = first output line
	Path string   `toml:"path"` // installed if it exists; version comes from state
}

// ShellSpec is the tool's fragment of the zsh config.
type ShellSpec struct {
	Priority int    `toml:"priority"` // 1..89, sets the load order in zsh.d
	Snippet  string `toml:"snippet"`
}

// FileSpec is a config file the tool ships, embedded under registry/.
type FileSpec struct {
	Src  string `toml:"src"`
	Dest string `toml:"dest"`
}
```

`internal/shellsetup/catalog.go`:

```go
package shellsetup

import (
	"bytes"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"slices"
	"strings"

	"github.com/pelletier/go-toml/v2"
)

//go:embed registry
var registryFS embed.FS

// Catalog is the set of tools, sorted so dependencies come first.
type Catalog struct {
	tools []Tool
	byID  map[string]Tool
	files fs.FS
}

// DefaultCatalog is the catalog embedded in the binary.
func DefaultCatalog() (*Catalog, error) {
	sub, err := fs.Sub(registryFS, "registry")
	if err != nil {
		return nil, err
	}
	return LoadCatalog(sub)
}

// LoadCatalog reads every *.toml manifest at the root of fsys. Files
// referenced by manifests are read from the same fsys.
func LoadCatalog(fsys fs.FS) (*Catalog, error) {
	names, err := fs.Glob(fsys, "*.toml")
	if err != nil {
		return nil, err
	}
	c := &Catalog{byID: map[string]Tool{}, files: fsys}
	var tools []Tool
	for _, name := range names {
		t, err := loadTool(fsys, name)
		if err != nil {
			return nil, fmt.Errorf("registry/%s: %w", name, err)
		}
		c.byID[t.ID] = t
		tools = append(tools, t)
	}
	for _, t := range tools {
		for _, dep := range t.Depends {
			if _, ok := c.byID[dep]; !ok {
				return nil, fmt.Errorf("registry/%s.toml: unknown dependency %q", t.ID, dep)
			}
		}
	}
	if c.tools, err = topoSort(tools); err != nil {
		return nil, err
	}
	return c, nil
}

func loadTool(fsys fs.FS, name string) (Tool, error) {
	data, err := fs.ReadFile(fsys, name)
	if err != nil {
		return Tool{}, err
	}
	var t Tool
	if err := toml.NewDecoder(bytes.NewReader(data)).DisallowUnknownFields().Decode(&t); err != nil {
		var strict *toml.StrictMissingError
		if errors.As(err, &strict) {
			return Tool{}, fmt.Errorf("unknown fields:\n%s", strict.String())
		}
		return Tool{}, err
	}
	if want := strings.TrimSuffix(name, ".toml"); t.ID != want {
		return Tool{}, fmt.Errorf("id %q must match file name %q", t.ID, want)
	}
	if t.Kind != KindBuiltin && t.Kind != KindPlugin {
		return Tool{}, fmt.Errorf("kind must be %q or %q", KindBuiltin, KindPlugin)
	}
	if t.Install.Backend == "" {
		return Tool{}, errors.New("install.backend is required")
	}
	if (len(t.Check.Cmd) == 0) == (t.Check.Path == "") {
		return Tool{}, errors.New("check needs exactly one of cmd or path")
	}
	for _, argv := range t.PostInstall {
		if len(argv) == 0 {
			return Tool{}, errors.New("post_install contains an empty command")
		}
	}
	if t.Shell != nil && (t.Shell.Priority < 1 || t.Shell.Priority > 89 || t.Shell.Snippet == "") {
		return Tool{}, errors.New("shell needs a priority in 1..89 and a snippet")
	}
	for _, f := range t.Files {
		if _, err := fs.Stat(fsys, f.Src); err != nil {
			return Tool{}, fmt.Errorf("file %s: %w", f.Src, err)
		}
	}
	return t, nil
}

// topoSort puts dependencies first. Among tools that are ready, built-ins
// go first and then ids alphabetically, so the order is stable.
func topoSort(tools []Tool) ([]Tool, error) {
	done := map[string]bool{}
	remaining := slices.Clone(tools)
	out := make([]Tool, 0, len(tools))
	for len(remaining) > 0 {
		var ready []Tool
		for _, t := range remaining {
			if !slices.ContainsFunc(t.Depends, func(d string) bool { return !done[d] }) {
				ready = append(ready, t)
			}
		}
		if len(ready) == 0 {
			ids := make([]string, len(remaining))
			for i, t := range remaining {
				ids[i] = t.ID
			}
			slices.Sort(ids)
			return nil, fmt.Errorf("dependency cycle between: %s", strings.Join(ids, ", "))
		}
		next := slices.MinFunc(ready, func(a, b Tool) int {
			if (a.Kind == KindBuiltin) != (b.Kind == KindBuiltin) {
				if a.Kind == KindBuiltin {
					return -1
				}
				return 1
			}
			return strings.Compare(a.ID, b.ID)
		})
		out = append(out, next)
		done[next.ID] = true
		remaining = slices.DeleteFunc(remaining, func(t Tool) bool { return t.ID == next.ID })
	}
	return out, nil
}

// Tools returns the tools in install order.
func (c *Catalog) Tools() []Tool { return slices.Clone(c.tools) }

// Get returns a tool by id.
func (c *Catalog) Get(id string) (Tool, bool) {
	t, ok := c.byID[id]
	return t, ok
}

// File returns an embedded file referenced by a manifest or the profile.
func (c *Catalog) File(src string) ([]byte, error) { return fs.ReadFile(c.files, src) }
```

- [ ] **Step 7: Ejecutar los tests**

Run: `go test ./internal/shellsetup/...`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add internal/shellsetup go.mod go.sum starship zsh
git commit -m "Add tool manifests, profile files and catalog loader"
```

---

### Task 10: Eventos, informe, state y archivos gestionados

**Files:**
- Create:
  - `internal/shellsetup/event.go`
  - `internal/shellsetup/report.go`
  - `internal/shellsetup/state.go`
  - `internal/shellsetup/managed.go`
  - `internal/shellsetup/managed_test.go`
  - `internal/shellsetup/state_test.go`

**Interfaces:**
- Produces:
  - Tipos `Phase` (`PhasePreflight`, `PhaseTools`, `PhaseShell`) y `Action` (`ActionNone`, `ActionInstall`, `ActionUpdate`).
  - Tipo `Result`, con los valores `ResultOK`, `ResultSkipped`, `ResultModified`, `ResultWarned` y `ResultFailed`.
  - `type Event interface{ event() }`, implementado por `PhaseStarted{Phase}`, `ToolStarted{ID, Action}`, `ToolFinished{ID, Action, Result, Version, Err}` y `FileFinished{Path, Result}`.
  - `var ErrDependencyFailed`.
  - `ToolReport{ID string; Optional bool; Action Action; Result Result; Version string; Err error}` y `FileReport{Path string; Result Result}`.
  - Tipo `CheckStatus`, con `CheckOK`, `CheckWarn`, `CheckFail` y `CheckSkip`; y `CheckResult{Name string; Status CheckStatus; Detail string}`.
  - `Report{Tools []ToolReport; Files []FileReport; Checks []CheckResult}` con `Failed() bool`.
  - `State{SchemaVersion int; Files map[string]string; Versions map[string]string}`, `LoadState(System, path) (*State, error)` y `(*State).Save(System, path) error`.
  - `hashBytes([]byte) string`.
  - `fileWriter{sys System; state *State; now func() time.Time}` con `write(path string, content []byte, force bool) (Result, error)` y `remove(path string) (Result, error)`.

- [ ] **Step 1: Escribir los tests que fallan**

`internal/shellsetup/state_test.go`:

```go
package shellsetup

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStateRoundTrip(t *testing.T) {
	sys, _ := newTestSystem(t)
	path := filepath.Join(sys.HomeDir(), "state.toml")

	st, err := LoadState(sys, path)
	require.NoError(t, err)
	assert.Equal(t, stateSchemaVersion, st.SchemaVersion)
	st.Files["/h/.zshrc"] = "abc"
	st.Versions["nerdfont"] = "v3.4.0"
	require.NoError(t, st.Save(sys, path))

	again, err := LoadState(sys, path)
	require.NoError(t, err)
	assert.Equal(t, st, again)
}

func TestStateFromNewerVersionIsRejected(t *testing.T) {
	sys, _ := newTestSystem(t)
	path := filepath.Join(sys.HomeDir(), "state.toml")
	require.NoError(t, os.WriteFile(path, []byte("schema_version = 99\n"), 0o644))

	_, err := LoadState(sys, path)
	assert.ErrorContains(t, err, "newer shell-setup")
}

func TestReportFailed(t *testing.T) {
	assert.False(t, Report{Tools: []ToolReport{{Result: ResultOK}, {Result: ResultWarned}}}.Failed())
	assert.True(t, Report{Tools: []ToolReport{{Result: ResultFailed}}}.Failed())
	assert.True(t, Report{Checks: []CheckResult{{Status: CheckFail}}}.Failed())
	assert.False(t, Report{Checks: []CheckResult{{Status: CheckWarn}}}.Failed())
}
```

`internal/shellsetup/managed_test.go`, que cubre una por una las filas de la tabla "Archivos gestionados y ediciones manuales" de la spec:

```go
package shellsetup

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

var fixedNow = time.Date(2026, 10, 10, 12, 0, 0, 0, time.UTC)

const backupSuffix = ".bak.20261010120000"

func newWriter(t *testing.T) (fileWriter, string) {
	sys, _ := newTestSystem(t)
	st := &State{Files: map[string]string{}, Versions: map[string]string{}}
	return fileWriter{sys: sys, state: st, now: func() time.Time { return fixedNow }},
		filepath.Join(sys.HomeDir(), ".zshrc")
}

func read(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	require.NoError(t, err)
	return string(data)
}

func TestWriteMissingFile(t *testing.T) {
	w, path := newWriter(t)
	res, err := w.write(path, []byte("new"), false)
	require.NoError(t, err)
	assert.Equal(t, ResultOK, res)
	assert.Equal(t, "new", read(t, path))
	assert.Equal(t, hashBytes([]byte("new")), w.state.Files[path])
}

func TestWriteFirstRunBacksUpUnmanagedFile(t *testing.T) {
	w, path := newWriter(t)
	require.NoError(t, os.WriteFile(path, []byte("mine"), 0o644))

	res, err := w.write(path, []byte("new"), false)
	require.NoError(t, err)
	assert.Equal(t, ResultOK, res)
	assert.Equal(t, "new", read(t, path))
	assert.Equal(t, "mine", read(t, path+backupSuffix))
}

func TestWriteFirstRunIdenticalContentNoBackup(t *testing.T) {
	w, path := newWriter(t)
	require.NoError(t, os.WriteFile(path, []byte("same"), 0o644))

	res, err := w.write(path, []byte("same"), false)
	require.NoError(t, err)
	assert.Equal(t, ResultOK, res)
	assert.NoFileExists(t, path+backupSuffix)
	assert.Equal(t, hashBytes([]byte("same")), w.state.Files[path])
}

func TestWriteUnmodifiedManagedFileUpdatesWithoutBackup(t *testing.T) {
	w, path := newWriter(t)
	_, err := w.write(path, []byte("v1"), false)
	require.NoError(t, err)

	res, err := w.write(path, []byte("v2"), false)
	require.NoError(t, err)
	assert.Equal(t, ResultOK, res)
	assert.Equal(t, "v2", read(t, path))
	assert.NoFileExists(t, path+backupSuffix)
}

func TestWriteModifiedManagedFileIsLeftAlone(t *testing.T) {
	w, path := newWriter(t)
	_, err := w.write(path, []byte("v1"), false)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(path, []byte("hand edit"), 0o644))

	res, err := w.write(path, []byte("v2"), false)
	require.NoError(t, err)
	assert.Equal(t, ResultModified, res)
	assert.Equal(t, "hand edit", read(t, path))
}

func TestWriteModifiedManagedFileWithForceBacksUp(t *testing.T) {
	w, path := newWriter(t)
	_, err := w.write(path, []byte("v1"), false)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(path, []byte("hand edit"), 0o644))

	res, err := w.write(path, []byte("v2"), true)
	require.NoError(t, err)
	assert.Equal(t, ResultOK, res)
	assert.Equal(t, "v2", read(t, path))
	assert.Equal(t, "hand edit", read(t, path+backupSuffix))
}

func TestRemoveManagedFile(t *testing.T) {
	w, path := newWriter(t)
	_, err := w.write(path, []byte("v1"), false)
	require.NoError(t, err)

	res, err := w.remove(path)
	require.NoError(t, err)
	assert.Equal(t, ResultOK, res)
	assert.NoFileExists(t, path)
	assert.NotContains(t, w.state.Files, path)
}

func TestRemoveKeepsHandEditedFile(t *testing.T) {
	w, path := newWriter(t)
	_, err := w.write(path, []byte("v1"), false)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(path, []byte("hand edit"), 0o644))

	res, err := w.remove(path)
	require.NoError(t, err)
	assert.Equal(t, ResultModified, res)
	assert.FileExists(t, path)
}
```

- [ ] **Step 2: Ejecutarlos para verificar que fallan**

Run: `go test ./internal/shellsetup/ -run 'State|Report|Write|Remove'`
Expected: FAIL, `undefined: LoadState` y similares

- [ ] **Step 3: Implementación**

`internal/shellsetup/event.go`:

```go
package shellsetup

import "errors"

// ErrDependencyFailed marks a tool skipped because a dependency failed.
var ErrDependencyFailed = errors.New("dependency failed")

// Phase is a stage of Init/Update.
type Phase string

const (
	PhasePreflight Phase = "preflight"
	PhaseTools     Phase = "tools"
	PhaseShell     Phase = "shell"
)

// Action is what was done to a tool.
type Action string

const (
	ActionNone    Action = ""
	ActionInstall Action = "install"
	ActionUpdate  Action = "update"
)

// Result is the outcome for a tool or file.
type Result string

const (
	ResultOK       Result = "ok"
	ResultSkipped  Result = "skipped"
	ResultModified Result = "modified" // managed file edited by hand, left alone
	ResultWarned   Result = "warned"   // optional tool failed
	ResultFailed   Result = "failed"
)

// Event is published on the operation's channel while it runs.
type Event interface{ event() }

type PhaseStarted struct{ Phase Phase }

type ToolStarted struct {
	ID     string
	Action Action
}

type ToolFinished struct {
	ID      string
	Action  Action
	Result  Result
	Version string
	Err     error
}

type FileFinished struct {
	Path   string
	Result Result
}

func (PhaseStarted) event() {}
func (ToolStarted) event()  {}
func (ToolFinished) event() {}
func (FileFinished) event() {}
```

`internal/shellsetup/report.go`:

```go
package shellsetup

// ToolReport is the outcome for one tool.
type ToolReport struct {
	ID       string
	Optional bool
	Action   Action
	Result   Result
	Version  string
	Err      error
}

// FileReport is the outcome for one managed file.
type FileReport struct {
	Path   string
	Result Result
}

// CheckStatus is a doctor check outcome.
type CheckStatus string

const (
	CheckOK   CheckStatus = "ok"
	CheckWarn CheckStatus = "warn"
	CheckFail CheckStatus = "fail"
	CheckSkip CheckStatus = "skip"
)

// CheckResult is one doctor check.
type CheckResult struct {
	Name   string
	Status CheckStatus
	Detail string
}

// Report is what an operation returns.
type Report struct {
	Tools  []ToolReport
	Files  []FileReport
	Checks []CheckResult
}

// Failed reports whether a required tool failed or a check failed.
func (r Report) Failed() bool {
	for _, t := range r.Tools {
		if t.Result == ResultFailed {
			return true
		}
	}
	for _, c := range r.Checks {
		if c.Status == CheckFail {
			return true
		}
	}
	return false
}
```

`internal/shellsetup/state.go`:

```go
package shellsetup

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io/fs"

	"github.com/pelletier/go-toml/v2"
)

const stateSchemaVersion = 1

// State is what shell-setup knows about this machine from previous runs.
type State struct {
	SchemaVersion int `toml:"schema_version"`
	// Files maps each managed file to the hash of what shell-setup wrote.
	Files map[string]string `toml:"files"`
	// Versions records versions backends know but checks cannot report.
	Versions map[string]string `toml:"versions"`
}

// LoadState reads the state file; a missing file is an empty state.
func LoadState(sys System, path string) (*State, error) {
	st := &State{}
	data, err := sys.ReadFile(path)
	switch {
	case errors.Is(err, fs.ErrNotExist):
	case err != nil:
		return nil, err
	default:
		if err := toml.Unmarshal(data, st); err != nil {
			return nil, fmt.Errorf("reading %s: %w", path, err)
		}
	}
	if st.SchemaVersion > stateSchemaVersion {
		return nil, fmt.Errorf("%s was written by a newer shell-setup (schema %d); run shell-setup self-update", path, st.SchemaVersion)
	}
	// Schema 1 is the first version: nothing older to migrate yet.
	st.SchemaVersion = stateSchemaVersion
	if st.Files == nil {
		st.Files = map[string]string{}
	}
	if st.Versions == nil {
		st.Versions = map[string]string{}
	}
	return st, nil
}

// Save writes the state file.
func (s *State) Save(sys System, path string) error {
	data, err := toml.Marshal(s)
	if err != nil {
		return err
	}
	return sys.WriteFile(path, data, 0o644)
}

func hashBytes(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}
```

`internal/shellsetup/managed.go`:

```go
package shellsetup

import (
	"bytes"
	"errors"
	"io/fs"
	"time"
)

// fileWriter writes files shell-setup owns. It never overwrites a manual
// edit unless forced, and backs up anything it replaces that it did not
// write itself.
type fileWriter struct {
	sys   System
	state *State
	now   func() time.Time
}

func (w fileWriter) write(path string, content []byte, force bool) (Result, error) {
	current, err := w.sys.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return w.put(path, content)
	}
	if err != nil {
		return ResultFailed, err
	}
	recorded, managed := w.state.Files[path]
	edited := managed && hashBytes(current) != recorded
	if edited && !force {
		return ResultModified, nil
	}
	if bytes.Equal(current, content) {
		w.state.Files[path] = hashBytes(content)
		return ResultOK, nil
	}
	if !managed || edited {
		if err := w.sys.Rename(path, path+".bak."+w.now().Format("20060102150405")); err != nil {
			return ResultFailed, err
		}
	}
	return w.put(path, content)
}

func (w fileWriter) put(path string, content []byte) (Result, error) {
	if err := w.sys.WriteFile(path, content, 0o644); err != nil {
		return ResultFailed, err
	}
	w.state.Files[path] = hashBytes(content)
	return ResultOK, nil
}

// remove deletes a managed file that is no longer wanted, unless edited.
func (w fileWriter) remove(path string) (Result, error) {
	current, err := w.sys.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		delete(w.state.Files, path)
		return ResultOK, nil
	}
	if err != nil {
		return ResultFailed, err
	}
	if hashBytes(current) != w.state.Files[path] {
		return ResultModified, nil
	}
	if err := w.sys.Remove(path); err != nil {
		return ResultFailed, err
	}
	delete(w.state.Files, path)
	return ResultOK, nil
}
```

- [ ] **Step 4: Ejecutar los tests**

Run: `go test ./internal/shellsetup/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add internal/shellsetup
git commit -m "Add events, report, state and managed-file writer"
```

---

### Task 11: Fetcher y backends `apt`, `mise` y `script`

**Files:**
- Create:
  - `internal/shellsetup/fetch.go`
  - `internal/shellsetup/backend.go`
  - `internal/shellsetup/aptbackend.go`
  - `internal/shellsetup/misebackend.go`
  - `internal/shellsetup/scriptbackend.go`
  - `internal/shellsetup/fetch_test.go`
  - `internal/shellsetup/backend_test.go`
- Modify: `internal/shellsetup/helpers_test.go` (añade `fakeFetcher`)

**Interfaces:**
- Consumes: `System`, `Cmd`, `Paths`, `State` y `Tool` (Tasks 8–10).
- Produces:
  - `type Fetcher interface{ Fetch(ctx, url string) ([]byte, error) }` y `HTTPFetcher{Client *http.Client; Token string}`.
  - `latestTag(ctx, Fetcher, repo string) (string, error)`.
  - `Env{System System; Fetcher Fetcher; Paths Paths; State *State}`.
  - `type Backend interface{ Install(ctx, Env, Tool) error; Update(ctx, Env, Tool) error }` y `DefaultBackends() map[string]Backend`, que devuelve `apt`, `mise`, `script`, `archive` y `font`. `archive` y `font` se implementan en la Task 12.
  - `aptPackages([]Tool) []string` y `missingAptPackages(ctx, System, []string) []string`.
  - Helper de test: `fakeFetcher{data map[string][]byte; requested []string}`.

- [ ] **Step 1: Añadir `fakeFetcher` a `helpers_test.go`**

Añade al final de `internal/shellsetup/helpers_test.go` (incluye `fmt` en los imports):

```go
// fakeFetcher serves canned responses and records requested URLs.
type fakeFetcher struct {
	data      map[string][]byte
	requested []string
}

func (f *fakeFetcher) Fetch(_ context.Context, url string) ([]byte, error) {
	f.requested = append(f.requested, url)
	b, ok := f.data[url]
	if !ok {
		return nil, fmt.Errorf("GET %s: 404 Not Found", url)
	}
	return b, nil
}
```

- [ ] **Step 2: Escribir los tests que fallan**

`internal/shellsetup/fetch_test.go`:

```go
package shellsetup

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHTTPFetcher(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		assert.Empty(t, r.Header.Get("Authorization"), "token only goes to api.github.com")
		if r.URL.Path == "/ok" {
			_, _ = w.Write([]byte("body"))
			return
		}
		http.NotFound(w, r)
	}))
	defer srv.Close()
	f := HTTPFetcher{Client: srv.Client(), Token: "secret"}

	data, err := f.Fetch(context.Background(), srv.URL+"/ok")
	require.NoError(t, err)
	assert.Equal(t, "body", string(data))

	_, err = f.Fetch(context.Background(), srv.URL+"/missing")
	assert.ErrorContains(t, err, "404")
}

func TestLatestTag(t *testing.T) {
	f := &fakeFetcher{data: map[string][]byte{
		"https://api.github.com/repos/o/r/releases/latest": []byte(`{"tag_name":"v1.2.3"}`),
		"https://api.github.com/repos/o/empty/releases/latest": []byte(`{}`),
	}}
	tag, err := latestTag(context.Background(), f, "o/r")
	require.NoError(t, err)
	assert.Equal(t, "v1.2.3", tag)

	_, err = latestTag(context.Background(), f, "o/empty")
	assert.ErrorContains(t, err, "no tag")
}
```

`internal/shellsetup/backend_test.go`:

```go
package shellsetup

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func testEnv(t *testing.T, f *fakeFetcher) (Env, *recorder) {
	sys, rec := newTestSystem(t)
	st := &State{Files: map[string]string{}, Versions: map[string]string{}}
	return Env{System: sys, Fetcher: f, Paths: NewPaths(sys.HomeDir()), State: st}, rec
}

func scriptTool(update ...string) Tool {
	return Tool{ID: "claude", Install: InstallSpec{Backend: "script", URL: "https://x/install.sh", UpdateCmd: update}}
}

func TestScriptInstallRunsDownloadedInstaller(t *testing.T) {
	f := &fakeFetcher{data: map[string][]byte{"https://x/install.sh": []byte("echo hi")}}
	env, rec := testEnv(t, f)
	script := filepath.Join(env.Paths.TmpDir, "claude-install.sh")

	require.NoError(t, scriptBackend{}.Install(context.Background(), env, scriptTool()))

	assert.Equal(t, []string{"bash " + script}, rec.commands())
	assert.NoFileExists(t, script, "installer is removed afterwards")
}

func TestScriptInterpreter(t *testing.T) {
	f := &fakeFetcher{data: map[string][]byte{"https://x/install.sh": []byte("echo hi")}}
	env, rec := testEnv(t, f)
	tool := scriptTool()
	tool.Install.Interpreter = "sh"

	require.NoError(t, scriptBackend{}.Install(context.Background(), env, tool))
	assert.Equal(t, []string{"sh " + filepath.Join(env.Paths.TmpDir, "claude-install.sh")}, rec.commands())
}

func TestScriptUpdateUsesOwnUpdater(t *testing.T) {
	env, rec := testEnv(t, &fakeFetcher{})
	require.NoError(t, scriptBackend{}.Update(context.Background(), env, scriptTool("claude", "update")))
	assert.Equal(t, []string{"claude update"}, rec.commands())
}

func TestScriptUpdateWithoutUpdaterReinstalls(t *testing.T) {
	f := &fakeFetcher{data: map[string][]byte{"https://x/install.sh": []byte("echo hi")}}
	env, rec := testEnv(t, f)
	require.NoError(t, scriptBackend{}.Update(context.Background(), env, scriptTool()))
	assert.Len(t, rec.commands(), 1)
	assert.Equal(t, []string{"https://x/install.sh"}, f.requested)
}

func TestScriptDownloadErrorRunsNothing(t *testing.T) {
	env, rec := testEnv(t, &fakeFetcher{})
	err := scriptBackend{}.Install(context.Background(), env, scriptTool())
	assert.ErrorContains(t, err, "404")
	assert.Empty(t, rec.commands())
}

func TestMiseBackend(t *testing.T) {
	env, rec := testEnv(t, &fakeFetcher{})
	tool := Tool{ID: "starship", Install: InstallSpec{Backend: "mise", Package: "starship"}}
	require.NoError(t, miseBackend{}.Install(context.Background(), env, tool))
	require.NoError(t, miseBackend{}.Update(context.Background(), env, tool))
	assert.Equal(t, []string{"mise use -g starship@latest", "mise upgrade starship"}, rec.commands())
}

func TestAptPackages(t *testing.T) {
	tools := []Tool{
		{ID: "zsh", Install: InstallSpec{Backend: "apt", Package: "zsh"}},
		{ID: "antidote", SystemPackages: []string{"git"}, Install: InstallSpec{Backend: "archive"}},
		{ID: "nerdfont", SystemPackages: []string{"fontconfig", "git"}, Install: InstallSpec{Backend: "font"}},
	}
	assert.Equal(t, []string{"fontconfig", "git", "zsh"}, aptPackages(tools))
}

func TestMissingAptPackages(t *testing.T) {
	env, rec := testEnv(t, &fakeFetcher{})
	rec.out["dpkg-query -W -f=${Status} zsh"] = "install ok installed"
	rec.setFail("dpkg-query -W -f=${Status} git", errExit)

	missing := missingAptPackages(context.Background(), env.System, []string{"git", "zsh"})
	assert.Equal(t, []string{"git"}, missing)
}

func TestDefaultBackendsCoverCatalog(t *testing.T) {
	cat, err := DefaultCatalog()
	require.NoError(t, err)
	backends := DefaultBackends()
	for _, tool := range cat.Tools() {
		assert.Contains(t, backends, tool.Install.Backend, tool.ID)
	}
}
```

- [ ] **Step 3: Ejecutarlos para verificar que fallan**

Run: `go test ./internal/shellsetup/ -run 'Fetch|Tag|Script|Mise|Apt|Backends'`
Expected: FAIL, `undefined: HTTPFetcher` y similares

- [ ] **Step 4: Implementación**

`internal/shellsetup/fetch.go`:

```go
package shellsetup

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// Fetcher downloads a URL into memory.
type Fetcher interface {
	Fetch(ctx context.Context, url string) ([]byte, error)
}

// HTTPFetcher fetches over HTTP. Token, if set, is sent only to the GitHub
// API (raises its rate limit).
type HTTPFetcher struct {
	Client *http.Client
	Token  string
}

func (f HTTPFetcher) Fetch(ctx context.Context, url string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	if f.Token != "" && strings.HasPrefix(url, "https://api.github.com/") {
		req.Header.Set("Authorization", "Bearer "+f.Token)
	}
	client := f.Client
	if client == nil {
		client = http.DefaultClient
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, fmt.Errorf("GET %s: %s", url, resp.Status)
	}
	return io.ReadAll(resp.Body)
}

// latestTag returns the tag of a GitHub repo's latest release.
func latestTag(ctx context.Context, f Fetcher, repo string) (string, error) {
	data, err := f.Fetch(ctx, "https://api.github.com/repos/"+repo+"/releases/latest")
	if err != nil {
		return "", err
	}
	var rel struct {
		TagName string `json:"tag_name"`
	}
	if err := json.Unmarshal(data, &rel); err != nil {
		return "", fmt.Errorf("parsing latest release of %s: %w", repo, err)
	}
	if rel.TagName == "" {
		return "", fmt.Errorf("latest release of %s has no tag", repo)
	}
	return rel.TagName, nil
}
```

`internal/shellsetup/backend.go`:

```go
package shellsetup

import "context"

// Env is what backends work with.
type Env struct {
	System  System
	Fetcher Fetcher
	Paths   Paths
	State   *State
}

// Backend installs and updates tools of one kind. Whether a tool is
// installed is decided by its check, never by the backend.
type Backend interface {
	Install(ctx context.Context, env Env, t Tool) error
	Update(ctx context.Context, env Env, t Tool) error
}

// DefaultBackends maps manifest backend names to implementations.
func DefaultBackends() map[string]Backend {
	return map[string]Backend{
		"apt":     aptBackend{},
		"mise":    miseBackend{},
		"script":  scriptBackend{},
		"archive": archiveBackend{},
		"font":    fontBackend{},
	}
}
```

`internal/shellsetup/aptbackend.go`:

```go
package shellsetup

import (
	"context"
	"maps"
	"slices"
	"strings"
)

// aptBackend tools are installed by the preflight, in one privileged
// apt-get call together with every tool's system_packages; Install and
// Update have nothing left to do.
type aptBackend struct{}

func (aptBackend) Install(context.Context, Env, Tool) error { return nil }
func (aptBackend) Update(context.Context, Env, Tool) error  { return nil }

// aptPackages lists every apt package the tools need, sorted and unique.
func aptPackages(tools []Tool) []string {
	set := map[string]bool{}
	for _, t := range tools {
		for _, p := range t.SystemPackages {
			set[p] = true
		}
		if t.Install.Backend == "apt" {
			set[t.Install.Package] = true
		}
	}
	return slices.Sorted(maps.Keys(set))
}

// missingAptPackages returns the packages dpkg does not report installed.
func missingAptPackages(ctx context.Context, sys System, pkgs []string) []string {
	var missing []string
	for _, p := range pkgs {
		out, err := sys.Run(ctx, Cmd{Name: "dpkg-query", Args: []string{"-W", "-f=${Status}", p}})
		if err != nil || !strings.Contains(string(out), "install ok installed") {
			missing = append(missing, p)
		}
	}
	return missing
}
```

`internal/shellsetup/misebackend.go`:

```go
package shellsetup

import "context"

// miseBackend installs user tools as global mise tools.
type miseBackend struct{}

func (miseBackend) Install(ctx context.Context, env Env, t Tool) error {
	_, err := env.System.Run(ctx, Cmd{Name: "mise", Args: []string{"use", "-g", t.Install.Package + "@latest"}})
	return err
}

func (miseBackend) Update(ctx context.Context, env Env, t Tool) error {
	_, err := env.System.Run(ctx, Cmd{Name: "mise", Args: []string{"upgrade", t.Install.Package}})
	return err
}
```

`internal/shellsetup/scriptbackend.go`:

```go
package shellsetup

import (
	"context"
	"path/filepath"
)

// scriptBackend runs a vendor's official install script.
type scriptBackend struct{}

func (scriptBackend) Install(ctx context.Context, env Env, t Tool) error {
	script, err := env.Fetcher.Fetch(ctx, t.Install.URL)
	if err != nil {
		return err
	}
	path := filepath.Join(env.Paths.TmpDir, t.ID+"-install.sh")
	if err := env.System.WriteFile(path, script, 0o700); err != nil {
		return err
	}
	defer func() { _ = env.System.Remove(path) }()
	interpreter := t.Install.Interpreter
	if interpreter == "" {
		interpreter = "bash"
	}
	_, err = env.System.Run(ctx, Cmd{Name: interpreter, Args: []string{path}})
	return err
}

// Update uses the tool's own updater when it has one, else reinstalls.
func (b scriptBackend) Update(ctx context.Context, env Env, t Tool) error {
	if len(t.Install.UpdateCmd) == 0 {
		return b.Install(ctx, env, t)
	}
	_, err := env.System.Run(ctx, Cmd{Name: t.Install.UpdateCmd[0], Args: t.Install.UpdateCmd[1:]})
	return err
}
```

Para que el paquete compile antes de la Task 12, crea `internal/shellsetup/archivebackend.go` y `fontbackend.go` con stubs. La Task 12 los sustituye:

```go
// archivebackend.go
package shellsetup

import (
	"context"
	"errors"
)

type archiveBackend struct{}

func (archiveBackend) Install(context.Context, Env, Tool) error { return errors.New("archive backend: not implemented") }
func (archiveBackend) Update(context.Context, Env, Tool) error  { return errors.New("archive backend: not implemented") }
```

```go
// fontbackend.go
package shellsetup

import (
	"context"
	"errors"
)

type fontBackend struct{}

func (fontBackend) Install(context.Context, Env, Tool) error { return errors.New("font backend: not implemented") }
func (fontBackend) Update(context.Context, Env, Tool) error  { return errors.New("font backend: not implemented") }
```

- [ ] **Step 5: Ejecutar los tests**

Run: `go test ./internal/shellsetup/...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add internal/shellsetup
git commit -m "Add fetcher and apt, mise and script backends"
```

---

### Task 12: Backends `archive` (antidote) y `font` (Nerd Font)

**Files:**
- Modify: `internal/shellsetup/archivebackend.go` y `internal/shellsetup/fontbackend.go` (se sustituyen los stubs)
- Create: `internal/shellsetup/archive_test.go`

**Interfaces:**
- Consumes: `latestTag`, `Fetcher`, `Env` y `State.Versions` (Tasks 10–11).
- Produces: `archiveBackend` y `fontBackend`, que cumplen `Backend`. Ambos guardan el tag instalado en `env.State.Versions[t.ID]`, y `Update` no descarga nada si ese tag ya es el último. También produce `extractTarGz(System, []byte, dest string) error`.

- [ ] **Step 1: Escribir el test que falla**

`internal/shellsetup/archive_test.go`:

```go
package shellsetup

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func tarGz(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for name, body := range files {
		require.NoError(t, tw.WriteHeader(&tar.Header{Name: name, Mode: 0o644, Size: int64(len(body)), Typeflag: tar.TypeReg}))
		_, err := tw.Write([]byte(body))
		require.NoError(t, err)
	}
	require.NoError(t, tw.Close())
	require.NoError(t, gz.Close())
	return buf.Bytes()
}

func zipFile(t *testing.T, files map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, body := range files {
		w, err := zw.Create(name)
		require.NoError(t, err)
		_, err = w.Write([]byte(body))
		require.NoError(t, err)
	}
	require.NoError(t, zw.Close())
	return buf.Bytes()
}

var antidoteTool = Tool{ID: "antidote", Install: InstallSpec{Backend: "archive", Repo: "mattmc3/antidote", Dest: "~/.antidote"}}

const (
	antidoteLatest  = "https://api.github.com/repos/mattmc3/antidote/releases/latest"
	antidoteTarball = "https://github.com/mattmc3/antidote/archive/refs/tags/v1.9.0.tar.gz"
)

func TestArchiveInstallExtractsAndRecordsTag(t *testing.T) {
	f := &fakeFetcher{data: map[string][]byte{
		antidoteLatest:  []byte(`{"tag_name":"v1.9.0"}`),
		antidoteTarball: tarGz(t, map[string]string{"antidote-1.9.0/antidote.zsh": "# antidote", "antidote-1.9.0/functions/x": "x"}),
	}}
	env, _ := testEnv(t, f)

	require.NoError(t, archiveBackend{}.Install(context.Background(), env, antidoteTool))

	data, err := os.ReadFile(filepath.Join(env.Paths.Home, ".antidote", "antidote.zsh"))
	require.NoError(t, err)
	assert.Equal(t, "# antidote", string(data))
	assert.FileExists(t, filepath.Join(env.Paths.Home, ".antidote", "functions", "x"))
	assert.Equal(t, "v1.9.0", env.State.Versions["antidote"])
}

func TestArchiveUpdateSkipsWhenCurrent(t *testing.T) {
	f := &fakeFetcher{data: map[string][]byte{antidoteLatest: []byte(`{"tag_name":"v1.9.0"}`)}}
	env, _ := testEnv(t, f)
	env.State.Versions["antidote"] = "v1.9.0"

	require.NoError(t, archiveBackend{}.Update(context.Background(), env, antidoteTool))
	assert.Equal(t, []string{antidoteLatest}, f.requested, "tarball not downloaded")
}

func TestArchiveRejectsPathTraversal(t *testing.T) {
	f := &fakeFetcher{data: map[string][]byte{
		antidoteLatest:  []byte(`{"tag_name":"v1.9.0"}`),
		antidoteTarball: tarGz(t, map[string]string{"top/../../evil": "x"}),
	}}
	env, _ := testEnv(t, f)
	err := archiveBackend{}.Install(context.Background(), env, antidoteTool)
	assert.ErrorContains(t, err, "unsafe path")
}

func TestFontInstallKeepsOnlyTTFAndRefreshesCache(t *testing.T) {
	tool := Tool{ID: "nerdfont", Install: InstallSpec{
		Backend: "font", Repo: "ryanoasis/nerd-fonts", Asset: "JetBrainsMono.zip",
		Dest: "~/.local/share/fonts/JetBrainsMonoNerdFont",
	}}
	f := &fakeFetcher{data: map[string][]byte{
		"https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest":                []byte(`{"tag_name":"v3.4.0"}`),
		"https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip": zipFile(t, map[string]string{"JetBrainsMonoNerdFont-Regular.ttf": "font", "README.md": "readme"}),
	}}
	env, rec := testEnv(t, f)
	dest := filepath.Join(env.Paths.Home, ".local", "share", "fonts", "JetBrainsMonoNerdFont")

	require.NoError(t, fontBackend{}.Install(context.Background(), env, tool))

	assert.FileExists(t, filepath.Join(dest, "JetBrainsMonoNerdFont-Regular.ttf"))
	assert.NoFileExists(t, filepath.Join(dest, "README.md"))
	assert.Equal(t, []string{"fc-cache -f " + dest}, rec.commands())
	assert.Equal(t, "v3.4.0", env.State.Versions["nerdfont"])
}
```

- [ ] **Step 2: Ejecutarlo para verificar que falla**

Run: `go test ./internal/shellsetup/ -run 'Archive|Font'`
Expected: FAIL, `archive backend: not implemented`

- [ ] **Step 3: Implementación**

`internal/shellsetup/archivebackend.go`:

```go
package shellsetup

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"path/filepath"
	"strings"
)

// archiveBackend installs a GitHub repo's source tarball at its latest
// release tag into Install.Dest.
type archiveBackend struct{}

func (archiveBackend) Install(ctx context.Context, env Env, t Tool) error {
	return installArchive(ctx, env, t, false)
}

func (archiveBackend) Update(ctx context.Context, env Env, t Tool) error {
	return installArchive(ctx, env, t, true)
}

func installArchive(ctx context.Context, env Env, t Tool, skipIfCurrent bool) error {
	tag, err := latestTag(ctx, env.Fetcher, t.Install.Repo)
	if err != nil {
		return err
	}
	if skipIfCurrent && env.State.Versions[t.ID] == tag {
		return nil
	}
	data, err := env.Fetcher.Fetch(ctx, fmt.Sprintf("https://github.com/%s/archive/refs/tags/%s.tar.gz", t.Install.Repo, tag))
	if err != nil {
		return err
	}
	dest := env.Paths.Expand(t.Install.Dest)
	staging := dest + ".new"
	if err := env.System.RemoveAll(staging); err != nil {
		return err
	}
	if err := extractTarGz(env.System, data, staging); err != nil {
		return fmt.Errorf("extracting %s: %w", t.ID, err)
	}
	if err := env.System.RemoveAll(dest); err != nil {
		return err
	}
	if err := env.System.Rename(staging, dest); err != nil {
		return err
	}
	env.State.Versions[t.ID] = tag
	return nil
}

// extractTarGz extracts directories and regular files into dest, dropping
// the top-level directory GitHub puts in source tarballs.
func extractTarGz(sys System, data []byte, dest string) error {
	gz, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return err
	}
	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
		_, rel, found := strings.Cut(hdr.Name, "/")
		if !found || rel == "" {
			continue
		}
		target, err := safeJoin(dest, rel)
		if err != nil {
			return err
		}
		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := sys.MkdirAll(target, 0o755); err != nil {
				return err
			}
		case tar.TypeReg:
			content, err := io.ReadAll(tr)
			if err != nil {
				return err
			}
			if err := sys.WriteFile(target, content, fs.FileMode(hdr.Mode).Perm()); err != nil {
				return err
			}
		}
	}
}

// safeJoin joins rel under dest, rejecting paths that escape it.
func safeJoin(dest, rel string) (string, error) {
	p := filepath.Join(dest, rel)
	if !strings.HasPrefix(p, dest+string(filepath.Separator)) {
		return "", fmt.Errorf("unsafe path in archive: %s", rel)
	}
	return p, nil
}
```

`internal/shellsetup/fontbackend.go`:

```go
package shellsetup

import (
	"archive/zip"
	"bytes"
	"context"
	"fmt"
	"io"
	"path/filepath"
	"strings"
)

// fontBackend installs the .ttf files of a GitHub release zip into
// Install.Dest and refreshes the font cache.
type fontBackend struct{}

func (fontBackend) Install(ctx context.Context, env Env, t Tool) error {
	return installFont(ctx, env, t, false)
}

func (fontBackend) Update(ctx context.Context, env Env, t Tool) error {
	return installFont(ctx, env, t, true)
}

func installFont(ctx context.Context, env Env, t Tool, skipIfCurrent bool) error {
	tag, err := latestTag(ctx, env.Fetcher, t.Install.Repo)
	if err != nil {
		return err
	}
	if skipIfCurrent && env.State.Versions[t.ID] == tag {
		return nil
	}
	data, err := env.Fetcher.Fetch(ctx, fmt.Sprintf("https://github.com/%s/releases/download/%s/%s", t.Install.Repo, tag, t.Install.Asset))
	if err != nil {
		return err
	}
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return fmt.Errorf("reading %s: %w", t.Install.Asset, err)
	}
	dest := env.Paths.Expand(t.Install.Dest)
	if err := env.System.RemoveAll(dest); err != nil {
		return err
	}
	fonts := 0
	for _, f := range zr.File {
		if f.FileInfo().IsDir() || !strings.EqualFold(filepath.Ext(f.Name), ".ttf") {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return err
		}
		content, err := io.ReadAll(rc)
		_ = rc.Close()
		if err != nil {
			return err
		}
		if err := env.System.WriteFile(filepath.Join(dest, filepath.Base(f.Name)), content, 0o644); err != nil {
			return err
		}
		fonts++
	}
	if fonts == 0 {
		return fmt.Errorf("%s contains no .ttf fonts", t.Install.Asset)
	}
	if _, err := env.System.Run(ctx, Cmd{Name: "fc-cache", Args: []string{"-f", dest}}); err != nil {
		return err
	}
	env.State.Versions[t.ID] = tag
	return nil
}
```

- [ ] **Step 4: Ejecutar los tests**

Run: `go test ./internal/shellsetup/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add internal/shellsetup
git commit -m "Add archive and font backends (antidote, Nerd Font)"
```

---

### Task 13: Composición del `.zshrc` (`shellrc.go`)

**Files:**
- Create: `internal/shellsetup/shellrc.go`, `internal/shellsetup/shellrc_test.go`, `internal/shellsetup/testdata/TestShellConfigGolden.golden` (generado)

**Interfaces:**
- Consumes: `Catalog.File`, `Catalog.Get`, `Paths`, `fileWriter` y `FileReport` (Tasks 8–10).
- Produces: `shellWriter{sys System; catalog *Catalog; paths Paths; files fileWriter}` con `apply(okTools []Tool, force bool) ([]FileReport, error)`. `apply` hace lo siguiente:
  - Crea los directorios `~/.config/zsh/*.d`.
  - Escribe el stub, el `zshrc` generado y los fragmentos de perfil.
  - Escribe `zsh.d/NN-<id>.zsh` y los `files` de cada herramienta de `okTools`.
  - Borra los fragmentos gestionados de herramientas que ya no están en el catálogo. Conserva los fragmentos de herramientas que sí están en el catálogo pero fallaron en esta ejecución.

- [ ] **Step 1: Escribir el test que falla**

`internal/shellsetup/shellrc_test.go`:

```go
package shellsetup

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/charmbracelet/x/exp/golden"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newShellWriter(t *testing.T) shellWriter {
	t.Helper()
	sys, _ := newTestSystem(t)
	cat, err := DefaultCatalog()
	require.NoError(t, err)
	st := &State{Files: map[string]string{}, Versions: map[string]string{}}
	return shellWriter{
		sys:     sys,
		catalog: cat,
		paths:   NewPaths(sys.HomeDir()),
		files:   fileWriter{sys: sys, state: st, now: func() time.Time { return fixedNow }},
	}
}

func catalogTools(t *testing.T, w shellWriter, ids ...string) []Tool {
	t.Helper()
	var tools []Tool
	for _, id := range ids {
		tool, ok := w.catalog.Get(id)
		require.True(t, ok, id)
		tools = append(tools, tool)
	}
	return tools
}

func zshdNames(t *testing.T, w shellWriter) []string {
	t.Helper()
	paths, err := filepath.Glob(filepath.Join(w.paths.ZshD, "*.zsh"))
	require.NoError(t, err)
	names := make([]string, len(paths))
	for i, p := range paths {
		names[i] = filepath.Base(p)
	}
	return names
}

func TestApplyWritesProfileAndFragments(t *testing.T) {
	w := newShellWriter(t)

	reports, err := w.apply(catalogTools(t, w, "mise", "starship", "zoxide"), false)
	require.NoError(t, err)

	assert.Equal(t, []string{"10-mise.zsh", "20-core.zsh", "50-starship.zsh", "60-zoxide.zsh", "70-aliases.zsh"}, zshdNames(t, w))
	assert.Equal(t, "# managed by shell-setup (tool: zoxide)\neval \"$(zoxide init zsh)\"\nalias cd=\"z\"\n",
		read(t, filepath.Join(w.paths.ZshD, "60-zoxide.zsh")))
	assert.Contains(t, read(t, w.paths.Stub), `source "$HOME/.config/shell-setup/zshrc"`)
	assert.FileExists(t, filepath.Join(w.paths.Home, ".config", "starship.toml"))
	for _, d := range []string{"env.d", "functions.d", "aliases.d", "custom.d"} {
		assert.DirExists(t, filepath.Join(w.paths.UserZshDir, d))
	}
	assert.Len(t, reports, 8) // stub, zshrc, 5 fragments, starship.toml
	for _, r := range reports {
		assert.Equal(t, ResultOK, r.Result, r.Path)
	}
}

func TestApplyBacksUpUnmanagedZshrc(t *testing.T) {
	w := newShellWriter(t)
	require.NoError(t, os.WriteFile(w.paths.Stub, []byte("# my old zshrc\n"), 0o644))

	_, err := w.apply(nil, false)
	require.NoError(t, err)

	assert.Equal(t, "# my old zshrc\n", read(t, w.paths.Stub+backupSuffix))
	assert.Contains(t, read(t, w.paths.Stub), "managed by shell-setup")
}

func TestApplyTwiceIsIdempotent(t *testing.T) {
	w := newShellWriter(t)
	tools := catalogTools(t, w, "mise", "zoxide")
	_, err := w.apply(tools, false)
	require.NoError(t, err)

	reports, err := w.apply(tools, false)
	require.NoError(t, err)
	for _, r := range reports {
		assert.Equal(t, ResultOK, r.Result, r.Path)
	}
	backups, err := filepath.Glob(filepath.Join(w.paths.Home, "*.bak.*"))
	require.NoError(t, err)
	assert.Empty(t, backups)
}

func TestApplyRemovesOnlyFragmentsOfRemovedTools(t *testing.T) {
	w := newShellWriter(t)
	gone := filepath.Join(w.paths.ZshD, "42-gone.zsh")         // managed, tool no longer in catalog
	failed := filepath.Join(w.paths.ZshD, "50-starship.zsh")   // managed, tool failed this run
	mine := filepath.Join(w.paths.ZshD, "99-mine.zsh")         // not managed
	for _, p := range []string{gone, failed} {
		_, err := w.files.write(p, []byte("# old\n"), false)
		require.NoError(t, err)
	}
	require.NoError(t, os.WriteFile(mine, []byte("# mine\n"), 0o644))

	reports, err := w.apply(nil, false)
	require.NoError(t, err)

	assert.NoFileExists(t, gone)
	assert.FileExists(t, failed)
	assert.FileExists(t, mine)
	assert.Contains(t, reports, FileReport{Path: gone, Result: ResultOK})
}

func TestShellConfigGolden(t *testing.T) {
	w := newShellWriter(t)
	_, err := w.apply(catalogTools(t, w, "mise", "antidote", "starship", "fzf", "zoxide"), false)
	require.NoError(t, err)

	var b strings.Builder
	files := append([]string{w.paths.Stub, w.paths.GeneratedZshrc}, globAll(t, w.paths.ZshD)...)
	for _, p := range files {
		b.WriteString("== " + strings.TrimPrefix(p, w.paths.Home) + " ==\n")
		b.WriteString(read(t, p))
	}
	golden.RequireEqual(t, []byte(b.String()))
}

func TestShellConfigIsValidZsh(t *testing.T) {
	path, err := lookSystemZsh()
	if err != nil {
		t.Skip("zsh not installed")
	}
	w := newShellWriter(t)
	_, err = w.apply(catalogTools(t, w, "mise", "antidote", "starship", "fzf", "zoxide"), false)
	require.NoError(t, err)
	for _, p := range append([]string{w.paths.Stub, w.paths.GeneratedZshrc}, globAll(t, w.paths.ZshD)...) {
		out, err := runZshSyntaxCheck(path, p)
		assert.NoError(t, err, "%s: %s", p, out)
	}
}

func globAll(t *testing.T, dir string) []string {
	t.Helper()
	paths, err := filepath.Glob(filepath.Join(dir, "*.zsh"))
	require.NoError(t, err)
	return paths
}
```

Y en `helpers_test.go` añade los helpers del chequeo de sintaxis (incluye `os/exec` en los imports):

```go
func lookSystemZsh() (string, error) { return exec.LookPath("zsh") }

func runZshSyntaxCheck(zsh, file string) (string, error) {
	out, err := exec.Command(zsh, "-n", file).CombinedOutput()
	return string(out), err
}
```

- [ ] **Step 2: Ejecutarlo para verificar que falla**

Run: `go test ./internal/shellsetup/ -run 'Apply|ShellConfig'`
Expected: FAIL, `undefined: shellWriter`

- [ ] **Step 3: Implementación**

`internal/shellsetup/shellrc.go`:

```go
package shellsetup

import (
	"fmt"
	"maps"
	"path/filepath"
	"slices"
	"strings"
)

var (
	profileFragments = []string{"20-core.zsh", "70-aliases.zsh"}
	userZshDirs      = []string{"env.d", "functions.d", "aliases.d", "custom.d"}
)

// shellWriter writes the managed zsh config: the ~/.zshrc stub, the
// generated zshrc, profile fragments and one zsh.d fragment per tool.
type shellWriter struct {
	sys     System
	catalog *Catalog
	paths   Paths
	files   fileWriter
}

// apply writes the config for okTools (the tools that ended OK this run).
func (w shellWriter) apply(okTools []Tool, force bool) ([]FileReport, error) {
	for _, d := range userZshDirs {
		if err := w.sys.MkdirAll(filepath.Join(w.paths.UserZshDir, d), 0o755); err != nil {
			return nil, err
		}
	}
	desired, err := w.desired(okTools)
	if err != nil {
		return nil, err
	}
	var reports []FileReport
	for _, path := range slices.Sorted(maps.Keys(desired)) {
		res, err := w.files.write(path, desired[path], force)
		if err != nil {
			return reports, fmt.Errorf("writing %s: %w", path, err)
		}
		reports = append(reports, FileReport{Path: path, Result: res})
	}
	orphans, err := w.orphans(desired)
	if err != nil {
		return reports, err
	}
	for _, path := range orphans {
		res, err := w.files.remove(path)
		if err != nil {
			return reports, fmt.Errorf("removing %s: %w", path, err)
		}
		reports = append(reports, FileReport{Path: path, Result: res})
	}
	return reports, nil
}

func (w shellWriter) desired(okTools []Tool) (map[string][]byte, error) {
	desired := map[string][]byte{}
	embed := func(dest, src string) error {
		data, err := w.catalog.File(src)
		if err != nil {
			return err
		}
		desired[dest] = data
		return nil
	}
	if err := embed(w.paths.Stub, "files/profile/zshrc-stub"); err != nil {
		return nil, err
	}
	if err := embed(w.paths.GeneratedZshrc, "files/profile/zshrc"); err != nil {
		return nil, err
	}
	for _, name := range profileFragments {
		if err := embed(filepath.Join(w.paths.ZshD, name), "files/profile/"+name); err != nil {
			return nil, err
		}
	}
	for _, t := range okTools {
		if t.Shell != nil {
			name := fmt.Sprintf("%02d-%s.zsh", t.Shell.Priority, t.ID)
			desired[filepath.Join(w.paths.ZshD, name)] = []byte(
				fmt.Sprintf("# managed by shell-setup (tool: %s)\n%s\n", t.ID, strings.TrimRight(t.Shell.Snippet, "\n")))
		}
		for _, f := range t.Files {
			if err := embed(w.paths.Expand(f.Dest), f.Src); err != nil {
				return nil, err
			}
		}
	}
	return desired, nil
}

// orphans are managed zsh.d fragments of tools no longer in the catalog.
// Fragments of catalog tools that failed this run are kept as they were.
func (w shellWriter) orphans(desired map[string][]byte) ([]string, error) {
	existing, err := w.sys.Glob(filepath.Join(w.paths.ZshD, "*.zsh"))
	if err != nil {
		return nil, err
	}
	var out []string
	for _, path := range existing {
		if _, wanted := desired[path]; wanted {
			continue
		}
		if _, managed := w.files.state.Files[path]; !managed {
			continue
		}
		name := filepath.Base(path)
		if slices.Contains(profileFragments, name) {
			continue
		}
		_, id, _ := strings.Cut(strings.TrimSuffix(name, ".zsh"), "-")
		if _, inCatalog := w.catalog.Get(id); inCatalog {
			continue
		}
		out = append(out, path)
	}
	return out, nil
}
```

- [ ] **Step 4: Generar el golden y ejecutar los tests**

Run: `go test ./internal/shellsetup/ -run TestShellConfigGolden -update && go test ./internal/shellsetup/...`
Expected: PASS. Revisa `internal/shellsetup/testdata/TestShellConfigGolden.golden`. Debe contener, en este orden:
1. el stub;
2. el `zshrc` generado;
3. `10-mise`, `20-core`, `30-antidote`, `50-starship`, `60-fzf`, `60-zoxide` y `70-aliases`.

`mise activate` (10) debe ir antes que `starship`, `fzf` y `zoxide`. Esto corrige el bug de orden del zshrc actual.

- [ ] **Step 5: Commit**

```bash
git add internal/shellsetup
git commit -m "Compose zsh config from profile + per-tool zsh.d fragments"
```

---

### Task 14: Engine: `Init` y `Update`

**Files:**
- Create: `internal/shellsetup/shellsetup.go`, `internal/shellsetup/engine_test.go`

**Interfaces:**
- Consumes: todo lo de las Tasks 8–13.
- Produces:
  - `Engine{System; Fetcher; Catalog *Catalog; Backends map[string]Backend; Paths Paths; Sudo []string; OSRelease string; Now func() time.Time}`.
  - `NewEngine(sys System, fetcher Fetcher) (*Engine, error)`.
  - `(*Engine).Init(ctx, chan<- Event) (Report, error)`.
  - `(*Engine).Update(ctx, UpdateOptions, chan<- Event) (Report, error)`, con `UpdateOptions{Force bool}`.
  - Uso interno: `(*Engine).checkTool(ctx, Tool, *State) toolStatus` y `(*Engine).loginShell(ctx) string`, que la Task 15 reutiliza.
- Contrato del canal: el Engine **cierra** `events` al terminar y envía de forma bloqueante, así que el llamante debe vaciarlo hasta que se cierre (o pasar un canal con buffer suficiente).

- [ ] **Step 1: Escribir los tests que fallan**

`internal/shellsetup/engine_test.go`:

```go
package shellsetup

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testOSRelease = "ID=ubuntu\nID_LIKE=debian\nPRETTY_NAME=\"Ubuntu 24.04\"\n"

// fakeBackend records calls; a successful call makes the tool's check pass.
type fakeBackend struct {
	rec      *recorder
	calls    []string
	failures map[string]error
}

func (b *fakeBackend) Install(_ context.Context, _ Env, t Tool) error { return b.do("install", t) }
func (b *fakeBackend) Update(_ context.Context, _ Env, t Tool) error  { return b.do("update", t) }

func (b *fakeBackend) do(action string, t Tool) error {
	b.calls = append(b.calls, action+" "+t.ID)
	if err := b.failures[t.ID]; err != nil {
		return err
	}
	b.rec.setFail(strings.Join(t.Check.Cmd, " "), nil)
	return nil
}

func fakeTool(id string, kind Kind, extra string) string {
	return fmt.Sprintf("id = %q\nkind = %q\n%s\n[install]\nbackend = \"fake\"\n[check]\ncmd = [%q, \"--version\"]\n",
		id, kind, extra, id)
}

// newTestEngine builds an Engine over a temp HOME with the given manifests
// (all tools start missing), the real profile files, and fake commands.
func newTestEngine(t *testing.T, manifests map[string]string) (*Engine, *recorder, *fakeBackend) {
	t.Helper()
	sys, rec := newTestSystem(t)

	fsys := fstest.MapFS{}
	registry, err := fs.Sub(registryFS, "registry")
	require.NoError(t, err)
	for _, name := range []string{"zshrc", "zshrc-stub", "20-core.zsh", "70-aliases.zsh"} {
		data, err := fs.ReadFile(registry, "files/profile/"+name)
		require.NoError(t, err)
		fsys["files/profile/"+name] = &fstest.MapFile{Data: data}
	}
	for id, m := range manifests {
		fsys[id+".toml"] = &fstest.MapFile{Data: []byte(m)}
		rec.setFail(id+" --version", errExit)
	}
	cat, err := LoadCatalog(fsys)
	require.NoError(t, err)

	osRelease := filepath.Join(t.TempDir(), "os-release")
	require.NoError(t, os.WriteFile(osRelease, []byte(testOSRelease), 0o644))

	t.Setenv("USER", "tester")
	rec.out["getent passwd tester"] = "tester:x:1000:1000::/home/tester:/usr/bin/zsh"
	writeExecutable(t, filepath.Join(sys.HomeDir(), ".local", "bin", "zsh"))

	backend := &fakeBackend{rec: rec, failures: map[string]error{}}
	paths := NewPaths(sys.HomeDir())
	paths.Legacy = []string{filepath.Join(sys.HomeDir(), ".local", "bin", "starship")}
	e := &Engine{
		System:    sys,
		Fetcher:   &fakeFetcher{},
		Catalog:   cat,
		Backends:  map[string]Backend{"fake": backend, "apt": aptBackend{}},
		Paths:     paths,
		Sudo:      []string{"sudo"},
		OSRelease: osRelease,
		Now:       func() time.Time { return fixedNow },
	}
	return e, rec, backend
}

func runOp(t *testing.T, op func(chan<- Event) (Report, error)) (Report, []Event, error) {
	t.Helper()
	events := make(chan Event, 256)
	rep, err := op(events)
	var got []Event
	for ev := range events { // the engine closed it
		got = append(got, ev)
	}
	return rep, got, err
}

func initOp(e *Engine) func(chan<- Event) (Report, error) {
	return func(ch chan<- Event) (Report, error) { return e.Init(context.Background(), ch) }
}

func results(rep Report) map[string]Result {
	m := map[string]Result{}
	for _, tr := range rep.Tools {
		m[tr.ID] = tr.Result
	}
	return m
}

func TestInitInstallsMissingToolsInDependencyOrder(t *testing.T) {
	e, _, backend := newTestEngine(t, map[string]string{
		"a": fakeTool("a", KindBuiltin, ""),
		"b": fakeTool("b", KindPlugin, `depends = ["a"]`),
	})

	rep, events, err := runOp(t, initOp(e))
	require.NoError(t, err)

	assert.Equal(t, []string{"install a", "install b"}, backend.calls)
	assert.Equal(t, map[string]Result{"a": ResultOK, "b": ResultOK}, results(rep))
	var started []string
	for _, ev := range events {
		if s, ok := ev.(ToolStarted); ok {
			started = append(started, s.ID)
		}
	}
	assert.Equal(t, []string{"a", "b"}, started)
	assert.Equal(t, PhaseStarted{Phase: PhasePreflight}, events[0])
	assert.FileExists(t, e.Paths.Stub)
	assert.FileExists(t, e.Paths.StateFile)
}

func TestInitIsIdempotent(t *testing.T) {
	e, rec, backend := newTestEngine(t, map[string]string{
		"a": fakeTool("a", KindBuiltin, `system_packages = ["git"]`),
	})
	rec.out["dpkg-query -W -f=${Status} git"] = "install ok installed"
	_, _, err := runOp(t, initOp(e))
	require.NoError(t, err)
	before := len(rec.commands())

	rep, _, err := runOp(t, initOp(e))
	require.NoError(t, err)

	assert.Equal(t, []string{"install a"}, backend.calls, "nothing reinstalled")
	for _, c := range rec.commands()[before:] {
		assert.NotContains(t, c, "sudo", "no privileged command on re-run")
		assert.NotContains(t, c, "chsh")
	}
	for _, f := range rep.Files {
		assert.Equal(t, ResultOK, f.Result, f.Path)
	}
	backups, _ := filepath.Glob(filepath.Join(e.Paths.Home, "*.bak.*"))
	assert.Empty(t, backups)
}

func TestAptPreflightInstallsMissingPackagesWithSudo(t *testing.T) {
	e, rec, _ := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, `system_packages = ["git"]`)})

	_, _, err := runOp(t, initOp(e))
	require.NoError(t, err)

	assert.Subset(t, rec.commands(), []string{"sudo apt-get update -qq", "sudo apt-get install -y git"})
}

func TestAptPreflightWithoutSudoWhenRoot(t *testing.T) {
	e, rec, _ := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, `system_packages = ["git"]`)})
	e.Sudo = nil

	_, _, err := runOp(t, initOp(e))
	require.NoError(t, err)

	assert.Subset(t, rec.commands(), []string{"apt-get update -qq", "apt-get install -y git"})
	for _, c := range rec.commands() {
		assert.False(t, strings.HasPrefix(c, "sudo "), c)
	}
}

func TestAptFailureAbortsBeforeTools(t *testing.T) {
	e, rec, backend := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, `system_packages = ["git"]`)})
	rec.setFail("sudo apt-get update -qq", errExit)

	_, _, err := runOp(t, initOp(e))
	assert.ErrorContains(t, err, "installing system packages")
	assert.Empty(t, backend.calls)
}

func TestUpdateUpdatesInstalledTools(t *testing.T) {
	e, rec, backend := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, "")})
	rec.setFail("a --version", nil)

	_, _, err := runOp(t, func(ch chan<- Event) (Report, error) {
		return e.Update(context.Background(), UpdateOptions{}, ch)
	})
	require.NoError(t, err)
	assert.Equal(t, []string{"update a"}, backend.calls)
}

func TestRequiredFailureSkipsDependentsButNotOthers(t *testing.T) {
	e, _, backend := newTestEngine(t, map[string]string{
		"a": fakeTool("a", KindBuiltin, ""),
		"b": fakeTool("b", KindPlugin, `depends = ["a"]`),
		"c": fakeTool("c", KindPlugin, ""),
	})
	backend.failures["a"] = errors.New("boom")

	rep, _, err := runOp(t, initOp(e))
	require.NoError(t, err)

	assert.Equal(t, map[string]Result{"a": ResultFailed, "b": ResultSkipped, "c": ResultOK}, results(rep))
	for _, tr := range rep.Tools {
		if tr.ID == "b" {
			assert.ErrorIs(t, tr.Err, ErrDependencyFailed)
		}
	}
	assert.True(t, rep.Failed())
}

func TestOptionalFailureIsAWarning(t *testing.T) {
	e, _, backend := newTestEngine(t, map[string]string{"c": fakeTool("c", KindPlugin, "optional = true")})
	backend.failures["c"] = errors.New("network down")

	rep, _, err := runOp(t, initOp(e))
	require.NoError(t, err)
	assert.Equal(t, map[string]Result{"c": ResultWarned}, results(rep))
	assert.False(t, rep.Failed())
}

func TestPostInstallRunsAfterInstall(t *testing.T) {
	e, rec, _ := newTestEngine(t, map[string]string{
		"a": fakeTool("a", KindBuiltin, `post_install = [["a", "settings", "set", "x", "true"]]`),
	})
	_, _, err := runOp(t, initOp(e))
	require.NoError(t, err)
	assert.Contains(t, rec.commands(), "a settings set x true")
}

func TestInitFailsWhenLocked(t *testing.T) {
	e, _, backend := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, "")})
	unlock, err := e.System.Lock(e.Paths.LockFile)
	require.NoError(t, err)
	defer unlock()

	_, _, err = runOp(t, initOp(e))
	assert.ErrorIs(t, err, ErrLocked)
	assert.Empty(t, backend.calls)
	assert.NoFileExists(t, e.Paths.Stub)
}

func TestUnsupportedOS(t *testing.T) {
	e, _, _ := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, "")})
	require.NoError(t, os.WriteFile(e.OSRelease, []byte("ID=fedora\nPRETTY_NAME=\"Fedora 41\"\n"), 0o644))

	_, _, err := runOp(t, initOp(e))
	assert.ErrorContains(t, err, "Debian/Ubuntu")
}

func TestChangesDefaultShellWhenNotZsh(t *testing.T) {
	e, rec, _ := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, "")})
	rec.out["getent passwd tester"] = "tester:x:1000:1000::/home/tester:/bin/bash"

	_, _, err := runOp(t, initOp(e))
	require.NoError(t, err)

	zsh := filepath.Join(e.Paths.Home, ".local", "bin", "zsh")
	assert.Contains(t, rec.commands(), "chsh -s "+zsh)
}

func TestChshFallsBackToSudo(t *testing.T) {
	e, rec, _ := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, "")})
	rec.out["getent passwd tester"] = "tester:x:1000:1000::/home/tester:/bin/bash"
	zsh := filepath.Join(e.Paths.Home, ".local", "bin", "zsh")
	rec.setFail("chsh -s "+zsh, errExit)

	_, _, err := runOp(t, initOp(e))
	require.NoError(t, err)
	assert.Contains(t, rec.commands(), "sudo chsh -s "+zsh+" tester")
}

func TestNewEngineLoadsEmbeddedCatalog(t *testing.T) {
	sys, _ := newTestSystem(t)
	e, err := NewEngine(sys, &fakeFetcher{})
	require.NoError(t, err, "the embedded catalog only uses known backends")
	assert.Len(t, e.Catalog.Tools(), 11)
}
```

- [ ] **Step 2: Ejecutarlos para verificar que fallan**

Run: `go test ./internal/shellsetup/ -run 'Init|Apt|Update|Failure|PostInstall|Locked|OS|Shell|Chsh|NewEngine'`
Expected: FAIL, `undefined: Engine`

- [ ] **Step 3: Implementación**

`internal/shellsetup/shellsetup.go`:

```go
package shellsetup

import (
	"context"
	"fmt"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

// UpdateOptions tune Update.
type UpdateOptions struct {
	// Force overwrites managed files edited by hand (after a backup).
	Force bool
}

// Engine runs the shell-setup operations.
type Engine struct {
	System   System
	Fetcher  Fetcher
	Catalog  *Catalog
	Backends map[string]Backend
	Paths    Paths
	// Sudo prefixes privileged commands; nil when already running as root.
	Sudo      []string
	OSRelease string
	Now       func() time.Time
}

// NewEngine returns an Engine over the embedded catalog.
func NewEngine(sys System, fetcher Fetcher) (*Engine, error) {
	cat, err := DefaultCatalog()
	if err != nil {
		return nil, err
	}
	e := &Engine{
		System:    sys,
		Fetcher:   fetcher,
		Catalog:   cat,
		Backends:  DefaultBackends(),
		Paths:     NewPaths(sys.HomeDir()),
		Sudo:      []string{"sudo"},
		OSRelease: "/etc/os-release",
		Now:       time.Now,
	}
	for _, t := range cat.Tools() {
		if _, ok := e.Backends[t.Install.Backend]; !ok {
			return nil, fmt.Errorf("tool %s: unknown backend %q", t.ID, t.Install.Backend)
		}
	}
	return e, nil
}

// Init installs what is missing and writes the shell config. It does not
// update tools that are already installed.
func (e *Engine) Init(ctx context.Context, events chan<- Event) (Report, error) {
	return e.apply(ctx, modeInit, false, events)
}

// Update is Init plus updating every installed tool.
func (e *Engine) Update(ctx context.Context, opts UpdateOptions, events chan<- Event) (Report, error) {
	return e.apply(ctx, modeUpdate, opts.Force, events)
}

type mode int

const (
	modeInit mode = iota
	modeUpdate
)

func (e *Engine) apply(ctx context.Context, m mode, force bool, events chan<- Event) (rep Report, err error) {
	defer close(events)

	events <- PhaseStarted{Phase: PhasePreflight}
	if err := e.checkOS(); err != nil {
		return rep, err
	}
	unlock, err := e.System.Lock(e.Paths.LockFile)
	if err != nil {
		return rep, err
	}
	defer unlock()
	state, err := LoadState(e.System, e.Paths.StateFile)
	if err != nil {
		return rep, err
	}
	defer func() {
		if saveErr := state.Save(e.System, e.Paths.StateFile); saveErr != nil && err == nil {
			err = saveErr
		}
	}()
	tools := e.Catalog.Tools()
	if err := e.ensureAptPackages(ctx, aptPackages(tools), m == modeUpdate); err != nil {
		return rep, fmt.Errorf("installing system packages: %w", err)
	}

	events <- PhaseStarted{Phase: PhaseTools}
	env := Env{System: e.System, Fetcher: e.Fetcher, Paths: e.Paths, State: state}
	blocked := map[string]bool{}
	var okTools []Tool
	for _, t := range tools {
		if err := ctx.Err(); err != nil {
			return rep, err
		}
		tr := e.applyTool(ctx, env, t, m, blocked, events)
		events <- ToolFinished{ID: tr.ID, Action: tr.Action, Result: tr.Result, Version: tr.Version, Err: tr.Err}
		rep.Tools = append(rep.Tools, tr)
		if tr.Result == ResultOK {
			okTools = append(okTools, t)
		} else {
			blocked[t.ID] = true
		}
	}

	events <- PhaseStarted{Phase: PhaseShell}
	w := shellWriter{
		sys:     e.System,
		catalog: e.Catalog,
		paths:   e.Paths,
		files:   fileWriter{sys: e.System, state: state, now: e.Now},
	}
	files, err := w.apply(okTools, force)
	for _, f := range files {
		events <- FileFinished{Path: f.Path, Result: f.Result}
	}
	rep.Files = files
	if err != nil {
		return rep, err
	}
	if err := e.ensureDefaultShell(ctx); err != nil {
		return rep, fmt.Errorf("changing the default shell: %w", err)
	}
	return rep, nil
}

func (e *Engine) applyTool(ctx context.Context, env Env, t Tool, m mode, blocked map[string]bool, events chan<- Event) ToolReport {
	tr := ToolReport{ID: t.ID, Optional: t.Optional}
	for _, dep := range t.Depends {
		if blocked[dep] {
			tr.Result = ResultSkipped
			tr.Err = fmt.Errorf("%w: %s", ErrDependencyFailed, dep)
			return tr
		}
	}
	st := e.checkTool(ctx, t, env.State)
	switch {
	case !st.Installed:
		tr.Action = ActionInstall
	case m == modeUpdate:
		tr.Action = ActionUpdate
	default:
		tr.Result, tr.Version = ResultOK, st.Version
		return tr
	}
	events <- ToolStarted{ID: t.ID, Action: tr.Action}
	err := e.runBackend(ctx, env, t, tr.Action)
	if err == nil {
		st = e.checkTool(ctx, t, env.State)
		if !st.Installed {
			err = fmt.Errorf("not detected after %s", tr.Action)
		}
	}
	if err != nil {
		tr.Result = ResultFailed
		if t.Optional {
			tr.Result = ResultWarned
		}
		tr.Err = fmt.Errorf("%s: %w", t.ID, err)
		return tr
	}
	tr.Result, tr.Version = ResultOK, st.Version
	return tr
}

func (e *Engine) runBackend(ctx context.Context, env Env, t Tool, action Action) error {
	b := e.Backends[t.Install.Backend]
	var err error
	if action == ActionInstall {
		err = b.Install(ctx, env, t)
	} else {
		err = b.Update(ctx, env, t)
	}
	if err != nil {
		return err
	}
	for _, argv := range t.PostInstall {
		if _, err := e.System.Run(ctx, Cmd{Name: argv[0], Args: argv[1:]}); err != nil {
			return err
		}
	}
	return nil
}

type toolStatus struct {
	Installed bool
	Version   string
}

func (e *Engine) checkTool(ctx context.Context, t Tool, state *State) toolStatus {
	if t.Check.Path != "" {
		if _, err := e.System.Stat(e.Paths.Expand(t.Check.Path)); err != nil {
			return toolStatus{}
		}
		return toolStatus{Installed: true, Version: state.Versions[t.ID]}
	}
	args := make([]string, 0, len(t.Check.Cmd)-1)
	for _, a := range t.Check.Cmd[1:] {
		args = append(args, e.Paths.Expand(a))
	}
	out, err := e.System.Run(ctx, Cmd{Name: t.Check.Cmd[0], Args: args})
	if err != nil {
		return toolStatus{}
	}
	first, _, _ := strings.Cut(strings.TrimSpace(string(out)), "\n")
	return toolStatus{Installed: true, Version: first}
}

func (e *Engine) ensureAptPackages(ctx context.Context, pkgs []string, upgrade bool) error {
	targets := missingAptPackages(ctx, e.System, pkgs)
	if upgrade {
		targets = pkgs
	}
	if len(targets) == 0 {
		return nil
	}
	if _, err := e.System.Run(ctx, e.privileged("apt-get", "update", "-qq")); err != nil {
		return err
	}
	_, err := e.System.Run(ctx, e.privileged("apt-get", append([]string{"install", "-y"}, targets...)...))
	return err
}

// privileged builds an interactive command run through sudo (unless root).
func (e *Engine) privileged(name string, args ...string) Cmd {
	if len(e.Sudo) == 0 {
		return Cmd{Name: name, Args: args, Interactive: true}
	}
	full := append(append(slices.Clone(e.Sudo[1:]), name), args...)
	return Cmd{Name: e.Sudo[0], Args: full, Interactive: true}
}

func (e *Engine) checkOS() error {
	data, err := e.System.ReadFile(e.OSRelease)
	if err != nil {
		return fmt.Errorf("cannot detect the OS (%s): %w", e.OSRelease, err)
	}
	vals := map[string]string{}
	for _, line := range strings.Split(string(data), "\n") {
		if k, v, ok := strings.Cut(strings.TrimSpace(line), "="); ok {
			vals[k] = strings.Trim(v, `"`)
		}
	}
	for _, id := range append([]string{vals["ID"]}, strings.Fields(vals["ID_LIKE"])...) {
		if id == "debian" || id == "ubuntu" {
			return nil
		}
	}
	return fmt.Errorf("unsupported OS %q: shell-setup supports Debian/Ubuntu only", vals["PRETTY_NAME"])
}

// loginShell is the user's login shell from the passwd database ($SHELL
// only reflects it after the next login).
func (e *Engine) loginShell(ctx context.Context) string {
	out, err := e.System.Run(ctx, Cmd{Name: "getent", Args: []string{"passwd", e.System.Getenv("USER")}})
	if err == nil {
		if fields := strings.Split(strings.TrimSpace(string(out)), ":"); len(fields) >= 7 {
			return fields[6]
		}
	}
	return e.System.Getenv("SHELL")
}

func (e *Engine) ensureDefaultShell(ctx context.Context) error {
	if filepath.Base(e.loginShell(ctx)) == "zsh" {
		return nil
	}
	zsh, err := e.System.LookPath("zsh")
	if err != nil {
		return err
	}
	if _, err := e.System.Run(ctx, Cmd{Name: "chsh", Args: []string{"-s", zsh}, Interactive: true}); err == nil {
		return nil
	}
	// chsh fails on accounts without a password (SSH-key-only); retry as root.
	_, err = e.System.Run(ctx, e.privileged("chsh", "-s", zsh, e.System.Getenv("USER")))
	return err
}
```

- [ ] **Step 4: Ejecutar los tests**

Run: `go test ./internal/shellsetup/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add internal/shellsetup
git commit -m "Add Engine: preflight, tool lifecycle, shell config, default shell"
```

---

### Task 15: `Doctor`

**Files:**
- Create: `internal/shellsetup/doctor.go`, `internal/shellsetup/doctor_test.go`

**Interfaces:**
- Consumes: `Engine.checkTool`, `Engine.loginShell`, `LoadState` y `Paths.Legacy` (Tasks 8–14).
- Produces: `(*Engine).Doctor(ctx) (Report, error)`, que solo rellena `Report.Checks`, en este orden: una por herramienta del catálogo, una por archivo gestionado (ordenados), `default shell` y los binarios heredados. Es de solo lectura: no toma el lock ni escribe nada.

- [ ] **Step 1: Escribir el test que falla**

`internal/shellsetup/doctor_test.go`:

```go
package shellsetup

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func checksByName(rep Report) map[string]CheckResult {
	m := map[string]CheckResult{}
	for _, c := range rep.Checks {
		m[c.Name] = c
	}
	return m
}

func TestDoctorReportsTools(t *testing.T) {
	e, rec, _ := newTestEngine(t, map[string]string{
		"a": fakeTool("a", KindBuiltin, ""),
		"b": fakeTool("b", KindPlugin, "optional = true"),
		"c": fakeTool("c", KindPlugin, ""),
	})
	rec.setFail("a --version", nil)
	rec.out["a --version"] = "a 1.2.3\nextra"

	rep, err := e.Doctor(context.Background())
	require.NoError(t, err)

	checks := checksByName(rep)
	assert.Equal(t, CheckResult{Name: "a", Status: CheckOK, Detail: "a 1.2.3"}, checks["a"])
	assert.Equal(t, CheckWarn, checks["b"].Status)
	assert.Equal(t, CheckFail, checks["c"].Status)
	assert.Equal(t, CheckOK, checks["default shell"].Status)
	assert.True(t, rep.Failed())
}

func TestDoctorFlagsModifiedAndMissingManagedFiles(t *testing.T) {
	e, _, _ := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, "")})
	_, _, err := runOp(t, initOp(e))
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(e.Paths.Stub, []byte("hand edit"), 0o644))
	require.NoError(t, os.Remove(e.Paths.GeneratedZshrc))

	rep, err := e.Doctor(context.Background())
	require.NoError(t, err)

	checks := checksByName(rep)
	assert.Equal(t, CheckWarn, checks[e.Paths.Stub].Status)
	assert.Contains(t, checks[e.Paths.Stub].Detail, "modified")
	assert.Equal(t, CheckWarn, checks[e.Paths.GeneratedZshrc].Status)
	assert.Contains(t, checks[e.Paths.GeneratedZshrc].Detail, "missing")
	assert.Equal(t, CheckOK, checks[filepath.Join(e.Paths.ZshD, "20-core.zsh")].Status)
}

func TestDoctorWarnsAboutLoginShellAndLegacyBinaries(t *testing.T) {
	e, rec, _ := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, "")})
	rec.out["getent passwd tester"] = "tester:x:1000:1000::/home/tester:/bin/bash"
	writeExecutable(t, e.Paths.Legacy[0])

	rep, err := e.Doctor(context.Background())
	require.NoError(t, err)

	checks := checksByName(rep)
	assert.Equal(t, CheckWarn, checks["default shell"].Status)
	assert.Equal(t, CheckWarn, checks[e.Paths.Legacy[0]].Status)
}

func TestDoctorDoesNotWrite(t *testing.T) {
	e, _, _ := newTestEngine(t, map[string]string{"a": fakeTool("a", KindBuiltin, "")})
	_, err := e.Doctor(context.Background())
	require.NoError(t, err)
	assert.NoFileExists(t, e.Paths.StateFile)
	assert.NoFileExists(t, e.Paths.LockFile)
}
```

- [ ] **Step 2: Ejecutarlo para verificar que falla**

Run: `go test ./internal/shellsetup/ -run Doctor`
Expected: FAIL, `e.Doctor undefined`

- [ ] **Step 3: Implementación**

`internal/shellsetup/doctor.go`:

```go
package shellsetup

import (
	"context"
	"maps"
	"path/filepath"
	"slices"
)

// Doctor checks the machine without changing anything.
func (e *Engine) Doctor(ctx context.Context) (Report, error) {
	state, err := LoadState(e.System, e.Paths.StateFile)
	if err != nil {
		return Report{}, err
	}
	var rep Report
	for _, t := range e.Catalog.Tools() {
		st := e.checkTool(ctx, t, state)
		c := CheckResult{Name: t.ID, Status: CheckOK, Detail: st.Version}
		if !st.Installed {
			c.Status, c.Detail = CheckFail, "not installed"
			if t.Optional {
				c.Status = CheckWarn
			}
		}
		rep.Checks = append(rep.Checks, c)
	}
	for _, path := range slices.Sorted(maps.Keys(state.Files)) {
		c := CheckResult{Name: path, Status: CheckOK}
		data, err := e.System.ReadFile(path)
		switch {
		case err != nil:
			c.Status, c.Detail = CheckWarn, "missing (run shell-setup update)"
		case hashBytes(data) != state.Files[path]:
			c.Status, c.Detail = CheckWarn, "modified by hand (update --force overwrites it)"
		}
		rep.Checks = append(rep.Checks, c)
	}
	shell := e.loginShell(ctx)
	sc := CheckResult{Name: "default shell", Status: CheckOK, Detail: shell}
	if filepath.Base(shell) != "zsh" {
		sc.Status, sc.Detail = CheckWarn, shell+" (run shell-setup init)"
	}
	rep.Checks = append(rep.Checks, sc)
	for _, p := range e.Paths.Legacy {
		if _, err := e.System.Stat(p); err == nil {
			rep.Checks = append(rep.Checks, CheckResult{
				Name: p, Status: CheckWarn,
				Detail: "installed by the old install.sh; the mise version takes precedence, you can remove it",
			})
		}
	}
	return rep, nil
}
```

- [ ] **Step 4: Ejecutar los tests**

Run: `go test ./internal/shellsetup/...`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add internal/shellsetup
git commit -m "Add Doctor: tools, managed files, login shell, legacy binaries"
```

---

### Task 16: `selfupdate`

**Files:**
- Create: `internal/selfupdate/selfupdate.go`, `internal/selfupdate/selfupdate_test.go`

**Interfaces:**
- Produces:
  - `var ErrDevBuild`.
  - `New(slug, current string) *Updater`.
  - `(*Updater).Latest(ctx) (latest string, newer bool, err error)`.
  - `(*Updater).Apply(ctx) (version string, updated bool, err error)`.

- [ ] **Step 1: Añadir la dependencia**

Run: `go get github.com/creativeprojects/go-selfupdate@v1.6.0`

- [ ] **Step 2: Escribir el test que falla**

`internal/selfupdate/selfupdate_test.go`:

```go
package selfupdate_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/BlasterM2A/shell-setup/internal/selfupdate"
)

func TestDevBuildCannotSelfUpdate(t *testing.T) {
	u := selfupdate.New("BlasterM2A/shell-setup", "dev")

	_, _, err := u.Latest(context.Background())
	assert.ErrorIs(t, err, selfupdate.ErrDevBuild)

	_, _, err = u.Apply(context.Background())
	assert.ErrorIs(t, err, selfupdate.ErrDevBuild)
}
```

Detectar la última release y reemplazar el binario necesita GitHub. Sin un servidor falso de releases no hay test unitario, así que eso se verifica a mano en la Task 19 (Step 8), después del primer release.

- [ ] **Step 3: Ejecutarlo para verificar que falla**

Run: `go test ./internal/selfupdate/...`
Expected: FAIL, el paquete no existe

- [ ] **Step 4: Implementación**

`internal/selfupdate/selfupdate.go`:

```go
// Package selfupdate replaces the running shell-setup binary with the
// latest GitHub release, verified against the release's checksums.txt.
package selfupdate

import (
	"context"
	"errors"
	"fmt"

	gsu "github.com/creativeprojects/go-selfupdate"
)

// ErrDevBuild is returned for builds without a release version.
var ErrDevBuild = errors.New("development build: self-update only works for released versions")

// Updater checks and applies updates for one GitHub repo.
type Updater struct {
	slug    string
	current string
}

// New returns an Updater for repo slug (owner/name) at version current.
func New(slug, current string) *Updater {
	return &Updater{slug: slug, current: current}
}

func (u *Updater) detect(ctx context.Context) (*gsu.Updater, *gsu.Release, error) {
	if u.current == "" || u.current == "dev" {
		return nil, nil, ErrDevBuild
	}
	up, err := gsu.NewUpdater(gsu.Config{Validator: &gsu.ChecksumValidator{UniqueFilename: "checksums.txt"}})
	if err != nil {
		return nil, nil, err
	}
	rel, found, err := up.DetectLatest(ctx, gsu.ParseSlug(u.slug))
	if err != nil {
		return nil, nil, err
	}
	if !found {
		return nil, nil, fmt.Errorf("no release of %s for this platform", u.slug)
	}
	return up, rel, nil
}

// Latest returns the latest released version and whether it is newer.
func (u *Updater) Latest(ctx context.Context) (string, bool, error) {
	_, rel, err := u.detect(ctx)
	if err != nil {
		return "", false, err
	}
	return rel.Version(), !rel.LessOrEqual(u.current), nil
}

// Apply installs the latest release over the running binary if newer.
func (u *Updater) Apply(ctx context.Context) (string, bool, error) {
	up, rel, err := u.detect(ctx)
	if err != nil {
		return "", false, err
	}
	if rel.LessOrEqual(u.current) {
		return u.current, false, nil
	}
	exe, err := gsu.ExecutablePath()
	if err != nil {
		return "", false, err
	}
	if err := up.UpdateTo(ctx, rel, exe); err != nil {
		return "", false, fmt.Errorf("replacing %s: %w", exe, err)
	}
	return rel.Version(), true, nil
}
```

- [ ] **Step 5: Ejecutar los tests**

Run: `go test ./internal/selfupdate/...`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add go.mod go.sum internal/selfupdate
git commit -m "Add selfupdate package (GitHub releases + checksum validation)"
```

---

### Task 17: Comandos: factory, bindings, progreso, `init`, `update`, `doctor` y `self-update`

**Files:**
- Create:
  - `internal/cmd/factory.go`
  - `internal/cmd/bindings.go`
  - `internal/cmd/runner.go`
  - `internal/cmd/apply.go`
  - `internal/cmd/init.go`
  - `internal/cmd/update.go`
  - `internal/cmd/doctor.go`
  - `internal/cmd/selfupdate.go`
  - `internal/cmd/bindings_test.go`
  - `internal/cmd/runner_test.go`
  - `internal/cmd/commands_test.go`
  - `internal/cmd/script_test.go`
  - `internal/cmd/testdata/scripts/version.txtar`
  - `internal/cmd/testdata/scripts/doctor.txtar`
- Modify: `internal/cmd/root.go` y `internal/cmd/root_test.go` (se reescriben enteros)

**Interfaces:**
- Consumes: todo lo anterior. En concreto:
  - `shellsetup`: `Engine.Init/Update/Doctor`, `Event`, `Report`, `NewRealSystem`, `HTTPFetcher`, `NewPaths` y los tipos de las Tasks 8–15.
  - UI: `steplist` (Task 4), `model.Progress/Done` (Task 4), `statustable` y `notice` (Task 3).
  - Paquetes transversales: `iostreams` (Task 5), `config` (Task 6), `log` (Task 7) y `selfupdate` (Task 16).
- Produces:
  - `NewFactory(*iostreams.IOStreams, home string) *Factory` y `NewRootCmd(*Factory) *cobra.Command`.
  - `Execute() int`.
  - `newXCmd(f, runF)` para init, update, doctor y self-update.

- [ ] **Step 1: Añadir las dependencias**

Run: `go get github.com/hashicorp/go-retryablehttp@v0.7.8 github.com/rogpeppe/go-internal@v1.15.0`

- [ ] **Step 2: Escribir los tests que fallan**

`internal/cmd/root_test.go` (sustituye el contenido completo del archivo):

```go
package cmd

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/BlasterM2A/shell-setup/internal/iostreams"
)

func newTestFactory(t *testing.T) (*Factory, *bytes.Buffer) {
	t.Helper()
	ios, out, _ := iostreams.Test()
	return NewFactory(ios, t.TempDir()), out
}

func TestRootVersion(t *testing.T) {
	f, _ := newTestFactory(t)
	root := NewRootCmd(f)
	var out bytes.Buffer
	root.SetOut(&out)
	root.SetArgs([]string{"--version"})

	require.NoError(t, root.Execute())
	assert.Equal(t, "shell-setup dev (none)\n", out.String())
}

func TestRootRegistersCommands(t *testing.T) {
	f, _ := newTestFactory(t)
	var names []string
	for _, c := range NewRootCmd(f).Commands() {
		names = append(names, c.Name())
	}
	assert.Subset(t, names, []string{"init", "update", "doctor", "self-update"})
}

func TestGlobalFlags(t *testing.T) {
	f, _ := newTestFactory(t)
	root := NewRootCmd(f)
	root.SetOut(&bytes.Buffer{})
	root.SetArgs([]string{"--plain", "--verbose", "--version"})

	require.NoError(t, root.Execute())
	assert.True(t, f.Plain)
	assert.True(t, f.Verbose)
}

func TestExitErrorMessage(t *testing.T) {
	assert.Equal(t, "exit status 3", (&ExitError{Code: 3}).Error())
}
```

`internal/cmd/commands_test.go`:

```go
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
```

`internal/cmd/bindings_test.go`:

```go
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
```

`internal/cmd/runner_test.go`:

```go
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
		tea.WithInput(nil), tea.WithOutput(&screen))
	require.NoError(t, err)
	assert.Len(t, res.Report.Tools, 1)
	assert.Contains(t, screen.String(), "SUMMARY")
}
```

`internal/cmd/script_test.go`:

```go
package cmd

import (
	"os"
	"testing"

	"github.com/rogpeppe/go-internal/testscript"
)

func TestMain(m *testing.M) {
	testscript.Main(m, map[string]func(){
		"shell-setup": func() { os.Exit(Execute()) },
	})
}

func TestScripts(t *testing.T) {
	testscript.Run(t, testscript.Params{Dir: "testdata/scripts"})
}
```

`internal/cmd/testdata/scripts/version.txtar`:

```
exec shell-setup --version
stdout '^shell-setup dev \(none\)$'
```

`internal/cmd/testdata/scripts/doctor.txtar`:

```
# A fresh HOME has nothing set up: doctor reports it and exits non-zero.
# Only read-only checks run; development builds skip the release check.
env HOME=$WORK/home
! exec shell-setup doctor --plain
stdout 'antidote +not installed'
stdout 'development build'
! stdout 'panic'
```

- [ ] **Step 3: Ejecutarlos para verificar que fallan**

Run: `go test ./internal/cmd/...`
Expected: FAIL, `undefined: NewFactory` y similares

- [ ] **Step 4: Implementar `factory.go` y reescribir `root.go`**

`internal/cmd/factory.go`:

```go
package cmd

import (
	"log/slog"
	"os"
	"sync"

	"github.com/hashicorp/go-retryablehttp"

	"github.com/BlasterM2A/shell-setup/internal/config"
	"github.com/BlasterM2A/shell-setup/internal/iostreams"
	applog "github.com/BlasterM2A/shell-setup/internal/log"
	"github.com/BlasterM2A/shell-setup/internal/selfupdate"
	"github.com/BlasterM2A/shell-setup/internal/shellsetup"
	"github.com/BlasterM2A/shell-setup/internal/ui/common"
)

// Factory builds dependencies lazily, after flags are parsed (gh pattern).
type Factory struct {
	IOStreams *iostreams.IOStreams
	Home      string

	// Global flags; set by cobra before any getter below is called.
	Plain, Verbose, Quiet bool

	Config  func() (config.Config, error)
	Logger  func() (*slog.Logger, error)
	System  func() (*shellsetup.RealSystem, error)
	Engine  func() (*shellsetup.Engine, error)
	Updater func() *selfupdate.Updater
}

// NewFactory returns the production factory.
func NewFactory(ios *iostreams.IOStreams, home string) *Factory {
	f := &Factory{IOStreams: ios, Home: home}
	f.Config = sync.OnceValues(func() (config.Config, error) {
		return config.Load(config.DefaultPath(home), nil)
	})
	f.Logger = sync.OnceValues(func() (*slog.Logger, error) {
		cfg, err := f.Config()
		if err != nil {
			return nil, err
		}
		var level slog.Level
		if err := level.UnmarshalText([]byte(cfg.LogLevel)); err != nil {
			return nil, err
		}
		if f.Verbose {
			level = slog.LevelDebug
		}
		if f.Quiet {
			level = slog.LevelError
		}
		opts := applog.Options{File: shellsetup.NewPaths(home).LogFile, Level: level, Styles: ios.Styles()}
		if !f.UseTUI() {
			opts.Console = ios.ErrOut
		}
		// The log file stays open for the life of the process.
		logger, _, err := applog.New(opts)
		return logger, err
	})
	f.System = sync.OnceValues(func() (*shellsetup.RealSystem, error) {
		logger, err := f.Logger()
		if err != nil {
			return nil, err
		}
		return shellsetup.NewRealSystem(home, logger), nil
	})
	f.Engine = sync.OnceValues(func() (*shellsetup.Engine, error) {
		sys, err := f.System()
		if err != nil {
			return nil, err
		}
		logger, err := f.Logger()
		if err != nil {
			return nil, err
		}
		client := retryablehttp.NewClient()
		client.RetryMax = 3
		client.Logger = logger
		e, err := shellsetup.NewEngine(sys, shellsetup.HTTPFetcher{
			Client: client.StandardClient(),
			Token:  os.Getenv("GITHUB_TOKEN"),
		})
		if err != nil {
			return nil, err
		}
		if os.Geteuid() == 0 {
			e.Sudo = nil
		}
		return e, nil
	})
	f.Updater = sync.OnceValue(func() *selfupdate.Updater { return selfupdate.New(repoSlug, version) })
	return f
}

// UseTUI reports whether to show the interactive UI.
func (f *Factory) UseTUI() bool { return !f.Plain && f.IOStreams.IsTTY() }

// Common is what UI components receive.
func (f *Factory) Common() common.Common { return common.New(f.IOStreams.Styles()) }
```

`internal/cmd/root.go` (sustituye el contenido completo del archivo):

```go
// Package cmd wires the cobra commands: it binds UI components to the
// shellsetup domain and holds no business logic of its own.
package cmd

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/spf13/cobra"

	"github.com/BlasterM2A/shell-setup/internal/iostreams"
	"github.com/BlasterM2A/shell-setup/internal/ui/notice"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
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

// NewRootCmd builds the command tree. Every command is listed here.
func NewRootCmd(f *Factory) *cobra.Command {
	root := &cobra.Command{
		Use:           "shell-setup",
		Short:         "Bootstrap and maintain your zsh environment",
		Version:       fmt.Sprintf("%s (%s)", version, commit),
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.SetVersionTemplate("shell-setup {{.Version}}\n")
	flags := root.PersistentFlags()
	flags.BoolVar(&f.Plain, "plain", false, "plain text output, no interactive UI")
	flags.BoolVarP(&f.Verbose, "verbose", "v", false, "log debug details")
	flags.BoolVarP(&f.Quiet, "quiet", "q", false, "only log errors")
	root.AddCommand(
		newInitCmd(f, nil),
		newUpdateCmd(f, nil),
		newDoctorCmd(f, nil),
		newSelfUpdateCmd(f, nil),
	)
	return root
}

// Execute runs the CLI and returns the process exit code.
func Execute() int {
	ios := iostreams.System()
	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintln(ios.ErrOut, "Error:", err)
		return 1
	}
	f := NewFactory(ios, home)
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := NewRootCmd(f).ExecuteContext(ctx); err != nil {
		var exitErr *ExitError
		if errors.As(err, &exitErr) {
			return exitErr.Code
		}
		fmt.Fprintln(ios.ErrOut, notice.Render(f.Common(), notice.Props{Status: styles.StatusFail, Text: err.Error()}))
		return 1
	}
	return 0
}
```

- [ ] **Step 5: Implementar `bindings.go` y `runner.go`**

`internal/cmd/bindings.go`:

```go
package cmd

import (
	"strings"

	tea "charm.land/bubbletea/v2"

	"github.com/BlasterM2A/shell-setup/internal/shellsetup"
	"github.com/BlasterM2A/shell-setup/internal/ui/statustable"
	"github.com/BlasterM2A/shell-setup/internal/ui/steplist"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

// eventMsg maps a domain event to the steplist message that shows it.
func eventMsg(home string, ev shellsetup.Event) (tea.Msg, bool) {
	switch ev := ev.(type) {
	case shellsetup.ToolStarted:
		return steplist.StepStarted{ID: "tool:" + ev.ID, Label: toolLabel(ev.ID, ev.Action)}, true
	case shellsetup.ToolFinished:
		detail := ev.Version
		if ev.Err != nil {
			detail = ev.Err.Error()
		}
		return steplist.StepFinished{
			ID: "tool:" + ev.ID, Label: toolLabel(ev.ID, ev.Action),
			Status: resultStatus(ev.Result), Detail: detail,
		}, true
	case shellsetup.FileFinished:
		detail := ""
		if ev.Result != shellsetup.ResultOK {
			detail = string(ev.Result)
		}
		return steplist.StepFinished{
			ID: "file:" + ev.Path, Label: shortPath(home, ev.Path),
			Status: resultStatus(ev.Result), Detail: detail,
		}, true
	}
	return nil, false
}

func toolLabel(id string, a shellsetup.Action) string {
	if a == shellsetup.ActionNone {
		return id
	}
	return id + " (" + string(a) + ")"
}

func resultStatus(r shellsetup.Result) styles.Status {
	switch r {
	case shellsetup.ResultOK:
		return styles.StatusOK
	case shellsetup.ResultSkipped:
		return styles.StatusSkip
	case shellsetup.ResultModified, shellsetup.ResultWarned:
		return styles.StatusWarn
	default:
		return styles.StatusFail
	}
}

func checkStatus(s shellsetup.CheckStatus) styles.Status {
	switch s {
	case shellsetup.CheckOK:
		return styles.StatusOK
	case shellsetup.CheckWarn:
		return styles.StatusWarn
	case shellsetup.CheckSkip:
		return styles.StatusSkip
	default:
		return styles.StatusFail
	}
}

// checkRows turns doctor checks into table rows.
func checkRows(home string, rep shellsetup.Report) []statustable.Row {
	rows := make([]statustable.Row, 0, len(rep.Checks))
	for _, c := range rep.Checks {
		rows = append(rows, statustable.Row{Status: checkStatus(c.Status), Name: shortPath(home, c.Name), Detail: c.Detail})
	}
	return rows
}

func phaseLabel(p shellsetup.Phase) string {
	switch p {
	case shellsetup.PhasePreflight:
		return "Checking system packages"
	case shellsetup.PhaseTools:
		return "Installing tools"
	default:
		return "Writing shell config"
	}
}

// shortPath shows paths under home as ~/...
func shortPath(home, p string) string {
	if rest, ok := strings.CutPrefix(p, home+"/"); ok {
		return "~/" + rest
	}
	return p
}
```

`internal/cmd/runner.go`:

```go
package cmd

import (
	"context"
	"fmt"

	tea "charm.land/bubbletea/v2"

	"github.com/BlasterM2A/shell-setup/internal/shellsetup"
	"github.com/BlasterM2A/shell-setup/internal/ui/model"
	"github.com/BlasterM2A/shell-setup/internal/ui/notice"
	"github.com/BlasterM2A/shell-setup/internal/ui/statustable"
	"github.com/BlasterM2A/shell-setup/internal/ui/steplist"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

// operation is an Engine call that publishes events and closes the channel.
type operation func(ctx context.Context, events chan<- shellsetup.Event) (shellsetup.Report, error)

// progressResult is what the operation returned.
type progressResult struct {
	Report shellsetup.Report
	OpErr  error
}

// runWithProgress runs op and shows its progress: the TUI on a terminal,
// plain lines otherwise. summary renders the final block once op is done.
// The returned error is a UI failure; op's own error is in OpErr.
func runWithProgress(ctx context.Context, f *Factory, title string, op operation,
	summary func(shellsetup.Report, error) string) (progressResult, error) {
	if f.UseTUI() {
		return runTUI(ctx, f, title, op, summary)
	}
	return runPlain(ctx, f, title, op, summary), nil
}

func runPlain(ctx context.Context, f *Factory, title string, op operation,
	summary func(shellsetup.Report, error) string) progressResult {
	c, out := f.Common(), f.IOStreams.Out
	fmt.Fprintln(out, c.Styles.Title.Render(title))
	events := make(chan shellsetup.Event)
	done := make(chan progressResult, 1)
	go func() {
		rep, err := op(ctx, events)
		done <- progressResult{Report: rep, OpErr: err}
	}()
	for ev := range events {
		if p, ok := ev.(shellsetup.PhaseStarted); ok {
			fmt.Fprintln(out, notice.Render(c, notice.Props{Status: styles.StatusInfo, Text: phaseLabel(p.Phase)}))
			continue
		}
		msg, ok := eventMsg(f.Home, ev)
		if fin, isFinished := msg.(steplist.StepFinished); ok && isFinished {
			fmt.Fprint(out, statustable.Render(c, statustable.Props{Rows: []statustable.Row{
				{Status: fin.Status, Name: fin.Label, Detail: fin.Detail},
			}}))
		}
	}
	res := <-done
	fmt.Fprint(out, summary(res.Report, res.OpErr))
	return res
}

func runTUI(ctx context.Context, f *Factory, title string, op operation,
	summary func(shellsetup.Report, error) string, opts ...tea.ProgramOption) (progressResult, error) {
	sys, err := f.System()
	if err != nil {
		return progressResult{}, err
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	opts = append([]tea.ProgramOption{tea.WithInput(f.IOStreams.In), tea.WithOutput(f.IOStreams.Out)}, opts...)
	p := tea.NewProgram(model.NewProgress(f.Common(), title, cancel), opts...)

	// sudo/chsh password prompts need the real terminal: suspend the TUI.
	sys.SetTerminalHandoff(func(run func() error) error {
		if err := p.ReleaseTerminal(); err != nil {
			return err
		}
		defer func() { _ = p.RestoreTerminal() }()
		return run()
	})
	defer sys.SetTerminalHandoff(nil)

	done := make(chan progressResult, 1)
	go func() {
		events := make(chan shellsetup.Event)
		forwarded := make(chan struct{})
		go func() {
			for ev := range events {
				if msg, ok := eventMsg(f.Home, ev); ok {
					p.Send(msg)
				}
			}
			close(forwarded)
		}()
		rep, err := op(ctx, events)
		<-forwarded
		p.Send(model.Done{Summary: summary(rep, err)})
		done <- progressResult{Report: rep, OpErr: err}
	}()
	if _, err := p.Run(); err != nil {
		return progressResult{}, err
	}
	return <-done, nil
}
```

- [ ] **Step 6: Implementar `apply.go` y los cuatro comandos**

`internal/cmd/apply.go`:

```go
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
```

`internal/cmd/init.go`:

```go
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
```

`internal/cmd/update.go`:

```go
package cmd

import (
	"context"

	"github.com/spf13/cobra"

	"github.com/BlasterM2A/shell-setup/internal/shellsetup"
)

// UpdateOptions are the inputs of update.
type UpdateOptions struct {
	Factory *Factory
	Force   bool
}

func newUpdateCmd(f *Factory, runF func(context.Context, *UpdateOptions) error) *cobra.Command {
	opts := &UpdateOptions{Factory: f}
	cmd := &cobra.Command{
		Use:   "update",
		Short: "Update every tool and the shell config",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if runF != nil {
				return runF(cmd.Context(), opts)
			}
			return runUpdate(cmd.Context(), opts)
		},
	}
	cmd.Flags().BoolVar(&opts.Force, "force", false, "overwrite managed files edited by hand (a backup is kept)")
	return cmd
}

func runUpdate(ctx context.Context, opts *UpdateOptions) error {
	e, err := opts.Factory.Engine()
	if err != nil {
		return err
	}
	op := func(ctx context.Context, events chan<- shellsetup.Event) (shellsetup.Report, error) {
		return e.Update(ctx, shellsetup.UpdateOptions{Force: opts.Force}, events)
	}
	return runApply(ctx, opts.Factory, e, "Updating your shell", op)
}
```

`internal/cmd/doctor.go`:

```go
package cmd

import (
	"context"
	"errors"
	"fmt"

	"github.com/spf13/cobra"

	"github.com/BlasterM2A/shell-setup/internal/selfupdate"
	"github.com/BlasterM2A/shell-setup/internal/shellsetup"
	"github.com/BlasterM2A/shell-setup/internal/ui/statustable"
)

// DoctorOptions are the inputs of doctor.
type DoctorOptions struct {
	Factory *Factory
}

func newDoctorCmd(f *Factory, runF func(context.Context, *DoctorOptions) error) *cobra.Command {
	opts := &DoctorOptions{Factory: f}
	return &cobra.Command{
		Use:   "doctor",
		Short: "Check tools, managed files and the default shell",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if runF != nil {
				return runF(cmd.Context(), opts)
			}
			return runDoctor(cmd.Context(), opts)
		},
	}
}

func runDoctor(ctx context.Context, opts *DoctorOptions) error {
	f := opts.Factory
	e, err := f.Engine()
	if err != nil {
		return err
	}
	rep, err := e.Doctor(ctx)
	if err != nil {
		return err
	}
	rep.Checks = append(rep.Checks, versionCheck(ctx, f.Updater()))
	fmt.Fprint(f.IOStreams.Out, statustable.Render(f.Common(), statustable.Props{
		Title: "shell-setup doctor", Rows: checkRows(f.Home, rep),
	}))
	if rep.Failed() {
		return &ExitError{Code: 1}
	}
	return nil
}

func versionCheck(ctx context.Context, u *selfupdate.Updater) shellsetup.CheckResult {
	c := shellsetup.CheckResult{Name: "shell-setup", Status: shellsetup.CheckOK, Detail: version}
	latest, newer, err := u.Latest(ctx)
	switch {
	case errors.Is(err, selfupdate.ErrDevBuild):
		c.Status, c.Detail = shellsetup.CheckSkip, "development build"
	case err != nil:
		c.Status, c.Detail = shellsetup.CheckSkip, "could not check for updates: "+err.Error()
	case newer:
		c.Status, c.Detail = shellsetup.CheckWarn, latest+" available, run shell-setup self-update"
	}
	return c
}
```

`internal/cmd/selfupdate.go`:

```go
package cmd

import (
	"context"
	"fmt"

	"github.com/spf13/cobra"

	"github.com/BlasterM2A/shell-setup/internal/ui/notice"
	"github.com/BlasterM2A/shell-setup/internal/ui/styles"
)

// SelfUpdateOptions are the inputs of self-update.
type SelfUpdateOptions struct {
	Factory *Factory
}

func newSelfUpdateCmd(f *Factory, runF func(context.Context, *SelfUpdateOptions) error) *cobra.Command {
	opts := &SelfUpdateOptions{Factory: f}
	return &cobra.Command{
		Use:   "self-update",
		Short: "Replace this binary with the latest release",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if runF != nil {
				return runF(cmd.Context(), opts)
			}
			return runSelfUpdate(cmd.Context(), opts)
		},
	}
}

func runSelfUpdate(ctx context.Context, opts *SelfUpdateOptions) error {
	f := opts.Factory
	c, out := f.Common(), f.IOStreams.Out
	v, updated, err := f.Updater().Apply(ctx)
	if err != nil {
		return err
	}
	if !updated {
		fmt.Fprintln(out, notice.Render(c, notice.Props{Status: styles.StatusOK, Text: "Already up to date (" + v + ")"}))
		return nil
	}
	fmt.Fprintln(out, notice.Render(c, notice.Props{Status: styles.StatusOK, Text: "Updated to " + v}))
	fmt.Fprintln(out, notice.Render(c, notice.Props{Status: styles.StatusInfo, Text: "Run `shell-setup update` to apply the new configuration."}))
	return nil
}
```

- [ ] **Step 7: Ejecutar los tests**

Run: `go test ./...`
Expected: PASS. Si `TestRunTUIReturnsReport` no puede arrancar bubbletea sin terminal en tu entorno (falla en `p.Run()` por un error de TTY y no por una aserción), cámbialo a `t.Skip("bubbletea needs a terminal here: <error>")` y anótalo en el commit. El camino TUI se verifica igualmente a mano en la Task 19 (Step 7).

- [ ] **Step 8: Prueba manual de solo lectura con un HOME desechable**

Run: `HOME=$(mktemp -d) go run . doctor; echo "exit=$?"`
Expected:
- se muestra la tabla `shell-setup doctor`, con `antidote` y `nerdfont` como `✗ not installed` y la fila `shell-setup` como `- development build`;
- `exit=1`.

- [ ] **Step 9: Commit**

```bash
git add go.mod go.sum internal/cmd
git commit -m "Wire commands: factory, progress (TUI/plain), init, update, doctor, self-update"
```

---

### Task 18: Bootstrap `install.sh` y sus tests

**Files:**
- Modify: `install.sh` y `tests/test_install.sh` (se reescriben enteros)

**Interfaces:**
- Produces: las funciones bash `check_os`, `detect_arch`, `install_binary <arch>` y `main`.
- Variables que se pueden sobrescribir (las usan los tests):
  - `SHELL_SETUP_BIN_DIR`
  - `SHELL_SETUP_STATE_DIR`
  - `SHELL_SETUP_OS_RELEASE`
  - `SHELL_SETUP_RELEASE_BASE`
- Los assets que espera del release (los genera la Task 19): `shell-setup_linux_<arch>.tar.gz` y `checksums.txt`.

- [ ] **Step 1: Escribir los tests que fallan**

`tests/test_install.sh` (sustituye el contenido completo del archivo):

```bash
#!/usr/bin/env bash
# Tests for the install.sh bootstrap. No network: curl and uname are stubbed
# and a fake release (tarball + checksums.txt) is served from a temp dir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_BIN="$TMP/fakebin"
export FAKE_RELEASE_DIR="$TMP/release"
mkdir -p "$FAKE_BIN" "$FAKE_RELEASE_DIR" "$TMP/build"

# Fake release: a tarball per arch containing a fake shell-setup binary.
printf '#!/bin/sh\necho fake-shell-setup "$@"\n' > "$TMP/build/shell-setup"
chmod +x "$TMP/build/shell-setup"
for arch in amd64 arm64; do
    tar -czf "$FAKE_RELEASE_DIR/shell-setup_linux_${arch}.tar.gz" -C "$TMP/build" shell-setup
done
(cd "$FAKE_RELEASE_DIR" && sha256sum shell-setup_linux_*.tar.gz > checksums.txt)

# Fake curl: copies $FAKE_RELEASE_DIR/<basename of URL> to the -o target.
cat > "$FAKE_BIN/curl" <<'EOS'
#!/usr/bin/env bash
out="" url="" prev=""
for arg in "$@"; do
    if [ "$prev" = "-o" ]; then out="$arg"; elif [[ "$arg" != -* ]]; then url="$arg"; fi
    prev="$arg"
done
cp "$FAKE_RELEASE_DIR/$(basename "$url")" "$out"
EOS
cat > "$FAKE_BIN/uname" <<'EOS'
#!/usr/bin/env bash
echo "${FAKE_ARCH:-x86_64}"
EOS
chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/uname"
export PATH="$FAKE_BIN:$PATH"

export SHELL_SETUP_BIN_DIR="$TMP/bin"
export SHELL_SETUP_STATE_DIR="$TMP/state"
export SHELL_SETUP_RELEASE_BASE="https://example.invalid/download"
export SHELL_SETUP_OS_RELEASE="$TMP/os-release"

source "$SCRIPT_DIR/../install.sh"
set +e # install.sh enables -e; assertions must keep running

FAILURES=0

assert_eq() {
    local expected="$1" actual="$2" desc="$3"
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc (expected '$expected', got '$actual')"
        FAILURES=$((FAILURES + 1))
    fi
}

assert_true() {
    local desc="$1"
    shift
    if "$@"; then echo "PASS: $desc"; else echo "FAIL: $desc"; FAILURES=$((FAILURES + 1)); fi
}

assert_false() {
    local desc="$1"
    shift
    if "$@"; then echo "FAIL: $desc"; FAILURES=$((FAILURES + 1)); else echo "PASS: $desc"; fi
}

# --- detect_arch ---
assert_eq "amd64" "$(export FAKE_ARCH=x86_64; detect_arch)" "x86_64 maps to amd64"
assert_eq "arm64" "$(export FAKE_ARCH=aarch64; detect_arch)" "aarch64 maps to arm64"
assert_false "unsupported arch fails" bash -c "export FAKE_ARCH=mips64; source '$SCRIPT_DIR/../install.sh'; detect_arch" 2>/dev/null

# --- check_os ---
printf 'ID=ubuntu\nID_LIKE=debian\n' > "$SHELL_SETUP_OS_RELEASE"
assert_true "ubuntu is supported" check_os
printf 'ID=fedora\n' > "$SHELL_SETUP_OS_RELEASE"
assert_false "fedora is rejected" bash -c "source '$SCRIPT_DIR/../install.sh'; check_os" 2>/dev/null
printf 'ID=ubuntu\nID_LIKE=debian\n' > "$SHELL_SETUP_OS_RELEASE"

# --- install_binary ---
assert_true "installs the binary" bash -c "source '$SCRIPT_DIR/../install.sh'; install_binary amd64" >/dev/null
assert_eq "fake-shell-setup --version" "$("$SHELL_SETUP_BIN_DIR/shell-setup" --version)" "installed binary runs"

second="$(bash -c "source '$SCRIPT_DIR/../install.sh'; install_binary amd64")"
assert_true "re-run skips the download" grep -q "already up to date" <<<"$second"

# A corrupted checksum must abort and leave no new binary behind.
rm -f "$SHELL_SETUP_BIN_DIR/shell-setup" "$SHELL_SETUP_STATE_DIR/bootstrap.sha256"
sed -i "s/^[0-9a-f]*/$(printf '0%.0s' $(seq 64))/" "$FAKE_RELEASE_DIR/checksums.txt"
assert_false "bad checksum aborts" bash -c "source '$SCRIPT_DIR/../install.sh'; install_binary amd64" 2>/dev/null
assert_false "no binary after a bad checksum" test -e "$SHELL_SETUP_BIN_DIR/shell-setup"

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "$FAILURES test(s) failed"
    exit 1
fi
echo "All tests passed"
```

- [ ] **Step 2: Ejecutarlos para verificar que fallan**

Run: `bash tests/test_install.sh`
Expected: FAIL. El `install.sh` antiguo no define `detect_arch` ni `install_binary` (o intenta ejecutar `main`).

- [ ] **Step 3: Implementación**

`install.sh` (sustituye el contenido completo del archivo):

```bash
#!/usr/bin/env bash
# shell-setup bootstrap: installs the shell-setup binary from the latest
# GitHub release (checksum verified) and runs `shell-setup init`.
#   curl -fsSL https://raw.githubusercontent.com/BlasterM2A/shell-setup/master/install.sh | bash
set -euo pipefail

REPO="BlasterM2A/shell-setup"
BIN_DIR="${SHELL_SETUP_BIN_DIR:-$HOME/.local/bin}"
STATE_DIR="${SHELL_SETUP_STATE_DIR:-$HOME/.local/state/shell-setup}"
OS_RELEASE="${SHELL_SETUP_OS_RELEASE:-/etc/os-release}"
RELEASE_BASE="${SHELL_SETUP_RELEASE_BASE:-https://github.com/$REPO/releases/latest/download}"
STAMP_FILE="$STATE_DIR/bootstrap.sha256"

log() { printf '\033[1;34m•\033[0m %s\n' "$1"; }
die() {
    printf '\033[1;31m✗\033[0m %s\n' "$1" >&2
    exit 1
}

check_os() {
    [ -f "$OS_RELEASE" ] || die "Cannot detect the OS: $OS_RELEASE not found. Ubuntu/Debian only."
    local ids
    ids="$(. "$OS_RELEASE" && echo "${ID:-} ${ID_LIKE:-}")"
    case " $ids " in
        *" debian "* | *" ubuntu "*) ;;
        *) die "Unsupported OS (${ids% }). shell-setup supports Ubuntu/Debian only." ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64 | amd64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac
}

install_binary() {
    local arch="$1" asset tmp expected
    asset="shell-setup_linux_${arch}.tar.gz"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/checksums.txt" "$RELEASE_BASE/checksums.txt" ||
        { rm -rf "$tmp"; die "Could not download checksums.txt"; }
    expected="$(grep " ${asset}\$" "$tmp/checksums.txt" || true)"
    [ -n "$expected" ] || { rm -rf "$tmp"; die "No checksum for $asset in the latest release"; }

    if [ -x "$BIN_DIR/shell-setup" ] && [ -f "$STAMP_FILE" ] && [ "$(cat "$STAMP_FILE")" = "$expected" ]; then
        rm -rf "$tmp"
        log "shell-setup is already up to date"
        return 0
    fi

    log "Downloading $asset..."
    curl -fsSL -o "$tmp/$asset" "$RELEASE_BASE/$asset" || { rm -rf "$tmp"; die "Could not download $asset"; }
    (cd "$tmp" && printf '%s\n' "$expected" | sha256sum -c --status) ||
        { rm -rf "$tmp"; die "Checksum verification failed for $asset"; }
    tar -xzf "$tmp/$asset" -C "$tmp" shell-setup
    mkdir -p "$BIN_DIR" "$STATE_DIR"
    install -m 0755 "$tmp/shell-setup" "$BIN_DIR/shell-setup"
    printf '%s\n' "$expected" > "$STAMP_FILE"
    rm -rf "$tmp"
    log "Installed $BIN_DIR/shell-setup"
}

main() {
    check_os
    local arch
    arch="$(detect_arch)"
    install_binary "$arch"
    # With `curl | bash`, stdin is the pipe: give init the real terminal.
    if (: </dev/tty) 2>/dev/null; then
        exec "$BIN_DIR/shell-setup" init </dev/tty
    fi
    exec "$BIN_DIR/shell-setup" init --plain
}

# Only run main when executed (./install.sh, bash install.sh, curl | bash),
# not when sourced by tests.
if ! (return 0 2>/dev/null); then
    main "$@"
fi
```

- [ ] **Step 4: Ejecutar los tests**

Run: `bash -n install.sh && bash tests/test_install.sh`
Expected: todo `PASS` y, al final, `All tests passed`

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install.sh
git commit -m "Rewrite install.sh as a bootstrap for the shell-setup binary"
```

---

### Task 19: Release, CI, lint con depguard, documentación y limpieza

**Files:**
- Create: `.goreleaser.yml`, `.golangci.yml`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`
- Modify: `README.md`, `CLAUDE.md`, `.gitignore` y `.gitattributes`
- Delete: `zsh/zshrc` (y los directorios vacíos `zsh/` y `starship/`)

**Interfaces:**
- Consumes: las variables de ldflags `internal/cmd.version`, `.commit` y `.repoSlug` (Task 1/17), y los nombres de asset que espera `install.sh` (Task 18).

- [ ] **Step 1: `.goreleaser.yml`**

```yaml
version: 2
project_name: shell-setup

before:
  hooks:
    - go mod tidy

builds:
  - id: shell-setup
    main: .
    binary: shell-setup
    env:
      - CGO_ENABLED=0
    goos: [linux]
    goarch: [amd64, arm64]
    ldflags:
      - -s -w
      - -X github.com/BlasterM2A/shell-setup/internal/cmd.version={{ .Version }}
      - -X github.com/BlasterM2A/shell-setup/internal/cmd.commit={{ .ShortCommit }}
      - -X github.com/BlasterM2A/shell-setup/internal/cmd.repoSlug=BlasterM2A/shell-setup

archives:
  - formats: [tar.gz]
    # Must match install.sh and go-selfupdate: shell-setup_linux_<arch>.tar.gz
    name_template: "{{ .ProjectName }}_{{ .Os }}_{{ .Arch }}"

checksum:
  name_template: checksums.txt

changelog:
  use: git
```

Run: `goreleaser check && goreleaser release --snapshot --clean && ls dist/`
Expected: `shell-setup_linux_amd64.tar.gz`, `shell-setup_linux_arm64.tar.gz` y `checksums.txt`. Comprueba además que `tar -tzf dist/shell-setup_linux_amd64.tar.gz` contiene `shell-setup`.

- [ ] **Step 2: `.golangci.yml` con las reglas de dependencia**

```yaml
version: "2"

linters:
  default: standard
  enable:
    - depguard
  settings:
    depguard:
      rules:
        business-logic:
          files:
            - "**/internal/shellsetup/**"
            - "**/internal/selfupdate/**"
            - "**/internal/config/**"
          deny:
            - pkg: github.com/BlasterM2A/shell-setup/internal/ui
              desc: business logic must not depend on the UI
            - pkg: github.com/BlasterM2A/shell-setup/internal/iostreams
              desc: business logic must not write to the console
            - pkg: github.com/BlasterM2A/shell-setup/internal/cmd
              desc: business logic must not depend on commands
            - pkg: charm.land
              desc: business logic must not depend on UI libraries
        ui:
          files:
            - "**/internal/ui/**"
            - "**/internal/iostreams/**"
            - "**/internal/log/**"
          deny:
            - pkg: github.com/BlasterM2A/shell-setup/internal/shellsetup
              desc: the UI must not depend on business logic
            - pkg: github.com/BlasterM2A/shell-setup/internal/cmd
              desc: the UI must not depend on commands

formatters:
  enable:
    - gofmt
```

Run: `task lint`
Expected: sin hallazgos. Si aparecen, corrígelos (normalmente `errcheck` en `fmt.Fprint*`: añade `_, _ =` solo cuando el linter lo exija) y vuelve a ejecutarlo.

- [ ] **Step 3: Verificar que depguard detecta una violación**

```bash
cat > internal/shellsetup/zz_violation.go <<'EOF'
package shellsetup

import _ "github.com/BlasterM2A/shell-setup/internal/ui/styles"
EOF
golangci-lint run ./internal/shellsetup/...; echo "exit=$?"
rm internal/shellsetup/zz_violation.go
```

Expected: un error de `depguard` con el texto "business logic must not depend on the UI" y `exit=1`. Si sale `exit=0`, revisa la sintaxis de `files` en la documentación de depguard v2 hasta conseguir que falle. Sin esto, las reglas de dependencia no están garantizadas.

- [ ] **Step 4: Workflows de CI y de release**

`.github/workflows/ci.yml`:

```yaml
name: ci
on:
  push:
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: task lint test
```

`.github/workflows/release.yml`:

```yaml
name: release
on:
  push:
    tags: ["v*"]

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: jdx/mise-action@v2
      - run: task test
      - run: goreleaser release --clean
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 5: Limpieza**

```bash
git rm zsh/zshrc
rmdir zsh starship 2>/dev/null || true
```

En `.gitignore`, elimina el bloque del comentario sobre antidote y la línea `zsh/plugins.zsh`, porque ese archivo ya no existe en el repo. Sustituye además el comentario sobre `*.bak.*` por:

```gitignore
# Backups shell-setup makes when replacing a file (never expected in the repo)
*.bak.*
```

En `.gitattributes`, sustituye las líneas `zshrc text eol=lf` y `plugins.txt text eol=lf` por:

```gitattributes
*.zsh text eol=lf
*.go text eol=lf
*.txtar text eol=lf
internal/shellsetup/registry/files/** text eol=lf
```

- [ ] **Step 6: Reescribir `README.md`**

````markdown
# shell-setup

A CLI/TUI that bootstraps and maintains a zsh environment on Ubuntu/Debian.
It installs and keeps up to date:

- **Built-in** (always installed; shell-setup needs them): zsh (as the login
  shell) and [mise](https://mise.jdx.dev/)
- [starship](https://starship.rs/), [zoxide](https://github.com/ajeetdsouza/zoxide)
  and [fzf](https://github.com/junegunn/fzf), installed through mise
- [antidote](https://github.com/mattmc3/antidote) with zsh-autosuggestions and
  zsh-syntax-highlighting
- JetBrainsMono Nerd Font
- AI CLIs (optional, a failure is only a warning): Claude Code, GitHub Copilot
  CLI, Junie, Antigravity CLI (`agy`)

## Install on a new machine

```bash
curl -fsSL https://raw.githubusercontent.com/BlasterM2A/shell-setup/master/install.sh | bash
```

This downloads the latest release binary to `~/.local/bin/shell-setup`
(checksum verified) and runs `shell-setup init`. Expect a **sudo** prompt
(apt packages) and possibly a **chsh** password prompt (login shell).

After the first `init`:

1. Log out and back in (the new login shell needs a new session).
2. Select **JetBrainsMono Nerd Font** in your terminal's font settings.

## Commands

| Command | What it does |
|---|---|
| `shell-setup init` | Install what is missing, write the shell config, make zsh the login shell |
| `shell-setup update` | Same as init, plus update every installed tool. `--force` overwrites managed files you edited (a backup is kept) |
| `shell-setup doctor` | Check tools, managed files and the login shell; exits non-zero if something required is missing |
| `shell-setup self-update` | Replace the binary with the latest release; then run `shell-setup update` |

Global flags: `--plain` (no interactive UI), `--verbose`, `--quiet`.

## Where things live

| Path | Owner |
|---|---|
| `~/.config/zsh/{env,functions,aliases,custom}.d/*.zsh` | **You.** Auto-loaded, never touched by shell-setup |
| `~/.zshrc` | shell-setup (a one-line stub) |
| `~/.config/shell-setup/zshrc`, `zsh.d/`, `plugins.txt` | shell-setup (generated) |
| `~/.config/starship.toml` | shell-setup |
| `~/.config/shell-setup/config.toml` | You (optional: `log_level`) |
| `~/.local/state/shell-setup/` | shell-setup (state, log) |

If you edit a file shell-setup manages, `update` leaves it alone and `doctor`
reports it as modified; `update --force` replaces it after a backup
(`<file>.bak.<timestamp>`). Put personal config in `~/.config/zsh/*.d` instead.

## Development

```bash
mise install          # Go, Task, goreleaser, golangci-lint
task test             # Go tests + bootstrap script tests
task lint             # golangci-lint, including dependency rules (depguard)
task run -- doctor    # run the CLI from source
task snapshot         # local release build into ./dist
```

Add a tool by adding `internal/shellsetup/registry/<id>.toml` (and any config
file under `registry/files/`). No Go code is needed if its backend exists.

Release: `git tag vX.Y.Z && git push --tags` (GitHub Actions runs goreleaser).
````

- [ ] **Step 7: Reescribir `CLAUDE.md`**

```markdown
# shell-setup

Go CLI/TUI that bootstraps and maintains a zsh environment on Ubuntu/Debian
(zsh, mise, starship, zoxide, fzf, antidote, Nerd Font, AI CLIs). Distributed
as a GitHub Release binary; `install.sh` only downloads it and runs `init`.
See `README.md` for usage and
`docs/superpowers/specs/2026-10-10-shell-setup-cli-design.md` for the design.

## Repo layout

- `main.go` → `internal/cmd` (cobra). `cmd` is the only integration layer: it
  reads flags, builds UI components and binds domain events to them. No
  business logic, no styles.
- `internal/shellsetup` — the whole domain in one package (chezmoi-style):
  `Engine` (`Init`, `Update`, `Doctor`), tool manifests + catalog, backends
  (`apt`, `mise`, `script`, `archive`, `font`), zsh config composition,
  managed files + state. All I/O goes through the `System` interface.
- `internal/shellsetup/registry/*.toml` — one manifest per tool, embedded.
  `registry/files/` holds the config files they ship and the zsh profile.
- `internal/ui` — components (`steplist`, `statustable`, `notice`, `model`).
  `internal/ui/styles` is the ONLY place that defines colors/icons.
- `internal/iostreams`, `internal/log`, `internal/config`, `internal/selfupdate`.
- `install.sh` + `tests/test_install.sh` — bootstrap and its tests.

## Conventions

- Dependency rules are enforced by depguard (`.golangci.yml`): `ui`,
  `iostreams` and `log` never import `shellsetup`/`cmd`; `shellsetup`,
  `selfupdate` and `config` never import `ui`/`iostreams`/`cmd`/`charm.land`.
- Every operation is idempotent. Managed files are never overwritten if the
  user edited them unless `--force`; anything replaced is backed up.
- The domain never prints: it sends `Event`s on a channel and returns a
  `Report`.
- Never run `shell-setup init`/`update` against your own `$HOME` while
  developing (installs packages, chsh). Verify with `task test` and
  `task lint`; manual runs only `doctor`/`--version` with `HOME=$(mktemp -d)`.
- No Docker- or shellcheck-based testing (explicit scope decision).
- The GitHub slug `BlasterM2A/shell-setup` is injected by goreleaser ldflags
  and hardcoded in `install.sh`; update both if the repo moves.

## Making changes

Design changes: update the spec first, then the code. Adding a tool is a new
manifest in `registry/` (plus a backend in Go only if none fits).
```

- [ ] **Step 8: Verificación completa**

Run: `task lint test && goreleaser release --snapshot --clean`
Expected: todo en verde. Después, prueba manual de solo lectura con el binario del snapshot:

```bash
H=$(mktemp -d); HOME=$H ./dist/shell-setup_linux_amd64_v1/shell-setup --version
HOME=$H ./dist/shell-setup_linux_amd64_v1/shell-setup doctor; echo "exit=$?"
```

Expected: una versión con el sufijo `-SNAPSHOT-…`, la tabla de doctor y `exit=1`. La ruta exacta dentro de `dist/` puede variar: usa `find dist -name shell-setup -type f`.

**Verificación manual del camino TUI e interactivo.** No hay test automático que lo cubra, así que hay que hacerla en una VM o máquina desechable con Ubuntu, **nunca en tu equipo**:
1. Ejecuta el one-liner.
2. Comprueba que:
   - se muestra la lista de pasos;
   - el prompt de sudo aparece en una terminal limpia (con la TUI suspendida) y la TUI vuelve después;
   - el resumen final incluye el aviso de la fuente.
3. Ejecuta `shell-setup init` otra vez y comprueba que no pide sudo.
4. Ejecuta `shell-setup update`.
5. Edita `~/.zshrc`, ejecuta `shell-setup update` y comprueba que doctor lo marca como *modified*.
6. Tras publicar una segunda release, ejecuta `shell-setup self-update`.

- [ ] **Step 9: Commit**

```bash
git add -A .goreleaser.yml .golangci.yml .github README.md CLAUDE.md .gitignore .gitattributes zsh starship
git commit -m "Add release pipeline, CI, depguard rules; update docs; remove old dotfiles"
```

**Despliegue (después de fusionar a `master`):**
- Ejecuta `git tag v0.1.0 && git push --tags` **inmediatamente**.
- Hasta que el workflow publique la release, el one-liner falla con "Could not download checksums.txt". El `install.sh` nuevo necesita una release que exista.
