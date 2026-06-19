# JuniperGameJam

Solo entry in the **Juniper Dev** game jam. **7 days from June 19, 2026.** Shipping a
**web (HTML5)** build playable in-browser on **itch.io**.

> **Status:** _pre-theme planning (theme reveal June 19)._ Update this line as we go.

---

## How we work together — READ THIS FIRST

AI is **discouraged for full generation** in this jam, and that matches how I want to
work. You are a **second person / docs-fetcher / debugger / rubber duck**, *not* a code
generator.

**Do:**
- Look up Godot 4.6 API, nodes, and idioms (don't guess — verify).
- Fetch & explain techniques: juice (screenshake, hit-stop, particles), shaders, tweens, sound sourcing.
- Debug *my* code, read errors with me, suggest fixes.
- Write tedious boilerplate I ask for: export config, build scripts, save/load, input maps.
- Gut-check scope. Push back when I'm over-scoping.
- Keep the design log (see below) current.

**Don't:**
- Implement whole features/systems unprompted. Wait for me to ask.
- Write big chunks of game logic for me — I'm here to learn and build it.
- Refactor or "improve" things I didn't ask about.

**Default:** explain over do, small over large, ask before anything big. Match my code style.

---

## The jam

- **Theme** revealed June 19. Treat it as a *constraint the core mechanic embodies*, not decoration. Don't grab the first (everyone's) idea — brainstorm ~10, drop the obvious 3.
- **Deadline:** 7 days. **Submit early on day 7 with buffer** — the web build will surprise us.
- **Platform:** itch.io, HTML5, in-browser.

---

## Scope discipline (this is what kills solo jams)

- **Vertical slice in 2 days, polish for 5.** One core mechanic. "Fun for 60 seconds" first, then make *that* great.
- **Avoid:** save systems, deep procgen, multiplayer, heavy content authoring, anything with a long content pipeline.
- Rough day plan:
  - **D1** theme → lock idea → grey-box prototype of the core mechanic
  - **D2–3** make the core loop actually fun
  - **D4–5** content / levels / difficulty curve
  - **D6** juice (screenshake, SFX, particles, feedback), menus, win/lose states
  - **D7** polish + buffer + **submit early**
- Juice is the highest-ROI work. Same mechanic + screenshake + a sound + a particle pop = feels 10× better.

---

## Tech

- **Godot 4.6.1**, **GL Compatibility** renderer. **Do not switch to Forward+** — it's flaky in browsers.
- Test in the **browser** regularly, not just the editor (GL Compatibility behaves differently).

## Web-build gotchas (know these now, not on day 7)

- **Audio won't play until a user gesture** (browser autoplay policy) → plan a click-to-start screen.
- Keep the build **small** — players bounce on slow loads.
- On the itch embed settings, **enable "SharedArrayBuffer support"** (Godot 4 web needs the COOP/COEP headers).
- Local testing needs those COOP/COEP headers too — `build.sh` serves with them.

---

## Build & deploy

```bash
./build.sh            # export Web preset → push to itch via butler
./build.sh --no-push  # export only (files land in builds/web/), no upload
```

To play-test the web build locally instead, run it from the editor, or serve
`builds/web/` with COOP/COEP headers (Godot 4 web needs them for SharedArrayBuffer).

**Setup status:**
- ✅ git initialized on `main`, remote → `git@github.com:kjbrown-sandbox/juniper-dev-gamejam.git`
- ✅ butler installed (`~/bin/butler`) and logged in
- ✅ itch target wired in `build.sh` → `itchy-dev-games/juniper-dev-gamejam:html5`
  (update `GAME_SLUG` if you rename the page: <https://itchy-dev-games.itch.io/juniper-dev-gamejam>)
- ⬜ On the itch.io game page, **enable "SharedArrayBuffer support"** in embed settings.
- ⬜ First `./build.sh` will create/confirm `export_presets.cfg` with a "Web" preset.

---

## Design log

Keep **`DESIGN_LOG.md`** as we work: decisions made, scope cuts, what's fun / not, running TODO.
**Append, don't rewrite.** This is our shared memory across sessions.
