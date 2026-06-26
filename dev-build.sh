#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="$ROOT/argon"
VSCODE_DIR="$ROOT/argon-vscode"
PLUGIN_DIR="$ROOT/argon-roblox"
EXT_LINK="${HOME}/.vscode/extensions/argon-dev"
BIN_DIR="${HOME}/.local/bin"
BIN_NAME="argon-ex"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

STEP_NO=0
STEP_TOTAL=0

step() { STEP_NO=$((STEP_NO + 1)); echo -e "\n${BOLD}${CYAN}==> [${STEP_NO}/${STEP_TOTAL}] $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${DIM}  $1${NC}"; }
warn() { echo -e "${YELLOW}! $1${NC}" >&2; }
fail() { echo -e "${RED}✗ $1${NC}" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 not found on PATH - $2"; }

run_spin() {
    local label="$1"; shift
    if [[ ! -t 1 ]]; then
        echo "  $label…"
        "$@" || fail "$label failed"
        return
    fi
    local log; log="$(mktemp)"
    "$@" >"$log" 2>&1 &
    local pid=$!
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0 start=$SECONDS
    while kill -0 "$pid" 2>/dev/null; do
        i=$(((i + 1) % ${#frames}))
        printf "\r  ${CYAN}%s${NC} %s  ${DIM}%ds${NC}" "${frames:$i:1}" "$label" "$((SECONDS - start))"
        sleep 0.1
    done
    wait "$pid"; local rc=$?
    printf "\r\033[K"
    if [[ $rc -ne 0 ]]; then
        echo -e "${RED}--- last 30 lines of output ---${NC}" >&2
        tail -30 "$log" >&2
        rm -f "$log"
        fail "$label failed"
    fi
    ok "$label  ${DIM}($((SECONDS - start))s)${NC}"
    rm -f "$log"
}

usage() {
    cat <<'EOF'
usage: ./dev-build.sh [setup] [cli] [vscode] [plugin] [--release] [--restart] [--no-restart]

  (no args)    build + install everything: cli, vscode, plugin
  cli          build the Argon Extended CLI -> ~/.local/bin/argon-ex
  vscode       build the VS Code extension (webview + webpack)
  plugin       build the Roblox plugin -> argon-roblox/Argon.rbxm
  setup        one-time: symlink VS Code extension into ~/.vscode/extensions, then exit

  --release    cargo build --release (default: debug)
  --restart    kill any running `argon-ex serve` after a cli build
  --no-restart skip the serve check entirely

flags combine, e.g. ./dev-build.sh cli vscode --release --restart
EOF
}

# ── parse flags ───────────────────────────────────────────────────────────────
BUILD_CLI=true
BUILD_VSCODE=true
BUILD_PLUGIN=true
DO_SETUP=false
RELEASE=false
RESTART_SERVE=ask

EXPLICIT=false
for arg in "$@"; do
    case "$arg" in
        --release)    RELEASE=true ;;
        --restart)    RESTART_SERVE=yes ;;
        --no-restart) RESTART_SERVE=no ;;
        -h|--help|help) usage; exit 0 ;;
    esac
done

if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        case "$arg" in
            cli|vscode|plugin|setup) EXPLICIT=true ;;
        esac
    done
fi

if $EXPLICIT; then
    BUILD_CLI=false
    BUILD_VSCODE=false
    BUILD_PLUGIN=false
    for arg in "$@"; do
        case "$arg" in
            cli)    BUILD_CLI=true ;;
            vscode) BUILD_VSCODE=true ;;
            plugin) BUILD_PLUGIN=true ;;
            setup)  DO_SETUP=true ;;
            --release|--restart|--no-restart) ;;
            -h|--help|help) usage; exit 0 ;;
            *) warn "unknown argument: $arg"; usage; exit 1 ;;
        esac
    done
fi

cd "$ROOT"

# ── setup: symlink extension into ~/.vscode/extensions (run once) ─────────────
if $DO_SETUP; then
    STEP_TOTAL=1
    step "VS Code extension symlink (one-time setup)"
    if [[ -L "$EXT_LINK" ]]; then
        ok "already linked: $EXT_LINK"
    else
        ln -s "$VSCODE_DIR" "$EXT_LINK"
        ok "linked $VSCODE_DIR -> $EXT_LINK"
        info "Reload VS Code window once to pick up the extension."
    fi
    exit 0
fi

# ── count steps ───────────────────────────────────────────────────────────────
STEP_TOTAL=0
$BUILD_CLI    && STEP_TOTAL=$((STEP_TOTAL + 1))
$BUILD_VSCODE && STEP_TOTAL=$((STEP_TOTAL + 1))
$BUILD_PLUGIN && STEP_TOTAL=$((STEP_TOTAL + 1))

# ── preflight ─────────────────────────────────────────────────────────────────
$BUILD_CLI    && need cargo "install Rust: https://rustup.rs"
$BUILD_VSCODE && need npm   "install Node.js: https://nodejs.org"
$BUILD_PLUGIN && need argon-ex "build cli first: ./dev-build.sh cli"
$BUILD_PLUGIN && need wally "install via rokit: rokit add UpliftGames/wally"

if $BUILD_VSCODE && [[ ! -L "$EXT_LINK" ]]; then
    warn "extension not symlinked - run ./dev-build.sh setup first"
fi

OVERALL_START=$SECONDS

# ── 1. Argon CLI ──────────────────────────────────────────────────────────────
if $BUILD_CLI; then
    step "Argon CLI"
    cd "$CLI_DIR"

    if $RELEASE; then
        run_spin "cargo build --release" cargo build --release --bin argon-ex --bin reflection_dump
        BINARY="$CLI_DIR/target/release/$BIN_NAME"
        REFLECT_DUMP="$CLI_DIR/target/release/reflection_dump"
    else
        run_spin "cargo build" cargo build --bin argon-ex --bin reflection_dump
        BINARY="$CLI_DIR/target/debug/$BIN_NAME"
        REFLECT_DUMP="$CLI_DIR/target/debug/reflection_dump"
    fi

    mkdir -p "$BIN_DIR"
    install -Dm755 "$BINARY" "$BIN_DIR/$BIN_NAME"
    ok "installed -> $BIN_DIR/$BIN_NAME"

    # Warn if a stale copy shadows our install
    RESOLVED="$(command -v "$BIN_NAME" || true)"
    if [[ -n "$RESOLVED" && "$RESOLVED" != "$BIN_DIR/$BIN_NAME" ]]; then
        if [[ -w "$RESOLVED" || -w "$(dirname "$RESOLVED")" ]]; then
            install -Dm755 "$BINARY" "$RESOLVED"
            warn "PATH resolves '$BIN_NAME' to $RESOLVED (shadows $BIN_DIR) - updated it too"
        else
            warn "PATH resolves '$BIN_NAME' to $RESOLVED (not writable) - it may be stale"
            warn "put $BIN_DIR first on PATH to use the local build"
        fi
    fi

    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) warn "$BIN_DIR is not on your PATH - the installed '$BIN_NAME' won't be found" ;;
    esac

    info "version: $("$BIN_DIR/$BIN_NAME" --version 2>/dev/null || echo '?')"

    # Generate global reflection catalog for VS Code extension
    mkdir -p "${HOME}/.argon-ex"
    "$REFLECT_DUMP" > "${HOME}/.argon-ex/reflection.json"
    ok "reflection catalog -> ${HOME}/.argon-ex/reflection.json"

    # Kill stale serve process if running (holds old binary in memory)
    if [[ "$RESTART_SERVE" != "no" ]]; then
        mapfile -t SERVE_PIDS < <(pgrep -f "argon-ex serve" 2>/dev/null || true)
        if [[ ${#SERVE_PIDS[@]} -gt 0 ]]; then
            warn "argon-ex serve is running (pid ${SERVE_PIDS[*]}) - still the OLD binary"
            DO_KILL=false
            if [[ "$RESTART_SERVE" == "yes" ]]; then
                DO_KILL=true
            elif [[ -t 0 ]]; then
                read -rp "  kill it now so the next 'argon-ex serve' is fresh? [y/N] " ans
                [[ "$ans" =~ ^[Yy]$ ]] && DO_KILL=true
            fi
            if $DO_KILL; then
                kill "${SERVE_PIDS[@]}" 2>/dev/null || true
                ok "stopped stale serve - rerun 'argon-ex serve' in your project"
            else
                warn "restart manually: kill ${SERVE_PIDS[*]} && argon-ex serve"
            fi
        fi
    fi

    cd "$ROOT"
fi

# ── 2. VS Code extension ──────────────────────────────────────────────────────
if $BUILD_VSCODE; then
    step "VS Code extension"
    cd "$VSCODE_DIR"

    [[ -d node_modules ]] || run_spin "npm install (extension)" npm install

    cd webview-ui
    [[ -d node_modules ]] || run_spin "npm install (webview)" npm install
    run_spin "vite build (webview)" node_modules/.bin/vite build
    cd ..

    run_spin "webpack (extension)" node_modules/.bin/webpack --mode development
    cd "$ROOT"
    info "Ctrl+Shift+P > Developer: Reload Window to pick up changes"
fi

# ── 3. Roblox plugin ─────────────────────────────────────────────────────────
if $BUILD_PLUGIN; then
    step "Roblox plugin"
    cd "$PLUGIN_DIR"

    run_spin "wally install" wally install
    run_spin "argon-ex build" argon-ex build --output Argon.rbxm

    [[ -f "Argon.rbxm" ]] || fail "plugin build did not produce Argon.rbxm"

    # Install to Studio plugins folder
    STUDIO_PLUGINS=""
    if [[ -d "${HOME}/.var/app/org.vinegarhq.Vinegar" ]]; then
        # Flatpak Vinegar detected
        VINEGAR_STUDIO="${HOME}/.var/app/org.vinegarhq.Vinegar/data/roblox-studio"
        if [[ ! -d "$VINEGAR_STUDIO" ]]; then
            warn "Vinegar detected but Roblox Studio data dir missing"
            warn "You must expose the Vinegar Flatpak filesystem and launch Studio at least once:"
            warn "  flatpak override --user --filesystem=home org.vinegarhq.Vinegar"
            warn "  then launch Roblox Studio via Vinegar, close it, and re-run this script"
            ok "built -> $PLUGIN_DIR/Argon.rbxm (not installed)"
            cd "$ROOT"
            return 0 2>/dev/null || true
        fi
        STUDIO_PLUGINS="$VINEGAR_STUDIO/Plugins"
        mkdir -p "$STUDIO_PLUGINS"
    elif [[ -d "${HOME}/.local/share/Roblox/Plugins" ]]; then
        STUDIO_PLUGINS="${HOME}/.local/share/Roblox/Plugins"
    elif [[ -d "${HOME}/Library/Application Support/Roblox/Plugins" ]]; then
        STUDIO_PLUGINS="${HOME}/Library/Application Support/Roblox/Plugins"
    fi

    if [[ -n "$STUDIO_PLUGINS" ]]; then
        cp Argon.rbxm "$STUDIO_PLUGINS/Argon.rbxm"
        ok "installed -> $STUDIO_PLUGINS/Argon.rbxm"
        info "restart Studio to load the new plugin"
    else
        ok "built -> $PLUGIN_DIR/Argon.rbxm"
        warn "could not find Studio Plugins dir - copy Argon.rbxm there manually"
        warn "if using Vinegar (Flatpak): flatpak override --user --filesystem=home org.vinegarhq.Vinegar"
    fi

    cd "$ROOT"
fi

echo -e "\n${BOLD}${GREEN}All done.${NC} ${DIM}($((SECONDS - OVERALL_START))s)${NC}"
