extends Node

## Dev tool, not part of the game: racetrack_playback_check.gd only ever
## exercises the default theme ("neon_downs") and default camera mode
## ("broadcast") for a full race — this drives every TrackThemes.THEME_IDS x
## RaceTrack3D.CAMERA_MODE_ORDER combination (including the overhead/jockey
## camera math and each theme's _apply_theme wiring) through a few seconds of
## real playback, then separately exercises the instant-replay path
## end-to-end. Must run as a real scene (not via --script) for the
## autoloads:
##   godot --headless --path . res://scenes/tools/theme_camera_check.tscn

const TIME_SCALE: float = 20.0
const FRAMES_PER_COMBO: int = 90

func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	Bankroll.autosave_enabled = false

	for theme_id in TrackThemes.THEME_IDS:
		for camera_mode in RaceTrack3D.CAMERA_MODE_ORDER:
			Settings.track_theme_id = theme_id
			Settings.camera_mode = camera_mode

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

			for i in range(FRAMES_PER_COMBO):
				await get_tree().process_frame

			assert(race_track._camera_mode == camera_mode, "camera mode should read from Settings at build time")
			print("theme_camera_check: theme=%s camera=%s ran %d frames with no runtime errors" % [theme_id, camera_mode, FRAMES_PER_COMBO])
			race_track.queue_free()
			await get_tree().process_frame

	# Instant replay: drive one race all the way to playback_finished, then
	# exercise play_replay() itself (the part no other dev tool touches).
	Settings.track_theme_id = TrackThemes.DEFAULT_THEME_ID
	Settings.camera_mode = "broadcast"
	var roster2: Array[Horse] = HorseRoster.generate()
	roster2.shuffle()
	var field2: Array[Horse] = roster2.slice(0, 8)
	HorseRoster.assign_race_colors(field2)
	var tiers2: Array[Dictionary] = OddsTable.assign_to_field(field2.size())
	var result2: RaceResult = RaceSim.simulate(field2, tiers2)

	var race_track2 := RaceTrack3D.new()
	add_child(race_track2)
	race_track2.setup(field2, result2)
	race_track2.play()

	var state := {"finished": false}
	race_track2.playback_finished.connect(func(): state.finished = true)
	var max_frames: int = int((result2.duration / TIME_SCALE) * 60.0 * 5.0) + 300
	var frame_count: int = 0
	while not state.finished and frame_count < max_frames:
		await get_tree().process_frame
		frame_count += 1
	assert(state.finished, "playback_finished should fire before exercising play_replay()")

	var replay_state := {"finished": false}
	race_track2.replay_finished.connect(func(): replay_state.finished = true)
	race_track2.play_replay()
	var replay_frames: int = 0
	var max_replay_frames: int = 2000
	while not replay_state.finished and replay_frames < max_replay_frames:
		await get_tree().process_frame
		replay_frames += 1
	assert(replay_state.finished, "replay_finished should fire once play_replay() completes")
	print("theme_camera_check: play_replay() completed with no runtime errors after %d real frames" % replay_frames)

	print("theme_camera_check: all checks passed")
	get_tree().quit()
