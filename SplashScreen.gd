extends Control
class_name SplashScreen
# Studio splash — plays first (project main_scene), then loads the main menu.
# Black screen → 8-Bit Curls logo fades up → holds → fades back to black → MainMenu.
# Any key / click skips straight to the menu (so it's not a wall on repeat plays).

const NEXT_SCENE := "res://MainMenu.tscn"
const FADE_IN := 1.5     # seconds — logo fades up
const HOLD := 1.0        # seconds — logo sits at full opacity
const FADE_OUT := 1.5    # seconds — logo fades back to black (~4s total)

@onready var logo: TextureRect = $Logo

var _leaving := false

func _ready() -> void:
	logo.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(logo, "modulate:a", 1.0, FADE_IN)
	tween.tween_interval(HOLD)
	tween.tween_property(logo, "modulate:a", 0.0, FADE_OUT)
	tween.tween_callback(_go_to_menu)

func _go_to_menu() -> void:
	if _leaving:
		return            # guard: tween-finish and a skip could both fire
	_leaving = true
	get_tree().change_scene_to_file(NEXT_SCENE)

func _unhandled_input(event: InputEvent) -> void:
	var skip: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if skip:
		_go_to_menu()
