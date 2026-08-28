extends Node

## Permanent dev tool for CareerStable's Phase 1 economy/training loop and
## its RaceSim hook — no UI exists yet (Phase 2), so this is the only way to
## verify the actual mechanics before building screens on top of them.
## Isolated from real save files/balance the same way scheduler_check.gd
## isolates Bankroll (see this project's own memory on why that matters).

func _ready() -> void:
	Bankroll.autosave_enabled = false
	Bankroll.balance = 1000000
	CareerStable.autosave_enabled = false
	CareerStable.owned_horses = {}
	CareerStable._next_id = CareerStable.ID_START
	CareerStable._has_picked_starter = false

	_check_starter_pick()
	_check_training_gate_and_potential_cap()
	_check_trainer_upkeep()
	_check_race_sim_hook()
	_check_save_load_roundtrip()

	print("career_stable_check: all checks passed")
	get_tree().quit()

func _check_starter_pick() -> void:
	var id: int = CareerStable.pick_starter_horse(2) # Late Charge, closing_kick specialty
	assert(id >= CareerStable.ID_START, "starter pick should return a valid id")
	assert(CareerStable.get_attribute_level(id, "closing_kick") == 2, "40 starter points / 20 per level should be level 2")
	assert(CareerStable.get_attribute_level(id, "acceleration") == 0, "non-specialty attributes should start untrained")
	assert(CareerStable.get_attribute_level(id, "stamina") == 0, "non-specialty attributes should start untrained")
	assert(CareerStable.pick_starter_horse(0) == -1, "a second starter pick should be refused")
	print("career_stable_check: starter pick OK (id=%d)" % id)

func _check_training_gate_and_potential_cap() -> void:
	var id: int = CareerStable.get_owned_horse_ids()[0]
	var balance_before: int = Bankroll.balance
	assert(CareerStable.self_train(id, "acceleration"), "self-train should succeed with plenty of balance and no training yet today")
	assert(Bankroll.balance == balance_before - CareerStable.SELF_TRAIN_ITEM_COST, "self-train should deduct its item cost")
	assert(not CareerStable.can_train_today(id), "a second training action the same day should be gated")
	assert(not CareerStable.self_train(id, "stamina"), "self-train should be refused once already trained today")

	# Force-advance "today" by backdating last_trained_date directly (test-only
	# technique — real play waits for the actual calendar day to roll over)
	# and hammer training past the "starter" origin's potential_cap (3) to
	# confirm points clamp instead of climbing forever.
	var cap_points: int = CareerStable.get_potential_cap(id) * CareerStable.POINTS_PER_LEVEL
	for i in range(20):
		var horse: Dictionary = CareerStable.get_owned_horse(id)
		horse.last_trained_date = "2000-01-01"
		CareerStable.owned_horses[str(id)] = horse
		CareerStable.self_train(id, "acceleration")
	assert(CareerStable.get_attribute_points(id, "acceleration") == cap_points, "training should clamp at the origin's potential cap, not climb past it")
	print("career_stable_check: daily training gate + potential cap clamp OK")

func _check_trainer_upkeep() -> void:
	var id: int = CareerStable.purchase_horse("local_bred", "Test Purchase")
	assert(id >= CareerStable.ID_START, "purchasing a second horse should succeed with plenty of balance")
	CareerStable.hire_trainer(id, "elite")
	CareerStable.set_training_focus(id, "stamina")
	var points_before: int = CareerStable.get_attribute_points(id, "stamina")
	var balance_before: int = Bankroll.balance
	CareerStable.process_daily_trainer_upkeep()
	var elite_gain: int = int(CareerStable.get_trainer_tier("elite").gain)
	assert(CareerStable.get_attribute_points(id, "stamina") == points_before + elite_gain, "hired trainer should train the focus attribute automatically")
	assert(Bankroll.balance == balance_before - int(CareerStable.get_trainer_tier("elite").daily_cost), "hired trainer's daily fee should be charged")
	var balance_before_second_call: int = Bankroll.balance
	CareerStable.process_daily_trainer_upkeep()
	assert(Bankroll.balance == balance_before_second_call, "trainer upkeep should not double-charge the same day")
	print("career_stable_check: hired trainer daily upkeep OK")

## The part that actually matters for gameplay: do trained attribute levels
## make a statistically real difference in RaceSim, not just numbers that go
## up on a screen. Two otherwise-identical horses (same tier, so no tier-
## based systematic edge), one maxed on all three attributes, run many
## trials and confirm the trained horse wins a large majority.
func _check_race_sim_hook() -> void:
	var field: Array[Horse] = [Horse.new(), Horse.new()]
	field[0].id = 9001
	field[0].horse_name = "Trained"
	field[1].id = 9002
	field[1].horse_name = "Untrained"
	var tiers: Array[Dictionary] = [
		{"index": 3, "num": 4, "den": 1, "label": "4/1"},
		{"index": 3, "num": 4, "den": 1, "label": "4/1"},
	]
	var overrides: Dictionary = {
		0: {"acceleration_level": CareerStable.MAX_LEVEL, "stamina_level": CareerStable.MAX_LEVEL, "closing_kick_level": CareerStable.MAX_LEVEL},
	}

	var trained_wins: int = 0
	const TRIALS: int = 300
	for i in range(TRIALS):
		var result: RaceResult = RaceSim.simulate(field, tiers, overrides)
		if result.finish_order[0] == 0:
			trained_wins += 1
	var win_rate: float = float(trained_wins) / float(TRIALS)
	assert(win_rate > 0.75, "a fully-trained horse should win the large majority of races against an identical-tier untrained rival (got %.1f%%)" % (win_rate * 100.0))
	print("career_stable_check: RaceSim attribute_overrides hook OK (trained horse won %.1f%% of %d trials)" % [win_rate * 100.0, TRIALS])

func _check_save_load_roundtrip() -> void:
	var scratch_path: String = "user://career_stable_check_scratch.save"
	if FileAccess.file_exists(scratch_path):
		DirAccess.remove_absolute(scratch_path)
	var real_path: String = CareerStable.SAVE_PATH
	CareerStable.SAVE_PATH = scratch_path
	CareerStable.autosave_enabled = true

	var id: int = CareerStable.get_owned_horse_ids()[0]
	var points_before: int = CareerStable.get_attribute_points(id, "acceleration")
	CareerStable._save()

	CareerStable.owned_horses = {}
	CareerStable._next_id = CareerStable.ID_START
	CareerStable._has_picked_starter = false
	CareerStable._load()

	assert(CareerStable.get_attribute_points(id, "acceleration") == points_before, "loaded state should match what was saved")
	assert(CareerStable.has_picked_starter(), "has_picked_starter should round-trip through save/load")

	CareerStable.autosave_enabled = false
	CareerStable.SAVE_PATH = real_path
	if FileAccess.file_exists(scratch_path):
		DirAccess.remove_absolute(scratch_path)
	print("career_stable_check: save/load round-trip OK")
