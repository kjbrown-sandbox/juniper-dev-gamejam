#!/bin/bash
set -e

# ── CONFIG ─────────────────────────────────────────────────────────────────
# Godot + butler are auto-detected from PATH; override with env vars if needed:
#   GODOT=/path/to/godot BUTLER=/path/to/butler ./build.sh
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
BUTLER="${BUTLER:-$(command -v butler || echo "$HOME/bin/butler")}"

EXPORT_PRESET="Web"
EXPORT_OUTPUT="builds/web/index.html"

# ── itch.io upload target (https://itchy-dev-games.itch.io/juniper-dev-gamejam) ──
ITCH_USER="itchy-dev-games"   # your itch.io username
GAME_SLUG="juniper-dev-gamejam"   # the game's URL slug (update if you rename the page)
# ───────────────────────────────────────────────────────────────────────────
ITCH_TARGET="${ITCH_USER}/${GAME_SLUG}:html5"

# Flags: ./build.sh --no-push  (export only, don't upload to itch)
PUSH=1
[[ "$1" == "--no-push" || "$1" == "-n" ]] && PUSH=0

cd "$(dirname "$0")"

# ── Version string (git if available, timestamp otherwise) ─────────────────
# Requires at least one commit; a freshly-init'd repo has no HEAD yet.
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    DIRTY=""
    if ! git diff-index --quiet HEAD -- 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        DIRTY="yes"
    fi
    if [ "$BRANCH" != "main" ] || [ -n "$DIRTY" ]; then
        echo "⚠️  Heads up:"
        [ "$BRANCH" != "main" ] && echo "   - You're on branch '$BRANCH', not 'main'"
        [ -n "$DIRTY" ] && echo "   - Working tree has uncommitted changes"
        echo ""
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo ""
        [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Aborted."; exit 1; }
    fi
    VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "manual-$(date +%Y%m%d-%H%M%S)")
else
    echo "ℹ️  No git history yet — skipping branch/dirty checks. (Make an initial commit when ready.)"
    VERSION="manual-$(date +%Y%m%d-%H%M%S)"
fi
echo "Building version: $VERSION"

# ── Export ─────────────────────────────────────────────────────────────────
if [ ! -x "$GODOT" ] && ! command -v "$GODOT" >/dev/null 2>&1; then
    echo "❌ Godot not found at: $GODOT"
    echo "   Set it explicitly:  GODOT=/path/to/godot ./build.sh"
    exit 1
fi

mkdir -p builds/web
echo "Exporting '$EXPORT_PRESET' preset..."
"$GODOT" --headless --export-release "$EXPORT_PRESET" "$EXPORT_OUTPUT"
echo "Export complete → $EXPORT_OUTPUT"

if [ "$PUSH" -eq 0 ]; then
    echo "Export-only mode (--no-push). Files are in builds/web/."
    exit 0
fi

# ── Push to itch via butler ────────────────────────────────────────────────
if [[ "$ITCH_USER" == "REPLACE_ME" || "$GAME_SLUG" == "REPLACE_ME" ]]; then
    echo "❌ ITCH_USER / GAME_SLUG not set. Edit the CONFIG block at the top of build.sh,"
    echo "   then re-run. (Build is saved in builds/web/.)"
    exit 1
fi
if [ ! -x "$BUTLER" ] && ! command -v "$BUTLER" >/dev/null 2>&1; then
    echo "❌ butler not found at: $BUTLER"
    echo "   Install:  https://itch.io/docs/butler/installing.html"
    echo "   Then log in once:  butler login"
    exit 1
fi

echo "Pushing to itch.io ($ITCH_TARGET)..."
"$BUTLER" push builds/web "$ITCH_TARGET" --userversion "$VERSION"

echo "Done. Check status:  $BUTLER status ${ITCH_USER}/${GAME_SLUG}"
