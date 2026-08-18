extends Node

## Dev tool, not part of the game: drives FinishPodium.setup() through every
## bet type (including the Quinella/Trifecta/Superfecta multi-pick types
## added alongside Career) against real RaceSim output, so runtime errors in
## the payout-resolution branches or the Career/achievement-toast hookup
## would actually surface — bet_flow_check.gd exercises OddsTable/BettingUI
## directly but never touches FinishPodium itself. Must run as a real scene
## (not via --script) for the autoloads:
##   godot --headless --path . res://scenes/tools/finish_podium_check.tscn

const TIME_SCALE: float = 20.0
const WAIT_FRAMES: int = 300

func _ready() -> void:
	Engine.time_scale = TIME_SCALE # FinishPodium's reveal beats use real wall-clock SceneTreeTimers — speed
		# them up the same way racetrack_playback_check.gd speeds up race playback, or WAIT_FRAMES worth of
		# real (uncapped, headless) frames finishes in far less wall-clock time than those timers need.
	Bankroll.autosave_enabled = false # never let these fake trials touch the real save file
	var bet_types: Array[OddsTable.BetType] = [
		OddsTable.BetType.WIN, OddsTable.BetType.PLACE, OddsTable.BetType.SHOW, OddsTable.BetType.EXACTA,
		OddsTable.BetType.QUINELLA, OddsTable.BetType.TRIFECTA, OddsTable.BetType.SUPERFECTA,
	]

	for bet_type in bet_types:
		Bankroll.balance = 1000
		var roster: Array[Horse] = HorseRoster.generate()
		roster.shuffle()
		var field: Array[Horse] = roster.slice(0, 8)
		HorseRoster.assign_race_colors(field)
		var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
		var result: RaceResult = RaceSim.simulate(field, tiers)

		var needed: int = OddsTable.picks_required(bet_type)
		var picks: Array[int] = []
		for i in range(needed):
			picks.append(i)

		var podium := FinishPodium.new()
		add_child(podium)
		podium.setup(field, result, {
			"bet_type": bet_type, "horse_index": picks[0], "second_index": picks[1] if picks.size() > 1 else -1,
			"picks": picks, "amount": 100, "dd_leg": 0,
		})

		# setup() is a coroutine (awaits its own reveal timers) — give it real
		# frames to actually run to completion instead of returning immediately.
		for i in range(WAIT_FRAMES):
			await get_tree().process_frame

		print("finish_podium_check: %s resolved with no runtime errors" % OddsTable.bet_type_label(bet_type))
		podium.queue_free()
		await get_tree().process_frame

	# Daily Double leg 1 (defers resolution, no bet outcome yet) — separate
	# code path (_build_leg1_continue) from every bet type above.
	Bankroll.balance = 1000
	var roster2: Array[Horse] = HorseRoster.generate()
	roster2.shuffle()
	var field2: Array[Horse] = roster2.slice(0, 8)
	HorseRoster.assign_race_colors(field2)
	var tiers2: Array[Dictionary] = OddsTable.assign_to_field(field2.size())
	var result2: RaceResult = RaceSim.simulate(field2, tiers2)
	var podium2 := FinishPodium.new()
	add_child(podium2)
	podium2.setup(field2, result2, {"dd_leg": 1})
	for i in range(WAIT_FRAMES):
		await get_tree().process_frame
	print("finish_podium_check: Daily Double leg 1 resolved with no runtime errors")
	podium2.queue_free()

	assert(Career.total_races > 0, "Career.record_finish should have run at least once")
	print("finish_podium_check: Career total_races=%d, current class=%s, achievements_unlocked=%d" % [
		Career.total_races, Career.get_current_class().name, Career.achievements_unlocked.size(),
	])
	print("finish_podium_check: all checks passed")
	get_tree().quit()
