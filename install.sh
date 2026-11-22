#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_DIR/src"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/appimage-launcher"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
RESET_SETTINGS=0
ONLY_INSTRUCTIONS=0

if { [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; } || [[ -n "${FORCE_COLOR:-}" ]]; then
    ESC=$'\033'
    RST="${ESC}[0m"
    BOLD="${ESC}[1m"
    DIM="${ESC}[2m"
    RED="${ESC}[31m"
    GRN="${ESC}[32m"
    YEL="${ESC}[33m"
    BLU="${ESC}[34m"
    MAG="${ESC}[35m"
    CYN="${ESC}[36m"
else
    ESC="" RST="" BOLD="" DIM="" RED="" GRN="" YEL="" BLU="" MAG="" CYN=""
fi

info() { printf '%s==>%s %s%s%s\n' "$BLU$BOLD" "$RST" "$BOLD" "$*" "$RST"; }
ok()   { printf ' %s✔%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf ' %s!%s %s\n' "$YEL" "$RST" "$*" >&2; }
die()  { printf ' %s✘%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: ./install.sh [options]

  --dest DIR          install the Quickshell config to DIR
                      (default: ${DEST})
  --bin-dir DIR       install the appimage-launcher command to DIR
                      (default: ${BIN_DIR})
  --reset-settings    overwrite an existing LauncherSettings.qml
  --instructions      only print the Hyprland Lua instructions
  -h, --help          show this help
EOF
}

while (($#)); do
    case "$1" in
        --dest)           DEST="${2:?--dest needs a directory}"; shift 2 ;;
        --bin-dir)        BIN_DIR="${2:?--bin-dir needs a directory}"; shift 2 ;;
        --reset-settings) RESET_SETTINGS=1; shift ;;
        --instructions)   ONLY_INSTRUCTIONS=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                usage >&2; die "unknown option: $1" ;;
    esac
done

paint_lua() {
    if [[ -z "$ESC" ]]; then
        cat
        return
    fi
    awk -v DIM="$DIM" -v RST="$RST" -v GRN="$GRN" -v CYN="$CYN" -v MAG="$MAG" -v YEL="$YEL" '
    function paint(line,    out, i, j, n, c, rest, tok) {
        out = ""; i = 1; n = length(line)
        while (i <= n) {
            c = substr(line, i, 1)
            if (substr(line, i, 2) == "--") {
                out = out DIM substr(line, i) RST
                break
            }
            if (c == "\"") {
                j = index(substr(line, i + 1), "\"")
                if (j == 0) j = n - i
                out = out GRN substr(line, i, j + 1) RST
                i += j + 1
                continue
            }
            rest = substr(line, i)
            if (match(rest, /^[A-Za-z_][A-Za-z0-9_.]*/)) {
                tok = substr(rest, 1, RLENGTH)
                if (tok ~ /^hl\./) out = out CYN tok RST
                else if (tok ~ /^(local|true|false|function|end|for|do)$/) out = out MAG tok RST
                else out = out tok
                i += RLENGTH
                continue
            }
            if (match(rest, /^[0-9]+(\.[0-9]+)?/)) {
                out = out YEL substr(rest, 1, RLENGTH) RST
                i += RLENGTH
                continue
            }
            out = out c
            i++
        }
        return out
    }
    { print paint($0) }'
}

print_instructions() {
    local bin="$BIN_DIR/appimage-launcher"
    local snippet
    read -r -d '' snippet <<'LUA' || true
-- ~/.config/hypr/hyprland.lua

-- Floating search box (the title must match LauncherSettings.qml)
hl.window_rule({
    name  = "appimage-launcher",
    match = { title = "^appimage-launcher$" },

    float       = true,
    center      = true,
    rounding    = 12,
    border_size = 2,

    -- size    = "420 320",
    -- size    = { "monitor_w * 0.3", "monitor_h * 0.35" },
    -- opacity = "0.95 0.95",
})

-- Open it with SUPER + A
hl.bind("SUPER + A", hl.dsp.exec_cmd("@BIN@"))

-- Scan another folder (default: ~/Applications)
-- hl.env("APPIMAGE_DIR", "@HOME@/Apps")
LUA
    snippet="${snippet//@BIN@/$bin}"
    snippet="${snippet//@HOME@/$HOME}"

    printf '\n%s%s Hyprland setup %s %s(Lua config, Hyprland 0.55+)%s\n\n' \
        "$BOLD" "$CYN" "$RST" "$DIM" "$RST"
    printf '%s\n' "$snippet" | paint_lua | sed 's/^/    /'

    printf '\n%s%s Customize %s\n\n' "$BOLD" "$MAG" "$RST"
    printf '  %sLook, size, behavior%s  edit %s%s/LauncherSettings.qml%s\n' \
        "$BOLD" "$RST" "$CYN" "$DEST" "$RST"
    printf '  %sWindow placement%s      change the %shl.window_rule%s above, then %shyprctl reload%s\n' \
        "$BOLD" "$RST" "$CYN" "$RST" "$CYN" "$RST"
    printf '  %sInitial size%s          %swidth%s / %sheight%s in LauncherSettings.qml,\n' \
        "$BOLD" "$RST" "$YEL" "$RST" "$YEL" "$RST"
    printf '                        or %ssize%s in the window rule (the rule wins)\n' "$YEL" "$RST"
    printf '  %sColors, fonts%s         the color and font properties in LauncherSettings.qml\n' \
        "$BOLD" "$RST"
    printf '  %sTry it now%s            %s%s%s\n\n' "$BOLD" "$RST" "$GRN" "$bin" "$RST"
}

if ((ONLY_INSTRUCTIONS)); then
    print_instructions
    exit 0
fi

info "Checking requirements"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
ok "python3"
if command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1; then
    ok "quickshell"
else
    warn "quickshell not found in PATH; install it before running the launcher"
fi
command -v hyprctl >/dev/null 2>&1 || warn "hyprctl not found; Hyprland does not seem to be installed"
[[ -f "$SRC_DIR/shell.qml" ]] || die "missing $SRC_DIR/shell.qml; run this script from the repository root"

info "Installing"
mkdir -p "$DEST/scripts" "$BIN_DIR"
install -m 0644 "$SRC_DIR/shell.qml" "$DEST/shell.qml"
install -m 0755 "$SRC_DIR/scripts/appimage-index.py" "$DEST/scripts/appimage-index.py"
ok "config   $DEST"

settings="$DEST/LauncherSettings.qml"
if [[ -f "$settings" ]] && ((RESET_SETTINGS == 0)); then
    if cmp -s "$SRC_DIR/LauncherSettings.qml" "$settings"; then
        ok "settings unchanged"
    else
        install -m 0644 "$SRC_DIR/LauncherSettings.qml" "$settings.dist"
        ok "settings kept (new defaults saved as LauncherSettings.qml.dist)"
    fi
else
    install -m 0644 "$SRC_DIR/LauncherSettings.qml" "$settings"
    rm -f "$settings.dist"
    ok "settings written"
fi

q_dest="$(printf '%q' "$DEST")"
cat > "$BIN_DIR/appimage-launcher" <<EOF
#!/usr/bin/env bash
dest=$q_dest
if command -v qs >/dev/null 2>&1; then qs_bin=qs; else qs_bin=quickshell; fi
lock="\${XDG_RUNTIME_DIR:-/tmp}/appimage-launcher.lock"
if command -v flock >/dev/null 2>&1; then
    exec flock -n "\$lock" "\$qs_bin" -p "\$dest" "\$@"
fi
exec "\$qs_bin" -p "\$dest" "\$@"
EOF
chmod 0755 "$BIN_DIR/appimage-launcher"
ok "command  $BIN_DIR/appimage-launcher"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in PATH; use the full path in your bind" ;;
esac

printf '\n%s%s Installed %s\n' "$BOLD" "$GRN" "$RST"
print_instructions
