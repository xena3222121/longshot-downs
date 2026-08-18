extends SceneTree

## Dev tool, not part of the game: run with
##   godot --headless --path . --script res://scripts/tools/sim_check.gd
## to sanity-check that odds tiers stay loosely (not tightly) correlated
## with actual race outcomes after any tuning change to RaceSim constants.

func _init() -> void:
	var roster: Array[Horse] = HorseRoster.generate()
	var trials: int = 2000
	var wins_by_tier_index: Dictionary = {}

	for t in range(trials):
		roster.shuffle()
		var field: Array[Horse] = roster.slice(0, 8)
		var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
		var result: RaceResult = RaceSim.simulate(field, tiers)
		var winner_idx: int = result.finish_order[0]
		var winner_tier_index: int = result.field[winner_idx].tier.get("index", -1)
		wins_by_tier_index[winner_tier_index] = wins_by_tier_index.get(winner_tier_index, 0) + 1

	print("Win rate by odds-tier index (0 = favorite, higher = longer shot) over %d races:" % trials)
	var keys: Array = wins_by_tier_index.keys()
	keys.sort()
	for k in keys:
		var wins: int = wins_by_tier_index[k]
		var pct: float = 100.0 * wins / trials
		print("  tier %d: %d wins (%.1f%%)" % [k, wins, pct])

	quit()
