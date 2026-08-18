extends Node

## "Steam-like" controller layer. Godot's built-in ui_up/down/left/right/
## accept/cancel actions already carry default joypad bindings with no
## project.godot [input] section needed (see RaceTrack3D._unhandled_input's
## own comment on why this project avoids hand-editing one), so Control
## focus navigation/activation across TitleScreen/BettingUI/FinishPodium/
## Settings already works on a gamepad out of the box. What's missing is the
## Big-Picture-style POLISH that makes that obvious: a bottom-corner button-
## prompt bar, a controller-connected toast, and light rumble on a few race
## beats. Registered as an autoload so it persists across every scene change
## (TitleScreen -> Main -> race) without needing to be added per-scene.

const TOAST_HOLD: float = 2.2
const TOAST_FADE: float = 0.35

var _is_gamepad_active: bool = false
var _hint_bar: HBoxContainer
var _hint_label: Label
var _toast_label: Label
var _toast_elapsed: float = 0.0
var _toast_active: bool = false

## Per-screen extra prompts appended after the generic Select/Back (e.g. the
## race screen's camera controls) — see set_context_hints. Each entry is
## {"button": "Y", "ps_button": "△" (optional, defaults to `button`), "label": "..."}.
var _context_hints: Array[Dictionary] = []
## The generic gate (gamepad active AND some Control has focus) is right for
## every menu screen, but the race itself has no focused Control at all — a
## screen with real gamepad-relevant context (see RaceTrack3D's camera hints)
## sets this true so the bar stays visible there too.
var _context_visible_without_focus: bool = false

func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_build_hint_bar()
	_build_toast()

## Tracks which input device the player is CURRENTLY driving the UI with —
## the hint bar only makes sense to show while a gamepad is actually in use,
## not just because one happens to be plugged in.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_is_gamepad_active = true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_is_gamepad_active = false

	if not (event is InputEventJoypadButton):
		return

	var viewport: Viewport = get_viewport()
	var focused: Control = viewport.gui_get_focus_owner() if viewport != null else null

	# An OptionButton's native popup turned out to be unreliable for gamepad
	# navigation on this controller/engine build (Cross opens it, but
	# navigating/selecting inside it doesn't work — a separate Window from
	# the one the ui_accept relay below easily reaches). Fix: never let
	# Cross or D-pad left/right reach the popup at all while an OptionButton
	# has focus — cycle its value directly instead, the same way plenty of
	# console-style settings menus present a dropdown as a "< Option >"
	# cycler instead of a popup list. Up/down/Circle still pass through
	# untouched, so leaving the control or backing out still works normally.
	if focused is OptionButton and _is_option_cycle_button(event.button_index):
		if event.pressed:
			_cycle_option_button(focused, event.button_index)
		viewport.set_input_as_handled() # don't ALSO let this open the popup or move focus via the default ui_left/right handling
		return

	# D-pad/stick already move menu focus fine (ui_up/down/left/right are
	# hat/axis-based, which this controller + engine build clearly deliver
	# correctly). Confirmed via a live diagnostic that Cross reports raw
	# button_index 0 (== JOY_BUTTON_A, exactly what Godot's built-in ui_accept
	# binding expects) — so the raw event IS arriving correctly, but it isn't
	# reaching Button._gui_input as the ui_accept action on this controller/
	# engine build combination for some reason not worth chasing further.
	# Explicitly relaying it as a synthetic ui_accept/ui_cancel action event
	# (not just flipping a polling flag — parse_input_event feeds a REAL
	# event through the normal pipeline so Button's own press/toggle handling
	# runs exactly like a genuine click) sidesteps whatever's swallowing the
	# automatic path, independent of root cause.
	_relay_ui_action(event, JOY_BUTTON_A, "ui_accept")
	_relay_ui_action(event, JOY_BUTTON_B, "ui_cancel")

	# Circle as a universal "back to main menu" from anywhere in Main.tscn's
	# flow (betting/race/podium) — there was previously no way back to
	# TitleScreen short of quitting the app, which is exactly the "leaving
	# you stuck" AJ hit. TitleScreen's own dialogs (Settings/Stable/Credits)
	# are never open while Main.tscn is the current scene, so there's no
	# conflict with their own Circle-closes-dialog behavior (that's handled
	# entirely by each AcceptDialog's own `canceled` signal reacting to the
	# ui_cancel relay above).
	if event.pressed and event.button_index == JOY_BUTTON_B:
		_try_return_to_title()

func _is_option_cycle_button(button_index: int) -> bool:
	return button_index == JOY_BUTTON_A or button_index == JOY_BUTTON_DPAD_LEFT or button_index == JOY_BUTTON_DPAD_RIGHT

func _cycle_option_button(option: OptionButton, button_index: int) -> void:
	if option.item_count == 0:
		return
	var delta: int = -1 if button_index == JOY_BUTTON_DPAD_LEFT else 1
	var next: int = wrapi(option.selected + delta, 0, option.item_count)
	option.select(next)
	option.item_selected.emit(next)

func _try_return_to_title() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return
	if tree.current_scene.scene_file_path != "res://scenes/TrackLobby.tscn":
		return
	clear_context_hints() # in case a race was abandoned mid-flight — otherwise stale camera hints would linger into the title screen
	AudioManager.stop_race_ambience() # safety cleanup for the same reason — otherwise the music stays ducked forever if a race never reached its own stop_race_ambience() call
	RaceScheduler.force_finish_all_races() # otherwise any mid-flight screen's venue would stay paused forever if its race was abandoned this way
	RaceScheduler.stop_watching() # freeze every countdown until the lobby is actually open again to receive race_ready
	await ScreenFade.fade_out()
	tree.change_scene_to_file("res://scenes/TitleScreen.tscn")

func _relay_ui_action(event: InputEventJoypadButton, button_index: int, action: String) -> void:
	if event.button_index != button_index:
		return
	var synthetic := InputEventAction.new()
	synthetic.action = action
	synthetic.pressed = event.pressed
	Input.parse_input_event(synthetic)

func _process(delta: float) -> void:
	var viewport: Viewport = get_viewport()
	var has_focus: bool = viewport != null and viewport.gui_get_focus_owner() != null
	_hint_bar.visible = _is_gamepad_active and (has_focus or _context_visible_without_focus)
	_update_toast(delta)

## Called by whichever screen currently has gamepad-relevant actions beyond
## the generic Select/Back (e.g. RaceTrack3D's camera-cycle/free-look
## controls) — appended to the hint bar until the caller clears them.
## `visible_without_focus` should be true for screens (like the race itself)
## that have no focused Control at all, where the bar would otherwise stay
## hidden regardless of these hints.
func set_context_hints(hints: Array[Dictionary], visible_without_focus: bool = false) -> void:
	_context_hints = hints
	_context_visible_without_focus = visible_without_focus
	_refresh_hint_text()

func clear_context_hints() -> void:
	_context_hints = []
	_context_visible_without_focus = false
	_refresh_hint_text()

func _build_hint_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30 # above BroadcastHUD (layer 9) and every plain-Control screen (default layer 0)
	add_child(layer)

	_hint_bar = HBoxContainer.new()
	_hint_bar.add_theme_constant_override("separation", 24)
	_hint_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_bar.visible = false
	layer.add_child(_hint_bar)
	# Content width depends on which glyph set is active (PlayStation vs
	# generic) — reposition once actual size is known instead of guessing,
	# same "defer to resized" idiom UITheme already uses for glass panels.
	_hint_bar.resized.connect(_reposition_hint_bar)

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_bar.add_child(_hint_label)
	_refresh_hint_text()

func _reposition_hint_bar() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	_hint_bar.position = viewport_size - _hint_bar.size - Vector2(24.0, 20.0)

func _refresh_hint_text() -> void:
	var is_ps: bool = _is_playstation_pad()
	var parts: PackedStringArray = []
	parts.append("✕ Select" if is_ps else "Ⓐ Select")
	parts.append("○ Back" if is_ps else "Ⓑ Back")
	for hint in _context_hints:
		var glyph: String = str(hint.get("button", "?"))
		if is_ps and hint.has("ps_button"):
			glyph = str(hint.ps_button)
		parts.append("%s %s" % [glyph, str(hint.get("label", ""))])
	_hint_label.text = "      ".join(parts)

## Godot doesn't expose a "this is a PlayStation pad" flag directly — the
## controller's reported name is the only cross-platform signal available,
## so this is a heuristic, not a guarantee. Falls back to generic Xbox-style
## glyphs for anything unrecognized (including no controller connected at
## all, in which case the hint bar is hidden anyway).
func _is_playstation_pad() -> bool:
	for id in Input.get_connected_joypads():
		var joy_name: String = Input.get_joy_name(id).to_lower()
		if "sony" in joy_name or "playstation" in joy_name or "dualshock" in joy_name or "dualsense" in joy_name or "wireless controller" in joy_name:
			return true
	return false

func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 31
	add_child(layer)

	_toast_label = Label.new()
	_toast_label.theme_type_variation = "EyebrowLabel"
	_toast_label.add_theme_font_size_override("font_size", 16)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.custom_minimum_size = Vector2(440.0, 30.0)
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.modulate.a = 0.0
	layer.add_child(_toast_label)

	var viewport: Viewport = get_viewport()
	var viewport_width: float = viewport.get_visible_rect().size.x if viewport != null else 1600.0
	_toast_label.position = Vector2((viewport_width - 440.0) * 0.5, 26.0)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	_refresh_hint_text()
	if connected:
		_show_toast("🎮 Controller Connected — %s" % Input.get_joy_name(device))
	else:
		_show_toast("🎮 Controller Disconnected")

func _show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_elapsed = 0.0
	_toast_active = true

func _update_toast(delta: float) -> void:
	if not _toast_active:
		return
	_toast_elapsed += delta
	var hold_end: float = TOAST_FADE + TOAST_HOLD
	var fade_out_end: float = hold_end + TOAST_FADE
	if _toast_elapsed < TOAST_FADE:
		_toast_label.modulate.a = _toast_elapsed / TOAST_FADE
	elif _toast_elapsed < hold_end:
		_toast_label.modulate.a = 1.0
	elif _toast_elapsed < fade_out_end:
		_toast_label.modulate.a = 1.0 - (_toast_elapsed - hold_end) / TOAST_FADE
	else:
		_toast_label.modulate.a = 0.0
		_toast_active = false

## Light haptic feedback for key race beats (gate open, big surge) — a no-op
## with no controller connected. A different feedback channel than audio, not
## a repeat of either audio addition this project already cut (the announcer,
## the "whoosh" SFX) — those were sound; this is rumble.
func rumble(weak: float, strong: float, duration: float) -> void:
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, weak, strong, duration)
