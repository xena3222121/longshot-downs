extends SceneTree

## Throwaway measurement, not a permanent dev tool — quantifies the SPATIAL
## margin between the winner and the rest of the field at the moment the
## winner crosses the line, in "lengths" (real racing convention: "beaten
## by N lengths" is a position gap at the winner's finish, not a time gap).
## Used to validate AJ's complaint ("worst loser ~25 lengths back, should be
## a max of ~8") and check RaceSim.MAX_GAP_FROM_LEADER is actually working.

## Same derivation as RaceSim.MAX_GAP_FROM_LEADER's comment: rail-lane
## perimeter ~443 world units/lap, TRACK_LENGTH/that ~8.8 sim-units per
## world-unit, ~2.4 world units per horse-length.
const SIM_UNITS_PER_LENGTH: float = 2.4 * (RaceSim.TRACK_LENGTH / (2.0 * 140.0 + 2.0 * PI * 26.0))

func _init() -> void:
	var roster: Array[Horse] = HorseRoster.generate()
	var trials: int = 200
	var total_worst_margin: float = 0.0
	var max_worst_margin: float = 0.0

	for t in range(trials):
		roster.shuffle()
		var field: Array[Horse] = roster.slice(0, 8)
		var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
		var result: RaceResult = RaceSim.simulate(field, tiers)

		var winner_idx: int = result.finish_order[0]
		var winner_time: float = result.field[winner_idx].finish_time
		var winner_tick: int = int(round(winner_time / RaceSim.DT))
		winner_tick = clamp(winner_tick, 0, result.frames.size() - 1)
		var frame: PackedFloat32Array = result.frames[winner_tick]

		var worst_fraction: float = 1.0
		for f in frame:
			worst_fraction = min(worst_fraction, f)
		var gap_distance: float = (1.0 - worst_fraction) * RaceSim.TRACK_LENGTH
		var gap_lengths: float = gap_distance / SIM_UNITS_PER_LENGTH

		total_worst_margin += gap_lengths
		max_worst_margin = max(max_worst_margin, gap_lengths)

	print("avg worst-loser margin at winner's finish: %.1f lengths" % (total_worst_margin / trials))
	print("max worst-loser margin seen: %.1f lengths" % max_worst_margin)
	quit()
