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
