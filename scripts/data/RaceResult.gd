class_name RaceResult
extends RefCounted

var field: Array[RaceHorseState] = []
## One entry per simulation tick. Each entry holds, per horse (by field
## index), the fraction of the track covered so far (0..1) — this is the
## full replay data the race-visualization layer will read from later.
var frames: Array[PackedFloat32Array] = []
## Parallel to frames: per horse, lateral position at that tick in abstract
## lane units (0.0 = hugging the rail; RaceTrack3D scales by its own
## world-unit LANE_GAP). See RaceSim._lane_targets for how this is derived —
## lets horses run single-file at the rail when there's daylight between
## them and only spread out to pass when bunched, instead of each horse
## riding a fixed lane for the whole race.
var lane_offsets: Array[PackedFloat32Array] = []
## Parallel to frames: per horse, RaceHorseState.surge at that tick (see
## RaceSim.SURGE_REVERSION/SURGE_VOLATILITY) — lets the playback layer react
## to a horse actively "making a move" (big positive surge) with camera
## punches/speed lines/particle trails, without re-deriving surge from the
## position data (which is only the NET effect of surge + base speed +
## fatigue + noise all combined, not separable back out after the fact).
var surges: Array[PackedFloat32Array] = []
## Parallel to frames: per horse, the actual ground speed (sim-distance-units
## per second) it was covering that tick — lets the playback layer drive gait
## animation speed off real velocity (slows the leg-cycle during fatigue/the
## post-finish coast-down, speeds it up on a surge) instead of animating
## every horse at one fixed cadence regardless of how fast it's actually moving.
var speeds: Array[PackedFloat32Array] = []
var finish_order: Array[int] = [] # field indices, 1st place first
var duration: float = 0.0
