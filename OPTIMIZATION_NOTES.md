# Optimization notes (review pass, 2026-06-26)

Read-through of the whole game looking for repeated draws, costly per-frame work,
dead code, and web load size. Nothing changed — this is a findings list, ordered by
bang-for-buck. Each item has **impact / effort / risk** so you can cherry-pick.

Context that matters: the game is **immediate-mode** — `queue_redraw()` fires every
frame, so `_draw()` runs at 60fps and every `draw_*` call is a per-frame cost. Target is
**WebGL / GL Compatibility**, where *draw-call count* is the main enemy (lots of tiny
primitives blow Godot's 2D batching and each one has real overhead in the browser).

The live skin on `main` is `styles/standard.tres`, and it has **`enable_grid = true`**
**and `glow_enable = true`**. So the two heaviest paths below are both ON in what ships.

---

## TIER 1 — frame-rate hotspots (do these first)

### 1. `_grid_shine()` is the single biggest cost, and it scales with enemy count
`Game.gd:1802` (and the moon+enemy fan-out at `Game.gd:1566`).

Every frame we shine the grid around **the moon AND every threat** (`glow_pts` is built
with one entry per enemy at `Game.gd:1567`). `_grid_shine` is a double nested loop:

- standard.tres: `grid_spacing = 72`, `grid_glow_radius = 240`, `step = 16`.
- Per glow point ≈ `2 × (480/72 cols) × (480/16 rows)` ≈ **~420 cells**, most of which
  emit a `draw_line`. Call it **~320 draw_line per glow point**.
- Moon + a wave of 5 enemies = 6 points = **~1,900 `draw_line` per frame**, plus ~840
  `distance_to()` that draw nothing. At 60fps that's ~114k line draws/sec.

This is almost certainly what will tank framerate on a mid-tier laptop in a browser once
enemies are on screen. Fixes, cheapest first:

- **Only shine the grid under the moon, not enemies.** Drop the loop at
  `Game.gd:1567`. Enemies are small and far out on ring 3 — the shine barely reads on
  them. ~6× fewer shine passes in the worst case. *Impact: huge / Effort: 1 line / Risk: cosmetic only.*
- **Or cap glow points** (moon + nearest 1–2 enemies).
- **Raise `step`** from 16 → 24 (`Game.gd:1803` area). ~2× fewer segments, slightly
  chunkier shine. *Impact: ~2× / Effort: trivial.*
- **Shrink `grid_glow_radius`** 240 → ~160. Cost is quadratic in radius, so this is a
  big lever. *Impact: ~2× / Effort: trivial (it's an @export at `Game.gd:130`).*

The same function is duplicated in `MainMenu.gd:176` (`MENU_GLOW_RADIUS = 320`, even
bigger) but it only runs on the menu with a single shine point, so it's far less urgent.

### 2. Fake-bloom glow multiplies every ring / line / point by 5–7×
`draw_glow_arc` `Game.gd:1894`, `draw_glow_line` `Game.gd:1904`, `draw_point_glow` `Game.gd:1916`.

standard.tres has `glow_layers = 5`, so:

- **Rings**: each *sealed* ring is `draw_glow_arc` = 6 arcs × `96` segments = **~576 line
  segments per ring**, up to ~1,700 across 3 rings (`Game.gd:1579`). The arc point count
  is hardcoded `96` at `Game.gd:1579/1581`.
- **`draw_point_glow`** always draws **7 circles** (5 glow + mid + core), regardless of
  `glow_enable`, for *every* square, asteroid, light, spawning mote, refill mote, and the
  moon. `layers := 5` hardcoded at `Game.gd:1917`.

Levers (all low-risk, mostly cosmetic):

- Drop `glow_layers` 5 → 3 in `standard.tres`. The outer two halos are nearly invisible
  (alpha falls off as `(1-lt)²`). *Impact: ~30–40% off all glowed draws / Effort: 1 value.*
- Drop the ring arc segment count 96 → 64 at `Game.gd:1579` and `:1581`. At the zoom
  levels used you won't see facets. *Impact: ~33% off ring draws / Effort: 2 numbers.*
- Make `draw_point_glow`'s `layers` honor a smaller count (e.g. 3). *Impact: medium.*

### 3. Comet tail can hit 2,000 individual `draw_circle` per frame
Emit at `Game.gd:884–890`, cap `comet.size() > 2000` at `Game.gd:900`, draw loop
`Game.gd:1584–1592`.

Each tail particle is its own `draw_circle`. At high speed the cap (2,000) is reachable,
and even mid-run it's commonly several hundred. That's hundreds–thousands of tiny filled
polys every frame.

- **Lower the cap** 2000 → ~600–800. With `tail_life = 2.5` and the alpha ease-out, the
  oldest particles are already near-invisible — you won't see the difference. *Impact:
  large at speed / Effort: 1 number / Risk: none.*
- Optionally raise `comet_emit_px` (10 → 14) so fewer particles are laid per unit
  distance (`Game.gd:884`). *Impact: medium.*
- Bigger refactor (probably not worth it for the jam): draw the tail as one
  `draw_polyline` / a `MultiMeshInstance2D` instead of N circles.

---

## TIER 2 — per-frame CPU (GDScript-side)

### 4. `tail_span()` iterates the comet array 2× per frame
`Game.gd:605`, called at `:782` (`display_tail`) and again at `:717` inside
`try_seal()`. Each call walks `comet` (up to 2,000 dicts, with `.get()` lookups).

- Compute it **once per frame**, cache, reuse in both spots. *Impact: small–medium /
  Effort: small / Risk: low.* (Combine with #3's smaller cap and this mostly disappears.)

### 5. `.filter()` with a fresh lambda every frame allocates garbage
`particles` `Game.gd:816`, `popups` `:820`, `flashes` `:823`, `flying` `:971`,
`asteroids` `:1005/1382`, `threats` (`cull_threats` `:1075`).

Each `filter()` allocates a new Array **and** a new Callable every frame. Not a CPU
cliff, but it's steady allocator churn → GC pressure → frame-time spikes on web.

- Replace the hot ones (`particles`, `popups`, `flashes`) with reverse-index in-place
  removal (`for i in range(n-1,-1,-1): if dead: arr.remove_at(i)`). *Impact: small /
  Effort: medium / Risk: low.* Lower priority than Tier 1.

### 6. `get_viewport_rect()` / `screen_center()` called many times per `_draw`
`Game.gd:550,554` and ~8 call sites (`:1719,1750,1763,2002,2107,...`).

`screen_center()` itself calls `get_viewport_rect()`. Cheap individually, but it's called
repeatedly within one frame across helpers.

- Cache `vp`/`center` once at the top of `_draw()` and pass down. *Impact: tiny / Effort:
  small / Risk: low.* Nice-to-have, not urgent.

### 7. Per-frame RNG allocation in reskin backgrounds
`_draw_starfield` `Game.gd:1855`, `_draw_shooting_stars` `:1834`, `_draw_treeline` `:1870`
each do `RandomNumberGenerator.new()` + reseed **every frame**.

- **Not active on `standard.tres`** (starfield/shooting-stars/treeline are off), so this
  is only a problem on the `synthwave`/reskin branches. If any reskin ships, hoist the RNG
  to a member and reseed once. *Impact: low / Effort: small.*

### 8. Physics Area2D pool for light hits is heavier than needed
`sync_light_areas()` `Game.gd:636`, used only by `get_overlapping_areas()` in
`try_boost()` `Game.gd:1295`.

You maintain 1 `Area2D` per light + 1 moon `Area2D`, repositioned every frame, just to do
a circle-overlap test you could do with a `distance_to` loop (there are only ~1–2 lights).
The physics nodes add a physics-server round-trip and frame-lag on overlap results.

- Replace with a direct distance check against each light. *Impact: low–medium / Effort:
  medium / Risk: medium* (it's load-bearing for the shockwave-on-aligned-lights feel —
  test the boost timing after). Optional.

---

## TIER 3 — web load size (players bounce on slow loads — see CLAUDE.md)

Build is **45 MB**: `index.wasm` 37.7 MB (engine, mostly fixed) + `index.pck` 9.4 MB.
The `.pck` is dominated by audio:

- `assets/sound/Space Sprinkles.mp3` = **6.5 MB**
- `assets/sound/magic space.mp3` = **2.2 MB**
- = **8.7 MB of audio**, i.e. basically the entire `.pck`.

Actions:

- **Re-encode both MP3s to a lower bitrate** (e.g. 96–128 kbps CBR, or mono if they're
  not truly stereo). Easily halves audio → shaves ~4 MB off the download. *Impact: big on
  load time / Effort: small / Risk: none (just listen to confirm quality).*
- The 37 MB wasm is the Godot web template. Real reduction means a custom build with
  modules stripped — **not worth it for a 7-day jam.** Note it, move on.
- Make sure itch "SharedArrayBuffer support" is on (it's in your CLAUDE.md checklist) so
  the COOP/COEP headers let the wasm stream.

---

## TIER 4 — dead code (no runtime cost, but it's ~140 lines of confusion)

The **entire old in-file shop** is dead — replaced by the `UpgradeMenu` scene. Nothing
calls `draw_shop_modal()`, so the data it reads is never displayed:

- `econ_nodes()` `Game.gd:321`, `battle_nodes()` `:348`, `visible_nodes()` `:372`,
  `make_shops()` `:383`, `buy()` `:1522`, `draw_shop_modal()` `:2202`,
  `_modal_section()` `:2240`, plus the `shop_sq` / `shop_bt` vars (`:247–248`).
- `make_shops()` *is* still called from `reset()` (`:482`) and `buy()` (`:1555`), so it
  runs, but its output (`shop_sq`/`shop_bt`) is only consumed by the unused
  `draw_shop_modal`. Safe to delete the whole cluster.

*Impact: 0 perf, but removes a dead currency/upgrade tree that can drift out of sync with
the real one in `UpgradeMenu.gd`. Effort: medium (careful delete). Risk: low — grep first
to confirm no stray refs.*

Other smaller dead/unused bits flagged in comments already: `comet_emit_step`,
`combo_every` / `combo_boost_mult` / `combo_step` (`Game.gd:46,78–80`),
`reach_level`/`ereach*` ladder (stuck at 0, noted at `Game.gd:240/576`). Harmless; tidy if
you touch the area.

---

## TIER 5 — micro / nitpick (only if you're bored)

- `_draw_vignette()` `Game.gd:1988` stacks **40** `draw_rect` outlines every frame while
  the core is low. 24 steps would look identical. Only fires in the danger state.
- `Icon.recolored()` `icon.gd:8` and `MainMenu._make_grabber()` `MainMenu.gd:487` do
  per-pixel double loops, but **once** at startup — fine, leave them.
- Color temporaries (`var gc := col; gc.a = …`) everywhere are value-type copies — cheap,
  ignore.

---

## Suggested quick-win order (≈30 min, all low-risk, biggest gains)

1. **#1**: delete the enemy entries from `glow_pts` (`Game.gd:1567`) → moon-only grid
   shine. *(Biggest single win.)*
2. **#1**: `grid_glow_radius` 240 → 160 (`Game.gd:130`); `step` 16 → 24 (`Game.gd:1803`).
3. **#3**: comet cap 2000 → 700 (`Game.gd:900`).
4. **#2**: `glow_layers` 5 → 3 in `standard.tres`; ring arc points 96 → 64
   (`Game.gd:1579/1581`).
5. **#9 (Tier 3)**: re-encode the two MP3s at ~112 kbps.

That set should noticeably lift in-browser framerate during enemy waves and trim several
MB off the download, with no gameplay or meaningful visual change. Test in the **browser**
(not just the editor) per CLAUDE.md — GL Compatibility batching behaves differently there.
