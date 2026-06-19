# Game Jam Brief: Cozy Iso-Voxel Night Scene (Godot, Web Target)

Context document for an AI coding agent. Read this fully before proposing setup or code.

## Project constraints (these drive every decision below)

- **Solo dev, 7-day jam.**
- **Deliverable: playable in-browser on itch.io.** This is the single most important constraint — it dictates the renderer.
- **No rigging or 3D modeling skill.** Art is deliberately simple shapes. Mood, atmosphere, lighting, and VFX carry the experience. Do not propose solutions that require rigged characters, complex modeling, or hand-authored art.
- **Avatar must need no rig.** First-person camera, a floating light/orb, a rolling or sliding shape, or a vehicle. Translation + rotation only. No humanoids.
- **Dev is strong at game-feel iteration, weak at graphics tuning.** Don't lecture about "finding the fun." Do help keep graphics polish time-boxed.

## Engine + renderer decisions (do not deviate without flagging)

- **Use Godot 4.6, not 4.7.** 4.6 is battle-tested since Jan 2026; 4.7 went stable mid-June 2026 and carries first-`.0`-release regression risk that a jam can't absorb. 4.7's headline features (HDR output, AreaLight3D) don't apply to this project anyway (see below). Only switch to 4.7 if a specific, identified 4.6 bug forces it.
- **Use the Compatibility renderer.** Web export requires it (WebGL 2.0). Forward+ and Mobile are NOT supported for browser builds. Set this in Project Settings immediately, before building anything, so no work rests on desktop-only assumptions.

## What the Compatibility renderer CANNOT do (do not propose these)

- **Volumetric fog** — Forward+ only. Not available on web. (Use regular distance/height fog instead; see recipe.)
- **SDFGI / VoxelGI** (real global illumination) — Forward+ only. Fake bounce light with placed lights instead.
- **AreaLight3D** — Forward+ only, and new in 4.7. Off the menu entirely.
- **HDR output** — desktop + HDR monitors only. Irrelevant to a web/SDR build. Does not affect in-game look.

## The mood/lighting recipe (all of this works in Compatibility on web)

1. **Camera:** `Camera3D`, projection = Orthogonal, rotated to an isometric angle (~45° yaw, ~35° pitch).
2. **Key light:** one `DirectionalLight3D`, cool blue, low energy — reads as moonlight. Lights all top/sky-facing surfaces.
3. **Warm interior light:** place `OmniLight3D` nodes (warm amber) just inside window/door cutouts. This fakes the GI bounce cheaply and controllably — do NOT reach for real GI.
4. **Glow/bloom:** enable `Environment > Glow`. This is the single biggest "wow" lever and it works in Compatibility (since 4.3). The blown-out focal point = an emissive material or light pushed past the glow threshold.
5. **Tonemap:** `Environment > Tonemap`, AgX or ACES, to keep bright spots from clipping ugly.
6. **Atmosphere:** regular distance/height fog (the non-volumetric kind) for depth — distant blocks fading into dark. For visible light shafts (god rays), fake them with thin additive semi-transparent quads or a billboard shaft texture; don't expect volumetric fog to do it.
7. **VFX:** dust motes drifting in the light via `CPUParticles3D` (NOT GPUParticles — CPU is more reliable on web). Keep VFX budget to: glow + fog + particles. Don't over-scope.

## Process discipline (enforce these)

- **Build a throwaway lighting test scene first:** one box, one window, the full light rig + Environment. Dial the entire mood there (light colors, glow, fog, tonemap values). Lock the recipe, then apply that Environment to the real game. Turns "graphics" into a bounded sprint with a clear done-state.
- **Time-box graphics polish.** The look hits ~80% in about an hour of toggles, then has a long seductive tail of diminishing returns. That tail is where jams die. Get to 80%, stop, return to gameplay.
- **Export to web and test on itch by day 2–3, with an ugly grey box.** Godot web export has platform gotchas (SharedArrayBuffer config, load times, occasional Compatibility shadow quirks) unrelated to the game. Discover these while they're cheap to fix, not on day 7.

## Mechanic direction (if relevant)

Strongest fit given the constraints: **light as a resource/tool** — the avatar carries or emits light, darkness hides hazards or paths, the player manages it. Here the aesthetic IS the mechanic, which is the best possible pairing. Avoid Monument-Valley-style impossible-geometry puzzles: the look evokes them, but they're hand-authored and design-iteration-heavy — a beginner trap in 7 days.
