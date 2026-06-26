# Design Log

Append-only shared memory across sessions. Newest at the bottom.

---

## 2026-06-25 — Art standardization (two-color: purple + cyan)

Collapsed the whole game to a **deep-purple + cyan** palette and reworked several
visuals. All on `main`. Palette lives in new `styles/standard.tres` (pointed at by
`Game.tscn`; the reskin `.tres` files are untouched). New *behavior* is in `Game.gd`.

- **Palette:** cyan = player/trail/sealed rings/light/asteroids; purple = unsealed
  rings + star-dust; enemies = brighter magenta-purple. Dark-purple bg + faint grid.
- **Light → planet laser.** The gate is now a cyan laser blasted radially out of the
  planet through the gate angle (reads from any ring, like light pouring from a window),
  brightening when you're in it. Replaces the old ring-arc + tick.
- **Star dust** (was "squares"): bright-purple diffuse points; HUD label "STAR DUST".
- **Star core** (was "mat" / asteroids loot): HUD label "STAR CORE". Asteroids are now
  cyan diffuse points (like star dust) + their hit counter.
- **Enemies:** magenta cursor/arrow triangles (no outline), tip toward the planet.
  Latched siphoners **pulse** + draw a "sucking" laser from the planet to the cursor.
- **Background grid** brightens near the moon (proximity falloff) — a moving shine.
- **Removed UI:** game timer, enemy-spawn clock + "enemies will spawn" text, speed
  readout, and the top control-hint line. Spawn/economy mechanics unchanged.
  - NOTE: I removed the *whole* enemy-spawn clock (pie + countdown + text), reading
    "remove the timer and the text" as both. Easy to restore the pie if you want the
    telegraph back.
- **R → "Are you sure?"** confirm modal (Y/Enter restart, N/Esc/R cancel; clickable).
  Mid-run only; win/lose still restart immediately. Freezes the sim while open.
- **Pause** uses a two-bar icon (borrowed from Pleenko's `pause.png` glyph): a
  clickable corner button (play-triangle when paused) + a big centered icon overlay.

New tunables on `Game.gd`: `light_beam_reach`, `grid_glow_radius`, `grid_glow_strength`.
Verified by screenshotting the launch screen, a forced mid-game state, and the modal.

## 2026-06-25 — Art-pass iteration (same session, follow-up rounds)

Refined the standardized look from feedback. Net state now:

- **Background:** kept the **purple** grid (the cyan grid was a misstep) on a deep-purple
  gradient. Grid line-shine is **local to a moving source** (short segments, 2D falloff),
  not whole lines lighting up — moderate strength. The shine now follows the **moon AND
  every enemy** (enemies tint it the unsealed-ring purple).
- **Boost light:** dropped the planet-laser idea; it's now a **yellow glowing circle** on
  the ring (`draw_point_glow`), a bit larger than star dust.
- **Moon:** same `draw_point_glow` as the light (size + pulse), kept cyan.
- **Tail:** flat cyan dots (tried a glow, too strong — removed).
- **Enemies:** plain **skinny triangle outline** (no notch/fill), outline = unsealed-ring
  thickness, colored unsealed-ring **purple** (was magenta); pulse + siphon beam kept.
- **Core:** replaced the rect bar and the (unclear) donut. Core is a filled disc, **no
  outline**, whose color+emission ramp dark→light-color by `core / core_color_max` (=80),
  so it brightens/darkens with health. A **Pleenko-style rounded fill healthbar**
  (`draw_fill_bar`/`_capsule`) sits beneath showing `core / core_cap`.
- **Naming:** "STAR CORE" → **COMETS** (HUD + shop + cost unit), asteroid-kill popup
  "+MAT" → "+1 COMET". (Planet "CORE x/y" and core-capacity upgrades stay "core".)
- **Font:** all text swapped to **Quantico** (`assets/fonts/Quantico/`, `@export ui_font`).

New tunables: `core_color_max`. Removed `light_beam_reach`. Each round verified via
throwaway screenshot scripts (launch, mid-game, shop modal, enemy close-up).

---

## Day 7 (Jun 25) — Main menu (own scene)

Added **`MainMenu.tscn` + `MainMenu.gd`** as the new `main_scene` (was `Game.tscn`). Own scene
per request (not a Game.gd phase). Node2D root draws the game's look — `standard.tres` palette,
neon grid drawn **zoomed-in** (`MENU_GRID_MULT 2.6` → big cells = "a tiny piece"), and a glowing
**hero moon** (the object that will later "fall" into the game) that shines the grid patch under
it, reusing the committed `_grid_shine` math. UI is **Control nodes built in code** (CanvasLayer):
centered `PLAY`/`SETTINGS` (pleenko-style StyleBoxFlat hover/press), and a `SETTINGS` panel with a
0–100 **VOLUME** `HSlider` → `AudioServer.set_bus_volume_db(0, …)` (Master). Menu music =
`assets/sound/magic space.mp3`, started on first gesture (web autoplay). `PLAY` → hard-cut
`change_scene_to_file("res://Game.tscn")`.

- **Volume is session-only** (no save system — scope discipline). Add a `ConfigFile` later if wanted.
- **Deferred (waiting on the other agent's final cell-lighting):** cursor-driven grid shine — hook
  left in `_draw()` (`_grid_shine(... get_local_mouse_position() ...)`).
- **Deferred:** the seamless moon-fall + zoom-out hand-off into `Game.tscn` (currently a hard cut).

### Menu update — fall transition, title, audio

- **Title** → "CORE MECHANICS" (`TITLE` const).
- **Buttons** moved to lower-middle (`_menu_box.anchor_top = 0.40`) so they clear the moon glow.
- **Moon-fall transition** (`state` menu→intro): on PLAY the hero moon shrinks and the camera
  pulls back, revealing ring 0 + planet (drawn from mirrored Game constants), landing the moon on
  the top of ring 0 = Game's exact first frame, then cuts to `Game.tscn` (short crossfade absorbs
  the cut). Geometry note: game moon starts at the *top* of ring 0, so this is a zoom-out reveal /
  settle, not a literal downward drop (a true drop would be a `Game.gd` intro cinematic).
- **Audio:** menu theme = `Space Sprinkles.mp3` (plays on launch; web waits for first gesture).
  Fades to silent over the fall (player `volume_db` ramp). Volume slider still drives Master bus.
- **PENDING (Game.gd — other agent's file):** play `magic space.mp3` when the first SPACE-hit lands
  on ring 1 in-game. Not done here to avoid colliding with their active edits.

### Menu polish round 2

- **Darkening removed** — deleted the end-of-transition crossfade entirely.
- **Fall reworked** — moon now rises above the revealed ring/core (pull-back), then drops
  STRAIGHT DOWN onto the top of ring 0 (game start), accelerating with a small settle-bounce.
  x stays centred (no sideways drift). Lands on the game's exact first frame, no fade.
- **Grid aligned to the moon** — grid is phased (`fposmod`) so lines cross dead-centre on the
  moon at rest, so it no longer reads as off-centre. During the fall the grid anchors to centre
  (stable) while the moon still lights the patch it passes.
- **Volume slider restyled** — cyan track + filled bar (matches the palette), grabber 2× size
  (generated circle texture), and a live **NN%** readout to the right of the slider.
- Menu title is "CORE MECHANICS".

### Menu polish round 3 — seamless drop onto the ring

- Moon now **drops straight down onto the ring's TOP edge** (= the game's exact moon-start spot,
  `centre + (0,-base_radius)*z_end`), so the cut into Game.tscn is seamless (verified: intro's last
  frame == game's first frame, moon in the identical position). No rise, x dead-centre.
- Menu moon moved HIGH (`MENU_MOON_FRAC 0.08`) so it starts above the ring's top and only falls;
  title moved below it. Mirrored consts fixed to match the game (`MOON_RADIUS 10`).
- The world **zooms in** (ring + core grow from small, their top rising to meet the falling moon) —
  this is what lets the moon start high/on-screen and land seamlessly; a literal zoom-OUT would need
  the moon to start off-screen. Slow (4s). Grid reverted to from-0 (matches the in-game grid).
- Tiny residual pops at the cut (game adds a yellow launch-boost glow + "PRESS SPACE TO LAUNCH"); the
  moon itself does not move.

### Menu polish round 4 — virtual camera, moon below title

- Reworked the intro as a **virtual camera** (focus + zoom) that interpolates from the menu framing
  to the game's first frame. The moon is fixed at the world ring-top, so p=1 == Game.tscn's opening
  exactly → seamless by construction.
- Menu now frames the moon **below the title** (`MENU_MOON_FRAC 0.34`, above centre); ring/core are
  off-screen (camera zoomed in) and sweep in as the camera pulls back.
- Camera timing is **cubic ease-out** (fast at the start, slows into the landing).
- Removed the old screen-space drop; `_draw_scene()` now serves both menu (p=0) and intro.

### Balancing & feedback pass (Jun 25)

- **Ring nav is interruptible** — UP/DOWN now retarget the glide from the moon's current
  radius (`move_r0`) instead of being locked out until a traverse finishes. The seal
  auto-launch uses the same continue-from-here radius.
- **"+1 stardust"** popup on square grab (was a bare "+1").
- **Combo reworked into a straight push multiplier** — combo only climbs on un-missed light
  hits; gain = base × (1 + (combo-1)·0.25), so combo 3 boosts a light 1.5×. Dropped the old
  "every 3rd hit" bonus.
- **MISS power-down** — whiffing SPACE shows "MISS", breaks the combo, and powers the moon
  down for 1.5s: emissions cut for 1s, ramp back over the next 0.5s, SPACE locked the whole
  time. (Launch press is exempt.) Replaces the old 0.2s miss cooldown.
- **Enemies are neon red and "beep"** — recolored in `standard.tres`; each enemy pings a red
  expanding/fading ring once per second (reuses the `flashes` system with a per-flash `col`).
- **Core shows health + tweens** — displays `N/5` in its center, glows bright yellow with
  emission at full (energy now keyed to `core/core_cap`), fades to the menu's dark-purple
  `planet_sick` (no emission) as it dies, matching the intro hand-off.

### Core polish — centered readout, no bar, launch flare

- **`N/5` is now vertically centered** in the core (baseline offset via the font's
  ascent/descent at the real 2× draw size; it was anchored at the baseline and rode high).
- **Removed the core health bar** under the disc — the centered number carries it.
- **Launch flare** — the core starts dead (`core_lit = 0`, dark-purple, matching the menu
  hand-off) and flares up to full over `core_flare_time` (0.35s) on the first SPACE, with an
  expanding yellow light ring + particle burst. Fixes the core popping straight to full and
  restores the seamless menu→game core match.

### New upgrade-menu scene (`UpgradeMenu.tscn` / `.gd`)

- **Standalone scene**, not yet wired into `Game.gd` (kept separate so it's editable in
  parallel). Run it on its own (F6) to preview; the host configures it via
  `configure(unlocked, stardust, stardust_max)` + `open()` and listens for the
  `purchased(section_id, upgrade_id)` / `closed` / `no_upgrades` signals. It draws itself in
  the game's purple+cyan / Quantico look (a `Control` with custom `_draw`, like the rest).
- **Five sections, two upgrades each** (mockup layout): top row Core / Boost / Stardust shows
  once the Stardust ring is unlocked (`unlocked >= 2`); bottom row Attack / Comet appears and
  grows the panel taller once the asteroid ring is unlocked (`unlocked >= 3`). Upgrades:
  Core = max / refill-rate _(stub — mechanic TBD)_; Boost = strength / frequency;
  Stardust = max-capacity / spawn-rate; Attack = Horns (+1 dmg) / Ram (whiff damage);
  Comet = Armor / +total asteroids. Costs/levels are placeholder; the host applies the real
  effect on `purchased`.
- **Keyboard nav** spatially jumps to the nearest BUYABLE card in the pressed direction
  (arrows or WASD); you only ever land on a card you can afford. **SPACE buys**, but is armed
  only after a 1 s delay so a stray light-boost press at open doesn't buy. **B / Esc** backs
  out. If nothing is buyable, `open()` refuses and flashes **"No upgrades available"**.
- Top-left readout **"Stardust: x/y"** with a glowing purple dot (same `draw_point_glow`
  recipe as the rings). Renamed the in-HUD/modal **"STAR DUST"** label to **"STARDUST"**.
