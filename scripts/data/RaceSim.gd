class_name RaceSim
extends RefCounted

## TRACK_LENGTH and DISTANCE_PER_STAMINA are scaled up together (originally
## 1000/8.0, then 5x to 5000/40.0 for a ~minute-long race, dialed back to
## 3900/31.2 to feel less draggy, then — after the tighter-finish-margin pass
## further down this file also shortened races — measured at 43.33s average
## over 300 trials via scripts/tools/duration_calibration_check.gd (a
## throwaway, deleted after use) and scaled back up ~1.4615x to 5700/45.6 for
## AJ's "make races take like 20 seconds longer" ask) without touching any
## speed/rate constant below — fatigue_distance (state.stamina *
## DISTANCE_PER_STAMINA) stays the same FRACTION of TRACK_LENGTH either way,
## so the fatigue-onset point in the race and the resulting win-rate/odds
## correlation are unchanged; only the real duration and physical distance
## change. Scaling only one of the two would shift fatigue to a different
## fraction of the race and change the whole game's balance.
## LANE_CONFLICT_DISTANCE and MAX_GAP_FROM_LEADER below are both scaled by
## the same factor for the same reason — each represents a fixed real-world
## distance (a horse-length gap, an ~8-length maximum spread), not a
## fraction of TRACK_LENGTH, and would otherwise silently represent a
## different physical distance once TRACK_LENGTH changed.
const TRACK_LENGTH: float = 5700.0
const DT: float = 0.05
const MAX_TICKS: int = 3000 # 150s safety cap so a pathological roll can't hang

const BASE_SPEED: float = 100.0
const SPEED_STEP: float = 1.6   # mean speed drop per odds-tier index (favorite -> longshot) — lowered from 2.5 (AJ: "double the win rate of the longest shot"), tuned empirically via sim_check.gd until tier 7 landed near 2x its old ~2.5% win rate
const SPEED_SIGMA: float = 6.0  # roll spread; large vs SPEED_STEP so tiers overlap heavily
## Extra flat mean-speed bonus for tier 0 (the favorite) ONLY — AJ then asked
## for the favorite's own win rate bumped back up too ("make the favorite
## also win by 5 percent more") without undoing the longshot boost above,
## which a uniform SPEED_STEP increase would have done (it would have
## widened EVERY tier gap equally, pushing tier 7 back down too). Tuned
## empirically via sim_check.gd until tier 0 landed ~5 percentage points
## above its post-SPEED_STEP-change level (23.4% -> ~28%, coincidentally
## close to its original pre-change level, with tier 7 left alone).
const FAVORITE_BONUS: float = 2.2

const STAMINA_MIN: float = 60.0
const STAMINA_MAX: float = 140.0
const DISTANCE_PER_STAMINA: float = 45.6 # fatigue starts past stamina * this distance

const CONSISTENCY_MIN: float = 0.4
const CONSISTENCY_MAX: float = 1.0
const NOISE_SCALE: float = 15.0   # per-tick speed noise at zero consistency
const FATIGUE_STRENGTH: float = 0.35 # max speed loss once fully fatigued

## Per-tick noise above is independent from tick to tick, so over thousands
## of ticks it averages out fast — the field sorts into its speed-roll order
## within the first furlong or two and then just holds station, which reads
## as boring to watch. `surge` is a mean-reverting random walk (an
## Ornstein-Uhlenbeck process) layered on top: SURGE_REVERSION is the
## per-second pull back toward zero (half-life ln(2)/0.12 ≈ 5.8s, so a surge
## lasts several real seconds, not one tick) and SURGE_VOLATILITY is tuned so
## its long-run spread (stationary stddev = volatility/sqrt(2*reversion) ≈
## 11) rivals SPEED_SIGMA, contesting the tier-based speed gaps hard enough
## to produce real mid-race lead changes (measured via
## scripts/tools/lead_change_check.gd) without erasing them outright.
## Zero-mean and identical for every horse regardless of tier, so it
## doesn't bias which tier wins on average (verified via sim_check.gd's
## win-rate-by-tier breakdown) — it just adds sustained swings that cause
## real mid-race lead changes instead of only a fixed early sort.
const SURGE_REVERSION: float = 0.12
const SURGE_VOLATILITY: float = 5.4

## How long (seconds) a horse keeps galloping past the finish line before
## easing to a stop, instead of freezing dead on the wire the instant it
## crosses. Purely cosmetic — finish_time/finish_order (and every payout
## that depends on them) are still recorded at the exact moment of crossing
## TRACK_LENGTH, below; this only affects what the frames afterward look
## like, not who won or when.
const COAST_DURATION: float = 3.0

## How close two horses' `distance` values need to be before they're treated
## as contesting the same patch of track and need lateral separation. This
## is in the same units as TRACK_LENGTH. Empirically calibrated (via
## scripts/tools/lane_offset_check.gd) at ~0.83x MAX_GAP_FROM_LEADER — the
## SAME ratio the original 140/170 pair had — after a naive proportional
## scale-with-TRACK_LENGTH attempt (205, alongside MAX_GAP_FROM_LEADER's own
## bad first guess of 248) landed ABOVE the recalibrated MAX_GAP_FROM_LEADER
## and broke the intended dynamic entirely: with this value larger than the
## field's own typical max spread, literally every horse stayed within
## "contesting" range for the whole race, so the field never collapsed back
## to single file down the stretch (measured: late-race lane offsets
## averaged 3.5, should be near 0). This constant MUST stay smaller than
## MAX_GAP_FROM_LEADER for that collapse-to-rail behavior to exist at all —
## keep that invariant true after any future retuning of either one.
## Tight packs (like right out of the gate, when every horse is still near
## distance 0) fall inside this window and fan out across lanes; as the
## field spreads out from fatigue/pace differences, most horses drift
## outside it and collapse back toward the rail — this is what produces a
## natural bunched-then-single-file look instead of fixed parallel lanes.
const LANE_CONFLICT_DISTANCE: float = 85.0

## Seconds for a horse's rendered lane offset to close ~63% of the distance
## to its newly-assigned target lane. Smooths lane changes (fanning out to
## pass, tucking back to the rail once clear) into a fluid drift instead of
## a snap — same exponential-smoothing shape RaceTrack3D's chase camera uses.
const LANE_SMOOTH_TIME: float = 0.5

## Bounds how far behind the leader a still-racing horse is allowed to drift
## — "beaten by N lengths" in real racing means the loser's position was N
## horse-lengths behind the winner's AT THE MOMENT the winner crossed the
## line (a spatial gap, not a time gap), so this is enforced directly as a
## distance bound rather than by trying to tune every speed/fatigue/noise
## source down until times happen to land close together. 103 is empirically
## calibrated (via scripts/tools/finish_spread_check.gd) to land at ~8
## lengths average again after TRACK_LENGTH was scaled up for AJ's "make
## races take ~20s longer" ask — NOT derived by scaling the old ~170 value
## (which was itself geometrically derived from TRACK_LENGTH/world-scale) by
## the same ratio TRACK_LENGTH changed by: that first attempt (248, i.e.
## 170 * 5700/3900) measured at 14.7 lengths average, nearly double the
## target. The reason a pure proportional scale doesn't hold: BASE_SPEED/
## SPEED_SIGMA/SURGE_VOLATILITY/NOISE_SCALE below are all fixed absolute
## values, untouched by the TRACK_LENGTH change — a longer race means more
## ticks to cover it at the same speed, and the surge/noise random-walk
## accumulates spread roughly with elapsed TIME (ticks), not with
## TRACK_LENGTH, so a longer race needs a SMALLER catch-up gap (as a
## fraction of the old proportional guess) to hold the same real-world
## length spread, not a larger one. Re-measure via finish_spread_check.gd
## after any future TRACK_LENGTH change rather than re-deriving this
## geometrically — same lesson, don't repeat the mistake. This is the MEAN
## of a per-horse target (see CATCHUP_GAP_MIN_MULT/MAX_MULT
## below), not a shared hard floor — an earlier version snapped every
## trailing horse's distance straight to exactly `leader_distance - 170`
## every tick, which meant any horse that would have fallen further behind
## than that got teleported to the SAME distance as every other clamped
## horse, so the back of the field visually clumped into one identical
## rank-and-file line at the finish (measured at the time: ~7.9 lengths
## average AND ~8.1 lengths max across 200 trials — suspiciously little
## race-to-race variance, which is exactly what made it read as fake). The
## fix keeps the same overall "don't let the field spread out 80 lengths"
## intent (see CATCHUP_TIME below for how it's now applied) but gives each
## horse its own tolerance and only pulls it toward that gradually, so
## trailing horses settle at different, race-varying distances instead of
## one shared number. Only ever pulls a trailing horse UP toward the leader,
## never holds the leader back, so it still can't change who wins (see
## sim_check.gd) — it only bounds how far the rest of the field can fall.
const MAX_GAP_FROM_LEADER: float = 103.0

## Per-horse spread multiplier applied to MAX_GAP_FROM_LEADER (rolled once
## per horse at race start, see RaceHorseState.catchup_gap) — gives a
## realistic mix of horses that hang close to the pace and horses that
## legitimately fall well off it, instead of every straggler tolerating the
## exact same gap.
const CATCHUP_GAP_MIN_MULT: float = 0.5
const CATCHUP_GAP_MAX_MULT: float = 1.9

## Time constant (seconds) for how fast a horse beyond its own catchup_gap
## gets reeled back toward the leader — same exponential-smoothing shape as
## LANE_SMOOTH_TIME, just slower, so it reads as a horse visibly working to
## not get left behind rather than an instant snap. Deliberately slow enough
## that a horse that falls far behind late in the race won't fully close the
## gap before the leader finishes — real races don't guarantee everyone
## reels themselves back to a tidy tolerance band in time either.
const CATCHUP_TIME: float = 3.0

## Individualizing catchup_gap (above) means some horses now legitimately
## take much longer than others to physically reach TRACK_LENGTH under their
## own power — without a bound, one extreme-bad-luck straggler could stretch
## a whole race out for many extra real seconds waiting for it alone to
## cross, which is its own kind of unrealistic (real broadcasts don't hold
## the result until the tail of the field finishes either). Once this many
## seconds have passed since the FIRST horse crossed the line, the race is
## considered decided: any horse still short of the line gets its finish
## order settled (see the "hit the safety cap" fallback at the end of
## simulate()) rather than waiting for it to physically finish.
const FIELD_CUTOFF_AFTER_LEADER: float = 8.0

## Rolls fresh per-race performance for each horse in `field` and simulates
## the race tick by tick. `tiers[i]` is the odds tier assigned to `field[i]`
## (must include the "index" key set by OddsTable.assign_to_field). The tier
## only nudges a horse's *mean* speed — roll variance is wide enough that
## favorites regularly lose to longshots. Returns a RaceResult with the full
## per-tick position history for replay plus the final finish order.
static func simulate(field: Array[Horse], tiers: Array[Dictionary]) -> RaceResult:
	var result := RaceResult.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for i in range(field.size()):
		var state := RaceHorseState.new()
		state.horse = field[i]
		state.tier = tiers[i]

		var tier_index: int = tiers[i].get("index", i)
		var mean_speed: float = BASE_SPEED - tier_index * SPEED_STEP
		if tier_index == 0:
			mean_speed += FAVORITE_BONUS
		state.base_speed = mean_speed + rng.randfn(0.0, SPEED_SIGMA)
		state.stamina = rng.randf_range(STAMINA_MIN, STAMINA_MAX)
		state.consistency = rng.randf_range(CONSISTENCY_MIN, CONSISTENCY_MAX)
		state.catchup_gap = MAX_GAP_FROM_LEADER * rng.randf_range(CATCHUP_GAP_MIN_MULT, CATCHUP_GAP_MAX_MULT)

		result.field.append(state)

	var tick: int = 0
	var finished_count: int = 0
	var first_finish_time: float = -1.0
	var lane_offsets := PackedFloat32Array()
	lane_offsets.resize(result.field.size()) # all start at 0.0 (rail), smoothed toward a fresh target every tick below
	while finished_count < result.field.size() and tick < MAX_TICKS:
		var frame := PackedFloat32Array()
		var speed_frame := PackedFloat32Array()
		frame.resize(result.field.size())
		speed_frame.resize(result.field.size())

		for i in range(result.field.size()):
			var state: RaceHorseState = result.field[i]
			var has_finished: bool = state.finish_time >= 0.0
			var time_since_finish: float = (tick * DT - state.finish_time) if has_finished else 0.0
			var effective_speed: float = 0.0 # stays 0 once a horse has fully eased to a stop

			if not has_finished or time_since_finish < COAST_DURATION:
				var fatigue_distance: float = state.stamina * DISTANCE_PER_STAMINA
				var fatigue_mult: float = 1.0
				if state.distance > fatigue_distance:
					var remaining: float = (state.distance - fatigue_distance) / max(TRACK_LENGTH - fatigue_distance, 1.0)
					remaining = clamp(remaining, 0.0, 1.0)
					fatigue_mult = 1.0 - FATIGUE_STRENGTH * remaining

				state.surge += -SURGE_REVERSION * state.surge * DT + rng.randfn(0.0, SURGE_VOLATILITY * sqrt(DT))

				var noise: float = rng.randfn(0.0, (1.0 - state.consistency) * NOISE_SCALE)
				effective_speed = max(state.base_speed * fatigue_mult + state.surge + noise, BASE_SPEED * 0.2)
				if has_finished:
					effective_speed *= 1.0 - (time_since_finish / COAST_DURATION) # ease down to a stop, not an abrupt cutoff

				state.distance += effective_speed * DT
				if not has_finished and state.distance >= TRACK_LENGTH:
					state.finish_time = tick * DT
					finished_count += 1
					if first_finish_time < 0.0:
						first_finish_time = state.finish_time

			frame[i] = state.distance / TRACK_LENGTH
			speed_frame[i] = effective_speed

		var leader_distance: float = 0.0
		for state in result.field:
			leader_distance = max(leader_distance, state.distance)
		var catchup_t: float = 1.0 - exp(-DT / CATCHUP_TIME)
		for state in result.field:
			if state.finish_time < 0.0:
				# Capped below TRACK_LENGTH so catch-up can never itself carry an
				# unfinished horse across the line while the leader is still
				# coasting past it (finish_time is only ever set by the horse's
				# own effective_speed crossing TRACK_LENGTH, above) — without this
				# cap a small catchup_gap plus a leader well past the line during
				# its coast-down could push floor_distance above TRACK_LENGTH,
				# leaving that horse's finish_time never set and the whole race
				# stuck simulating ticks until MAX_TICKS.
				var floor_distance: float = min(leader_distance - state.catchup_gap, TRACK_LENGTH - 1.0)
				if state.distance < floor_distance:
					state.distance = lerp(state.distance, floor_distance, catchup_t)
		for i in range(result.field.size()):
			frame[i] = result.field[i].distance / TRACK_LENGTH

		var lane_targets: PackedFloat32Array = _lane_targets(result.field)
		var lane_smooth_t: float = 1.0 - exp(-DT / LANE_SMOOTH_TIME)
		for i in range(lane_offsets.size()):
			lane_offsets[i] = lerp(lane_offsets[i], lane_targets[i], lane_smooth_t)

		var surge_frame := PackedFloat32Array()
		surge_frame.resize(result.field.size())
		for i in range(result.field.size()):
			surge_frame[i] = result.field[i].surge

		result.frames.append(frame)
		result.lane_offsets.append(lane_offsets.duplicate())
		result.surges.append(surge_frame)
		result.speeds.append(speed_frame)
		tick += 1
		if first_finish_time >= 0.0 and tick * DT - first_finish_time >= FIELD_CUTOFF_AFTER_LEADER:
			break

	result.duration = tick * DT

	for state in result.field:
		if state.finish_time < 0.0:
			# Hit MAX_TICKS or the FIELD_CUTOFF_AFTER_LEADER grace window without
			# reaching TRACK_LENGTH under its own power. Still-short horses are
			# ordered by how far short they were (not all lumped at the same
			# finish_time) so their relative placing stays meaningful even
			# though none of them physically crossed the line.
			var shortfall: float = TRACK_LENGTH - state.distance
			state.finish_time = result.duration + max(shortfall, 0.0) * 0.01

	var indices: Array[int] = []
	for i in range(result.field.size()):
		indices.append(i)
	indices.sort_custom(func(a, b): return result.field[a].finish_time < result.field[b].finish_time)
	result.finish_order = indices

	return result

## Greedy lane assignment for a single tick, in abstract lane units (0 = rail).
## Sorts horses by distance descending — the leader gets first claim on the
## rail — then walks down that order handing each horse the innermost lane
## that doesn't sit within LANE_CONFLICT_DISTANCE of an already-placed horse
## occupying a lane less than one lane-step away. Horses with no nearby
## rival default to lane 0; only genuinely contested horses fan outward, and
## only as far as needed to clear the horses ahead of them in the claim order.
static func _lane_targets(field: Array[RaceHorseState]) -> PackedFloat32Array:
	var order: Array[int] = []
	for i in range(field.size()):
		order.append(i)
	order.sort_custom(func(a, b): return field[a].distance > field[b].distance)

	var targets := PackedFloat32Array()
	targets.resize(field.size())
	var placed: Array[int] = []

	for idx in order:
		var lane: int = 0
		while true:
			var conflict: bool = false
			for other in placed:
				if abs(field[idx].distance - field[other].distance) < LANE_CONFLICT_DISTANCE \
						and abs(targets[other] - float(lane)) < 1.0:
					conflict = true
					break
			if not conflict:
				break
			lane += 1
		targets[idx] = float(lane)
		placed.append(idx)

	return targets
