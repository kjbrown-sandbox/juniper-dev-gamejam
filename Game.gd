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
@export var traverse_cost := 40.0
@export var view_margin := 0.80

# ── Tail / speed ───────────────────────────────────────────
@export var tail_life := 1.4            # seconds a tail particle lingers; sealing = lap within this time
@export var tail_up := 0.25             # extra lifetime per Tail-stretch upgrade
@export var tail_color := Color(1.0, 0.85, 0.2)   # yellow comet tail
@export var comet_emit_step := 0.04     # rad spacing between emitted tail particles
@export var comet_dot := 5.0            # tail particle radius (world px)
@export var seal_near := 0.70           # tail fraction of full at which the seal cinematic engages
@export var seal_slowmo := 0.15         # steady time scale held through the seal (pleenko orange-unlock value)
@export var seal_zoom := 1.9            # camera punch-in during the seal
@export var seal_zoom_time := 0.5       # s to become fully zoomed in
@export var reveal_dur := 1.8           # s the camera zooms out to show the newly opened ring
@export var gate_window := 0.22
@export var light_delay := 1.0
@export var light_delay_jitter := 0.25
@export var light_cost := 1.0
@export var light_tween_speed := 2000.0           # speed at which the arc range reaches its "fast" values
@export var light_arc_slow := Vector2(20.0, 45.0)   # min/max degrees ahead at speed 0
@export var light_arc_fast := Vector2(90.0, 270.0)  # min/max degrees ahead at light_tween_speed+
@export var start_speed := 0.0
@export var min_speed := 0.0
@export var death_speed := 0.0
@export var stall_decay := 120.0
@export var max_speed := 4000.0
@export var boost_base := 60.0
@export var boost_up := 18.0            # per Boost-power upgrade
@export var combo_mult := 0.08
@export var base_decay := 15.0
@export var whiff_slow := 0.85
@export var hitstop_time := 0.05
@export var seal_hitstop := 0.18

# ── Core / squares ─────────────────────────────────────────
@export var core_start := 15.0
@export var core_cap := 15.0
@export var feed_per_square := 7.0
@export var material_max := 2
@export var pickup_radius := 90.0
@export var deposit_interval := 0.12
@export var suck_time := 0.45
@export var square_decay := 10.0        # carried-square drag on the core decay

# ── Asteroids (loot vein, ring 3) ──────────────────────────
@export var asteroid_max := 1
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
@export var threat_drain := 0.5
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

var lights: Array = []
var light_count := 1
var light_timer := 0.0

var materials: Array = []   # angle floats (squares on the middle ring)
var flying: Array = []      # { start:Vector2, t:float }
var deposit_timer := 0.0
var asteroids: Array = []   # { angle, hits_left, cd }
var threats: Array = []     # { angle, radius, hp, latched, cd }
var threat_timer := 0.0
var threat_spawn_count := 0

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


func _ready() -> void:
	reset()


# ── Shop data ──────────────────────────────────────────────
func make_shops() -> void:
	shop_sq = [
		{ "id": "boost",  "name": "Boost power",     "cost": cost_of("boost"),  "max": -1 },
		{ "id": "dual",   "name": "Double lights",   "cost": 10,                "max": 1, "done": light_count >= 2 },
		{ "id": "moresq", "name": "More squares",    "cost": cost_of("moresq"), "max": 3 },
		{ "id": "tail",   "name": "Tail stretch",    "cost": cost_of("tail"),   "max": -1 },
	]
	shop_bt = [
		{ "id": "armor",   "name": "Armor",      "cost": cost_of("armor"), "max": -1 },
		{ "id": "horns",   "name": "Horns",      "cost": 5,  "max": 1, "done": has_horns },
		{ "id": "horns2",  "name": "Horns II",   "cost": 10, "max": 1, "done": has_horns2, "req": has_horns },
		{ "id": "blasters","name": "Blasters",   "cost": 10, "max": 1, "done": has_blasters },
	]


var bought := {}   # id -> count

func cost_of(id: String) -> int:
	var n: int = bought.get(id, 0)
	match id:
		"boost", "armor": return (n + 1) * (n + 2) / 2   # triangular: 1,3,6,10...
		"tail": return 5 + n * 5                          # 5,10,15,20...
		"moresq": return [2, 8, 20][mini(n, 2)]
	return 0


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
	has_horns = false
	has_horns2 = false
	has_blasters = false
	beam_on = false
	bought = {}
	# restore upgrade-modified tunables to base (so restart is clean)
	tail_life = 1.4
	boost_base = 80.0
	material_max = 2
	ram_hit_mult = 0.7
	asteroid_hits = 3
	threat_hp = 2
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
	return minf(1.0, (half_screen() * view_margin) / maxf(1.0, r))


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
	return base_decay + inventory * square_decay


# ── Lights ─────────────────────────────────────────────────
func aligned_light() -> int:
	for i in lights.size():
		if absf(wrapf(angle - lights[i], -PI, PI)) <= gate_window:
			return i
	return -1


func rand_ahead() -> float:
	# Arc distance ahead scales with speed: at speed 0 it's light_arc_slow degrees, rising
	# to light_arc_fast at light_tween_speed; the random pick is within the lerped range.
	var t := clampf(speed / maxf(1.0, light_tween_speed), 0.0, 1.0)
	var lo := lerpf(light_arc_slow.x, light_arc_fast.x, t)
	var hi := lerpf(light_arc_slow.y, light_arc_fast.y, t)
	return wrapf(angle + deg_to_rad(randf_range(lo, hi)), -PI, PI)


# ── Spawners ───────────────────────────────────────────────
func refill_materials() -> void:
	materials.clear()
	for i in material_max:
		materials.append(randf_range(-PI, PI))


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
	if unlocked == 3:
		ensure_asteroids()
		spawn_threat()
		threat_spawn_count = 1
		threat_timer = 30.0


# ── Sim ────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if phase == "won" or phase == "dead":
		queue_redraw()
		return

	# Blaster: held F (only with the upgrade, while playing).
	beam_on = has_blasters and phase == "play" and Input.is_key_pressed(KEY_F)

	if started and phase == "play":
		game_time += delta

	display_tail = minf(tail_span(), TAU)

	# Engage the seal cinematic on prediction: tail near full AND fast enough to connect.
	# Once committed it's latched; the failsafe (frozen anchor particle) guarantees contact.
	if not sealing and phase == "play" and started and not moving and reveal_timer <= 0.0 \
		and current_ring < unlocked and not sealed[current_ring] \
		and display_tail >= seal_near * TAU and speed >= seal_speed():
		sealing = true
		seal_anim = 0.0

	# Hold a deep, steady slow-mo for the whole committed seal (pleenko orange-unlock feel);
	# it lasts until contact, which the frozen anchor particle guarantees.
	if sealing:
		seal_anim += delta
	time_scale = lerpf(time_scale, seal_slowmo if sealing else 1.0, clampf(8.0 * delta, 0.0, 1.0))

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
	# Zoom fully onto the moon over seal_zoom_time (0.5s), then track it; ease back out after.
	if sealing:
		var zp := smoothstep(0.0, maxf(0.05, seal_zoom_time), seal_anim)
		cam_focus = Vector2.ZERO.lerp(moon_world(), zp)
		cam_zoom = lerpf(1.0, seal_zoom, zp)
	else:
		cam_focus = cam_focus.lerp(Vector2.ZERO, clampf(5.0 * delta, 0.0, 1.0))
		cam_zoom = lerpf(cam_zoom, 1.0, clampf(5.0 * delta, 0.0, 1.0))
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
				refill_materials()
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

	# At the hub, carried squares auto-suck into the core (animated).
	if current_ring == 0 and not moving and inventory > 0:
		deposit_timer -= sim
		if deposit_timer <= 0.0:
			deposit_timer = deposit_interval
			inventory -= 1
			flying.append({ "start": moon_world(), "t": 0.0 })

	# Lights: each missing slot refills independently after the delay (a double light doesn't
	# wait for both to be taken). No core = no spawn (soft stall, not an instant loss).
	if lights.size() < light_count:
		light_timer -= sim
		if light_timer <= 0.0:
			if core >= light_cost:
				core -= light_cost
				lights.append(rand_ahead())
				light_timer = light_delay + randf_range(-light_delay_jitter, light_delay_jitter)
			else:
				light_timer = 0.0   # broke: retry as soon as the core can pay

	# Asteroids (loot vein, ring 3).
	if unlocked >= 3:
		ensure_asteroids()
		for ast in asteroids:
			ast.angle = wrapf(ast.angle - asteroid_speed * sim, -PI, PI)
			if ast.cd > 0.0:
				ast.cd -= sim
		if current_ring == 2:
			for ast in asteroids:
				if ast.cd <= 0.0 and absf(wrapf(angle - ast.angle, -PI, PI)) < asteroid_tol:
					speed = speed * asteroid_hit_mult
					ast.cd = asteroid_hit_cd
					ast.hits_left -= 1
					shake = minf(1.8, shake + 0.4)
					var ap := ring_point(ring_r(2), ast.angle)
					for i in 6:
						particles.append({ "pos": ap, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(90.0, 200.0), "life": randf_range(0.2, 0.45) })
					if ast.hits_left <= 0:
						asteroid_mats += 1
						popups.append({ "pos": ap, "text": "+MAT", "life": 0.7, "size": 16 })
		asteroids = asteroids.filter(func(a): return a.hits_left > 0)
		_tick_threats(sim)

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


func _tick_threats(sim: float) -> void:
	threat_timer -= sim
	if threat_timer <= 0.0:
		spawn_threat()
		threat_spawn_count += 1
		var sched := [30.0, 25.0, 20.0, 15.0]
		threat_timer = sched[mini(threat_spawn_count - 1, sched.size() - 1)]

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
		if t.cd <= 0.0 and absf(display_radius - t.radius) < ram_radial_tol and absf(wrapf(angle - t.angle, -PI, PI)) < ram_ang_tol:
			t.hp -= 1
			t.cd = threat_ram_cd
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
		KEY_1, KEY_2, KEY_3, KEY_4:
			if can_shop():
				buy(shop_sq[k - KEY_1])
		KEY_5, KEY_6, KEY_7, KEY_8:
			if can_shop():
				buy(shop_bt[k - KEY_5])
		KEY_R:
			reset()


func can_shop() -> bool:
	return phase == "play" and current_ring == 0 and not moving


func traverse(dir: int) -> void:
	if moving or sealing:
		return
	var target := clampi(current_ring + dir, 0, unlocked - 1)
	if target == current_ring:
		return
	if dir > 0:
		speed = maxf(min_speed, speed - traverse_cost)
	else:
		speed = minf(max_speed, speed + traverse_cost * 0.5)
	move_from = current_ring
	move_to = target
	move_t = 0.0
	moving = true


func nearest_square() -> int:
	var mw := moon_world()
	var best := -1
	var bestd := pickup_radius
	for i in materials.size():
		var d := mw.distance_to(ring_point(ring_r(1), materials[i]))
		if d < bestd:
			bestd = d
			best = i
	return best


func collect_square(i: int) -> void:
	var ma: float = materials[i]
	materials.remove_at(i)
	inventory += 1
	var mp := ring_point(ring_r(1), ma)
	flashes.append({ "pos": mp, "life": 0.3 })
	popups.append({ "pos": mp, "text": "+1", "life": 0.5, "size": 14 })


func try_boost() -> void:
	var did := false
	var si := nearest_square()
	if si >= 0:
		collect_square(si)
		did = true
	var li := aligned_light()
	if li >= 0:
		do_boost(li)
		did = true
	if not did and not moving:
		combo = 0
		speed = maxf(min_speed, speed * whiff_slow)
		shake = minf(1.5, shake + 0.2)


func do_boost(li: int) -> void:
	var la: float = lights[li]
	var q := 1.0 - absf(wrapf(angle - la, -PI, PI)) / gate_window
	combo += 1
	var gain := boost_base * (1.0 + combo * combo_mult) * (0.5 + 0.5 * q)
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
	light_timer = light_delay + randf_range(-light_delay_jitter, light_delay_jitter)


func feed_one() -> void:
	# Core first; overflow becomes square-credits (the economy currency).
	if core < core_cap:
		core = minf(core_cap, core + feed_per_square)
	else:
		square_credits += 1


func buy(item: Dictionary) -> void:
	var id: String = item.id
	var maxb: int = item.max
	var n: int = bought.get(id, 0)
	if maxb >= 0 and n >= maxb:
		return
	if item.has("req") and not item.req:
		return
	var cur := "ast" if id in ["armor", "horns", "horns2", "blasters"] else "sq"
	var have: int = square_credits if cur == "sq" else asteroid_mats
	var cost: int = item.cost
	if have < cost:
		return
	if cur == "sq":
		square_credits -= cost
	else:
		asteroid_mats -= cost
	bought[id] = n + 1
	match id:
		"boost":    boost_base += boost_up
		"dual":     light_count = 2
		"moresq":   material_max += 1
		"tail":     tail_life += tail_up
		"armor":    ram_hit_mult = minf(0.95, ram_hit_mult + 0.05)
		"horns":    has_horns = true; asteroid_hits = 2; threat_hp = 1
		"horns2":   has_horns2 = true; asteroid_hits = 1
		"blasters": has_blasters = true
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

	# Blaster beam.
	if beam_on:
		var bd := Vector2(cos(angle), sin(angle))
		var p_in := c + bd * planet_draw_radius() * z
		var p_out := c + bd * ring_r(2) * 1.3 * z
		draw_line(p_in, p_out, Color(1.0, 0.4, 0.9, 0.9), (beam_width * 2.0) * 80.0 * z)
		draw_line(p_in, p_out, Color(1, 1, 1, 0.9), 3.0)

	# Squares (middle ring).
	for i in materials.size():
		var ma: float = materials[i]
		var mp := c + ring_point(ring_r(1), ma) * z
		var msz := 11.0 * z
		draw_rect(Rect2(mp - Vector2(msz, msz) * 0.5, Vector2(msz, msz)), Color(0.4, 0.85, 0.95))

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

	# Lights.
	for i in lights.size():
		var ang: float = lights[i]
		var lr := display_radius * z
		var on: bool = absf(wrapf(angle - ang, -PI, PI)) <= gate_window
		var col := Color(0.3, 1.0, 0.45) if on else Color(0.95, 0.85, 0.2)
		var zone := col
		zone.a = 0.22
		draw_arc(c, lr, ang - gate_window, ang + gate_window, 14, zone, 8.0)
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
	draw_string(font, Vector2(22, 84), "CREDITS %d      MAT %d      CORE %d/%d" % [square_credits, asteroid_mats, int(core), int(core_cap)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.82, 0.82, 0.88))
	# Seal hint: how close the tail is to wrapping the current ring.
	if phase == "play" and current_ring < unlocked and not sealed[current_ring] and not moving:
		var pct := int(clampf(tail_span() / TAU, 0.0, 1.0) * 100.0)
		draw_string(font, Vector2(22, 108), "SEAL RING %d: tail %d%%" % [current_ring + 1, pct],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.9, 1.0))

	# Shop panels (bottom corners), larger rows; usable only at the inner ring.
	var enabled := can_shop()
	_draw_shop(font, shop_sq, "ECONOMY (1-4) — CREDITS", "sq", Vector2(20, vp.y - 20), false, enabled)
	_draw_shop(font, shop_bt, "BATTLE (5-8) — MAT", "ast", Vector2(vp.x - 400, vp.y - 20), true, enabled)

	# Game timer (top-right corner).
	var mins := int(game_time) / 60
	var secs := int(game_time) % 60
	draw_string(font, Vector2(vp.x - 110, 34), "%d:%02d" % [mins, secs], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.85, 0.85, 0.9))

	# Controls hint (top-right, under the timer).
	var hint := "SPACE boost/grab   UP/DOWN rings   1-8 buy (hub)"
	if has_blasters:
		hint += "   hold F: blaster"
	hint += "   R restart"
	draw_string(font, Vector2(vp.x - 760, 58), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.55, 0.6))

	var sc := screen_center()
	if not started and phase == "play":
		draw_string(font, sc + Vector2(-150, -170), "PRESS SPACE TO LAUNCH", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.9, 0.95, 0.6))
	elif phase == "won":
		draw_string(font, sc + Vector2(-160, -170), "PLANET SAVED!  (R)", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.5, 1, 0.6))
	elif phase == "dead":
		draw_string(font, sc + Vector2(-200, -170), "%s  (R)" % dead_reason, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.4, 0.4))
	elif banner_timer > 0.0:
		draw_string(font, sc + Vector2(-170, -170), banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 0.6))


func _draw_shop(font: Font, items: Array, header: String, cur: String, anchor: Vector2, right: bool, enabled: bool) -> void:
	var rowh := 28.0
	var pw := 380.0
	var ph := 38.0 + items.size() * rowh
	var x := anchor.x
	var top := anchor.y - ph
	draw_rect(Rect2(x, top, pw, ph), Color(0, 0, 0, 0.5))
	draw_string(font, Vector2(x + 12, top + 24), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 1, 0.7) if enabled else Color(0.5, 0.5, 0.55))
	for i in items.size():
		var item: Dictionary = items[i]
		var key := i + 1 if not right else i + 5
		var done: bool = item.get("done", false)
		var locked: bool = item.has("req") and not item.req
		var have: int = square_credits if cur == "sq" else asteroid_mats
		var label := "%d) %s" % [key, item.name]
		var rc: Color
		if done:
			label += "  ✓"
			rc = Color(0.5, 0.7, 0.5)
		elif locked:
			label += "  (locked)"
			rc = Color(0.45, 0.45, 0.5)
		else:
			label += "  —  %d %s" % [int(item.cost), cur]
			if not enabled:
				rc = Color(0.45, 0.45, 0.5)
			else:
				rc = Color(0.85, 0.95, 0.85) if have >= int(item.cost) else Color(0.75, 0.55, 0.55)
		draw_string(font, Vector2(x + 12, top + 24 + (i + 1) * rowh), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, rc)
