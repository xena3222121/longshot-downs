extends SceneTree

## Throwaway measurement, not a permanent dev tool — counts how many times
## the race leader changes over a race, and how early the field settles
## into its final order, across many trials. Used to quantify "races get
## boring because the field sorts into position in the first couple
## furlongs and then nothing changes" before/after tuning RaceSim.

## A raw tick-to-tick leader swap includes meaningless 1-tick (0.05s) noise
## flicker a viewer would never perceive as "a lead change" — only count one
## once the new leader holds it for at least this long.
const MIN_HOLD_SECONDS: float = 1.0

func _init() -> void:
	var roster: Array[Horse] = HorseRoster.generate()
	var trials: int = 200
	var total_sustained_changes: int = 0
	var total_final_order_lock_fraction: float = 0.0

	for t in range(trials):
		roster.shuffle()
		var field: Array[Horse] = roster.slice(0, 8)
		var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
		var result: RaceResult = RaceSim.simulate(field, tiers)
		var min_hold_ticks: int = int(MIN_HOLD_SECONDS / RaceSim.DT)

		var sustained_changes: int = 0
		var current_leader: int = -1
		var current_leader_since: int = 0
		var lock_tick: int = 0 # last tick the eventual winner did NOT hold the lead
		var winner: int = result.finish_order[0]

		for tick in range(result.frames.size()):
			var frame: PackedFloat32Array = result.frames[tick]
			var leader: int = 0
			for i in range(1, frame.size()):
				if frame[i] > frame[leader]:
					leader = i
			if leader != current_leader:
				if current_leader != -1 and tick - current_leader_since >= min_hold_ticks:
					sustained_changes += 1
				current_leader = leader
				current_leader_since = tick
			if leader != winner:
				lock_tick = tick

		total_sustained_changes += sustained_changes
		total_final_order_lock_fraction += float(lock_tick) / result.frames.size()

	print("avg SUSTAINED (>=%.0fs held) lead changes per race: %.2f" % [MIN_HOLD_SECONDS, float(total_sustained_changes) / trials])
	print("avg fraction of race before winner takes the lead for good: %.2f" % (total_final_order_lock_fraction / trials))
	quit()
