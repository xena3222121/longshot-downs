class_name BroadcastHUD
extends CanvasLayer

## TVG/Woodbine-style broadcast overlay — modeled directly on a real harness
## racing stream screenshot AJ shared: a track/race header (top-left), a
## dark bottom bar with a live leaderboard (post-position chip colored by
## silk + horse name + odds, updating as running order changes) topped by a
## race-progress fill, and a small track-position minimap + speed readout
## in the corner. Separate concern from the arcade-excess camera/particle
## effects (camera shake/punch-zoom, HorseMarker3D's surge trail) — this is
## informational broadcast polish, not a special-move spectacle.

const TOP_N_SHOWN: int = 4 # the reference only shows a handful of current leaders, not the full field
const CHIP_SIZE: float = 30.0
const ROW_HEIGHT: float = 34.0
const BOTTOM_BAR_HEIGHT: float = 150.0
const PROGRESS_BAR_HEIGHT: float = 6.0
## Real broadcast leaderboards don't flicker every frame when two horses are
## a hair apart — they settle on an order and hold it for a beat.
const REORDER_INTERVAL: float = 0.4
const START_BANNER_HOLD: float = 1.1
const START_BANNER_FADE: float = 0.4

const COMMENTARY_HOLD: float = 2.4
const COMMENTARY_FADE: float = 0.4

const COUNTDOWN_STEPS: Array[String] = ["RIDERS UP", "3", "2", "1"]
const COUNTDOWN_STEP_HOLD: float = 0.55
const COUNTDOWN_STEP_FADE: float = 0.15

## Same world-scale derivation as RaceSim.MAX_GAP_FROM_LEADER's comment
## (rail-lane perimeter ~443 world units/lap -> ~8.8 sim-units per
## world-unit) — turns the leader's sim speed into a plausible-looking
## km/h readout instead of a made-up number.
const SIM_UNITS_PER_WORLD_UNIT: float = 8.797
const WORLD_UNITS_PER_METER: float = 1.0

static var _race_number: int = 0

var field: Array[Horse] = []
var result: RaceResult
var _venue_label: String = "LONGSHOT DOWNS"
var _straight_len: float = 140.0
var _inner_radius: float = 26.0
var _rows: Array[Control] = []
var _row_labels: Array[Label] = []
var _row_chips: Array[Panel] = []
var _row_chip_styles: Array[StyleBoxFlat] = []
var _row_current_horse: Array[int] = [] # which horse currently occupies each row slot — see _animate_row_swap
var _leaderboard_vbox: VBoxContainer
var _progress_fill: ColorRect
var _progress_bar_width: float = 0.0
var _clock_label: Label
var _speed_label: Label
var _minimap: Control
var _minimap_percent_label: Label
var _all_fractions: PackedFloat32Array = PackedFloat32Array()
var _banner: Label
var _commentary_label: Label
var _countdown_label: Label
var _live_indicator: Control

var _commentary_elapsed: float = 0.0
var _commentary_active: bool = false

var _reorder_timer: float = 0.0
var _banner_elapsed: float = 0.0
var _prev_leader_fraction: float = 0.0
var _has_prev_leader_fraction: bool = false
var _current_speed_kmh: float = 0.0
var _leader_fraction: float = 0.0

func setup(p_field: Array[Horse], p_result: RaceResult, bet_context: Dictionary = {}, straight_len: float = 140.0, inner_radius: float = 26.0, venue_label: String = "LONGSHOT DOWNS") -> void:
	field = p_field
	result = p_result
	_straight_len = straight_len
	_inner_radius = inner_radius
	_venue_label = venue_label
	_race_number += 1
	_build(bet_context)

func _build(bet_context: Dictionary = {}) -> void:
	layer = 9 # above the 3D viewport

	_build_header()
	_build_bottom_bar()
	_build_start_banner()
	_build_commentary()
	_build_countdown()
	_build_bet_panel(bet_context)

func _build_header() -> void:
	var glass: PanelContainer = UITheme.make_glass_panel_container(14.0, Color(0.016, 0.027, 0.047, 0.55))
	glass.position = Vector2(20.0, 16.0)
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glass)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	glass.add_child(margin)

	var header := VBoxContainer.new()
	margin.add_child(header)

	var track_name := Label.new()
	track_name.theme_type_variation = "HeadingLabel"
	track_name.add_theme_font_size_override("font_size", 26)
	track_name.text = _venue_label
	header.add_child(track_name)

	var race_row := HBoxContainer.new()
	race_row.add_theme_constant_override("separation", 10)
	header.add_child(race_row)

	var race_label := Label.new()
	race_label.add_theme_font_size_override("font_size", 16)
	race_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	race_label.text = "RACE %d — %s" % [_race_number, Career.get_current_class().name]
	race_row.add_child(race_label)

	_build_live_indicator(race_row)

## Small pulsing red dot + "LIVE" text next to the race number.
func _build_live_indicator(parent: Control) -> void:
	_live_indicator = HBoxContainer.new()
	_live_indicator.add_theme_constant_override("separation", 5)
	parent.add_child(_live_indicator)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(9.0, 9.0)
	dot.color = UITheme.COLOR_MAROON_LIGHT
	_live_indicator.add_child(dot)

	var pulse: Tween = create_tween()
	pulse.set_loops()
	pulse.tween_property(dot, "modulate:a", 0.35, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(dot, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var live_label := Label.new()
	live_label.add_theme_font_size_override("font_size", 14)
	live_label.add_theme_color_override("font_color", UITheme.COLOR_CREAM)
	live_label.text = "LIVE"
	_live_indicator.add_child(live_label)

## Top-right "YOUR BET" card, mirroring the top-left header — there was
## previously no way to see what you'd actually wagered once the betting
## screen hid itself for the race. `bet_context` is `{bet_type, picks,
## amount, dd_leg}` — Main.gd builds it fresh per race (see its comments),
## since a Daily Double's two legs each only show THAT leg's own relevant
## pick, not the other leg's pick into a different race's field. No-ops if
## empty (bet_context defaults to {} for every caller, so this can't crash
## an existing call site that doesn't know about it).
func _build_bet_panel(bet_context: Dictionary) -> void:
	if bet_context.is_empty():
		return

	var glass: PanelContainer = UITheme.make_glass_panel_container(14.0, Color(0.016, 0.027, 0.047, 0.55))
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glass)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	glass.add_child(margin)

	var box := VBoxContainer.new()
	margin.add_child(box)

	var eyebrow := Label.new()
	eyebrow.theme_type_variation = "EyebrowLabel"
	eyebrow.text = "YOUR BET"
	box.add_child(eyebrow)

	var bet_label := Label.new()
	bet_label.add_theme_font_size_override("font_size", 18)
	bet_label.text = _bet_description(bet_context)
	box.add_child(bet_label)

	# Border tinted with the picked horse's own silk color when there's
	# exactly one pick to show — same "colors are the identity" convention
	# as the bet-slip color swatches and the on-track coat tinting.
	var picks: Array = bet_context.get("picks", [])
	if picks.size() == 1 and int(picks[0]) < field.size():
		var horse: Horse = field[int(picks[0])]
		var mat: ShaderMaterial = glass.material
		mat.set_shader_parameter("border_color", Color(horse.silk_primary, 0.85))

	# Width depends on the bet description's length — reposition once actual
	# size is known, same "defer to resized" idiom the rest of this project's
	# UI already uses for anything anchored by its own far edge.
	glass.resized.connect(func():
		var viewport: Viewport = get_viewport()
		if viewport == null:
			return
		glass.position = Vector2(viewport.get_visible_rect().size.x - glass.size.x - 20.0, 16.0)
	)

func _bet_description(bet_context: Dictionary) -> String:
	var bet_type: OddsTable.BetType = bet_context.get("bet_type", OddsTable.BetType.WIN)
	var picks: Array = bet_context.get("picks", [])
	var amount: int = int(bet_context.get("amount", 0))
	var dd_leg: int = int(bet_context.get("dd_leg", 0))

	var names: Array[String] = []
	for p in picks:
		var idx: int = int(p)
		if idx >= 0 and idx < field.size():
			names.append(field[idx].horse_name)

	var type_label: String = OddsTable.bet_type_label(bet_type)
	if dd_leg == 1:
		type_label = "Daily Double (Leg 1 of 2)"
	elif dd_leg == 2:
		type_label = "Daily Double (Leg 2 of 2)"

	var picks_text: String = " & ".join(names)
	return "%s\n%s — %s" % [OddsTable.format_money(amount), type_label, picks_text]


func _build_bottom_bar() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_progress_bar_width = viewport_size.x

	# Real frosted glass over the live race now, not a flat tinted rectangle —
	# corner_radius 0 since this bar is docked flush to all three screen
	# edges (a floating rounded card wouldn't sit right full-bleed).
	var bar: Panel = UITheme.make_glass_panel(
		Vector2(viewport_size.x, BOTTOM_BAR_HEIGHT), 0.0, Color(0.016, 0.027, 0.047, 0.7), UITheme.COLOR_GOLD,
	)
	bar.position = Vector2(0.0, viewport_size.y - BOTTOM_BAR_HEIGHT)
	add_child(bar)

	var progress_track := ColorRect.new()
	progress_track.position = Vector2(0.0, 0.0)
	progress_track.size = Vector2(_progress_bar_width, PROGRESS_BAR_HEIGHT)
	progress_track.color = Color(1.0, 1.0, 1.0, 0.15)
	bar.add_child(progress_track)

	_progress_fill = ColorRect.new()
	_progress_fill.position = Vector2(0.0, 0.0)
	_progress_fill.size = Vector2(0.0, PROGRESS_BAR_HEIGHT)
	_progress_fill.color = UITheme.COLOR_GOLD
	bar.add_child(_progress_fill)

	var margin := MarginContainer.new()
	margin.position = Vector2(16.0, PROGRESS_BAR_HEIGHT + 10.0)
	margin.size = Vector2(viewport_size.x - 32.0, BOTTOM_BAR_HEIGHT - PROGRESS_BAR_HEIGHT - 20.0)
	bar.add_child(margin)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 40)
	margin.add_child(content)

	_leaderboard_vbox = VBoxContainer.new()
	_leaderboard_vbox.add_theme_constant_override("separation", 4)
	content.add_child(_leaderboard_vbox)

	for i in range(min(TOP_N_SHOWN, field.size())):
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
		row.add_theme_constant_override("separation", 10)

		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(CHIP_SIZE, CHIP_SIZE)
		var chip_style := StyleBoxFlat.new()
		chip_style.set_corner_radius_all(9)
		chip.add_theme_stylebox_override("panel", chip_style)
		var chip_label := Label.new()
		chip_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(chip_label)
		row.add_child(chip)
		_row_chip_styles.append(chip_style)

		var label := Label.new()
		label.add_theme_font_size_override("font_size", 20)
		label.custom_minimum_size = Vector2(260.0, 0.0)
		row.add_child(label)
		_row_labels.append(label)

		_leaderboard_vbox.add_child(row)
		_rows.append(row)

	var minimap_box := VBoxContainer.new()
	minimap_box.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(minimap_box)

	_minimap = Control.new()
	# Sized closer to the real stadium's actual aspect ratio (two long
	# straights + two tight turns is much wider than tall) now that the
	# drawing below samples the real shape instead of a generic ellipse —
	# see _on_draw_minimap.
	_minimap.custom_minimum_size = Vector2(150.0, 48.0)
	_minimap.draw.connect(_on_draw_minimap)
	minimap_box.add_child(_minimap)

	_minimap_percent_label = Label.new()
	_minimap_percent_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_minimap_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_minimap_percent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_minimap_percent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_percent_label.add_theme_font_size_override("font_size", 13)
	_minimap_percent_label.add_theme_color_override("font_color", UITheme.COLOR_CREAM)
	_minimap_percent_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_minimap_percent_label.add_theme_constant_override("outline_size", 3)
	_minimap_percent_label.text = "0%"
	_minimap.add_child(_minimap_percent_label) # drawn on top of the parent's own _draw polyline/dots, since children render after their parent

	_speed_label = Label.new()
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_speed_label.add_theme_font_size_override("font_size", 16)
	_speed_label.text = "0 km/h"
	minimap_box.add_child(_speed_label)

	_clock_label = Label.new()
	_clock_label.theme_type_variation = "HeadingLabel"
	_clock_label.add_theme_font_size_override("font_size", 28)
	_clock_label.text = "0:00.0"
	content.add_child(_clock_label)

func _build_start_banner() -> void:
	_banner = Label.new()
	_banner.text = "OFF AND RUNNING!"
	_banner.theme_type_variation = "HeadingLabel"
	_banner.add_theme_font_size_override("font_size", 44)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.position = Vector2(-260.0, 40.0)
	_banner.custom_minimum_size = Vector2(520.0, 60.0)
	_banner.modulate.a = 0.0
	add_child(_banner)

## Live commentary caption — RaceAnnouncerDirector's TTS lines shown as text
## too, so the call is legible with TTS off/muted. Sits just under the start
## banner (which fades out well before real commentary starts firing).
func _build_commentary() -> void:
	_commentary_label = Label.new()
	_commentary_label.theme_type_variation = "HeadingLabel"
	_commentary_label.add_theme_font_size_override("font_size", 22)
	_commentary_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_commentary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_commentary_label.anchor_left = 0.5
	_commentary_label.anchor_right = 0.5
	_commentary_label.position = Vector2(-320.0, 110.0)
	_commentary_label.custom_minimum_size = Vector2(640.0, 40.0)
	_commentary_label.modulate.a = 0.0
	add_child(_commentary_label)

## Reused by both the countdown sequence and (implicitly, via its own timer
## below) live commentary — a single big centered label, since the two never
## run at the same time (countdown finishes and is hidden before `play()`,
## and thus before any commentary, ever runs).
func _build_countdown() -> void:
	_countdown_label = Label.new()
	_countdown_label.theme_type_variation = "HeadingLabel"
	_countdown_label.add_theme_font_size_override("font_size", 52)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.anchor_left = 0.5
	_countdown_label.anchor_right = 0.5
	_countdown_label.position = Vector2(-260.0, 140.0)
	_countdown_label.custom_minimum_size = Vector2(520.0, 70.0)
	_countdown_label.modulate.a = 0.0
	_countdown_label.visible = false
	add_child(_countdown_label)

func show_commentary(text: String) -> void:
	_commentary_label.text = text
	_commentary_elapsed = 0.0
	_commentary_active = true

## "Riders up... post time..." beat awaited by RaceTrack3D.play_with_post_time
## before the race itself starts ticking — each step fades in, holds, fades
## out in turn.
func play_post_time_sequence() -> void:
	_countdown_label.visible = true
	for step_text in COUNTDOWN_STEPS:
		_countdown_label.text = step_text
		_countdown_label.modulate.a = 0.0
		var fade_in: Tween = create_tween()
		fade_in.tween_property(_countdown_label, "modulate:a", 1.0, COUNTDOWN_STEP_FADE)
		await get_tree().create_timer(COUNTDOWN_STEP_FADE + COUNTDOWN_STEP_HOLD).timeout
		var fade_out: Tween = create_tween()
		fade_out.tween_property(_countdown_label, "modulate:a", 0.0, COUNTDOWN_STEP_FADE)
		await get_tree().create_timer(COUNTDOWN_STEP_FADE).timeout
	_countdown_label.visible = false

func update(delta: float, playback_time: float, fractions: PackedFloat32Array) -> void:
	_clock_label.text = _format_clock(playback_time)
	_update_banner(delta)
	_update_commentary(delta)
	_update_progress(fractions)
	_update_speed(delta, fractions)

	_reorder_timer -= delta
	if _reorder_timer > 0.0:
		return
	_reorder_timer = REORDER_INTERVAL
	_update_leaderboard(fractions)

func _update_progress(fractions: PackedFloat32Array) -> void:
	_all_fractions = fractions
	var leader_fraction: float = 0.0
	for f in fractions:
		leader_fraction = max(leader_fraction, f)
	_leader_fraction = clamp(leader_fraction, 0.0, 1.0)
	_progress_fill.size.x = _progress_bar_width * _leader_fraction
	_minimap_percent_label.text = "%d%%" % int(round(_leader_fraction * 100.0))
	_minimap.queue_redraw()

func _update_speed(delta: float, fractions: PackedFloat32Array) -> void:
	var leader_fraction: float = 0.0
	for f in fractions:
		leader_fraction = max(leader_fraction, f)

	if _has_prev_leader_fraction and delta > 0.0:
		var delta_fraction: float = leader_fraction - _prev_leader_fraction
		var sim_units_per_sec: float = delta_fraction * RaceSim.TRACK_LENGTH / delta
		var meters_per_sec: float = sim_units_per_sec / SIM_UNITS_PER_WORLD_UNIT * WORLD_UNITS_PER_METER
		var kmh: float = max(0.0, meters_per_sec * 3.6)
		_current_speed_kmh = lerp(_current_speed_kmh, kmh, 0.15) # smoothed, raw per-tick delta is noisy
		_speed_label.text = "%.1f km/h" % _current_speed_kmh

	_prev_leader_fraction = leader_fraction
	_has_prev_leader_fraction = true

func _update_leaderboard(fractions: PackedFloat32Array) -> void:
	var order: Array[int] = []
	for i in range(fractions.size()):
		order.append(i)
	order.sort_custom(func(a, b): return fractions[a] > fractions[b])

	if _row_current_horse.size() != _rows.size():
		_row_current_horse.resize(_rows.size())
		_row_current_horse.fill(-1)

	for row_i in range(_rows.size()):
		var horse_idx: int = order[row_i]
		var horse: Horse = field[horse_idx]
		var tier: Dictionary = result.field[horse_idx].tier
		_row_chip_styles[row_i].bg_color = horse.silk_primary
		_row_chip_styles[row_i].border_color = horse.silk_secondary
		_row_chip_styles[row_i].set_border_width_all(2)
		var chip_label: Label = _rows[row_i].get_child(0).get_child(0)
		chip_label.text = str(horse_idx + 1)
		chip_label.add_theme_color_override("font_color", horse.silk_secondary)
		_row_labels[row_i].text = "%s  %s" % [horse.horse_name, tier.get("label", "")]

		if _row_current_horse[row_i] != horse_idx:
			_row_current_horse[row_i] = horse_idx
			_animate_row_swap(_rows[row_i])

## A quick slide-in-from-left + fade whenever a row slot's occupant actually
## changes (a new horse took over that running-order rank) — a real
## broadcast leaderboard doesn't just snap new text into place, the row
## itself reads as "just updated." Rows stay laid out by _leaderboard_vbox's
## VBoxContainer (their rank/position never moves, only their content does),
## so this animates the row's own position/opacity around its container-
## assigned spot rather than tweening a reorder.
func _animate_row_swap(row: Control) -> void:
	var rest_x: float = row.position.x
	row.position.x = rest_x - 14.0
	row.modulate.a = 0.25
	var tween: Tween = row.create_tween()
	tween.set_parallel(true)
	tween.tween_property(row, "position:x", rest_x, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(row, "modulate:a", 1.0, 0.2)

func _update_banner(delta: float) -> void:
	_banner_elapsed += delta
	var fade_in_end: float = START_BANNER_FADE
	var hold_end: float = fade_in_end + START_BANNER_HOLD
	var fade_out_end: float = hold_end + START_BANNER_FADE

	if _banner_elapsed < fade_in_end:
		_banner.modulate.a = _banner_elapsed / START_BANNER_FADE
	elif _banner_elapsed < hold_end:
		_banner.modulate.a = 1.0
	elif _banner_elapsed < fade_out_end:
		_banner.modulate.a = 1.0 - (_banner_elapsed - hold_end) / START_BANNER_FADE
	else:
		_banner.modulate.a = 0.0

func _update_commentary(delta: float) -> void:
	if not _commentary_active:
		return
	_commentary_elapsed += delta
	var fade_in_end: float = COMMENTARY_FADE
	var hold_end: float = fade_in_end + COMMENTARY_HOLD
	var fade_out_end: float = hold_end + COMMENTARY_FADE

	if _commentary_elapsed < fade_in_end:
		_commentary_label.modulate.a = _commentary_elapsed / COMMENTARY_FADE
	elif _commentary_elapsed < hold_end:
		_commentary_label.modulate.a = 1.0
	elif _commentary_elapsed < fade_out_end:
		_commentary_label.modulate.a = 1.0 - (_commentary_elapsed - hold_end) / COMMENTARY_FADE
	else:
		_commentary_label.modulate.a = 0.0
		_commentary_active = false

const MINIMAP_TRACK_SAMPLES: int = 48

## Was a plain hardcoded ellipse with only the leader plotted on it — didn't
## match the real track's stadium shape (two straights + two turns) or
## necessarily its winding direction, since it never actually sampled the
## real track geometry at all. Now samples RaceTrack3D.sample_shape (the same
## stadium math the actual 3D track/camera/horses use) at minimap scale, so
## the drawn oval really is the track's shape and every horse's dot moves the
## same direction around it that the horses do on-screen.
func _on_draw_minimap() -> void:
	var size: Vector2 = _minimap.size
	var center: Vector2 = size * 0.5
	var half_extent_x: float = _straight_len * 0.5 + _inner_radius
	var half_extent_y: float = _inner_radius
	var fit: float = min(size.x / (2.0 * half_extent_x), size.y / (2.0 * half_extent_y)) * 0.86

	var points := PackedVector2Array()
	for i in range(MINIMAP_TRACK_SAMPLES + 1):
		var f: float = float(i) / float(MINIMAP_TRACK_SAMPLES)
		points.append(center + RaceTrack3D.sample_shape(f, _straight_len, _inner_radius) * fit)
	_minimap.draw_polyline(points, Color(1.0, 1.0, 1.0, 0.5), 2.0)

	# Every horse plotted in its own silk color (not just the leader) — the
	# data was already available every frame via _all_fractions, this just
	# hadn't been drawn before.
	for i in range(min(_all_fractions.size(), field.size())):
		var dot: Vector2 = center + RaceTrack3D.sample_shape(_all_fractions[i], _straight_len, _inner_radius) * fit
		_minimap.draw_circle(dot, 3.0, field[i].silk_primary)

	var leader_point: Vector2 = center + RaceTrack3D.sample_shape(_leader_fraction, _straight_len, _inner_radius) * fit
	_minimap.draw_arc(leader_point, 5.5, 0.0, TAU, 16, UITheme.COLOR_GOLD, 2.0)

func _format_clock(seconds: float) -> String:
	var whole: int = int(seconds)
	var minutes: int = whole / 60
	var secs: int = whole % 60
	var tenths: int = int((seconds - whole) * 10.0)
	return "%d:%02d.%d" % [minutes, secs, tenths]
