class_name FinishPodium
extends Control

## Full-screen overlay shown after a race — deliberately over the top: a
## big bouncy title card, then the winner's own name (in their silk colors)
## and time snapping in with a screen flash/fanfare/confetti/crowd-cheer/
## rumble all landing together as one punchy beat, then the bet outcome and
## the complete finish order. Plays "finish_fanfare"/"win_jingle"/
## "lose_sting" through AudioManager if those assets exist yet; otherwise
## runs identically but silent.
##
## AJ, after seeing an actual screenshot of an earlier version of this that
## put the top-3 finishers up on literal riser blocks with tiny 3D horses on
## top: "ditch the podium who tf cares... just make the finish animation
## better." That whole riser/diorama concept (PODIUM_COLORS/SLOT_PLACES/
## _build_podium/_build_horse_diorama etc.) is gone — replaced by putting
## the same effort into THIS reveal beat being tighter and punchier instead.
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

const CENTER_X: float = 800.0
## Leftover from the old podium-riser layout, where blocks up to 220px tall
## sat ABOVE this line — never rechecked after the podium was removed. With
## the window a fixed 900px tall, BASELINE_Y+40 (where the backdrop/payoff
## cards start) plus the old 430px-tall backdrop overflowed the bottom of
## the screen outright, cutting off horse #8's row before content even
## factored in. Lowered to reclaim the now-empty gap between the winner
## line (ends ~y=230) and here.
const BASELINE_Y: float = 260.0
const TITLE_LEAD_IN: float = 0.55
const WINNER_HOLD: float = 0.6 # short beat after the winner-line/flash/fanfare lands before the payoff/outcome panels pop in — long enough to register, short enough to stay "tight"

const OUTCOME_CHIP_SIZE: Vector2 = Vector2(340.0, 100.0) # see _build_outcome_chip

const CONFETTI_COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.2), Color(0.2, 0.55, 1.0), Color(1.0, 0.85, 0.1),
	Color(0.3, 0.9, 0.3), Color(0.9, 0.3, 0.9), Color(1.0, 0.6, 0.1),
]

## Below this margin (seconds) between 1st and 2nd, it's genuinely a photo
## finish. Above this, it's a runaway. AJ: "everything is a photo finish,
## make it only trigger if they finish like within a head length" — 0.3s
## measured out to a 1.5-LENGTH margin at this project's own established
## "1 length ≈ 0.2s" conversion (see finish_spread_check.gd's own comment)
## — nowhere near photo-finish territory in real racing, which is why it
## was firing on ~19% of races (measured via a throwaway 1000-trial sample:
## debug_finish_margin_check.gd, deleted after use). A real head is roughly
## 0.15-0.2 lengths, i.e. ~0.03-0.04s at that same conversion; landed on
## 0.05s instead of going tighter still since the same sample showed
## anything below ~0.03s was almost entirely exact/near-exact simulation
## ties rather than genuine close racing, and 0.05s already gives a real,
## rare (~3.6% of races in that sample) trigger rate without being so tight
## it reads as broken/never-happening.
const PHOTO_FINISH_MARGIN: float = 0.05
const RUNAWAY_MARGIN: float = 3.0

var result: RaceResult

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

	_show_winner_line()
	_flash_screen()
	# All four land in the same instant — the actual "we have a winner"
	# impact beat. finish_fanfare/crowd_cheer each get a -8dB cut so the
	# combined result reads as one big moment instead of two full-volume
	# sounds summing into a blaring spike.
	AudioManager.play_sfx("finish_fanfare", -8.0)
	AudioManager.play_sfx("crowd_cheer", -8.0)
	InputHints.rumble(0.25, 0.6, 0.4)
	_spawn_confetti()

	await get_tree().create_timer(WINNER_HOLD).timeout

	var unlocked: Array[String] = Career.record_finish(result)
	_build_payoff_board()
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

	# AJ: the reveal looked "jumbled" — this used to loop 6x (6 real seconds),
	# still visibly rocking back and forth long after the payout/payoff cards
	# had already appeared below it. A serious dollar-amount card sharing the
	# screen with a banner still lazily wobbling reads as messy, not festive.
	# 2 loops settles it well before WINNER_HOLD (0.6s) elapses.
	var wobble: Tween = create_tween()
	wobble.set_loops(2)
	wobble.tween_property(title, "rotation", deg_to_rad(-2.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	wobble.tween_property(title, "rotation", deg_to_rad(2.0), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	wobble.tween_property(title, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_SINE) # settle dead level, not mid-wobble

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

## Winner's name (in their own silk_primary) + finish time, snapping in with
## a punchy scale/overshoot right as the flash/fanfare/confetti/rumble all
## land together (see setup()) — the actual "we have a winner" payoff beat,
## now that there's no podium riser to reveal it via rise-and-bounce instead.
func _show_winner_line() -> void:
	if result.finish_order.is_empty():
		return
	var winner: RaceHorseState = result.field[result.finish_order[0]]

	var name_label := Label.new()
	name_label.text = winner.horse.horse_name
	name_label.theme_type_variation = "HeadingLabel"
	name_label.add_theme_font_size_override("font_size", 40)
	name_label.add_theme_color_override("font_color", winner.horse.silk_primary)
	name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(600.0, 50.0)
	name_label.position = Vector2(CENTER_X - 300.0, 165.0)
	name_label.pivot_offset = Vector2(300.0, 25.0)
	name_label.scale = Vector2(0.6, 0.6)
	name_label.modulate.a = 0.0
	add_child(name_label)

	var time_label := Label.new()
	time_label.text = "%.2fs" % winner.finish_time
	time_label.add_theme_font_size_override("font_size", 18)
	time_label.add_theme_color_override("font_color", Color(UITheme.COLOR_CREAM, 0.85))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.custom_minimum_size = Vector2(600.0, 24.0)
	time_label.position = Vector2(CENTER_X - 300.0, 210.0)
	time_label.modulate.a = 0.0
	add_child(time_label)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(name_label, "scale", Vector2(1.1, 1.1), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(name_label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)
	tween.set_parallel(true)
	tween.tween_property(name_label, "modulate:a", 1.0, 0.15)
	tween.tween_property(time_label, "modulate:a", 1.0, 0.15)

## One frame of pure white flashed over the whole screen right as the
## fanfare/crowd cheer/rumble/confetti all land — a fast in, slightly slower
## out (a real camera flash decays, it doesn't cut) — sells the "moment of
## impact" the old podium used to carry via its rise-and-land bounce.
func _flash_screen() -> void:
	var flash := ColorRect.new()
	flash.color = Color.WHITE
	flash.size = size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	add_child(flash)

	var tween: Tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0.85, 0.05)
	tween.tween_property(flash, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(flash.queue_free)

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
	continue_btn.text = "CONTINUE TO RACE 2 →"
	continue_btn.theme_type_variation = "PrimaryButton"
	continue_btn.custom_minimum_size = Vector2(280.0, 52.0)
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
	continue_btn.text = "CONTINUE"
	continue_btn.theme_type_variation = "PrimaryButton"
	continue_btn.custom_minimum_size = Vector2(280.0, 52.0)
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

	var bet_description: String = "%s %s on %s" % [
		OddsTable.format_money(amount), description, result.field[horse_index].horse.horse_name,
	] if horse_index < result.field.size() else description
	if won:
		Bankroll.pay(payout)
		AudioManager.play_sfx("win_jingle", -8.0) # this file is mastered hot; -8dB brings it in line with everything else
	else:
		AudioManager.play_sfx("lose_sting", -8.0) # matches win_jingle's cut so neither outcome jolts louder than the other
	var chip: Control = _build_outcome_chip(won, payout, bet_description)
	chip.position = Vector2(CENTER_X - OUTCOME_CHIP_SIZE.x * 0.5, BASELINE_Y + 50.0)
	add_child(chip)

	# Pushed down from the old +100 to clear the chip above (BASELINE_Y+50,
	# OUTCOME_CHIP_SIZE.y=100 tall — the old single-line Label it replaced
	# was much shorter and never needed this much room).
	var list_box: VBoxContainer = _add_full_order_list(BASELINE_Y + 165.0)
	var again_btn := Button.new()
	again_btn.text = "RACE AGAIN"
	again_btn.theme_type_variation = "PrimaryButton"
	again_btn.custom_minimum_size = Vector2(280.0, 52.0)
	again_btn.pressed.connect(func(): race_again_pressed.emit())
	list_box.add_child(again_btn)
	UITheme.add_button_juice(again_btn)
	again_btn.grab_focus.call_deferred() # lets a gamepad/keyboard player immediately mash "Race Again" without a mouse

	mouse_filter = Control.MOUSE_FILTER_STOP
	return Career.record_bet_outcome(won, amount, win_tier)

## AJ: "clean up the you won money text box make it look tight" — was one
## long run-on sentence ("YOU WON $X! (bankroll: $Y)") in a single Label with
## no card of its own. Now a compact bordered chip (same glass-panel language
## as the payoff board next to it) with the actual dollar amount as its own
## big, bold focal line — a real number, not a middle word buried in a
## sentence — and the bet description underneath in a quieter, smaller line.
## Bankroll total dropped entirely: BettingUI/TrackLobby's own balance
## display already shows that continuously, repeating it here was clutter
## this specific chip doesn't need.
func _build_outcome_chip(won: bool, payout: int, bet_description: String) -> Control:
	var accent: Color = Color(0.35, 0.95, 0.4) if won else Color(0.95, 0.35, 0.35)
	var chip: Panel = UITheme.make_glass_panel(OUTCOME_CHIP_SIZE, 16.0, Color(UITheme.COLOR_BG, 0.6), accent)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	chip.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)

	var eyebrow := Label.new()
	eyebrow.theme_type_variation = "EyebrowLabel"
	eyebrow.text = "🏆 YOU WON" if won else "LOST THE BET"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_color_override("font_color", accent)
	box.add_child(eyebrow)

	var amount_label := Label.new()
	amount_label.theme_type_variation = "HeadingLabel"
	if won:
		amount_label.text = "+%s" % OddsTable.format_money(payout)
		amount_label.add_theme_font_size_override("font_size", 32)
	else:
		# A loss has no payout figure worth headlining — the bet amount lost
		# is already in the description line below; leading with "-$0" would
		# read as a bug, not a real number.
		amount_label.text = "NO PAYOUT"
		amount_label.add_theme_font_size_override("font_size", 22)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount_label.add_theme_color_override("font_color", accent)
	box.add_child(amount_label)

	var desc_label := Label.new()
	desc_label.text = bet_description
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_color_override("font_color", Color(UITheme.COLOR_CREAM, 0.75))
	box.add_child(desc_label)

	return chip

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

const BACKDROP_SIZE: Vector2 = Vector2(360.0, 340.0) # sized for chip + 2-column order list (see _add_full_order_list) + button, now that BASELINE_Y no longer wastes ~220px on the removed podium risers
const PAYOFF_BOARD_SIZE: Vector2 = Vector2(320.0, 190.0)
## Traditional US racetrack "$2 Mutuel Payoffs" board convention — shown
## regardless of what anyone actually staked, exactly like a real broadcast's
## payout graphic. Not tied to Bankroll/BettingUI's own bet-amount scale at
## all; it's a race-wide informational graphic, not a personal bet result.
const PAYOFF_BET_BASE: int = 2

## Real racetrack broadcasts show this after every race regardless of whether
## you personally had a bet in — win/place/show payout for the top 3
## finishers off a standard $2 bet. Previously the single biggest missing
## piece of broadcast authenticity here: the game only ever showed the
## PLAYER's own bet outcome as one sentence (see _build_outcome_and_list),
## never the track-wide payout graphic every real broadcast overlays. Called
## from setup() itself (not from any bet_context branch) so it appears
## whether or not this particular race had a bet riding on it, same as a
## real board. Positioned to the right of the main backdrop card rather than
## sharing it — the existing backdrop is a fixed 360x380 already close to
## full with the outcome text + full finish order + button, and this
## screen's layout is entirely fixed-pixel (see CENTER_X/BASELINE_Y above),
## so a separate card avoids fighting that layout for vertical space.
func _build_payoff_board() -> void:
	if result.finish_order.size() < 2:
		return # need at least a win+place for a board to say anything

	var board: Panel = UITheme.make_glass_panel(PAYOFF_BOARD_SIZE, 16.0, Color(UITheme.COLOR_BG, 0.6))
	board.position = Vector2(CENTER_X + BACKDROP_SIZE.x * 0.5 + 20.0, BASELINE_Y + 40.0)
	add_child(board)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	board.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var eyebrow := Label.new()
	eyebrow.theme_type_variation = "EyebrowLabel"
	eyebrow.text = "$%d MUTUEL PAYOFFS" % PAYOFF_BET_BASE
	box.add_child(eyebrow)

	var win_state: RaceHorseState = result.field[result.finish_order[0]]
	box.add_child(_payoff_row(win_state.horse.horse_name, [
		["WIN", OddsTable.payout(PAYOFF_BET_BASE, win_state.tier, OddsTable.BetType.WIN)],
		["PLACE", OddsTable.payout(PAYOFF_BET_BASE, win_state.tier, OddsTable.BetType.PLACE)],
		["SHOW", OddsTable.payout(PAYOFF_BET_BASE, win_state.tier, OddsTable.BetType.SHOW)],
	]))

	var place_state: RaceHorseState = result.field[result.finish_order[1]]
	box.add_child(_payoff_row(place_state.horse.horse_name, [
		["PLACE", OddsTable.payout(PAYOFF_BET_BASE, place_state.tier, OddsTable.BetType.PLACE)],
		["SHOW", OddsTable.payout(PAYOFF_BET_BASE, place_state.tier, OddsTable.BetType.SHOW)],
	]))

	if result.finish_order.size() >= 3:
		var show_state: RaceHorseState = result.field[result.finish_order[2]]
		box.add_child(_payoff_row(show_state.horse.horse_name, [
			["SHOW", OddsTable.payout(PAYOFF_BET_BASE, show_state.tier, OddsTable.BetType.SHOW)],
		]))

## One finisher's payoff line(s) — `entries` is an Array of [label, amount]
## pairs, e.g. [["WIN", 5], ["PLACE", 3], ["SHOW", 2]] for the winner, down to
## just [["SHOW", 2]] for 3rd. Horse name on its own line above since some
## names run long enough to crowd three payout figures on one line otherwise.
func _payoff_row(horse_name: String, entries: Array) -> VBoxContainer:
	var row_box := VBoxContainer.new()
	row_box.add_theme_constant_override("separation", 1)

	var name_label := Label.new()
	name_label.text = horse_name
	name_label.add_theme_font_size_override("font_size", 15)
	row_box.add_child(name_label)

	var line_parts: Array[String] = []
	for entry in entries:
		line_parts.append("%s %s" % [entry[0], OddsTable.format_money(entry[1])])
	var line_label := Label.new()
	line_label.text = "    " + "     ".join(line_parts)
	line_label.add_theme_font_size_override("font_size", 14)
	line_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	row_box.add_child(line_label)

	return row_box

## Glass card grouping the outcome text + full finish order + Race Again
## button into one visually distinct region instead of them floating loose
## over the confetti/podium — sized generously since the exact content
## height varies (a Daily Double's "still live" note is shorter than a
## resolved bet's win/loss line + 8-horse order list + button).
func _add_backdrop_card() -> void:
	var backdrop: Panel = UITheme.make_glass_panel(BACKDROP_SIZE, 20.0, Color(UITheme.COLOR_BG, 0.55))
	backdrop.position = Vector2(CENTER_X - BACKDROP_SIZE.x * 0.5, BASELINE_Y + 40.0)
	add_child(backdrop)

## 2-column grid, not one long vertical list — AJ: "you cant even see the
## number 8 horse it cuts off the name." Fixed mainly by BASELINE_Y no
## longer wasting ~220px on the removed podium risers (see that const's own
## comment), but halving the list's own height is a real, cheap second
## margin of safety against an 8+ horse field ever running off the bottom
## of a fixed 900px window again.
func _add_full_order_list(top_y: float) -> VBoxContainer:
	var list_box := VBoxContainer.new()
	list_box.position = Vector2(CENTER_X - 165.0, top_y)
	add_child(list_box)

	var header := Label.new()
	header.text = "Full order (%.1fs):" % result.duration
	list_box.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	list_box.add_child(grid)

	for place in range(result.finish_order.size()):
		var idx: int = result.finish_order[place]
		var state: RaceHorseState = result.field[idx]
		var row := Label.new()
		row.text = "%d. %s — %.2fs" % [place + 1, state.horse.horse_name, state.finish_time]
		row.add_theme_font_size_override("font_size", 14)
		grid.add_child(row)

	return list_box
