#!/usr/bin/env bash
# Install mpv-vlc-redesign into your mpv config folder.
#
#   ./install.sh               copy the files
#   ./install.sh --link        symlink instead (handy if you want `git pull` to update it)
#   ./install.sh --thumbfast   also download thumbfast.lua for seekbar thumbnails
#   ./install.sh --dir PATH    install somewhere else than ~/.config/mpv
#
# Existing mpv.conf / input.conf / vlcui.conf are backed up as *.bak-<date> first.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${MPV_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/mpv}"
LINK=0
THUMBFAST=0

while [ $# -gt 0 ]; do
    case "$1" in
        --link) LINK=1 ;;
        --thumbfast) THUMBFAST=1 ;;
        --dir) shift; DEST="$1" ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

if ! command -v mpv >/dev/null 2>&1; then
    echo "warning: mpv was not found in PATH. Install mpv 0.39 or newer first." >&2
fi

stamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST/scripts" "$DEST/script-opts" "$DEST/fonts"

backup() {
    local f="$1"
    if [ -e "$f" ] || [ -L "$f" ]; then
        if [ -L "$f" ] && [ "$(readlink "$f")" = "$2" ]; then return; fi
        if [ -f "$f" ] && [ -f "$2" ] && cmp -s "$f" "$2"; then return; fi
        mv "$f" "$f.bak-$stamp"
        echo "  backed up $(basename "$f") -> $(basename "$f").bak-$stamp"
    fi
}

place() { # place <source> <destination>
    local src="$1" dst="$2"
    backup "$dst" "$src"
    if [ -e "$dst" ] || [ -L "$dst" ]; then return; fi
    if [ "$LINK" = 1 ]; then ln -s "$src" "$dst"; else cp -r "$src" "$dst"; fi
}

echo "Installing into $DEST"
place "$SRC/mpv.conf" "$DEST/mpv.conf"
place "$SRC/input.conf" "$DEST/input.conf"
place "$SRC/script-opts/vlcui.conf" "$DEST/script-opts/vlcui.conf"

# the script folder is replaced as a whole (it holds no user data)
if [ -e "$DEST/scripts/vlcui" ] || [ -L "$DEST/scripts/vlcui" ]; then
    rm -rf "$DEST/scripts/vlcui"
fi
if [ "$LINK" = 1 ]; then ln -s "$SRC/scripts/vlcui" "$DEST/scripts/vlcui"; else cp -r "$SRC/scripts/vlcui" "$DEST/scripts/vlcui"; fi

for font in "$SRC"/fonts/*; do
    cp -f "$font" "$DEST/fonts/"
done

if [ "$THUMBFAST" = 1 ]; then
    echo "  downloading thumbfast.lua (seekbar thumbnails, by po5)"
    curl -fsSL -o "$DEST/scripts/thumbfast.lua" https://raw.githubusercontent.com/po5/thumbfast/master/thumbfast.lua
fi

echo "Done. Start mpv and press F1 for the keyboard shortcuts."
