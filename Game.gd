extends Node2D
# GRAY BOX — "Save the Planet" (comet-tail). The moon is a comet whose TAIL LENGTH is a
# live readout of SPEED. When the tail wraps a full 360° and touches its own head, that
# ring SEALS (permanent). Seal the three rings outward to save the planet (win). Core
# depletion = lose. Squares (ring 2) feed the core; overflow = square-credits for ECONOMY
# upgrades. Asteroids (ring 3) = mat for BATTLE upgrades; siphoners attack the core.
# Target: a complete, beautiful 5-10 min arc. One file. Disposable.

# ── Rings ──────────────────────────────────────────────────
@export var base_radius := 180.0
@export var ring_gap := 300.0
@export var planet_radius := 40.0
@export var planet_grow_step := 14.0    # planet heals a step per ring sealed
@export var moon_radius := 12.0
@export var traverse_time := 2.0
@export var traverse_cost := 300.0
@export var view_margin := 0.80
@export var max_zoom := 2.2             # cap on zoom-in (lets the small inner ring fill the view)

# ── Tail / speed ───────────────────────────────────────────
@export var tail_life := 1.6            # seconds a tail particle lingers; sealing = lap within this time
@export var feed_up := 5.0              # +50% of base feed per Bigger-squares level (10->15->20->25)
@export var tail_color := Color(1.0, 0.85, 0.2)   # yellow comet tail
@export var comet_emit_step := 0.04     # rad spacing between emitted tail particles
@export var comet_dot := 5.0            # tail particle radius (world px)
@export var seal_near := 0.70           # tail fraction of full at which the seal cinematic engages
@export var seal_slowmo := 0.15         # steady time scale held through the seal (pleenko orange-unlock value)
@export var seal_zoom := 1.9            # camera punch-in during the seal
@export var seal_zoom_time := 0.5       # s to become fully zoomed in
@export var reveal_dur := 1.8           # s the camera zooms out to show the newly opened ring
@export var gate_dist := 50.0           # px along the ring to accept a light (same on every ring)
@export var light_delay := 2.0
@export var light_delay_jitter := 0.25
@export var light_cost := 1.0
@export var light_min_speed := 100.0              # at/below this speed the arc uses its "slow" range
@export var light_tween_speed := 2000.0           # speed at which the arc range reaches its "fast" values
@export var light_arc_slow := Vector2(15.0, 40.0)   # min/max degrees ahead at light_min_speed
@export var light_arc_fast := Vector2(90.0, 270.0)  # min/max degrees ahead at light_tween_speed+
@export var start_speed := 0.0
@export var min_speed := 0.0
@export var death_speed := 0.0
@export var stall_decay := 120.0
@export var max_speed := 4000.0
@export var boost_base := 125.0
@export var boost_up := 0.5             # Boost-power upgrade multiplies boost_base by (1 + this)
@export var combo_every := 3            # every Nth consecutive hit gives a combo boost
@export var combo_boost_mult := 1.5     # that hit's boost is multiplied by this
@export var sealed_decay_mult := 0.5    # core decay on a SEALED ring is halved
@export var base_decay := 25.0
@export var whiff_slow := 0.85
@export var hitstop_time := 0.05
@export var seal_hitstop := 0.18

# ── Core / squares ─────────────────────────────────────────
@export var core_start := 5.0
@export var core_cap := 5.0
@export var feed_per_square := 5.0
@export var material_max := 1             # squares on the ring (doubles per upgrade)
@export var square_ready_time := 1.0      # s a freshly-spawned square fades in before it's grabbable
@export var pickup_radius := 90.0
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
@export var threat_speed := 90.0
@export var threat_hp := 2
@export var threat_drain := 1 
@export var ram_radial_tol := 45.0
@export var ram_ang_tol := 0.18
@export var ram_hit_mult := 0.7
@export var threat_ram_cd := 0.4

# ── Blaster ────────────────────────────────────────────────
@export var beam_width := 0.12          # rad half-width of the laser
@export var beam_drain := 3.0           # core/s while firing

# ── State ──────────────────────────────────────────────────
var phase := "play"      # play | stalling | dead | won
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
var view_scale := 1.0
var display_tail := 0.0   # eased tail angle (for subtle growth + the seal check)
var sealing := false      # committed seal cinematic (latched until contact; failsafe-guaranteed)
var seal_anim := 0.0
var time_scale := 1.0
var cam_focus := Vector2.ZERO
var cam_zoom := 1.0
var reveal_timer := 0.0
var game_time := 0.0
var comet: Array = []     # tail particles: { pos:Vector2, life:float, cum:float }
var cum_angle := 0.0      # unwrapped accumulated rotation (drives the seal span)

var core := 0.0
var inventory := 0
var square_credits := 0
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
var shop_open := false
var shop_hit: Array = []   # clickable regions in the upgrade modal: { rect, action, list, idx }

# Upgrades
var has_horns := false
var has_horns2 := false
var has_blasters := false
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
		{ "id":"esq",    "name":"More squares",            "req":"",       "cost":1,  "eff":"material", "cur":"sq", "desc":"Double squares on the ring" },
		{ "id":"ecore1", "name":"More core capacity",      "req":"esq",    "cost":2,  "eff":"core",     "cur":"sq", "desc":"Double the core's capacity" },
		{ "id":"einv1",  "name":"More square capacity",    "req":"esq",    "cost":2,  "eff":"inv",      "cur":"sq", "desc":"Carry +3 more squares" },
		{ "id":"ecore2", "name":"More core capacity II",   "req":"ecore1", "cost":4,  "eff":"core",     "cur":"sq", "desc":"Double the core's capacity" },
		{ "id":"eb1",    "name":"Boost light",             "req":"ecore1", "cost":5,  "eff":"boost",    "cur":"sq", "desc":"Light +50% speed, but +1 core/light" },
		{ "id":"ecore3", "name":"More core capacity III",  "req":"ecore2", "cost":8,  "eff":"core",     "cur":"sq", "desc":"Double the core's capacity" },
		{ "id":"ecore4", "name":"More core capacity IV",   "req":"ecore3", "cost":16, "eff":"core",     "cur":"sq", "desc":"Double the core's capacity" },
		{ "id":"efast1", "name":"Faster lights",           "req":"eb1",            "cost":6,  "eff":"fast1", "cur":"sq", "desc":"Lights respawn faster (1.5s)" },
		{ "id":"efast2", "name":"Faster lights II",        "req":"efast1",         "cost":12, "eff":"fast2", "cur":"sq", "desc":"Lights respawn faster (1.0s)" },
		{ "id":"edual",  "name":"Double lights",           "req":["efast1","eb2"], "cost":11, "eff":"dual",  "cur":"sq", "desc":"Two boost lights at once" },
		{ "id":"eb2",    "name":"Boost light II",          "req":"eb1",    "cost":10, "eff":"boost",    "cur":"sq", "desc":"Light +50% speed, but +1 core/light" },
		{ "id":"eb3",    "name":"Boost light III",         "req":"eb2",    "cost":20, "eff":"boost",    "cur":"sq", "desc":"Light +50% speed, but +1 core/light" },
		{ "id":"einv2",  "name":"More square capacity II", "req":"einv1",  "cost":4,  "eff":"inv",      "cur":"sq", "desc":"Carry +3 more squares" },
		{ "id":"einv3",  "name":"More square capacity III","req":"einv2",  "cost":8,  "eff":"inv",      "cur":"sq", "desc":"Carry +3 more squares" },
		{ "id":"ebig1",  "name":"Bigger squares",          "req":"einv2",  "cost":5,  "eff":"feed",     "cur":"sq", "desc":"Each square feeds +1 more core" },
		{ "id":"ebig2",  "name":"Bigger squares II",       "req":"ebig1",  "cost":13, "eff":"feed",     "cur":"sq", "desc":"Each square feeds +1 more core" },
		{ "id":"esq2",   "name":"More squares II",         "req":"einv1",  "cost":3,  "eff":"material", "cur":"sq", "desc":"Double squares on the ring" },
		{ "id":"esq3",   "name":"More squares III",        "req":"esq2",   "cost":6,  "eff":"material", "cur":"sq", "desc":"Double squares on the ring" },
		{ "id":"esq4",   "name":"More squares IV",         "req":"esq3",   "cost":12, "eff":"material", "cur":"sq", "desc":"Double squares on the ring" },
	]


func battle_nodes() -> Array:
	return [
		{ "id":"armor",    "name":"Armor",    "req":"",      "cost":5,  "eff":"armor",    "cur":"ast", "desc":"Keep more speed when ramming threats" },
		{ "id":"horns",    "name":"Horns",    "req":"",      "cost":5,  "eff":"horns",    "cur":"ast", "desc":"Asteroids crack in 2 hits" },
		{ "id":"horns2",   "name":"Horns II", "req":"horns", "cost":10, "eff":"horns2",   "cur":"ast", "desc":"Asteroids & enemies die in 1 hit, no slowdown" },
		{ "id":"blasters", "name":"Blasters", "req":"",      "cost":10, "eff":"blasters", "cur":"ast", "desc":"Hold F: a beam that vaporizes threats" },
		{ "id":"ast1",     "name":"More asteroids",    "req":"",     "cost":2, "eff":"asteroids", "cur":"ast", "desc":"+1 asteroid on the ring" },
		{ "id":"ast2",     "name":"More asteroids II", "req":"ast1", "cost":5, "eff":"asteroids", "cur":"ast", "desc":"+1 asteroid on the ring" },
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
	square_credits = 0
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
	shop_open = false
	shop_hit.clear()
	has_horns = false
	has_horns2 = false
	has_blasters = false
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
	time_scale = 1.0
	cam_focus = Vector2.ZERO
	cam_zoom = 1.0
	reveal_timer = 0.0
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
	if reveal_timer > 0.0:
		return frame_scale(ring_r(unlocked - 1))   # zoom out to show the newly opened ring
	return frame_scale(display_radius)


func moon_world() -> Vector2:
	return display_radius * Vector2(cos(angle), sin(angle))


func ring_point(r: float, a: float) -> Vector2:
	return r * Vector2(cos(a), sin(a))


func speed_t() -> float:
	return clampf(speed / max_speed, 0.0, 1.0)


func tail_span() -> float:
	# Angular length of the live tail = rotation accumulated while the oldest particle is
	# still alive. The moon "catches its tail" (span >= TAU) by lapping within tail_life.
	if comet.is_empty():
		return 0.0
	var oldest: Dictionary = comet[0]
	return cum_angle - oldest.cum


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
	reveal_timer = reveal_dur   # camera zooms out to reveal the new ring
	banner_text = "RING SEALED — RING %d OPEN" % unlocked
	banner_timer = 2.5
	if unlocked == 2:
		refill_materials()   # ring 2 opens with squares ready to grab
		core = core_cap                  # the planet's core comes online (full)
		enemy_active = true              # the enemy spawn-clock begins
		threat_spawn_count = 0
		threat_timer = enemy_interval(0)
	if unlocked == 3:
		ensure_asteroids()


# ── Sim ────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if phase == "won" or phase == "dead":
		queue_redraw()
		return
	if paused or shop_open:
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
		if phase == "stalling":
			_tick_stall(sim)
		else:
			_tick_play(sim)

	reveal_timer = maxf(0.0, reveal_timer - delta)
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
	for f in flying:
		f.t += delta / maxf(0.01, suck_time)
		if f.t >= 1.0:
			feed_one()
	flying = flying.filter(func(f): return f.t < 1.0)

	queue_redraw()


func _tick_stall(sim: float) -> void:
	speed = maxf(0.0, speed - stall_decay * sim)
	display_radius = ring_r(current_ring)
	angle = wrapf(angle + (speed / display_radius) * sim, -PI, PI)
	_trail()
	if speed <= 1.0:
		phase = "dead"
		if dead_reason == "":
			dead_reason = "YOU STOPPED SPINNING"


func _tick_play(sim: float) -> void:
	if not started:
		return   # parked at the top until the first SPACE launches us
	speed = clampf(speed - cur_decay() * sim, min_speed, max_speed)

	# Blaster core drain.
	if beam_on:
		core = maxf(0.0, core - beam_drain * sim)
		do_beam()

	if speed <= death_speed:
		phase = "stalling"
		return

	# Ring glide (radius drives angular pace).
	if moving:
		move_t += sim / maxf(0.001, traverse_time)
		if move_t >= 1.0:
			move_t = 1.0
			moving = false
			current_ring = move_to
			if current_ring == 0:
				arrive_at_hub()   # bank squares + open the upgrade screen
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


	# Lights spawn as a full batch once the previous batch is fully used; each costs 1 core.
	if lights.is_empty():
		light_timer -= sim
		if light_timer <= 0.0:
			for n in light_count:
				if unlocked < 2:
					lights.append(rand_ahead())           # free before the core exists (ring 1)
				elif core >= light_cost:
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
		if current_ring == 2:
			for ast in asteroids:
				if ast.cd <= 0.0 and absf(wrapf(angle - ast.angle, -PI, PI)) < asteroid_tol:
					if not has_horns2:        # Horns II shatters them with no momentum loss
						speed = speed * asteroid_hit_mult
					ast.cd = asteroid_hit_cd
					ast.hits_left -= 1
					shake = minf(1.8, shake + 0.4)
					var ap := ring_point(ring_r(2), ast.angle)
					for i in 6:
						particles.append({ "pos": ap, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(90.0, 200.0), "life": randf_range(0.2, 0.45) })
					if ast.hits_left <= 0:
						asteroid_mats += 1
						asteroid_respawn = asteroid_respawn_delay   # wait before the next appears
						popups.append({ "pos": ap, "text": "+MAT", "life": 0.7, "size": 16 })
		asteroids = asteroids.filter(func(a): return a.hits_left > 0)

	# Enemies start once ring 2 is unlocked (clock-driven waves).
	if unlocked >= 2:
		_tick_threats(sim)

	# Back at the hub with all enemies cleared -> open the upgrade screen.
	if hub_pending and not shop_open and current_ring == 0 and not moving and threats.is_empty():
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
		threats = threats.filter(func(t): return t.hp > 0)


func enemy_interval(i: int) -> float:
	return [45.0, 40.0, 35.0, 30.0][i % 4]


func enemy_count(i: int) -> int:
	return i / 4 + 1   # +1 enemy each full 4-spawn cycle


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
		# Slamming into an enemy MID-AIR (while traversing between rings) is a 1-hit KO.
		if moving and moon_world().distance_to(ring_point(t.radius, t.angle)) < moon_radius + threat_radius:
			t.hp = 0
			shake = minf(1.8, shake + 0.5)
			var cp := ring_point(t.radius, t.angle)
			for i in 10:
				particles.append({ "pos": cp, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(120.0, 280.0), "life": randf_range(0.2, 0.5) })
		# On a ring you hit them normally — a chip per ram (Horns II makes it a 1-hit KO).
		elif t.hp > 0 and t.cd <= 0.0 and absf(display_radius - t.radius) < ram_radial_tol and absf(wrapf(angle - t.angle, -PI, PI)) < ram_ang_tol:
			t.hp -= 1
			if has_horns2:
				t.hp = 0                                          # Horns II one-shots enemies
			t.cd = threat_ram_cd
			if not has_horns2:
				speed = maxf(min_speed, speed * ram_hit_mult)
			shake = minf(1.8, shake + 0.4)
			var tp := ring_point(t.radius, t.angle)
			for i in 8:
				particles.append({ "pos": tp, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(100.0, 240.0), "life": randf_range(0.2, 0.5) })
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
			KEY_R: reset()
		return

	match k:
		KEY_SPACE:
			if phase == "play":
				if not started:
					started = true        # launch: kick off + the boost below
					speed = start_speed
				try_boost()
		KEY_UP:
			if phase == "play":
				traverse(1)
		KEY_DOWN:
			if phase == "play":
				traverse(-1)
		KEY_P:
			if phase == "play":
				paused = not paused
		KEY_R:
			reset()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse clicks in the upgrade modal (buy rows / back button).
	if not shop_open:
		return
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mp := (event as InputEventMouseButton).position
		for h in shop_hit:
			if (h.rect as Rect2).has_point(mp):
				match h.action:
					"back": shop_open = false
					"buy": buy(shop_sq[h.idx] if h.list == "sq" else shop_bt[h.idx])
				return


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
	inventory += 1
	spawn_square()   # replacement appears immediately (not grabbable until it fades in)
	var mp := ring_point(ring_r(1), ma)
	flashes.append({ "pos": mp, "life": 0.3 })
	popups.append({ "pos": mp, "text": "+1", "life": 0.5, "size": 14 })


func try_boost() -> void:
	var did := false
	var mw := moon_world()
	# Grab EVERY square within reach (up to the carry cap). Iterate back-to-front so removals
	# don't shift the indices we haven't checked yet.
	for i in range(materials.size() - 1, -1, -1):
		var m: Dictionary = materials[i]
		if mw.distance_to(ring_point(ring_r(1), m.angle)) < pickup_radius:
			var sp := ring_point(ring_r(1), m.angle) + Vector2(0, -26)
			if m.ready > 0.0:
				popups.append({ "pos": sp, "text": "NOT READY", "life": 0.6, "size": 14 })
				did = true   # not a whiff — attempting an unripe square doesn't punish you
			elif inventory >= max_inventory:
				popups.append({ "pos": sp, "text": "FULL INVENTORY", "life": 0.6, "size": 14 })
				did = true
			else:
				collect_square(i)
				did = true
	# Boost on EVERY aligned light at once.
	for i in range(lights.size() - 1, -1, -1):
		if display_radius * absf(wrapf(angle - lights[i], -PI, PI)) <= gate_dist:
			do_boost(i)
			did = true
	if not did and not moving:
		combo = 0
		speed = maxf(min_speed, speed * whiff_slow)
		shake = minf(1.5, shake + 0.2)


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
		light_timer = light_delay + randf_range(-light_delay_jitter, light_delay_jitter)


func feed_one() -> void:
	# Core first; overflow becomes square-credits (the economy currency).
	if core < core_cap:
		core = minf(core_cap, core + feed_per_square)
	else:
		square_credits += overflow_mult


func arrive_at_hub() -> void:
	# Reaching the inner ring banks all carried squares, then opens the paused upgrade screen.
	while inventory > 0:
		inventory -= 1
		feed_one()
	hub_pending = unlocked >= 2   # shop opens once any enemies are cleared


func buy(node: Dictionary) -> void:
	var id: String = node.id
	if bought.get(id, 0) >= 1:
		return
	if not req_met(node.req):   # prerequisite not owned
		return
	var cur: String = node.cur
	var have: int = square_credits if cur == "sq" else asteroid_mats
	var cost: int = node.cost
	if have < cost:
		return
	if cur == "sq":
		square_credits -= cost
	else:
		asteroid_mats -= cost
	bought[id] = 1
	match node.eff:
		"material":  material_max *= 2
		"inv":       max_inventory += 3
		"core":      core_cap *= 2.0
		"boost":     boost_base *= (1.0 + boost_up); light_cost += 1.0
		"fast1":     light_delay = 1.5
		"fast2":     light_delay = 1.0
		"dual":      light_count = 2
		"feed":      feed_per_square += 1.0
		"armor":     ram_hit_mult = minf(0.95, ram_hit_mult + 0.05)
		"horns":     has_horns = true; asteroid_hits = 2
		"horns2":    has_horns2 = true; asteroid_hits = 1
		"asteroids": asteroid_max += 1
		"blasters":  has_blasters = true
	make_shops()


# ── Rendering ──────────────────────────────────────────────
func _draw() -> void:
	var font := ThemeDB.fallback_font
	var t := speed_t()
	# Camera: view_scale frames the ring; cam_zoom/cam_focus add the near-seal punch-in.
	var z := view_scale * cam_zoom
	var c := screen_center() + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 9.0 - cam_focus * z
	var spd_col := Color(0.40, 0.70, 1.0).lerp(Color(1.0, 0.55, 0.15), t)

	# Rings (sealed = bright ring, unsealed-unlocked = dim, locked = very dim).
	for i in 3:
		if i >= unlocked and not sealed[i]:
			continue
		var col := Color(0.22, 0.22, 0.30)
		if sealed[i]:
			col = Color(0.5, 0.85, 1.0)
		draw_arc(c, ring_r(i) * z, 0.0, TAU, 96, col, 3.0 if sealed[i] else 2.0)

	# The comet tail: yellow particles the moon drops as it flies; they linger and fade.
	for cp in comet:
		var cpos: Vector2 = cp.pos
		var clf: float = cp.life
		var fa := clampf(clf / tail_life, 0.0, 1.0)
		var col := tail_color
		col.a = fa
		draw_circle(c + cpos * z, comet_dot * z * (0.4 + 0.6 * fa), col)

	# Planet — heals (grows + brightens) with rings sealed.
	var pcol := Color(0.30, 0.22, 0.20).lerp(Color(0.55, 0.9, 0.75), float(sealed_count()) / 3.0)
	draw_circle(c, planet_draw_radius() * z, pcol)

	# Core health bar beneath the planet — only once the core exists (ring 2+).
	if unlocked >= 2:
		var cbw := 170.0
		var cby := c.y + planet_draw_radius() * z + 16.0
		var cbx := c.x - cbw * 0.5
		var cfrac := clampf(core / core_cap, 0.0, 1.0)
		draw_rect(Rect2(cbx - 2, cby - 2, cbw + 4, 16.0), Color(0.05, 0.05, 0.07))
		draw_rect(Rect2(cbx, cby, cbw, 12.0), Color(0.14, 0.14, 0.18))
		draw_rect(Rect2(cbx, cby, cbw * cfrac, 12.0), Color(0.85, 0.3, 0.3).lerp(Color(0.3, 0.85, 0.45), cfrac))
		draw_string(font, Vector2(cbx, cby + 27.0), "CORE %d/%d" % [int(core), int(core_cap)], HORIZONTAL_ALIGNMENT_CENTER, cbw, 13, Color(0.92, 0.92, 0.96))

	# Shop is blocked by living enemies: prompt above the planet while waiting at the hub.
	if hub_pending and not shop_open and current_ring == 0 and not threats.is_empty():
		draw_string(font, c + Vector2(-230, -planet_draw_radius() * z - 34.0), "KILL ENEMIES TO OPEN THE SHOP",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.3, 0.3))

	# Blaster beam.
	if beam_on:
		var bd := Vector2(cos(angle), sin(angle))
		var p_in := c + bd * planet_draw_radius() * z
		var p_out := c + bd * ring_r(2) * 1.3 * z
		draw_line(p_in, p_out, Color(1.0, 0.4, 0.9, 0.9), (beam_width * 2.0) * 80.0 * z)
		draw_line(p_in, p_out, Color(1, 1, 1, 0.9), 3.0)

	# Squares (middle ring) — gray while not yet grabbable, cyan once ready.
	for i in materials.size():
		var m: Dictionary = materials[i]
		var mp := c + ring_point(ring_r(1), m.angle) * z
		var msz := 11.0 * z
		var scol: Color
		if m.ready > 0.0:
			scol = Color(0.5, 0.5, 0.55)   # gray, fading in, until ready
			scol.a = clampf(1.0 - m.ready / maxf(0.01, square_ready_time), 0.25, 1.0)
		else:
			scol = Color(0.4, 0.85, 0.95)  # cyan = grabbable
		draw_rect(Rect2(mp - Vector2(msz, msz) * 0.5, Vector2(msz, msz)), scol)

	# Asteroids.
	for ast in asteroids:
		var aa: float = ast.angle
		var hl: int = ast.hits_left
		var ap := c + ring_point(ring_r(2), aa) * z
		draw_circle(ap, asteroid_radius * z, Color(0.6, 0.55, 0.5))
		draw_string(font, ap + Vector2(-20, -asteroid_radius * z - 4.0), str(hl), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, Color(1, 1, 1))

	# Threats (siphoners).
	for tr in threats:
		var trad: float = tr.radius
		var latched: bool = tr.latched
		var tp := c + ring_point(trad, tr.angle) * z
		var tcol := Color(1.0, 0.3, 0.85) if not latched else Color(1.0, 0.25, 0.25)
		var rad := threat_radius * z
		draw_colored_polygon([tp + Vector2(0, -rad), tp + Vector2(rad, 0), tp + Vector2(0, rad), tp + Vector2(-rad, 0)], tcol)
		draw_string(font, tp + Vector2(-16, -rad - 4.0), str(tr.hp), HORIZONTAL_ALIGNMENT_CENTER, 32, 15, Color(1, 1, 1))

	# Lights.
	for i in lights.size():
		var ang: float = lights[i]
		var lr := display_radius * z
		var half_ang := gate_dist / maxf(1.0, display_radius)   # constant-distance window
		var on: bool = display_radius * absf(wrapf(angle - ang, -PI, PI)) <= gate_dist
		var col := Color(0.3, 1.0, 0.45) if on else Color(0.95, 0.85, 0.2)
		var zone := col
		zone.a = 0.22
		draw_arc(c, lr, ang - half_ang, ang + half_ang, 14, zone, 8.0)
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(c + dir * (lr - 14.0), c + dir * (lr + 14.0), col, 4.0)

	for fl in flashes:
		var fa := clampf(fl.life / 0.6, 0.0, 1.0)
		draw_arc(c + fl.pos * z, (1.0 - fa) * 120.0 + 6.0, 0.0, TAU, 32, Color(1, 1, 1, fa), 3.0)

	# Flying squares (feed animation).
	for f in flying:
		var fst: Vector2 = f.start
		var fft: float = f.t
		var wpos := fst.lerp(Vector2.ZERO, fft)
		var fsz := 9.0 * z * (1.0 - 0.4 * fft)
		draw_rect(Rect2(c + wpos * z - Vector2(fsz, fsz) * 0.5, Vector2(fsz, fsz)), Color(0.4, 0.85, 0.95))

	# Carried squares trailing the moon.
	var carried := mini(inventory, 8)
	for j in carried:
		var idx := trail.size() - 2 - j * 3
		if idx >= 0:
			var tpos: Vector2 = trail[idx]
			var sp := c + tpos * z
			var ssz := 8.0 * z
			draw_rect(Rect2(sp - Vector2(ssz, ssz) * 0.5, Vector2(ssz, ssz)), Color(0.4, 0.85, 0.95))

	# Moon (the comet head).
	draw_circle(c + moon_world() * z, moon_radius * z, Color(0.7, 0.85, 1.0).lerp(Color(1, 1, 1), t))

	for pu in popups:
		var qa := clampf(pu.life * 1.6, 0.0, 1.0)
		draw_string(font, c + pu.pos * z + Vector2(-40, 0), pu.text, HORIZONTAL_ALIGNMENT_CENTER, 80, pu.size, Color(1, 1, 1, qa))

	_draw_hud(font, spd_col)


func _draw_hud(font: Font, spd_col: Color) -> void:
	var vp := get_viewport_rect().size
	draw_string(font, Vector2(22, 56), "SPEED %d" % int(speed), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, spd_col)
	draw_string(font, Vector2(22, 84), "CREDITS %d      MAT %d      SQUARES %d/%d" % [square_credits, asteroid_mats, inventory, max_inventory],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.82, 0.82, 0.88))
	# Seal hint: how close the tail is to wrapping the current ring.
	if phase == "play" and current_ring < unlocked and not sealed[current_ring] and not moving:
		var pct := int(clampf(tail_span() / TAU, 0.0, 1.0) * 100.0)
		draw_string(font, Vector2(22, 108), "SEAL RING %d: tail %d%%" % [current_ring + 1, pct],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.9, 1.0))

	# Enemy spawn clock (Pleenko-style pie slice that depletes clockwise), on the left.
	if enemy_active:
		var ck := Vector2(74, 220)
		var cr := 42.0
		var secs := maxi(0, ceili(threat_timer))
		var total := enemy_interval(threat_spawn_count)
		var frac := clampf(float(secs) / maxf(1.0, total), 0.0, 1.0)
		draw_arc(ck, cr, 0.0, TAU, 48, Color(0.22, 0.22, 0.28), 3.0)
		if frac > 0.0:
			var pts := PackedVector2Array([ck])
			var sweep := TAU * frac
			for i in 33:
				var a := -PI / 2.0 + sweep * (float(i) / 32.0)
				pts.append(ck + Vector2(cos(a), sin(a)) * cr)
			draw_colored_polygon(pts, Color(0.92, 0.92, 1.0))
		draw_string(font, ck + Vector2(-cr, 9), str(secs), HORIZONTAL_ALIGNMENT_CENTER, cr * 2.0, 26, Color(0.1, 0.1, 0.15))
		var cnt := enemy_count(threat_spawn_count)
		var etext := ("%d enemy will spawn" if cnt == 1 else "%d enemies will spawn") % cnt
		draw_string(font, Vector2(ck.x - 110, ck.y + cr + 28.0), etext, HORIZONTAL_ALIGNMENT_CENTER, 220, 17, Color(1, 0.58, 0.5))

	# Game timer (top-right corner).
	var mins := int(game_time) / 60
	var secs := int(game_time) % 60
	draw_string(font, Vector2(vp.x - 110, 34), "%d:%02d" % [mins, secs], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.85, 0.85, 0.9))

	# Controls hint (top-right, under the timer).
	var hint := "SPACE boost/grab   UP/DOWN rings   1-8 buy (hub)   P pause"
	if has_blasters:
		hint += "   hold F: blaster"
	hint += "   R restart"
	draw_string(font, Vector2(vp.x - 760, 58), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.55, 0.6))

	var sc := screen_center()
	if paused:
		draw_string(font, sc + Vector2(-70, -170), "PAUSED  (P)", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.9, 0.9, 1.0))
	elif not started and phase == "play":
		draw_string(font, sc + Vector2(-150, -170), "PRESS SPACE TO LAUNCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.9, 0.95, 0.6))
	elif phase == "won":
		draw_string(font, sc + Vector2(-160, -170), "PLANET SAVED!  (R)", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.5, 1, 0.6))
	elif phase == "dead":
		draw_string(font, sc + Vector2(-200, -170), "%s  (R)" % dead_reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.4, 0.4))
	elif banner_timer > 0.0:
		draw_string(font, sc + Vector2(-170, -170), banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 0.6))

	if shop_open:
		draw_shop_modal(font)


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
	draw_string(font, Vector2(px, py + 88), "CREDITS %d        MAT %d        CORE %d/%d" % [square_credits, asteroid_mats, int(core), int(core_cap)],
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
		var have: int = square_credits if cur == "sq" else asteroid_mats
		var afford: bool = have >= int(item.cost)
		draw_rect(rect, Color(0.15, 0.24, 0.18) if afford else Color(0.16, 0.18, 0.23))
		var name_col := Color(0.96, 0.98, 0.96) if afford else Color(0.72, 0.72, 0.78)
		draw_string(font, rect.position + Vector2(16, 30), "[%d]  %s" % [key_base + i, item.name], HORIZONTAL_ALIGNMENT_LEFT, -1, 23, name_col)
		draw_string(font, rect.position + Vector2(0, 30), "%d %s" % [int(item.cost), "cr" if cur == "sq" else "mat"], HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 18, 21, name_col)
		draw_string(font, rect.position + Vector2(18, 50), item.get("desc", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.64, 0.66, 0.72))
		shop_hit.append({ "rect": rect, "action": "buy", "list": cur, "idx": i })
		y += rowh
	return y
