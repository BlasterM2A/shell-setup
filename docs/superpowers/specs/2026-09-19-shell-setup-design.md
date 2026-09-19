# shell-setup — Clip tool para configuración de shell reutilizable

**Fecha:** 2026-09-19
**Estado:** Aprobado para implementación

## Contexto y objetivo

El usuario quiere automatizar la configuración de su shell en Ubuntu para poder
reproducirla fácilmente en todos los dispositivos que usa. El `.bashrc` actual
es esencialmente el default de Ubuntu (119 líneas, solo 3 aliases custom:
`ll`, `la`, `l`) — no hay configuración previa significativa que migrar, así
que el setup arranca minimalista.

## Decisiones

- **Shell:** Zsh (POSIX-compatible, ecosistema amplio, estándar de facto).
- **Stack:** Zsh minimalista (sin Oh My Zsh) + Starship (prompt) +
  zsh-autosuggestions + zsh-syntax-highlighting + fzf + zoxide + mise.
- **Plugin manager:** antidote.
- **Alcance del tool:** dotfiles core (`.zshrc`, `starship.toml`) +
  instalación automática de paquetes. No incluye (por ahora) otros dotfiles
  (`.gitconfig`, `.tmux.conf`), ni config de Claude Code.
- **Distribución:** repo público en GitHub (BlasterM2A/shell-setup) + un único
  `install.sh` autocontenible, sin `git clone` en el dispositivo destino. El
  script instala las herramientas de terceros y descarga los 3 dotfiles
  propios (`zshrc`, `starship.toml`, `plugins.txt`) directo vía
  `raw.githubusercontent.com`, escribiéndolos en su lugar (no symlinks, no
  repo clonado). *(Decisión revisada — originalmente se diseñó con
  `git clone` + symlinks; se simplificó tras notar que `install.sh` solo
  instala herramientas de terceros y gestiona 3 archivos chicos, sin
  necesidad real de un repo persistente en el dispositivo.)*
- **Migración de `.bashrc`:** ninguna — se arranca limpio, solo se replican
  los 3 aliases (`ll`, `la`, `l`) en el nuevo `.zshrc`.
- **Nerd Font:** se instala JetBrainsMono Nerd Font automáticamente; la
  selección como fuente de la terminal queda manual (no se puede automatizar
  por script en la mayoría de emuladores de terminal).
- **Starship theme:** preset propio minimalista (no un preset oficial).
- **Shell por defecto:** el script cambia el shell a zsh automáticamente
  (`chsh -s`) si no lo es ya.
- **Idempotencia:** el script se puede correr N veces sin romper nada;
  dotfiles existentes con contenido distinto al descargado se respaldan con
  timestamp antes de sobreescribirlos (si el contenido es idéntico, no se
  toca nada).
- **Testing:** fuera de alcance por ahora. Sin validación en contenedor ni
  shellcheck en esta primera versión.
- **mise:** se instala y se activa en `.zshrc` (`eval "$(mise activate zsh)"`)
  para gestionar versiones de runtimes (node, python, etc.) por proyecto. No
  se predefinen versiones globales — el usuario las configura por
  proyecto/dispositivo con `mise use` según lo necesite.

## Arquitectura

Repo público en GitHub (`shell-setup`) donde vive el código fuente de los 3
dotfiles y de `install.sh`. **Ningún dispositivo destino clona el repo.**
`install.sh` es autocontenible (una sola función `fetch_dotfile` reemplaza
symlinks) y, al correr:

1. Instala los paquetes faltantes.
2. Descarga los 3 dotfiles propios directo desde
   `raw.githubusercontent.com` y los escribe en `$HOME` (con backup si el
   contenido cambió respecto al existente).
3. Cambia el shell por defecto a zsh.

**Flujo en máquina nueva (y de actualización — es el mismo comando):**
```
curl -fsSL https://raw.githubusercontent.com/BlasterM2A/shell-setup/master/install.sh | bash
```

Re-correr el mismo comando en cualquier momento trae los cambios más
recientes de los dotfiles y vuelve a aplicar los instaladores (todos
idempotentes) — no hace falta `git pull` porque no hay ningún repo local.

## Estructura del repo

```
shell-setup/
├── install.sh                 # único script: helpers + instaladores + orquestación
├── zsh/
│   ├── zshrc                  # fuente; install.sh la descarga a ~/.zshrc
│   └── plugins.txt            # fuente; install.sh la descarga a ~/.config/shell-setup/plugins.txt
├── starship/
│   └── starship.toml          # fuente; install.sh la descarga a ~/.config/starship.toml
└── tests/
    └── test_install.sh        # sourcea install.sh (con guard), stubs de curl/apt-get/git/mise
```

## Componentes

### Paquetes instalados por `install.sh`

Cada uno se verifica con `command -v` antes de instalar (no se reinstala si
ya está presente):

- `zsh` (apt)
- `git`, `curl` (apt, por si faltan)
- `starship` (script oficial vía curl, instala en `~/.local/bin`)
- `fzf` (apt)
- `zoxide` (script oficial vía curl, o apt si está disponible)
- `antidote` (git clone a `~/.antidote`)
- `mise` (script oficial vía curl, instala en `~/.local/bin`)
- Nerd Font JetBrainsMono (descarga desde GitHub releases →
  `~/.local/share/fonts` → `fc-cache -f`)

### `.zshrc` (contenido inicial)

- Inicialización de antidote, cargando `zsh-users/zsh-autosuggestions` y
  `zsh-users/zsh-syntax-highlighting` desde `zsh/plugins.txt`
- Inicialización de starship (`eval "$(starship init zsh)"`)
- Inicialización de zoxide (`eval "$(zoxide init zsh)"`, alias `z` para `cd`)
- Inicialización de mise (`eval "$(mise activate zsh)"`)
- Inicialización de fzf (keybindings + fuzzy completion)
- Los 3 aliases migrados: `ll='ls -alF'`, `la='ls -A'`, `l='ls -CF'`

### `starship.toml`

Preset propio minimalista: directorio actual, rama/estado de git, lenguaje
detectado si aplica (node/python/etc.), tiempo de ejecución de comandos
lentos. Requiere Nerd Font para íconos.

## Pasos del `install.sh`

Ejecutado con `set -euo pipefail`, idempotente en cada paso:

1. Detectar SO (Ubuntu/Debian-based); abortar con mensaje claro si no lo es.
2. Instalar paquetes faltantes (chequeo previo vía `command -v`).
3. Descargar los 3 dotfiles vía `curl -fsSL` desde `raw.githubusercontent.com`
   y escribirlos en `$HOME`: si el destino existe y su contenido difiere del
   descargado → respaldar a `<archivo>.bak.<timestamp>`, luego escribir; si
   el contenido es idéntico, no tocar nada.
4. `chsh -s "$(which zsh)"` si el shell de login actual no es ya zsh
   (con fallback a `sudo chsh` si falla la autenticación PAM — común en
   cuentas sin contraseña, solo SSH key).
5. Imprimir resumen final: versiones de cada herramienta instalada, y
   fallar (`exit 1`) si alguna falta.
6. Avisar que hace falta cerrar sesión y volver a entrar (no alcanza con
   reiniciar la terminal), y seleccionar manualmente "JetBrainsMono Nerd
   Font" en las preferencias del emulador de terminal.

## Manejo de errores

- `set -euo pipefail` en todo el script para abortar ante errores
  inesperados en vez de continuar en estado inconsistente.
- Cada instalación de paquete se verifica post-instalación
  (`command -v <tool>`); si falla, el script aborta con un mensaje claro
  indicando qué paso falló.
- Los dotfiles nunca se sobreescriben sin antes verificar si hay que
  respaldar contenido existente — no se pierde configuración previa sin
  backup.

## Fuera de alcance (por ahora)

- Otros dotfiles (`.gitconfig`, `.tmux.conf`, `.vimrc`).
- Configuración de Claude Code (settings, plugins, skills).
- Testing automatizado (contenedor Docker, shellcheck).
- Herramientas adicionales de reemplazo (`eza`/`lsd` para `ls`, `bat` para
  `cat`, `tmux`) — se pueden evaluar en una iteración futura.
