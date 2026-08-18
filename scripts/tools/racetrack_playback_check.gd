extends Node

## Dev tool, not part of the game: actually drives RaceTrack3D through a
## full race (not just RaceSim.simulate() in isolation) so runtime errors in
## the "arcade excess"/broadcast-HUD playback code — surge handling, camera
## shake/punch-zoom, HorseMarker3D's particle trail,
## BroadcastHUD — would actually surface. Lets Godot's own engine drive
## _process() normally (add_child + play(), not manually calling
## race_track._process() in a synchronous script loop — that bypasses
## enough of the engine's real per-frame machinery that it behaves
## unpredictably) and speeds up simulated time via Engine.time_scale so a
## ~45s race finishes in a couple of real seconds of actual engine frames.
## Waits on frame COUNT (await get_tree().process_frame), not a real-world
## wall-clock timer (SceneTree timers track actual elapsed time regardless
## of time_scale, so they don't shrink the real wait the way this does).
## Must run as a real scene (--path ., not --script) for autoloads:
##   godot --headless --path . res://scenes/tools/racetrack_playback_check.tscn

const TIME_SCALE: float = 20.0
const PROGRESS_EVERY_N_FRAMES: int = 60

func _ready() -> void:
	Engine.time_scale = TIME_SCALE

	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	var field: Array[Horse] = roster.slice(0, 8)
	HorseRoster.assign_race_colors(field)
	var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
	var result: RaceResult = RaceSim.simulate(field, tiers)

	var race_track := RaceTrack3D.new()
	add_child(race_track)
	race_track.setup(field, result)
	race_track.play()

	# A plain bool local wouldn't observe a write made inside the lambda below
	# (GDScript closures capture locals by value, not by reference — same
	# gotcha bet_flow_check.gd documents) — a Dictionary's contents are
	# shared, so mutating it here does.
	var state := {"finished": false}
	race_track.playback_finished.connect(func(): state.finished = true)

	# Real frames needed ~= (race duration / time_scale) * assumed_fps, with
	# generous headroom — this is a safety cap on FRAME COUNT, not seconds.
	var max_frames: int = int((result.duration / TIME_SCALE) * 60.0 * 5.0) + 300
	var frame_count: int = 0
	while not state.finished and frame_count < max_frames:
		if frame_count % PROGRESS_EVERY_N_FRAMES == 0:
			print("frame %d / %d (playback_time=%.1f/%.1f)" % [frame_count, max_frames, race_track.playback_time, result.duration])
		await get_tree().process_frame
		frame_count += 1

	assert(state.finished, "playback_finished should fire once the race actually completes")
	print("racetrack_playback_check: full playback completed with no runtime errors after %d real frames" % frame_count)
	get_tree().quit()
