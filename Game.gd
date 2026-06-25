extends Node2D
# GRAY BOX — "Save the Planet" (comet-tail). The moon is a comet whose TAIL LENGTH is a
# live readout of SPEED. When the tail wraps a full 360° and touches its own head, that
# ring SEALS (permanent). Seal the three rings outward to save the planet (win). Core
# depletion = lose. Squares (ring 2) feed the core; overflow = square-credits for ECONOMY
# upgrades. Asteroids (ring 3) = mat for BATTLE upgrades; siphoners attack the core.
# Target: a complete, beautiful 5-10 min arc. One file. Disposable.

# ── Reskin palette ─────────────────────────────────────────
# Every drawable color reads from this resource. Swap the assigned .tres (or tweak its
# swatches live in the inspector) to reskin the whole game without touching gameplay.
@export var style: VisualStyle

# All in-game text uses this font (Quantico). Swap the weight in the inspector if desired.
@export var ui_font: Font

# Runtime asset handles, built in _ready(): looping background-music player + the arrow icon
# recolored (via Icon.recolored) from its source green to the hint text color.
var music: AudioStreamPlayer
var arrow_tex: Texture2D

# ── Rings ──────────────────────────────────────────────────
@export var base_radius := 180.0
@export var ring_gap := 300.0
@export var planet_radius := 40.0
@export var planet_grow_step := 14.0    # planet heals a step per ring sealed
@export var moon_radius := 10.0    # matches the boost-light point size (the moon is a cyan one)
@export var traverse_time := 2.0
@export var traverse_cost := 200.0
@export var view_margin := 0.80
@export var max_zoom := 2.2             # cap on zoom-in (lets the small inner ring fill the view)

# ── Tail / speed ───────────────────────────────────────────
@export var tail_life := 1.8            # seconds a tail particle lingers; sealing = lap within this time
@export var feed_up := 5.0              # +50% of base feed per Bigger-squares level (10->15->20->25)
# (comet tail color now lives in the reskin palette: style.tail)
@export var comet_emit_step := 0.04     # rad spacing between emitted tail particles
@export var comet_dot := 5.0            # tail particle radius (world px)
@export var seal_near := 0.70           # tail fraction of full at which the seal cinematic engages
@export var ui_text_scale := 2.0        # multiplier on all HUD / in-world text sizes (shop modal excluded)
@export var seal_slowmo := 0.15         # steady time scale held through the seal (pleenko orange-unlock value)
@export var seal_zoom := 1.9            # camera punch-in during the seal
@export var seal_zoom_time := 0.5       # s to become fully zoomed in
@export var gate_dist := 70.0          # px along the ring to accept a light (same on every ring)
@export var light_delay := 2.0
@export var light_delay_jitter := 0.25
@export var light_cost := 1.0
@export var dying_batches := 2          # final N light-batches (orange + slow) as the core dies
@export var dying_delay_mult := 3.0     # those final lights respawn this many × slower
@export var light_min_speed := 100.0              # at/below this speed the arc uses its "slow" range
@export var light_tween_speed := 2000.0           # speed at which the arc range reaches its "fast" values
@export var light_arc_slow := Vector2(15.0, 40.0)   # min/max degrees ahead at light_min_speed
@export var light_arc_fast := Vector2(90.0, 270.0)  # min/max degrees ahead at light_tween_speed+
@export var start_speed := 0.0
@export var min_speed := 50.0           # speed never drops below this — you can't stall out
@export var space_cd_time := 0.2        # min seconds between SPACE actions (anti-spam)
@export var death_speed := 0.0
@export var stall_decay := 120.0
@export var max_speed := 4000.0
@export var boost_base := 100.0
@export var boost_up := 0.5             # Boost-power upgrade multiplies boost_base by (1 + this)
@export var combo_every := 3            # every Nth consecutive hit gives a combo boost
@export var combo_boost_mult := 1.5     # that hit's boost is multiplied by this
@export var sealed_decay_mult := 0.5    # core decay on a SEALED ring is halved
@export var base_decay := 15.0
@export var whiff_slow := 0.85
@export var hitstop_time := 0.05
@export var seal_hitstop := 0.18

# ── Core / squares ─────────────────────────────────────────
@export var core_start := 5.0
@export var core_cap := 5.0
@export var core_color_max := 80.0      # core value at which the core glows full light-color (the upgrade ceiling)
@export var feed_per_square := 5.0
@export var material_max := 1             # squares on the ring (doubles per upgrade)
@export var square_ready_time := 1.0      # s a freshly-spawned square fades in before it's grabbable
@export var pickup_radius := 90.0       # base SPACE reach for squares (scaled by reach_mult())
@export var deposit_interval := 0.12
@export var suck_time := 0.45
@export var max_inventory := 3          # most squares you can carry at once (doubles per upgrade)

# ── Asteroids (loot vein, ring 3) ──────────────────────────
@export var asteroid_max := 1
@export var asteroid_respawn_delay := 1.0   # s after one is destroyed before the next spawns
@export var asteroid_radius := 16.0
@export var asteroid_speed := 1.2
@export var asteroid_hits := 3
@export var asteroid_hit_mult := 0.7
@export var asteroid_tol := 0.16
@export var asteroid_hit_cd := 0.5

# ── Siphoner threats (frontier) ────────────────────────────
@export var threat_radius := 14.0
@export var enemy_hit_dist := 70.0      # base SPACE reach for enemies (scaled by reach_mult())
@export var enemy_contact_dist := 34.0  # proximity at which a passed enemy slows you (item 9)
@export var threat_speed := 90.0
@export var threat_hp := 2
@export var threat_drain :=  0.75
@export var ram_radial_tol := 45.0
@export var ram_ang_tol := 0.18
@export var ram_hit_mult := 0.7
@export var threat_ram_cd := 0.4

# ── Blaster ────────────────────────────────────────────────
@export var beam_width := 0.12          # rad half-width of the laser
@export var beam_drain := 3.0           # core/s while firing

# ── Standardized look (purple + cyan) ──────────────────────
@export var grid_glow_radius := 240.0   # screen px: grid lines within this of the moon brighten
@export var grid_glow_strength := 0.8   # extra alpha added to grid lines right under the moon

# ── State ──────────────────────────────────────────────────
var phase := "play"      # play | dead | won
var started := false     # the moon waits at the top until the first SPACE (launch)
var dead_reason := ""
var top_angle := -PI / 2.0
var banner_text := ""
var banner_timer := 0.0
var angle := 0.0
var speed := 0.0
var combo := 0
var sealed := [false, false, false]
var unlocked := 1
var current_ring := 0
var display_radius := 0.0
var moving := false
var move_from := 0
var move_to := 0
var move_t := 0.0
var nav_hint_wait := false   # armed at first auto-launch; waiting for the glide to land
var nav_hint_show := false   # currently displaying the top-center ring-nav hint
var nav_hint_seen := false   # once dismissed, never arm/show again
var view_scale := 1.0
var display_tail := 0.0   # eased tail angle (for subtle growth + the seal check)
var sealing := false      # committed seal cinematic (latched until contact; failsafe-guaranteed)
var seal_anim := 0.0
var time_scale := 1.0
var cam_focus := Vector2.ZERO
var cam_zoom := 1.0
var game_time := 0.0
var comet: Array = []     # tail particles: { pos:Vector2, life:float, cum:float }
var cum_angle := 0.0      # unwrapped accumulated rotation (drives the seal span)

var core := 0.0
var inventory := 0        # carried squares = the economy wallet (capped by max_inventory)
var asteroid_mats := 0
var overflow_mult := 1    # credits per overflow square (+1 per Bigger-squares level)

var lights: Array = []
var light_count := 1
var light_timer := 0.0

var materials: Array = []   # { angle:float, ready:float } squares on the middle ring
var flying: Array = []      # { start:Vector2, t:float }
var deposit_timer := 0.0
var asteroids: Array = []   # { angle, hits_left, cd }
var threats: Array = []     # { angle, radius, hp, latched, cd }
var threat_timer := 0.0
var threat_spawn_count := 0   # enemy wave index (drives interval + count)
var enemy_active := false     # the spawn-clock runs once ring 2 is unlocked
var hub_pending := false      # arrived at hub; shop opens once enemies are cleared
var asteroid_respawn := 0.0
var square_respawn := 0.0
var paused := false
var confirm_reset := false   # R opens an "are you sure?" overlay before actually resetting
var confirm_hit: Array = []  # clickable Yes/No regions in the confirm overlay
var space_cd := 0.0
var shop_open := false
var shop_hit: Array = []   # clickable regions in the upgrade modal: { rect, action, list, idx }

# Upgrades
var has_horns := false
var has_horns2 := false
var has_blasters := false
var has_material_boost := false
var has_ramming := false
var has_vacuum := false
var reach_level := 0      # "Larger space hit" upgrades; reach_mult() = 1 + level/6 (lvl3 = 1.5x)
var beam_on := false
var shop_sq: Array = []
var shop_bt: Array = []

var trail: Array = []
var particles: Array = []
var popups: Array = []
var flashes: Array = []
var shake := 0.0
var hitstop := 0.0


var _base := {}   # snapshot of upgrade-modified export bases (so reset honors the exports)


func _ready() -> void:
	if style == null:
		style = VisualStyle.new()   # defaults reproduce the original look
	if ui_font == null:
		ui_font = load("res://assets/fonts/Quantico/Quantico-Regular.ttf")
	# Background music: a looping player, started on the first SPACE (a user gesture, which
	# satisfies the browser autoplay policy in the web build).
	music = AudioStreamPlayer.new()
	var ms: AudioStream = load("res://assets/sound/magic space.mp3")
	if ms is AudioStreamMP3:
		(ms as AudioStreamMP3).loop = true
	music.stream = ms
	add_child(music)
	# Recolor the green arrow art to the hint text color for the ring-nav prompt.
	arrow_tex = Icon.recolored(load("res://assets/icons/arrows.png"), style.banner_info)
	# Capture export bases BEFORE the first reset, so editing an @export actually takes effect
	# (reset() restores from here instead of hardcoded duplicates).
	_base = {
		"tail_life": tail_life,
		"boost_base": boost_base,
		"feed_per_square": feed_per_square,
		"material_max": material_max,
		"max_inventory": max_inventory,
		"core_cap": core_cap,
		"light_cost": light_cost,
		"light_delay": light_delay,
		"ram_hit_mult": ram_hit_mult,
		"asteroid_hits": asteroid_hits,
		"asteroid_max": asteroid_max,
		"threat_hp": threat_hp,
	}
	reset()


# ── Shop data ──────────────────────────────────────────────
var bought := {}   # node id -> 1 once owned


# Economy tech tree. Each node reveals its children when bought; only buyable frontier shows.
func econ_nodes() -> Array:
	return [
		{ "id":"esq",    "name":"More squares",            "req":"",       "cost":1,  "eff":"material", "cur":"sq", "desc":"+1 square on the ring" },
		{ "id":"ereach1","name":"Larger space hit",        "req":"",       "cost":5,  "eff":"reach",    "cur":"sq", "desc":"Bigger SPACE reach (squares, lights, enemies, asteroids)" },
		{ "id":"ereach2","name":"Larger space hit II",     "req":"ereach1","cost":10, "eff":"reach",    "cur":"sq", "desc":"Bigger SPACE reach" },
		{ "id":"ereach3","name":"Larger space hit III",    "req":"ereach2","cost":15, "eff":"reach",    "cur":"sq", "desc":"Bigger SPACE reach" },
		{ "id":"ereach4","name":"Larger space hit IV",     "req":"ereach3","cost":20, "eff":"reach",    "cur":"sq", "desc":"Bigger SPACE reach" },
		{ "id":"ecore1", "name":"More core capacity",      "req":"esq",    "cost":2,  "eff":"core",     "cur":"sq", "desc":"Double the core's capacity" },
		{ "id":"einv1",  "name":"More square capacity",    "req":"esq",    "cost":1,  "amt":3, "eff":"inv", "cur":"sq", "desc":"Carry up to 6 squares" },
		{ "id":"ecore2", "name":"More core capacity II",   "req":"ecore1", "cost":4,  "eff":"core",     "cur":"sq", "desc":"Double the core's capacity" },
		{ "id":"eb1",    "name":"Boost light",             "req":"ecore1", "cost":5,  "eff":"boost",    "cur":"sq", "desc":"Light +50% speed, but +1 core/light" },
		{ "id":"ecore3", "name":"More core capacity III",  "req":"ecore2", "cost":8,  "eff":"core",     "cur":"sq", "desc":"Double the core's capacity" },
		{ "id":"ecore4", "name":"More core capacity IV",   "req":"ecore3", "cost":16, "eff":"core",     "cur":"sq", "desc":"Double the core's capacity" },
		{ "id":"efast1", "name":"Faster lights",           "req":"eb1",            "cost":6,  "eff":"fast1", "cur":"sq", "desc":"Lights respawn faster (1.5s)" },
		{ "id":"efast2", "name":"Faster lights II",        "req":"efast1",         "cost":12, "eff":"fast2", "cur":"sq", "desc":"Lights respawn faster (1.0s)" },
		{ "id":"edual",  "name":"Double lights",           "req":["efast1","eb2"], "cost":11, "mat":1, "eff":"dual",  "cur":"sq", "desc":"Two boost lights at once (+1 comet)" },
		{ "id":"eb2",    "name":"Boost light II",          "req":"eb1",    "cost":10, "eff":"boost",    "cur":"sq", "desc":"Light +50% speed, but +1 core/light" },
		{ "id":"eb3",    "name":"Boost light III",         "req":"eb2",    "cost":20, "eff":"boost",    "cur":"sq", "desc":"Light +50% speed, but +1 core/light" },
		{ "id":"einv2",  "name":"More square capacity II", "req":"einv1",  "cost":3,  "amt":4, "eff":"inv", "cur":"sq", "desc":"Carry up to 10 squares" },
		{ "id":"einv3",  "name":"More square capacity III","req":"einv2",  "cost":6,  "amt":5, "eff":"inv", "cur":"sq", "desc":"Carry up to 15 squares" },
		{ "id":"einv4",  "name":"More square capacity IV", "req":"einv3",  "cost":10, "amt":5, "eff":"inv", "cur":"sq", "desc":"Carry up to 20 squares" },
		{ "id":"esq2",   "name":"More squares II",         "req":"einv1",  "cost":3,  "eff":"material", "cur":"sq", "desc":"+1 square on the ring" },
		{ "id":"esq3",   "name":"More squares III",        "req":"esq2",   "cost":6,  "eff":"material", "cur":"sq", "desc":"+1 square on the ring" },
		{ "id":"esq4",   "name":"More squares IV",         "req":"esq3",   "cost":12, "eff":"material", "cur":"sq", "desc":"+1 square on the ring" },
	]


func battle_nodes() -> Array:
	return [
		{ "id":"horns",    "name":"Horns",          "req":"",      "cost":2,  "eff":"horns",    "cur":"ast", "desc":"Asteroids crack in 2 hits" },
		{ "id":"horns2",   "name":"Horns II",       "req":"horns", "cost":10, "eff":"horns2",   "cur":"ast", "desc":"Asteroids die in 1 hit, no slowdown" },
		{ "id":"matboost", "name":"Material boost", "req":"horns", "cost":5,  "eff":"matboost", "cur":"ast", "desc":"Press B: spend 1 square for a speed boost" },
		{ "id":"ramming",  "name":"Ramming",       "req":"horns", "cost":3,  "eff":"ramming",  "cur":"ast", "desc":"Missed-SPACE enemy collisions deal 1 damage" },
		{ "id":"vacuum",   "name":"Vacuum",        "req":"horns", "cost":3,  "eff":"vacuum",   "cur":"ast", "desc":"Auto-collect nearby squares, no SPACE needed" },
		{ "id":"ast1",     "name":"More asteroids",    "req":"horns", "cost":4,  "eff":"asteroids", "cur":"ast", "desc":"+1 asteroid on the ring" },
		{ "id":"ast2",     "name":"More asteroids II", "req":"ast1",  "cost":12, "eff":"asteroids", "cur":"ast", "desc":"+1 asteroid on the ring" },
	]


func req_met(req) -> bool:
	# req is "" (root), a single id, or an Array of ids where ANY owned satisfies it.
	if req is Array:
		for r in req:
			if bought.get(r, 0) >= 1:
				return true
		return false
	if req == "":
		return true
	return bought.get(req, 0) >= 1


func visible_nodes(tree: Array) -> Array:
	# A node is on the frontier when its prerequisite is met and it isn't owned yet.
	var out: Array = []
	for node in tree:
		if bought.get(node.id, 0) >= 1:
			continue
		if req_met(node.req):
			out.append(node)
	return out


func make_shops() -> void:
	shop_sq = visible_nodes(econ_nodes())
	shop_bt = visible_nodes(battle_nodes())


func reset() -> void:
	phase = "play"
	started = false
	dead_reason = ""
	angle = top_angle
	speed = 0.0
	combo = 0
	sealed = [false, false, false]
	unlocked = 1
	current_ring = 0
	display_radius = ring_r(0)
	moving = false
	move_t = 0.0
	banner_timer = 0.0
	core = core_start
	inventory = 0
	asteroid_mats = 0
	lights.clear()
	light_count = 1
	light_timer = 0.0
	lights = [top_angle]   # a boost waits right under the player to launch with
	materials.clear()
	flying.clear()
	deposit_timer = 0.0
	asteroids.clear()
	threats.clear()
	threat_timer = 0.0
	threat_spawn_count = 0
	enemy_active = false
	hub_pending = false
	asteroid_respawn = 0.0
	square_respawn = 0.0
	paused = false
	confirm_reset = false
	confirm_hit.clear()
	shop_open = false
	shop_hit.clear()
	has_horns = false
	has_horns2 = false
	has_blasters = false
	has_material_boost = false
	has_ramming = false
	has_vacuum = false
	reach_level = 0
	beam_on = false
	bought = {}
	# restore upgrade-modified tunables to their export bases (snapshotted in _ready)
	tail_life = _base.tail_life
	boost_base = _base.boost_base
	feed_per_square = _base.feed_per_square
	material_max = _base.material_max
	max_inventory = _base.max_inventory
	core_cap = _base.core_cap
	light_cost = _base.light_cost
	light_delay = _base.light_delay
	ram_hit_mult = _base.ram_hit_mult
	asteroid_hits = _base.asteroid_hits
	asteroid_max = _base.asteroid_max
	threat_hp = _base.threat_hp
	overflow_mult = 1   # pure runtime var, base is always 1
	make_shops()
	trail.clear()
	particles.clear()
	popups.clear()
	flashes.clear()
	shake = 0.0
	hitstop = 0.0
	display_tail = 0.0
	comet.clear()
	cum_angle = 0.0
	sealing = false
	seal_anim = 0.0
	nav_hint_wait = false
	nav_hint_show = false
	nav_hint_seen = false
	time_scale = 1.0
	cam_focus = Vector2.ZERO
	cam_zoom = 1.0
	game_time = 0.0
	view_scale = desired_scale()
	queue_redraw()


# ── Geometry / view ────────────────────────────────────────
func ring_r(i: int) -> float:
	return base_radius + i * ring_gap


func sealed_count() -> int:
	var n := 0
	for s in sealed:
		if s:
			n += 1
	return n


func planet_draw_radius() -> float:
	return planet_radius + sealed_count() * planet_grow_step


func screen_center() -> Vector2:
	return get_viewport_rect().size * 0.5


func half_screen() -> float:
	var vp := get_viewport_rect().size
	return minf(vp.x, vp.y) * 0.5


func frame_scale(r: float) -> float:
	return minf(max_zoom, (half_screen() * view_margin) / maxf(1.0, r))


func desired_scale() -> float:
	return frame_scale(display_radius)   # camera always frames the ring the moon is on (incl. the auto-launch glide)


func moon_world() -> Vector2:
	return display_radius * Vector2(cos(angle), sin(angle))


func ring_point(r: float, a: float) -> Vector2:
	return r * Vector2(cos(a), sin(a))


func reach_mult() -> float:
	# SPACE-hit reach grows with "Larger space hit": +1/6 per level, so level 3 = 1.5x (the
	# old default size), level 4 keeps the same step (1.667x).
	return 1.0 + float(reach_level) / 6.0


func speed_t() -> float:
	return clampf(speed / max_speed, 0.0, 1.0)


func tail_span() -> float:
	# Angular length of the live tail = rotation since the oldest STILL-VISIBLE particle was
	# dropped. The moon "catches its tail" (span >= TAU) by lapping within tail_life. A
	# particle faded below 15% opacity is too ghostly to "collide" with, so it doesn't count
	# — we measure to the oldest particle that's still at least 15% opaque.
	for cp in comet:   # comet is ordered oldest-first
		var lf: float = cp.life
		var f := clampf(lf / tail_life, 0.0, 1.0)
		var op := 1.0 - (1.0 - f) * (1.0 - f)   # same ease-out as the draw
		if op >= 0.15:
			var cm: float = cp.cum
			return cum_angle - cm
	return 0.0


func seal_speed() -> float:
	# Min speed at which the trail will fill to a full wrap (TAU) within tail_life.
	# At or above this, the tail WILL connect; below it, it plateaus short.
	return (TAU * display_radius) / maxf(0.01, tail_life)


func cur_decay() -> float:
	return base_decay * (sealed_decay_mult if sealed[current_ring] else 1.0)


# ── Lights ─────────────────────────────────────────────────
func aligned_light() -> int:
	# Acceptance is by along-ring DISTANCE (px), so it's the same window on every ring.
	for i in lights.size():
		if display_radius * absf(wrapf(angle - lights[i], -PI, PI)) <= gate_dist:
			return i
	return -1


func light_dying() -> bool:
	# True once the core can only make its final `dying_batches` of lights — they go orange
	# and respawn slowly to show the planet dying. (Full core is never "dying".)
	return unlocked >= 2 and core < core_cap and core <= float(dying_batches * light_count) * light_cost


func rand_ahead() -> float:
	# Arc distance ahead scales with speed: at speed 0 it's light_arc_slow degrees, rising
	# to light_arc_fast at light_tween_speed; the random pick is within the lerped range.
	var t := clampf((speed - light_min_speed) / maxf(1.0, light_tween_speed - light_min_speed), 0.0, 1.0)
	var lo := lerpf(light_arc_slow.x, light_arc_fast.x, t)
	var hi := lerpf(light_arc_slow.y, light_arc_fast.y, t)
	return wrapf(angle + deg_to_rad(randf_range(lo, hi)), -PI, PI)


# ── Spawners ───────────────────────────────────────────────
func spawn_square() -> void:
	# A new square appears immediately but fades in over square_ready_time before it's grabbable.
	materials.append({ "angle": randf_range(-PI, PI), "ready": square_ready_time })


func refill_materials() -> void:
	materials.clear()
	for i in material_max:
		spawn_square()


func ensure_asteroids() -> void:
	while asteroids.size() < asteroid_max:
		asteroids.append({ "angle": randf_range(-PI, PI), "hits_left": asteroid_hits, "cd": 0.0 })


func spawn_threat() -> void:
	threats.append({ "angle": randf_range(-PI, PI), "radius": ring_r(unlocked - 1) + 80.0, "hp": threat_hp, "latched": false, "cd": 0.0 })


# ── Sealing / progression ──────────────────────────────────
func try_seal() -> void:
	# Seal the ring you're on if it's unlocked, unsealed, and the tail has wrapped it.
	if moving or current_ring >= unlocked or sealed[current_ring]:
		return
	if tail_span() < TAU:
		return
	sealed[current_ring] = true
	sealing = false         # cinematic done; tail despawn resumes
	hitstop = seal_hitstop
	shake = minf(2.5, shake + 1.4)
	var mp := moon_world()
	for i in 26:
		particles.append({ "pos": mp, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(160.0, 420.0), "life": randf_range(0.3, 0.7) })
	flashes.append({ "pos": Vector2.ZERO, "life": 0.6 })
	if current_ring == 2:
		phase = "won"
		return
	unlocked = sealed_count() + 1
	# Extra burst of light: the moon broke free of this ring's orbit.
	shake = minf(3.0, shake + 0.8)
	flashes.append({ "pos": Vector2.ZERO, "life": 0.6, "r": ring_r(unlocked - 1) })   # light ring expanding out to the new ring
	flashes.append({ "pos": mp, "life": 0.6, "r": 220.0 })                            # burst at the launch point
	# Auto-launch onto the freshly opened ring, carrying momentum (no traverse_cost).
	move_from = current_ring
	move_to = unlocked - 1
	move_t = 0.0
	moving = true
	if not nav_hint_seen:
		nav_hint_wait = true   # show the ring-nav hint once we land
	banner_text = "RING SEALED — RING %d OPEN" % unlocked
	banner_timer = 2.5
	if unlocked == 2:
		refill_materials()   # ring 2 opens with squares ready to grab
	if unlocked == 3:
		ensure_asteroids()


# ── Sim ────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if phase == "won" or phase == "dead":
		queue_redraw()
		return
	if paused or shop_open or confirm_reset:
		beam_on = false
		queue_redraw()
		return

	# Blaster: held F (only with the upgrade, while playing).
	beam_on = has_blasters and phase == "play" and Input.is_key_pressed(KEY_F)

	if started and phase == "play":
		game_time += delta

	display_tail = minf(tail_span(), TAU)

	# (Seal slow-mo cinematic removed for now — the tail simply seals on contact in try_seal.)
	time_scale = 1.0

	var sim := delta * time_scale
	if hitstop > 0.0:
		hitstop -= delta
		sim = 0.0

	if sim > 0.0:
		_tick_play(sim)

	space_cd = maxf(0.0, space_cd - delta)
	cam_focus = Vector2.ZERO
	cam_zoom = 1.0
	view_scale = lerpf(view_scale, desired_scale(), clampf(3.0 * delta, 0.0, 1.0))
	banner_timer = maxf(0.0, banner_timer - delta)
	shake = maxf(0.0, shake - delta * 5.0)
	for p in particles:
		p.pos += p.vel * delta
		p.vel *= 0.9
		p.life -= delta
	particles = particles.filter(func(p): return p.life > 0.0)
	for pu in popups:
		pu.pos += Vector2(0, -36) * delta
		pu.life -= delta
	popups = popups.filter(func(pu): return pu.life > 0.0)
	for fl in flashes:
		fl.life -= delta
	flashes = flashes.filter(func(fl): return fl.life > 0.0)

	queue_redraw()


func _tick_play(sim: float) -> void:
	if not started:
		return   # parked at the top until the first SPACE launches us
	speed = clampf(speed - cur_decay() * sim, min_speed, max_speed)

	# Blaster core drain.
	if beam_on:
		core = maxf(0.0, core - beam_drain * sim)
		do_beam()

	# Ring glide (radius drives angular pace).
	if moving:
		move_t += sim / maxf(0.001, traverse_time)
		if move_t >= 1.0:
			move_t = 1.0
			moving = false
			current_ring = move_to
			comet.clear()   # drop the spiral tail from the glide — a seal needs a full lap made ON the ring
			if current_ring == 0:
				arrive_at_hub()   # bank squares + open the upgrade screen
			if nav_hint_wait:
				nav_hint_wait = false
				nav_hint_show = true   # landed on the new outer ring — teach UP/DOWN
		display_radius = lerpf(ring_r(move_from), ring_r(move_to), move_t)
	else:
		display_radius = ring_r(current_ring)

	# Advance, dropping tail particles along the arc just traversed (they linger tail_life).
	var a0 := angle
	var dlt := (speed / display_radius) * sim
	angle = wrapf(angle + dlt, -PI, PI)
	cum_angle += dlt
	var nsub := clampi(int(dlt / comet_emit_step), 1, 60)
	for s in range(1, nsub + 1):
		var f := float(s) / float(nsub)
		var aa := a0 + dlt * f
		comet.append({ "pos": display_radius * Vector2(cos(aa), sin(aa)), "life": tail_life, "cum": (cum_angle - dlt) + dlt * f })
	# Age particles. During a committed seal, FREEZE the oldest (anchor) and never pop it,
	# so the moon is guaranteed to lap around and make contact (failsafe).
	for i in range(comet.size()):
		if sealing and i == 0:
			continue
		comet[i].life -= sim
	if not sealing:
		while not comet.is_empty() and comet[0].life <= 0.0:
			comet.pop_front()
		while comet.size() > 2000:
			comet.pop_front()

	try_seal()

	# Keep material_max squares present (new ones spawn instantly), and fade them in. A small
	# burst of light pops the moment a square becomes grabbable.
	if unlocked >= 2:
		while materials.size() < material_max:
			spawn_square()
		for m in materials:
			if m.ready > 0.0:
				m.ready -= sim
				if m.ready <= 0.0:
					m.ready = 0.0
					var bp := ring_point(ring_r(1), m.angle)
					flashes.append({ "pos": bp, "life": 0.4 })
					for n in 6:
						particles.append({ "pos": bp, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(60.0, 140.0), "life": randf_range(0.2, 0.4) })
		# Vacuum upgrade: auto-grab ready squares within reach, no SPACE needed.
		if has_vacuum:
			for i in range(materials.size() - 1, -1, -1):
				var mv: Dictionary = materials[i]
				if mv.ready <= 0.0 and inventory < max_inventory and moon_world().distance_to(ring_point(ring_r(1), mv.angle)) < pickup_radius * reach_mult():
					collect_square(i)


	# Lights spawn as a full batch once the previous batch is fully used; each costs 1 core.
	if lights.is_empty():
		light_timer -= sim
		if light_timer <= 0.0:
			for n in light_count:
				if unlocked < 2:
					lights.append(rand_ahead())           # free before the core exists (ring 1)
				elif core > light_cost:                   # strict: never spend the last point
					core -= light_cost
					lights.append(rand_ahead())

	# Asteroids (loot vein, ring 3) — respawn only after a delay once destroyed.
	if unlocked >= 3:
		if asteroids.size() < asteroid_max:
			asteroid_respawn -= sim
			if asteroid_respawn <= 0.0:
				asteroids.append({ "angle": randf_range(-PI, PI), "hits_left": asteroid_hits, "cd": 0.0 })
		for ast in asteroids:
			ast.angle = wrapf(ast.angle - asteroid_speed * sim, -PI, PI)
			if ast.cd > 0.0:
				ast.cd -= sim
		# Passing an asteroid on the ring slows you (always, on a cooldown) — damaging it
		# requires SPACE (handled in try_boost). Horns II removes the slowdown.
		if current_ring == 2:
			for ast in asteroids:
				if ast.cd <= 0.0 and absf(wrapf(angle - ast.angle, -PI, PI)) < asteroid_tol:
					if not has_horns2:
						speed = speed * asteroid_hit_mult
					ast.cd = asteroid_hit_cd
		asteroids = asteroids.filter(func(a): return a.hits_left > 0)

	# Enemies run on the clock from launch (we're past the not-started early-return).
	_tick_threats(sim)

	# Core refills to full ONLY on the inner ring (home base) — unless an enemy has reached it.
	# (Other sealed rings still get reduced decay via cur_decay, but no replenish.)
	if current_ring == 0 and not moving and not core_under_attack():
		core = core_cap
	# Death only when the planet's core is drained to nothing.
	if core <= 0.0:
		phase = "dead"
		if dead_reason == "":
			dead_reason = "THE PLANET'S CORE DIED"

	# Back at the hub with no enemy on the inner ring -> open the upgrade screen.
	if hub_pending and not shop_open and current_ring == 0 and not moving and not core_under_attack():
		shop_open = true
		hub_pending = false

	_trail()


func do_beam() -> void:
	# Vaporize threats within the beam's angular band.
	var killed := false
	for t in threats:
		if absf(wrapf(t.angle - angle, -PI, PI)) < beam_width:
			t.hp = 0
			killed = true
			var tp := ring_point(t.radius, t.angle)
			for i in 6:
				particles.append({ "pos": tp, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(120.0, 260.0), "life": randf_range(0.2, 0.5) })
	if killed:
		shake = minf(2.0, shake + 0.5)   # punch the screen when the beam vaporizes an enemy
		threats = threats.filter(func(t): return t.hp > 0)


func enemy_interval(i: int) -> float:
	return [40.0, 35.0, 30.0, 25.0][i % 4]


func enemy_count(i: int) -> int:
	return i / 4 + 1   # +1 enemy each full 4-spawn cycle


func core_under_attack() -> bool:
	# True while any enemy has reached (latched onto) the innermost ring.
	return threats.any(func(t): return t.latched)


func _tick_threats(sim: float) -> void:
	# Spawn-clock: each time it drains, a wave of enemy_count() enemies spawns and the next
	# interval is loaded (45/40/35/30 cycling, count rising every full cycle).
	if enemy_active:
		threat_timer -= sim
		if threat_timer <= 0.0:
			for n in enemy_count(threat_spawn_count):
				spawn_threat()
			threat_spawn_count += 1
			threat_timer = enemy_interval(threat_spawn_count)

	for t in threats:
		if t.cd > 0.0:
			t.cd -= sim
		if not t.latched:
			t.radius -= threat_speed * sim
			if t.radius <= ring_r(0):
				t.radius = ring_r(0)
				t.latched = true
		else:
			core -= threat_drain * sim
		# Passing an enemy slows you like an asteroid (on a cooldown). A successful SPACE that
		# pass sets t.cd, so killing/hitting it skips the slow. With Ramming, a missed-SPACE
		# collision still slows but chips 1 HP off the enemy.
		if t.cd <= 0.0 and moon_world().distance_to(ring_point(t.radius, t.angle)) < enemy_contact_dist:
			speed = maxf(min_speed, speed * asteroid_hit_mult)
			t.cd = asteroid_hit_cd
			shake = minf(1.8, shake + 0.3)
			var cp := ring_point(t.radius, t.angle)
			for i in 5:
				particles.append({ "pos": cp, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(90.0, 200.0), "life": randf_range(0.2, 0.45) })
			if has_ramming:
				t.hp -= 1
	threats = threats.filter(func(t): return t.hp > 0)

	core = maxf(0.0, core)   # core can run dry (lights stop spawning), but it's not an instant loss


func _trail() -> void:
	trail.append(moon_world())
	if trail.size() > 26:
		trail.pop_front()


# ── Input ──────────────────────────────────────────────────
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode

	# "Are you sure?" overlay swallows all input until answered.
	if confirm_reset:
		match k:
			KEY_Y, KEY_ENTER, KEY_KP_ENTER:
				confirm_reset = false
				reset()
			KEY_N, KEY_ESCAPE, KEY_R:
				confirm_reset = false
		return

	# Upgrade modal: only buying + back + restart.
	if shop_open:
		match k:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var idx := k - KEY_1   # economy rows first, then battle (continuous numbering)
				if idx < shop_sq.size():
					buy(shop_sq[idx])
				elif unlocked >= 3 and idx - shop_sq.size() < shop_bt.size():
					buy(shop_bt[idx - shop_sq.size()])
			KEY_B: shop_open = false
			KEY_R: confirm_reset = true
		return

	match k:
		KEY_SPACE:
			if phase == "play" and space_cd <= 0.0:
				if not started:
					started = true        # launch: kick off + the boost below
					speed = start_speed
					core = core_cap                 # the core is online from the first second
					enemy_active = true             # and enemies start attacking immediately
					threat_spawn_count = 0
					threat_timer = enemy_interval(0)
					if not music.playing:
						music.play()    # background music starts on the very first launch, then loops
				if not try_boost():
					space_cd = space_cd_time   # only rate-limit a MISS; a hit lets you go again
		KEY_B:
			# Material boost: spend a carried square for a soft (base, unupgraded) speed boost.
			if phase == "play" and has_material_boost and inventory > 0:
				inventory -= 1
				speed = minf(max_speed, speed + _base.boost_base)
				var bp := moon_world()
				shake = minf(1.6, shake + 0.3)
				for i in 10:
					particles.append({ "pos": bp, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(110.0, 240.0), "life": randf_range(0.25, 0.5) })
				popups.append({ "pos": bp, "text": "MATERIAL BOOST", "life": 0.8, "size": 18 })
		KEY_UP:
			if phase == "play":
				if nav_hint_show:
					nav_hint_show = false
					nav_hint_seen = true
				traverse(1)
		KEY_DOWN:
			if phase == "play":
				if nav_hint_show:
					nav_hint_show = false
					nav_hint_seen = true
				traverse(-1)
		KEY_P:
			if phase == "play":
				paused = not paused
		KEY_R:
			# Mid-run, confirm first (accidental restarts hurt). On win/lose, just restart.
			if phase == "play" and started:
				confirm_reset = true
			else:
				reset()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return
	var mp := (event as InputEventMouseButton).position

	# "Are you sure?" overlay — Yes / No buttons.
	if confirm_reset:
		for h in confirm_hit:
			if (h.rect as Rect2).has_point(mp):
				confirm_reset = false
				if h.action == "yes":
					reset()
				return
		return

	# Upgrade modal: buy rows / back button.
	if shop_open:
		for h in shop_hit:
			if (h.rect as Rect2).has_point(mp):
				match h.action:
					"back": shop_open = false
					"buy": buy(shop_sq[h.idx] if h.list == "sq" else shop_bt[h.idx])
				return
		return

	# Pause toggle via the corner icon (Pleenko-style clickable pause button).
	if phase == "play" and started and pause_btn_rect().has_point(mp):
		paused = not paused


func can_shop() -> bool:
	return phase == "play" and current_ring == 0 and not moving


func traverse(dir: int) -> void:
	if moving or sealing:
		return
	var target := clampi(current_ring + dir, 0, unlocked - 1)
	if target == current_ring:
		return
	hub_pending = false   # leaving the hub cancels a pending shop
	if dir > 0:
		speed = maxf(min_speed, speed - traverse_cost)
	else:
		speed = minf(max_speed, speed + traverse_cost * 0.5)
	move_from = current_ring
	move_to = target
	move_t = 0.0
	moving = true


func collect_square(i: int) -> void:
	var ma: float = materials[i].angle
	materials.remove_at(i)
	inventory = mini(max_inventory, inventory + overflow_mult)   # Bigger squares = +N wallet per grab
	spawn_square()   # replacement appears immediately (not grabbable until it fades in)
	var mp := ring_point(ring_r(1), ma)
	flashes.append({ "pos": mp, "life": 0.3 })
	popups.append({ "pos": mp, "text": "+1", "life": 0.5, "size": 14 })


func try_boost() -> bool:
	# Returns true if the press connected with anything (square/light/enemy/asteroid).
	var did := false
	var mw := moon_world()
	var rm := reach_mult()   # "Larger space hit" scales every SPACE reach below

	# Lights FIRST — boosting one (or several aligned at once) fires a single shockwave centered
	# on the boosted lights, reaching 2× the square-grab radius. It sweeps squares, asteroids, and
	# enemies in that blast (Euclidean), on top of the normal per-target reach below.
	var shock_pts: Array[Vector2] = []
	for i in range(lights.size() - 1, -1, -1):
		if display_radius * absf(wrapf(angle - lights[i], -PI, PI)) <= gate_dist * rm:
			shock_pts.append(ring_point(display_radius, lights[i]))
			do_boost(i)
			did = true
	var shock := not shock_pts.is_empty()
	var shock_r := pickup_radius * 2.0 * rm
	var shock_c := Vector2.ZERO
	if shock:
		for p in shock_pts:
			shock_c += p
		shock_c /= float(shock_pts.size())
		flashes.append({ "pos": shock_c, "life": 0.55, "r": shock_r })
		shake = minf(2.0, shake + 0.5)
		for n in 20:
			particles.append({ "pos": shock_c, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(160.0, 380.0), "life": randf_range(0.3, 0.6) })

	# Squares — normal reach from the moon, OR caught in the shockwave. Up to the carry cap.
	for i in range(materials.size() - 1, -1, -1):
		var m: Dictionary = materials[i]
		var smp := ring_point(ring_r(1), m.angle)
		if mw.distance_to(smp) < pickup_radius * rm or (shock and shock_c.distance_to(smp) < shock_r):
			var sp := smp + Vector2(0, -26)
			if m.ready > 0.0:
				popups.append({ "pos": sp, "text": "NOT READY", "life": 0.6, "size": 14 })
				did = true
			elif inventory >= max_inventory:
				popups.append({ "pos": sp, "text": "FULL INVENTORY", "life": 0.6, "size": 14 })
				did = true
			else:
				collect_square(i)
				did = true

	# Enemies — normal reach (with the mid-air instakill) OR the shockwave (always a normal 1 HP).
	var hit_enemy := false
	for t in threats:
		var ep := ring_point(t.radius, t.angle)
		var in_normal: bool = mw.distance_to(ep) < enemy_hit_dist * rm
		var in_shock: bool = shock and shock_c.distance_to(ep) < shock_r
		if not (in_normal or in_shock):
			continue
		var midair: bool = in_normal and moving and not t.latched
		if midair:
			t.hp = 0
		else:
			t.hp -= 1
		t.cd = asteroid_hit_cd   # a successful hit suppresses the contact-slow this pass
		hit_enemy = true
		did = true
		shake = minf(1.8, shake + (0.5 if t.hp <= 0 else 0.25))
		for i in (10 if t.hp <= 0 else 5):
			particles.append({ "pos": ep, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(120.0, 280.0), "life": randf_range(0.2, 0.5) })
		if midair:
			popups.append({ "pos": ep + Vector2(0, -30), "text": "MID-AIR KILL BONUS", "life": 0.9, "size": 18 })
	if hit_enemy:
		threats = threats.filter(func(t): return t.hp > 0)

	# Asteroids — normal hit needs you on ring 2 within tol; the shockwave reaches any in blast range.
	if unlocked >= 3:
		var hit_ast := false
		for ast in asteroids:
			var ap := ring_point(ring_r(2), ast.angle)
			var in_normal_a: bool = current_ring == 2 and absf(wrapf(angle - ast.angle, -PI, PI)) < asteroid_tol * rm
			var in_shock_a: bool = shock and shock_c.distance_to(ap) < shock_r
			if not (in_normal_a or in_shock_a):
				continue
			ast.hits_left -= 1
			hit_ast = true
			did = true
			shake = minf(1.8, shake + 0.3)
			for i in 6:
				particles.append({ "pos": ap, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(90.0, 200.0), "life": randf_range(0.2, 0.45) })
			if ast.hits_left <= 0:
				asteroid_mats += 1
				asteroid_respawn = asteroid_respawn_delay
				popups.append({ "pos": ap, "text": "+1 COMET", "life": 0.7, "size": 16 })
		if hit_ast:
			asteroids = asteroids.filter(func(a): return a.hits_left > 0)
	return did


func do_boost(li: int) -> void:
	var la: float = lights[li]
	var q := clampf(1.0 - (display_radius * absf(wrapf(angle - la, -PI, PI))) / gate_dist, 0.0, 1.0)
	combo += 1
	var gain := boost_base * (0.5 + 0.5 * q)
	if combo % combo_every == 0:   # every 3rd-in-a-row: a bonus boost
		gain *= combo_boost_mult
		popups.append({ "pos": ring_point(display_radius, la) + Vector2(0, -28), "text": "COMBO BOOST", "life": 1.0, "size": 26 })
	speed = minf(max_speed, speed + gain)
	shake = minf(1.6, shake + 0.35 + 0.4 * q)
	var lp := ring_point(display_radius, la)
	for i in 12:
		particles.append({ "pos": lp, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(110.0, 280.0), "life": randf_range(0.25, 0.55) })
	flashes.append({ "pos": lp, "life": 0.35 })
	popups.append({ "pos": lp, "text": ("PERFECT" if q > 0.75 else "x%d" % combo), "life": 0.7, "size": 18 })
	if q > 0.75:
		hitstop = hitstop_time
	lights.remove_at(li)
	if lights.is_empty():   # whole batch used — respawn after the delay
		var mult := dying_delay_mult if light_dying() else 1.0
		light_timer = light_delay * mult + randf_range(-light_delay_jitter, light_delay_jitter)


func arrive_at_hub() -> void:
	# Carried squares ARE the wallet now (no banking) — just flag the shop to open.
	hub_pending = unlocked >= 2   # shop opens once the inner ring is clear of enemies


func buy(node: Dictionary) -> void:
	var id: String = node.id
	if bought.get(id, 0) >= 1:
		return
	if not req_met(node.req):   # prerequisite not owned
		return
	var cur: String = node.cur
	var have: int = inventory if cur == "sq" else asteroid_mats
	var cost: int = node.cost
	var mat_cost: int = int(node.get("mat", 0))   # optional secondary cost (e.g. Double lights)
	if have < cost or asteroid_mats < mat_cost:
		return
	if cur == "sq":
		inventory -= cost
	else:
		asteroid_mats -= cost
	asteroid_mats -= mat_cost
	bought[id] = 1
	match node.eff:
		"material":  material_max += 1
		"inv":       max_inventory += int(node.get("amt", 3))
		"reach":     reach_level += 1
		"core":      core_cap *= 2.0
		"boost":     boost_base *= (1.0 + boost_up); light_cost += 1.0
		"fast1":     light_delay = 1.5
		"fast2":     light_delay = 1.0
		"dual":      light_count = 2
		"horns":     has_horns = true; asteroid_hits = 2
		"horns2":    has_horns2 = true; asteroid_hits = 1
		"asteroids": asteroid_max += 1
		"matboost":  has_material_boost = true
		"ramming":   has_ramming = true
		"vacuum":    has_vacuum = true
	make_shops()


# ── Rendering ──────────────────────────────────────────────
func _draw() -> void:
	var font: Font = ui_font
	var t := speed_t()
	# Camera: view_scale frames the ring; cam_zoom/cam_focus add the near-seal punch-in.
	var z := view_scale * cam_zoom
	var c := screen_center() + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 9.0 - cam_focus * z
	# Background first (behind the world); the grid line-shine follows the moon and each enemy.
	var glow_pts: Array = [{ "pos": c + moon_world() * z, "tint": Color(1, 1, 1) }]
	for tr in threats:
		glow_pts.append({ "pos": c + ring_point(tr.radius, tr.angle) * z, "tint": style.ring_locked })
	_draw_background(glow_pts)

	# Rings (sealed = bright ring, unsealed-unlocked = dim, locked = very dim).
	for i in 3:
		if i >= unlocked and not sealed[i]:
			continue
		var col := style.ring_locked
		if sealed[i]:
			col = style.ring_sealed
		if sealed[i]:
			draw_glow_arc(c, ring_r(i) * z, 0.0, TAU, 96, col, style.ring_w_sealed)
		else:
			draw_arc(c, ring_r(i) * z, 0.0, TAU, 96, col, style.ring_w_locked)

	# The comet tail: cyan particles the moon drops as it flies; they linger and fade.
	for cp in comet:
		var cpos: Vector2 = cp.pos
		var clf: float = cp.life
		var f := clampf(clf / tail_life, 0.0, 1.0)
		# Ease-out (quadratic): bright for most of the life, then a quick fade at the tail end.
		var fa := 1.0 - (1.0 - f) * (1.0 - f)
		var col := style.tail
		col.a = style.tail.a * fa
		draw_circle(c + cpos * z, comet_dot * z * (0.4 + 0.6 * fa), col)

	# Core — a filled disc (no outline) whose color + emission ramp from the darkest background
	# (low) up to the light's color at the ceiling (core_color_max), so it brightens/darkens with
	# health. A rounded fill healthbar beneath shows current core / capacity.
	var pr := planet_draw_radius() * z
	var energy := clampf(core / maxf(1.0, core_color_max), 0.0, 1.0)
	for gi in range(5, 0, -1):
		var lt := float(gi) / 5.0
		var gc := style.light_idle
		gc.a = energy * 0.55 * (1.0 - lt) * (1.0 - lt)   # strong emission only when energized
		draw_circle(c, pr * (1.0 + 1.4 * lt), gc)
	draw_circle(c, pr, style.bg_top.lerp(style.light_idle, energy))
	if unlocked >= 2:
		draw_fill_bar(c.x, c.y + pr + 18.0, 190.0, 16.0, clampf(core / maxf(0.01, core_cap), 0.0, 1.0), style.light_idle)

	# Shop is blocked by living enemies: prompt above the planet while waiting at the hub.
	if hub_pending and not shop_open and current_ring == 0 and not threats.is_empty():
		dtext(font, c + Vector2(-450, -planet_draw_radius() * z - 40.0), "KILL ENEMIES TO OPEN THE SHOP",
			HORIZONTAL_ALIGNMENT_CENTER, 900, 26, style.shop_blocked)

	# Blaster beam.
	if beam_on:
		var bd := Vector2(cos(angle), sin(angle))
		var p_in := c + bd * planet_draw_radius() * z
		var p_out := c + bd * ring_r(2) * 1.3 * z
		draw_glow_line(p_in, p_out, style.beam_outer, (beam_width * 2.0) * 80.0 * z)
		draw_line(p_in, p_out, style.beam_core, 3.0)

	# Star dust (middle ring) — bright purple diffuse points; dim while fading in.
	for i in materials.size():
		var m: Dictionary = materials[i]
		var mp := c + ring_point(ring_r(1), m.angle) * z
		var rr := 7.0 * z
		var scol: Color
		if m.ready > 0.0:
			scol = style.square_pending   # fading in until grabbable
			scol.a = style.square_pending.a * clampf(1.0 - m.ready / maxf(0.01, square_ready_time), 0.25, 1.0)
			rr *= 0.7
		else:
			scol = style.square_ready     # grabbable
		draw_point_glow(mp, rr, scol)

	# Asteroids — cyan diffuse points (like star dust), with their hit counter.
	for ast in asteroids:
		var aa: float = ast.angle
		var hl: int = ast.hits_left
		var ap := c + ring_point(ring_r(2), aa) * z
		draw_point_glow(ap, asteroid_radius * 0.8 * z, style.asteroid)
		dtext(font,ap + Vector2(-20, -asteroid_radius * z - 4.0), str(hl), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, style.asteroid_text)

	# Threats (siphoners) — magenta cursor arrows pointing at the planet they hunt.
	for tr in threats:
		var trad: float = tr.radius
		var latched: bool = tr.latched
		var tp := c + ring_point(trad, tr.angle) * z
		var tcol := style.threat_flying if not latched else style.threat_latched
		var rad := threat_radius * z
		var toward: float = tr.angle + PI   # cursor tip faces inward, toward the core
		if latched:
			# Siphoning: a soft pulse + a "sucking" laser drawn from the planet into the cursor.
			var pulse := 0.5 + 0.5 * sin(game_time * 6.0 + tr.angle * 3.0)
			var pin := c + ring_point(planet_draw_radius(), tr.angle) * z
			var beam := tcol
			beam.a = 0.28 + 0.45 * pulse
			draw_glow_line(pin, tp, beam, (3.0 + 4.0 * pulse) * z)
			rad *= 1.0 + 0.18 * pulse
		draw_cursor(tp, rad, toward, tcol)
		var thp: int = tr.hp
		dtext(font,tp + Vector2(-20, -rad - 6.0), str(thp), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, style.threat_text)

	# Lights — a bright yellow point on the ring at the gate. A touch bigger than star dust
	# so it's easy to spot and hit. Brightens + grows a little when you're in it.
	for i in lights.size():
		var ang: float = lights[i]
		var on: bool = display_radius * absf(wrapf(angle - ang, -PI, PI)) <= gate_dist
		var idle_col := style.light_dying if light_dying() else style.light_idle   # warns (orange) as the core dies
		var col := style.light_on if on else idle_col
		var pulse := 0.5 + 0.5 * sin(game_time * 4.0 + ang * 2.0)
		var lp := c + ring_point(display_radius, ang) * z
		var r := (10.0 + (2.5 if on else 0.0) + 1.5 * pulse) * z
		draw_point_glow(lp, r, col)

	for fl in flashes:
		var fa := clampf(fl.life / 0.6, 0.0, 1.0)
		var maxr: float = fl.get("r", 120.0)   # shockwaves pass a larger radius
		var flcol := style.flash
		flcol.a = style.flash.a * fa
		draw_arc(c + fl.pos * z, (1.0 - fa) * maxr + 6.0, 0.0, TAU, 32, flcol, 3.0)

	# Flying star dust (feed animation).
	for f in flying:
		var fst: Vector2 = f.start
		var fft: float = f.t
		var wpos := fst.lerp(Vector2.ZERO, fft)
		var fr := 6.0 * z * (1.0 - 0.4 * fft)
		draw_point_glow(c + wpos * z, fr, style.square_ready)

	# Carried star dust trailing the moon.
	var carried := mini(inventory, 8)
	for j in carried:
		var idx := trail.size() - 2 - j * 3
		if idx >= 0:
			var tpos: Vector2 = trail[idx]
			draw_point_glow(c + tpos * z, 5.0 * z, style.square_ready)

	# Moon (the comet head) — the same glowing point as the boost lights, but kept cyan.
	var mpulse := 0.5 + 0.5 * sin(game_time * 4.0)
	draw_point_glow(c + moon_world() * z, (moon_radius + 1.5 * mpulse) * z, style.moon_slow.lerp(style.moon_fast, t))

	for pu in popups:
		var qa := clampf(pu.life * 1.6, 0.0, 1.0)
		dtext(font, c + pu.pos * z + Vector2(-110, 0), pu.text, HORIZONTAL_ALIGNMENT_CENTER, 220, pu.size, Color(1, 1, 1, qa))

	_draw_hud(font)


# ── Reskin render helpers ──────────────────────────────────
# Full-viewport background painted before the world. No-op for the base look (bg colors
# are transparent). Reskins set bg_top/bg_bottom for a sky gradient, and optionally a
# starfield or a silhouette treeline.
func _draw_background(glow_points: Array) -> void:
	var vp := get_viewport_rect().size
	if style.bg_top.a > 0.0 or style.bg_bottom.a > 0.0:
		var n := maxi(1, style.bg_bands)
		for i in n:
			var f := float(i) / float(n)
			var col: Color
			if style.use_bg_mid:
				col = style.bg_top.lerp(style.bg_mid, f * 2.0) if f < 0.5 else style.bg_mid.lerp(style.bg_bottom, (f - 0.5) * 2.0)
			else:
				col = style.bg_top.lerp(style.bg_bottom, f)
			draw_rect(Rect2(0.0, vp.y * float(i) / float(n), vp.x, vp.y / float(n) + 1.0), col)
	if style.enable_grid:
		_draw_grid(vp, glow_points)
	if style.enable_starfield:
		_draw_starfield(vp)
	if style.enable_shooting_stars:
		_draw_shooting_stars(vp)
	if style.enable_treeline:
		_draw_treeline(vp)


func _draw_grid(vp: Vector2, glow_points: Array) -> void:
	# Faint, uniform neon grid.
	var sp := maxf(8.0, style.grid_spacing)
	var x := 0.0
	while x <= vp.x:
		draw_line(Vector2(x, 0), Vector2(x, vp.y), style.grid_color, 1.0)
		x += sp
	var y := 0.0
	while y <= vp.y:
		draw_line(Vector2(0, y), Vector2(vp.x, y), style.grid_color, 1.0)
		y += sp
	# Each glow point (the moon, plus every enemy) shines the grid patch around it.
	for gp in glow_points:
		_grid_shine(vp, sp, gp.pos, gp.tint)


# Local shine: only the patch of grid right around `center` brightens (2D falloff), drawn as
# short segments so whole lines don't light up — just the area the source is over.
func _grid_shine(vp: Vector2, sp: float, center: Vector2, tint: Color) -> void:
	var rad := maxf(1.0, grid_glow_radius)
	var step := 16.0
	var gx := ceilf((center.x - rad) / sp) * sp
	while gx <= center.x + rad:
		if gx >= 0.0 and gx <= vp.x:
			var yy := center.y - rad
			while yy <= center.y + rad:
				var k := clampf(1.0 - Vector2(gx, yy + step * 0.5).distance_to(center) / rad, 0.0, 1.0)
				if k > 0.02:
					var col := style.grid_color.lerp(Color(tint.r, tint.g, tint.b, style.grid_color.a), 0.3 * k)
					col.a = clampf(grid_glow_strength * k, 0.0, 1.0)
					draw_line(Vector2(gx, yy), Vector2(gx, yy + step), col, 1.0 + k * 1.5)
				yy += step
		gx += sp
	var gy := ceilf((center.y - rad) / sp) * sp
	while gy <= center.y + rad:
		if gy >= 0.0 and gy <= vp.y:
			var xx := center.x - rad
			while xx <= center.x + rad:
				var k := clampf(1.0 - Vector2(xx + step * 0.5, gy).distance_to(center) / rad, 0.0, 1.0)
				if k > 0.02:
					var col := style.grid_color.lerp(Color(tint.r, tint.g, tint.b, style.grid_color.a), 0.3 * k)
					col.a = clampf(grid_glow_strength * k, 0.0, 1.0)
					draw_line(Vector2(xx, gy), Vector2(xx + step, gy), col, 1.0 + k * 1.5)
				xx += step
		gy += sp


func _draw_shooting_stars(vp: Vector2) -> void:
	# Deterministic streaks: each star cycles on its own period from game_time, sweeping a
	# diagonal line across the sky, visible only for a slice of its cycle.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in style.shoot_count:
		var period := rng.randf_range(6.0, 12.0)
		var phase := fposmod(game_time + rng.randf() * period, period) / period
		if phase > 0.18:
			continue   # off-screen most of the cycle
		var p := phase / 0.18
		var y0 := rng.randf_range(0.0, vp.y * 0.55)
		var dir := Vector2(1.0, 0.35).normalized()
		var span := vp.x * 0.5
		var head := Vector2(-100.0 + (vp.x + 200.0) * p, y0)
		var tail := head - dir * span * 0.18
		var col := style.shoot_color
		col.a = style.shoot_color.a * sin(p * PI)   # fade in then out
		draw_line(tail, head, col, 2.0)
		draw_circle(head, 2.2, col)


func _draw_starfield(vp: Vector2) -> void:
	# Deterministic (seeded) so stars stay put; only twinkle animates.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in style.star_count:
		var p := Vector2(rng.randf() * vp.x, rng.randf() * vp.y)
		var rr := rng.randf_range(0.6, 1.9)
		var a := style.star_color.a
		if style.star_twinkle > 0.0:
			a *= 1.0 - style.star_twinkle * (0.5 + 0.5 * sin(game_time * 2.2 + float(i) * 1.7))
		var col := style.star_color
		col.a = clampf(a, 0.0, 1.0)
		draw_circle(p, rr, col)


func _draw_treeline(vp: Vector2) -> void:
	# Simple triangle silhouette band along the bottom — a cheap storybook horizon.
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var n := 26
	for i in n:
		var x := vp.x * float(i) / float(n - 1)
		var w := vp.x / float(n) * rng.randf_range(0.7, 1.4)
		var h := style.treeline_height * rng.randf_range(0.45, 1.2)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - w * 0.5, vp.y), Vector2(x, vp.y - h), Vector2(x + w * 0.5, vp.y)
		]), style.treeline_color)


# Fake bloom: stack N concentric draws with growing size + decaying alpha, then the crisp
# core on top. Gated by style.glow_enable so the base look pays nothing. Respects col.a.
func draw_glow_circle(pos: Vector2, r: float, col: Color) -> void:
	if style.glow_enable:
		for i in range(style.glow_layers, 0, -1):
			var lt := float(i) / float(style.glow_layers)
			var gc := col
			gc.a = col.a * style.glow_alpha * (1.0 - lt) * (1.0 - lt)
			draw_circle(pos, r * (1.0 + (style.glow_spread - 1.0) * lt), gc)
	draw_circle(pos, r, col)


func draw_glow_arc(center: Vector2, radius: float, a0: float, a1: float, points: int, col: Color, base_w: float) -> void:
	if style.glow_enable:
		for i in range(style.glow_layers, 0, -1):
			var lt := float(i) / float(style.glow_layers)
			var gc := col
			gc.a = col.a * style.glow_alpha * (1.0 - lt) * (1.0 - lt)
			draw_arc(center, radius, a0, a1, points, gc, base_w * (1.0 + (style.glow_spread - 1.0) * lt * 2.0))
	draw_arc(center, radius, a0, a1, points, col, base_w)


func draw_glow_line(a: Vector2, b: Vector2, col: Color, base_w: float) -> void:
	if style.glow_enable:
		for i in range(style.glow_layers, 0, -1):
			var lt := float(i) / float(style.glow_layers)
			var gc := col
			gc.a = col.a * style.glow_alpha * (1.0 - lt) * (1.0 - lt)
			draw_line(a, b, gc, base_w * (1.0 + (style.glow_spread - 1.0) * lt * 2.0))
	draw_line(a, b, col, base_w)


# A bright point wrapped in lots of soft diffuse light (star dust / asteroids / gate blooms).
# Always on (palette-driven), independent of glow_enable so these objects read as "lit".
func draw_point_glow(pos: Vector2, r: float, col: Color) -> void:
	var layers := 5
	for i in range(layers, 0, -1):
		var lt := float(i) / float(layers)
		var gc := col
		gc.a = col.a * 0.30 * (1.0 - lt) * (1.0 - lt)
		draw_circle(pos, r * (1.0 + 3.0 * lt), gc)
	var mid := col
	mid.a = col.a * 0.85
	draw_circle(pos, r, mid)
	draw_circle(pos, r * 0.5, col.lerp(Color(1, 1, 1, col.a), 0.5))   # whitened lit core


# A rounded fill bar (borrowed from Pleenko's FillBar look): dark rounded track + a rounded
# fill that grows with `frac`. Centered horizontally on `cx`, top at `top_y`.
func draw_fill_bar(cx: float, top_y: float, w: float, h: float, frac: float, fill_col: Color) -> void:
	var x := cx - w * 0.5
	_capsule(x - 2.0, top_y - 2.0, w + 4.0, h + 4.0, Color(0.03, 0.02, 0.06, 0.92))   # border
	_capsule(x, top_y, w, h, Color(0.12, 0.1, 0.18, 1.0))                              # track
	var fw := clampf(frac, 0.0, 1.0) * w
	if fw >= h:
		_capsule(x, top_y, fw, h, fill_col)
	elif fw > 0.0:
		draw_circle(Vector2(x + h * 0.5, top_y + h * 0.5), h * 0.5 * (fw / h), fill_col)


# A horizontal capsule (rect with rounded ends) — the rounded-corner look of a Pleenko bar.
func _capsule(x: float, y: float, w: float, h: float, col: Color) -> void:
	var r := h * 0.5
	if w <= h:
		draw_circle(Vector2(x + w * 0.5, y + r), minf(r, w * 0.5), col)
		return
	draw_rect(Rect2(x + r, y, w - h, h), col)
	draw_circle(Vector2(x + r, y + r), r, col)
	draw_circle(Vector2(x + w - r, y + r), r, col)


# A skinny triangle OUTLINE (no fill), tip pointing along `rot`. Used for siphoner enemies.
# Outline drawn at the unsealed-ring thickness; its "glow" comes from the background line-shine.
func draw_cursor(pos: Vector2, s: float, rot: float, col: Color) -> void:
	var ca := cos(rot)
	var sa := sin(rot)
	var local := [Vector2(s, 0.0), Vector2(-s * 0.72, -s * 0.6), Vector2(-s * 0.72, s * 0.6)]
	var pts := PackedVector2Array()
	for p in local:
		pts.append(pos + Vector2(p.x * ca - p.y * sa, p.x * sa + p.y * ca))
	pts.append(pts[0])   # close the loop
	draw_polyline(pts, col, style.ring_w_locked)


# Scaled text helper — same arg order as draw_string, but the font size is multiplied by
# ui_text_scale. Used everywhere except the shop modal (its layout is sized to fixed fonts).
func dtext(f: Font, pos: Vector2, text: String, align: int, width: float, size: int, color: Color) -> void:
	draw_string(f, pos, text, align, width, int(round(float(size) * ui_text_scale)), color)


# Draw a square icon centered at `center`, side `sz`, rotated `rot` radians (PI = flipped).
func draw_icon(tex: Texture2D, center: Vector2, sz: float, rot: float) -> void:
	draw_set_transform(center, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_hud(font: Font) -> void:
	var vp := get_viewport_rect().size
	# Resource readouts appear only once they matter: star dust at ring 2, star core at ring 3.
	var res := ""
	if unlocked >= 2:
		res = "STAR DUST %d/%d" % [inventory, max_inventory]
	if unlocked >= 3:
		res += "      COMETS %d" % asteroid_mats
	if res != "":
		dtext(font, Vector2(22, 56), res, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, style.hud_text)
	# Core too low to make lights: head home to refill (it won't kill you, just dries up).
	if phase == "play" and unlocked >= 2 and lights.is_empty() and core <= light_cost:
		dtext(font, Vector2(22, 104), "CORE LOW — RETURN HOME TO REFILL",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, style.hud_warn)

	# Clickable pause button (top-right). Pause bars while playing; play triangle while paused.
	if phase == "play" and started and not shop_open and not confirm_reset:
		var r := pause_btn_rect()
		draw_rect(r, Color(0.1, 0.06, 0.18, 0.5))
		var bc := r.position + r.size * 0.5
		if paused:
			var ps := r.size.x * 0.24
			draw_colored_polygon(PackedVector2Array([bc + Vector2(-ps * 0.7, -ps), bc + Vector2(ps, 0), bc + Vector2(-ps * 0.7, ps)]), style.banner_pause)
		else:
			draw_pause_bars(bc, r.size.x * 0.26, style.banner_pause)

	var sc := screen_center()
	# Centered banners — CENTER alignment in a wide box so they stay centered at any text scale.
	if paused:
		draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.45))   # dim the world
		draw_pause_bars(sc + Vector2(0, -40), 46.0, style.banner_pause)
	elif not started and phase == "play":
		dtext(font, sc + Vector2(-500, -180), "PRESS SPACE TO LAUNCH", HORIZONTAL_ALIGNMENT_CENTER, 1000, 26, style.banner_launch)
	elif phase == "won":
		dtext(font, sc + Vector2(-500, -180), "PLANET SAVED!  (R)", HORIZONTAL_ALIGNMENT_CENTER, 1000, 30, style.banner_win)
	elif phase == "dead":
		dtext(font, sc + Vector2(-500, -180), "%s  (R)" % dead_reason, HORIZONTAL_ALIGNMENT_CENTER, 1000, 24, style.banner_lose)
	elif banner_timer > 0.0:
		dtext(font, sc + Vector2(-500, -180), banner_text, HORIZONTAL_ALIGNMENT_CENTER, 1000, 24, style.banner_info)

	# One-time ring-nav hint — "PRESS [↑] AND [↓]" with the arrow icons standing in for the
	# words. Laid out by hand (text + icon + text + icon + text) and centered along the top.
	if nav_hint_show:
		var hfs := int(round(22.0 * ui_text_scale))
		var hcol: Color = style.banner_info
		var p_pre := "PRESS ["
		var p_mid := "] AND ["
		var p_end := "]"
		var asc := font.get_ascent(hfs)
		var isz := float(hfs) * 1.2   # arrow side ≈ text cap height
		var w_pre := font.get_string_size(p_pre, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
		var w_mid := font.get_string_size(p_mid, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
		var w_end := font.get_string_size(p_end, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs).x
		var hx := sc.x - (w_pre + isz + w_mid + isz + w_end) * 0.5
		var hbase := 60.0 + asc          # text baseline
		var hmid := 60.0 + asc * 0.55    # icon vertical center, roughly on the text's midline
		draw_string(font, Vector2(hx, hbase), p_pre, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, hcol)
		hx += w_pre
		draw_icon(arrow_tex, Vector2(hx + isz * 0.5, hmid), isz, 0.0)
		hx += isz
		draw_string(font, Vector2(hx, hbase), p_mid, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, hcol)
		hx += w_mid
		draw_icon(arrow_tex, Vector2(hx + isz * 0.5, hmid), isz, PI)
		hx += isz
		draw_string(font, Vector2(hx, hbase), p_end, HORIZONTAL_ALIGNMENT_LEFT, -1, hfs, hcol)

	if shop_open:
		draw_shop_modal(font)
	if confirm_reset:
		draw_confirm_modal(font)


# Two vertical bars (the pause glyph borrowed from Pleenko's pause icon), centered on `center`.
func draw_pause_bars(center: Vector2, h: float, col: Color) -> void:
	var bw := h * 0.36
	var gap := h * 0.30
	draw_rect(Rect2(center.x - gap - bw, center.y - h, bw, h * 2.0), col)
	draw_rect(Rect2(center.x + gap, center.y - h, bw, h * 2.0), col)


func pause_btn_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var s := 46.0
	return Rect2(vp.x - s - 26.0, 26.0, s, s)


# "Are you sure?" overlay shown when R is pressed mid-run (Pleenko-style restart confirm).
func draw_confirm_modal(font: Font) -> void:
	confirm_hit.clear()
	var vp := get_viewport_rect().size
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.72))
	var pw := 560.0
	var ph := 250.0
	var px := (vp.x - pw) * 0.5
	var py := (vp.y - ph) * 0.5
	draw_rect(Rect2(px - 3, py - 3, pw + 6, ph + 6), style.banner_pause)   # cyan border
	draw_rect(Rect2(px, py, pw, ph), Color(0.08, 0.05, 0.14, 0.99))
	draw_string(font, Vector2(px, py + 76), "ARE YOU SURE?", HORIZONTAL_ALIGNMENT_CENTER, pw, 40, style.banner_pause)
	draw_string(font, Vector2(px, py + 116), "Restart — all progress will be lost.", HORIZONTAL_ALIGNMENT_CENTER, pw, 22, Color(0.7, 0.75, 0.85))

	var bw := 210.0
	var bh := 58.0
	var gap := 36.0
	var by := py + ph - bh - 28.0
	var yx := px + (pw - (bw * 2.0 + gap)) * 0.5
	var nx := yx + bw + gap
	var yrect := Rect2(yx, by, bw, bh)
	var nrect := Rect2(nx, by, bw, bh)
	draw_rect(yrect, Color(0.5, 0.16, 0.34))   # restart
	draw_rect(nrect, Color(0.14, 0.32, 0.4))   # cancel
	draw_string(font, Vector2(yx, by + 38), "[Y]  RESTART", HORIZONTAL_ALIGNMENT_CENTER, bw, 26, Color(1, 1, 1))
	draw_string(font, Vector2(nx, by + 38), "[N]  CANCEL", HORIZONTAL_ALIGNMENT_CENTER, bw, 26, Color(1, 1, 1))
	confirm_hit.append({ "rect": yrect, "action": "yes" })
	confirm_hit.append({ "rect": nrect, "action": "no" })


func draw_shop_modal(font: Font) -> void:
	shop_hit.clear()
	var vp := get_viewport_rect().size
	draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.72))   # dim the world behind

	var has_battle := unlocked >= 3
	var rowh := 60.0
	var sect_h := 38.0
	var head_h := 120.0
	var foot_h := 86.0
	var pw := 780.0
	var ph := head_h + sect_h + shop_sq.size() * rowh + foot_h
	if has_battle:
		ph += sect_h + shop_bt.size() * rowh
	var px := (vp.x - pw) * 0.5
	var py := (vp.y - ph) * 0.5

	draw_rect(Rect2(px - 3, py - 3, pw + 6, ph + 6), Color(0.45, 0.55, 0.75))   # border
	draw_rect(Rect2(px, py, pw, ph), Color(0.09, 0.10, 0.14, 0.99))
	draw_string(font, Vector2(px, py + 48), "UPGRADES", HORIZONTAL_ALIGNMENT_CENTER, pw, 36, Color(1, 1, 0.8))
	draw_string(font, Vector2(px, py + 88), "STAR DUST %d/%d        COMETS %d        CORE %d/%d" % [inventory, max_inventory, asteroid_mats, int(core), int(core_cap)],
		HORIZONTAL_ALIGNMENT_CENTER, pw, 22, Color(0.78, 0.85, 0.95))

	var y := py + head_h
	y = _modal_section(font, "ECONOMY", shop_sq, "sq", px, y, pw, rowh, sect_h, 1)
	if has_battle:
		y = _modal_section(font, "BATTLE", shop_bt, "ast", px, y, pw, rowh, sect_h, shop_sq.size() + 1)

	# Back button.
	var bw := 240.0
	var bh := 54.0
	var bx := px + (pw - bw) * 0.5
	var by := py + ph - foot_h + 16.0
	draw_rect(Rect2(bx, by, bw, bh), Color(0.28, 0.30, 0.40))
	draw_string(font, Vector2(bx, by + 36), "[ B ]   BACK", HORIZONTAL_ALIGNMENT_CENTER, bw, 26, Color(1, 1, 1))
	shop_hit.append({ "rect": Rect2(bx, by, bw, bh), "action": "back", "list": "", "idx": 0 })


func _modal_section(font: Font, header: String, items: Array, cur: String, px: float, y0: float, pw: float, rowh: float, sect_h: float, key_base: int) -> float:
	draw_string(font, Vector2(px + 30, y0 + 26), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.9, 0.9, 0.55))
	var y := y0 + sect_h
	for i in items.size():
		var item: Dictionary = items[i]
		var rect := Rect2(px + 26, y + 4, pw - 52, rowh - 8)
		var have: int = inventory if cur == "sq" else asteroid_mats
		var mat_cost: int = int(item.get("mat", 0))
		var afford: bool = have >= int(item.cost) and asteroid_mats >= mat_cost
		draw_rect(rect, Color(0.15, 0.24, 0.18) if afford else Color(0.16, 0.18, 0.23))
		var name_col := Color(0.96, 0.98, 0.96) if afford else Color(0.72, 0.72, 0.78)
		draw_string(font, rect.position + Vector2(16, 30), "[%d]  %s" % [key_base + i, item.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 23, name_col)
		var cost_label := "%d %s" % [int(item.cost), "dust" if cur == "sq" else "comet"]
		if mat_cost > 0:
			cost_label += " + %d comet" % mat_cost
		draw_string(font, rect.position + Vector2(0, 30), cost_label, HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 18, 21, name_col)
		draw_string(font, rect.position + Vector2(18, 50), item.get("desc", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.64, 0.66, 0.72))
		shop_hit.append({ "rect": rect, "action": "buy", "list": cur, "idx": i })
		y += rowh
	return y
