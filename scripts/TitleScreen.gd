extends Control

## First thing the player sees (project.godot run/main_scene). Three actions,
## top to bottom per AJ's spec: Play Now -> the existing betting/race flow
## (scenes/Main.tscn, unchanged), Credits -> the attribution dialog (moved
## here from BettingUI's old footer), Exit to Desktop -> quit. Built
## procedurally in code, same convention as BettingUI/FinishPodium rather
## than hand-laid-out in the editor. Styling (fonts/colors/button chrome)
## comes entirely from the UITheme autoload's global theme — this script
## only sets sizes/positions, no per-widget color/font overrides, so the
## title screen automatically stays in sync with the rest of the game's look.

const BUTTON_SIZE: Vector2 = Vector2(340.0, 60.0)

func _ready() -> void:
	# Was never needed before InputHints' Circle-to-title feature — TitleScreen
	# used to only ever be the very first scene the game boots into (nothing
	# ever navigated back to it), so nothing previously had to fade back IN on
	# arrival here. Harmless on that original first-boot path too (the fade
	# rect's alpha is already 0 then, so this just tweens 0 -> 0).
	ScreenFade.fade_in()
	AudioManager.play_music("theme")
	_build()

func _build() -> void:
	_build_ambient_glow()

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 18)
	center.add_child(content)

	var title := Label.new()
	title.theme_type_variation = "HeadingLabel"
	title.add_theme_font_size_override("font_size", 76)
	title.text = "LONGSHOT DOWNS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	_start_title_pulse(title)

	var subtitle := Label.new()
	subtitle.text = "— A Thoroughbred Racing & Wagering Experience —"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	subtitle.add_theme_font_size_override("font_size", 18)
	content.add_child(subtitle)

	var rule := HSeparator.new()
	rule.custom_minimum_size = Vector2(360.0, 0.0)
	content.add_child(rule)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 24.0)
	content.add_child(spacer)

	var menu_panel: PanelContainer = UITheme.make_glass_panel_container()
	content.add_child(menu_panel)

	var menu_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		menu_margin.add_theme_constant_override("margin_%s" % side, 32)
	menu_panel.add_child(menu_margin)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 14)
	menu_margin.add_child(menu)

	var play_btn := Button.new()
	play_btn.text = "Play Now"
	play_btn.custom_minimum_size = BUTTON_SIZE
	play_btn.pressed.connect(_on_play_pressed)
	menu.add_child(play_btn)
	UITheme.add_button_juice(play_btn)

	var stable_btn := Button.new()
	stable_btn.text = "Stable"
	stable_btn.custom_minimum_size = BUTTON_SIZE
	stable_btn.pressed.connect(_show_stable)
	menu.add_child(stable_btn)
	UITheme.add_button_juice(stable_btn)

	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.custom_minimum_size = BUTTON_SIZE
	settings_btn.pressed.connect(_show_settings)
	menu.add_child(settings_btn)
	UITheme.add_button_juice(settings_btn)

	var credits_btn := Button.new()
	credits_btn.text = "Credits"
	credits_btn.custom_minimum_size = BUTTON_SIZE
	credits_btn.pressed.connect(_show_credits)
	menu.add_child(credits_btn)
	UITheme.add_button_juice(credits_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Exit to Desktop"
	exit_btn.custom_minimum_size = BUTTON_SIZE
	exit_btn.theme_type_variation = "MaroonButton"
	exit_btn.pressed.connect(func(): get_tree().quit())
	menu.add_child(exit_btn)
	UITheme.add_button_juice(exit_btn)

	play_btn.grab_focus.call_deferred() # lets a gamepad/keyboard player navigate the menu with no mouse at all

const GLOW_SIZE: float = 1100.0

## A single soft radial glow drifting slowly behind the content — the flat
## solid-color background otherwise reads as static/dead on the very first
## screen a player sees. GradientTexture2D (a plain built-in Resource, not a
## shader) keeps this cheap and simple: a center-bright, edge-transparent
## radial fill, faded down to a low modulate alpha so it reads as ambient
## light rather than a visible sprite, breathing in scale and drifting in
## position on two independent slow loops so it never quite repeats.
func _build_ambient_glow() -> void:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UITheme.COLOR_GOLD, 0.55))
	gradient.set_color(1, Color(UITheme.COLOR_GOLD, 0.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 512
	texture.height = 512

	var glow := TextureRect.new()
	glow.texture = texture
	glow.custom_minimum_size = Vector2(GLOW_SIZE, GLOW_SIZE)
	glow.size = Vector2(GLOW_SIZE, GLOW_SIZE)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.anchor_left = 0.5
	glow.anchor_top = 0.5
	glow.position = Vector2(-GLOW_SIZE * 0.5, -GLOW_SIZE * 0.55)
	glow.pivot_offset = Vector2(GLOW_SIZE, GLOW_SIZE) * 0.5
	glow.modulate.a = 0.5
	add_child(glow)

	var drift: Tween = create_tween()
	drift.set_loops()
	drift.tween_property(glow, "position", glow.position + Vector2(60.0, 30.0), 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	drift.tween_property(glow, "position", glow.position + Vector2(-60.0, -20.0), 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var breathe: Tween = create_tween()
	breathe.set_loops()
	breathe.tween_property(glow, "scale", Vector2(1.12, 1.12), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathe.tween_property(glow, "scale", Vector2(1.0, 1.0), 6.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## A slow, subtle breathing scale + glow so the title reads as alive rather
## than a flat screenshot — same continuous-pulse idea FinishPodium already
## uses on the winner's podium block, just gentler (a title shouldn't
## upstage the actual menu).
func _start_title_pulse(title: Label) -> void:
	title.resized.connect(func(): title.pivot_offset = title.size * 0.5)
	var pulse: Tween = create_tween()
	pulse.set_loops()
	pulse.tween_property(title, "scale", Vector2(1.02, 1.02), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(title, "scale", Vector2.ONE, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# modulate multiplies the base font color, so a "brighter" glow needs
	# channels ABOVE 1.0 — multiplying by COLOR_GOLD_BRIGHT's own (all <1.0)
	# channels would darken it instead. Cool cyan-white bias (not warm amber)
	# to match the neon palette's electric-cyan accent instead of the old
	# brass/gold one.
	var glow: Tween = create_tween()
	glow.set_loops()
	glow.tween_property(title, "modulate", Color(1.05, 1.3, 1.4), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	glow.tween_property(title, "modulate", Color.WHITE, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## change_scene_to_file frees this TitleScreen node (the current scene) once
## the deferred swap runs — awaiting anything on `self` after calling it is a
## bug, since the coroutine's owner is gone before it can resume, silently
## dropping whatever ran after (here, that left ScreenFade stuck fully
## opaque forever: a permanent black screen with input blocked). Main.gd's
## own _ready fades back in instead, since Main is the node that actually
## survives to see it through.
func _on_play_pressed() -> void:
	await ScreenFade.fade_out()
	get_tree().change_scene_to_file("res://scenes/TrackLobby.tscn")

## Master/Music/SFX volume sliders + a fullscreen checkbox, all applying live
## through the Settings autoload (each slider's value_changed calls straight
## into Settings.set_*, which persists to disk immediately) — no separate
## Save button needed since there's nothing to discard on Cancel.
func _show_settings() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Settings"
	dialog.ok_button_text = "Close"

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(360.0, 0.0)
	content.add_theme_constant_override("separation", 12)
	dialog.add_child(content)

	_add_volume_slider(content, "Master Volume", Settings.master_volume, Settings.set_master_volume)
	_add_volume_slider(content, "Music Volume", Settings.music_volume, Settings.set_music_volume)
	_add_volume_slider(content, "Sound Effects Volume", Settings.sfx_volume, Settings.set_sfx_volume)

	_add_track_theme_picker(content)
	_add_camera_mode_picker(content)

	var fullscreen_check := CheckBox.new()
	fullscreen_check.text = "Fullscreen"
	fullscreen_check.button_pressed = Settings.fullscreen
	fullscreen_check.toggled.connect(Settings.set_fullscreen)
	content.add_child(fullscreen_check)

	add_child(dialog)
	dialog.popup_centered()
	dialog.get_ok_button().grab_focus.call_deferred() # gamepad player can close/navigate with no mouse
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _add_volume_slider(parent: Control, label_text: String, initial_value: float, on_change: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial_value
	slider.custom_minimum_size = Vector2(0.0, 24.0)
	slider.value_changed.connect(on_change)
	row.add_child(slider)

## Every theme is unlocked from the start (see TrackThemes) — this is purely
## an aesthetic pick, not a progression gate, so there's no reason to make a
## player unlock their way into trying "Storm Coast Downs".
func _add_track_theme_picker(parent: Control) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var label := Label.new()
	label.text = "Track"
	row.add_child(label)

	var option := OptionButton.new()
	for theme_id in TrackThemes.THEME_IDS:
		option.add_item(TrackThemes.label_for(theme_id))
	var current_i: int = TrackThemes.THEME_IDS.find(Settings.track_theme_id)
	option.select(max(current_i, 0))
	option.item_selected.connect(func(index: int): Settings.set_track_theme_id(TrackThemes.THEME_IDS[index]))
	row.add_child(option)

## Camera mode also cycles live mid-race via the C key/gamepad Y button (see
## RaceTrack3D._unhandled_input) — this picker just sets which mode a race
## STARTS on, and stays in sync since both paths write through
## Settings.set_camera_mode.
func _add_camera_mode_picker(parent: Control) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var label := Label.new()
	label.text = "Camera (cycle mid-race with C / gamepad Y)"
	row.add_child(label)

	var option := OptionButton.new()
	var modes: Array[String] = RaceTrack3D.CAMERA_MODE_ORDER
	for mode in modes:
		option.add_item(mode.capitalize())
	option.select(max(modes.find(Settings.camera_mode), 0))
	option.item_selected.connect(func(index: int): Settings.set_camera_mode(modes[index]))
	row.add_child(option)

## Career/meta-progression summary — current class, lifetime totals, and
## which achievements are unlocked so far. Same AcceptDialog-with-plain-text
## pattern as _show_credits rather than a bespoke scrollable widget; the
## content is short enough not to need one.
func _show_stable() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Your Stable"
	dialog.dialog_text = _stable_summary_text()
	add_child(dialog)
	dialog.popup_centered()
	dialog.get_ok_button().grab_focus.call_deferred()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _stable_summary_text() -> String:
	var lines: PackedStringArray = []
	lines.append("Class: %s" % Career.get_current_class().name)
	lines.append("Races run: %d" % Career.total_races)
	lines.append("Current win streak: %d    Best streak: %d" % [Career.current_streak, Career.best_streak])
	lines.append("")
	lines.append("Achievements (%d/%d):" % [Career.achievements_unlocked.size(), Career.ACHIEVEMENTS.size()])
	for id in Career.ACHIEVEMENTS.keys():
		var unlocked: bool = Career.achievements_unlocked.has(id)
		var mark: String = "✓" if unlocked else "-"
		lines.append("  %s %s — %s" % [mark, Career.achievement_name(id), Career.ACHIEVEMENTS[id].description])

	var records: Array = []
	for key in Career.horse_stats.keys():
		var stats: Dictionary = Career.horse_stats[key]
		if int(stats.get("wins", 0)) > 0:
			records.append({"id": int(key), "wins": int(stats.get("wins", 0)), "races": int(stats.get("races", 0))})
	if not records.is_empty():
		records.sort_custom(func(a, b): return a.wins > b.wins)
		lines.append("")
		lines.append("Winningest horses:")
		for entry in records.slice(0, 5):
			var horse_name: String = HorseRoster.NAMES[entry.id] if entry.id < HorseRoster.NAMES.size() else "Horse #%d" % entry.id
			lines.append("  %s — %dW-%dR" % [horse_name, entry.wins, entry.races])

	return "\n".join(lines)

func _show_credits() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Credits"
	dialog.dialog_text = "Longshot Downs\n\n" \
		+ "Music: \"Calm Ambient 2 (Synthwave 15k)\" by The Cynic Project (OpenGameArt.org), CC0.\n\n" \
		+ "Horse model: Quaternius (quaternius.com), CC0.\n\n" \
		+ "Sound effects: Kenney.nl, OpenGameArt.org, Freesound.org — all CC0.\n\n" \
		+ "Typeface: Playfair Display by Claus Eggers Sørensen, SIL Open Font License 1.1."
	add_child(dialog)
	dialog.popup_centered()
	dialog.get_ok_button().grab_focus.call_deferred()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
