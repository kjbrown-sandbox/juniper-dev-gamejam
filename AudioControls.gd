class_name AudioControls
extends RefCounted
# Shared audio-settings widget: a master-volume slider + Music/SFX mute toggles. Built by BOTH the
# main-menu settings panel (MainMenu) and the in-game hover popup (Game), so the two stay identical.
#
# There's no settings store: the AudioServer buses ARE the state (volume_db on Master, mute on the
# "Music"/"SFX" buses), and those persist for the whole session. So build() just reads the current
# bus state when it's created and writes it back on change. Session-only, matching the jam's no-save
# design — nothing is saved to disk.

static func build(style: VisualStyle, ui_font: Font) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.custom_minimum_size = Vector2(300, 0)

	# Master volume: slider + live percentage (same dB math as MainMenu._set_volume).
	vb.add_child(_label("VOLUME", 26, style, ui_font))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = clampf(db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0, 0.0, 100.0)
	slider.custom_minimum_size = Vector2(0, 40)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	style_slider(slider, style)
	var pct := _label("%d%%" % int(round(slider.value)), 24, style, ui_font)
	pct.custom_minimum_size = Vector2(72, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# No sound on change: value_changed fires once per pixel of travel, so a blip would machine-gun.
	slider.value_changed.connect(func(v):
		AudioServer.set_bus_volume_db(0, -80.0 if v <= 0.0 else linear_to_db(v / 100.0))
		pct.text = "%d%%" % int(round(v)))
	row.add_child(slider)
	row.add_child(pct)
	vb.add_child(row)

	# Music / SFX toggles — each rides its own bus, muted independently of the master.
	vb.add_child(_toggle("Music", "Music", style, ui_font))
	vb.add_child(_toggle("SFX", "SFX", style, ui_font))
	return vb


# A labeled on/off toggle bound to a bus's mute flag. "pressed" = sound ON (bus un-muted). The -1
# guards make it a safe no-op if the bus doesn't exist yet (e.g. before Sfx sets the buses up).
static func _toggle(label: String, bus: String, style: VisualStyle, ui_font: Font) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.add_theme_font_override("font", ui_font)
	c.add_theme_font_size_override("font_size", 24)
	c.add_theme_color_override("font_color", style.hud_text)
	c.add_theme_color_override("font_hover_color", style.moon_fast)
	c.add_theme_color_override("font_pressed_color", style.moon_fast)
	var idx := AudioServer.get_bus_index(bus)
	c.button_pressed = idx < 0 or not AudioServer.is_bus_mute(idx)
	c.toggled.connect(func(on):
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_mute(i, not on))
	return c


static func _label(text: String, size: int, style: VisualStyle, ui_font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", ui_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", style.hud_text)
	return l


# Cyan track + filled bar (same hue as everything else) and a grabber 2× the default size.
# Moved here from MainMenu so the menu panel and the in-game popup share one slider look.
static func style_slider(s: HSlider, style: VisualStyle) -> void:
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
	var grab := make_grabber(34, style.moon_fast)
	s.add_theme_icon_override("grabber", grab)
	s.add_theme_icon_override("grabber_highlight", grab)
	s.add_theme_icon_override("grabber_disabled", grab)


static func make_grabber(diameter: int, col: Color) -> ImageTexture:
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
