# SFX manifest

Drop a file named `<name>.wav` (or `.ogg` / `.mp3`) in this folder and it plays automatically —
the call sites are already wired (via the `Sfx` autoload). Missing files are silent no-ops, so
you can fill these in one at a time. Names are matched exactly (case-sensitive).

For the two **loops** (`beam`, ...) set the file to loop in its Godot import settings.

## Core gameplay
- [ ] `launch`          — first SPACE: ignition, core flares alive
- [ ] `boost`           — SPACE hits a light (the core sound; pitch-varied)
- [ ] `boost_perfect`   — a PERFECT (high-quality) boost
- [ ] `miss`            — whiffed SPACE / power-down
- [ ] `combo_break`     — a light passes by unhit, breaking a streak
- [ ] `material_boost`  — B: spend a square for a speed boost

## Economy / squares
- [ ] `pickup`          — collect a square ("+1 stardust"), pitch-varied
- [ ] `square_ready`    — a square finishes fading in (becomes grabbable)
- [ ] `denied`          — NOT READY / FULL INVENTORY blip
- [ ] `refill_tick`     — soft tick per mote sucked into the recharging core
- [ ] `core_low`        — "CORE LOW — RETURN HOME" warning first appears

## Lights from the core
- [ ] `light_charge`    — core charges/pays for a light (wobble + dip)
- [ ] `light_ready`     — a light lands & latches onto the ring
- [ ] `shockwave`       — boosting multiple lights at once (big blast)

## Sealing / win / lose
- [ ] `seal`            — a ring SEALS (the big one)
- [ ] `win`             — PLANET SAVED
- [ ] `lose`            — the core dies

## Navigation
- [ ] `traverse_up`     — glide outward to a higher ring (costs speed)
- [ ] `traverse_down`   — glide inward to a lower ring

## Combat
- [ ] `enemy_spawn`     — a siphoner spawns on the frontier
- [ ] `enemy_beep`      — the radar ping a siphoner pulses once/sec
- [ ] `enemy_latch`     — a siphoner reaches the inner ring and latches on
- [ ] `siphon`          — pulse while a latched enemy drains the core
- [ ] `enemy_hit`       — enemy damaged but not killed
- [ ] `enemy_kill`      — enemy destroyed
- [ ] `midair_kill`     — MID-AIR KILL BONUS
- [ ] `bump`            — passing an enemy/asteroid slows you
- [ ] `asteroid_hit`    — asteroid cracked (not destroyed)
- [ ] `asteroid_break`  — asteroid destroyed ("+1 COMET")
- [ ] `beam`            — blaster firing **(LOOP — set loop on import)**
- [ ] `beam_kill`       — beam vaporizes an enemy

## UI / menus / shop
- [ ] `ui_hover`        — hover a main-menu button
- [ ] `ui_confirm`      — PLAY / accept / restart-yes
- [ ] `ui_cancel`       — back / cancel
- [ ] `pause`           — pause the game
- [ ] `unpause`         — resume
- [ ] `confirm_open`    — the "ARE YOU SURE?" restart overlay opens
- [ ] `shop_open`       — the upgrade screen opens
- [ ] `shop_move`       — moving the selection in the upgrade screen
- [ ] `purchase`        — buy an upgrade
- [ ] `shop_denied`     — "No upgrades available"
