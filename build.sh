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

# Flags: ./build.sh --no-push  (build + test locally, never prompt to upload)
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

echo ""
echo "Starting local test server at http://localhost:8000"
echo ""

# Bail early if something is already on the port (e.g. a server orphaned by a
# previous run that was SIGKILLed before its cleanup trap could fire).
if lsof -nP -iTCP:8000 -sTCP:LISTEN >/dev/null 2>&1; then
    STALE_PID=$(lsof -nP -tiTCP:8000 -sTCP:LISTEN 2>/dev/null | head -1)
    echo "❌ Port 8000 is already in use (pid ${STALE_PID:-unknown})."
    echo "   Kill it and re-run:  kill ${STALE_PID:-<pid>}"
    exit 1
fi

# Godot 4 web exports need COOP/COEP headers to enable SharedArrayBuffer.
python3 -c "
import http.server, functools

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

s = http.server.HTTPServer(('', 8000), functools.partial(Handler, directory='builds/web'))
s.serve_forever()
" &
SERVER_PID=$!

# Tear the server down no matter how this script ends: normal exit, Ctrl+C
# (SIGINT), kill (SIGTERM), or the terminal window being closed (SIGHUP).
cleanup() {
    if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}
on_signal() {
    echo ""
    echo "Interrupted — shutting down the local server and exiting."
    cleanup
    exit 130
}
trap cleanup EXIT
trap on_signal INT TERM HUP

# Wait until the socket is actually accepting connections before opening the
# browser (Python needs ~0.5s to import + bind; opening too early = "connection
# refused").
echo "Waiting for server to come up..."
for i in $(seq 1 50); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "❌ Server process exited before it could bind to port 8000."
        wait "$SERVER_PID" 2>/dev/null || true
        exit 1
    fi
    if curl -s -o /dev/null "http://localhost:8000/"; then
        break
    fi
    sleep 0.2
    if [ "$i" -eq 50 ]; then
        echo "❌ Server did not become ready within 10s."
        kill "$SERVER_PID" 2>/dev/null || true
        exit 1
    fi
done
echo "Server is up at http://localhost:8000"
open "http://localhost:8000" 2>/dev/null || true

if [ "$PUSH" -eq 0 ]; then
    echo ""
    echo "Build-only mode (--no-push). Server running at http://localhost:8000"
    echo "Press Ctrl+C to stop."
    while true; do sleep 1; done
fi

echo "Test the build in the browser."
echo "  - Press Enter when done   → stops the server, then asks about pushing to itch"
echo "  - Press Ctrl+C any time   → shuts the server down and exits (no push)"
read -r

cleanup

echo ""
read -p "Build looks good? Push to itch? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted. Build is still in builds/web/ if you want to inspect it."
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
