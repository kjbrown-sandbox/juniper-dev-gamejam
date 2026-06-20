extends Node2D
# GRAY BOX — "Revolutions". Momentum feel + a dying-core economy across three rings.
# SPACE: nail the light(s) (the core PAYS core-power per light) to boost. P1: 5 laps on
# the inner ring. P2: a middle ring unlocks where you grab squares to refuel the core
# (50 laps). P3: an outer ring unlocks with counter-orbiting asteroids — ram them 3x to
# crack them for asteroid material; collect 500 to win. Laps are counted at the top tick.
# Reaching the inner ring auto-opens a paused terminal to feed/upgrade (C closes). Disposable.

# ── Rings ──────────────────────────────────────────────────
@export var base_radius := 180.0
@export var ring_gap := 300.0
@export var planet_radius := 40.0
@export var moon_radius := 12.0
@export var traverse_time := 2.0
@export var traverse_cost := 25.0
@export var view_margin := 0.80

# ── Light / boost ──────────────────────────────────────────
@export var gate_window := 0.22
@export var light_delay := 1.0
@export var light_cost := 1.0
@export var light_ahead_min_deg := 30.0
@export var light_ahead_max_deg := 180.0
@export var start_speed := 200.0
@export var min_speed := 0.0
@export var death_speed := 50.0
@export var stall_decay := 120.0
@export var max_speed := 2500.0
@export var boost_base := 60.0
@export var combo_mult := 0.08
@export var base_decay := 15.0
@export var whiff_slow := 0.85
@export var hitstop_time := 0.05

# ── Core / materials / inventory ───────────────────────────
@export var core_start := 15.0
@export var core_cap := 15.0
@export var feed_per_square := 7.0
@export var material_max := 1
@export var material_tol := 0.18
@export var material_respawn_lo := 2.0
@export var material_respawn_hi := 4.0
@export var pickup_slow := 1.0
@export var square_decay := 10.0

# ── Asteroids (ring 3 / outer) ─────────────────────────────
@export var asteroid_max := 4
@export var asteroid_radius := 16.0
@export var asteroid_speed := 1.2       # rad/s, counter-orbiting (opposite the player)
@export var asteroid_hits := 3          # rams to crack one
@export var asteroid_hit_mult := 0.7    # speed kept when you ram one
@export var asteroid_tol := 0.16        # rad window a ram registers
@export var asteroid_hit_cd := 0.5      # s before the same rock can hit you again

# ── Goal ───────────────────────────────────────────────────
@export var p1_revs := 5
@export var p2_revs := 20
@export var p3_asteroids := 50

# ── State ──────────────────────────────────────────────────
var phase := "p1"        # p1 | p2 | p3 | stalling | dead | won
var top_angle := -PI / 2.0
var banner_text := ""
var banner_timer := 0.0
var angle := 0.0
var speed := 0.0
var combo := 0
var revs_left := 0
var unlocked := 1
var current_ring := 0
var display_radius := 0.0
var moving := false
var move_from := 0
var move_to := 0
var move_t := 0.0
var view_scale := 1.0

var core := 0.0
var inventory := 0
var asteroid_mats := 0

var lights: Array = []   # angles (floats); up to light_count at once
var light_count := 1
var light_timer := 0.0

var materials: Array = []   # angle floats (active squares on the middle ring)
var asteroids: Array = []   # { angle, hits_left, cd }
var maxsq_cost := 1
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
	var s: Array = [
		{ "id": "inertia", "name": "Increase inertia (-square drag)", "cost": 2, "cur": "sq" },
		{ "id": "boost",   "name": "Stronger light boost (+0.2 core/light)", "cost": 2, "cur": "sq" },
		{ "id": "maxsq",   "name": "More squares (+1)", "cost": maxsq_cost, "cur": "sq" },
	]
	if light_count < 2:
		s.append({ "id": "dual", "name": "Two light boosts at once", "cost": 1, "cur": "ast" })
	return s


func reset() -> void:
	phase = "p1"
	angle = top_angle
	speed = start_speed
	combo = 0
	revs_left = p1_revs
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
	materials.clear()
	asteroids.clear()
	maxsq_cost = 1
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
	# Always frame the outermost unlocked ring, so each unlock zooms out and stays out.
	return frame_scale(ring_r(unlocked - 1))


func moon_world() -> Vector2:
	return display_radius * Vector2(cos(angle), sin(angle))


func ring_point(r: float, a: float) -> Vector2:
	return r * Vector2(cos(a), sin(a))


func speed_t() -> float:
	return clampf(speed / max_speed, 0.0, 1.0)


func cur_decay() -> float:
	return base_decay + inventory * square_decay


func crossed(target: float, a0: float, a1: float) -> bool:
	# True if the moon swept past `target` this frame (small forward step).
	var r0 := wrapf(target - a0, -PI, PI)
	var r1 := wrapf(target - a1, -PI, PI)
	return signf(r0) != signf(r1) and absf(r0) < 1.0 and absf(r1) < 1.0


# ── Lights ─────────────────────────────────────────────────
func aligned_light() -> int:
	for i in lights.size():
		if absf(wrapf(angle - lights[i], -PI, PI)) <= gate_window:
			return i
	return -1


func rand_ahead() -> float:
	return wrapf(angle + deg_to_rad(randf_range(light_ahead_min_deg, light_ahead_max_deg)), -PI, PI)


# ── Spawners ───────────────────────────────────────────────
func refill_materials() -> void:
	# A fresh finite batch; no respawn timer — you must return to the hub for more.
	materials.clear()
	for i in material_max:
		materials.append(randf_range(-PI, PI))


func ensure_asteroids() -> void:
	while asteroids.size() < asteroid_max:
		asteroids.append({ "angle": randf_range(-PI, PI), "hits_left": asteroid_hits, "cd": 0.0 })


# ── Phase transitions ──────────────────────────────────────
func on_revolution() -> void:
	if phase == "p1":
		revs_left -= 1
		if revs_left <= 0:
			unlock_ring(2, "p2")
	elif phase == "p2":
		revs_left -= 1
		if revs_left <= 0:
			unlock_ring(3, "p3")


func unlock_ring(new_unlocked: int, next_phase: String) -> void:
	# No cinematic pause — play continues; the camera just zooms out (and stays out).
	unlocked = new_unlocked
	phase = next_phase
	banner_text = "RING %d UNLOCKED" % new_unlocked
	banner_timer = 2.5
	if next_phase == "p2":
		revs_left = p2_revs
		refill_materials()
	elif next_phase == "p3":
		refill_materials()
		ensure_asteroids()


# ── Sim ────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if terminal_open or phase == "won" or phase == "dead":
		queue_redraw()
		return

	var sim := delta
	if hitstop > 0.0:
		hitstop -= delta
		sim = 0.0

	if sim > 0.0:
		if phase == "stalling":
			_tick_stall(sim)
		else:
			_tick_play(sim)

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


func _tick_stall(sim: float) -> void:
	speed = maxf(0.0, speed - stall_decay * sim)
	display_radius = ring_r(current_ring)
	angle = wrapf(angle + (speed / display_radius) * sim, -PI, PI)
	_trail()
	if speed <= 1.0:
		phase = "dead"


func _tick_play(sim: float) -> void:
	speed = clampf(speed - cur_decay() * sim, min_speed, max_speed)
	if speed <= death_speed:
		phase = "stalling"
		return
	# Ring glide first, so the radius we're on this frame drives the angular pace.
	if moving:
		move_t += sim / maxf(0.001, traverse_time)
		if move_t >= 1.0:
			move_t = 1.0
			moving = false
			current_ring = move_to
			if current_ring == 0:
				terminal_open = true   # auto-open the terminal on reaching the hub
				refill_materials()     # fresh batch of squares each time you return
		display_radius = lerpf(ring_r(move_from), ring_r(move_to), move_t)
	else:
		display_radius = ring_r(current_ring)

	# Angular pace = speed / CURRENT radius, so bigger rings sweep slower (feel slower).
	var dang := (speed / display_radius) * sim
	var a0 := angle
	angle = wrapf(angle + dang, -PI, PI)
	# Laps are counted when you cross the top tick.
	if (phase == "p1" or phase == "p2") and crossed(top_angle, a0, angle):
		on_revolution()

	# Lights: respawn light_count of them after the delay, each costing core.
	if lights.is_empty():
		light_timer -= sim
		if light_timer <= 0.0:
			for n in light_count:
				if core >= light_cost:
					core -= light_cost
					lights.append(rand_ahead())

	# Asteroids on the outer ring (P3): counter-orbit; ram them on ring 2 (index).
	if phase == "p3":
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
					shake = minf(1.8, shake + 0.5)
					var ap := ring_point(ring_r(2), ast.angle)
					for i in 8:
						particles.append({ "pos": ap, "vel": Vector2.from_angle(randf_range(-PI, PI)) * randf_range(90.0, 220.0), "life": randf_range(0.2, 0.45) })
					if ast.hits_left <= 0:
						asteroid_mats += 1
						popups.append({ "pos": ap, "text": "+MAT", "life": 0.7, "size": 16 })
						if asteroid_mats >= p3_asteroids:
							phase = "won"
		asteroids = asteroids.filter(func(a): return a.hits_left > 0)

	_trail()


func _trail() -> void:
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
			KEY_C: terminal_open = false
			KEY_F: feed_core()
			KEY_1, KEY_2, KEY_3, KEY_4: buy(k - KEY_1)
			KEY_R: reset()
		return

	var playing: bool = phase == "p1" or phase == "p2" or phase == "p3"
	match k:
		KEY_SPACE:
			if playing:
				try_boost()
		KEY_UP:
			if phase == "p2" or phase == "p3":
				traverse(1)
		KEY_DOWN:
			if phase == "p2" or phase == "p3":
				traverse(-1)
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
		var d := absf(wrapf(angle - materials[i], -PI, PI))
		if d < bestd:
			bestd = d
			best = i
	return best


func acquire_material(i: int) -> void:
	var ma: float = materials[i]
	materials.remove_at(i)
	inventory += 1
	speed = maxf(min_speed, speed * pickup_slow)
	var mp := ring_point(ring_r(1), ma)
	flashes.append({ "pos": mp, "life": 0.3 })
	popups.append({ "pos": mp, "text": "+1", "life": 0.6, "size": 16 })
	shake = minf(1.0, shake + 0.15)


func try_boost() -> void:
	if moving:
		return   # mid-glide between rings: SPACE does nothing (no whiff penalty)
	# On the middle ring, SPACE grabs a nearby square first.
	if (phase == "p2" or phase == "p3") and current_ring == 1:
		var mi := nearest_material()
		if mi >= 0:
			acquire_material(mi)
			return
	var li := aligned_light()
	if li < 0:
		combo = 0
		speed = maxf(min_speed, speed * whiff_slow)
		shake = minf(1.5, shake + 0.2)
		return
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
	if lights.is_empty():
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
	var cur: String = item.cur
	var have: int = inventory if cur == "sq" else asteroid_mats
	if have < cost:
		return
	if cur == "sq":
		inventory -= cost
	else:
		asteroid_mats -= cost
	match item.id:
		"inertia":
			square_decay = maxf(4.0, square_decay - 5.0)
		"boost":
			boost_base += 12.0
			light_cost += 0.2
		"maxsq":
			material_max = mini(10, material_max + 1)
			maxsq_cost += 2
		"dual":
			light_count = 2
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

	# Rings, each with a tick mark at the top (the lap line).
	var topd := Vector2(cos(top_angle), sin(top_angle))
	for i in unlocked:
		var rr := ring_r(i) * z
		draw_arc(c, rr, 0.0, TAU, 96, Color(0.24, 0.24, 0.32), 2.0)
		draw_line(c + topd * (rr - 11.0), c + topd * (rr + 11.0), Color(0.9, 0.85, 0.4), 3.0)

	# Planet + center counter.
	draw_circle(c, planet_radius * z, Color(0.40, 0.40, 0.48))
	var big := str(asteroid_mats) if phase == "p3" or phase == "won" else str(revs_left)
	var label := "ASTEROIDS" if phase == "p3" or phase == "won" else "LAPS LEFT"
	draw_string(font, c + Vector2(-60, 10), big, HORIZONTAL_ALIGNMENT_CENTER, 120, 38, Color(1, 1, 1))
	draw_string(font, c + Vector2(-60, 30), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(0.7, 0.7, 0.78))

	# Core health bar beneath the planet.
	var cbw := 120.0
	var cby := c.y + planet_radius * z + 14.0
	var cbx := c.x - cbw * 0.5
	var cfrac := clampf(core / core_cap, 0.0, 1.0)
	draw_rect(Rect2(cbx, cby, cbw, 9.0), Color(0.12, 0.12, 0.15))
	draw_rect(Rect2(cbx, cby, cbw * cfrac, 9.0), Color(0.85, 0.3, 0.3).lerp(Color(0.3, 0.85, 0.45), cfrac))
	draw_string(font, Vector2(cbx, cby + 24.0), "CORE %d" % int(core), HORIZONTAL_ALIGNMENT_CENTER, cbw, 12, Color(0.9, 0.9, 0.95))

	# Materials (middle ring squares) — finite batch, refilled at the hub.
	for i in materials.size():
		var ma: float = materials[i]
		var mp := c + ring_point(ring_r(1), ma) * z
		var msz := 11.0 * z
		draw_rect(Rect2(mp - Vector2(msz, msz) * 0.5, Vector2(msz, msz)), Color(0.4, 0.85, 0.95))

	# Asteroids (outer ring) with a remaining-hits number.
	for ast in asteroids:
		var aa: float = ast.angle
		var hl: int = ast.hits_left
		var ap := c + ring_point(ring_r(2), aa) * z
		draw_circle(ap, asteroid_radius * z, Color(0.85, 0.3, 0.25))
		draw_string(font, ap + Vector2(-20, -asteroid_radius * z - 4.0), str(hl), HORIZONTAL_ALIGNMENT_CENTER, 40, 16, Color(1, 1, 1))

	# Lights on the current ring.
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
	var line2 := "COMBO x%d      SQUARES %d      MAT %d" % [combo, inventory, asteroid_mats]
	draw_string(font, Vector2(22, 84), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.82, 0.82, 0.88))
	if lights.is_empty() and core < light_cost and (phase == "p1" or phase == "p2" or phase == "p3"):
		draw_string(font, Vector2(22, 108), "CORE EMPTY — feed it (F) to relight", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.5, 0.4))

	var hint := "SPACE: light / grab square    (terminal auto-opens at the inner ring)"
	if phase == "p2" or phase == "p3":
		hint += "    UP/DOWN: switch ring"
	hint += "    R: restart"
	draw_string(font, Vector2(22, get_viewport_rect().size.y - 18), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.55, 0.6))

	var sc := screen_center()
	if phase == "won":
		draw_string(font, sc + Vector2(-180, -120), "YOU MADE IT — 500 ASTEROIDS!  (R)", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.5, 1, 0.6))
	elif phase == "dead":
		draw_string(font, sc + Vector2(-150, -120), "YOU STOPPED SPINNING  (R)", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.4, 0.4))
	elif banner_timer > 0.0:
		draw_string(font, sc + Vector2(-150, -120), banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 0.6))

	if terminal_open:
		var vp := get_viewport_rect().size
		draw_rect(Rect2(0, 0, vp.x, vp.y), Color(0, 0, 0, 0.55))
		var x := sc.x - 180.0
		var y := sc.y - 120.0
		draw_string(font, Vector2(x, y), "TERMINAL — SQUARES %d   MAT %d   CORE %d" % [inventory, asteroid_mats, int(core)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 0.7))
		draw_string(font, Vector2(x, y + 30), "F) Feed core: 1 square -> +%d" % int(feed_per_square),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.95, 0.7) if inventory >= 1 else Color(0.5, 0.5, 0.5))
		for i in shop.size():
			var item: Dictionary = shop[i]
			var cur: String = item.cur
			var have: int = inventory if cur == "sq" else asteroid_mats
			var afford: bool = have >= int(item.cost)
			draw_string(font, Vector2(x, y + 56 + i * 24), "%d) %s — %d %s" % [i + 1, item.name, int(item.cost), cur],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.95, 0.85) if afford else Color(0.5, 0.5, 0.5))
		draw_string(font, Vector2(x, y + 56 + shop.size() * 24 + 10), "C: close",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.6, 0.65))
