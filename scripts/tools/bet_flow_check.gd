extends Node

## Dev tool, not part of the game: exercises the bet -> race -> payout
## resolution path (via BettingUI's own methods, not real clicks) as a
## regression smoke test. Must run as a real scene (not via --script) so
## the Bankroll autoload is actually bootstrapped:
##   godot --headless --path . res://scenes/tools/bet_flow_check.tscn --quit-after 5

func _ready() -> void:
	_check_odds_table_unit_cases()
	_check_went_broke_timing()

	Bankroll.autosave_enabled = false # never let these fake trials touch the real save file
	var trials: int = 300
	var bet_types: Array[OddsTable.BetType] = [
		OddsTable.BetType.WIN, OddsTable.BetType.PLACE, OddsTable.BetType.SHOW, OddsTable.BetType.EXACTA,
		OddsTable.BetType.QUINELLA, OddsTable.BetType.TRIFECTA, OddsTable.BetType.SUPERFECTA,
	]
	var wins_by_type: Dictionary = {}
	var losses_by_type: Dictionary = {}
	for bt in bet_types:
		wins_by_type[bt] = 0
		losses_by_type[bt] = 0

	for t in range(trials):
		Bankroll.balance = 100000 # comfortable headroom above BET_LEVELS[0] (10000) — was 1000/BET_LEVELS[0]==100 before the min-bet bump
		var this_bet_type: OddsTable.BetType = bet_types[t % bet_types.size()]
		var needed: int = OddsTable.picks_required(this_bet_type)

		var roster: Array[Horse] = HorseRoster.generate()
		roster.shuffle()
		var field: Array[Horse] = roster.slice(0, 8)
		var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())

		var betting_ui := BettingUI.new()
		betting_ui.setup(field, tiers)
		betting_ui.bet_type = this_bet_type # bypass the OptionButton widget itself, same as horse selection below
		for i in range(needed): # 1 pick for Win/Place/Show, 2/3/4 in click order for Exacta/Quinella/Trifecta/Superfecta
			betting_ui._on_horse_selected(i)
		betting_ui.amount_option.select(0) # BET_LEVELS[0] == 10000

		# GDScript lambdas capture locals by value, not by reference, so a
		# plain int local wouldn't observe writes made inside the callback.
		# A Dictionary's contents are shared, so mutating it here does.
		var captured := {"picks": [], "amount": -1, "bet_type": -1}
		betting_ui.bet_placed.connect(func(picks, amt, btype):
			captured.picks = picks
			captured.amount = amt
			captured.bet_type = btype
		)
		betting_ui._on_race_pressed()

		assert(captured.picks.size() == needed, "bet_placed should report exactly %d pick(s)" % needed)
		for i in range(needed):
			assert(captured.picks[i] == i, "bet_placed should report picks in click order")
		assert(captured.amount == BettingUI.BET_LEVELS[0], "bet_placed should report the staked amount")
		assert(captured.bet_type == this_bet_type, "bet_placed should report the selected bet type")

		var accepted: bool = Bankroll.place_bet(captured.amount)
		assert(accepted, "Bankroll should accept an affordable bet")
		var after_stake: int = 100000 - captured.amount

		var result: RaceResult = RaceSim.simulate(field, tiers)
		var won: bool
		var payout: int = 0
		var picks: Array = captured.picks
		match this_bet_type:
			OddsTable.BetType.EXACTA:
				won = OddsTable.is_winning_exacta(result.finish_order, picks[0], picks[1])
				if won:
					payout = OddsTable.exacta_payout(captured.amount, tiers[picks[0]], tiers[picks[1]])
			OddsTable.BetType.QUINELLA:
				won = OddsTable.is_winning_quinella(result.finish_order, picks)
				if won:
					payout = OddsTable.multi_payout(captured.amount, [tiers[picks[0]], tiers[picks[1]]])
			OddsTable.BetType.TRIFECTA, OddsTable.BetType.SUPERFECTA:
				won = OddsTable.is_winning_exact_order(result.finish_order, picks)
				if won:
					var pick_tiers: Array[Dictionary] = []
					for p in picks:
						pick_tiers.append(tiers[p])
					payout = OddsTable.multi_payout(captured.amount, pick_tiers)
			_:
				won = OddsTable.is_winning_bet(result.finish_order, picks[0], captured.bet_type)
				if won:
					payout = OddsTable.payout(captured.amount, tiers[picks[0]], captured.bet_type)

		if won:
			wins_by_type[this_bet_type] += 1
			Bankroll.pay(payout)
			assert(Bankroll.balance == after_stake + payout, "balance should reflect the payout on a win")
		else:
			losses_by_type[this_bet_type] += 1
			assert(Bankroll.balance == after_stake, "balance should stay debited on a loss")

		betting_ui.queue_free() # avoid piling up 300 unfreed Control trees

	for bt in bet_types:
		print("bet_flow_check: %s — %d wins, %d losses" % [
			OddsTable.bet_type_label(bt), wins_by_type[bt], losses_by_type[bt],
		])
	print("bet_flow_check: %d trials — all assertions passed" % trials)
	get_tree().quit()

## Regression check for a real bug AJ hit: betting your ENTIRE balance (e.g.
## "All In") used to fire Bankroll.went_broke the instant the bet was
## PLACED — before the race even played, even on a bet about to win. Fixed
## by removing that check from place_bet entirely; went_broke now only
## fires from pay(), called unconditionally (0 on a loss) by every
## resolution path once a bet's outcome is actually known.
func _check_went_broke_timing() -> void:
	Bankroll.autosave_enabled = false
	var went_broke_count := {"n": 0} # Dictionary wrapper — a bare int local wouldn't observe a write made inside the lambda below (this project's own documented closure-capture gotcha)
	var on_went_broke := func(): went_broke_count.n += 1
	Bankroll.went_broke.connect(on_went_broke)

	Bankroll.balance = 10000
	assert(Bankroll.place_bet(10000), "an all-in bet should be accepted")
	assert(Bankroll.balance == 0, "the full balance should be staked")
	assert(went_broke_count.n == 0, "placing an all-in bet must NOT itself fire went_broke — that's the exact bug this fixes")

	Bankroll.pay(0) # every resolution path now calls pay() unconditionally, even on a total loss
	assert(went_broke_count.n == 1, "went_broke should fire once a bet actually RESOLVES with nothing left, not when it was placed")

	Bankroll.balance = 10000
	Bankroll.place_bet(10000)
	Bankroll.pay(20000) # a win — should never be treated as going broke
	assert(went_broke_count.n == 1, "a winning all-in bet must never trigger went_broke")

	Bankroll.went_broke.disconnect(on_went_broke)
	print("bet_flow_check: went_broke timing (all-in bet != instant bankrupt) OK")

## Independent hand-computed oracle for OddsTable, separate from the
## simulation loop above — catches bugs in is_winning_bet/decimal_multiplier
## themselves rather than just bugs in how Main/BettingUI call them.
func _check_odds_table_unit_cases() -> void:
	var order: Array[int] = [3, 1, 4, 0, 2] # horse 3 won, then 1, then 4, then 0, then 2

	assert(OddsTable.is_winning_bet(order, 3, OddsTable.BetType.WIN), "winner should hit a Win bet")
	assert(not OddsTable.is_winning_bet(order, 1, OddsTable.BetType.WIN), "runner-up should miss a Win bet")

	assert(OddsTable.is_winning_bet(order, 1, OddsTable.BetType.PLACE), "2nd place should hit a Place bet")
	assert(not OddsTable.is_winning_bet(order, 4, OddsTable.BetType.PLACE), "3rd place should miss a Place bet")

	assert(OddsTable.is_winning_bet(order, 4, OddsTable.BetType.SHOW), "3rd place should hit a Show bet")
	assert(not OddsTable.is_winning_bet(order, 2, OddsTable.BetType.SHOW), "4th place should miss a Show bet")

	assert(OddsTable.is_winning_exacta(order, 3, 1), "exact 1st+2nd order should hit an Exacta")
	assert(not OddsTable.is_winning_exacta(order, 1, 3), "reversed order should miss an Exacta")
	assert(not OddsTable.is_winning_exacta(order, 3, 4), "wrong 2nd place should miss an Exacta")

	var tier: Dictionary = {"num": 5, "den": 1, "label": "5/1"}
	assert(is_equal_approx(OddsTable.decimal_multiplier(tier, OddsTable.BetType.WIN), 6.0), "5/1 win should pay 6.0x")
	assert(is_equal_approx(OddsTable.decimal_multiplier(tier, OddsTable.BetType.PLACE), 3.5), "5/1 place should pay 3.5x at a 0.5 profit factor")
	assert(is_equal_approx(OddsTable.decimal_multiplier(tier, OddsTable.BetType.SHOW), 2.5), "5/1 show should pay 2.5x at a 0.3 profit factor")

	var tier2: Dictionary = {"num": 2, "den": 1, "label": "2/1"}
	# raw combined win odds: 6.0 * 3.0 = 18.0x profit-of-17, dampened 0.6 -> 1 + 17*0.6 = 11.2x
	assert(is_equal_approx(OddsTable.exacta_multiplier(tier, tier2), 11.2), "exacta multiplier should dampen the combined win odds")
	assert(is_equal_approx(OddsTable.daily_double_multiplier(tier, tier2), 11.2), "daily double uses the same combined-odds shape as exacta")

	assert(OddsTable.picks_required(OddsTable.BetType.WIN) == 1, "Win needs 1 pick")
	assert(OddsTable.picks_required(OddsTable.BetType.EXACTA) == 2, "Exacta needs 2 picks")
	assert(OddsTable.picks_required(OddsTable.BetType.QUINELLA) == 2, "Quinella needs 2 picks")
	assert(OddsTable.picks_required(OddsTable.BetType.TRIFECTA) == 3, "Trifecta needs 3 picks")
	assert(OddsTable.picks_required(OddsTable.BetType.SUPERFECTA) == 4, "Superfecta needs 4 picks")

	assert(OddsTable.is_winning_quinella(order, [3, 1]), "top-2 in click order should hit a Quinella")
	assert(OddsTable.is_winning_quinella(order, [1, 3]), "top-2 in EITHER order should hit a Quinella")
	assert(not OddsTable.is_winning_quinella(order, [3, 4]), "a non-top-2 horse should miss a Quinella")

	assert(OddsTable.is_winning_exact_order(order, [3, 1, 4]), "exact top-3 order should hit a Trifecta")
	assert(not OddsTable.is_winning_exact_order(order, [3, 4, 1]), "wrong 2nd/3rd order should miss a Trifecta")
	assert(OddsTable.is_winning_exact_order(order, [3, 1, 4, 0]), "exact top-4 order should hit a Superfecta")
	assert(not OddsTable.is_winning_exact_order(order, [3, 1, 4, 2]), "wrong 4th place should miss a Superfecta")

	assert(is_equal_approx(OddsTable.multi_multiplier([tier, tier2]), 11.2), "2-pick multi_multiplier should match exacta_multiplier's dampening")
	assert(OddsTable.multi_payout(100, [tier, tier2]) == OddsTable.exacta_payout(100, tier, tier2), "2-pick multi_payout should match exacta_payout")

	var tier3: Dictionary = {"num": 3, "den": 1, "label": "3/1"} # decimal 4.0x
	# combined 6.0*3.0*4.0 = 72.0x, profit-of-71, dampened 0.4 -> 1 + 71*0.4 = 29.4x
	assert(is_equal_approx(OddsTable.multi_multiplier([tier, tier2, tier3]), 29.4), "3-pick multi_multiplier should use the 3-pick dampening factor")

	var tier4: Dictionary = {"num": 8, "den": 1, "label": "8/1"} # decimal 9.0x
	# combined 6.0*3.0*4.0*9.0 = 648.0x, profit-of-647, dampened 0.28 -> 1 + 647*0.28 = 182.16x
	assert(is_equal_approx(OddsTable.multi_multiplier([tier, tier2, tier3, tier4]), 182.16), "4-pick multi_multiplier should use the 4-pick dampening factor")

	assert(OddsTable.format_money(1000000) == "$1,000,000", "format_money should comma-group large amounts")
	assert(OddsTable.format_money(100) == "$100", "format_money should not comma-group amounts under 1000")
	assert(OddsTable.format_money(-2500) == "-$2,500", "format_money should handle negative amounts")

	print("bet_flow_check: OddsTable unit cases passed")
