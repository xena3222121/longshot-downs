extends SceneTree

## Dev tool, not part of the game: run with
##   godot --headless --path . --script res://scripts/tools/lane_offset_check.gd
## Sanity-checks RaceSim's dynamic lane offsets: the field should fan out
## early (bunched at the gate) and mostly collapse back toward the rail
## (offset near 0) once the field has spread out along the back stretch.

func _init() -> void:
	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	var field: Array[Horse] = roster.slice(0, 8)
	var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
	var result: RaceResult = RaceSim.simulate(field, tiers)

	var early_index: int = int(result.frames.size() * 0.05)
	var late_index: int = int(result.frames.size() * 0.7)

	var early_offsets: PackedFloat32Array = result.lane_offsets[early_index]
	var late_offsets: PackedFloat32Array = result.lane_offsets[late_index]

	var early_max: float = 0.0
	for v in early_offsets:
		early_max = max(early_max, v)
	var late_avg: float = 0.0
	for v in late_offsets:
		late_avg += v
	late_avg /= late_offsets.size()

	print("frames: %d, duration: %.1fs" % [result.frames.size(), result.duration])
	print("early (tick %d) offsets: %s  (max %.2f)" % [early_index, str(early_offsets), early_max])
	print("late  (tick %d) offsets: %s  (avg %.2f)" % [late_index, str(late_offsets), late_avg])

	assert(early_max > 1.0, "field should fan out across multiple lanes near the start when bunched")
	assert(late_avg < early_max, "average offset late in the race should relax back toward the rail as the field spreads out")

	print("lane_offset_check: assertions passed")
	quit()
