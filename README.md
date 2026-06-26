# Argon (local fork)

Monorepo for local Argon development. Three components:

| Directory | Language | What |
|---|---|---|
| `argon/` | Rust | CLI binary (`argon` command) |
| `argon-vscode/` | TypeScript + React | VS Code extension |
| `argon-roblox/` | Luau | Roblox Studio plugin |

---

## Quick start

```bash
# First time only — symlink extension into VS Code
./dev-build.sh setup

# Build + install everything (debug CLI, dev extension, plugin)
./dev-build.sh

# Reload VS Code window to pick up the extension
# Ctrl+Shift+P > Developer: Reload Window
```

---

## Build script

```
./dev-build.sh [setup] [cli] [vscode] [plugin] [--release] [--restart] [--no-restart]

  (no args)    build everything: cli, vscode, plugin
  cli          build CLI -> ~/.local/bin/argon
  vscode       build VS Code extension (webview + webpack)
  plugin       build Roblox plugin -> argon-roblox/Argon.rbxm
  setup        symlink VS Code extension, then exit

  --release    cargo build --release (default: debug)
  --restart    kill any running `argon serve` after cli build
  --no-restart skip the serve check
```

---

## Component workflows

### CLI (`argon/`)

```bash
cargo build                    # debug build -> target/debug/argon
cargo build --release          # release build -> target/release/argon
./dev-build.sh cli             # build + install to ~/.local/bin/argon
./dev-build.sh cli --release   # release + install
./dev-build.sh cli --restart   # build + install + kill stale serve
```

After installing, verify with `argon --version`.

### VS Code extension (`argon-vscode/`)

**One-time setup:**
```bash
./dev-build.sh setup
# Reload VS Code window once
```

**Full rebuild:**
```bash
./dev-build.sh vscode
# Ctrl+Shift+P > Developer: Reload Window
```

**Hot reload during development** (two watchers, leave running):
```bash
# Terminal 1 — extension TS
cd argon-vscode && node_modules/.bin/webpack --watch --mode development

# Terminal 2 — webview React
cd argon-vscode/webview-ui && node_modules/.bin/vite build --watch
```

After any change rebuilds:
- Extension TS change → `Ctrl+Shift+P` → **Developer: Reload Window**
- Webview TSX change → `Ctrl+Shift+P` → **Developer: Reload Webviews** (faster)

### Roblox plugin (`argon-roblox/`)

Requires `argon` CLI on PATH (build CLI first).

```bash
./dev-build.sh plugin          # build + install to Studio plugins dir
```

Or manually:
```bash
cd argon-roblox
wally install
argon build --output Argon.rbxm
# Copy Argon.rbxm to your Studio Plugins folder
```

---

## Prerequisites

| Tool | Install |
|---|---|
| Rust + cargo | https://rustup.rs |
| Node.js + npm | https://nodejs.org |
| rokit | https://github.com/roblox/rokit |
| wally | `rokit add UpliftGames/wally` |

PATH should include `~/.local/bin` (CLI install target) and `~/.rokit/bin`.

---

## Project structure

```
argon/
├── argon/           Rust CLI source
│   ├── src/
│   ├── crates/      workspace sub-crates
│   └── build.rs     downloads argon-roblox plugin at build time
├── argon-vscode/    VS Code extension
│   ├── src/         Extension TypeScript
│   │   ├── instanceTree.ts    Explorer tree view
│   │   ├── propertiesView.ts  Properties panel webview
│   │   └── extension.ts       Activation + wiring
│   └── webview-ui/  React properties panel
│       └── src/
│           ├── App.tsx
│           ├── components/    Property input widgets
│           └── utils/         categorize, math helpers
├── argon-roblox/    Roblox Studio plugin (Luau)
├── target/          Cargo build artifacts (shared workspace)
└── dev-build.sh     Development build script
```
