class_name VisualStyle extends Resource
# A reskin palette. One .tres per look; assign it to Game's `style` slot.
# Every default below equals the ORIGINAL hardcoded color in Game._draw(), so a freshly
# created VisualStyle (or the default.tres) reproduces the base game look exactly. Each
# reskin branch ships its own .tres overriding these — tweak any swatch live in the
# inspector, then run the scene to see it. (The shop/upgrade modal is intentionally not
# themed here — its layout is sized to fixed fonts.)

# ── Background (painted full-viewport before the world; transparent = original look) ──
@export_group("Background")
@export var bg_top: Color = Color(0, 0, 0, 0)        # gradient top (a=0 → no background)
@export var bg_bottom: Color = Color(0, 0, 0, 0)     # gradient bottom
@export var bg_bands := 24                            # gradient resolution (horizontal strips)
@export var enable_starfield := false
@export var star_color: Color = Color(1, 1, 1, 0.6)
@export var star_count := 140
@export var star_twinkle := 0.0                      # 0 = steady, up to ~1 = strong shimmer
@export var enable_treeline := false                 # forest-dusk silhouette along the bottom
@export var treeline_color: Color = Color(0.04, 0.05, 0.09)
@export var treeline_height := 220.0

# ── Fake bloom (stacked alpha draws; renderer-agnostic, safe for web) ──
@export_group("Glow")
@export var glow_enable := false                     # off = byte-identical to original
@export var glow_layers := 4
@export var glow_spread := 2.2                       # outermost halo size as a multiple
@export var glow_alpha := 0.5                        # innermost halo alpha

# ── Rings ──
@export_group("Rings")
@export var ring_locked: Color = Color(0.22, 0.22, 0.30)
@export var ring_sealed: Color = Color(0.5, 0.85, 1.0)
@export var ring_w_locked := 2.0
@export var ring_w_sealed := 3.0

# ── Comet head + tail ──
@export_group("Comet / Moon")
@export var tail: Color = Color(1.0, 0.85, 0.2)
@export var moon_slow: Color = Color(0.7, 0.85, 1.0)
@export var moon_fast: Color = Color(1, 1, 1)

# ── Planet + core bar ──
@export_group("Planet / Core")
@export var planet_sick: Color = Color(0.30, 0.22, 0.20)
@export var planet_healed: Color = Color(0.55, 0.9, 0.75)
@export var core_bar_border: Color = Color(0.05, 0.05, 0.07)
@export var core_bar_bg: Color = Color(0.14, 0.14, 0.18)
@export var core_bar_low: Color = Color(0.85, 0.3, 0.3)
@export var core_bar_full: Color = Color(0.3, 0.85, 0.45)
@export var core_text: Color = Color(0.92, 0.92, 0.96)

# ── Entities ──
@export_group("Entities")
@export var square_pending: Color = Color(0.5, 0.5, 0.55)
@export var square_ready: Color = Color(0.4, 0.85, 0.95)
@export var asteroid: Color = Color(0.6, 0.55, 0.5)
@export var asteroid_text: Color = Color(1, 1, 1)
@export var threat_flying: Color = Color(1.0, 0.3, 0.85)
@export var threat_latched: Color = Color(1.0, 0.25, 0.25)
@export var threat_text: Color = Color(1, 1, 1)

# ── Boost lights ──
@export_group("Lights")
@export var light_idle: Color = Color(0.95, 0.85, 0.2)
@export var light_dying: Color = Color(1.0, 0.5, 0.1)
@export var light_on: Color = Color(0.3, 1.0, 0.45)
@export var light_zone_alpha := 0.22

# ── Blaster + flashes ──
@export_group("Blaster / FX")
@export var beam_outer: Color = Color(1.0, 0.4, 0.9, 0.9)
@export var beam_core: Color = Color(1, 1, 1, 0.9)
@export var flash: Color = Color(1, 1, 1)

# ── HUD / banners ──
@export_group("HUD")
@export var spd_slow: Color = Color(0.40, 0.70, 1.0)
@export var spd_fast: Color = Color(1.0, 0.55, 0.15)
@export var hud_text: Color = Color(0.82, 0.82, 0.88)
@export var hud_seal_hint: Color = Color(0.6, 0.9, 1.0)
@export var hud_warn: Color = Color(1.0, 0.55, 0.2)
@export var hud_dim: Color = Color(0.55, 0.55, 0.6)
@export var hud_timer: Color = Color(0.85, 0.85, 0.9)
@export var clock_ring: Color = Color(0.22, 0.22, 0.28)
@export var clock_fill: Color = Color(0.92, 0.92, 1.0)
@export var clock_text: Color = Color(0.1, 0.1, 0.15)
@export var enemy_warn: Color = Color(1, 0.58, 0.5)
@export var banner_info: Color = Color(1, 1, 0.6)
@export var banner_win: Color = Color(0.5, 1, 0.6)
@export var banner_lose: Color = Color(1, 0.4, 0.4)
@export var banner_launch: Color = Color(0.9, 0.95, 0.6)
@export var banner_pause: Color = Color(0.9, 0.9, 1.0)
@export var shop_blocked: Color = Color(1, 0.3, 0.3)
