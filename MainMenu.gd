extends Node2D
class_name MainMenu
# Main menu — its OWN scene (project main_scene). PLAY loads Game.tscn; SETTINGS opens a
# volume panel. Drawn to feel like the game: same VisualStyle palette, the neon grid (here
# zoomed-in so only a "tiny piece" shows = big cells), and a glowing hero moon — the object
# that will later "fall" into the game during the menu→game transition (a later step).

# Palette + font shared with the game (assigned in MainMenu.tscn; falls back to defaults).
@export var style: VisualStyle
@export var ui_font: Font

const TITLE := "CORE MECHANICS"     # working title — easy to change
const MENU_GRID_MULT := 2.6         # bigger cells than in-game → reads as a zoomed-in slice
const MENU_GLOW_RADIUS := 320.0     # screen px the moon (and later the cursor) shines the grid
const MENU_GLOW_STRENGTH := 0.8
const DEFAULT_VOLUME := 80.0        # 0..100, session-only (no save system this jam)

const MENU_MOON_FRAC := 0.34        # menu moon's vertical screen position (below the title, above centre)
const MENU_MOON_R := 70.0           # menu moon radius (the "huge, zoomed-in" hero)

# Mirrors of Game's start geometry, so the zoom-out reveal lands EXACTLY on the game's first
# frame (moon at the top of ring 0, planet centered) and the scene cut is invisible.
const BASE_RADIUS := 180.0
const WORLD_MOON_Y := -180.0        # the game's moon starts at the top of ring 0 (world (0, -base_radius))
const PLANET_RADIUS := 40.0
const MOON_RADIUS := 10.0           # must match Game.gd moon_radius for a seamless hand-off
const MAX_ZOOM := 2.2
const VIEW_MARGIN := 0.80
const INTRO_DUR := 4.0              # seconds of slow zoom-out + fall before the cut to Game.tscn

var time := 0.0
var volume := DEFAULT_VOLUME
var state := "menu"                 # menu | intro
var intro_t := 0.0
# Set by the victory screen's "Play again" so the menu skips straight into the intro -> Game.tscn,
# landing on the same first frame a normal PLAY would.
static var skip_to_intro := false

const LOGO_W := 300.0               # bottom-right brand mark width (px); height follows the art's aspect
const LOGO_MARGIN := 64.0           # px from the bottom-right corner

# Jam rule: credit everything you didn't make (also tracked in CREDITS.md → itch description).
# Each entry is [SECTION HEADER (caps), body]. The infinity icon still needs a source.
const CREDITS_SECTIONS := [
	["PROGRAMMING, GRAPHICS & DESIGN", "Kimberly Durrant (8-Bit Curls)"],
	["PLAYTESTING", "Dane Durrant\nJoshua Taylor (lumosterris)"],
	["CAPSULE ART", "Dane Durrant"],
	["MUSIC", "\"Space Sprinkles\" — Matthew Pablo (CC-BY 3.0)\n\"Magic Space\" — CodeManu (CC0)\nfrom OpenGameArt.org"],
	["ICONS", "Arrows — hqrloveq (Flaticon)\nInfinity — Freepik (Flaticon)"],
]
const CREDITS_FOOTER := "Made for the Juniper Dev game jam with Godot 4.6"

var _ui: CanvasLayer
var _title: Label
var _menu_box: Control
var _play_btn: Button
var _settings_box: Control
var _credits_box: Control
var _logo: TextureRect
var _pct_label: Label
var _music: AudioStreamPlayer
var _music_started := false


func _ready() -> void:
	if style == null:
		style = load("res://styles/standard.tres")
	if ui_font == null:
		ui_font = load("res://assets/fonts/Quantico/Quantico-Regular.ttf")
	_set_volume(volume)
	_build_music()
	_build_ui()
	if skip_to_intro:
		skip_to_intro = false
		_on_play()   # "Play again" -> run the same moon-fall transition straight into a new game


func _process(delta: float) -> void:
	time += delta
	if state == "intro":
		intro_t += delta
		# Fade the menu theme out over the fall, silent by the time the moon lands.
		var fp := smoothstep(0.0, 1.0, clampf(intro_t / INTRO_DUR, 0.0, 1.0))
		var lin := clampf(1.0 - fp, 0.0, 1.0)
		_music.volume_db = -80.0 if lin <= 0.001 else linear_to_db(lin)
		if intro_t >= INTRO_DUR:
			get_tree().change_scene_to_file("res://Game.tscn")
			return
	queue_redraw()


func _input(event: InputEvent) -> void:
	if state != "menu":
		return
	# Web autoplay policy: audio won't start until a user gesture — kick the music on the
	# first click or keypress.
	if not _music_started and (event is InputEventMouseButton or event is InputEventKey):
		_start_music()


# ── Rendering ──────────────────────────────────────────────
func _draw() -> void:
	var vp := get_viewport_rect().size
	if state == "intro":
		# Ease-out: the camera moves fast at the start and slows as it settles onto the game frame.
		var raw := clampf(intro_t / INTRO_DUR, 0.0, 1.0)
		var p := 1.0 - pow(1.0 - raw, 3.0)
		_draw_scene(vp, p, lerpf(_menu_spacing(), style.grid_spacing, p), 0.0)
	else:
		_draw_scene(vp, 0.0, _menu_spacing(), sin(time * 1.3) * 8.0)


# Everything is drawn through a virtual camera (focus + zoom) that interpolates from the menu
# framing (p=0: zoomed in on the moon, which sits below the title; ring/core off-screen) to the
# game's exact first frame (p=1: moon on the ring's top edge, planet centred). Because p=1 equals
# Game.tscn's opening view, the cut at the end is seamless — the moon never jumps.
func _draw_scene(vp: Vector2, p: float, grid_spacing: float, moon_bob: float) -> void:
	var center := vp * 0.5
	var z_end := minf(MAX_ZOOM, (minf(vp.x, vp.y) * 0.5 * VIEW_MARGIN) / BASE_RADIUS)
	var z0 := MENU_MOON_R / MOON_RADIUS                                  # menu zoom sets the hero size
	var f0y := WORLD_MOON_Y - (MENU_MOON_FRAC * vp.y - center.y) / z0     # focus puts the moon below the title
	var focus := Vector2(0.0, lerpf(f0y, 0.0, p))
	var zoom := lerpf(z0, z_end, p)

	var moon_screen := center + (Vector2(0.0, WORLD_MOON_Y) - focus) * zoom + Vector2(0.0, moon_bob)
	var ring_center := center - focus * zoom

	# Grid: screen-space, from 0 (same as the in-game grid); the moon lights the patch under it.
	_draw_bg(vp, grid_spacing, moon_screen)

	# Ring + core fade in as the camera pulls back to reveal them (off-screen in the menu).
	var wa := clampf(p / 0.3, 0.0, 1.0)
	if wa > 0.0:
		var rcol := style.ring_locked
		rcol.a *= wa
		draw_arc(ring_center, BASE_RADIUS * zoom, 0.0, TAU, 96, rcol, style.ring_w_locked)
		var pcol := style.planet_sick
		pcol.a *= wa
		draw_circle(ring_center, PLANET_RADIUS * zoom, pcol)

	_glow_circle(moon_screen, MOON_RADIUS * zoom, style.moon_slow.lerp(style.moon_fast, 0.4))


func _menu_spacing() -> float:
	return maxf(8.0, style.grid_spacing * MENU_GRID_MULT)


func _draw_bg(vp: Vector2, sp: float, shine_center: Vector2) -> void:
	# Gradient backdrop (same 2-/3-stop logic as Game._draw_background).
	if style.bg_top.a > 0.0 or style.bg_bottom.a > 0.0:
		var n := maxi(1, style.bg_bands)
		for i in n:
			var f := float(i) / float(n)
			var col: Color
			if style.use_bg_mid:
				col = style.bg_top.lerp(style.bg_mid, f * 2.0) if f < 0.5 else style.bg_mid.lerp(style.bg_bottom, (f - 0.5) * 2.0)
			else:
				col = style.bg_top.lerp(style.bg_bottom, f)
			draw_rect(Rect2(0.0, vp.y * f, vp.x, vp.y / float(n) + 1.0), col)
	if style.enable_starfield:
		_draw_starfield(vp)
	if style.enable_grid:
		# Grid drawn from 0 (same phase as the in-game grid) so it doesn't drift against the real
		# grid during the hand-off into Game.tscn.
		var x := 0.0
		while x <= vp.x:
			draw_line(Vector2(x, 0), Vector2(x, vp.y), style.grid_color, 1.0)
			x += sp
		var y := 0.0
		while y <= vp.y:
			draw_line(Vector2(0, y), Vector2(vp.x, y), style.grid_color, 1.0)
			y += sp
		_grid_shine(vp, sp, shine_center, style.moon_slow)


func _grid_shine(vp: Vector2, sp: float, center: Vector2, tint: Color) -> void:
	# Local shine: only the patch of grid right around `center` brightens (2D falloff), drawn
	# as short segments so whole lines don't light up. Mirrors Game._grid_shine.
	var rad := MENU_GLOW_RADIUS
	var step := 16.0
	var gx := ceilf((center.x - rad) / sp) * sp
	while gx <= center.x + rad:
		if gx >= 0.0 and gx <= vp.x:
			var yy := center.y - rad
			while yy <= center.y + rad:
				var k := clampf(1.0 - Vector2(gx, yy + step * 0.5).distance_to(center) / rad, 0.0, 1.0)
				if k > 0.02:
					var col := style.grid_color.lerp(Color(tint.r, tint.g, tint.b, style.grid_color.a), 0.3 * k)
					col.a = clampf(MENU_GLOW_STRENGTH * k, 0.0, 1.0)
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
					col.a = clampf(MENU_GLOW_STRENGTH * k, 0.0, 1.0)
					draw_line(Vector2(xx, gy), Vector2(xx + step, gy), col, 1.0 + k * 1.5)
				xx += step
		gy += sp


func _draw_starfield(vp: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for i in style.star_count:
		var p := Vector2(rng.randf() * vp.x, rng.randf() * vp.y)
		var rr := rng.randf_range(0.6, 1.9)
		var a := style.star_color.a
		if style.star_twinkle > 0.0:
			a *= 1.0 - style.star_twinkle * (0.5 + 0.5 * sin(time * 2.2 + float(i) * 1.7))
		var col := style.star_color
		col.a = clampf(a, 0.0, 1.0)
		draw_circle(p, rr, col)


# Fake bloom (renderer-agnostic, safe for web): stacked alpha circles + a crisp core.
func _glow_circle(pos: Vector2, r: float, col: Color) -> void:
	if style.glow_enable:
		for i in range(style.glow_layers, 0, -1):
			var lt := float(i) / float(style.glow_layers)
			var gc := col
			gc.a = col.a * style.glow_alpha * (1.0 - lt) * (1.0 - lt)
			draw_circle(pos, r * (1.0 + (style.glow_spread - 1.0) * lt), gc)
	draw_circle(pos, r, col)


# ── Audio ──────────────────────────────────────────────────
func _build_music() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	# Menu theme = "Space Sprinkles" (in-game "magic space" is triggered from Game.gd instead).
	var stream: AudioStream = load("res://assets/sound/Space Sprinkles.mp3")
	if stream != null:
		if stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		_music.stream = stream
	add_child(_music)
	# Start as soon as the menu launches. On web the browser keeps audio suspended until the
	# first user gesture, then auto-resumes this stream; _input() is a belt-and-suspenders retry.
	_music.play()


func _start_music() -> void:
	_music_started = true
	if _music.stream != null and not _music.playing:
		_music.play()


func _set_volume(percent: float) -> void:
	volume = clampf(percent, 0.0, 100.0)
	# Master bus is index 0 (always present, no bus-layout file needed).
	var db := -80.0 if volume <= 0.0 else linear_to_db(volume / 100.0)
	AudioServer.set_bus_volume_db(0, db)


# ── UI (built in code; this scene owns no .tscn node structure to edit) ──
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	# Title, anchored top-center.
	var title := Label.new()
	title.text = TITLE
	title.add_theme_font_override("font", ui_font)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", style.moon_slow)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 90.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = title
	_ui.add_child(title)

	# Main buttons, horizontally centered, pushed to the lower-middle so they clear the moon.
	_menu_box = _make_center()
	_menu_box.anchor_top = 0.40
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	var play_btn := _make_button("PLAY")
	play_btn.pressed.connect(_on_play)
	_play_btn = play_btn
	var settings_btn := _make_button("SETTINGS")
	settings_btn.pressed.connect(_on_settings)
	var credits_btn := _make_button("CREDITS")
	credits_btn.pressed.connect(_on_credits)
	vb.add_child(play_btn)
	vb.add_child(settings_btn)
	vb.add_child(credits_btn)
	_menu_box.add_child(vb)
	_ui.add_child(_menu_box)

	# Settings panel, dead-center, hidden until SETTINGS pressed.
	_settings_box = _make_center()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.09, 0.14, 0.96), style.moon_slow))
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 22)
	pv.custom_minimum_size = Vector2(560, 0)
	var vol_label := _make_label("VOLUME", 32)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = volume
	slider.custom_minimum_size = Vector2(0, 44)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_slider(slider)
	slider.value_changed.connect(_on_volume_changed)
	_pct_label = _make_label("%d%%" % int(round(volume)), 28)
	_pct_label.custom_minimum_size = Vector2(96, 0)
	_pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(slider)
	row.add_child(_pct_label)
	var back_btn := _make_button("BACK")
	back_btn.pressed.connect(_on_back)
	pv.add_child(vol_label)
	pv.add_child(row)
	pv.add_child(back_btn)
	panel.add_child(pv)
	_settings_box.add_child(panel)
	_settings_box.visible = false
	_ui.add_child(_settings_box)

	# Credits panel, dead-center, hidden until CREDITS pressed.
	_credits_box = _make_center()
	var cpanel := PanelContainer.new()
	cpanel.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.09, 0.14, 0.96), style.moon_slow))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 20)
	cv.custom_minimum_size = Vector2(760, 0)
	cv.add_child(_make_label("CREDITS", 46))
	# Each section: a caps header (cyan accent) tight above its body, grouped in its own VBox.
	for sec in CREDITS_SECTIONS:
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", 4)
		var head := _make_label(sec[0], 30)
		head.add_theme_color_override("font_color", style.moon_slow)
		sv.add_child(head)
		sv.add_child(_make_label(sec[1], 26))
		cv.add_child(sv)
	cv.add_child(_make_label(CREDITS_FOOTER, 24))
	var credits_back := _make_button("BACK")
	credits_back.pressed.connect(_on_credits_back)
	cv.add_child(credits_back)
	cpanel.add_child(cv)
	_credits_box.add_child(cpanel)
	_credits_box.visible = false
	_ui.add_child(_credits_box)

	# 8-Bit Curls brand mark, pinned to the bottom-right corner.
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/icons/8bit-curls-logo-white.png")
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex_size := _logo.texture.get_size()
	var logo_h := LOGO_W * (tex_size.y / tex_size.x)
	_logo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_logo.offset_left = -LOGO_W - LOGO_MARGIN
	_logo.offset_top = -logo_h - LOGO_MARGIN
	_logo.offset_right = -LOGO_MARGIN
	_logo.offset_bottom = -LOGO_MARGIN
	_ui.add_child(_logo)

	# Focus PLAY so the menu is keyboard-navigable from launch (Space/Enter activates, arrows move).
	_play_btn.grab_focus()


func _make_center() -> Control:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cc


func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", ui_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", style.hud_text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 88)
	b.add_theme_font_override("font", ui_font)
	b.add_theme_font_size_override("font_size", 38)
	b.add_theme_color_override("font_color", style.hud_text)
	b.add_theme_color_override("font_hover_color", style.moon_fast)
	b.add_theme_color_override("font_pressed_color", style.moon_fast)
	var base := Color(0.10, 0.12, 0.20, 0.92)
	var border := style.moon_slow
	b.add_theme_stylebox_override("normal", _sb(base, border))
	b.add_theme_stylebox_override("hover", _sb(base.lightened(0.10), border.lightened(0.15)))
	b.add_theme_stylebox_override("pressed", _sb(base.darkened(0.10), border))
	# Focus reads like hover so keyboard navigation shows which button is selected.
	b.add_theme_stylebox_override("focus", _sb(base.lightened(0.10), border.lightened(0.15)))
	return b


func _sb(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(14)
	return s


# ── Button handlers ────────────────────────────────────────
func _on_play() -> void:
	# Kick off the moon-fall + zoom-out cinematic; _process cuts to Game.tscn when it ends.
	if state != "menu":
		return
	state = "intro"
	intro_t = 0.0
	_title.visible = false
	_menu_box.visible = false
	_settings_box.visible = false
	_logo.visible = false
	if not _music_started:
		_start_music()


func _on_settings() -> void:
	_menu_box.visible = false
	_settings_box.visible = true


func _on_back() -> void:
	_settings_box.visible = false
	_menu_box.visible = true
	_play_btn.grab_focus()


func _on_credits() -> void:
	_menu_box.visible = false
	_credits_box.visible = true


func _on_credits_back() -> void:
	_credits_box.visible = false
	_menu_box.visible = true
	_play_btn.grab_focus()


func _on_volume_changed(v: float) -> void:
	_set_volume(v)
	if _pct_label != null:
		_pct_label.text = "%d%%" % int(round(v))


# Cyan track + filled bar (same hue as everything else) and a grabber 2× the default size.
func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(style.moon_slow.r, style.moon_slow.g, style.moon_slow.b, 0.55)
	track.set_corner_radius_all(5)
	track.content_margin_top = 5.0
	track.content_margin_bottom = 5.0
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = style.moon_slow
	fill.set_corner_radius_all(5)
	fill.content_margin_top = 5.0
	fill.content_margin_bottom = 5.0
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var grab := _make_grabber(34, style.moon_fast)
	s.add_theme_icon_override("grabber", grab)
	s.add_theme_icon_override("grabber_highlight", grab)
	s.add_theme_icon_override("grabber_disabled", grab)


func _make_grabber(diameter: int, col: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rad := float(diameter) * 0.5
	var ctr := Vector2(rad, rad)
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(ctr)
			if d <= rad:
				var c := col
				c.a = col.a * clampf(rad - d, 0.0, 1.0)   # 1px soft edge
				img.set_pixelv(Vector2i(x, y), c)
	return ImageTexture.create_from_image(img)
