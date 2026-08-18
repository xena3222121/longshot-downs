class_name FinishPodium
extends Control

## Full-screen overlay shown after a race — deliberately over the top: a
## big bouncy title card, 3rd place rises first, then 2nd, then 1st (each
## with a squash-and-stretch landing bounce, biggest reveal held for last),
## a multi-color confetti rain timed with the fanfare, then the bet outcome
## and the complete finish order. Plays "finish_fanfare"/"win_jingle"/
## "lose_sting" through AudioManager if those assets exist yet; otherwise
## runs identically but silent.
##
## `bet_context` carries everything needed to resolve (or defer resolving)
## the bet, since that varies by bet type:
##   bet_type: OddsTable.BetType
##   horse_index: int          — Win/Place/Show pick, Exacta 1st, or DD race-1 pick
##   second_index: int         — Exacta 2nd pick, or DD race-2 pick (-1 if unused)
##   amount: int
##   dd_leg: int               — 0 = not a Daily Double; 1 = this is race 1 of one
##                                (no payout yet, "Continue" instead of "Race Again");
##                                2 = this is race 2, resolves the combined bet
##   dd_leg1_result: RaceResult — only needed when dd_leg == 2

signal race_again_pressed
signal continue_to_next_race

const PODIUM_COLORS: Array[Color] = [
	Color(0.85, 0.68, 0.15), Color(0.75, 0.75, 0.78), Color(0.72, 0.45, 0.2),
] # gold, silver, bronze — indexed by place (0-based)
const PODIUM_HEIGHTS: Array[float] = [220.0, 160.0, 120.0] # indexed by place
const SLOT_PLACES: Array[int] = [1, 0, 2] # left-to-right visual order: 2nd, 1st, 3rd
const REVEAL_ORDER: Array[int] = [2, 1, 0] # bronze, silver, then gold last

const BLOCK_WIDTH: float = 130.0
const BLOCK_GAP: float = 24.0
const CENTER_X: float = 800.0
const BASELINE_Y: float = 480.0
const RISE_DURATION: float = 0.45
const REVEAL_STAGGER: float = 0.5
const TITLE_LEAD_IN: float = 0.7

const CONFETTI_COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.2), Color(0.2, 0.55, 1.0), Color(1.0, 0.85, 0.1),
	Color(0.3, 0.9, 0.3), Color(0.9, 0.3, 0.9), Color(1.0, 0.6, 0.1),
]

## Below this margin (seconds) between 1st and 2nd, it's genuinely a photo
## finish. Above this, it's a runaway. The title banner used to hardcode
## "PHOTO FINISH!" unconditionally — true maybe once in a while, wrong (and
## a little absurd) every other race.
const PHOTO_FINISH_MARGIN: float = 0.3
const RUNAWAY_MARGIN: float = 3.0

var result: RaceResult
var _podium_rest_y: Dictionary = {} # place -> resting y position, for the reveal tween
var _podium_blocks: Dictionary = {} # place -> the ColorRect, for the landing bounce

func setup(p_field: Array[Horse], p_result: RaceResult, bet_context: Dictionary) -> void:
	result = p_result
	position = Vector2.ZERO
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.size = size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_show_title_banner()
	await get_tree().create_timer(TITLE_LEAD_IN).timeout

	_build_podium()
	_reveal_podium()

	await get_tree().create_timer(REVEAL_STAGGER * REVEAL_ORDER.size() + RISE_DURATION).timeout
	# Both cues fire in the same instant — each gets a -8dB cut so the combined
	# result reads as one big moment instead of two full-volume sounds summing
	# into a blaring spike.
	AudioManager.play_sfx("finish_fanfare", -8.0)
	AudioManager.play_sfx("crowd_cheer", -8.0)
	InputHints.rumble(0.25, 0.6, 0.4)
	_spawn_confetti()

	var unlocked: Array[String] = Career.record_finish(result)
	if bet_context.is_empty():
		# RaceScheduler's multi-screen viewing doesn't require a bet to watch
		# a race — this is the "just watching, no bet riding on it" case, not
		# possible in the old single-track flow (which never showed a race
		# without one).
		_build_watch_only_continue()
	elif int(bet_context.get("dd_leg", 0)) == 1:
		_build_leg1_continue()
	else:
		unlocked.append_array(_build_outcome_and_list(bet_context))
	_show_achievement_toasts(unlocked)

## Big bouncy title card that pops in before the podium even builds — the
## opening beat of the celebration.
func _show_title_banner() -> void:
	var title := Label.new()
	title.text = _banner_text()
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(700.0, 90.0)
	title.position = Vector2(CENTER_X - 350.0, 60.0)
	title.pivot_offset = Vector2(350.0, 45.0)
	title.scale = Vector2.ZERO
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	title.add_theme_color_override("font_outline_color", Color(0.4, 0.1, 0.0))
	title.add_theme_constant_override("outline_size", 10)
	add_child(title)

	var tween: Tween = create_tween()
	tween.tween_property(title, "scale", Vector2(1.25, 1.25), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(title, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_SINE)

	var wobble: Tween = create_tween()
	wobble.set_loops(6)
	wobble.tween_property(title, "rotation", deg_to_rad(-2.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	wobble.tween_property(title, "rotation", deg_to_rad(2.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Reads the actual margin between 1st and 2nd rather than assuming — see
## PHOTO_FINISH_MARGIN/RUNAWAY_MARGIN above.
func _banner_text() -> String:
	if result.finish_order.size() < 2:
		return "WE HAVE A WINNER!"
	var winner_time: float = result.field[result.finish_order[0]].finish_time
	var runner_up_time: float = result.field[result.finish_order[1]].finish_time
	var margin: float = runner_up_time - winner_time
	if margin < PHOTO_FINISH_MARGIN:
		return "PHOTO FINISH!"
	elif margin > RUNAWAY_MARGIN:
		return "WINS GOING AWAY!"
	return "WE HAVE A WINNER!"

func _build_podium() -> void:
	for slot in range(SLOT_PLACES.size()):
		var place: int = SLOT_PLACES[slot]
		var idx: int = result.finish_order[place]
		var state: RaceHorseState = result.field[idx]
		var height: float = PODIUM_HEIGHTS[place]
		var slot_x: float = CENTER_X + (slot - 1) * (BLOCK_WIDTH + BLOCK_GAP) - BLOCK_WIDTH * 0.5
		var rest_y: float = BASELINE_Y - height
		_podium_rest_y[place] = rest_y

		var unit := Control.new()
		unit.position = Vector2(slot_x, BASELINE_Y + 60.0) # starts hidden below the baseline
		unit.name = "podium_unit_%d" % place
		add_child(unit)

		var block := ColorRect.new()
		block.color = PODIUM_COLORS[place]
		block.size = Vector2(BLOCK_WIDTH, height)
		block.pivot_offset = Vector2(BLOCK_WIDTH * 0.5, height)
		unit.add_child(block)
		_podium_blocks[place] = block

		var place_label := Label.new()
		place_label.text = "%d" % (place + 1)
		place_label.add_theme_font_size_override("font_size", 30)
		place_label.custom_minimum_size = Vector2(BLOCK_WIDTH, 40.0)
		place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		place_label.position = Vector2(0.0, 6.0)
		unit.add_child(place_label)

		var name_label := Label.new()
		name_label.text = state.horse.horse_name
		name_label.add_theme_color_override("font_color", state.horse.silk_secondary)
		name_label.custom_minimum_size = Vector2(BLOCK_WIDTH + 40.0, 24.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.position = Vector2(-20.0, -50.0)
		unit.add_child(name_label)

		var time_label := Label.new()
		time_label.text = "%.2fs" % state.finish_time
		time_label.custom_minimum_size = Vector2(BLOCK_WIDTH, 20.0)
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_label.position = Vector2(0.0, -26.0)
		unit.add_child(time_label)

## Each block rises with a big overshoot, then lands with a squash-and-
## stretch bounce (wide+flat, then tall+thin, then settle) instead of just
## stopping dead — gold's bounce is the biggest and gets a continuous idle
## pulse afterward so the winner keeps drawing the eye.
func _reveal_podium() -> void:
	var delay: float = 0.0
	for place in REVEAL_ORDER:
		var unit: Control = get_node("podium_unit_%d" % place)
		var block: ColorRect = _podium_blocks[place]
		var tween: Tween = create_tween()
		tween.tween_interval(delay)
		tween.tween_property(unit, "position:y", _podium_rest_y[place], RISE_DURATION) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_land_bounce.bind(block, place))
		delay += REVEAL_STAGGER

func _land_bounce(block: ColorRect, place: int) -> void:
	var is_winner: bool = place == 0
	var squash: float = 1.35 if is_winner else 1.2
	var tween: Tween = create_tween()
	tween.tween_property(block, "scale", Vector2(squash, 1.0 / squash), 0.09)
	tween.tween_property(block, "scale", Vector2(1.0 / squash * 0.95, squash * 0.95), 0.09)
	tween.tween_property(block, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if is_winner:
		tween.tween_callback(_start_winner_pulse.bind(block))

func _start_winner_pulse(block: ColorRect) -> void:
	var pulse: Tween = create_tween()
	pulse.set_loops()
	pulse.tween_property(block, "scale", Vector2(1.06, 1.06), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(block, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Multi-color confetti raining down across the whole width of the screen —
## several single-color CPUParticles2D emitters layered together, since one
## emitter only tints all its particles a single color.
func _spawn_confetti() -> void:
	var width: float = size.x
	for color in CONFETTI_COLORS:
		var p := CPUParticles2D.new()
		p.position = Vector2(width * 0.5, -20.0)
		p.emitting = true
		p.one_shot = true
		p.amount = 40
		p.lifetime = 3.0
		p.explosiveness = 0.3
		p.direction = Vector2(0.0, 1.0)
		p.spread = 25.0
		p.gravity = Vector2(0.0, 260.0)
		p.initial_velocity_min = 60.0
		p.initial_velocity_max = 200.0
		p.angular_velocity_min = -540.0
		p.angular_velocity_max = 540.0
		p.scale_amount_min = 5.0
		p.scale_amount_max = 9.0
		p.color = color
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(width * 0.5, 4.0)
		add_child(p)

## Race 1 of a Daily Double: show the field and finish order, but the bet
## isn't decided yet — resolution waits for race 2. No payout, no win/lose
## sting, just a nudge onward.
func _build_leg1_continue() -> void:
	_add_backdrop_card()
	var note := Label.new()
	note.add_theme_font_size_override("font_size", 20)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.custom_minimum_size = Vector2(400.0, 30.0)
	note.position = Vector2(CENTER_X - 200.0, BASELINE_Y + 60.0)
	note.text = "Daily Double is still live — on to race 2..."
	add_child(note)

	var list_box: VBoxContainer = _add_full_order_list(BASELINE_Y + 100.0)
	var continue_btn := Button.new()
	continue_btn.text = "Continue to Race 2 →"
	continue_btn.pressed.connect(func(): continue_to_next_race.emit())
	list_box.add_child(continue_btn)
	UITheme.add_button_juice(continue_btn)
	continue_btn.grab_focus.call_deferred()

	mouse_filter = Control.MOUSE_FILTER_STOP

## Watched this race on a RaceScheduler screen with no bet riding on it — no
## payout, no win/lose sting, just the finish order and a way back.
func _build_watch_only_continue() -> void:
	_add_backdrop_card()
	var note := Label.new()
	note.add_theme_font_size_override("font_size", 20)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.custom_minimum_size = Vector2(400.0, 30.0)
	note.position = Vector2(CENTER_X - 200.0, BASELINE_Y + 60.0)
	note.text = "Just watching this one — no bet placed."
	add_child(note)

	var list_box: VBoxContainer = _add_full_order_list(BASELINE_Y + 100.0)
	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.pressed.connect(func(): race_again_pressed.emit())
	list_box.add_child(continue_btn)
	UITheme.add_button_juice(continue_btn)
	continue_btn.grab_focus.call_deferred()

	mouse_filter = Control.MOUSE_FILTER_STOP

## Returns any achievement ids newly unlocked by this bet's outcome, for
## setup() to fold into its single combined toast list.
func _build_outcome_and_list(bet_context: Dictionary) -> Array[String]:
	_add_backdrop_card()
	var bet_type: OddsTable.BetType = bet_context.bet_type
	var amount: int = bet_context.amount
	var horse_index: int = bet_context.horse_index
	var second_index: int = int(bet_context.get("second_index", -1))
	# Explicit element-wise conversion rather than a direct assignment —
	# bet_context is a Dictionary (necessarily loosely typed), and GDScript's
	# strict Array[int] typing rejects assigning a plain untyped Array to it
	# at runtime even when every element is actually an int.
	var picks: Array[int] = []
	for p in bet_context.get("picks", []):
		picks.append(int(p))
	var dd_leg: int = int(bet_context.get("dd_leg", 0))

	var won: bool = false
	var payout: int = 0
	var win_tier: Dictionary = {} # only populated for a plain WIN bet — see Career.record_bet_outcome's Giant Killer check
	var description: String = OddsTable.bet_type_label(bet_type)

	if dd_leg == 2:
		var leg1_result: RaceResult = bet_context.dd_leg1_result
		var leg1_won: bool = OddsTable.is_winning_bet(leg1_result.finish_order, horse_index, OddsTable.BetType.WIN)
		var leg2_won: bool = OddsTable.is_winning_bet(result.finish_order, second_index, OddsTable.BetType.WIN)
		won = leg1_won and leg2_won
		if won:
			payout = OddsTable.daily_double_payout(amount, leg1_result.field[horse_index].tier, result.field[second_index].tier)
	elif bet_type == OddsTable.BetType.EXACTA:
		won = OddsTable.is_winning_exacta(result.finish_order, horse_index, second_index)
		if won:
			payout = OddsTable.exacta_payout(amount, result.field[horse_index].tier, result.field[second_index].tier)
	elif bet_type == OddsTable.BetType.QUINELLA:
		won = OddsTable.is_winning_quinella(result.finish_order, picks)
		if won:
			payout = OddsTable.multi_payout(amount, [result.field[picks[0]].tier, result.field[picks[1]].tier])
	elif bet_type == OddsTable.BetType.TRIFECTA or bet_type == OddsTable.BetType.SUPERFECTA:
		won = OddsTable.is_winning_exact_order(result.finish_order, picks)
		if won:
			var pick_tiers: Array[Dictionary] = []
			for p in picks:
				pick_tiers.append(result.field[p].tier)
			payout = OddsTable.multi_payout(amount, pick_tiers)
	else:
		won = OddsTable.is_winning_bet(result.finish_order, horse_index, bet_type)
		if won:
			payout = OddsTable.payout(amount, result.field[horse_index].tier, bet_type)
			if bet_type == OddsTable.BetType.WIN:
				win_tier = result.field[horse_index].tier

	# Career's race-class purse bonus (see Career.RACE_CLASSES) — a flat
	# bonus on top of the bet's own payout, not a rebalance of the payout
	# math itself.
	if won:
		payout = int(round(payout * (1.0 + Career.get_purse_bonus())))

	var outcome := Label.new()
	outcome.add_theme_font_size_override("font_size", 20)
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome.custom_minimum_size = Vector2(400.0, 30.0)
	outcome.position = Vector2(CENTER_X - 200.0, BASELINE_Y + 60.0)

	if won:
		Bankroll.pay(payout)
		outcome.text = "YOU WON %s! (bankroll: %s)" % [OddsTable.format_money(payout), OddsTable.format_money(Bankroll.balance)]
		outcome.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		AudioManager.play_sfx("win_jingle", -8.0) # this file is mastered hot; -8dB brings it in line with everything else
	else:
		outcome.text = "You lost your %s %s bet. (bankroll: %s)" % [
			OddsTable.format_money(amount), description, OddsTable.format_money(Bankroll.balance),
		]
		outcome.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
		AudioManager.play_sfx("lose_sting", -8.0) # matches win_jingle's cut so neither outcome jolts louder than the other
	add_child(outcome)

	var list_box: VBoxContainer = _add_full_order_list(BASELINE_Y + 100.0)
	var again_btn := Button.new()
	again_btn.text = "Race Again"
	again_btn.pressed.connect(func(): race_again_pressed.emit())
	list_box.add_child(again_btn)
	UITheme.add_button_juice(again_btn)
	again_btn.grab_focus.call_deferred() # lets a gamepad/keyboard player immediately mash "Race Again" without a mouse

	mouse_filter = Control.MOUSE_FILTER_STOP
	return Career.record_bet_outcome(won, amount, win_tier)

## Small stacked "🏆 Achievement Unlocked" badges in the top-right corner,
## each fading in slightly staggered — reuses the same fade-Tween idiom as
## the rest of this file's reveal beats instead of introducing a new pattern.
func _show_achievement_toasts(ids: Array[String]) -> void:
	for i in range(ids.size()):
		var label := Label.new()
		label.text = "🏆 Achievement Unlocked: %s" % Career.achievement_name(ids[i])
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", UITheme.COLOR_GOLD_BRIGHT)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.7))
		label.add_theme_constant_override("outline_size", 4)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.custom_minimum_size = Vector2(360.0, 28.0)
		label.position = Vector2(size.x - 380.0, 20.0 + i * 32.0)
		label.modulate.a = 0.0
		add_child(label)
		var tween: Tween = create_tween()
		tween.tween_interval(0.3 + 0.25 * i)
		tween.tween_property(label, "modulate:a", 1.0, 0.4)

const BACKDROP_SIZE: Vector2 = Vector2(360.0, 380.0)

## Glass card grouping the outcome text + full finish order + Race Again
## button into one visually distinct region instead of them floating loose
## over the confetti/podium — sized generously since the exact content
## height varies (a Daily Double's "still live" note is shorter than a
## resolved bet's win/loss line + 8-horse order list + button).
func _add_backdrop_card() -> void:
	var backdrop: Panel = UITheme.make_glass_panel(BACKDROP_SIZE, 20.0, Color(0.016, 0.027, 0.047, 0.55))
	backdrop.position = Vector2(CENTER_X - BACKDROP_SIZE.x * 0.5, BASELINE_Y + 40.0)
	add_child(backdrop)

func _add_full_order_list(top_y: float) -> VBoxContainer:
	var list_box := VBoxContainer.new()
	list_box.position = Vector2(CENTER_X - 150.0, top_y)
	add_child(list_box)

	var header := Label.new()
	header.text = "Full order (%.1fs):" % result.duration
	list_box.add_child(header)

	for place in range(result.finish_order.size()):
		var idx: int = result.finish_order[place]
		var state: RaceHorseState = result.field[idx]
		var row := Label.new()
		row.text = "%d. %s — %.2fs" % [place + 1, state.horse.horse_name, state.finish_time]
		list_box.add_child(row)

	return list_box
