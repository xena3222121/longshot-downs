extends Control

## Phase 2 of the Career/"owner mode" system — the actual clickable screen
## for CareerStable.gd's Phase 1 data/economy layer. One screen handles the
## whole loop (slot select, starter pick, training, buying a horse, racing)
## rather than a chain of separate scene files, matching TrackLobby's "one
## hub + popups" shape rather than a full scene transition per step —
## appropriate for how small this MVP surface still is. No free-text input
## anywhere (matches this game's existing zero-LineEdit Steam Deck
## compatibility point) — every choice (trainer tier, training focus, which
## sub-attribute to train) opens a plain scrollable list of normal focusable
## Buttons in a popup Window (_open_selector below) rather than an
## OptionButton dropdown, which sidesteps this project's own documented
## OptionButton-popup-vs-gamepad bugs entirely. AJ, later: tap-to-cycle
## buttons for trainer/focus "seemed really unintuitive... make it a screen
## or selectable, like a dropdown" — _open_selector is that screen.

const RIVAL_COUNT: int = 7

var _content: VBoxContainer
var _marketplace_open: bool = false
var _balance_label: Label
## Everything state-specific (slot picker / starter pick / hub / a live race
## / the race result) lives under this one swappable container. AJ: got
## trapped in the menu with no way back to the title screen and had to
## force-close — root cause was _start_race/_show_race_result each doing
## `for child in get_children(): child.queue_free()` on the WHOLE screen,
## wiping out the back button along with everything else, so once a race
## started (or finished) there was no escape short of the "Continue" button
## eventually appearing. The back button/balance label/vignette below are
## now built ONCE in _ready() as permanent chrome that's never torn down;
## every view-building function only clears/replaces _view_root's children.
var _view_root: Control

func _ready() -> void:
	ScreenFade.fade_in()

	add_child(UITheme.make_vignette_overlay())

	var back_btn := Button.new()
	back_btn.text = "< Back to Title"
	back_btn.theme_type_variation = "QuietButton"
	back_btn.custom_minimum_size = Vector2(180.0, 40.0)
	back_btn.position = Vector2(24.0, 24.0)
	back_btn.pressed.connect(_on_back_pressed)
	add_child(back_btn)
	UITheme.add_button_juice(back_btn)

	_balance_label = Label.new()
	_balance_label.theme_type_variation = "EyebrowLabel"
	_balance_label.position = Vector2(24.0, 70.0)
	_refresh_balance_label()
	add_child(_balance_label)

	_view_root = Control.new()
	_view_root.anchor_right = 1.0
	_view_root.anchor_bottom = 1.0
	_view_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_view_root)

	_build()

func _clear_view() -> void:
	for child in _view_root.get_children():
		child.queue_free()

func _build() -> void:
	_clear_view()

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	_view_root.add_child(center)

	var panel: PanelContainer = UITheme.make_glass_panel_container()
	panel.custom_minimum_size = Vector2(860.0, 600.0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 28)
	panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800.0, 540.0)
	margin.add_child(scroll)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	if CareerStable.current_slot == -1:
		_build_slot_picker()
	elif not CareerStable.has_picked_starter():
		_build_starter_pick()
	else:
		_build_hub()

func _refresh_balance_label() -> void:
	if _balance_label != null:
		_balance_label.text = "Balance: %s" % OddsTable.format_money(Bankroll.balance)

## Always reachable now, including mid-race (see _view_root's own comment) —
## safety-cleans any in-progress race's ducked/looping audio first, same
## "cleanup regardless of how the scene got abandoned" belt-and-suspenders
## philosophy InputHints._try_return_to_title already uses for TrackLobby.
func _on_back_pressed() -> void:
	AudioManager.stop_race_ambience()
	await ScreenFade.fade_out()
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")

func _add_heading(text: String) -> void:
	var heading := Label.new()
	heading.theme_type_variation = "HeadingLabel"
	heading.add_theme_font_size_override("font_size", 28)
	heading.text = text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(heading)

func _add_body_text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(label)
	return label

## ---- Slot picker (multiple independent careers) ----
##
## AJ: every stable he'd ever started was piling up in one shared save,
## reading as "all just commingled in one cluster" — this screen is the
## fix: SLOT_COUNT independent careers, each with its own stable, picked
## explicitly before anything else loads (see CareerStable.current_slot).

func _build_slot_picker() -> void:
	_add_heading("Select a Career")
	_add_body_text("Each career keeps its own stable, completely separate from the others.")
	for slot in range(CareerStable.SLOT_COUNT):
		_content.add_child(_build_slot_card(slot))

func _build_slot_card(slot: int) -> Control:
	var summary: Dictionary = CareerStable.peek_slot_summary(slot)
	var card: PanelContainer = UITheme.make_glass_panel_container()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var title := Label.new()
	title.theme_type_variation = "EyebrowLabel"
	title.text = "Career %d" % (slot + 1)
	col.add_child(title)

	var button_row := HFlowContainer.new()
	button_row.add_theme_constant_override("separation", 10)

	if summary.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Empty"
		col.add_child(empty_label)

		var new_btn := Button.new()
		new_btn.text = "Start New Career"
		new_btn.theme_type_variation = "PrimaryButton"
		new_btn.pressed.connect(_on_slot_new_pressed.bind(slot))
		button_row.add_child(new_btn)
		UITheme.add_button_juice(new_btn)
	else:
		var summary_label := Label.new()
		summary_label.text = "%d horse%s   —   lead horse: %s   —   %d career win%s" % [
			int(summary.horse_count), "" if int(summary.horse_count) == 1 else "s",
			String(summary.lead_name) if String(summary.lead_name) != "" else "—",
			int(summary.total_wins), "" if int(summary.total_wins) == 1 else "s",
		]
		summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		col.add_child(summary_label)

		var continue_btn := Button.new()
		continue_btn.text = "Continue"
		continue_btn.theme_type_variation = "PrimaryButton"
		continue_btn.pressed.connect(_on_slot_continue_pressed.bind(slot))
		button_row.add_child(continue_btn)
		UITheme.add_button_juice(continue_btn)

		var delete_btn := Button.new()
		delete_btn.text = "Delete"
		delete_btn.theme_type_variation = "QuietButton"
		delete_btn.pressed.connect(_on_slot_delete_requested.bind(slot))
		button_row.add_child(delete_btn)
		UITheme.add_button_juice(delete_btn)

	col.add_child(button_row)
	return card

func _on_slot_new_pressed(slot: int) -> void:
	CareerStable.start_new_career(slot)
	_build()

func _on_slot_continue_pressed(slot: int) -> void:
	CareerStable.load_slot(slot)
	CareerStable.process_daily_trainer_upkeep()
	_refresh_balance_label()
	_build()

## Destructive — real confirmation dialog before actually deleting a slot's
## save file (CareerStable.delete_slot), same "confirm before anything
## irreversible" pattern this project's own tooling guidance calls for.
func _on_slot_delete_requested(slot: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Delete Career %d? This can't be undone." % (slot + 1)
	add_child(dialog)
	dialog.confirmed.connect(func():
		CareerStable.delete_slot(slot)
		dialog.queue_free()
		_build()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

## Back to the slot picker without leaving CareerHub entirely — reachable
## from the main hub footer (see _build_hub).
func _on_switch_career_pressed() -> void:
	CareerStable.current_slot = -1
	_build()

## ---- Starter pick ----

func _build_starter_pick() -> void:
	_add_heading("Choose Your First Horse")
	_add_body_text("Every great stable starts with one horse. Pick the one that fits how you want to race — you'll train the other two attributes up over time.")

	for i in range(CareerStable.STARTER_HORSES.size()):
		_content.add_child(_build_starter_card(i))

func _build_starter_card(index: int) -> Control:
	var starter: Dictionary = CareerStable.STARTER_HORSES[index]
	var card: PanelContainer = UITheme.make_glass_panel_container()
	var card_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		card_margin.add_theme_constant_override("margin_%s" % side, 14)
	card.add_child(card_margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	card_margin.add_child(col)

	var name_label := Label.new()
	name_label.theme_type_variation = "EyebrowLabel"
	name_label.text = starter.horse_name
	col.add_child(name_label)

	var specialty_label := Label.new()
	specialty_label.text = "Specialty: %s (starts at Level 2)" % CareerStable.CATEGORY_LABELS[starter.specialty]
	col.add_child(specialty_label)

	var flavor_label := Label.new()
	flavor_label.text = starter.flavor
	flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(flavor_label)

	var pick_btn := Button.new()
	pick_btn.text = "Choose " + String(starter.horse_name)
	pick_btn.pressed.connect(_on_starter_picked.bind(index))
	col.add_child(pick_btn)
	UITheme.add_button_juice(pick_btn)

	return card

func _on_starter_picked(index: int) -> void:
	CareerStable.pick_starter_horse(index)
	_build()

## ---- Main hub ----

func _build_hub() -> void:
	_add_heading("Your Career")

	for id in CareerStable.get_owned_horse_ids():
		_content.add_child(_build_horse_card(id))

	if _marketplace_open:
		_content.add_child(_build_marketplace_section())
	else:
		var buy_btn := Button.new()
		buy_btn.text = "Buy a Horse"
		buy_btn.theme_type_variation = "GhostButton"
		buy_btn.pressed.connect(func(): _marketplace_open = true; _build())
		_content.add_child(buy_btn)
		UITheme.add_button_juice(buy_btn)

	var footer_row := HFlowContainer.new()
	footer_row.add_theme_constant_override("separation", 10)
	_content.add_child(footer_row)

	var stats_btn := Button.new()
	stats_btn.text = "Career Achievements"
	stats_btn.theme_type_variation = "GhostButton"
	stats_btn.pressed.connect(_show_achievements_dialog)
	footer_row.add_child(stats_btn)
	UITheme.add_button_juice(stats_btn)

	var switch_btn := Button.new()
	switch_btn.text = "Switch Career"
	switch_btn.theme_type_variation = "GhostButton"
	switch_btn.pressed.connect(_on_switch_career_pressed)
	footer_row.add_child(switch_btn)
	UITheme.add_button_juice(switch_btn)

func _build_horse_card(id: int) -> Control:
	var horse: Dictionary = CareerStable.get_owned_horse(id)
	var origin: Dictionary = HorseOrigins.get_origin(String(horse.get("origin_id", "")))

	var card: PanelContainer = UITheme.make_glass_panel_container()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	card.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var title := Label.new()
	title.theme_type_variation = "EyebrowLabel"
	title.text = "%s  —  %s" % [horse.horse_name, origin.label]
	col.add_child(title)

	var record := Label.new()
	record.text = "Record: %dW-%dR    Jockey: %s" % [int(horse.get("career_wins", 0)), int(horse.get("career_races", 0)), horse.jockey_name]
	col.add_child(record)

	var horse_class: Dictionary = CareerStable.get_horse_class(id)
	var class_label := Label.new()
	class_label.text = "Class: %s" % horse_class.name
	col.add_child(class_label)

	# 3 category rollups shown compactly (each summed from several trainable
	# sub-attributes — see CareerStable.get_category_level) rather than all
	# ~25 sub-attribute lines inline, which would make this card enormous;
	# the "Train"/"Focus" buttons below open the full grouped list instead.
	var cap: int = CareerStable.get_potential_cap(id)
	for category_id in CareerStable.CATEGORY_IDS:
		var level: int = CareerStable.get_category_level(id, category_id)
		var pips: String = ""
		for p in range(cap):
			pips += "●" if p < level else "○"
		var attr_label := Label.new()
		attr_label.text = "%s: %s (Lv %d/%d)" % [CareerStable.CATEGORY_LABELS[category_id], pips, level, cap]
		col.add_child(attr_label)

	var trainer_tier: Dictionary = CareerStable.get_trainer_tier(String(horse.get("trainer_tier_id", "none")))
	var focus_id: String = String(horse.get("training_focus", CareerStable.SUB_ATTRIBUTE_IDS[0]))
	var trainer_row := HFlowContainer.new() # wraps to a new line instead of overflowing the panel when both buttons' text doesn't fit one row
	trainer_row.add_theme_constant_override("separation", 10)
	col.add_child(trainer_row)

	var trainer_btn := Button.new()
	trainer_btn.text = "Trainer: %s" % trainer_tier.label
	trainer_btn.theme_type_variation = "GhostButton"
	trainer_btn.pressed.connect(_on_open_trainer_selector.bind(id))
	trainer_row.add_child(trainer_btn)
	UITheme.add_button_juice(trainer_btn)

	var focus_btn := Button.new()
	focus_btn.text = "Focus: %s" % String(CareerStable.SUB_ATTRIBUTE_LABELS.get(focus_id, focus_id))
	focus_btn.theme_type_variation = "GhostButton"
	focus_btn.pressed.connect(_on_open_focus_selector.bind(id))
	trainer_row.add_child(focus_btn)
	UITheme.add_button_juice(focus_btn)

	var can_train: bool = CareerStable.can_train_today(id)
	var train_btn := Button.new()
	train_btn.text = "Train an Attribute (%s)" % OddsTable.format_money(CareerStable.SELF_TRAIN_ITEM_COST)
	train_btn.disabled = not can_train or not Bankroll.can_afford(CareerStable.SELF_TRAIN_ITEM_COST)
	train_btn.pressed.connect(_on_open_train_selector.bind(id))
	col.add_child(train_btn)
	UITheme.add_button_juice(train_btn)

	if not can_train:
		var trained_note := Label.new()
		trained_note.text = "Already trained %d time(s) today — check back tomorrow." % CareerStable.DAILY_TRAINING_ACTIONS
		col.add_child(trained_note)

	var race_btn := Button.new()
	race_btn.text = "Enter a Race — %s purse" % OddsTable.format_money(horse_class.purse)
	race_btn.theme_type_variation = "PrimaryButton"
	race_btn.pressed.connect(_start_race.bind(id))
	col.add_child(race_btn)
	UITheme.add_button_juice(race_btn)

	return card

## ---- Trainer / focus / train selectors (popup lists, not OptionButton) ----

func _on_open_trainer_selector(id: int) -> void:
	var options: Array = []
	for tier in CareerStable.TRAINER_TIERS:
		var label: String = String(tier.label)
		if int(tier.daily_cost) > 0:
			label = "%s — %s/day" % [tier.label, OddsTable.format_money(int(tier.daily_cost))]
		options.append({"id": tier.id, "label": label})
	_open_selector("Choose a Trainer", [{"heading": "", "options": options}], func(picked_id: String):
		CareerStable.hire_trainer(id, picked_id)
		_build()
	)

func _on_open_focus_selector(id: int) -> void:
	_open_selector("Set Training Focus", _sub_attribute_groups(), func(picked_id: String):
		CareerStable.set_training_focus(id, picked_id)
		_build()
	)

func _on_open_train_selector(id: int) -> void:
	var title: String = "Train Which Attribute? (%s)" % OddsTable.format_money(CareerStable.SELF_TRAIN_ITEM_COST)
	_open_selector(title, _sub_attribute_groups(), func(picked_id: String):
		_on_self_train_pressed(id, picked_id)
	)

func _on_self_train_pressed(id: int, attribute_id: String) -> void:
	CareerStable.self_train(id, attribute_id)
	_refresh_balance_label()
	_build()

## All 25 sub-attributes, grouped by their parent category — shared by the
## focus and train selectors so both list the exact same options the exact
## same way.
func _sub_attribute_groups() -> Array:
	var groups: Array = []
	for category_id in CareerStable.CATEGORY_IDS:
		var options: Array = []
		for sub_id in CareerStable.SUB_ATTRIBUTE_IDS:
			if String(CareerStable.SUB_ATTRIBUTE_CATEGORY.get(sub_id, "")) == category_id:
				options.append({"id": sub_id, "label": String(CareerStable.SUB_ATTRIBUTE_LABELS[sub_id])})
		groups.append({"heading": String(CareerStable.CATEGORY_LABELS[category_id]), "options": options})
	return groups

## Generic gamepad-friendly selection popup — a plain scrollable list of
## normal focusable Buttons in a Window (same "add_child + popup_centered"
## shape _show_achievements_dialog's AcceptDialog already uses, since
## AcceptDialog is itself a Window subclass), never an OptionButton — this
## project has documented OptionButton-popup-vs-gamepad bugs, and plain
## Buttons in a VBox get normal focus navigation for free. `groups` is
## [{"heading": String, "options": [{"id": String, "label": String}]}];
## `on_pick` is called with the chosen option's id once the player picks one.
func _open_selector(title: String, groups: Array, on_pick: Callable) -> void:
	var popup := Window.new()
	popup.title = title
	popup.size = Vector2i(440, 620)
	popup.unresizable = true
	add_child(popup)
	popup.close_requested.connect(popup.queue_free)

	var panel: PanelContainer = UITheme.make_glass_panel_container()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	popup.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	panel.add_child(margin)

	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	var first_btn: Button = null
	for group in groups:
		if String(group.get("heading", "")) != "":
			var heading := Label.new()
			heading.theme_type_variation = "EyebrowLabel"
			heading.text = String(group.heading)
			col.add_child(heading)
		for opt in group.options:
			var btn := Button.new()
			btn.text = String(opt.label)
			btn.pressed.connect(func():
				popup.queue_free()
				on_pick.call(String(opt.id))
			)
			col.add_child(btn)
			UITheme.add_button_juice(btn)
			if first_btn == null:
				first_btn = btn

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.theme_type_variation = "QuietButton"
	cancel_btn.pressed.connect(popup.queue_free)
	col.add_child(cancel_btn)

	popup.popup_centered()
	if first_btn != null:
		first_btn.grab_focus.call_deferred()

## ---- Marketplace (buying horse #2+) ----

func _build_marketplace_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)

	var heading := Label.new()
	heading.theme_type_variation = "EyebrowLabel"
	heading.text = "Buy a Horse"
	col.add_child(heading)

	for origin in HorseOrigins.ORIGINS:
		if origin.id == "starter":
			continue
		col.add_child(_build_marketplace_row(origin))

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.theme_type_variation = "QuietButton"
	close_btn.pressed.connect(func(): _marketplace_open = false; _build())
	col.add_child(close_btn)
	UITheme.add_button_juice(close_btn)

	return col

func _build_marketplace_row(origin: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "%s — %s (cap Lv %d)\n%s" % [origin.label, OddsTable.format_money(origin.price), origin.potential_cap, origin.description]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.disabled = not Bankroll.can_afford(int(origin.price))
	buy_btn.pressed.connect(_on_buy_pressed.bind(String(origin.id)))
	row.add_child(buy_btn)
	UITheme.add_button_juice(buy_btn)

	return row

func _on_buy_pressed(origin_id: String) -> void:
	var horse_name: String = CareerStable.PURCHASABLE_NAME_POOL[randi() % CareerStable.PURCHASABLE_NAME_POOL.size()]
	CareerStable.purchase_horse(origin_id, horse_name)
	_marketplace_open = false
	_refresh_balance_label()
	_build()

## ---- Achievements (relocated from TitleScreen's old read-only "Stable" dialog) ----

func _show_achievements_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Career Achievements"
	dialog.dialog_text = _achievements_summary_text()
	add_child(dialog)
	dialog.popup_centered()
	dialog.get_ok_button().grab_focus.call_deferred()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)

func _achievements_summary_text() -> String:
	var lines: PackedStringArray = []
	lines.append("Career Milestones (%d/%d):" % [CareerStable.milestones_unlocked.size(), CareerStable.MILESTONES.size()])
	for id in CareerStable.MILESTONES.keys():
		var unlocked: bool = CareerStable.milestones_unlocked.has(id)
		var mark: String = "✓" if unlocked else "-"
		lines.append("  %s %s — %s" % [mark, CareerStable.milestone_name(id), CareerStable.MILESTONES[id].description])
	lines.append("")
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
		lines.append("Winningest wild-field horses:")
		for entry in records.slice(0, 5):
			var horse_name: String = HorseRoster.NAMES[entry.id] if entry.id < HorseRoster.NAMES.size() else "Horse #%d" % entry.id
			lines.append("  %s — %dW-%dR" % [horse_name, entry.wins, entry.races])

	return "\n".join(lines)

## ---- Racing ----

func _start_race(stable_horse_id: int) -> void:
	# Snapshot the class/purse now, before this race's own result can bump
	# career_races — get_horse_class reads career_races live, so paying out
	# whatever class the horse is IN AFTER this race (rather than the class it
	# actually raced AT) would silently pay a Claiming-race purse at Allowance
	# rates the one race a horse levels up on.
	var race_class: Dictionary = CareerStable.get_horse_class(stable_horse_id)
	var owned_horse: Horse = _make_horse_resource(stable_horse_id)
	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	var field: Array[Horse] = [owned_horse]
	field.append_array(roster.slice(0, RIVAL_COUNT))
	HorseRoster.assign_race_colors(field)
	var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
	var overrides: Dictionary = CareerStable.build_attribute_overrides(stable_horse_id, 0)
	var result: RaceResult = RaceSim.simulate(field, tiers, overrides)

	_clear_view()

	var race_track := RaceTrack3D.new()
	_view_root.add_child(race_track)
	race_track.setup(field, result)
	race_track.playback_finished.connect(_on_race_finished.bind(stable_horse_id, race_class, result))
	race_track.play_with_post_time()

func _make_horse_resource(stable_horse_id: int) -> Horse:
	var data: Dictionary = CareerStable.get_owned_horse(stable_horse_id)
	var horse := Horse.new()
	horse.id = stable_horse_id
	horse.horse_name = String(data.get("horse_name", "Your Horse"))
	horse.jockey_name = String(data.get("jockey_name", ""))
	return horse

func _on_race_finished(stable_horse_id: int, race_class: Dictionary, result: RaceResult) -> void:
	var placement: int = result.finish_order.find(0) + 1
	var purse_before: int = Bankroll.balance
	CareerStable.pay_purse(stable_horse_id, placement, int(race_class.purse))
	var earned: int = Bankroll.balance - purse_before
	# "" (not the class id) whenever placement isn't 1st — check_milestones only
	# credits grade1_win for an ACTUAL win, not just racing in Grade 1 class.
	var just_won_class_id: String = String(race_class.id) if placement == 1 else ""
	var newly_unlocked: Array[String] = CareerStable.check_milestones(just_won_class_id)
	_show_race_result(placement, earned, String(race_class.name), newly_unlocked)

func _show_race_result(placement: int, earned: int, class_name_text: String, newly_unlocked_milestones: Array[String] = []) -> void:
	_clear_view()

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	_view_root.add_child(center)

	var panel: PanelContainer = UITheme.make_glass_panel_container()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 32)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var place_text: String = _ordinal(placement)
	var heading := Label.new()
	heading.theme_type_variation = "HeadingLabel"
	heading.text = "Finished %s!" % place_text
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(heading)

	var class_label := Label.new()
	class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	class_label.text = "%s race" % class_name_text
	col.add_child(class_label)

	var earned_label := Label.new()
	earned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if earned > 0:
		earned_label.text = "You earned %s in purse money!" % OddsTable.format_money(earned)
	else:
		earned_label.text = "No purse money this time — better luck next race."
	col.add_child(earned_label)

	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.theme_type_variation = "PrimaryButton"
	continue_btn.pressed.connect(_build)
	col.add_child(continue_btn)
	UITheme.add_button_juice(continue_btn)
	continue_btn.grab_focus.call_deferred()

	_show_milestone_toasts(newly_unlocked_milestones)

## Small stacked "🏆 Milestone Unlocked" badges in the top-right corner — same
## fade-Tween idiom FinishPodium._show_achievement_toasts already uses for
## the wild-field achievement toasts, kept separate since these are
## CareerStable milestones (per-slot), not Career.gd's global ones.
func _show_milestone_toasts(ids: Array[String]) -> void:
	for i in range(ids.size()):
		var label := Label.new()
		label.text = "🏆 Milestone Unlocked: %s" % CareerStable.milestone_name(ids[i])
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", UITheme.COLOR_GOLD_BRIGHT)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
		label.add_theme_constant_override("outline_size", 4)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.anchor_left = 1.0
		label.anchor_right = 1.0
		label.offset_left = -400.0
		label.offset_right = -20.0
		label.position.y = 20.0 + i * 32.0
		label.modulate.a = 0.0
		_view_root.add_child(label)
		var tween: Tween = create_tween()
		tween.tween_interval(0.3 + 0.25 * i)
		tween.tween_property(label, "modulate:a", 1.0, 0.4)

func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return "%dth" % n
