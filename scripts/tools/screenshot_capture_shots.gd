extends Node

## One-off capture of the automatic broadcast camera CUTS (see RaceTrack3D's
## ShotState: GATE/CHASE/TURN_CUTAWAY/STRETCH) — takes several screenshots
## across one real race, at wall-clock times chosen (from the race's actual
## RaceSim.simulate() duration) to land inside the TURN_CUTAWAY and STRETCH
## windows, so each capture actually shows a different shot rather than N
## copies of the same chase-cam view at different points along its rail.
## Must run with the REAL (non-headless) binary:
##   godotsteam.441.editor.windows64.exe --path . res://scenes/tools/screenshot_capture_shots.tscn

const OUT_DIR: String = "C:/Users/AJ/AppData/Local/Temp/claude/C--Users-AJ/d28ea6ec-b18d-4c6c-a5f5-874a5dec842d/scratchpad/"

func _ready() -> void:
	await get_tree().process_frame

	var roster: Array[Horse] = HorseRoster.generate()
	roster.shuffle()
	var field: Array[Horse] = roster.slice(0, 8)
	HorseRoster.assign_race_colors(field)
	var tiers: Array[Dictionary] = OddsTable.assign_to_field(field.size())
	var result: RaceResult = RaceSim.simulate(field, tiers)

	var race_track := RaceTrack3D.new()
	get_tree().root.add_child(race_track)
	race_track.setup(field, result)
	race_track.play_with_post_time() # not awaited — runs as a background coroutine, same pattern as racetrack_playback_check.gd

	# Fractions chosen to land mid-TURN_CUTAWAY (~0.5) and mid-STRETCH (~0.92)
	# windows, plus one plain mid-race CHASE shot for contrast.
	var targets: Array[Dictionary] = [
		{"label": "chase", "fraction": 0.25},
		{"label": "turn_cutaway", "fraction": 0.50},
		{"label": "stretch", "fraction": 0.92},
	]
	var next_target: int = 0
	# Wall-clock safety cap, NOT a frame count — the real (non-headless,
	# uncapped) binary can burn through thousands of frames per real second,
	# so a frame-count cap hit the limit before the race even reached its
	# later targets on the first attempt at this. Same lesson already learned
	# building screenshot_capture_podium.gd.
	const MAX_SAFETY_MSEC: int = 100000 # ~100s real time — well past ceremony+race
	var start_msec: int = Time.get_ticks_msec()

	while next_target < targets.size():
		await get_tree().process_frame
		if Time.get_ticks_msec() - start_msec > MAX_SAFETY_MSEC:
			print("screenshot_capture_shots: safety cap hit, stopping with %d/%d targets captured" % [next_target, targets.size()])
			break
		if not race_track.playing:
			continue # still mid pre-race ceremony (odds board/countdown), or the race already finished before we caught this target
		var target_time: float = targets[next_target]["fraction"] * result.duration
		if race_track.playback_time >= target_time:
			var image: Image = get_viewport().get_texture().get_image()
			var path: String = "%sscreenshot_shot_%s.png" % [OUT_DIR, targets[next_target]["label"]]
			var err: Error = image.save_png(path)
			print("screenshot_capture_shots: [%s] save_png -> %s (err=%s, playback_time=%.1f/%.1f)" % [
				targets[next_target]["label"], path, err, race_track.playback_time, result.duration,
			])
			next_target += 1

	# This tool deliberately quits mid-race (unlike racetrack_playback_check,
	# which always waits for a natural finish) — cutting audio focus first
	# stops the still-actively-playing race-ambience/crowd-swell
	# AudioStreamPlayers cleanly instead of leaving them mid-playback at the
	# moment the engine tears down.
	race_track.set_audio_focus(false)
	get_tree().quit()
