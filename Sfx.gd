extends Node
# Central sound-effect bus (autoload singleton `Sfx`). Every gameplay/UI event calls
# Sfx.play("name"); the file lives at assets/sound/sfx/<name>.{wav,ogg,mp3}. Sounds are still
# being gathered, so a MISSING file is a silent no-op (no crash, no error spam) — the call sites
# are wired now and start making noise the moment the matching file lands in that folder.
#
# Usage:
#   Sfx.play("boost")              one-shot, pooled (polyphonic — many can overlap)
#   Sfx.play("boost", 0.10)        one-shot with ±0.10 random pitch (variety on rapid repeats)
#   Sfx.play("asteroid_hit", 0.05, 1.3)  one-shot at a chosen base pitch (+ a little jitter)
#   Sfx.loop("beam")               start a sustained loop (idempotent; needs loop set on import)
#   Sfx.stop("beam")               stop that loop
#
# Buses (set up once in _ready, persist for the session): SFX rides its own "SFX" bus and music
# rides "Music"; both feed Master. The master volume slider drives Master, and the Music/SFX
# toggles mute their bus — so the two are controllable independently.

const DIR := "res://assets/sound/sfx/"
const EXTS := ["wav", "ogg", "mp3"]
const POOL := 12          # how many one-shots can sound at once before the oldest is reused

var _pool: Array = []     # round-robin AudioStreamPlayer pool for one-shots
var _next := 0
var _cache := {}          # name -> AudioStream, or null once we've confirmed no file exists
var _loops := {}          # name -> persistent AudioStreamPlayer (one per looping sound)


func _ready() -> void:
	_ensure_buses()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)


# Create the "Music" and "SFX" buses (both sending to Master) if they don't exist yet. This runs
# from the autoload so the buses are present app-wide — the menu's audio toggles need them before
# Game ever loads. Idempotent: AudioServer buses persist across scene reloads, so reuse any that
# already exist. The Music bus carries a (disabled) low-pass filter that Game toggles to muffle the
# track while paused — see Game._set_music_muffled().
func _ensure_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.add_bus_effect(idx, AudioEffectLowPassFilter.new())
		AudioServer.set_bus_effect_enabled(idx, 0, false)
	if AudioServer.get_bus_index("SFX") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")


# Resolve a name to its stream, trying each extension once. Result (incl. "no file") is cached.
func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var found: AudioStream = null
	for e in EXTS:
		var path: String = DIR + name + "." + e
		if ResourceLoader.exists(path):
			found = load(path)
			break
	_cache[name] = found
	return found


# One-shot. `pitch_var` > 0 jitters pitch by ±pitch_var (keeps spammy cues from machine-gunning);
# `base_pitch` sets the center pitch (e.g. asteroids rising in pitch as they take damage);
# `volume_db` trims a too-loud cue (negative = quieter), relative to the file's own level.
func play(name: String, pitch_var := 0.0, base_pitch := 1.0, volume_db := 0.0) -> void:
	var s := _stream(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.pitch_scale = base_pitch + (randf_range(-pitch_var, pitch_var) if pitch_var > 0.0 else 0.0)
	p.volume_db = volume_db
	p.play()


# Start a sustained loop (e.g. the blaster beam). Idempotent — calling it while already looping
# does nothing. The file itself must be set to loop in its import settings.
func loop(name: String) -> void:
	var p: AudioStreamPlayer = _loops.get(name)
	if p == null:
		var s := _stream(name)
		if s == null:
			return
		p = AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = s
		add_child(p)
		_loops[name] = p
	if not p.playing:
		p.play()


func stop(name: String) -> void:
	var p: AudioStreamPlayer = _loops.get(name)
	if p != null and p.playing:
		p.stop()
