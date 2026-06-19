extends Node2D
# GRAY BOX — "Revolutions". Momentum feel + a dying-core economy. SPACE: nail the light
# (the core PAYS core-power to create each one) to boost. Phase 1: do 5 laps on the
# inner ring. Then a far outer ring unlocks where you harvest material squares to refuel
# the core — but hauling cargo drags you down. Race a 50-lap countdown to win. F opens a
# paused terminal to feed the core or buy upgrades. One file, all logic in _process, all
# rendering in _draw. Disposable.

# ── Rings ──────────────────────────────────────────────────
@export var base_radius := 180.0       # inner ring (ring 0)
@export var ring_gap := 300.0          # outer ring is far away so distance reads big
@export var planet_radius := 40.0
@export var moon_radius := 12.0
@export var traverse_time := 2.5        # s to glide between rings
@export var traverse_cost := 25.0       # speed lost going OUT (half refunded going IN)
@export var view_margin := 0.80

# ── Light / boost ──────────────────────────────────────────
@export var gate_window := 0.22
@export var light_delay := 1.0          # s after a hit before the next light spawns
@export var light_cost := 1.0           # core power spent to spawn a light
@export var start_speed := 150.0
@export var min_speed := 80.0
@export var max_speed := 2500.0
@export var boost_base := 45.0
@export var combo_mult := 0.08
@export var base_decay := 20.0
@export var whiff_slow := 0.95
@export var hitstop_time := 0.05

# ── Core / materials / inventory ───────────────────────────
@export var core_start := 20.0
@export var core_cap := 99.0
@export var feed_per_square := 5.0
@export var material_max := 3
@export var material_tol := 0.18
@export var material_respawn_lo := 2.0
@export var material_respawn_hi := 4.0
@export var pickup_slow := 0.94         # speed kept when you scoop a square
@export var square_decay := 18.0        # extra decay per carried square

# ── Goal ───────────────────────────────────────────────────
@export var p1_revs := 5
@export var p2_revs := 50
@export var cine_dur := 5.0

# ── State ──────────────────────────────────────────────────
var phase := "p1"        # p1 | cine | p2 | won
var angle := 0.0
var speed := 0.0
var combo := 0
var revs_left := 0
var rev_accum := 0.0
var unlocked := 1
var current_ring := 0
var display_radius := 0.0
var moving := false
var move_from := 0
var move_to := 0
var move_t := 0.0
var view_scale := 1.0
var cine_t := 0.0

var core := 0.0
var core_visible := false
var inventory := 0

var has_light := false
var light_angle := 0.0
var light_timer := 0.0

var materials: Array = []   # { angle:float, active:bool, timer:float }
var shop: Array = []
var terminal_open := false

var trail: Array = []
var particles: Array = []
var popups: Array = []
var flashes: Array = []
var shake := 0.0
var hitstop := 0.0


func _ready() -> void:
	reset()


func make_shop() -> Array:
	# Only the reveal shows until bought; then the real upgrades appear.
	if not core_visible:
		return [{ "id": "reveal", "name": "Reveal core power", "cost": 1 }]
	return [
		{ "id": "inertia", "name": "Increase inertia (-square drag)", "cost": 2 },
		{ "id": "boost",   "name": "Stronger light boost (+0.2 core/light)", "cost": 2 },
		{ "id": "maxsq",   "name": "More squares at ring 2 (+1)", "cost": 3 },
	]


func reset() -> void:
	phase = "p1"
	angle = 0.0
	speed = start_speed
	combo = 0
	revs_left = p1_revs
	rev_accum = 0.0
	unlocked = 1
	current_ring = 0
	display_radius = ring_r(0)
	moving = false
	move_t = 0.0
	cine_t = 0.0
	core = core_start
	core_visible = false
	inventory = 0
	has_light = false
	light_timer = 0.0
	materials.clear()
	shop = make_shop()
	terminal_open = false
	trail.clear()
	particles.clear()
	popups.clear()
	flashes.clear()
	shake = 0.0
	hitstop = 0.0
	view_scale = desired_scale()
	queue_redraw()


# ── Geometry / view ────────────────────────────────────────
func ring_r(i: int) -> float:
	return base_radius + i * ring_gap


func screen_center() -> Vector2:
	return get_viewport_rect().size * 0.5


func half_screen() -> float:
	var vp := get_viewport_rect().size
	return minf(vp.x, vp.y) * 0.5


func frame_scale(r: float) -> float:
	return minf(1.0, (half_screen() * view_margin) / maxf(1.0, r))


func desired_scale() -> float:
	if phase == "cine":
		return frame_scale(ring_r(1)) if cine_t < cine_dur * 0.6 else frame_scale(ring_r(0))
	return frame_scale(display_radius)


func moon_world() -> Vector2:
	return display_radius * Vector2(cos(angle), sin(angle))


func ring_point(r: float, a: float) -> Vector2:
	return r * Vector2(cos(a), sin(a))


func speed_t() -> float:
	return clampf(speed / max_speed, 0.0, 1.0)


func cur_decay() -> float:
	return base_decay + inventory * square_decay


# ── Light ──────────────────────────────────────────────────
func aligned() -> bool:
	return has_light and absf(wrapf(angle - light_angle, -PI, PI)) <= gate_window


# ── Materials ──────────────────────────────────────────────
func ensure_materials() -> void:
	while materials.size() < material_max:
		materials.append({ "angle": randf_range(-PI, PI), "active": false, "timer": randf_range(material_respawn_lo, material_respawn_hi) })


# ── Phase transitions ──────────────────────────────────────
func on_revolution() -> void:
	revs_left -= 1
	if revs_left <= 0:
		if phase == "p1":
			phase = "cine"
			cine_t = 0.0
			unlocked = 2
			has_light = false
		elif phase == "p2":
			revs_left = 0
			phase = "won"


func end_cine() -> void:
	phase = "p2"
	revs_left = p2_revs
	current_ring = 0
	display_radius = ring_r(0)
	ensure_materials()


# ── Sim ────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if terminal_open or phase == "won":
		queue_redraw()
		return

	var sim := delta
	if hitstop > 0.0:
		hitstop -= delta
		sim = 0.0

	if sim > 0.0:
		if phase == "cine":
			_tick_cine(sim)
		else:
			_tick_play(sim)

	# Juice timers.
	view_scale = lerpf(view_scale, desired_scale(), clampf(3.0 * delta, 0.0, 1.0))
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


func _tick_cine(sim: float) -> void:
	# Keep revolving, no decay, camera handled by desired_scale().
	angle = wrapf(angle + (speed / base_radius) * sim, -PI, PI)
	trail.append(moon_world())
	if trail.size() > 26:
		trail.pop_front()
	cine_t += sim
	if cine_t >= cine_dur:
		end_cine()


func _tick_play(sim: float) -> void:
	speed = clampf(speed - cur_decay() * sim, min_speed, max_speed)
	# Angular pace uses the FIXED base radius so timing feel is ring-independent.
	var dang := (speed / base_radius) * sim
	angle = wrapf(angle + dang, -PI, PI)

	rev_accum += dang
	if rev_accum >= TAU:
		rev_accum -= TAU
		on_revolution()
		if phase != "p2" and phase != "p1":
			return

	# Ring glide.
	if moving:
		move_t += sim / maxf(0.001, traverse_time)
		if move_t >= 1.0:
			move_t = 1.0
			moving = false
			current_ring = move_to
		display_radius = lerpf(ring_r(move_from), ring_r(move_to), move_t)
	else:
		display_radius = ring_r(current_ring)

	# Light: respawn after delay, costs core. No core -> stall (no spawn).
	if not has_light:
		light_timer -= sim
		if light_timer <= 0.0 and core >= light_cost:
			core -= light_cost
			light_angle = randf_range(-PI, PI)
			has_light = true

	# Materials (phase 2, outer ring) — only respawn timers here; you grab them with SPACE.
	if phase == "p2":
		ensure_materials()
		for m in materials:
			if not m.active:
				m.timer -= sim
				if m.timer <= 0.0:
					m.active = true
					m.angle = randf_range(-PI, PI)

	trail.append(moon_world())
	if trail.size() > 26:
		trail.pop_front()


# ── Input ──────────────────────────────────────────────────
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode

	if terminal_open:
		match k:
			KEY_F: terminal_open = false
			KEY_C: feed_core()
			KEY_1, KEY_2, KEY_3: buy(k - KEY_1)
			KEY_R: reset()
		return

	match k:
		KEY_SPACE:
			if phase == "p1" or phase == "p2":
				try_boost()
		KEY_UP:
			if phase == "p2":
				traverse(1)
		KEY_DOWN:
			if phase == "p2":
				traverse(-1)
		KEY_F:
			# Terminal only opens at the innermost ring.
			if (phase == "p1" or phase == "p2") and current_ring == 0 and not moving:
				terminal_open = true
		KEY_R:
			reset()


func traverse(dir: int) -> void:
	if moving:
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


func nearest_material() -> int:
	var best := -1
	var bestd := material_tol
	for i in materials.size():
		if not materials[i].active:
			continue
		var d := absf(wrapf(angle - materials[i].angle, -PI, PI))
		if d < bestd:
			bestd = d
			best = i
	return best


func acquire_material(i: int) -> void:
	var m: Dictionary = materials[i]
	var ma: float = m.angle
	m.active = false
	m.timer = randf_range(material_respawn_lo, material_respawn_hi)
	inventory += 1
	speed = maxf(min_speed, speed * pickup_slow)
	var mp := ring_point(ring_r(1), ma)
	flashes.append({ "pos": mp, "life": 0.3 })
	popups.append({ "pos": mp, "text": "+1", "life": 0.6, "size": 16 })
	shake = minf(1.0, shake + 0.15)


func try_boost() -> void:
	# On the outer ring, SPACE grabs a nearby square first.
	if phase == "p2" and current_ring == 1:
		var mi := nearest_material()
		if mi >= 0:
			acquire_material(mi)
			return
	if not aligned():
		combo = 0
		speed = maxf(min_speed, speed * whiff_slow)
		shake = minf(1.5, shake + 0.2)
		return
	var q := 1.0 - absf(wrapf(angle - light_angle, -PI, PI)) / gate_window
	combo += 1
	var gain := boost_base * (1.0 + combo * combo_mult) * (0.5 + 0.5 * q)
	speed = minf(max_speed, speed + gain)
	shake = minf(1.6, shake + 0.35 + 0.4 * q)
	var lp := ring_point(display_radius, light_angle)
	for i in 12:
		particles.append({ "pos": lp, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(110.0, 280.0), "life": randf_range(0.25, 0.55) })
	flashes.append({ "pos": lp, "life": 0.35 })
	popups.append({ "pos": lp, "text": ("PERFECT" if q > 0.75 else "x%d" % combo), "life": 0.7, "size": 18 })
	if q > 0.75:
		hitstop = hitstop_time
	has_light = false
	light_timer = light_delay


func feed_core() -> void:
	if inventory >= 1:
		inventory -= 1
		core = minf(core_cap, core + feed_per_square)


func buy(i: int) -> void:
	if i < 0 or i >= shop.size():
		return
	var item: Dictionary = shop[i]
	var cost: int = item.cost
	if inventory < cost:
		return
	inventory -= cost
	match item.id:
		"reveal":
			core_visible = true
		"inertia":
			square_decay = maxf(4.0, square_decay - 5.0)
		"boost":
			boost_base += 12.0
			light_cost += 0.2
		"maxsq":
			material_max = mini(6, material_max + 1)
	shop = make_shop()


# ── Rendering ──────────────────────────────────────────────
func _draw() -> void:
	var font := ThemeDB.fallback_font
	var t := speed_t()
	var z := view_scale
	var c := screen_center() + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 9.0
	var spd_col := Color(0.40, 0.70, 1.0).lerp(Color(1.0, 0.45, 0.12), t)

	if t > 0.30:
		for i in int(t * 16.0):
			var a := randf_range(-PI, PI)
			var d0 := Vector2(cos(a), sin(a))
			var r0 := ring_r(unlocked - 1) * z * randf_range(1.3, 2.2)
			var sc := spd_col
			sc.a = (t - 0.30) * 0.5
			draw_line(c + d0 * r0, c + d0 * (r0 + 50.0 + t * 70.0), sc, 2.0)

	# Rings (unlocked solid; next ring faint teaser).
	for i in unlocked:
		draw_arc(c, ring_r(i) * z, 0.0, TAU, 96, Color(0.24, 0.24, 0.32), 2.0)
	if unlocked < 2:
		draw_arc(c, ring_r(1) * z, 0.0, TAU, 96, Color(0.15, 0.15, 0.19), 1.0)

	# Planet + revolutions-remaining counter.
	draw_circle(c, planet_radius * z, Color(0.40, 0.40, 0.48))
	draw_string(font, c + Vector2(-60, 10), str(revs_left), HORIZONTAL_ALIGNMENT_CENTER, 120, 38, Color(1, 1, 1))
	draw_string(font, c + Vector2(-60, 30), "LAPS LEFT", HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(0.7, 0.7, 0.78))

	# Materials (outer ring squares).
	for m in materials:
		if not m.active:
			continue
		var ma: float = m.angle
		var mp := c + ring_point(ring_r(1), ma) * z
		var msz := 11.0 * z
		draw_rect(Rect2(mp - Vector2(msz, msz) * 0.5, Vector2(msz, msz)), Color(0.4, 0.85, 0.95))

	# Light on the current ring.
	if has_light:
		var lr := display_radius * z
		var col := Color(0.3, 1.0, 0.45) if aligned() else Color(0.95, 0.85, 0.2)
		var zone := col
		zone.a = 0.22
		draw_arc(c, lr, light_angle - gate_window, light_angle + gate_window, 14, zone, 8.0)
		var dir := Vector2(cos(light_angle), sin(light_angle))
		draw_line(c + dir * (lr - 14.0), c + dir * (lr + 14.0), col, 4.0)

	for fl in flashes:
		var fa := clampf(fl.life / 0.35, 0.0, 1.0)
		draw_arc(c + fl.pos * z, (1.0 - fa) * 40.0 + 6.0, 0.0, TAU, 24, Color(1, 1, 1, fa), 3.0)

	for i in trail.size():
		var f := float(i) / float(maxi(1, trail.size()))
		var tc := spd_col
		tc.a = f * 0.6
		draw_circle(c + trail[i] * z, moon_radius * z * (0.25 + 0.75 * f), tc)

	for p in particles:
		var pc := spd_col
		pc.a = clampf(p.life * 2.2, 0.0, 1.0)
		draw_circle(c + p.pos * z, 3.0, pc)

	draw_circle(c + moon_world() * z, moon_radius * z, Color(0.6, 0.8, 1.0).lerp(Color(1, 1, 1), t))

	for pu in popups:
		var qa := clampf(pu.life * 1.6, 0.0, 1.0)
		draw_string(font, c + pu.pos * z + Vector2(-40, 0), pu.text, HORIZONTAL_ALIGNMENT_CENTER, 80, pu.size, Color(1, 1, 1, qa))

	_draw_hud(font, spd_col)


func _draw_hud(font: Font, spd_col: Color) -> void:
	draw_string(font, Vector2(22, 56), "SPEED %d" % int(speed), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, spd_col)
	var line2 := "COMBO x%d      SQUARES %d" % [combo, inventory]
	if core_visible:
		line2 += "      CORE %d" % int(core)
	draw_string(font, Vector2(22, 84), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.82, 0.82, 0.88))
	if not has_light and core < light_cost and (phase == "p1" or phase == "p2"):
		draw_string(font, Vector2(22, 108), "CORE EMPTY — feed it (F) to relight", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.5, 0.4))

	var hint := "SPACE: light / grab square    F: terminal (inner ring)"
	if phase == "p2":
		hint += "    UP/DOWN: switch ring"
	hint += "    R: restart"
	draw_string(font, Vector2(22, get_viewport_rect().size.y - 18), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.55, 0.6))

	var sc := screen_center()
	if phase == "won":
		draw_string(font, sc + Vector2(-160, -120), "YOU MADE IT — 50 LAPS!  (R)", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.5, 1, 0.6))
	elif phase == "cine":
		draw_string(font, sc + Vector2(-150, -120), "RING 2 UNLOCKED", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 0.6))

	# Terminal overlay (paused).
	if terminal_open:
		var vp := get_viewport_rect().size
		draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.55))
		var x := sc.x - 170.0
		var y := sc.y - 110.0
		draw_string(font, Vector2(x, y), "TERMINAL — SQUARES %d%s" % [inventory, ("   CORE %d" % int(core)) if core_visible else ""],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 0.7))
		draw_string(font, Vector2(x, y + 30), "C) Feed core: 1 square -> +%d" % int(feed_per_square),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.95, 0.7) if inventory >= 1 else Color(0.5, 0.5, 0.5))
		for i in shop.size():
			var item: Dictionary = shop[i]
			var afford: bool = inventory >= int(item.cost)
			draw_string(font, Vector2(x, y + 56 + i * 24), "%d) %s — %d sq" % [i + 1, item.name, int(item.cost)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.95, 0.85) if afford else Color(0.5, 0.5, 0.5))
		draw_string(font, Vector2(x, y + 56 + shop.size() * 24 + 10), "F: close",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.6, 0.65))
