extends Control

## The post-TitleScreen hub — a persistent "simulcast parlor" screen: a
## sidebar lists every RaceScheduler venue with its own live post-time
## countdown, and RaceScheduler.SCREEN_COUNT fixed tiles on the right each
## render whichever venue is assigned to them via its own SubViewport — real
## simultaneous multi-race viewing, not just switching which one you look at.
## Betting happens in a popup dialog (not a full-screen takeover) so it never
## blocks the live tiles rendering underneath.
##
## Watching a venue does NOT require a bet — RaceScheduler hands off to the
## full visual flow (RaceTrack3D/BroadcastHUD/replay/FinishPodium) for any
## venue assigned to a screen when its post time hits, bet or no bet (see
## FinishPodium._build_watch_only_continue for the no-bet case). The podium
## reveal is a brief FULL-SCREEN moment on top of everything else ONLY when
## it's the sole screen racing — FinishPodium's layout uses fixed pixel
## coordinates sized for the whole window, so it never needed touching at
## all. If ANOTHER screen is still mid-race when this one finishes, a
## compact in-tile result (_show_compact_result) is used instead, so the
## full podium never blanks out a race that's still actually running.

const BET_LEVELS: Array[int] = [100, 1000, 5000, 10000, 25000, 50000, 100000, 1000000]
const SIMPLE_BET_TYPES: Array[OddsTable.BetType] = [OddsTable.BetType.WIN, OddsTable.BetType.PLACE, OddsTable.BetType.SHOW]
const TOAST_HOLD: float = 3.0
const TOAST_FADE: float = 0.4

var _row_countdown_labels: Dictionary = {} # venue_id -> Label
var _row_screen_buttons: Dictionary = {} # venue_id -> Array[Button], one per screen
var _row_bet_chips: Dictionary = {} # venue_id -> Label

var _screen_viewports: Dictionary = {} # screen (int) -> SubViewport
var _screen_overlays: Dictionary = {} # screen -> Control (shown when that screen isn't actively racing)
var _screen_overlay_labels: Dictionary = {} # screen -> Label
var _screen_continue_buttons: Dictionary = {} # screen -> Button, only visible while _screen_pending_result has that screen
var _screen_pending_result: Dictionary = {} # screen -> result description String, set by _show_compact_result until its Continue button is pressed
var _active_race_tracks: Dictionary = {} # screen -> RaceTrack3D
var _screen_audio_buttons: Dictionary = {} # screen -> Button
var _audio_focus_screen: int = 0 # exactly one screen's audio is ever live at once — see RaceTrack3D.has_audio_focus

var _active_bet_dialog: AcceptDialog # tracked so _show_busted_dialog can close it first — see that function's own comment for the real crash this fixes
var _balance_label: Label
var _toast_label: Label
var _toast_elapsed: float = 0.0
var _toast_active: bool = false

var _screens_grid: GridContainer
var _screen_tile_wrappers: Dictionary = {} # screen -> the tile's wrapper Control, for show/hide when the display-count layout changes
var _display_count_buttons: Dictionary = {} # count (1/2/SCREEN_COUNT) -> its picker Button
var _display_title_label: Label
var _display_count: int = 4 # how many screen tiles are currently shown — see Settings.screen_display_count / _set_display_count

func _ready() -> void:
	ScreenFade.fade_in() # arriving here from TitleScreen's own fade_out
	AudioManager.play_music("theme")
	RaceScheduler.race_ready.connect(_on_race_ready)
	RaceScheduler.background_result.connect(_on_background_result)
	RaceScheduler.screen_assignment_changed.connect(_on_screen_assignment_changed)
	Bankroll.balance_changed.connect(_on_balance_changed)
	Bankroll.went_broke.connect(_show_busted_dialog)
	_display_count = clamp(Settings.screen_display_count, 1, RaceScheduler.SCREEN_COUNT)
	_build_layout()
	_apply_display_count() # sync tile visibility/grid columns/picker state to the loaded preference — _build_layout() itself always builds all SCREEN_COUNT tiles/buttons
	RaceScheduler.begin_watching() # only starts/resumes ticking once something is actually here to receive race_ready — see its own comment for why

func _process(_delta: float) -> void:
	_refresh_sidebar()
	_refresh_screens()
	_refresh_audio_buttons()
	_update_toast(_delta)

## Radio-style picker: switching focus immediately mutes the old screen's
## ambience/announcer and unmutes the new one (see RaceTrack3D.set_audio_focus)
## rather than waiting for either race to end — a live toggle, not a
## next-race setting.
func _set_audio_focus(screen: int) -> void:
	if screen == _audio_focus_screen:
		return
	var old_track: RaceTrack3D = _active_race_tracks.get(_audio_focus_screen)
	if old_track != null:
		old_track.set_audio_focus(false)
	_audio_focus_screen = screen
	var new_track: RaceTrack3D = _active_race_tracks.get(screen)
	if new_track != null:
		new_track.set_audio_focus(true)
	AudioManager.play_sfx("bet_click")

func _refresh_audio_buttons() -> void:
	for screen in range(RaceScheduler.SCREEN_COUNT):
		var btn: Button = _screen_audio_buttons[screen]
		btn.text = "🔊" if screen == _audio_focus_screen else "🔇"

const SCREEN_GRID_COLUMNS: int = 2 # 4 screens -> 2x2 grid, not one cramped row

func _build_layout() -> void:
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	root.add_child(_build_sidebar())

	_screens_grid = GridContainer.new()
	_screens_grid.columns = SCREEN_GRID_COLUMNS
	_screens_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screens_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_screens_grid.add_theme_constant_override("h_separation", 6)
	_screens_grid.add_theme_constant_override("v_separation", 6)
	root.add_child(_screens_grid)
	for screen in range(RaceScheduler.SCREEN_COUNT):
		var tile: Control = _build_screen_tile(screen)
		_screen_tile_wrappers[screen] = tile
		_screens_grid.add_child(tile)

	_build_toast()

## Condensed on purpose — all 14 venues need to fit without a scrollbar or
## eating into the screens area, which is the actual point of this whole
## layout (more room for the grid means smaller tiles, not a wider sidebar).
func _build_sidebar() -> Control:
	var panel: PanelContainer = UITheme.make_glass_panel_container()
	panel.custom_minimum_size = Vector2(250.0, 0.0)

	# No extra MarginContainer here -- PanelContainer's own themed "panel"
	# stylebox already applies real content margins (18px/10px), so wrapping
	# another margin around it just doubles the padding for no visual gain.
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	_balance_label = Label.new()
	_balance_label.theme_type_variation = "HeadingLabel"
	_balance_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_balance_label)
	_update_balance_label()

	_display_title_label = Label.new()
	_display_title_label.theme_type_variation = "EyebrowLabel"
	_display_title_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(_display_title_label)

	_build_display_count_picker(vbox)

	# ScrollContainer stays as a safety net if the window is ever resized
	# smaller than the design resolution -- but at the normal window size the
	# condensed row height below means all 14 venues fit without it ever
	# actually needing to scroll.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 2)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows_box)

	for venue_id in Venues.VENUE_IDS:
		rows_box.add_child(_build_venue_row(venue_id))

	var exit_btn := Button.new()
	exit_btn.text = "Title Screen"
	exit_btn.theme_type_variation = "MaroonButton"
	exit_btn.add_theme_font_size_override("font_size", 14)
	exit_btn.pressed.connect(func():
		await ScreenFade.fade_out()
		get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
	)
	vbox.add_child(exit_btn)
	UITheme.add_button_juice(exit_btn)

	return panel

## "1 / 2 / 4" viewing-layout picker — AJ: "make it so you can toggle 1
## screen 2 screens or 4 screens, if you want to watch one screen you should
## be able to [go] huge." Screen 0 is always the one shown in 1-screen mode
## (it's already the flagship default per screen_venue_ids' own init in
## RaceScheduler.gd), and GridContainer skips invisible children entirely
## when laying itself out (documented Godot Container behavior) — so hiding
## the other tiles and dropping to 1 column is enough to make the remaining
## tile expand to fill the whole screens area on its own; no separate
## "big mode" layout branch is needed.
func _build_display_count_picker(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var label := Label.new()
	label.text = "View:"
	label.add_theme_font_size_override("font_size", 10)
	row.add_child(label)

	for count in [1, 2, RaceScheduler.SCREEN_COUNT]:
		var btn := Button.new()
		btn.text = "%d screen%s" % [count, "" if count == 1 else "s"]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0.0, 18.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 9)
		btn.pressed.connect(_set_display_count.bind(count))
		_apply_tight_button_style(btn, 2.0, 1.0)
		row.add_child(btn)
		_display_count_buttons[count] = btn

## Toggling down (e.g. 4 -> 1) hides screens n..SCREEN_COUNT-1 and clears any
## venue assignment on them — refused (with a toast, same pattern as
## _on_background_result's notifications) if any of those screens is
## currently mid-race, the same "can't yank a screen out from under a live
## race" rule set_screen_venue already enforces for a single reassignment —
## otherwise a race the player is mid-watching on screen 3 would just vanish
## the instant they clicked "1 screen."
func _set_display_count(n: int) -> void:
	if n == _display_count:
		return
	for screen in range(n, RaceScheduler.SCREEN_COUNT):
		var venue_id: String = RaceScheduler.screen_venue_ids[screen]
		if venue_id != "" and RaceScheduler.is_racing(venue_id):
			_show_toast("Screen %d is still racing — wait for it to finish before switching to %d screen%s." % [screen + 1, n, "" if n == 1 else "s"])
			return

	for screen in range(n, RaceScheduler.SCREEN_COUNT):
		if RaceScheduler.screen_venue_ids[screen] != "":
			RaceScheduler.set_screen_venue(screen, "")

	_display_count = n
	Settings.set_screen_display_count(n)
	_apply_display_count()
	AudioManager.play_sfx("bet_click")

## Syncs the grid/tiles/sidebar-buttons/picker-state to _display_count —
## called once after _build_layout() (to apply a loaded preference to the
## always-fully-built tile set) and again every time _set_display_count runs.
func _apply_display_count() -> void:
	_screens_grid.columns = 1 if _display_count == 1 else SCREEN_GRID_COLUMNS
	for screen in range(RaceScheduler.SCREEN_COUNT):
		var wrapper: Control = _screen_tile_wrappers.get(screen)
		if wrapper != null:
			wrapper.visible = screen < _display_count

	for venue_id in Venues.VENUE_IDS:
		var buttons: Array = _row_screen_buttons.get(venue_id, [])
		for screen in range(buttons.size()):
			buttons[screen].visible = screen < _display_count

	if _display_title_label != null:
		_display_title_label.text = "SIMULCAST — %d SCREEN%s" % [_display_count, "" if _display_count == 1 else "S"]

	for count in _display_count_buttons.keys():
		_display_count_buttons[count].button_pressed = (count == _display_count)

## The shared theme's default Button stylebox bakes in 18px/10px content
## margins (same formula as PanelContainer's — see UITheme._panel_style)
## meant for normal-sized buttons elsewhere in the game. That silently
## overrides a small button's custom_minimum_size (the button grows to fit
## text+padding regardless), which is why the tiny screen-digit/Bet buttons
## rendered much taller than requested. Buttons (unlike
## UITheme.make_glass_panel_container's shader-based panels) have no
## material conflict, so overriding their per-state styleboxes directly here
## is safe.
func _apply_tight_button_style(btn: Button, h_margin: float, v_margin: float) -> void:
	var normal := _tight_stylebox(UITheme.COLOR_PANEL, UITheme.COLOR_GOLD, 1, h_margin, v_margin)
	var hover := _tight_stylebox(UITheme.COLOR_PANEL_LIGHT, UITheme.COLOR_GOLD_BRIGHT, 1, h_margin, v_margin)
	var pressed := _tight_stylebox(UITheme.COLOR_PANEL_LIGHT.darkened(0.25), UITheme.COLOR_GOLD, 1, h_margin, v_margin)
	var disabled := _tight_stylebox(UITheme.COLOR_PANEL.darkened(0.4), UITheme.COLOR_GOLD.darkened(0.5), 1, h_margin, v_margin)
	var focus := _tight_stylebox(Color(0.0, 0.0, 0.0, 0.0), UITheme.COLOR_GOLD_BRIGHT, 1, h_margin, v_margin)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", focus)

func _tight_stylebox(fill: Color, border: Color, border_width: int, h_margin: float, v_margin: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = h_margin
	sb.content_margin_right = h_margin
	sb.content_margin_top = v_margin
	sb.content_margin_bottom = v_margin
	return sb

## Two tight lines per venue (name+countdown+bet-chip, then screen digits +
## Bet) instead of three — with 14 venues now (up from the original 10) a
## third line per row was the difference between fitting on one screen and
## needing a scrollbar. Screen buttons are just the digit ("1"/"2"/...), not
## "Screen 1" — with 4 of them plus a Bet button, full-word labels don't fit
## at this width at all.
func _build_venue_row(venue_id: String) -> PanelContainer:
	# Plain flat stylebox, not UITheme.make_glass_panel_container -- that
	# helper's shader material explicitly can't be combined with a custom
	# "panel" stylebox override (see its own doc comment), and its glass-blur
	# look is only worth the theme's default 18px/10px content margins for a
	# single hero panel, not repeated 14 times over in a tight list. A plain
	# StyleBoxFlat gives full control over padding so 14 rows actually fit.
	var row_panel := PanelContainer.new()
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.043, 0.067, 0.106, 0.6)
	row_style.border_color = UITheme.COLOR_GOLD
	row_style.set_border_width_all(1)
	row_style.set_corner_radius_all(6)
	row_style.content_margin_left = 6.0
	row_style.content_margin_right = 6.0
	row_style.content_margin_top = 3.0
	row_style.content_margin_bottom = 3.0
	row_panel.add_theme_stylebox_override("panel", row_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	row_panel.add_child(vbox)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)
	vbox.add_child(top_row)

	var name_label := Label.new()
	name_label.text = Venues.label_for(venue_id)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	top_row.add_child(name_label)

	var bet_chip := Label.new()
	bet_chip.add_theme_font_size_override("font_size", 9)
	bet_chip.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	top_row.add_child(bet_chip)
	_row_bet_chips[venue_id] = bet_chip

	var countdown_label := Label.new()
	countdown_label.add_theme_font_size_override("font_size", 10)
	countdown_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	countdown_label.custom_minimum_size = Vector2(58.0, 0.0)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(countdown_label)
	_row_countdown_labels[venue_id] = countdown_label

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 2)
	vbox.add_child(actions)

	var screen_buttons: Array[Button] = []
	for screen in range(RaceScheduler.SCREEN_COUNT):
		var screen_btn := Button.new()
		screen_btn.text = str(screen + 1)
		screen_btn.custom_minimum_size = Vector2(18.0, 18.0)
		screen_btn.add_theme_font_size_override("font_size", 9)
		screen_btn.toggle_mode = true
		screen_btn.pressed.connect(_on_screen_toggle_pressed.bind(venue_id, screen, screen_btn))
		_apply_tight_button_style(screen_btn, 2.0, 1.0)
		actions.add_child(screen_btn)
		screen_buttons.append(screen_btn)
	_row_screen_buttons[venue_id] = screen_buttons

	var bet_btn := Button.new()
	bet_btn.text = "Bet"
	bet_btn.custom_minimum_size = Vector2(0.0, 18.0)
	bet_btn.add_theme_font_size_override("font_size", 10)
	bet_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bet_btn.pressed.connect(_on_bet_pressed.bind(venue_id))
	_apply_tight_button_style(bet_btn, 4.0, 1.0)
	actions.add_child(bet_btn)

	return row_panel

## Toggling ON assigns this venue to that screen (bumping whatever was there,
## if anything — RaceScheduler.set_screen_venue handles that). Toggling OFF
## clears the screen. Refused (and the button un-pressed again) if that
## screen is currently mid-race.
func _on_screen_toggle_pressed(venue_id: String, screen: int, button: Button) -> void:
	var target_venue: String = venue_id if button.button_pressed else ""
	if not RaceScheduler.set_screen_venue(screen, target_venue):
		button.button_pressed = not button.button_pressed
		AudioManager.play_sfx("bet_click")

func _refresh_sidebar() -> void:
	_update_balance_label()
	for venue_id in Venues.VENUE_IDS:
		var label: Label = _row_countdown_labels[venue_id]
		if RaceScheduler.is_racing(venue_id):
			label.text = "LIVE NOW"
		else:
			label.text = "Post in %s" % _format_countdown(RaceScheduler.get_countdown(venue_id))

		var bet_chip: Label = _row_bet_chips[venue_id]
		bet_chip.text = "BET IN" if RaceScheduler.has_bet(venue_id) else ""

		var screen_buttons: Array = _row_screen_buttons[venue_id]
		for screen in range(screen_buttons.size()):
			var btn: Button = screen_buttons[screen]
			var assigned: bool = RaceScheduler.screen_venue_ids[screen] == venue_id
			if btn.button_pressed != assigned:
				btn.button_pressed = assigned
			btn.disabled = RaceScheduler.is_racing(venue_id) and assigned

func _format_countdown(seconds: float) -> String:
	var whole: int = int(ceil(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]

func _build_screen_tile(screen: int) -> Control:
	var wrapper := Control.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.custom_minimum_size = Vector2(400.0, 300.0)

	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.add_child(viewport_container)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 500) # overwritten immediately once laid out — stretch=true keeps it matched to the container's actual size
	# Without this, every screen's SubViewport shares ONE World3D by default —
	# all 4 screens' RaceTrack3D instances (track geometry, horses, lights,
	# sky) would literally coexist at the same coordinates in a single shared
	# 3D space instead of 4 independent scenes, which is exactly the
	# "overlapping/same universe" look. own_world_3d gives each screen its own
	# fully isolated 3D world.
	viewport.own_world_3d = true
	viewport_container.add_child(viewport)
	_screen_viewports[screen] = viewport

	# STOP (not IGNORE) — while visible, nothing underneath (an idle black
	# SubViewport, or a race that's actually still hidden mid-swap) is worth
	# clicking through to, and the Continue button below needs to actually
	# receive input. Irrelevant while overlay.visible is false: an invisible
	# Control never receives input regardless of filter.
	var overlay: PanelContainer = UITheme.make_glass_panel_container(10.0, Color(UITheme.COLOR_BG, 0.75))
	overlay.set_anchors_preset(Control.PRESET_CENTER)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	wrapper.add_child(overlay)
	_screen_overlays[screen] = overlay

	var overlay_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		overlay_margin.add_theme_constant_override("margin_%s" % side, 18)
	overlay.add_child(overlay_margin)

	var overlay_box := VBoxContainer.new()
	overlay_box.add_theme_constant_override("separation", 10)
	overlay_margin.add_child(overlay_box)

	# With up to SCREEN_COUNT races potentially live at once, only ONE screen's
	# announcer/ambience/gate SFX should ever actually play (see
	# RaceTrack3D.has_audio_focus) — this button is the player's radio-style
	# picker for which one. Always on top of the live footage (not gated by
	# the overlay, which only shows when idle) so it can be switched mid-race.
	var audio_btn := Button.new()
	audio_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	audio_btn.offset_left = -48.0
	audio_btn.offset_top = 8.0
	audio_btn.offset_right = -8.0
	audio_btn.offset_bottom = 48.0
	audio_btn.add_theme_font_size_override("font_size", 18)
	audio_btn.pressed.connect(_set_audio_focus.bind(screen))
	wrapper.add_child(audio_btn)
	_screen_audio_buttons[screen] = audio_btn

	var overlay_label := Label.new()
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.add_theme_font_size_override("font_size", 18)
	overlay_box.add_child(overlay_label)
	_screen_overlay_labels[screen] = overlay_label

	var continue_btn := Button.new()
	continue_btn.text = "CONTINUE"
	continue_btn.theme_type_variation = "PrimaryButton"
	continue_btn.custom_minimum_size = Vector2(0.0, 44.0)
	continue_btn.visible = false
	continue_btn.pressed.connect(_on_compact_result_continue.bind(screen))
	overlay_box.add_child(continue_btn)
	UITheme.add_button_juice(continue_btn)
	_screen_continue_buttons[screen] = continue_btn

	return wrapper

## Shows a placeholder (venue name + countdown, or "no track assigned", or a
## just-finished result — see _screen_pending_result) over any screen that
## isn't actively rendering a live race — the SubViewport sits empty/black
## otherwise with nothing telling the player what it's waiting for.
func _refresh_screens() -> void:
	for screen in range(RaceScheduler.SCREEN_COUNT):
		var overlay: Control = _screen_overlays[screen]
		var label: Label = _screen_overlay_labels[screen]
		var continue_btn: Button = _screen_continue_buttons[screen]
		if _screen_pending_result.has(screen):
			overlay.visible = true
			continue_btn.visible = true
			label.text = _screen_pending_result[screen]
			continue
		continue_btn.visible = false

		var venue_id: String = RaceScheduler.screen_venue_ids[screen]
		if venue_id == "":
			overlay.visible = true
			label.text = "No track assigned\n\nPick a Screen button\non a track in the list"
		elif RaceScheduler.is_racing(venue_id):
			overlay.visible = false
		else:
			overlay.visible = true
			label.text = "%s\n\nPost in %s" % [Venues.label_for(venue_id).to_upper(), _format_countdown(RaceScheduler.get_countdown(venue_id))]

func _any_other_screen_racing(exclude_screen: int) -> bool:
	for screen in range(RaceScheduler.SCREEN_COUNT):
		if screen == exclude_screen:
			continue
		var venue_id: String = RaceScheduler.screen_venue_ids[screen]
		if venue_id != "" and RaceScheduler.is_racing(venue_id):
			return true
	return false

## Fires for whichever venue/screen combination RaceScheduler decided should
## get the full visual treatment this cycle — see its own class comment for
## exactly when that is (any venue currently assigned to a screen at the
## exact moment its post time hits). Runs the full pre-race ceremony since
## the player was already watching before the gate opened.
func _on_race_ready(venue_id: String, screen: int, result: RaceResult, bet_context: Dictionary) -> void:
	var race_track: RaceTrack3D = _build_race_track(venue_id, screen, result, bet_context)
	if race_track != null:
		race_track.play_with_post_time()

## AJ: "make it start anyways, if im not watching it it still runs and
## remains live until the race is over, if i choose to tune in itll open at
## whatever part of the race its at." A venue can go from unassigned to
## assigned at ANY point, not just at post time — if RaceScheduler reports
## that venue is already mid-race, build the same RaceTrack3D but seek it
## straight to `elapsed` instead of running the pre-race ceremony (see
## RaceTrack3D.join_in_progress). A venue assigned before/at its own post
## time is a no-op here — _on_race_ready above already owns that moment.
func _on_screen_assignment_changed(screen: int, venue_id: String) -> void:
	if venue_id == "":
		return
	var live: Dictionary = RaceScheduler.get_live_race(venue_id)
	if live.is_empty():
		return
	var race_track: RaceTrack3D = _build_race_track(venue_id, screen, live.result, live.bet_context)
	if race_track != null:
		race_track.join_in_progress(live.elapsed)

func _build_race_track(venue_id: String, screen: int, result: RaceResult, bet_context: Dictionary) -> RaceTrack3D:
	var viewport: SubViewport = _screen_viewports.get(screen)
	if viewport == null:
		return null
	var race_track := RaceTrack3D.new()
	viewport.add_child(race_track)
	race_track.setup(RaceScheduler.get_field(venue_id), result, bet_context, venue_id, screen == _audio_focus_screen, RaceScheduler.get_is_turf(venue_id))
	race_track.playback_finished.connect(_on_playback_finished.bind(venue_id, screen, race_track, result, bet_context))
	_active_race_tracks[screen] = race_track
	return race_track

func _on_playback_finished(venue_id: String, screen: int, race_track: RaceTrack3D, result: RaceResult, bet_context: Dictionary) -> void:
	await race_track.play_replay() # TVG-style stretch-run replay before the podium
	race_track.queue_free()
	_active_race_tracks.erase(screen)

	# The full FinishPodium overlay covers the ENTIRE window (by design — see
	# its own dim ColorRect), which would visually blank out any OTHER
	# screen's still-live race underneath it, making that race look like it
	# "insta-finished" even though it was actually still running the whole
	# time. Only show the full cinematic podium when this is the ONLY screen
	# racing right now; otherwise show a compact result inside just THIS
	# screen's own tile so the other one stays visible and unblocked.
	if _any_other_screen_racing(screen):
		_show_compact_result(screen, venue_id, result, bet_context)
		return

	var podium := FinishPodium.new()
	add_child(podium)
	podium.setup(RaceScheduler.get_field(venue_id), result, bet_context)
	podium.race_again_pressed.connect(_on_podium_continue.bind(venue_id, podium))

func _on_podium_continue(venue_id: String, podium: FinishPodium) -> void:
	podium.queue_free()
	RaceScheduler.finish_watched_race(venue_id)

## Cheaper stand-in for FinishPodium when it can't take over the whole screen
## (see _on_playback_finished) — resolves the bet with the same simple WIN/
## PLACE/SHOW math RaceScheduler's own background resolution uses (this
## flow's bet popup only ever offers those three types anyway), shows the
## result inside the screen's own overlay, and waits for its Continue button
## rather than auto-dismissing. Deliberately skips the purse bonus/
## achievement-toast treatment FinishPodium gives a fully-watched race — a
## known, accepted gap between "the one race you're fully focused on" and
## "one of several running at once."
func _show_compact_result(screen: int, venue_id: String, result: RaceResult, bet_context: Dictionary) -> void:
	Career.record_finish(result)
	var winner_name: String = result.field[result.finish_order[0]].horse.horse_name
	var description: String
	if bet_context.is_empty():
		description = "%s\n\nJust watching.\nWinner: %s" % [Venues.label_for(venue_id).to_upper(), winner_name]
	else:
		var horse_index: int = bet_context.horse_index
		var bet_type: OddsTable.BetType = bet_context.bet_type
		var amount: int = bet_context.amount
		var won: bool = OddsTable.is_winning_bet(result.finish_order, horse_index, bet_type)
		var horse_name: String = result.field[horse_index].horse.horse_name
		if won:
			var payout: int = OddsTable.payout(amount, result.field[horse_index].tier, bet_type)
			Bankroll.pay(payout)
			description = "%s\n\nYOU WON %s!\n%s on %s" % [
				Venues.label_for(venue_id).to_upper(), OddsTable.format_money(payout), OddsTable.bet_type_label(bet_type), horse_name,
			]
		else:
			description = "%s\n\nLost your %s %s bet\non %s." % [
				Venues.label_for(venue_id).to_upper(), OddsTable.format_money(amount), OddsTable.bet_type_label(bet_type), horse_name,
			]
	_screen_pending_result[screen] = description

func _on_compact_result_continue(screen: int) -> void:
	var venue_id: String = RaceScheduler.screen_venue_ids[screen]
	_screen_pending_result.erase(screen)
	if venue_id != "":
		RaceScheduler.finish_watched_race(venue_id)

func _on_bet_pressed(venue_id: String) -> void:
	if RaceScheduler.is_racing(venue_id):
		_show_toast("%s has already gone to post — wait for the next race to bet." % Venues.label_for(venue_id))
		return
	var field: Array[Horse] = RaceScheduler.get_field(venue_id)
	var tiers: Array[Dictionary] = RaceScheduler.get_tiers(venue_id)

	var dialog := AcceptDialog.new()
	dialog.title = "Bet — %s" % Venues.label_for(venue_id)
	dialog.ok_button_text = "Close"

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(440.0, 0.0)
	content.add_theme_constant_override("separation", 8)
	dialog.add_child(content)

	# A single-element array so the per-horse button closures below can
	# mutate it — a plain int local wouldn't be visible across separate
	# closures (GDScript captures locals by value, not by reference; a
	# Dictionary/Array's CONTENTS are shared, so mutating one here is).
	var selected := [-1]
	var horse_buttons: Array[Button] = []

	var pick_label := Label.new()
	pick_label.text = "Pick a horse:"
	content.add_child(pick_label)

	for i in range(field.size()):
		var horse: Horse = field[i]
		var tier: Dictionary = tiers[i]
		var row := HBoxContainer.new()
		content.add_child(row)

		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(24.0, 24.0)
		var style := StyleBoxFlat.new()
		style.bg_color = horse.silk_primary
		style.border_color = UITheme.COLOR_GOLD
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		swatch.add_theme_stylebox_override("panel", style)
		row.add_child(swatch)

		var btn := Button.new()
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_color", horse.silk_primary)
		var mult: float = OddsTable.decimal_multiplier(tier, OddsTable.BetType.WIN)
		btn.text = "%s — %s (%.2fx win)" % [horse.horse_name, tier.label, mult]
		btn.pressed.connect(func():
			selected[0] = i
			for b in horse_buttons:
				b.button_pressed = false
			btn.button_pressed = true
			AudioManager.play_sfx("bet_click")
		)
		row.add_child(btn)
		horse_buttons.append(btn)

	var type_row := HBoxContainer.new()
	content.add_child(type_row)
	type_row.add_child(_make_label("Bet type:"))
	var bet_type_option := OptionButton.new()
	for bt in SIMPLE_BET_TYPES:
		bet_type_option.add_item(OddsTable.bet_type_label(bt), bt)
	type_row.add_child(bet_type_option)

	var amount_row := HBoxContainer.new()
	content.add_child(amount_row)
	amount_row.add_child(_make_label("Amount:"))
	var amount_option := OptionButton.new()
	for level in BET_LEVELS:
		amount_option.add_item(OddsTable.format_money(level))
	amount_option.add_item("All In (%s)" % OddsTable.format_money(Bankroll.balance))
	amount_option.select(0)
	amount_row.add_child(amount_option)

	var status_label := Label.new()
	if RaceScheduler.has_bet(venue_id):
		status_label.text = "You already have a bet in on this race — placing a new one replaces it."
	content.add_child(status_label)

	var place_btn := Button.new()
	place_btn.text = "PLACE BET"
	place_btn.theme_type_variation = "PrimaryButton"
	place_btn.custom_minimum_size = Vector2(0.0, 48.0)
	place_btn.pressed.connect(func():
		if selected[0] < 0:
			status_label.text = "Pick a horse first."
			return
		var bet_type: OddsTable.BetType = SIMPLE_BET_TYPES[bet_type_option.selected]
		var amount: int = Bankroll.balance if amount_option.selected == BET_LEVELS.size() else BET_LEVELS[amount_option.selected]
		if not Bankroll.can_afford(amount):
			status_label.text = "You don't have enough to bet that much."
			return
		if not RaceScheduler.place_bet(venue_id, selected[0], bet_type, amount):
			status_label.text = "Couldn't place that bet."
			return
		status_label.text = "Bet placed: %s on %s (%s). Catch the post!" % [
			OddsTable.format_money(amount), field[selected[0]].horse_name, OddsTable.bet_type_label(bet_type),
		]
		AudioManager.play_sfx("bet_click")
	)
	content.add_child(place_btn)
	UITheme.add_button_juice(place_btn)

	add_child(dialog)
	_active_bet_dialog = dialog
	dialog.popup_centered()
	dialog.get_ok_button().grab_focus.call_deferred()
	dialog.confirmed.connect(func():
		_active_bet_dialog = null
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		_active_bet_dialog = null
		dialog.queue_free()
	)

func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _update_balance_label() -> void:
	if _balance_label != null:
		_balance_label.text = "Bankroll: %s" % OddsTable.format_money(Bankroll.balance)

func _on_balance_changed(_new_balance: int) -> void:
	_update_balance_label()

const BUSTED_REFILL_AMOUNT: int = 50000

## AJ: "when the player runs out of bankroll play a sound that sucks and ask
## the player if they want to try again not to suck at betting on horses and
## refills their bankroll back to 50k." Bankroll itself only reports the
## state via went_broke — this owns the actual UI reaction, same separation
## as every other Bankroll signal. Reuses the existing "lose_sting" cue
## (already the game's "you lost" sound) rather than sourcing a new asset —
## it's already exactly the "that sucked" stinger this calls for.
func _show_busted_dialog() -> void:
	AudioManager.play_sfx("lose_sting")

	# Real crash hit and fixed: going broke fires synchronously from inside
	# the bet popup's own "Place Bet" button handler (Bankroll.went_broke ->
	# this, all on the same call stack as RaceScheduler.place_bet), so the
	# bet dialog is still fully open the instant this tried to open a SECOND
	# one — Godot refused ("parent window already has another exclusive
	# child"), confirmed via AJ's actual play session console output.
	# queue_free() alone isn't enough here: it only marks the bet dialog for
	# deletion at the end of THIS frame, but popup_centered() on a new
	# exclusive dialog checks synchronously, in the same call — so the new
	# dialog still has to wait. Deferring the actual build/popup to the next
	# idle frame (queued AFTER the queue_free() below, so it runs after)
	# gives the old dialog time to actually leave the tree first.
	if _active_bet_dialog != null and is_instance_valid(_active_bet_dialog):
		_active_bet_dialog.queue_free()
		_active_bet_dialog = null
	_build_busted_dialog.call_deferred()

func _build_busted_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Busted!"
	dialog.dialog_text = "You're out of money. You kind of suck at betting on horses, ngl.\n\nWant to try again?"
	dialog.ok_button_text = "Try Again"

	add_child(dialog)
	dialog.popup_centered()
	dialog.get_ok_button().grab_focus.call_deferred()
	# Both paths refill — AcceptDialog has no Cancel button, but Escape/the
	# window's own close control still fire `canceled`, and going broke with
	# no way back in would just soft-lock the player (nothing else in the
	# live TrackLobby flow ever refills a mid-session busted balance).
	var refill_and_close := func():
		Bankroll.refill(BUSTED_REFILL_AMOUNT)
		dialog.queue_free()
	dialog.confirmed.connect(refill_and_close)
	dialog.canceled.connect(refill_and_close)

## Small fading toast for whatever happens at a venue with no screen
## assigned — without this there'd be no way to ever know a background bet
## won or lost.
func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)

	_toast_label = Label.new()
	_toast_label.theme_type_variation = "EyebrowLabel"
	_toast_label.add_theme_font_size_override("font_size", 16)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.custom_minimum_size = Vector2(600.0, 30.0)
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.modulate.a = 0.0
	layer.add_child(_toast_label)

	var viewport_width: float = get_viewport().get_visible_rect().size.x
	_toast_label.position = Vector2((viewport_width - 600.0) * 0.5, 26.0)

func _on_background_result(_venue_id: String, description: String, won: bool, payout: int) -> void:
	var outcome: String = "WON %s" % OddsTable.format_money(payout) if won else "lost"
	_show_toast("%s — %s" % [description, outcome])

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
