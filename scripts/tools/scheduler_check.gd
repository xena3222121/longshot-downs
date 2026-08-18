extends Node

## Dev tool, not part of the game: RaceScheduler drives a fixed number of
## simultaneous viewing "screens" (any venue can be assigned to one), plus
## every OTHER venue resolving silently in the background — this drives one
## full cycle on both paths: a bet on a venue assigned to screen 0 (should
## hand off via race_ready, exactly like TrackLobby would receive it) and a
## bet on a venue with NO screen assigned (should resolve via
## background_result, no visual playback involved). Speeds up real time via
## Engine.time_scale so POST_INTERVAL (240s) doesn't take 4 real minutes to
## observe. Must run as a real scene (--path ., not --script) for autoloads:
##   godot --headless --path . res://scenes/tools/scheduler_check.tscn

const TIME_SCALE: float = 120.0
const SCREEN_VENUE: String = "longshot_downs" # screen 0's default assignment
const UNWATCHED_VENUE: String = "barton_bay"

func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	assert(RaceScheduler.screen_venue_ids[0] == SCREEN_VENUE, "test assumes screen 0's default assignment")
	assert(RaceScheduler.screen_venue_ids[1] == "", "test assumes screen 1 starts unassigned")

	# Also exercise assigning a SECOND venue to screen 1 concurrently — the
	# actual "watch two races at once" ask this scheduler exists for. Done
	# BEFORE begin_watching() so both screen-assigned venues get the fixed
	# INITIAL_SCREEN_COUNTDOWN seed, not a staggered fraction.
	var second_screen_venue: String = "el_cid"
	assert(RaceScheduler.set_screen_venue(1, second_screen_venue), "assigning a second venue to screen 1 should succeed")
	assert(RaceScheduler.screen_for(second_screen_venue) == 1, "el_cid should now be reported as occupying screen 1")

	# Ticking is gated on this — without it, _process would never advance any
	# countdown at all (the fix for AJ's "stuck live" bug: nothing ticks
	# until something is actually here to receive race_ready).
	RaceScheduler.begin_watching()
	assert(is_equal_approx(RaceScheduler.get_countdown(SCREEN_VENUE), RaceScheduler.INITIAL_SCREEN_COUNTDOWN), "a screen-assigned venue should seed to the fixed initial countdown, not a staggered fraction")

	var balance_before: int = Bankroll.balance
	assert(RaceScheduler.place_bet(SCREEN_VENUE, 0, OddsTable.BetType.WIN, 1000), "placing the screened-venue bet should succeed")
	assert(RaceScheduler.place_bet(UNWATCHED_VENUE, 0, OddsTable.BetType.WIN, 1000), "placing the unwatched-venue bet should succeed")
	assert(Bankroll.balance == balance_before - 2000, "both bets should have been deducted")
	assert(RaceScheduler.has_bet(SCREEN_VENUE) and RaceScheduler.has_bet(UNWATCHED_VENUE), "both venues should show a pending bet")

	var state := {"race_ready_screens": {}, "background": false, "bg_venue": ""}
	RaceScheduler.race_ready.connect(func(venue_id: String, screen: int, _result: RaceResult, _bet_context: Dictionary):
		state.race_ready_screens[venue_id] = screen
	)
	RaceScheduler.background_result.connect(func(venue_id: String, _description: String, _won: bool, _payout: int):
		state.background = true
		state.bg_venue = venue_id
	)

	var max_frames: int = int((RaceScheduler.POST_INTERVAL / TIME_SCALE) * 60.0 * 5.0) + 300
	var frame_count: int = 0
	while (state.race_ready_screens.size() < 2 or not state.background) and frame_count < max_frames:
		if frame_count % 60 == 0:
			print("frame %d / %d (screen0 countdown=%.1f, screen1 countdown=%.1f, unwatched countdown=%.1f)" % [
				frame_count, max_frames,
				RaceScheduler.get_countdown(SCREEN_VENUE), RaceScheduler.get_countdown(second_screen_venue), RaceScheduler.get_countdown(UNWATCHED_VENUE),
			])
		await get_tree().process_frame
		frame_count += 1

	assert(state.race_ready_screens.get(SCREEN_VENUE) == 0, "race_ready should have fired for screen 0's venue with screen index 0")
	assert(state.race_ready_screens.get(second_screen_venue) == 1, "race_ready should have fired for screen 1's venue with screen index 1 — BOTH screens racing simultaneously")
	assert(state.background, "background_result should have fired for the unwatched venue by now")
	assert(state.bg_venue == UNWATCHED_VENUE, "background_result should have fired for the unwatched venue specifically")
	assert(RaceScheduler.is_racing(SCREEN_VENUE) and RaceScheduler.is_racing(second_screen_venue), "both screened venues should be paused (is_racing) awaiting their visual flows to finish them")
	assert(not RaceScheduler.has_bet(UNWATCHED_VENUE), "the unwatched venue's bet should already be cleared after silent resolution")

	# Simulates what TrackLobby does once each screen's RaceTrack3D/
	# BroadcastHUD/replay/FinishPodium (already covered by
	# racetrack_playback_check.tscn) finish playing that screen's race out.
	RaceScheduler.finish_watched_race(SCREEN_VENUE)
	RaceScheduler.finish_watched_race(second_screen_venue)
	assert(not RaceScheduler.is_racing(SCREEN_VENUE) and not RaceScheduler.is_racing(second_screen_venue), "finish_watched_race should unpause both venues")
	assert(RaceScheduler.get_countdown(SCREEN_VENUE) > RaceScheduler.POST_INTERVAL - 1.0, "finish_watched_race should reset the countdown to a fresh POST_INTERVAL")

	print("scheduler_check: full cycle (two simultaneous screen handoffs + unwatched background resolution) completed with no runtime errors after %d real frames" % frame_count)
	get_tree().quit()
