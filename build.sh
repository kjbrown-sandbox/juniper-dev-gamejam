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

# Flags:
#   ./build.sh --no-push   export only, don't upload to itch
#   ./build.sh --serve     export + serve builds/web locally (COOP/COEP headers) and open the
#                          browser to test — no push. Use this to test audio: Godot 4 web audio
#                          misbehaves without the Cross-Origin-Opener/Embedder-Policy headers a
#                          plain file open / bare http.server doesn't send.
PUSH=1
SERVE=0
case "$1" in
    --no-push|-n) PUSH=0 ;;
    --serve|-s)   PUSH=0; SERVE=1 ;;
esac

cd "$(dirname "$0")"

# ── Version string (git if available, timestamp otherwise) ─────────────────
# Requires at least one commit; a freshly-init'd repo has no HEAD yet. The branch/dirty *warning*
# is deferred to the push gate below — exporting and local serving don't care about a dirty tree,
# so we only nag right before actually uploading to itch.
BRANCH=""
DIRTY=""
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if ! git diff-index --quiet HEAD -- 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
        DIRTY="yes"
    fi
    VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "manual-$(date +%Y%m%d-%H%M%S)")
else
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

# ── Local test server (--serve) ────────────────────────────────────────────
# Serve builds/web with the COOP/COEP headers Godot 4 web needs for SharedArrayBuffer (and which a
# bare `python -m http.server` or a file:// open does NOT send), then open the browser. No push.
if [ "$SERVE" -eq 1 ]; then
    PORT=8000
    if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
        echo "❌ Port $PORT is already in use (pid $(lsof -nP -tiTCP:$PORT -sTCP:LISTEN 2>/dev/null | head -1))."
        echo "   Stop that server (or kill the pid) and re-run."
        exit 1
    fi
    echo "Serving builds/web at http://localhost:$PORT  (COOP/COEP headers on)"
    python3 -c "
import http.server, functools
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()
http.server.HTTPServer(('', $PORT), functools.partial(H, directory='builds/web')).serve_forever()
" &
    SERVER_PID=$!
    # Always tear the server down — normal exit, Ctrl+C, kill, or terminal close — so it can't
    # orphan and keep holding the port. (SIGKILL can't be trapped; the port precheck covers that.)
    cleanup() { kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; }
    trap cleanup EXIT
    trap 'echo; echo "Shutting down local server."; cleanup; exit 130' INT TERM HUP
    # Wait for the socket to accept connections before opening the browser (avoids "connection refused").
    for i in $(seq 1 50); do
        kill -0 "$SERVER_PID" 2>/dev/null || { echo "❌ Server exited before it could bind to $PORT."; exit 1; }
        curl -s -o /dev/null "http://localhost:$PORT/" && break
        sleep 0.2
    done
    open "http://localhost:$PORT" 2>/dev/null || true
    echo "Testing in the browser. Press Enter (or Ctrl+C) to stop the server."
    read -r
    cleanup
    trap - EXIT
    exit 0
fi

if [ "$PUSH" -eq 0 ]; then
    echo "Export-only mode (--no-push). Files are in builds/web/."
    exit 0
fi

# ── Pre-push gate: branch/dirty warning (export already succeeded above) ────
# Only nag here, right before uploading — a dirty tree or off-main branch is fine for testing,
# but you usually don't want to ship an un-versioned build to itch.
if [ -n "$BRANCH" ] && { [ "$BRANCH" != "main" ] || [ -n "$DIRTY" ]; }; then
    echo "⚠️  About to push to itch, but:"
    [ "$BRANCH" != "main" ] && echo "   - You're on branch '$BRANCH', not 'main'"
    [ -n "$DIRTY" ] && echo "   - Working tree has uncommitted changes"
    echo ""
    read -p "Push anyway? [y/N] " -n 1 -r
    echo ""
    [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Aborted push. Build is in builds/web/."; exit 1; }
fi

# ── Safety: never ship a debug build ───────────────────────────────────────
# debug_start is an @export, so it can be true via Game.gd's default OR a
# Game.tscn scene override. Refuse to upload if either turns it on.
if grep -Eq 'debug_start[[:space:]]*:?=[[:space:]]*true' Game.gd Game.tscn; then
    echo "❌ Refusing to push: debug_start is set to true."
    echo "   Turn it off before shipping:"
    grep -EnH 'debug_start[[:space:]]*:?=[[:space:]]*true' Game.gd Game.tscn
    echo "   (Build is saved in builds/web/. Re-run after disabling.)"
    exit 1
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
