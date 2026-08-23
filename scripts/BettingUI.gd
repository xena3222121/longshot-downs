class_name BettingUI
extends Control

## Bet UI for one field: pick a horse (radio-style toggle buttons), pick a
## bet type (Win/Place/Show/Exacta/Quinella/Trifecta/Superfecta/Daily
## Double), choose a stake from 7 fixed levels bounded by the current
## Bankroll balance, confirm. Knows nothing about race simulation or payout
## resolution — Main.gd owns that, this just reports the player's choice via
## bet_placed.
##
## `picks` is a generalized ordered N-slot selection (see
## OddsTable.picks_required) shared by every ordered/unordered multi-pick bet
## type: 1 slot for Win/Place/Show/Daily-Double's race-1 leg, 2 for
## Exacta/Quinella, 3 for Trifecta, 4 for Superfecta. Order matters for the
## picks themselves (1st click = picks[0], etc.) even for Quinella, which
## resolves order-independently — the UI still shows "your picks" in click
## order, only OddsTable.is_winning_quinella ignores it.
##
## Daily Double needs a second race's field, which isn't known yet when this
## scene is built — selecting it emits daily_double_second_race_needed, and
## Main.gd calls provide_second_race() once it has drawn one, at which point
## a second horse list appears for the race-2 pick (second_selected_index,
## kept separate from `picks` since it's a different field entirely, not
## another ordinal slot in this one).

signal bet_placed(picks: Array[int], amount: int, bet_type: OddsTable.BetType)
signal daily_double_second_race_needed

const BET_LEVELS: Array[int] = [100, 1000, 5000, 10000, 25000, 50000, 100000, 1000000]

var field: Array[Horse] = []
var tiers: Array[Dictionary] = []
var picks: Array[int] = []
var second_selected_index: int = -1
var bet_type: OddsTable.BetType = OddsTable.BetType.WIN

var second_field: Array[Horse] = []
var second_tiers: Array[Dictionary] = []
var second_race_requested: bool = false

var horse_buttons: Array[Button] = []
var second_horse_buttons: Array[Button] = []
var bet_type_option: OptionButton
var amount_option: OptionButton
var race_button: Button
var balance_label: Label
var status_label: Label

var vbox: VBoxContainer
var second_race_box: VBoxContainer

## Odds keep drifting live in RaceScheduler._drift_odds while this screen
## sits open waiting for post time, but _refresh_horse_labels was previously
## only ever called from _build()/_on_horse_selected — meaning a player just
## watching the board would never actually see a number move until they
## clicked something. Polling on a short interval (not every frame — these
## are just label redraws, no need to touch them 60x/sec) makes the "live
## betting public" odds drift actually visible while waiting to bet.
const ODDS_REFRESH_INTERVAL: float = 1.0
var _odds_refresh_timer: float = 0.0

func _process(delta: float) -> void:
	if tiers.is_empty() or not is_visible_in_tree():
		return
	_odds_refresh_timer += delta
	if _odds_refresh_timer < ODDS_REFRESH_INTERVAL:
		return
	_odds_refresh_timer = 0.0
	_refresh_horse_labels()
	if bet_type == OddsTable.BetType.DAILY_DOUBLE and not second_tiers.is_empty():
		_refresh_second_horse_labels()

func setup(p_field: Array[Horse], p_tiers: Array[Dictionary]) -> void:
	field = p_field
	tiers = p_tiers
	picks = []
	second_selected_index = -1
	bet_type = OddsTable.BetType.WIN
	second_field = []
	second_tiers = []
	second_race_requested = false
	_build()

## Called by Main.gd once it has drawn a second race's field, in response to
## daily_double_second_race_needed. That signal is emitted from inside
## _build_second_race_picker(), itself called from _build() — rebuilding
## immediately here would re-enter _build() while the original call is
## still on the stack, leaving two overlapping control trees behind (the
## shared `vbox`/`amount_option`/etc. fields would get reassigned mid-call,
## so the outer call's remaining statements silently keep operating on the
## new inner instances instead of the ones it started with). Deferring
## breaks that reentrancy: the original _build() finishes cleanly first
## (showing the "drawing race 2 field..." placeholder), then this runs
## fresh on the next idle frame.
func provide_second_race(p_field: Array[Horse], p_tiers: Array[Dictionary]) -> void:
	second_field = p_field
	second_tiers = p_tiers
	call_deferred("_build")

func _build() -> void:
	for child in get_children():
		child.queue_free()
	horse_buttons.clear()
	second_horse_buttons.clear()

	var panel: PanelContainer = UITheme.make_glass_panel_container()
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 22)
	panel.add_child(margin)

	vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	balance_label = Label.new()
	balance_label.theme_type_variation = "HeadingLabel"
	balance_label.add_theme_font_size_override("font_size", 24)
	var balance_chip := PanelContainer.new()
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = UITheme.COLOR_PANEL_LIGHT
	chip_style.border_color = UITheme.COLOR_GOLD
	chip_style.set_border_width_all(2)
	chip_style.set_corner_radius_all(8)
	chip_style.content_margin_left = 16.0
	chip_style.content_margin_right = 16.0
	chip_style.content_margin_top = 6.0
	chip_style.content_margin_bottom = 6.0
	balance_chip.add_theme_stylebox_override("panel", chip_style)
	balance_chip.add_child(balance_label)
	balance_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(balance_chip)
	_update_balance_label()
	if not Bankroll.balance_changed.is_connected(_on_balance_changed):
		Bankroll.balance_changed.connect(_on_balance_changed)

	var type_row := HBoxContainer.new()
	vbox.add_child(type_row)

	var type_label := Label.new()
	type_label.text = "Bet type:"
	type_row.add_child(type_label)

	bet_type_option = OptionButton.new()
	for bt in [
		OddsTable.BetType.WIN, OddsTable.BetType.PLACE, OddsTable.BetType.SHOW,
		OddsTable.BetType.EXACTA, OddsTable.BetType.QUINELLA, OddsTable.BetType.TRIFECTA, OddsTable.BetType.SUPERFECTA,
		OddsTable.BetType.DAILY_DOUBLE,
	]:
		bet_type_option.add_item(OddsTable.bet_type_label(bt), bt)
	bet_type_option.select(bet_type_option.get_item_index(bet_type))
	bet_type_option.item_selected.connect(_on_bet_type_selected)
	type_row.add_child(bet_type_option)

	var title := Label.new()
	title.text = _picker_title()
	vbox.add_child(title)

	for i in range(field.size()):
		var horse: Horse = field[i]
		var row := HBoxContainer.new()
		vbox.add_child(row)
		row.add_child(_make_color_swatch(horse.silk_primary))

		var btn := Button.new()
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_color", horse.silk_primary)
		btn.pressed.connect(_on_horse_selected.bind(i))
		row.add_child(btn)
		UITheme.add_button_juice(btn)
		horse_buttons.append(btn)

	if bet_type == OddsTable.BetType.DAILY_DOUBLE:
		second_race_box = VBoxContainer.new()
		vbox.add_child(second_race_box)
		_build_second_race_picker()

	_refresh_horse_labels()
	if not horse_buttons.is_empty() and is_inside_tree():
		horse_buttons[0].grab_focus.call_deferred() # lets a gamepad/keyboard player start navigating with no mouse

	var amount_row := HBoxContainer.new()
	vbox.add_child(amount_row)

	var amount_label := Label.new()
	amount_label.text = "Bet amount:"
	amount_row.add_child(amount_label)

	amount_option = OptionButton.new()
	for level in BET_LEVELS:
		amount_option.add_item(OddsTable.format_money(level))
	# "All In" isn't a fixed level — its amount is whatever Bankroll.balance
	# actually is at bet time, so it's appended as one extra item after the
	# fixed BET_LEVELS rather than living in that array. Always lands at
	# index BET_LEVELS.size() (one past the last fixed level) since it's
	# added right after that loop, every time this screen is built.
	amount_option.add_item("All In (%s)" % OddsTable.format_money(Bankroll.balance))
	amount_option.select(0)
	amount_row.add_child(amount_option)

	race_button = Button.new()
	race_button.text = "PLACE BET & RACE!"
	race_button.theme_type_variation = "PrimaryButton"
	race_button.custom_minimum_size = Vector2(0.0, 56.0)
	race_button.pressed.connect(_on_race_pressed)
	vbox.add_child(race_button)
	UITheme.add_button_juice(race_button)

	status_label = Label.new()
	vbox.add_child(status_label)

## Ordinal names for the multi-pick bet types' click-order slots (1st slot =
## "the winner" you're calling, 2nd = "2nd place", etc.) — reused by both the
## picker title and _refresh_horse_labels' per-slot prefix.
const SLOT_ORDINALS: Array[String] = ["1st", "2nd", "3rd", "4th"]

func _picker_title() -> String:
	if bet_type == OddsTable.BetType.DAILY_DOUBLE:
		return "Race 1 — pick the winner:"
	var needed: int = OddsTable.picks_required(bet_type)
	if needed == 1:
		return "Pick a horse to bet on:"
	return "Pick %d horses, in order (%s):" % [needed, ", ".join(SLOT_ORDINALS.slice(0, needed))]

func _build_second_race_picker() -> void:
	for child in second_race_box.get_children():
		child.queue_free()
	second_horse_buttons.clear()

	if second_field.is_empty():
		if not second_race_requested:
			second_race_requested = true
			daily_double_second_race_needed.emit()
		var waiting := Label.new()
		waiting.text = "Drawing race 2 field..."
		second_race_box.add_child(waiting)
		return

	var title := Label.new()
	title.text = "Race 2 — pick the winner:"
	second_race_box.add_child(title)

	for i in range(second_field.size()):
		var horse: Horse = second_field[i]
		var row := HBoxContainer.new()
		second_race_box.add_child(row)
		row.add_child(_make_color_swatch(horse.silk_primary))

		var btn := Button.new()
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_color_override("font_color", horse.silk_primary)
		btn.pressed.connect(_on_second_horse_selected.bind(i))
		row.add_child(btn)
		UITheme.add_button_juice(btn)
		second_horse_buttons.append(btn)
	_refresh_second_horse_labels()

## A small bordered swatch of a horse's own silk color, next to its bet
## button — the button's font_color tint alone was too subtle to read as
## "this is your horse's color" at a glance; this makes it the obvious,
## unambiguous color reference so it can be matched against the coat color
## on the actual horse (see HorseMarker3D._tint_coat) once the race starts.
func _make_color_swatch(color: Color) -> Panel:
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(32.0, 32.0)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = UITheme.COLOR_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	swatch.add_theme_stylebox_override("panel", style)
	return swatch

func _refresh_horse_labels() -> void:
	var needed: int = OddsTable.picks_required(bet_type)
	for i in range(field.size()):
		var horse: Horse = field[i]
		var tier: Dictionary = tiers[i]
		var mult: float = OddsTable.decimal_multiplier(tier, OddsTable.BetType.WIN)
		var prefix: String = ""
		var slot: int = picks.find(i)
		if slot != -1:
			prefix = "✓ " if needed == 1 else "[%s] " % SLOT_ORDINALS[slot]
		var record: String = Career.get_horse_record_label(horse.id)
		horse_buttons[i].text = "%s%s %s— %s (%.2fx win)" % [prefix, horse.horse_name, record, tier.label, mult]
		horse_buttons[i].button_pressed = slot != -1

func _refresh_second_horse_labels() -> void:
	for i in range(second_field.size()):
		var horse: Horse = second_field[i]
		var tier: Dictionary = second_tiers[i]
		var mult: float = OddsTable.decimal_multiplier(tier, OddsTable.BetType.WIN)
		var prefix: String = "✓ " if i == second_selected_index else ""
		second_horse_buttons[i].text = "%s%s — %s (%.2fx win)" % [prefix, horse.horse_name, tier.label, mult]
		second_horse_buttons[i].button_pressed = (i == second_selected_index)

func _on_bet_type_selected(index: int) -> void:
	bet_type = bet_type_option.get_item_id(index) as OddsTable.BetType
	picks = []
	second_selected_index = -1
	_build()

## Generalizes the old Exacta-only 2-slot toggle to any pick count (see
## OddsTable.picks_required): clicking an already-picked horse un-picks it;
## clicking a new horse fills the next open slot; once every slot is full, a
## new click overwrites the LAST slot only — earlier picks stay sticky rather
## than the whole selection shifting, matching the original Exacta behavior
## generalized to N slots.
func _on_horse_selected(index: int) -> void:
	var needed: int = OddsTable.picks_required(bet_type)
	if picks.has(index):
		picks.erase(index)
	elif picks.size() < needed:
		picks.append(index)
	else:
		picks[picks.size() - 1] = index
	_refresh_horse_labels()
	AudioManager.play_sfx("bet_click")

func _on_second_horse_selected(index: int) -> void:
	second_selected_index = index
	_refresh_second_horse_labels()
	AudioManager.play_sfx("bet_click")

func _on_race_pressed() -> void:
	var needed: int = OddsTable.picks_required(bet_type)
	if picks.size() < needed:
		status_label.text = "Pick %d horse%s first." % [needed, "" if needed == 1 else "s"]
		return
	if bet_type == OddsTable.BetType.DAILY_DOUBLE and (second_field.is_empty() or second_selected_index < 0):
		status_label.text = "Pick a winner for race 2 too."
		return

	var amount: int = Bankroll.balance if amount_option.selected == BET_LEVELS.size() else BET_LEVELS[amount_option.selected]
	if not Bankroll.can_afford(amount):
		status_label.text = "You don't have enough to bet that much."
		return
	var final_picks: Array[int] = picks.duplicate()
	if bet_type == OddsTable.BetType.DAILY_DOUBLE:
		final_picks.append(second_selected_index) # race-2 winner tacked on as picks[1], alongside race-1's picks[0]
	bet_placed.emit(final_picks, amount, bet_type)

func lock() -> void:
	for btn in horse_buttons:
		btn.disabled = true
	for btn in second_horse_buttons:
		btn.disabled = true
	bet_type_option.disabled = true
	amount_option.disabled = true
	race_button.disabled = true

func _update_balance_label() -> void:
	balance_label.text = "Bankroll: %s" % OddsTable.format_money(Bankroll.balance)

func _on_balance_changed(new_balance: int) -> void:
	_update_balance_label()
	if amount_option != null: # balance can change (e.g. Bankroll.ensure_minimum) while this screen is still up
		amount_option.set_item_text(BET_LEVELS.size(), "All In (%s)" % OddsTable.format_money(new_balance))
