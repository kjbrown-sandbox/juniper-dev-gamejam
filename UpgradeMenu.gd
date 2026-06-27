extends Control
# Standalone upgrade screen. Self-contained on purpose: it owns its own data (the five
# sections below), draws itself in the game's purple+cyan / Quantico look, and talks to the
# outside world only through `configure()` / `open()` / `close()` and the `purchased` /
# `closed` signals. Run THIS scene (F6) to see it with the preview state.
#
# Layout follows the mockup: a top row (Core / Boost / Stardust) always shown once the
# Stardust ring is unlocked, plus a bottom row (Attack / Comet) that appears — and grows the
# panel taller — once the asteroid ring is unlocked.
#
# Two wallets: the top row spends STARDUST, the bottom row spends COMETS (the asteroid drops).
# A section's currency is just its row (0 = stardust, 1 = comets).

signal purchased(section_id: String, upgrade_id: String, level: int)   # fired on a successful buy
signal closed                                              # menu dismissed (B / Esc)
signal no_upgrades                                         # open() refused: nothing buyable

# ── State the host sets (defaults are the standalone preview) ──────────────
@export var unlocked := 3          # 2 = top row only, 3 = both rows (panel grows taller)
@export var reveal := 3            # how many top-row sections to show (1=Stardust, 2=+Core, 3=+Light boost)
@export var stardust := 8          # stardust wallet (top row)
@export var stardust_max := 12     # carry cap (shown as "Stardust: x/y")
@export var comets := 6            # comet wallet (bottom row: Attack / Comet)
@export var finale := false        # show the Finale section (set once the outer ring is sealed)
@export var auto_open_for_preview := true   # run the scene on its own and it opens itself
@export var buy_arm_delay := 0.25  # ignore SPACE for this long after opening (stray boosts)

# ── Look (tuned to styles/standard.tres so it matches the rings) ───────────
const C_DIM       := Color(0, 0, 0, 0.72)
const C_FRAME_BG  := Color(0.09, 0.10, 0.14, 0.99)
const C_PURPLE    := Color(0.74, 0.42, 1.0)     # = style.square_ready (stardust)
const C_COMET     := Color(0.3, 0.95, 1.0)      # = style.asteroid (comets)
const C_CYAN      := Color(0.5, 0.85, 1.0)      # = style.ring_sealed (selection / borders)
const C_TITLE     := Color(0.88, 0.95, 1.0)
const C_TEXT      := Color(0.92, 0.92, 0.96)
const C_DIMTEXT   := Color(0.58, 0.58, 0.66)
const C_WARN      := Color(1.0, 0.55, 0.25)     # unaffordable cost

# ── Geometry ───────────────────────────────────────────────────────────────
const FRAME_W   := 1520.0   # full width (3 top columns / comet readout fits without colliding)
const MIN_W     := 920.0    # narrow floor when only 1–2 sections show and no comet readout
const SECT_W    := 440.0    # one section box
const MARGIN    := 56.0     # frame edge -> section
const COL_GAP   := 44.0
const ROW_GAP   := 44.0
const TOP_BAND  := 150.0    # title + stardust readout
const BOT_PAD   := 132.0    # room below the last row for the Back button + footer hint
const BACK_W    := 240.0
const BACK_H    := 54.0
const SECT_H    := 380.0
const HEADER_H  := 54.0

var _font: Font
var _font_bold: Font
var sections: Array = []     # the five sections (built in _ready)
var _cards: Array = []       # [{ rect, center, si, ui }] for the currently-shown rows
var selected := -1           # index into _cards (only ever a buyable card)
var _mode := "closed"        # "closed" | "open" | "no_upgrades"
var _no_up := 0.0            # "No upgrades available" banner timer
var _arm := 0.0              # counts down from buy_arm_delay; SPACE disabled until 0
var _t := 0.0               # animation clock (pulses)


func _ready() -> void:
	_font = load("res://assets/fonts/Quantico/Quantico-Regular.ttf")
	_font_bold = load("res://assets/fonts/Quantico/Quantico-Bold.ttf")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # receive clicks (click-to-buy)
	sections = default_sections()
	for s in sections:
		for u in s.upgrades:
			u.level = 0   # bought levels (max_level = u.sd.size())
	visible = false
	if auto_open_for_preview:
		open()


# ── Upgrade data ───────────────────────────────────────────────────────────
# Two upgrades per section. Costs are PER LEVEL: `sd[i]` stardust + `cm[i]` comets for the
# (i+1)th buy; max_level = sd.size(). Most top-row levels are stardust, but a couple of 4th-tier
# unlocks (Vacuum, Double lights) cost comets — the exceptions, mirroring the old tech tree.
# Bottom row (Attack / Comet) is all comets. The host applies the real effect on `purchased`.
func default_sections() -> Array:
	# Top-row order = the visit reveal order (Stardust, then Core, then Light boost).
	return [
		{ "id": "stardust", "title": "Stardust", "row": 0, "upgrades": [
			{ "id": "dust_main", "name": "Basic", "desc": "Hold more Stardust",
			  "sd": [1, 6, 10], "cm": [0, 0, 0] },
			{ "id": "dust_premium", "name": "Vacuum", "desc": "Auto-collect Stardust in reach",
			  "sd": [5], "cm": [1], "premium": true },
		] },
		{ "id": "core", "title": "Core", "row": 0, "upgrades": [
			{ "id": "core_main", "name": "Basic", "desc": "Increase core power",
			  "sd": [2, 7, 12], "cm": [0, 0, 0] },
			{ "id": "core_premium", "name": "Overfill", "desc": "Charge past full, up to 1.5×",
			  "sd": [6], "cm": [1], "premium": true },
		] },
		{ "id": "boost", "title": "Light boost", "row": 0, "upgrades": [
			{ "id": "boost_main", "name": "Basic", "desc": "Faster, stronger lights",
			  "warn": "Costs +1 core to spawn light boosts", "sd": [3, 10, 20], "cm": [0, 0, 0] },
			{ "id": "boost_premium", "name": "Double lights", "desc": "Two boost lights at once",
			  "sd": [8], "cm": [1], "premium": true },
		] },
		{ "id": "attack", "title": "Attack", "row": 1, "upgrades": [
			{ "id": "atk_main", "name": "Basic", "desc": "+1 damage, comets slow less",
			  "sd": [0, 0, 0], "cm": [1, 4, 9] },
			{ "id": "atk_premium", "name": "Ram", "desc": "Deal damage even on miss",
			  "sd": [10], "cm": [2], "premium": true },
		] },
		{ "id": "comet", "title": "Comet", "row": 1, "upgrades": [
			{ "id": "comet_main", "name": "Basic", "desc": "+1 comet on the ring",
			  "sd": [0, 0, 0], "cm": [1, 4, 9] },
			{ "id": "comet_premium", "name": "Comet boost", "desc": "Comets grant a speed boost",
			  "sd": [10], "cm": [1], "premium": true },
		] },
		# Finale: appears once the outer ring is sealed (gated by `finale`); bottom-right slot.
		{ "id": "finale", "title": "Finale", "row": 1, "upgrades": [
			{ "id": "finale_main", "name": "Infinity", "desc": "Remove the Stardust cap",
			  "sd": [0], "cm": [10] },
			{ "id": "finale_premium", "name": "Freedom?", "desc": "???",
			  "sd": [100], "cm": [20], "premium": true },
		] },
	]


# Cost of the NEXT level as [stardust, comets]. Only valid when not maxed.
func cost_of(u: Dictionary) -> Array:
	var lv := int(u.level)
	return [int(u.sd[lv]), int(u.cm[lv])]


func is_maxed(u: Dictionary) -> bool:
	return int(u.level) >= u.sd.size()


# Pip tint by section: stardust (top row) purple, comets (bottom row) cyan.
func section_tint(si: int) -> Color:
	return C_PURPLE if int(sections[si].row) == 0 else C_COMET


# A premium upgrade (the section's 2nd card) is locked until its main track (card 0) is fully
# maxed — i.e. all of its levels, including the final one, have been bought.
func _premium_locked(si: int, ui: int) -> bool:
	var u: Dictionary = sections[si].upgrades[ui]
	if not u.get("premium", false):
		return false
	var main: Dictionary = sections[si].upgrades[0]
	return int(main.level) < main.sd.size()


func can_buy(si: int, ui: int) -> bool:
	var u: Dictionary = sections[si].upgrades[ui]
	if is_maxed(u) or _premium_locked(si, ui):
		return false
	var c := cost_of(u)
	return stardust >= c[0] and comets >= c[1]


# All three top-row sections (Stardust/Core/Light boost) show at once now. The bottom row
# (Attack/Comet) still appears only once the asteroid ring is unlocked.
func _section_visible(si: int) -> bool:
	if String(sections[si].get("id", "")) == "finale":
		return finale   # only after the outer ring is sealed
	if int(sections[si].row) == 0:
		return true
	return unlocked >= 3


func any_buyable() -> bool:
	for si in sections.size():
		if not _section_visible(si):
			continue
		for ui in sections[si].upgrades.size():
			if can_buy(si, ui):
				return true
	return false


# ── Public API (host calls these) ──────────────────────────────────────────
func configure(p_unlocked: int, p_stardust: int, p_stardust_max: int, p_comets: int, p_reveal: int, p_finale: bool = false) -> void:
	unlocked = p_unlocked
	stardust = p_stardust
	stardust_max = p_stardust_max
	comets = p_comets
	reveal = p_reveal
	finale = p_finale


# Opens the menu — UNLESS nothing is buyable, in which case it stays closed and flashes
# "No upgrades available" instead (and fires `no_upgrades` so the host can react).
func open() -> void:
	if not any_buyable():
		_mode = "no_upgrades"
		_no_up = 1.6
		visible = true
		no_upgrades.emit()
		queue_redraw()
		return
	_mode = "open"
	_arm = buy_arm_delay
	visible = true
	_build_layout()
	_select_first()
	queue_redraw()


func close() -> void:
	_mode = "closed"
	visible = false
	closed.emit()


# Host game restarted: wipe all bought levels and hide, WITHOUT emitting `closed` (the host is
# already resetting its own state).
func reset_upgrades() -> void:
	for s in sections:
		for u in s.upgrades:
			u.level = 0
	_mode = "closed"
	selected = -1
	visible = false


# ── Layout ─────────────────────────────────────────────────────────────────
# How many sections show in each row right now (top grows with `reveal`; bottom is 0 or 2).
func _row_counts() -> Vector2i:
	var top := 0
	var bot := 0
	for si in sections.size():
		if _section_visible(si):
			if int(sections[si].row) == 0:
				top += 1
			else:
				bot += 1
	return Vector2i(top, bot)


func frame_size() -> Vector2:
	var rc := _row_counts()
	var cols := maxi(rc.x, rc.y)
	var content_w := cols * SECT_W + maxi(0, cols - 1) * COL_GAP
	# Keep the panel wide enough that the centered title clears the top-left readouts: full
	# width once the comet readout is present (unlocked 3), a narrower floor otherwise.
	var floor_w := FRAME_W if unlocked >= 3 else MIN_W
	var w := maxf(floor_w, content_w + 2.0 * MARGIN)
	var h := TOP_BAND + SECT_H + BOT_PAD
	if rc.y > 0:
		h += ROW_GAP + SECT_H
	return Vector2(w, h)


func frame_origin() -> Vector2:
	var vp := get_viewport_rect().size
	return (vp - frame_size()) * 0.5


# Section boxes for the visible sections, each row centered within the panel. Returns
# [{ si, rect }]; both the card layout and the draw pass build off this.
func _section_boxes() -> Array:
	var o := frame_origin()
	var fw := frame_size().x
	var rows := [[], []]
	for si in sections.size():
		if _section_visible(si):
			rows[int(sections[si].row)].append(si)
	# Shared left edge for every row: align them under the widest row (which stays centered in the
	# panel), so a shorter bottom row starts flush-left with the top row instead of being centered.
	var cols_max := maxi(rows[0].size(), rows[1].size())
	var rw_max := cols_max * SECT_W + maxi(0, cols_max - 1) * COL_GAP
	var x0 := o.x + (fw - rw_max) * 0.5
	var out: Array = []
	for row in 2:
		var ids: Array = rows[row]
		var n := ids.size()
		if n == 0:
			continue
		var sy := o.y + TOP_BAND + row * (SECT_H + ROW_GAP)
		for j in n:
			out.append({ "si": ids[j], "rect": Rect2(x0 + j * (SECT_W + COL_GAP), sy, SECT_W, SECT_H) })
	return out


# Build the per-card rects from the section boxes. Affordability is recomputed live in draw/nav.
func _build_layout() -> void:
	_cards.clear()
	for box in _section_boxes():
		var si: int = box.si
		var sbox: Rect2 = box.rect
		var cards_top := sbox.position.y + HEADER_H + 8.0
		var avail := SECT_H - HEADER_H - 8.0 - 16.0
		var card_gap := 16.0
		var ch := (avail - card_gap) / 2.0
		for ui in 2:
			var rect := Rect2(sbox.position.x + 16.0, cards_top + ui * (ch + card_gap), SECT_W - 32.0, ch)
			_cards.append({ "rect": rect, "center": rect.position + rect.size * 0.5, "si": si, "ui": ui })
	# Back button: a navigable target at the bottom-center (arrow down to it, or press B).
	var o := frame_origin()
	var fs := frame_size()
	var brect := Rect2(o.x + (fs.x - BACK_W) * 0.5, o.y + fs.y - BACK_H - 36.0, BACK_W, BACK_H)
	_cards.append({ "rect": brect, "center": brect.position + brect.size * 0.5, "si": -1, "ui": -1, "back": true })


func _upgrade_at(card: Dictionary) -> Dictionary:
	return sections[card.si].upgrades[card.ui]


func _buyable_card(card: Dictionary) -> bool:
	return not card.get("back", false) and can_buy(card.si, card.ui)


# A nav target: any buyable upgrade card, or the always-available Back button.
func _selectable(card: Dictionary) -> bool:
	return card.get("back", false) or _buyable_card(card)


func _select_first() -> void:
	selected = -1
	for i in _cards.size():
		if _buyable_card(_cards[i]):   # land on a real upgrade first
			selected = i
			return
	for i in _cards.size():            # nothing buyable -> focus the Back button
		if _cards[i].get("back", false):
			selected = i
			return


# ── Input ──────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if _mode != "open":
		return
	# Click-to-buy: a left click on a card selects it and buys/closes (same path as SPACE).
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mp: Vector2 = (event as InputEventMouseButton).position
		for i in _cards.size():
			if _selectable(_cards[i]) and (_cards[i].rect as Rect2).has_point(mp):
				selected = i
				_try_buy()
				break
		get_viewport().set_input_as_handled()
		queue_redraw()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k := (event as InputEventKey).keycode
	match k:
		KEY_LEFT, KEY_A:  _nav(Vector2.LEFT)
		KEY_RIGHT, KEY_D: _nav(Vector2.RIGHT)
		KEY_UP, KEY_W:    _nav(Vector2.UP)
		KEY_DOWN, KEY_S:  _nav(Vector2.DOWN)
		KEY_SPACE:        _try_buy()
		KEY_B, KEY_ESCAPE: close()
		_: return
	get_viewport().set_input_as_handled()
	queue_redraw()


# Spatial navigation: jump to the nearest SELECTABLE target in the pressed direction. Unbuyable
# upgrade cards are skipped (you only land on buyable ones), but the Back button is always a
# valid target so the player can arrow down to it.
func _nav(dir: Vector2) -> void:
	if selected < 0:
		return
	var cur: Vector2 = _cards[selected].center
	var best := -1
	var best_score := INF
	for i in _cards.size():
		if i == selected or not _selectable(_cards[i]):
			continue
		var d: Vector2 = _cards[i].center - cur
		var along := d.dot(dir)
		if along <= 1.0:
			continue                          # not in the pressed direction
		var cross := absf(d.dot(Vector2(dir.y, -dir.x)))
		var score := along + cross * 2.5      # closest, most-aligned wins
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		selected = best


# SPACE activates the selected target: the Back button closes; an upgrade card buys it.
func _try_buy() -> void:
	if _arm > 0.0 or selected < 0:
		return
	var card: Dictionary = _cards[selected]
	if card.get("back", false):
		close()
		return
	if not can_buy(card.si, card.ui):
		return
	var u: Dictionary = _upgrade_at(card)
	var c := cost_of(u)
	stardust -= c[0]
	comets -= c[1]
	u.level = int(u.level) + 1
	purchased.emit(sections[card.si].id, u.id, int(u.level))
	# Buying never closes the shop (only B does). If this card is now maxed/unaffordable, hop the
	# selection to the nearest still-buyable card; if none remain, just leave it highlighted here.
	if not _buyable_card(card) and any_buyable():
		_select_first()


# ── Tick ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_t += delta
	if _mode == "open":
		if _arm > 0.0:
			_arm = maxf(0.0, _arm - delta)
		queue_redraw()        # cheap: pulses on the dot + selected card
	elif _mode == "no_upgrades":
		_no_up -= delta
		if _no_up <= 0.0:
			_mode = "closed"
			visible = false
		queue_redraw()


# ── Draw ───────────────────────────────────────────────────────────────────
func _draw() -> void:
	var vp := get_viewport_rect().size
	if _mode == "no_upgrades":
		var a := clampf(_no_up / 0.4, 0.0, 1.0)
		var col := C_TEXT
		col.a = a
		_text(Vector2(vp.x * 0.5 - 500, vp.y * 0.5), "No upgrades available", 34, col, HORIZONTAL_ALIGNMENT_CENTER, 1000, _font_bold)
		return
	if _mode != "open":
		return

	draw_rect(Rect2(Vector2.ZERO, vp), C_DIM)             # dim the world behind

	var o := frame_origin()
	var fs := frame_size()
	_panel(Rect2(o, fs), 28.0, C_FRAME_BG, C_CYAN, 3.0)

	# Title + wallet readouts share the top band.
	_text(Vector2(o.x, o.y + 84), "UPGRADES", 52, C_TITLE, HORIZONTAL_ALIGNMENT_CENTER, fs.x, _font_bold)
	var rx := _draw_readout(o + Vector2(MARGIN, 58), "Stardust: %d/%d" % [stardust, stardust_max], C_PURPLE)
	if unlocked >= 3:   # comets only matter once the Attack / Comet (comet-priced) row appears
		_draw_readout(o + Vector2(MARGIN + rx + 60, 58), "Comets: %d" % comets, C_COMET)

	# Section boxes (white headers) then cards on top (so a selected card's glow isn't clipped).
	for box in _section_boxes():
		var sbox: Rect2 = box.rect
		_panel(sbox, 18.0, Color(0.12, 0.13, 0.18, 0.85), Color(0, 0, 0, 0), 0.0)
		_text(sbox.position + Vector2(24, 40), sections[box.si].title, 30, C_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_bold)
	for i in _cards.size():
		if _cards[i].get("back", false):
			_draw_back(i)
		else:
			_draw_card(i)
	# (No footer hint — the BOT_PAD space below the Back button is kept as padding.)


func _draw_card(i: int) -> void:
	var card: Dictionary = _cards[i]
	var u: Dictionary = _upgrade_at(card)
	var r: Rect2 = card.rect
	var maxed := is_maxed(u)
	var afford := can_buy(card.si, card.ui)
	var sel := i == selected

	# A locked premium card shows nothing but the word LOCKED (no name/pips/cost/desc).
	if _premium_locked(card.si, card.ui):
		_panel(r, 12.0, Color(0.13, 0.13, 0.17), Color(0, 0, 0, 0), 0.0)
		_text(r.position + Vector2(0, r.size.y * 0.5 + 9), "LOCKED", 26, C_DIMTEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, _font_bold)
		return

	var bg := Color(0.16, 0.18, 0.25) if afford else Color(0.13, 0.13, 0.17)
	if sel:
		bg = Color(0.20, 0.24, 0.34)
		_panel(r, 12.0, bg, C_CYAN, 3.0)
	else:
		_panel(r, 12.0, bg, Color(0, 0, 0, 0), 0.0)

	var name_col := C_TEXT if (afford or sel or maxed) else C_DIMTEXT
	# On the final tier (next/last buy), some upgrades rename to the special unlock they grant.
	var nm: String = u.name
	if u.has("last_name") and int(u.level) >= u.sd.size() - 1:
		nm = u.last_name
	_text(r.position + Vector2(18, 36), nm, 25, name_col, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_bold)

	# Level pips under the name (tinted to the section's currency).
	_draw_pips(r.position + Vector2(20, 52), int(u.level), u.sd.size(), section_tint(card.si))

	# Cost (stardust and/or comet dots), right-aligned on the name line (or MAX once capped).
	if maxed:
		_text(r.position + Vector2(0, 36), "MAX", 22, C_DIMTEXT, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 18, _font_bold)
	else:
		var c := cost_of(u)
		_draw_cost(r, c[0], c[1], afford)

	# Description along the bottom (the final tier swaps to its unlock's blurb, alongside last_name).
	# A `warn` upgrade carries a second, orange line below the description for its catch (e.g. the
	# light boost costing +1 core).
	var dsc: String = u.desc
	if u.has("last_desc") and int(u.level) >= u.sd.size() - 1:
		dsc = u.last_desc
	# A capstone level (last_name swap) grants a different unlock, so its track's warn no longer applies.
	var on_capstone: bool = u.has("last_name") and int(u.level) >= u.sd.size() - 1
	var warn: String = "" if on_capstone else u.get("warn", "")
	if warn != "":
		_text(r.position + Vector2(18, r.size.y - 44), dsc, 25, C_DIMTEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 30, _font)
		_text(r.position + Vector2(18, r.size.y - 16), warn, 19, C_WARN, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 30, _font)
	else:
		_text(r.position + Vector2(18, r.size.y - 16), dsc, 25, C_DIMTEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 30, _font)


# The Back button (a navigable target). "[B]ack" — the bracketed B marks the hotkey.
func _draw_back(i: int) -> void:
	var r: Rect2 = _cards[i].rect
	if i == selected:
		_panel(r, 12.0, Color(0.20, 0.24, 0.34), C_CYAN, 3.0)
	else:
		_panel(r, 12.0, Color(0.16, 0.18, 0.25), Color(C_CYAN.r, C_CYAN.g, C_CYAN.b, 0.5), 2.0)
	_text(r.position + Vector2(0, 37), "[B]ack", 26, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, _font_bold)


# Right-aligned cost: a comet segment (rightmost) and/or a stardust segment to its left. Each is
# a number + a glowing currency dot; dims when unaffordable.
func _draw_cost(r: Rect2, sd: int, cm: int, afford: bool) -> void:
	var right := r.position.x + r.size.x - 16.0
	var y_dot := r.position.y + 24.0
	var y_txt := r.position.y + 36.0
	var segs: Array = []
	if sd > 0:
		segs.append([sd, C_PURPLE])
	if cm > 0:
		segs.append([cm, C_COMET])
	for s in range(segs.size() - 1, -1, -1):   # draw right-to-left so comet ends up rightmost
		var n: int = segs[s][0]
		var col: Color = segs[s][1]             # always the currency color (purple = stardust, cyan = comet)
		col.a = 1.0 if afford else 0.5          # dim a touch when you can't afford it, but keep the hue
		_point_glow(Vector2(right - 6.0, y_dot), 6.0, col)
		var ns := str(n)
		var nw := _font_bold.get_string_size(ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		_text(Vector2(right - 18.0 - nw, y_txt), ns, 24, col, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_bold)
		right = right - 18.0 - nw - 14.0


func _draw_pips(pos: Vector2, level: int, maxlv: int, col: Color) -> void:
	var step := 18.0
	var rad := 5.0
	for i in maxlv:
		var c := pos + Vector2(step * i + rad, 0)
		if i < level:
			draw_circle(c, rad, col)
		else:
			draw_circle(c, rad, Color(0.3, 0.3, 0.38))
			draw_arc(c, rad, 0.0, TAU, 16, Color(0.45, 0.45, 0.55), 1.0)


# A wallet readout ("Stardust: x/y") + a glowing dot matching that currency on the rings.
# Returns the label width so the next readout can sit beside it.
func _draw_readout(pos: Vector2, label: String, dot_col: Color) -> float:
	var size := 30
	_text(pos + Vector2(0, 22), label, size, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, _font)
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pulse := 0.85 + 0.15 * sin(_t * 3.0)
	_point_glow(pos + Vector2(w + 26, 16), 8.0 * pulse, dot_col)
	return w + 40.0


# ── Draw helpers ───────────────────────────────────────────────────────────
# Rounded panel with optional border, via a throwaway StyleBoxFlat (gives the mockup's
# rounded corners — draw_rect can't round).
func _panel(rect: Rect2, radius: float, bg: Color, border: Color, bw: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	if bw > 0.0 and border.a > 0.0:
		sb.set_border_width_all(int(bw))
		sb.border_color = border
	draw_style_box(sb, rect)


func _text(pos: Vector2, s: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font: Font = null) -> void:
	draw_string(font if font else _font, pos, s, align, width, size, color)


# Bright point wrapped in soft diffuse light — same recipe as Game.draw_point_glow so the
# HUD dot reads identically to the stardust on the rings.
func _point_glow(p: Vector2, r: float, col: Color) -> void:
	var layers := 5
	for i in range(layers, 0, -1):
		var lt := float(i) / float(layers)
		var gc := col
		gc.a = col.a * 0.30 * (1.0 - lt) * (1.0 - lt)
		draw_circle(p, r * (1.0 + 3.0 * lt), gc)
	var mid := col
	mid.a = col.a * 0.85
	draw_circle(p, r, mid)
	draw_circle(p, r * 0.5, col.lerp(Color(1, 1, 1, col.a), 0.5))
