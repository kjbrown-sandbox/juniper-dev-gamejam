# SFX manifest

Drop a file named `<name>.wav` (or `.ogg` / `.mp3`) in this folder and it plays automatically —
the call sites are already wired (via the `Sfx` autoload). Missing files are silent no-ops, so
you can fill these in one at a time. Names are matched exactly (case-sensitive).

For the two **loops** (`beam`, ...) set the file to loop in its Godot import settings.

**Filled so far** (Helton Yan's "Pixel Combat"): boost, boost_perfect, pickup, square_ready,
light_ready, seal, lose, enemy_spawn, enemy_beep, enemy_hit, enemy_kill, midair_kill, bump,
asteroid_hit, ui_hover, ui_confirm, ui_cancel, shop_move, purchase. Boxes below checked accordingly.

Notes:
- `pause` / `unpause` have **no sound** by design — pausing muffles the music (low-pass bus) instead.
- `asteroid_hit` (survives) is pitched: base at 2 HP left, a fifth up (1.5×) at 1 HP.
  `asteroid_break` (destroyed) is now its OWN sound, not a pitched `asteroid_hit`.

## Core gameplay
- [ ] `launch`          — first SPACE: ignition, core flares alive
- [x] `boost`           — SPACE hits a light (the core sound; pitch-varied)
- [x] `boost_perfect`   — a PERFECT (high-quality) boost
- [ ] `miss`            — whiffed SPACE / power-down
- [ ] `combo_break`     — a light passes by unhit, breaking a streak
- [ ] `material_boost`  — B: spend a square for a speed boost

## Economy / squares
- [x] `pickup`          — collect a square ("+1 stardust"), pitch-varied
- [ ] `stardust_spawn`  — REMOVED: no sound on dim spawn (the `square_ready` pop covers it)
- [x] `square_ready`    — a square finishes fading in (becomes grabbable)
- [ ] `denied`          — NOT READY / FULL INVENTORY blip
- [x] `refill_tick`     — soft tick per mote sucked into the recharging core
- [ ] `core_low`        — "CORE LOW — RETURN HOME" warning first appears

## Lights from the core
- [ ] `light_charge`    — core charges/pays for a light (wobble + dip)
- [x] `light_ready`     — a light lands & latches onto the ring
- [ ] `shockwave`       — boosting multiple lights at once (big blast)

## Sealing / win / lose
- [x] `seal`            — a ring SEALS (the big one)
- [ ] `seal_final`      — the FINAL ring seals (unlocks the Finale upgrades) — optional, else reuse `seal`
- [ ] `escape`          — the "Freedom?" finale cinematic launches (the escape spiral)
- [ ] `win`             — the victory screen resolves (FREE AT LAST)
- [x] `lose`            — the core dies

## Navigation
- [ ] `traverse_up`     — glide outward to a higher ring (costs speed)
- [ ] `traverse_down`   — glide inward to a lower ring

## Combat
- [ ] `enemy_spawn`     — REMOVED: no announce sound (per request); call deleted from code
- [x] `enemy_beep`      — the radar ping a siphoner pulses once/sec
- [ ] `enemy_latch`     — a siphoner reaches the inner ring and latches on
- [ ] `siphon`          — pulse while a latched enemy drains the core
- [x] `enemy_hit`       — enemy damaged but not killed
- [x] `enemy_kill`      — enemy destroyed
- [x] `midair_kill`     — MID-AIR KILL BONUS
- [x] `bump`            — passing an enemy/asteroid slows you
- [x] `asteroid_hit`    — asteroid cracked (not destroyed); PITCH RISES as its remaining health drops
- [x] `asteroid_break`  — asteroid destroyed ("+1 COMET"); its own sound
- [ ] `beam`            — blaster firing **(LOOP — set loop on import)**
- [ ] `beam_kill`       — beam vaporizes an enemy

## UI / menus / shop
- [x] `ui_hover`        — hover a main-menu button
- [x] `ui_confirm`      — PLAY / accept / restart-yes
- [x] `ui_cancel`       — back / cancel
- [ ] `pause`           — pause the game
- [ ] `unpause`         — resume
- [ ] `confirm_open`    — the "ARE YOU SURE?" restart overlay opens
- [ ] `shop_open`       — the upgrade screen opens
- [x] `shop_move`       — moving the selection in the upgrade screen
- [x] `purchase`        — buy an upgrade
- [ ] `shop_denied`     — "No upgrades available"

## Optional / nice-to-have
- [ ] `core_critical`   — the low-core danger vignette kicks in (edge-triggered)
- [ ] `ui_appear`       — soft ding per element on the victory screen as it fades in
