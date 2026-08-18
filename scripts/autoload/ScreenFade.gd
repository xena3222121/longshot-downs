extends CanvasLayer

## Fade-to-black / fade-from-black transition, used to wrap scene changes and
## race-to-race resets instead of instant cuts. Registered as an autoload
## (not a node owned by any one scene) specifically because autoloads
## survive get_tree().change_scene_to_file — a scene-owned overlay would be
## destroyed along with the rest of the old scene right as it's needed.
## FADE_LAYER is far above BroadcastHUD's layer=9 so it always draws on top
## of literally everything.

const FADE_LAYER: int = 100

var _rect: ColorRect

func _ready() -> void:
	layer = FADE_LAYER
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	add_child(_rect)

func fade_out(duration: float = 0.4) -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP # block clicks reaching whatever's underneath mid-transition
	var tween: Tween = create_tween()
	tween.tween_property(_rect, "modulate:a", 1.0, duration)
	await tween.finished

func fade_in(duration: float = 0.4) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_rect, "modulate:a", 0.0, duration)
	await tween.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
