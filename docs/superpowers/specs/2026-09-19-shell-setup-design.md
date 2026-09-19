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
- **Distribución:** repo git privado en GitHub + script `install.sh` custom
  (sin Stow ni chezmoi). Symlinks del repo hacia `$HOME`.
- **Migración de `.bashrc`:** ninguna — se arranca limpio, solo se replican
  los 3 aliases (`ll`, `la`, `l`) en el nuevo `.zshrc`.
- **Nerd Font:** se instala JetBrainsMono Nerd Font automáticamente; la
  selección como fuente de la terminal queda manual (no se puede automatizar
  por script en la mayoría de emuladores de terminal).
- **Starship theme:** preset propio minimalista (no un preset oficial).
- **Shell por defecto:** el script cambia el shell a zsh automáticamente
  (`chsh -s`) si no lo es ya.
- **Idempotencia:** el script se puede correr N veces sin romper nada;
  dotfiles existentes que no sean ya symlinks al repo se respaldan con
  timestamp antes de reemplazarlos.
- **Testing:** fuera de alcance por ahora. Sin validación en contenedor ni
  shellcheck en esta primera versión.
- **mise:** se instala y se activa en `.zshrc` (`eval "$(mise activate zsh)"`)
  para gestionar versiones de runtimes (node, python, etc.) por proyecto. No
  se predefinen versiones globales — el usuario las configura por
  proyecto/dispositivo con `mise use` según lo necesite.

## Arquitectura

Repo git privado (`shell-setup`, este directorio) con dotfiles versionados
dentro del repo (no directamente en `$HOME`), más un script `install.sh`
idempotente que:

1. Instala los paquetes faltantes.
2. Symlinkea los dotfiles del repo hacia `$HOME` (con backup si hace falta).
3. Cambia el shell por defecto a zsh.

**Flujo en máquina nueva:**
```
git clone git@github.com:<user>/shell-setup ~/shell-setup
cd ~/shell-setup
./install.sh
```

**Flujo de actualización:** editar en el repo → `git push`; en otra máquina
→ `git pull`. Los symlinks reflejan el cambio al instante; no hace falta
re-correr `install.sh` salvo que cambien paquetes o el plugin manager.

## Estructura del repo

```
shell-setup/
├── install.sh                 # script bootstrap idempotente
├── zsh/
│   ├── zshrc                  # -> ~/.zshrc
│   └── plugins.txt            # lista de plugins para antidote
├── starship/
│   └── starship.toml          # -> ~/.config/starship.toml
└── scripts/
    └── lib.sh                 # helpers: log, backup_if_exists, symlink, is_installed
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
3. Symlinkear dotfiles: por cada archivo, si el destino existe y no es ya
   symlink al repo → respaldar a `<archivo>.bak.<timestamp>`, luego
   symlinkear.
4. Configurar antidote con los plugins listados en `zsh/plugins.txt`.
5. `chsh -s "$(which zsh)"` si el shell de login actual no es ya zsh.
6. Imprimir resumen final: qué se instaló, qué ya estaba, qué se respaldó, y
   confirmar que `zsh --version`, `starship --version`, `fzf --version`,
   `zoxide --version` responden correctamente.
7. Avisar que hace falta reiniciar la terminal y seleccionar manualmente
   "JetBrainsMono Nerd Font" en las preferencias del emulador de terminal.

## Manejo de errores

- `set -euo pipefail` en todo el script para abortar ante errores
  inesperados en vez de continuar en estado inconsistente.
- Cada instalación de paquete se verifica post-instalación
  (`command -v <tool>`); si falla, el script aborta con un mensaje claro
  indicando qué paso falló.
- Los symlinks nunca se crean sin antes verificar si hay que respaldar algo
  existente — no se pierde configuración previa sin backup.

## Fuera de alcance (por ahora)

- Otros dotfiles (`.gitconfig`, `.tmux.conf`, `.vimrc`).
- Configuración de Claude Code (settings, plugins, skills).
- Testing automatizado (contenedor Docker, shellcheck).
- Herramientas adicionales de reemplazo (`eza`/`lsd` para `ls`, `bat` para
  `cat`, `tmux`) — se pueden evaluar en una iteración futura.
