class_name RaceHorseState
extends RefCounted

## Rolled fresh per race by RaceSim — never persisted on Horse itself.
var horse: Horse
var tier: Dictionary
var base_speed: float
var stamina: float
var consistency: float # 0..1, higher = smoother pace, less surge/fade
var distance: float = 0.0
var finish_time: float = -1.0 # seconds; -1 until it crosses the line

## A slowly wandering, mean-reverting speed offset (see RaceSim.SURGE_*) —
## unlike the independent per-tick noise, this persists for several seconds
## at a stretch, giving each horse sustained "making a move" / "fading"
## stretches instead of the field just sorting into its final order early
## and holding station for the rest of the race.
var surge: float = 0.0

## This horse's own personal tolerance for how far it lets itself fall
## behind the leader before RaceSim's soft catch-up starts reeling it back in
## (see RaceSim.CATCHUP_GAP_MIN_MULT/MAX_MULT) — rolled once per race so
## different horses in the same field settle at different distances off the
## pace instead of every trailing horse converging on one identical gap.
var catchup_gap: float = 0.0
